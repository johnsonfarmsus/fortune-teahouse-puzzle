# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## Scene tests. They use the real autoloads but never touch the real save:
## GameState does not persist and Progress gets a throwaway store file.

const PROGRESS_PATH := "user://test_scene_progress.json"
const MACHINE := "cookie_machine"


func before_test() -> void:
	_cleanup()
	GameState.persist = false
	GameState.player = PlayerState.new()
	GameState.player.ensure_device_id()
	Progress.set_store(LocalProgressStore.new(PROGRESS_PATH))
	Router.clear()


func after_test() -> void:
	Router.clear()
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(PROGRESS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))


func _all_clue_ids(machine: String) -> Array:
	var ids: Array = []
	for clue: Dictionary in PuzzleData.get_clues(machine):
		ids.append(clue["id"])
	return ids


func _matching(clue_count: int) -> PuzzleBase:
	var ids := _all_clue_ids(MACHINE).slice(0, clue_count)
	var puzzle: PuzzleBase = load("res://scenes/puzzles/matching_puzzle.tscn").instantiate()
	puzzle.puzzle_id = MACHINE + "/logic"
	puzzle.machine = MACHINE
	puzzle.part = "logic"
	puzzle.configure(PuzzleData.matching_config(MACHINE, ids))
	add_child(auto_free(puzzle))
	return puzzle


func _place_answer(puzzle: Node) -> void:
	var answer := PuzzleData.get_answer(MACHINE)
	for item: String in answer:
		puzzle.place(item, answer[item])


func _check_buttons(root: Node, label: String) -> void:
	var buttons := root.find_children("*", "BaseButton", true, false)
	assert_bool(buttons.is_empty()).override_failure_message("%s has no buttons" % label).is_false()
	for node in buttons:
		var b := node as BaseButton
		assert_float(b.custom_minimum_size.x).override_failure_message("%s: %s too narrow" % [label, b.name]).is_greater_equal(44.0)
		assert_float(b.custom_minimum_size.y).override_failure_message("%s: %s too short" % [label, b.name]).is_greater_equal(44.0)


# --- Main, Router, screens ---------------------------------------------------


func test_main_starts_into_the_town() -> void:
	var main: Node = auto_free(load(Paths.MAIN).instantiate())
	add_child(main)
	await get_tree().process_frame
	assert_bool(main.hud.visible).is_false()
	main.start_screen.started.emit()
	await get_tree().process_frame
	assert_str(Router.current_place().name).is_equal("Town")
	assert_bool(main.hud.visible).is_true()
	# A new player with no crew and no clues lands on lucky-word entry.
	assert_int(Router.depth()).is_equal(1)
	_check_buttons(main.hud, "hud")


func test_main_with_a_crew_skips_lucky_word_entry() -> void:
	GameState.player.choose_crew("oven")
	var main: Node = auto_free(load(Paths.MAIN).instantiate())
	add_child(main)
	await get_tree().process_frame
	main.start_screen.started.emit()
	await get_tree().process_frame
	assert_int(Router.depth()).is_equal(0)


func test_router_push_pop_replace_top() -> void:
	assert_int(Router.depth()).is_equal(0)
	Router.push(Paths.CLUE_BOARD)
	assert_int(Router.depth()).is_equal(1)
	Router.push(Paths.SETTINGS)
	assert_int(Router.depth()).is_equal(2)
	assert_bool(Router.top() is ScreenBase).is_true()
	Router.replace_top(Paths.CONTRIBUTORS)
	assert_int(Router.depth()).is_equal(2)
	Router.pop()
	assert_int(Router.depth()).is_equal(1)
	Router.pop()
	Router.pop()
	assert_int(Router.depth()).is_equal(0)
	assert_object(Router.top()).is_null()


func test_every_screen_instantiates_with_big_buttons() -> void:
	GameState.enter_lucky_word("TUX")
	var screens: Array = [
		[Paths.LUCKY_WORD_ENTRY, {}],
		[Paths.CLUE_BOARD, {}],
		[Paths.MACHINE_VIEW, {"machine": MACHINE}],
		[Paths.CONTRIBUTORS, {}],
		[Paths.CONTRIBUTORS, {"machine": MACHINE}],
		[Paths.SETTINGS, {}],
	]
	for part in Ids.PARTS:
		screens.append([Paths.PUZZLE_HOST, {"machine": MACHINE, "part": part}])
	for entry: Array in screens:
		var screen := Router.push(entry[0], entry[1])
		await get_tree().process_frame
		_check_buttons(screen, str(entry[0]))
		Router.pop()


func test_merge_celebration_screens() -> void:
	for credited in [true, false]:
		var screen := Router.push(
			Paths.MERGE_CELEBRATION, {"machine": MACHINE, "part": "logic", "credited": credited, "now_running": credited}
		)
		await get_tree().process_frame
		screen.skip()
		await get_tree().process_frame
		_check_buttons(screen, "merge credited=%s" % credited)
		Router.pop()


func _button_with_text(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node
	return null


func _merge_screen(credited: bool = true) -> ScreenBase:
	var screen := Router.push(Paths.MERGE_CELEBRATION, {"machine": MACHINE, "part": "logic", "credited": credited})
	await get_tree().process_frame
	screen.skip()
	return screen


func test_merge_celebration_asks_for_a_name_once() -> void:
	var screen := await _merge_screen()
	var anon := _button_with_text(screen, "Stay anonymous")
	assert_object(anon).is_not_null()
	anon.pressed.emit()
	assert_bool(GameState.name_asked).is_true()
	assert_str(GameState.display_name).is_empty()
	Router.pop()
	# A second credited solve does not ask again.
	var second := await _merge_screen()
	assert_object(_button_with_text(second, "Stay anonymous")).is_null()
	assert_object(_button_with_text(second, "Add my name")).is_null()
	assert_object(_button_with_text(second, "Continue")).is_not_null()


func test_merge_celebration_add_my_name() -> void:
	var screen := await _merge_screen()
	var keypad := screen.find_children("*", "LetterKeypad", true, false)[0] as LetterKeypad
	for ch in "TUX":
		keypad.type_char(ch)
	_button_with_text(screen, "Add my name").pressed.emit()
	assert_bool(GameState.name_asked).is_true()
	assert_str(GameState.display_name).is_equal("TUX")
	assert_object(_button_with_text(screen, "Continue")).is_not_null()
	assert_object(_button_with_text(screen, "Add my name")).is_null()


func test_uncredited_merge_never_asks_for_a_name() -> void:
	var screen := await _merge_screen(false)
	assert_object(_button_with_text(screen, "Stay anonymous")).is_null()
	assert_bool(GameState.name_asked).is_false()


# --- World --------------------------------------------------------------------


func test_town_hotspots_and_tap_hit_test() -> void:
	var town: PlaceBase = auto_free(load(Paths.PLACES["town"]).instantiate())
	add_child(town)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hotspots := town.find_children("*", "Hotspot", true, false)
	assert_int(hotspots.size()).is_equal(3)
	for node in hotspots:
		var shape := (node as Hotspot).get_node("Shape") as CollisionShape2D
		var size: Vector2 = (shape.shape as RectangleShape2D).size
		assert_float(size.x).is_greater_equal(96.0)
		assert_float(size.y).is_greater_equal(96.0)
	var shop := town.hotspot_at(Vector2(95, 240))
	assert_object(shop).is_not_null()
	assert_str(shop.place_id).is_equal("shop")
	assert_object(town.hotspot_at(Vector2(200, 400))).is_null()
	assert_object(town.get_node("Avatar")).is_not_null()


func test_shop_has_three_machines_with_six_fixtures_each() -> void:
	var shop: Node = auto_free(load(Paths.PLACES["shop"]).instantiate())
	add_child(shop)
	await get_tree().process_frame
	for machine in Ids.MACHINES:
		var count := 0
		for fixture in shop.find_children("*", "PartFixture", true, false):
			if (fixture as PartFixture).machine == machine:
				count += 1
		assert_int(count).is_equal(6)
	assert_int(shop.find_children("*", "Hotspot", true, false).size()).is_equal(3)


func test_fixture_flips_when_a_part_is_fixed() -> void:
	var shop: Node = auto_free(load(Paths.PLACES["shop"]).instantiate())
	add_child(shop)
	var target: PartFixture
	for fixture in shop.find_children("*", "PartFixture", true, false):
		if (fixture as PartFixture).machine == MACHINE and (fixture as PartFixture).part == "logic":
			target = fixture
	assert_bool(target.is_fixed()).is_false()
	assert_bool(target.get_node("Broken").visible).is_true()
	Progress.store.record_part_solved(MACHINE, "logic", GameState.device_id, true)
	assert_bool(target.is_fixed()).is_true()
	assert_bool(target.get_node("Fixed").visible).is_true()
	assert_bool(target.get_node("Broken").visible).is_false()


# --- Matching puzzle ---------------------------------------------------------------


func test_matching_solves_with_the_answer() -> void:
	var puzzle := _matching(4)
	var results: Array = []
	puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
	_place_answer(puzzle)
	assert_bool(puzzle.check()).is_true()
	assert_array(results).contains_exactly([true])


func test_matching_wrong_full_placement_emits_nothing() -> void:
	var puzzle := _matching(4)
	var results: Array = []
	puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
	_place_answer(puzzle)
	var answer := PuzzleData.get_answer(MACHINE)
	var items: Array = answer.keys()
	puzzle.place(items[0], answer[items[1]])
	puzzle.place(items[1], answer[items[0]])
	assert_int(puzzle.placement().size()).is_equal(5)
	assert_bool(puzzle.check()).is_false()
	assert_array(results).is_empty()


func test_matching_place_replaces_and_clears() -> void:
	var puzzle := _matching(0)
	puzzle.place("sugar", 1)
	puzzle.place("flour", 1)
	assert_dict(puzzle.placement()).is_equal({"flour": 1})
	puzzle.clear_slot(1)
	assert_dict(puzzle.placement()).is_empty()
	assert_bool(puzzle.check()).is_false()


func test_matching_three_hints_with_four_clues_reveal_without_credit() -> void:
	var puzzle := _matching(4)
	assert_bool(puzzle.can_reveal()).is_true()
	var results: Array = []
	var levels: Array = []
	puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
	puzzle.hint_requested.connect(func(level: int) -> void: levels.append(level))
	puzzle.request_hint()
	puzzle.request_hint()
	assert_array(results).is_empty()
	puzzle.request_hint()
	assert_array(levels).contains_exactly([1, 2, 3])
	assert_array(results).contains_exactly([false])
	assert_bool(MatchingRules.is_solved(puzzle.placement(), PuzzleData.get_answer(MACHINE))).is_true()


func test_matching_hints_stop_at_two_with_fewer_than_four_clues() -> void:
	var puzzle := _matching(3)
	assert_bool(puzzle.can_reveal()).is_false()
	var results: Array = []
	var levels: Array = []
	puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
	puzzle.hint_requested.connect(func(level: int) -> void: levels.append(level))
	for i in 4:
		puzzle.request_hint()
	assert_array(levels).contains_exactly([1, 2, 2, 2])
	assert_array(results).is_empty()


func test_matching_hint_texts() -> void:
	var puzzle := _matching(6)
	assert_str(puzzle.get_hint_text(1)).contains("Start here")
	var first := puzzle.get_hint_text(2)
	assert_str(first).starts_with("A clue says:")
	# Repeats move on to another broken clue.
	assert_str(puzzle.get_hint_text(2)).is_not_equal(first)
	_place_answer(puzzle)
	assert_str(puzzle.get_hint_text(2)).contains("fit")


func test_matching_with_no_clues_points_to_the_teahouse() -> void:
	var puzzle := _matching(0)
	assert_str(puzzle.get_hint_text(1)).contains("Teahouse")
	var labels := puzzle.find_children("*", "Label", true, false)
	var found := false
	for node in labels:
		if (node as Label).text.contains("Teahouse"):
			found = true
	assert_bool(found).is_true()


# --- Helper puzzle and host --------------------------------------------------------


func _helper() -> PuzzleBase:
	var config: Dictionary = PuzzleData.get_part(MACHINE, "helper")["config"]
	var puzzle: PuzzleBase = load("res://scenes/puzzles/helper_puzzle.tscn").instantiate()
	puzzle.puzzle_id = MACHINE + "/helper"
	puzzle.configure(config)
	add_child(auto_free(puzzle))
	return puzzle


func test_helper_wrong_then_right() -> void:
	var puzzle := _helper()
	var results: Array = []
	puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
	assert_bool(puzzle.is_asking()).is_false()
	for i in 10:
		puzzle.advance()
	assert_bool(puzzle.is_asking()).is_true()
	var config: Dictionary = PuzzleData.get_part(MACHINE, "helper")["config"]
	var correct := int(config["correct"])
	puzzle.answer_choice((correct + 1) % config["choices"].size())
	assert_array(results).is_empty()
	puzzle.answer_choice(correct)
	assert_array(results).contains_exactly([true])


func test_helper_hints() -> void:
	var puzzle := _helper()
	var config: Dictionary = PuzzleData.get_part(MACHINE, "helper")["config"]
	assert_str(puzzle.get_hint_text(1)).is_equal(config["nudge"])
	var before: int = puzzle.remaining_choices()
	puzzle.request_hint()
	assert_int(puzzle.remaining_choices()).is_equal(before)
	puzzle.request_hint()
	assert_int(puzzle.remaining_choices()).is_equal(before - 1)


func test_host_turns_a_solve_into_progress_and_a_celebration() -> void:
	for id: String in _all_clue_ids(MACHINE):
		GameState.player.collected_clue_ids.append(id)
	var host := Router.push(Paths.PUZZLE_HOST, {"machine": MACHINE, "part": "logic"})
	await get_tree().process_frame
	var puzzle: PuzzleBase = host.puzzle
	assert_str(puzzle.puzzle_id).is_equal("cookie_machine/logic")
	_place_answer(puzzle)
	puzzle.check()
	await get_tree().process_frame
	assert_int(Progress.store.get_crew_progress(MACHINE)["logic"]).is_equal(1)
	assert_bool(GameState.player.is_part_credited(MACHINE, "logic")).is_true()
	assert_str(Router.top().scene_file_path).is_equal(Paths.MERGE_CELEBRATION)
	assert_int(Router.depth()).is_equal(1)


func test_unbuilt_parts_open_coming_soon() -> void:
	assert_str(Paths.puzzle_scene("not_a_type")).is_equal(Paths.COMING_SOON)
	var host := Router.push(Paths.PUZZLE_HOST, {"machine": MACHINE, "part": "wiring"})
	await get_tree().process_frame
	assert_bool(host.puzzle is PuzzleBase).is_true()
	assert_bool(host.puzzle.can_reveal()).is_false()
	var found := false
	for node in host.puzzle.find_children("*", "Label", true, false):
		if (node as Label).text == "This part is still being built":
			found = true
	assert_bool(found).is_true()


func test_machine_view_counts_parts() -> void:
	var view := Router.push(Paths.MACHINE_VIEW, {"machine": MACHINE})
	await get_tree().process_frame
	var summary := view.content.get_child(0) as Label
	assert_str(summary.text).is_equal("0 of 6 parts working")
	Progress.store.record_part_solved(MACHINE, "logic", GameState.device_id, true)
	assert_str(summary.text).is_equal("1 of 6 parts working")
	for part in Ids.PARTS:
		Progress.store.record_part_solved(MACHINE, part, GameState.device_id, true)
	assert_str(summary.text).is_equal("Running!")


func test_host_restarts_the_ladder_for_an_uncredited_part() -> void:
	GameState.player.hint_levels["cookie_machine/logic"] = 2
	var host := Router.push(Paths.PUZZLE_HOST, {"machine": MACHINE, "part": "logic"})
	await get_tree().process_frame
	assert_int(Hints.level("cookie_machine/logic")).is_equal(0)
	Router.pop()
	GameState.mark_solved(MACHINE, "logic", true)
	GameState.player.hint_levels["cookie_machine/logic"] = 2
	Router.push(Paths.PUZZLE_HOST, {"machine": MACHINE, "part": "logic"})
	await get_tree().process_frame
	assert_int(Hints.level("cookie_machine/logic")).is_equal(2)


func test_host_asks_before_revealing() -> void:
	for id: String in _all_clue_ids(MACHINE):
		GameState.player.collected_clue_ids.append(id)
	var host := Router.push(Paths.PUZZLE_HOST, {"machine": MACHINE, "part": "logic"})
	await get_tree().process_frame
	var hint := _button_with_text(host, "Hint")
	hint.pressed.emit()
	hint.pressed.emit()
	assert_int(Hints.level("cookie_machine/logic")).is_equal(2)
	hint.pressed.emit()
	# Level 3 waits for a confirmation.
	assert_int(Hints.level("cookie_machine/logic")).is_equal(2)
	assert_int(Router.depth()).is_equal(1)
	assert_str(host._hint_label.text).is_equal("Reveal the answer? You will not get credit.")
	_button_with_text(host, "Keep trying").pressed.emit()
	assert_int(Hints.level("cookie_machine/logic")).is_equal(2)
	assert_bool(hint.disabled).is_false()
	hint.pressed.emit()
	_button_with_text(host, "Reveal").pressed.emit()
	await get_tree().process_frame
	assert_str(Router.top().scene_file_path).is_equal(Paths.MERGE_CELEBRATION)
	assert_bool(GameState.player.is_part_solved(MACHINE, "logic")).is_true()
	assert_bool(GameState.player.is_part_credited(MACHINE, "logic")).is_false()


func test_helper_hint_two_is_honest_when_nothing_is_crossed_off() -> void:
	var puzzle := _helper()
	assert_str(puzzle.get_hint_text(2)).not_contains("crossed")
	puzzle.request_hint()
	puzzle.request_hint()
	assert_str(puzzle.get_hint_text(2)).contains("crossed")


func test_reset_keeps_a_remote_store_remote() -> void:
	var local := LocalProgressStore.new(PROGRESS_PATH)
	Progress.set_store(RemoteProgressStore.new("https://example.invalid", local))
	Progress.store.record_part_solved(MACHINE, "logic", GameState.device_id, true)
	Progress.reset()
	assert_bool(Progress.store is RemoteProgressStore).is_true()
	assert_int(Progress.store.get_crew_progress(MACHINE)["logic"]).is_equal(0)
	assert_int((Progress.store as RemoteProgressStore).flush()).is_equal(0)
