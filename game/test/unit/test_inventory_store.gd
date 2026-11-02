# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## The crew inventory: the local store, and the remote store against the fake
## scoreboard with the response shapes of server/API.md.

const PATH := "user://test_inventory.json"
const QUEUE := "user://test_inventory_queue.json"
const M := "cookie_machine"
const ME := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const MATE := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for p in [PATH, QUEUE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _row(item: String, state: String, by: String, place: String = "depot:gnu_locker") -> Dictionary:
	return {
		"item_id": item, "state": state, "found_by": by, "found_at": "2027-10-29T17:40:12Z",
		"installed_by": by if state == "installed" else null, "installed_at": "2027-10-29T17:52:03Z" if state == "installed" else null,
		"place": place,
	}


func _remote(fake: FakeScoreboard, local: LocalInventoryStore = null) -> RemoteInventoryStore:
	var l := local if local != null else LocalInventoryStore.new("")
	var store := RemoteInventoryStore.new(FakeScoreboard.BASE, l, fake.transport(), QUEUE)
	store.clock_override = 0
	return store


# --- Local --------------------------------------------------------------------------


func test_local_find_records_who_and_where() -> void:
	var store := LocalInventoryStore.new(PATH)
	store.now_override = "2027-10-29T10:00:00Z"
	assert_bool(store.mark(M, "spanner", "found", "workshop:penguin", ME)).is_true()
	var e := store.entry(M, "spanner")
	assert_str(str(e["state"])).is_equal("found")
	assert_str(str(e["found_by"])).is_equal(ME)
	assert_str(str(e["place"])).is_equal("workshop:penguin")
	assert_dict(store.states(M)).is_equal({"spanner": "found"})


func test_local_is_idempotent_and_only_moves_forward() -> void:
	var store := LocalInventoryStore.new(PATH)
	assert_bool(store.mark(M, "cutter_die", "found", "workshop:bench", ME)).is_true()
	assert_bool(store.mark(M, "cutter_die", "found", "workshop:bench", ME)).is_false()
	assert_bool(store.mark(M, "cutter_die", "installed", "shop:cutter", ME)).is_true()
	assert_bool(store.mark(M, "cutter_die", "found", "elsewhere", ME)).is_false()
	assert_str(str(store.entry(M, "cutter_die")["state"])).is_equal("installed")
	assert_int(store.items(M).size()).is_equal(1)
	assert_bool(store.mark(M, "x", "lost", "", ME)).is_false()


func test_local_round_trip_and_reset() -> void:
	var store := LocalInventoryStore.new(PATH)
	store.mark(M, "spanner", "found", "workshop:penguin", ME)
	store.mark("oven", "brass_key", "installed", "depot:locker", ME)
	var again := LocalInventoryStore.new(PATH)
	assert_dict(again.states(M)).is_equal({"spanner": "found"})
	assert_dict(again.states("oven")).is_equal({"brass_key": "installed"})
	again.reset_local()
	assert_dict(LocalInventoryStore.new(PATH).states(M)).is_empty()


# --- Remote -------------------------------------------------------------------------


func test_remote_posts_the_contract_body_and_merges_the_row() -> void:
	var fake := FakeScoreboard.new()
	fake.answer("POST", "/crews/cookie_machine/inventory/spanner", 200, _row("spanner", "found", ME, "workshop:penguin"))
	var store := _remote(fake)
	store.mark(M, "spanner", "found", "workshop:penguin", ME)
	assert_array(fake.posts()).contains_exactly(["POST /crews/cookie_machine/inventory/spanner"])
	assert_dict(fake.last_post_body()).is_equal({"device_id": ME, "state": "found", "place": "workshop:penguin"})
	assert_int(store.queue_size()).is_equal(0)
	assert_bool(store.is_online()).is_true()
	assert_str(str(store.entry(M, "spanner")["found_by"])).is_equal(ME)


func test_remote_never_sends_a_repeat_twice() -> void:
	var fake := FakeScoreboard.new()
	fake.answer("POST", "/crews/cookie_machine/inventory/spanner", 200, _row("spanner", "found", ME))
	var store := _remote(fake)
	store.mark(M, "spanner", "found", "", ME)
	store.mark(M, "spanner", "found", "", ME)
	assert_int(fake.posts().size()).is_equal(1)
	# While offline, the same write is queued once.
	fake.offline = true
	store.mark(M, "die_bent", "found", "depot:gnu_locker", ME)
	store.mark(M, "die_bent", "found", "depot:gnu_locker", ME)
	assert_int(store.queue_size()).is_equal(1)


func test_remote_drops_a_403_not_in_crew_but_keeps_it_on_this_phone() -> void:
	var fake := FakeScoreboard.new()
	fake.answer("POST", "/crews/cookie_machine/inventory/spanner", 403, {"error": {"code": "not_in_crew", "message": "Device is in crew 'oven'."}})
	var store := _remote(fake)
	store.mark(M, "spanner", "found", "", ME)
	assert_int(store.queue_size()).is_equal(0)
	assert_dict(store.states(M)).is_equal({"spanner": "found"})


func test_remote_queues_offline_backs_off_and_sends_later() -> void:
	var fake := FakeScoreboard.new()
	fake.offline = true
	var store := _remote(fake)
	store.mark(M, "spanner", "found", "", ME)
	assert_int(store.queue_size()).is_equal(1)
	assert_bool(store.is_online()).is_false()
	assert_dict(store.states(M)).is_equal({"spanner": "found"})
	# The queue survives a restart.
	var reloaded := _remote(fake, LocalInventoryStore.new(""))
	assert_int(reloaded.queue_size()).is_equal(1)
	fake.offline = false
	fake.answer("POST", "/crews/cookie_machine/inventory/spanner", 200, _row("spanner", "found", ME))
	store.tick(1000)  # still inside the 2 s backoff
	assert_int(store.queue_size()).is_equal(1)
	store.tick(2500)
	assert_int(store.queue_size()).is_equal(0)


func test_remote_gives_up_on_a_write_refused_five_times() -> void:
	var fake := FakeScoreboard.new()
	fake.answer("POST", "/crews/cookie_machine/inventory/spanner", 400, {"error": {"code": "bad_place", "message": "too long"}})
	var store := _remote(fake)
	store.mark(M, "spanner", "found", "", ME)
	for n in 5:
		store.flush()
	assert_int(store.queue_size()).is_equal(0)


func test_found_by_is_the_first_writer_from_the_server() -> void:
	var fake := FakeScoreboard.new()
	# A crewmate reported the die first; the server returns their row.
	fake.answer("POST", "/crews/cookie_machine/inventory/cutter_die", 200, _row("cutter_die", "found", MATE))
	var store := _remote(fake)
	store.mark(M, "cutter_die", "found", "workshop:bench", ME)
	assert_str(str(store.entry(M, "cutter_die")["found_by"])).is_equal(MATE)


func test_refresh_shares_a_crewmates_finds() -> void:
	var fake := FakeScoreboard.new()
	fake.answer("GET", "/crews/cookie_machine/inventory", 200, {"items": [_row("die_bent", "found", MATE), _row("spanner", "installed", MATE, "shop:cutter")]})
	var store := _remote(fake)
	var seen: Array[String] = []
	store.changed.connect(func(machine: String) -> void: seen.append(machine))
	store.set_watching([M] as Array[String])
	assert_dict(store.states(M)).is_equal({"die_bent": "found", "spanner": "installed"})
	assert_str(str(store.entry(M, "die_bent")["found_by"])).is_equal(MATE)
	assert_array(seen).contains([M])
	# Polls again only after the interval.
	var gets := fake.count("GET", "/crews/cookie_machine/inventory")
	store.tick(1000)
	assert_int(fake.count("GET", "/crews/cookie_machine/inventory")).is_equal(gets)
	store.tick(RemoteInventoryStore.POLL_INTERVAL_MSEC + 1)
	assert_int(fake.count("GET", "/crews/cookie_machine/inventory")).is_equal(gets + 1)


func test_backfill_sends_this_phones_offline_finds_once() -> void:
	var local := LocalInventoryStore.new("")
	local.mark(M, "spanner", "found", "workshop:penguin", ME)
	local.mark(M, "die_bent", "found", "depot:gnu_locker", MATE)  # came from the crew, not mine
	var fake := FakeScoreboard.new()
	var store := _remote(fake, local)
	store.backfill(M, ME)
	assert_array(fake.posts()).contains_exactly(["POST /crews/cookie_machine/inventory/spanner"])


func test_retired_store_sends_nothing() -> void:
	var fake := FakeScoreboard.new()
	var store := _remote(fake)
	store.retire()
	store.mark(M, "spanner", "found", "", ME)
	assert_int(fake.requests.size()).is_equal(0)
