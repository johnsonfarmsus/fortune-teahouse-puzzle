# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## The finale's scenes: DialsPuzzle, HandoffHost, FinaleView, Archive, README,
## the Lucky word and Clues changes, and the hooks that hand out notes. Real
## autoloads, an in-memory FinaleState and a fake transport (no network).

const FinaleFixtures := preload("res://test/fixtures/finale_fixtures.gd")
const PROGRESS_PATH := "user://test_finale_progress.json"
const DEVICE_CREW := "oven"

var fake: FakeScoreboard
var data: FinaleData


func before_test() -> void:
	_cleanup()
	GameState.persist = false
	GameState.player = PlayerState.new()
	GameState.player.ensure_device_id()
	Progress.persist_settings = false
	Progress.scoreboard_url = ""
	Progress.set_store(LocalProgressStore.new(PROGRESS_PATH))
	Hints.pushed_nudges = {}
	Router.clear()
	Finale.set_client(null)
	Finale.set_state(FinaleState.new(""))
	fake = FakeScoreboard.new()
	data = Finale.data


func after_test() -> void:
	Router.clear()
	Finale.set_client(null)
	Finale.set_state(FinaleState.new(""))
	Progress.set_store(LocalProgressStore.new(PROGRESS_PATH))
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(PROGRESS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))


## A client on the fake transport, as if a scoreboard were in use.
func _online() -> FinaleClient:
	var client := FinaleClient.new(FakeScoreboard.BASE, Finale.state, fake.transport())
	client.set_identity(GameState.device_id, GameState.crew, "")
	Finale.set_client(client)
	return client


func _open(overrides: Dictionary = {}, extra: Dictionary = {}) -> void:
	Finale.state.set_cache(FinaleFixtures.finale(true, overrides, extra))


func _grant_all_crew_notes() -> void:
	for id in ["cookie_machine", "fortune_machine", "oven", "gopher"]:
		Finale.state.grant_note(id)


func _texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node in root.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	for node in root.find_children("*", "Button", true, false):
		out.append((node as Button).text)
	return out


func _has_text(root: Node, needle: String) -> bool:
	for text in _texts(root):
		if text.contains(needle):
			return true
	return false


func _button_with_text(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node
	return null


func _check_buttons(root: Node, label: String) -> void:
	var buttons := root.find_children("*", "BaseButton", true, false)
	assert_bool(buttons.is_empty()).override_failure_message("%s has no buttons" % label).is_false()
	for node in buttons:
		var b := node as BaseButton
		assert_float(b.custom_minimum_size.x).override_failure_message("%s: %s too narrow" % [label, b.name]).is_greater_equal(44.0)
		assert_float(b.custom_minimum_size.y).override_failure_message("%s: %s too short" % [label, b.name]).is_greater_equal(44.0)


func _dials(handoff_id: String, extra: Dictionary = {}) -> PuzzleBase:
	var config: Dictionary = data.handoff(handoff_id)["config"].duplicate(true)
	config.merge(extra, true)
	var puzzle: PuzzleBase = load("res://scenes/puzzles/dials_puzzle.tscn").instantiate()
	puzzle.puzzle_id = "finale/" + handoff_id
	puzzle.configure(config)
	add_child(auto_free(puzzle))
	return puzzle


func _set_answers(puzzle: Node, handoff_id: String) -> void:
	for dial: Dictionary in data.handoff(handoff_id)["config"]["dials"]:
		puzzle.set_value(str(dial["id"]), dial["answer"])


# --- DialsPuzzle ------------------------------------------------------------------------


func test_dials_a_test_locks_right_dials_and_emits_their_settings() -> void:
	var puzzle := _dials("cookie_to_oven")
	var emitted: Array = []
	puzzle.setting_set.connect(func(i: int) -> void: emitted.append(i))
	puzzle.set_value("belt_speed", 3)
	puzzle.set_value("press_every", 8)
	var marks: Dictionary = puzzle.test_run()
	assert_str(marks["belt_speed"]).is_equal("ok")
	assert_str(marks["press_every"]).is_equal("high")
	assert_str(marks["bowl_every"]).is_equal("low")
	assert_array(emitted).contains_exactly([0])
	assert_array(puzzle.locked()).contains_exactly(["belt_speed"])
	assert_str((puzzle.find_child("Tag_belt_speed", true, false) as Label).text).is_equal("Set - OK")
	assert_str((puzzle.find_child("Tag_press_every", true, false) as Label).text).is_equal("Too slow: big gaps on the belt.")
	assert_str((puzzle.find_child("Tag_bowl_every", true, false) as Label).text).is_equal("Too soon: the bowl overflows.")
	# Moving a dial clears its stale tag.
	puzzle.step("bowl_every", 1)
	assert_str((puzzle.find_child("Tag_bowl_every", true, false) as Label).text).is_equal("")
	assert_int(int(puzzle.values()["bowl_every"])).is_equal(2)


func test_dials_solved_true_once_every_dial_is_right() -> void:
	for id in ["cookie_to_oven", "fortune_to_oven", "oven_to_packaging"]:
		var puzzle := _dials(id)
		var credited: Array = []
		var emitted: Array = []
		puzzle.solved.connect(func(c: bool) -> void: credited.append(c))
		puzzle.setting_set.connect(func(i: int) -> void: emitted.append(i))
		_set_answers(puzzle, id)
		puzzle.test_run()
		assert_array(credited).contains_exactly([true])
		assert_array(emitted).contains_exactly([0, 1, 2])
		assert_int(puzzle.locked().size()).is_equal(3)


func test_dials_wrong_chute_says_gopher_frowns() -> void:
	var puzzle := _dials("oven_to_packaging")
	var credited: Array = []
	puzzle.solved.connect(func(c: bool) -> void: credited.append(c))
	puzzle.set_value("chute_1", "teahouse_tin")
	var marks: Dictionary = puzzle.test_run()
	assert_str(marks["chute_1"]).is_equal("wrong")
	assert_str((puzzle.find_child("Tag_chute_1", true, false) as Label).text).is_equal("Gopher frowns: that's not who wants these.")
	assert_array(credited).is_empty()
	assert_array(puzzle.locked()).is_empty()


func test_dials_three_hints_reveal_and_solve_uncredited() -> void:
	var puzzle := _dials("fortune_to_oven")
	var hints: Array = []
	var emitted: Array = []
	var credited: Array = []
	puzzle.hint_requested.connect(func(l: int) -> void: hints.append(l))
	puzzle.setting_set.connect(func(i: int) -> void: emitted.append(i))
	puzzle.solved.connect(func(c: bool) -> void: credited.append(c))
	Hints.reset(puzzle.puzzle_id)
	puzzle.request_hint()
	assert_str(puzzle.get_hint_text(1)).is_equal("Read both notes side by side. Everything you need is in them.")
	puzzle.request_hint()
	assert_str(puzzle.get_hint_text(2)).is_equal("How often does a round reach the arms?")
	assert_array(credited).is_empty()
	puzzle.request_hint()
	assert_array(hints).contains_exactly([1, 2, 3])
	assert_array(emitted).contains_exactly([0, 1, 2])
	assert_array(credited).contains_exactly([false])
	assert_int(int(puzzle.values()["print_every"])).is_equal(4)


func test_dials_level_two_names_the_first_unlocked_dial() -> void:
	var puzzle := _dials("fortune_to_oven")
	puzzle.set_value("print_every", 4)
	puzzle.test_run()
	assert_str(puzzle.get_hint_text(2)).is_equal("How long does fresh ink need?")


func test_dials_locked_indices_start_locked() -> void:
	var puzzle := _dials("oven_to_packaging", {"locked_indices": [1]})
	assert_array(puzzle.locked()).contains_exactly(["chute_2"])
	assert_str(str(puzzle.values()["chute_2"])).is_equal("teahouse_tin")
	assert_bool((puzzle.find_child("Plus_chute_2", true, false) as Button).disabled).is_true()
	assert_str((puzzle.find_child("Tag_chute_2", true, false) as Label).text).is_equal("Set - OK")
	var credited: Array = []
	puzzle.solved.connect(func(c: bool) -> void: credited.append(c))
	puzzle.set_value("chute_1", "rooftop_basket")
	puzzle.set_value("chute_3", "pier_crate")
	puzzle.test_run()
	assert_array(credited).contains_exactly([true])


func test_dials_buttons_are_at_least_44_px_and_steppers_48() -> void:
	for id in ["cookie_to_oven", "fortune_to_oven", "oven_to_packaging"]:
		var puzzle := _dials(id)
		_check_buttons(puzzle, id)
		for dial: Dictionary in data.handoff(id)["config"]["dials"]:
			for prefix in ["Minus_", "Plus_"]:
				var b := puzzle.find_child(prefix + str(dial["id"]), true, false) as Button
				assert_float(b.custom_minimum_size.x).is_greater_equal(48.0)
				assert_float(b.custom_minimum_size.y).is_greater_equal(48.0)
	assert_str(((_dials("oven_to_packaging")).find_child("TestButton", true, false) as Button).text).is_equal("Send a test cookie")
	assert_str(((_dials("cookie_to_oven")).find_child("TestButton", true, false) as Button).text).is_equal("Run a test batch")


func test_dials_belt_preview_words() -> void:
	var puzzle := _dials("cookie_to_oven")
	var preview := puzzle.find_child("Preview", true, false) as DialPreview
	assert_str(preview.words()).is_equal("Rounds: burnt\nSpacing: touching\nBowl: overflowing")
	_set_answers(puzzle, "cookie_to_oven")
	assert_str(preview.words()).is_equal("Rounds: golden\nSpacing: even\nBowl: full")
	puzzle.set_value("belt_speed", 6)
	puzzle.set_value("press_every", 8)
	puzzle.set_value("bowl_every", 6)
	assert_str(preview.words()).is_equal("Rounds: raw\nSpacing: gappy\nBowl: empty")


func test_dials_beats_preview_folds_and_smudges() -> void:
	var puzzle := _dials("fortune_to_oven")
	var preview := puzzle.find_child("Preview", true, false) as DialPreview
	# The answers: every fortune lands as the arms fold.
	_set_answers(puzzle, "fortune_to_oven")
	assert_str(preview.words()).is_equal("Folded: 3 of 3.")
	# Too little drying smudges the ink, whatever else is right.
	puzzle.set_value("dry", 0)
	puzzle.set_value("start_tick", 1)
	assert_str(preview.words()).contains("Smudged")
	# Printing every 6 ticks leaves rounds without a fortune.
	puzzle.set_value("dry", 1)
	puzzle.set_value("start_tick", 0)
	puzzle.set_value("print_every", 6)
	assert_str(preview.words()).is_equal("Folded: 1 of 3.")


func test_dials_routes_preview_is_dashed_until_locked() -> void:
	var puzzle := _dials("oven_to_packaging")
	var preview := puzzle.find_child("Preview", true, false) as DialPreview
	assert_str(preview.words()).contains("Chute 1: dashed, not set yet")
	puzzle.set_value("chute_1", "rooftop_basket")
	puzzle.test_run()
	assert_str(preview.words()).contains("Chute 1: connected")
	assert_str(preview.words()).contains("Chute 2: dashed, not set yet")


# --- HandoffHost ------------------------------------------------------------------------


func test_handoff_host_says_the_finale_has_not_opened() -> void:
	var screen := Router.push(Paths.HANDOFF_HOST, {"handoff": "cookie_to_oven"})
	await get_tree().process_frame
	assert_bool(_has_text(screen, "The finale hasn't opened yet.")).is_true()
	assert_object(screen.puzzle).is_null()


func test_handoff_host_asks_for_the_missing_notes() -> void:
	_online()
	_open()
	var screen := Router.push(Paths.HANDOFF_HOST, {"handoff": "cookie_to_oven"})
	await get_tree().process_frame
	assert_bool(_has_text(screen, "You need the Cookie Machine note. Find someone from the Cookie Machine crew and ask for their handoff word.")).is_true()
	assert_bool(_has_text(screen, "You need the Oven note. Find someone from the Oven crew and ask for their handoff word.")).is_true()
	assert_object(screen.puzzle).is_null()
	Finale.state.grant_note("cookie_machine")
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Cookie Machine crew and ask")).is_false()
	assert_bool(_has_text(screen, "You need the Oven note.")).is_true()


func test_handoff_host_waits_for_a_machine_that_is_not_running() -> void:
	_online()
	var waiting := {"oven_to_packaging": FinaleFixtures.handoff("oven_to_packaging", "waiting", [], false)}
	_open(waiting)
	_grant_all_crew_notes()
	var screen := Router.push(Paths.HANDOFF_HOST, {"handoff": "oven_to_packaging"})
	await get_tree().process_frame
	assert_bool(_has_text(screen, "This handoff waits for the Oven.")).is_true()
	assert_object(screen.puzzle).is_null()
	# The Oven runs and the server says the handoff is available: the puzzle appears.
	for part in Ids.PARTS:
		Progress.store.record_part_solved("oven", part, GameState.device_id, true)
	_open()
	await get_tree().process_frame
	assert_object(screen.puzzle).is_not_null()
	assert_bool(_has_text(screen, "waits for")).is_false()


func test_handoff_host_header_counts_and_completion() -> void:
	_online()
	_open({"cookie_to_oven": FinaleFixtures.handoff("cookie_to_oven", "in_progress", [0, 1], true)})
	_grant_all_crew_notes()
	var screen := Router.push(Paths.HANDOFF_HOST, {"handoff": "cookie_to_oven"})
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Settings set by everyone: 2 of 3. On this phone: 0 of 3.")).is_true()
	var puzzle: PuzzleBase = screen.puzzle
	assert_object(puzzle).is_not_null()
	puzzle.set_value("belt_speed", 3)
	puzzle.test_run()
	assert_bool(_has_text(screen, "Settings set by everyone: 2 of 3. On this phone: 1 of 3.")).is_true()
	assert_array(Finale.settings_on_phone("cookie_to_oven")).contains_exactly([0])
	assert_int(Finale.state.queue.size()).is_equal(0)  # sent to the fake at once
	assert_int(fake.count("POST", "/finale/handoffs/cookie_to_oven/settings")).is_equal(1)
	assert_bool(_has_text(screen, "connected on this phone")).is_false()
	_set_answers(puzzle, "cookie_to_oven")
	puzzle.test_run()
	assert_bool(_has_text(screen, "Cookie Machine to Oven: connected on this phone. Elephant adds a page to the README.")).is_true()
	assert_bool(_has_text(screen, "On this phone: 3 of 3.")).is_true()
	assert_bool(Finale.handoff_connected("cookie_to_oven")).is_true()
	var next := screen.find_child("ContinueButton", true, false) as Button
	assert_bool(next.visible).is_true()
	_check_buttons(screen, "handoff host")
	next.pressed.emit()
	assert_int(Router.depth()).is_equal(0)


func test_handoff_host_revealed_settings_still_post() -> void:
	_online()
	_open()
	_grant_all_crew_notes()
	var screen := Router.push(Paths.HANDOFF_HOST, {"handoff": "fortune_to_oven"})
	await get_tree().process_frame
	var puzzle: PuzzleBase = screen.puzzle
	Hints.reset(puzzle.puzzle_id)
	puzzle.request_hint()
	puzzle.request_hint()
	puzzle.request_hint()
	assert_int(Finale.settings_on_phone("fortune_to_oven").size()).is_equal(3)
	assert_int(fake.count("POST", "/finale/handoffs/fortune_to_oven/settings")).is_equal(3)
	assert_bool(_has_text(screen, "Fortune Machine to Oven: connected on this phone.")).is_true()


func test_handoff_host_reopens_with_settings_already_locked() -> void:
	_open()
	_grant_all_crew_notes()
	Finale.add_setting("oven_to_packaging", 0)
	var screen := Router.push(Paths.HANDOFF_HOST, {"handoff": "oven_to_packaging"})
	await get_tree().process_frame
	assert_array(screen.puzzle.locked()).contains_exactly(["chute_1"])
	assert_bool(_has_text(screen, "On this phone: 1 of 3.")).is_true()


# --- Handoff words ------------------------------------------------------------------------


func test_a_handoff_word_collects_the_note_once() -> void:
	var screen := Router.push(Paths.LUCKY_WORD_ENTRY)
	await get_tree().process_frame
	var result: Label
	for node in screen.find_children("*", "Label", true, false):
		if (node as Label).custom_minimum_size.y == 52.0:
			result = node
	screen._on_submitted(" golden-round ")
	assert_str(result.text).is_equal("Handoff note collected! See it under Clues.")
	assert_bool(Finale.state.has_note("oven")).is_true()
	assert_str(GameState.crew).is_equal("")  # a handoff word never picks a crew
	screen._on_submitted("GOLDENROUND")
	assert_str(result.text).is_equal("You already have that note.")


func test_an_unknown_word_points_to_the_archive() -> void:
	var screen := Router.push(Paths.LUCKY_WORD_ENTRY)
	await get_tree().process_frame
	screen._on_submitted("NOPE")
	assert_bool(_has_text(screen, "That word is not on any cookie we know. Check the spelling. If it's from one of the gnu's notes, take it to Elephant at the Archive.")).is_true()
	assert_int(Finale.state.notes_held.size()).is_equal(0)


func test_a_lucky_word_still_wins_over_the_finale() -> void:
	var screen := Router.push(Paths.LUCKY_WORD_ENTRY)
	await get_tree().process_frame
	screen._on_submitted("TUX")
	assert_bool(_has_text(screen, "Clue collected!")).is_true()
	assert_int(Finale.state.notes_held.size()).is_equal(0)


# --- Archive ------------------------------------------------------------------------------


func test_archive_codes_before_the_finale_opens() -> void:
	_online()
	fake.answer("POST", "/finale/notes", 403, FakeScoreboard.error("finale_closed"))
	var screen := Router.push(Paths.ARCHIVE)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Elephant: I keep the town's records. The gnu left notes all over the place. Bring me any you find.")).is_true()
	assert_bool(_has_text(screen, "Type the code from one of the gnu's notes.")).is_true()
	assert_bool(_has_text(screen, "Notes found by everyone: 0 of 6 (4 needed). On this phone: 0.")).is_true()
	assert_bool(_has_text(screen, "Somewhere at the venue, or ask Red Panda.")).is_true()
	assert_object(_button_with_text(screen, "Ask Red Panda")).is_null()  # not open yet
	screen._on_submitted("kettle 27")
	assert_bool(_has_text(screen, "Elephant files it. It goes in when the finale opens.")).is_true()
	assert_bool(_has_text(screen, "Note to self: the registration desk always runs out of pens. Bring more. – G. Code: KETTLE 27")).is_true()
	assert_bool(_has_text(screen, "On this phone: 1.")).is_true()
	assert_int(Finale.state.queue.size()).is_equal(1)  # held until the finale opens
	assert_str(str(Finale.state.queue[0]["code"])).is_equal("KETTLE27")
	assert_bool(bool(Finale.state.queue[0]["held"])).is_true()


func test_archive_valid_repeat_and_invalid_codes_when_open() -> void:
	_online()
	_open()
	fake.answer("POST", "/finale/notes", 200, {"valid": true, "already_found": false, "notes": {"found": 1, "total": 6, "needed": 4, "complete": false}})
	var screen := Router.push(Paths.ARCHIVE)
	await get_tree().process_frame
	var result: Label
	for node in screen.find_children("*", "Label", true, false):
		if (node as Label).custom_minimum_size.y == 52.0:
			result = node
	screen._on_submitted("GULLWING41")
	assert_str(result.text).is_equal("Elephant files it. Thank you!")
	assert_str(str(fake.last_post_body()["code"])).is_equal("GULLWING41")
	assert_bool(_has_text(screen, "Notes found by everyone: 1 of 6 (4 needed). On this phone: 1.")).is_true()
	screen._on_submitted("Gullwing 41")
	assert_str(result.text).is_equal("Elephant already has that one.")
	screen._on_submitted("KETTLE 28")
	assert_str(result.text).is_equal("That isn't one of the gnu's notes. Check the code.")
	assert_int(Finale.state.gnu_notes.size()).is_equal(1)
	assert_int(fake.count("POST", "/finale/notes")).is_equal(1)
	_check_buttons(screen, "archive")


func test_archive_works_with_no_scoreboard() -> void:
	var screen := Router.push(Paths.ARCHIVE)
	await get_tree().process_frame
	screen._on_submitted("INKBLOT 19")
	assert_bool(_has_text(screen, "Elephant files it. It goes in when the finale opens.")).is_true()
	assert_bool(Finale.state.has_gnu_note("note_5")).is_true()


func test_archive_twin_files_the_note_once_the_finale_is_open() -> void:
	_online()
	_open()
	fake.answer("POST", "/finale/notes", 200, {"valid": true, "already_found": false, "notes": {"found": 1, "total": 6, "needed": 4, "complete": false}})
	var archive := Router.push(Paths.ARCHIVE)
	await get_tree().process_frame
	var ask := _button_with_text(archive, "Ask Crab")
	assert_object(ask).is_not_null()
	ask.pressed.emit()
	await get_tree().process_frame
	var host := Router.top()
	assert_str(host.scene_file_path).is_equal(Paths.HANDOFF_HOST)
	var helper: PuzzleBase = host.puzzle
	assert_object(helper).is_not_null()
	var config: Dictionary = data.gnu_note("note_3")["twin"]["config"]
	helper.advance()
	helper.advance()
	helper.answer_choice((int(config["correct"]) + 1) % 3)  # wrong first
	assert_bool(Finale.state.has_gnu_note("note_3")).is_false()
	helper.answer_choice(int(config["correct"]))
	assert_bool(Finale.state.has_gnu_note("note_3")).is_true()
	assert_bool(_has_text(host, "Elephant files it. Thank you!")).is_true()
	assert_str(str(fake.last_post_body()["code"])).is_equal("DRIPCOFFEE08")
	Router.pop()
	await get_tree().process_frame
	assert_bool(_has_text(archive, "Hallway-track") or _has_text(archive, "DRIPCOFFEE 08")).is_true()
	assert_object(_button_with_text(archive, "Ask Crab")).is_null()


func test_archive_twin_is_closed_before_the_finale_opens() -> void:
	var archive := Router.push(Paths.ARCHIVE)
	await get_tree().process_frame
	archive.ask_twin("note_1")
	assert_int(Router.depth()).is_equal(1)
	var host := Router.push(Paths.HANDOFF_HOST, {"twin": "note_1"})
	await get_tree().process_frame
	assert_bool(_has_text(host, "The finale hasn't opened yet.")).is_true()
	assert_object(host.puzzle).is_null()


func test_archive_opens_the_readme() -> void:
	var archive := Router.push(Paths.ARCHIVE)
	await get_tree().process_frame
	_button_with_text(archive, "README so far").pressed.emit()
	await get_tree().process_frame
	assert_str(Router.top().scene_file_path).is_equal(Paths.README_SCREEN)


# --- README -------------------------------------------------------------------------------


func test_readme_sections_appear_as_triggers_hold() -> void:
	var screen := Router.push(Paths.README_SCREEN)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "The gnu's shop: README")).is_true()
	assert_bool(_has_text(screen, "Written by everyone who fixed it, because I never did. – G.")).is_true()
	assert_bool(_has_text(screen, "Nothing is written yet")).is_true()
	for part in Ids.PARTS:
		Progress.store.record_part_solved("cookie_machine", part, GameState.device_id, true)
	assert_bool(_has_text(screen, "Dry first, then wet, then mix and rest.")).is_true()
	assert_bool(_has_text(screen, "Five phrase banks")).is_false()
	for i in 3:
		Finale.add_setting("oven_to_packaging", i)
	assert_bool(_has_text(screen, "Chute 1, extra crisp, to Seagull's rooftop basket.")).is_true()
	assert_bool(_has_text(screen, "Maintainers")).is_false()


func test_readme_closing_names_the_contributors_once_started() -> void:
	GameState.set_display_name("Ada")
	for part in Ids.PARTS:
		Progress.store.record_part_solved("oven", part, GameState.device_id, true)
	_open({}, {"started": true})
	var screen := Router.push(Paths.README_SCREEN)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Maintainers")).is_true()
	assert_bool(_has_text(screen, "Not one gnu. All of you:")).is_true()
	assert_bool(_has_text(screen, "Ada")).is_true()


# --- FinaleView ---------------------------------------------------------------------------


func test_finale_view_without_a_scoreboard() -> void:
	var screen := Router.push(Paths.FINALE_VIEW)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "The finale is played together on the event scoreboard. Open the game from the event link to join in.")).is_true()
	assert_bool((screen.find_child("Row_cookie_to_oven", true, false) as Control).is_visible_in_tree()).is_false()
	assert_bool(_has_text(screen, "Gnu's notes: 0 of 6 found (4 needed)")).is_true()


func test_finale_view_before_it_opens() -> void:
	_online()
	Finale.state.set_cache(FinaleFixtures.finale(false))
	for part in Ids.PARTS:
		Progress.store.record_part_solved("cookie_machine", part, GameState.device_id, true)
	Progress.store.record_part_solved("oven", "logic", GameState.device_id, true)
	var screen := Router.push(Paths.FINALE_VIEW)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "The gnu ran the handoffs between his machines by hand and never wrote down how. Once all three machines run, everyone connects them into one line. Opens when they all run, or at ")).is_true()
	assert_bool(_has_text(screen, " at the latest.")).is_true()
	assert_bool(_has_text(screen, "Cookie Machine: running")).is_true()
	assert_bool(_has_text(screen, "Oven: 1 of 6 parts working")).is_true()
	assert_bool(_has_text(screen, "Fortune Machine: 0 of 6 parts working")).is_true()
	assert_bool(_has_text(screen, "Cookie Machine to Oven: locked")).is_true()
	assert_bool(_has_text(screen, "Start code: the line isn't ready yet.")).is_true()
	assert_bool(_has_text(screen, "Gnu's notes: 0 of 6 found (4 needed)")).is_true()


func test_finale_view_drops_the_time_when_an_admin_holds_it_closed() -> void:
	_online()
	Finale.state.set_cache(FinaleFixtures.finale(false, {}, {"open_reason": "admin_closed", "override": "closed"}))
	var screen := Router.push(Paths.FINALE_VIEW)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Opens when they all run.")).is_true()
	assert_bool(_has_text(screen, "at the latest")).is_false()


func test_finale_view_rows_follow_the_cached_finale() -> void:
	_online()
	var overrides := {
		"cookie_to_oven": FinaleFixtures.handoff("cookie_to_oven", "in_progress", [0, 2], true),
		"fortune_to_oven": FinaleFixtures.handoff("fortune_to_oven", "waiting", [], false),
		"oven_to_packaging": FinaleFixtures.handoff("oven_to_packaging", "connected", [0, 1, 2], true),
	}
	_open(overrides)
	var screen := Router.push(Paths.FINALE_VIEW)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Cookie Machine to Oven: 2 of 3 settings")).is_true()
	assert_bool(_has_text(screen, "Fortune Machine to Oven: waiting for the Fortune Machine and Oven")).is_true()
	assert_bool(_has_text(screen, "Oven to packaging: connected")).is_true()
	assert_bool(_has_text(screen, "Opens when they all run")).is_false()
	_check_buttons(screen, "finale view")
	(screen.find_child("Row_cookie_to_oven", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	assert_str(Router.top().scene_file_path).is_equal(Paths.HANDOFF_HOST)
	assert_str(Router.top().handoff_id).is_equal("cookie_to_oven")


func test_finale_view_start_code_flow() -> void:
	_online()
	_open({}, {"line_ready": true})
	var screen := Router.push(Paths.FINALE_VIEW)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "The line is ready! The start code is the lucky numbers from the backs of two cookies, Pack A then Pack B.")).is_true()
	assert_bool(screen._keypad.is_visible_in_tree()).is_true()
	fake.answer("POST", "/finale/start", 200, {"valid": false, "started": false, "started_at": null})
	screen._keypad.submitted.emit("3141592650")
	assert_bool(_has_text(screen, "Wrong code. Read both cookie backs again.")).is_true()
	fake.answer("POST", "/finale/start", 409, FakeScoreboard.error("line_not_ready"))
	screen._keypad.submitted.emit("3141592653")
	assert_bool(_has_text(screen, "The line isn't quite ready yet.")).is_true()
	fake.answer("POST", "/finale/start", 200, {"valid": true, "started": true, "started_at": "2027-10-30T20:30:00Z"})
	screen._keypad.submitted.emit("3141592653")
	assert_bool(_has_text(screen, "The line is running!")).is_true()
	assert_bool(screen._keypad.is_visible_in_tree()).is_false()
	assert_bool(Finale.started()).is_true()
	assert_bool(Story.flag("line_running")).is_true()


func test_finale_view_hides_the_keypad_until_the_line_is_ready() -> void:
	_online()
	_open()
	var screen := Router.push(Paths.FINALE_VIEW)
	await get_tree().process_frame
	assert_bool(screen._keypad.is_visible_in_tree()).is_false()
	assert_bool(_has_text(screen, "Start code: the line isn't ready yet.")).is_true()
	assert_bool(Story.flag("finale_open")).is_true()


func test_finale_view_unreachable_shows_the_cache() -> void:
	_online()
	_open({"cookie_to_oven": FinaleFixtures.handoff("cookie_to_oven", "in_progress", [1], true)})
	fake.offline = true
	Finale.client.refresh()
	var screen := Router.push(Paths.FINALE_VIEW)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "The scoreboard can't be reached right now. Showing what this phone last heard.")).is_true()
	assert_bool(_has_text(screen, "Cookie Machine to Oven: 1 of 3 settings")).is_true()


func test_finale_view_shows_maintainers_their_crew_word() -> void:
	_online()
	_open()
	GameState.choose_crew("oven")
	var screen := Router.push(Paths.FINALE_VIEW)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Your crew's handoff word")).is_false()
	# The oven runs: the player is a maintainer, holds the note and sees its word.
	fake.answer("GET", "/crews/oven", 200, FakeScoreboard.crew("oven", {"logic": 1, "wiring": 1, "sequence": 1, "word": 1, "rhythm": 1, "helper": 1}, true))
	var remote := RemoteProgressStore.new(FakeScoreboard.BASE, LocalProgressStore.new(PROGRESS_PATH), fake.transport(), "user://test_finale_queue.json")
	Progress.scoreboard_url = FakeScoreboard.BASE
	Progress.set_store(remote)
	Finale.set_client(null)
	_online()
	remote.set_identity(GameState.device_id, "oven", "")
	remote.refresh()
	await get_tree().process_frame
	assert_bool(Progress.is_maintainer()).is_true()
	assert_bool(_has_text(screen, "Your crew's handoff word: GOLDENROUND. Share it!")).is_true()
	Progress.scoreboard_url = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_finale_queue.json"))


# --- Clues --------------------------------------------------------------------------------


func test_clue_board_shows_handoff_notes_first_with_the_word_to_share() -> void:
	Finale.state.grant_note("oven")
	Finale.state.grant_note("cookie_machine")
	var screen := Router.push(Paths.CLUE_BOARD)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Handoff notes")).is_true()
	assert_bool(_has_text(screen, "Handoff word: GOLDENROUND. Share it with someone from another crew.")).is_true()
	assert_bool(_has_text(screen, "Handoff word: BATTERBOWL. Share it with someone from another crew.")).is_true()
	assert_bool(_has_text(screen, "The baking tunnel is 120 cm long")).is_true()
	assert_bool(_has_text(screen, "PAPERCHUTE")).is_false()
	assert_bool(_has_text(screen, "The gnu's last fortune")).is_false()
	var order: Array[String] = []
	for node in screen.find_children("*", "Label", true, false):
		order.append((node as Label).text)
	var notes_at := order.find("Handoff notes")
	var first_machine_at := -1
	for i in order.size():
		if order[i].contains("needed") and not order[i].begins_with("Gnu"):
			first_machine_at = i
			break
	assert_int(notes_at).is_greater_equal(0)
	assert_int(notes_at).is_less(first_machine_at)


func test_clue_board_has_no_handoff_section_without_notes() -> void:
	var screen := Router.push(Paths.CLUE_BOARD)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Handoff notes")).is_false()


func test_clue_board_shows_the_last_fortune_once_started() -> void:
	_open({}, {"started": true})
	var screen := Router.push(Paths.CLUE_BOARD)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "The gnu's last fortune")).is_true()
	assert_bool(_has_text(screen, "You figured out what I never wrote down. It's yours now. – G.")).is_true()


func test_clue_board_shows_gophers_slip_once_the_finale_is_open() -> void:
	_open()
	Finale.sync_notes()
	var screen := Router.push(Paths.CLUE_BOARD)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Seagull wants the extra crisp ones for the rooftop basket.")).is_true()
	assert_bool(_has_text(screen, "Handoff word:")).is_false()  # the slip has no word


# --- Hooks --------------------------------------------------------------------------------


func test_a_crews_note_is_granted_when_its_machine_runs() -> void:
	GameState.choose_crew("cookie_machine")
	assert_bool(Finale.state.has_note("cookie_machine")).is_false()
	for part in Ids.PARTS:
		Progress.store.record_part_solved("cookie_machine", part, GameState.device_id, true)
	assert_bool(Finale.state.has_note("cookie_machine")).is_true()
	assert_bool(Finale.state.has_note("oven")).is_false()


func test_joining_a_running_crew_grants_its_note_at_once() -> void:
	for part in Ids.PARTS:
		Progress.store.record_part_solved("fortune_machine", part, "someone_else", true)
	assert_bool(Finale.state.has_note("fortune_machine")).is_false()  # not in that crew
	GameState.choose_crew("fortune_machine")
	assert_bool(Finale.state.has_note("fortune_machine")).is_true()


func test_gophers_slip_is_granted_when_the_finale_opens() -> void:
	_online()
	assert_bool(Finale.state.has_note("gopher")).is_false()
	fake.answer("GET", "/finale", 200, FinaleFixtures.finale(true))
	Finale.client.refresh()
	assert_bool(Finale.state.has_note("gopher")).is_true()
	assert_bool(Story.flag("finale_open")).is_true()


func test_the_finale_polls_only_while_a_finale_screen_is_on_top() -> void:
	var client := _online()
	fake.answer("GET", "/finale", 200, FinaleFixtures.finale(false))
	Finale._connect_router()
	Router.push(Paths.SETTINGS)
	assert_bool(client.is_watching()).is_false()
	Router.push(Paths.FINALE_VIEW)
	assert_bool(client.is_watching()).is_true()
	Router.push(Paths.ARCHIVE)
	assert_bool(client.is_watching()).is_true()
	Router.pop()
	Router.pop()
	assert_bool(client.is_watching()).is_false()  # the settings screen is on top again


# --- Town and Shop --------------------------------------------------------------------------


func test_the_town_has_an_archive_hotspot_that_opens_the_archive() -> void:
	var town: PlaceBase = auto_free(load(Paths.PLACES["town"]).instantiate())
	add_child(town)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := town.hotspot_at(Vector2(295, 240))
	assert_object(hit).is_not_null()
	assert_str(hit.place_id).is_equal("archive")
	assert_object(town.get_node("Hotspots/Archive")).is_not_null()
	town.activate(hit)
	assert_str(Router.top().scene_file_path).is_equal(Paths.ARCHIVE)


func test_the_shop_has_a_the_line_button() -> void:
	var shop: Node = auto_free(load(Paths.PLACES["shop"]).instantiate())
	add_child(shop)
	await get_tree().process_frame
	var button := shop.get_node("LineButton") as Button
	assert_str(button.text).is_equal("The line")
	assert_float(button.custom_minimum_size.x).is_greater_equal(44.0)
	assert_float(button.custom_minimum_size.y).is_greater_equal(44.0)
	button.pressed.emit()
	assert_str(Router.top().scene_file_path).is_equal(Paths.FINALE_VIEW)


# --- Review follow-ups ----------------------------------------------------------------------


func test_a_revealed_twin_files_nothing() -> void:
	_online()
	_open()
	var host := Router.push(Paths.HANDOFF_HOST, {"twin": "note_2"})
	await get_tree().process_frame
	var helper: PuzzleBase = host.puzzle
	assert_object(helper).is_not_null()
	Hints.reset(helper.puzzle_id)
	helper.request_hint()
	helper.request_hint()
	helper.request_hint()  # level 3: the answer is shown, solved(false)
	assert_bool(Finale.state.has_gnu_note("note_2")).is_false()
	assert_int(Finale.state.queue.size()).is_equal(0)
	assert_int(fake.count("POST", "/finale/notes")).is_equal(0)
	assert_bool(_has_text(host, "Elephant smiles. Find the real note, or solve it yourself.")).is_true()
	assert_bool(_has_text(host, "Elephant files it. Thank you!")).is_false()
	assert_int(Finale.notes_found()).is_equal(0)


func test_reset_device_clears_the_finale_state() -> void:
	Finale.state.grant_note("oven")
	Finale.add_setting("cookie_to_oven", 1)
	Finale.collect_gnu_note("note_4")
	Finale.state.set_cache(FinaleFixtures.finale(true))
	assert_bool(Finale.state.queue.is_empty()).is_false()
	GameState.reset_device()
	assert_bool(Finale.state.notes_held.is_empty()).is_true()
	assert_bool(Finale.state.settings.is_empty()).is_true()
	assert_bool(Finale.state.gnu_notes.is_empty()).is_true()
	assert_bool(Finale.state.queue.is_empty()).is_true()
	assert_bool(Finale.state.cache.is_empty()).is_true()
	assert_bool(Finale.is_open()).is_false()
	assert_bool(Story.flag("finale_open")).is_false()


func test_finale_screens_make_progress_watch_all_three_machines() -> void:
	var queue := "user://test_finale_watch_queue.json"
	var remote := RemoteProgressStore.new(FakeScoreboard.BASE, LocalProgressStore.new(PROGRESS_PATH), fake.transport(), queue)
	Progress.set_store(remote)
	Router.push(Paths.SETTINGS)
	assert_array(remote.watched_machines()).is_empty()
	for path in [Paths.FINALE_VIEW, Paths.ARCHIVE]:
		Router.push(path)
		assert_array(remote.watched_machines()).contains_exactly(Ids.MACHINES)
		Router.pop()
		assert_array(remote.watched_machines()).is_empty()
	Router.push(Paths.HANDOFF_HOST, {"handoff": "oven_to_packaging"})
	assert_array(remote.watched_machines()).contains_exactly(Ids.MACHINES)
	assert_int(fake.count("GET", "/crews/")).is_greater_equal(3)
	Router.clear()
	assert_array(remote.watched_machines()).is_empty()
	if FileAccess.file_exists(queue):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(queue))
