# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## RemoteProgressStore against a fake transport: no network, no real clock.

const LOCAL := "user://test_remote_local.json"
const QUEUE := "user://test_remote_queue.json"
const COOKIE := "cookie_machine"

var fake: FakeScoreboard


func before_test() -> void:
	_cleanup()
	fake = FakeScoreboard.new()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for path in [LOCAL, QUEUE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _store() -> RemoteProgressStore:
	var store := RemoteProgressStore.new(FakeScoreboard.BASE, LocalProgressStore.new(LOCAL), fake.transport(), QUEUE)
	store.clock_override = 1000
	return store


func _none() -> Array[String]:
	return []


func _ops(store: RemoteProgressStore) -> Array:
	var out: Array = []
	for item in store.queue:
		out.append(item["op"])
	return out


# --- Queue ---------------------------------------------------------------------------


func test_queue_survives_a_restart() -> void:
	fake.offline = true
	var store := _store()
	store.set_display_name("dev1", "Ada")
	store.join_crew("dev1", COOKIE)
	store.record_part_solved(COOKIE, "logic", "dev1", true)
	assert_array(_ops(store)).contains_exactly(["set_display_name", "join_crew", "record_part_solved"])
	var again := _store()
	assert_array(_ops(again)).contains_exactly(["set_display_name", "join_crew", "record_part_solved"])
	assert_str(again.queue[2]["part"]).is_equal("logic")
	assert_bool(again.queue[2]["credited"]).is_true()
	assert_int(again.queue_size()).is_equal(3)


func test_flush_sends_in_order_with_the_api_bodies() -> void:
	fake.offline = true
	var store := _store()
	store.set_display_name("dev1", "Ada")
	store.join_crew("dev1", COOKIE)
	store.record_part_solved(COOKIE, "logic", "dev1", true)
	assert_bool(store.is_online()).is_false()
	fake.offline = false
	fake.requests.clear()
	assert_int(store.flush()).is_equal(0)
	assert_array(fake.posts()).contains_exactly(
		["POST /devices", "POST /devices", "POST /crews/cookie_machine/parts/logic/solve"]
	)
	assert_dict(fake.requests[0]["body"]).is_equal({"device_id": "dev1", "display_name": "Ada"})
	assert_dict(fake.requests[1]["body"]).is_equal({"device_id": "dev1", "crew": COOKIE})
	assert_dict(fake.requests[2]["body"]).is_equal({"device_id": "dev1"})
	assert_bool(store.is_online()).is_true()
	# The emptied queue is what a restart sees too.
	assert_int(_store().queue_size()).is_equal(0)


func test_a_write_goes_out_at_once_when_the_scoreboard_is_up() -> void:
	var store := _store()
	store.record_part_solved(COOKIE, "logic", "dev1", true)
	assert_int(store.queue_size()).is_equal(0)
	assert_int(fake.count("POST", "/crews/")).is_equal(1)


func test_not_in_crew_drops_the_solve_but_keeps_it_locally() -> void:
	fake.answer("POST", "/crews/cookie_machine/parts/logic/solve", 403, FakeScoreboard.error("not_in_crew"))
	var store := _store()
	store.record_part_solved(COOKIE, "logic", "dev1", true)
	store.record_part_solved(COOKIE, "wiring", "dev1", true)
	assert_int(store.queue_size()).is_equal(0)
	assert_bool(store.is_online()).is_true()
	# The wiring solve behind the refused one still went out.
	assert_int(fake.count("POST", "/crews/cookie_machine/parts/wiring/solve")).is_equal(1)
	assert_int(store.get_crew_progress(COOKIE)["logic"]).is_equal(1)
	assert_int(fake.count("POST", "/crews/cookie_machine/parts/logic/solve")).is_equal(1)


func test_other_errors_keep_the_write_for_a_retry() -> void:
	for status in [0, 500, 503, 429]:
		fake = FakeScoreboard.new()
		_cleanup()
		fake.answer("POST", "/crews/cookie_machine/parts/logic/solve", status, {}, 7)
		var store := _store()
		store.record_part_solved(COOKIE, "logic", "dev1", true)
		assert_int(store.queue_size()).override_failure_message("status %d" % status).is_equal(1)
		# It is still there after a restart, and goes out once the server is fine.
		fake.answer("POST", "/crews/cookie_machine/parts/logic/solve", 200, {"newly_solved": true})
		var again := _store()
		assert_int(again.flush()).is_equal(0)


func test_a_write_the_server_keeps_refusing_is_dropped_after_five_tries() -> void:
	fake.answer("POST", "/devices", 422, FakeScoreboard.error("validation_error"))
	var store := _store()
	store.set_display_name("dev1", "Ada")
	for i in 3:
		assert_int(store.flush()).is_equal(1)
	assert_int(store.flush()).is_equal(0)


func test_backoff_doubles_and_resets() -> void:
	fake.offline = true
	var store := _store()
	store.join_crew("dev1", COOKIE)  # fails at t=1000, next try at 3000
	assert_int(fake.requests.size()).is_equal(1)
	store.tick(2999)
	assert_int(fake.requests.size()).is_equal(1)
	store.tick(3000)  # fails again, next try 4000 later
	assert_int(fake.requests.size()).is_equal(2)
	store.tick(6999)
	assert_int(fake.requests.size()).is_equal(2)
	fake.offline = false
	store.tick(7000)
	assert_int(fake.requests.size()).is_equal(3)
	assert_int(store.queue_size()).is_equal(0)
	assert_bool(store.is_online()).is_true()


func test_retry_after_pushes_the_next_try_out() -> void:
	fake.answer_once("POST", "/devices", 429, {}, 30)
	var store := _store()
	store.join_crew("dev1", COOKIE)
	store.tick(20000)
	assert_int(fake.requests.size()).is_equal(1)
	store.tick(31000)
	assert_int(fake.requests.size()).is_equal(2)
	assert_int(store.queue_size()).is_equal(0)


func test_a_second_flush_while_one_is_in_flight_sends_nothing_new() -> void:
	fake.hold = true
	var store := _store()
	store.join_crew("dev1", COOKIE)
	store.record_part_solved(COOKIE, "logic", "dev1", true)
	store.flush()
	store.flush()
	assert_int(fake.requests.size()).is_equal(1)
	fake.release()
	assert_int(fake.requests.size()).is_equal(2)
	fake.release()
	assert_int(store.queue_size()).is_equal(0)


func test_unregistered_device_is_registered_then_the_solve_retried() -> void:
	fake.answer_once("POST", "/crews/cookie_machine/parts/logic/solve", 404, FakeScoreboard.error("device_not_registered"))
	var store := _store()
	store.set_display_name("dev1", "Ada")  # goes out, then the queue is empty
	fake.requests.clear()
	store.record_part_solved(COOKIE, "logic", "dev1", true)
	assert_array(fake.posts()).contains_exactly(
		["POST /crews/cookie_machine/parts/logic/solve", "POST /devices", "POST /crews/cookie_machine/parts/logic/solve"]
	)
	assert_dict(fake.requests[1]["body"]).contains_keys(["device_id", "display_name"])
	assert_int(store.queue_size()).is_equal(0)


func test_set_identity_registers_a_device_once() -> void:
	var store := _store()
	store.set_identity("dev1", COOKIE, "Ada")
	assert_dict(fake.requests[0]["body"]).is_equal({"device_id": "dev1", "display_name": "Ada", "crew": COOKIE})
	var again := _store()
	again.set_identity("dev1", COOKIE, "Ada")
	assert_int(fake.requests.size()).is_equal(1)
	# A device with nothing to say yet is not registered.
	var blank := RemoteProgressStore.new(FakeScoreboard.BASE, LocalProgressStore.new(LOCAL), fake.transport(), QUEUE)
	blank.set_identity("dev2", "", "")
	assert_int(fake.requests.size()).is_equal(1)


func test_reset_forgets_unsent_writes_and_the_file() -> void:
	fake.offline = true
	var store := _store()
	store.join_crew("dev1", COOKIE)
	store.reset_local()
	assert_int(store.queue_size()).is_equal(0)
	assert_int(_store().queue_size()).is_equal(0)
	assert_int(store.get_crew_progress(COOKIE)["logic"]).is_equal(0)


func test_without_a_transport_it_only_queues_and_writes_no_file() -> void:
	var store := RemoteProgressStore.new("https://example.invalid", LocalProgressStore.new(LOCAL))
	store.join_crew("dev1", COOKIE)
	assert_int(store.flush()).is_equal(1)
	assert_bool(store.is_online()).is_false()


# --- Cache ---------------------------------------------------------------------------


func test_refresh_fills_the_cache_and_emits_progress_changed() -> void:
	var store := _store()
	store.join_crew("dev1", COOKIE)
	var seen: Array = []
	store.progress_changed.connect(func(machine: String) -> void: seen.append(machine))
	var contributors := [
		{"name": "anonymous", "machine": COOKIE, "via": "solve", "first_merged_at": "2027-10-29T17:40:00Z"},
		{"name": "Ada", "machine": COOKIE, "via": "solve", "first_merged_at": "2027-10-29T17:31:40Z"},
	]
	fake.answer("GET", "/crews/cookie_machine", 200, FakeScoreboard.crew(COOKIE, {"logic": 3, "wiring": 1}, false, contributors))
	store.refresh()
	assert_array(seen).contains_exactly([COOKIE])
	var progress := store.get_crew_progress(COOKIE)
	assert_int(progress["logic"]).is_equal(3)
	assert_int(progress["wiring"]).is_equal(1)
	assert_int(progress["rhythm"]).is_equal(0)
	# Served newest first; the store hands back first-solve order, "Anonymous" capitalised.
	assert_array(store.get_contributors(COOKIE)).contains_exactly(["Ada", "Anonymous"])
	# The same answer again changes nothing, so nothing is emitted.
	store.refresh()
	assert_array(seen).contains_exactly([COOKIE])
	assert_bool(store.is_online()).is_true()


func test_local_solves_still_show_when_the_server_is_behind() -> void:
	var store := _store()
	store.join_crew("dev1", COOKIE)
	fake.offline = true
	store.record_part_solved(COOKIE, "logic", "dev1", true)
	fake.offline = false
	fake.answer("GET", "/crews/cookie_machine", 200, FakeScoreboard.crew(COOKIE, {"wiring": 2}))
	store.refresh()
	var progress := store.get_crew_progress(COOKIE)
	assert_int(progress["logic"]).is_equal(1)
	assert_int(progress["wiring"]).is_equal(2)


func test_offline_getters_fall_back_to_local() -> void:
	fake.offline = true
	var store := _store()
	store.set_display_name("dev1", "Ada")
	store.join_crew("dev1", COOKIE)
	store.record_part_solved(COOKIE, "logic", "dev1", true)
	store.refresh()
	assert_bool(store.is_online()).is_false()
	assert_int(store.get_crew_progress(COOKIE)["logic"]).is_equal(1)
	assert_array(store.get_contributors(COOKIE)).contains_exactly(["Ada"])
	assert_bool(store.server_runs(COOKIE)).is_false()


func test_a_cached_answer_survives_going_offline() -> void:
	var store := _store()
	store.join_crew("dev1", COOKIE)
	fake.answer("GET", "/crews/cookie_machine", 200, FakeScoreboard.crew(COOKIE, {"logic": 2}))
	store.refresh()
	fake.offline = true
	store.refresh()
	assert_bool(store.is_online()).is_false()
	assert_int(store.get_crew_progress(COOKIE)["logic"]).is_equal(2)


func test_the_solve_answer_updates_the_cache() -> void:
	var crew := FakeScoreboard.crew(COOKIE, {"logic": 1, "wiring": 4})
	fake.answer("POST", "/crews/cookie_machine/parts/logic/solve", 200, {"newly_solved": true, "crew": crew})
	var store := _store()
	store.record_part_solved(COOKIE, "logic", "dev1", true)
	assert_int(store.get_crew_progress(COOKIE)["wiring"]).is_equal(4)


func test_machine_runs_is_remembered_across_restarts() -> void:
	var store := _store()
	store.join_crew("dev1", COOKIE)
	var all := {"logic": 1, "wiring": 1, "sequence": 1, "word": 1, "rhythm": 1, "helper": 1}
	fake.answer("GET", "/crews/cookie_machine", 200, FakeScoreboard.crew(COOKIE, all, true))
	assert_bool(store.server_runs(COOKIE)).is_false()
	store.refresh()
	assert_bool(store.server_runs(COOKIE)).is_true()
	assert_bool(store.server_runs("oven")).is_false()
	assert_bool(_store().server_runs(COOKIE)).is_true()


func test_all_contributors_fill_every_crew() -> void:
	fake.answer(
		"GET",
		"/contributors",
		200,
		{
			"total": 3,
			"contributors":
			[
				{"name": "Mina", "machine": COOKIE, "via": "mentor", "first_merged_at": "2027-10-29T18:05:00Z"},
				{"name": "anonymous", "machine": "oven", "via": "solve", "first_merged_at": "2027-10-29T17:40:12Z"},
				{"name": "Ada", "machine": COOKIE, "via": "solve", "first_merged_at": "2027-10-29T17:31:40Z"},
			],
		}
	)
	var store := _store()
	store.refresh_contributors()
	assert_array(store.get_contributors(COOKIE)).contains_exactly(["Ada", "Mina"])
	assert_array(store.get_contributors("oven")).contains_exactly(["Anonymous"])
	assert_str(store.get_contributor_entries(COOKIE)[1]["via"]).is_equal("mentor")
	assert_array(store.get_contributors("fortune_machine")).is_empty()


# --- Polling ---------------------------------------------------------------------------


func test_polling_runs_only_while_something_is_watched() -> void:
	var store := _store()
	store.join_crew("dev1", COOKIE)
	fake.requests.clear()
	store.tick(5000)
	store.tick(50000)
	assert_int(fake.requests.size()).is_equal(0)
	var machines: Array[String] = [COOKIE]
	store.set_watching(machines, false)  # looks at once
	assert_int(fake.count("GET", "/crews/cookie_machine")).is_equal(1)
	assert_int(fake.count("GET", "/hints")).is_equal(1)
	store.tick(60000)
	assert_int(fake.count("GET", "/crews/cookie_machine")).is_equal(2)  # 10 s have not passed since the look
	store.set_watching(_none(), false)
	store.tick(200000)
	assert_int(fake.count("GET", "/crews/cookie_machine")).is_equal(2)


func test_polling_waits_ten_seconds_between_looks() -> void:
	var store := _store()
	store.join_crew("dev1", COOKIE)
	var machines: Array[String] = [COOKIE]
	store.set_watching(machines, false)  # clock 1000: looks, next at 11000
	fake.requests.clear()
	store.tick(10999)
	assert_int(fake.requests.size()).is_equal(0)
	store.tick(11000)
	assert_int(fake.count("GET", "/crews/cookie_machine")).is_equal(1)
	store.tick(15000)
	assert_int(fake.count("GET", "/crews/cookie_machine")).is_equal(1)


# --- Hints -----------------------------------------------------------------------------


func test_first_look_delivers_only_the_newest_hint_then_pages_by_id() -> void:
	var store := _store()
	store.join_crew("dev1", COOKIE)
	var got: Array = []
	store.hint_arrived.connect(func(hint: Dictionary) -> void: got.append(int(hint["id"])))
	fake.answer_once("GET", "/hints", 200, {"crew": COOKIE, "hints": [FakeScoreboard.hint(3, COOKIE), FakeScoreboard.hint(5, COOKIE)]})
	store.set_watching(_none(), true)
	assert_array(got).contains_exactly([5])
	assert_str(fake.requests[fake.requests.size() - 1]["path"]).is_equal("/hints?crew=cookie_machine")
	fake.answer_once("GET", "/hints", 200, {"crew": COOKIE, "hints": [FakeScoreboard.hint(6, COOKIE, "ask_a_crewmate")]})
	store.tick(11000)
	assert_array(got).contains_exactly([5, 6])
	assert_str(fake.requests[fake.requests.size() - 1]["path"]).is_equal("/hints?crew=cookie_machine&after_id=5")
	# After a restart the stored id is used, so old hints do not come back.
	var again := _store()
	again.join_crew("dev1", COOKIE)
	again.set_watching(_none(), true)
	assert_str(fake.requests[fake.requests.size() - 1]["path"]).is_equal("/hints?crew=cookie_machine&after_id=6")


func test_a_full_page_of_hints_is_followed_by_the_next_page() -> void:
	var store := _store()
	store.join_crew("dev1", COOKIE)
	var got: Array = []
	store.hint_arrived.connect(func(hint: Dictionary) -> void: got.append(int(hint["id"])))
	fake.answer_once("GET", "/hints", 200, {"crew": COOKIE, "hints": []})
	store.set_watching(_none(), true)
	var page: Array = []
	for id in range(1, 51):
		page.append(FakeScoreboard.hint(id, COOKIE))
	fake.answer_once("GET", "/hints", 200, {"crew": COOKIE, "hints": page})
	fake.answer_once("GET", "/hints", 200, {"crew": COOKIE, "hints": [FakeScoreboard.hint(51, COOKIE)]})
	store.tick(11000)
	assert_int(got.size()).is_equal(51)
	assert_str(fake.requests[fake.requests.size() - 1]["path"]).is_equal("/hints?crew=cookie_machine&after_id=50")


# --- Mentors -----------------------------------------------------------------------------


func test_send_nudge_posts_and_reports() -> void:
	fake.answer("POST", "/hints", 200, {"created": true, "hint": FakeScoreboard.hint(7, "oven")})
	var store := _store()
	store.join_crew("dev1", "cookie_machine")
	var results: Array = []
	store.send_nudge("oven", "reread_the_clue", func(ok: bool, message: String) -> void: results.append([ok, message]))
	assert_dict(fake.last_post_body()).is_equal(
		{"device_id": "dev1", "to_crew": "oven", "nudge_id": "reread_the_clue"}
	)
	assert_array(results).contains_exactly([[true, "Nudge sent."]])


func test_send_nudge_explains_a_refusal() -> void:
	fake.answer("POST", "/hints", 403, FakeScoreboard.error("not_a_maintainer"))
	var store := _store()
	var results: Array = []
	store.send_nudge("oven", "reread_the_clue", func(ok: bool, message: String) -> void: results.append([ok, message]))
	assert_bool(results[0][0]).is_false()
	assert_str(results[0][1]).contains("machine has to run")
	fake.offline = true
	store.send_nudge("oven", "reread_the_clue", func(ok: bool, message: String) -> void: results.append([ok, message]))
	assert_str(results[1][1]).contains("not reachable")


func test_nudge_ids_come_from_the_server() -> void:
	fake.answer("GET", "/hints/nudges", 200, {"nudges": ["reread_the_clue", "take_a_short_break"]})
	var store := _store()
	var results: Array = []
	store.fetch_nudge_ids(func(ok: bool, ids: Array[String]) -> void: results.append([ok, ids]))
	assert_bool(results[0][0]).is_true()
	assert_array(results[0][1]).contains_exactly(["reread_the_clue", "take_a_short_break"])
	fake.offline = true
	store.fetch_nudge_ids(func(ok: bool, ids: Array[String]) -> void: results.append([ok, ids]))
	assert_bool(results[1][0]).is_false()
