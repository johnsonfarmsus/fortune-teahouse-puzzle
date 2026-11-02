# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## FinaleClient against a fake transport: no network, no real clock.

const FinaleFixtures := preload("res://test/fixtures/finale_fixtures.gd")
const DEVICE := "dev1"

var fake: FakeScoreboard
var state: FinaleState
var client: FinaleClient


func before_test() -> void:
	fake = FakeScoreboard.new()
	state = FinaleState.new("")
	client = FinaleClient.new(FakeScoreboard.BASE, state, fake.transport())
	client.clock_override = 1000
	client.set_identity(DEVICE, "oven", "Ada")


func test_posts_a_setting_with_the_device_id() -> void:
	fake.answer("POST", "/finale/handoffs/cookie_to_oven/settings", 200, {"newly_recorded": true})
	state.add_setting("cookie_to_oven", 1)
	assert_array(fake.posts()).contains_exactly(["POST /finale/handoffs/cookie_to_oven/settings"])
	assert_int(int(fake.last_post_body()["setting_index"])).is_equal(1)
	assert_str(str(fake.last_post_body()["device_id"])).is_equal(DEVICE)
	assert_int(state.queue.size()).is_equal(0)


func test_posts_a_note_code_in_its_normalised_form() -> void:
	fake.answer("POST", "/finale/notes", 200, {"valid": true, "already_found": false, "notes": {"found": 1, "total": 6, "needed": 4, "complete": false}})
	state.set_cache(FinaleFixtures.finale(true))
	state.add_gnu_note("note_1", "KETTLE27")
	assert_str(str(fake.last_post_body()["code"])).is_equal("KETTLE27")
	assert_int(int(state.cache["notes"]["found"])).is_equal(1)
	assert_int(state.queue.size()).is_equal(0)


func test_offline_writes_wait_and_retry_after_a_backoff() -> void:
	fake.offline = true
	state.add_setting("cookie_to_oven", 0)
	assert_int(state.queue.size()).is_equal(1)
	assert_bool(client.is_online()).is_false()
	fake.offline = false
	client.tick(1500)  # inside the 2 s backoff: nothing is sent
	assert_int(fake.count("POST", "/finale")).is_equal(1)
	client.tick(3500)
	assert_int(fake.count("POST", "/finale")).is_equal(2)
	assert_int(state.queue.size()).is_equal(0)
	assert_bool(client.is_online()).is_true()


func test_403_finale_closed_keeps_the_write_until_a_poll_shows_it_open() -> void:
	fake.answer("POST", "/finale/notes", 403, FakeScoreboard.error("finale_closed"))
	fake.answer("GET", "/finale", 200, FinaleFixtures.finale(false))
	state.add_gnu_note("note_4", "CROSSWIND63")
	assert_int(fake.count("POST", "/finale/notes")).is_equal(1)
	assert_int(state.queue.size()).is_equal(1)
	assert_bool(bool(state.queue[0]["held"])).is_true()
	client.set_watching(true)  # a poll still says closed: no resend
	assert_int(fake.count("POST", "/finale/notes")).is_equal(1)
	fake.answer("POST", "/finale/notes", 200, {"valid": true, "already_found": false, "notes": {"found": 1, "total": 6, "needed": 4, "complete": false}})
	fake.answer("GET", "/finale", 200, FinaleFixtures.finale(true))
	client.tick(1000 + FinaleClient.POLL_INTERVAL_MSEC)
	assert_int(fake.count("POST", "/finale/notes")).is_equal(2)
	assert_int(state.queue.size()).is_equal(0)


func test_409_handoff_waiting_keeps_the_write_until_the_handoff_is_available() -> void:
	fake.answer("POST", "/finale/handoffs/cookie_to_oven/settings", 409, FakeScoreboard.error("handoff_waiting"))
	var waiting := {"cookie_to_oven": FinaleFixtures.handoff("cookie_to_oven", "waiting", [], false)}
	fake.answer("GET", "/finale", 200, FinaleFixtures.finale(true, waiting))
	state.add_setting("cookie_to_oven", 2)
	assert_bool(bool(state.queue[0]["held"])).is_true()
	client.refresh()
	assert_int(fake.count("POST", "/finale/handoffs")).is_equal(1)  # still waiting
	fake.answer("POST", "/finale/handoffs/cookie_to_oven/settings", 200, {"newly_recorded": true, "handoff": FinaleFixtures.handoff("cookie_to_oven", "in_progress", [2], true)})
	fake.answer("GET", "/finale", 200, FinaleFixtures.finale(true))
	client.refresh()
	assert_int(fake.count("POST", "/finale/handoffs")).is_equal(2)
	assert_int(state.queue.size()).is_equal(0)
	assert_int(int(state.cache["handoffs"][0]["settings_solved"])).is_equal(1)


func test_a_held_write_does_not_block_the_ones_behind_it() -> void:
	fake.answer("POST", "/finale/handoffs/oven_to_packaging/settings", 409, FakeScoreboard.error("handoff_waiting"))
	fake.answer("POST", "/finale/handoffs/cookie_to_oven/settings", 200, {"newly_recorded": true})
	state.add_setting("oven_to_packaging", 0)
	state.add_setting("cookie_to_oven", 0)
	assert_int(state.queue.size()).is_equal(1)
	assert_str(str(state.queue[0]["handoff_id"])).is_equal("oven_to_packaging")


func test_404_registers_the_device_first_then_resends() -> void:
	fake.answer_once("POST", "/finale/handoffs/cookie_to_oven/settings", 404, FakeScoreboard.error("device_not_registered"))
	fake.answer("POST", "/finale/handoffs/cookie_to_oven/settings", 200, {"newly_recorded": true})
	fake.answer("POST", "/devices", 200, {"created": true})
	state.add_setting("cookie_to_oven", 0)
	assert_array(fake.posts()).contains_exactly(
		[
			"POST /finale/handoffs/cookie_to_oven/settings",
			"POST /devices",
			"POST /finale/handoffs/cookie_to_oven/settings",
		]
	)
	var registration: Dictionary = fake.requests[1]["body"]
	assert_str(str(registration["device_id"])).is_equal(DEVICE)
	assert_str(str(registration["crew"])).is_equal("oven")
	assert_str(str(registration["display_name"])).is_equal("Ada")
	assert_int(state.queue.size()).is_equal(0)


func test_a_write_the_server_keeps_refusing_is_dropped_after_five_tries() -> void:
	fake.answer("POST", "/finale/handoffs/cookie_to_oven/settings", 400, FakeScoreboard.error("bad_setting_index"))
	state.add_setting("cookie_to_oven", 0)
	var now := 1000
	for i in 10:
		now += 70000
		client.tick(now)
	assert_int(state.queue.size()).is_equal(0)
	assert_int(fake.count("POST", "/finale/handoffs")).is_equal(5)


func test_polls_only_while_watched() -> void:
	fake.answer("GET", "/finale", 200, FinaleFixtures.finale(false))
	client.tick(1000)
	client.tick(100000)
	assert_int(fake.count("GET", "/finale")).is_equal(0)
	client.set_watching(true)  # one look when watching starts, at 100000
	assert_int(fake.count("GET", "/finale")).is_equal(1)
	client.tick(100000 + FinaleClient.POLL_INTERVAL_MSEC - 1)
	assert_int(fake.count("GET", "/finale")).is_equal(1)
	client.tick(100000 + FinaleClient.POLL_INTERVAL_MSEC)
	assert_int(fake.count("GET", "/finale")).is_equal(2)
	client.set_watching(false)
	client.tick(100000 + 10 * FinaleClient.POLL_INTERVAL_MSEC)
	assert_int(fake.count("GET", "/finale")).is_equal(2)
	assert_bool(client.finale().has("handoffs")).is_true()


func test_a_poll_fills_the_cache_and_signals_once_per_change() -> void:
	fake.answer("GET", "/finale", 200, FinaleFixtures.finale(true))
	var count := [0]
	client.finale_changed.connect(func() -> void: count[0] += 1)
	client.refresh()
	client.refresh()
	assert_int(count[0]).is_equal(1)
	assert_bool(bool(client.finale()["open"])).is_true()


func test_a_failed_poll_keeps_the_cached_answer() -> void:
	fake.answer_once("GET", "/finale", 200, FinaleFixtures.finale(true))
	client.refresh()
	fake.offline = true
	client.refresh()
	assert_bool(bool(client.finale()["open"])).is_true()
	assert_bool(client.is_online()).is_false()


func test_a_429_on_a_poll_pushes_the_next_poll_out() -> void:
	fake.answer("GET", "/finale", 429, FakeScoreboard.error("rate_limited"), 40)
	client.set_watching(true)
	client.tick(1000 + FinaleClient.POLL_INTERVAL_MSEC + 1)
	assert_int(fake.count("GET", "/finale")).is_equal(1)
	client.tick(1000 + 40000 + 1)
	assert_int(fake.count("GET", "/finale")).is_equal(2)


func test_start_code_results() -> void:
	var got: Array[String] = []
	fake.answer("POST", "/finale/start", 200, {"valid": false, "started": false, "started_at": null})
	client.submit_start("3141592654", func(r: String) -> void: got.append(r))
	fake.answer("POST", "/finale/start", 409, FakeScoreboard.error("line_not_ready"))
	client.submit_start("3141592653", func(r: String) -> void: got.append(r))
	fake.answer("POST", "/finale/start", 403, FakeScoreboard.error("finale_closed"))
	client.submit_start("3141592653", func(r: String) -> void: got.append(r))
	fake.answer("POST", "/finale/start", 200, {"valid": true, "started": true, "started_at": "2027-10-30T20:30:00Z"})
	client.submit_start("3.141 592 653", func(r: String) -> void: got.append(r))
	assert_array(got).contains_exactly([FinaleClient.START_WRONG, FinaleClient.START_NOT_READY, FinaleClient.START_CLOSED, FinaleClient.START_STARTED])
	assert_str(str(fake.last_post_body()["code"])).is_equal("3141592653")
	assert_bool(bool(client.finale()["started"])).is_true()
	fake.offline = true
	client.submit_start("3141592653", func(r: String) -> void: got.append(r))
	assert_str(got[4]).is_equal(FinaleClient.START_OFFLINE)


func test_start_is_never_queued() -> void:
	fake.offline = true
	client.submit_start("3141592653", func(_r: String) -> void: pass)
	assert_int(state.queue.size()).is_equal(0)


func test_a_retired_client_sends_nothing() -> void:
	client.retire()
	state.add_setting("cookie_to_oven", 0)
	client.set_watching(true)
	assert_int(fake.requests.size()).is_equal(0)


func test_a_second_start_tap_while_one_is_pending_is_ignored() -> void:
	fake.hold = true
	fake.answer("POST", "/finale/start", 200, {"valid": false, "started": false, "started_at": null})
	var got: Array[String] = []
	client.submit_start("3141592650", func(r: String) -> void: got.append(r))
	client.submit_start("3141592650", func(r: String) -> void: got.append(r))
	assert_int(fake.count("POST", "/finale/start")).is_equal(1)
	fake.release()
	assert_array(got).contains_exactly([FinaleClient.START_WRONG])
	# Once answered, the next tap goes out.
	fake.hold = false
	client.submit_start("3141592650", func(r: String) -> void: got.append(r))
	assert_int(fake.count("POST", "/finale/start")).is_equal(2)


func test_start_does_not_call_an_invalid_callback() -> void:
	fake.answer("POST", "/finale/start", 200, {"valid": false, "started": false, "started_at": null})
	client.submit_start("3141592650", Callable())  # no callback at all: must not raise
	assert_int(fake.count("POST", "/finale/start")).is_equal(1)
	# The guard was released, so a later tap still works.
	var got: Array[String] = []
	client.submit_start("3141592650", func(r: String) -> void: got.append(r))
	assert_array(got).contains_exactly([FinaleClient.START_WRONG])
