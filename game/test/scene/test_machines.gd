# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## Every part of every machine: the configured scene loads with its config,
## has phone-sized buttons and can be driven to solved(true) through its test
## API. Answers are read from the config (or the puzzle data), never hard-coded.


func before_test() -> void:
	GameState.persist = false
	GameState.player = PlayerState.new()
	GameState.player.ensure_device_id()
	Progress.set_store(LocalProgressStore.new("user://test_machines_progress.json"))
	Router.clear()


func after_test() -> void:
	Router.clear()
	if FileAccess.file_exists("user://test_machines_progress.json"):
		DirAccess.remove_absolute("user://test_machines_progress.json")


func _config(machine: String, part: String) -> Dictionary:
	var config: Dictionary = PuzzleData.get_part(machine, part)["config"]
	if config.get("from_puzzle_data", false):
		var ids: Array = []
		for clue: Dictionary in PuzzleData.get_clues(machine):
			ids.append(clue["id"])
		return PuzzleData.matching_config(machine, ids)
	return config


func _make(machine: String, part: String) -> PuzzleBase:
	var def := PuzzleData.get_part(machine, part)
	var puzzle: PuzzleBase = load(Paths.puzzle_scene(str(def["type"]))).instantiate()
	puzzle.puzzle_id = "%s/%s" % [machine, part]
	puzzle.machine = machine
	puzzle.part = part
	Hints.reset(puzzle.puzzle_id)
	puzzle.configure(_config(machine, part))
	if str(def["type"]) == "rhythm":
		puzzle.manual_clock = true
	add_child(auto_free(puzzle))
	return puzzle


## Solves a puzzle through its test API. Returns the result of the final call.
func _drive(machine: String, part: String, puzzle: PuzzleBase) -> void:
	var config := _config(machine, part)
	match str(PuzzleData.get_part(machine, part)["type"]):
		"matching":
			var answer := PuzzleData.get_answer(machine)
			for item: String in answer:
				puzzle.place(item, answer[item])
			puzzle.check()
		"wiring":
			var answer: Dictionary = config["connections"]
			for terminal: String in answer:
				puzzle.tap_terminal(terminal)
				puzzle.tap_socket(answer[terminal])
			puzzle.check()
		"sequence":
			for id: String in config["order"]:
				puzzle.append(id)
			puzzle.check()
		"word":
			for blank: Dictionary in config["blanks"]:
				puzzle.tap_blank(int(blank["index"]))
				puzzle.choose_word(str(blank["answer"]))
			puzzle.check()
		"rhythm":
			for i in int(config["required"]):
				puzzle.advance(puzzle.clock.seconds_to_next_lit_beat())
				puzzle.press()
		"helper":
			for i in (config["lines"] as Array).size():
				puzzle.advance()
			assert_bool(puzzle.is_asking()).is_true()
			puzzle.answer_choice(int(config["correct"]))


func _each_part(callback: Callable) -> void:
	for machine in Ids.MACHINES:
		for part in Ids.PARTS:
			callback.call(machine, part)


func _check_buttons(root: Node, label: String) -> void:
	var buttons := root.find_children("*", "BaseButton", true, false)
	assert_bool(buttons.is_empty()).override_failure_message("%s has no buttons" % label).is_false()
	for node in buttons:
		var b := node as BaseButton
		assert_float(b.custom_minimum_size.x).override_failure_message("%s: %s too narrow" % [label, b.name]).is_greater_equal(44.0)
		assert_float(b.custom_minimum_size.y).override_failure_message("%s: %s too short" % [label, b.name]).is_greater_equal(44.0)


# --- Data shape ----------------------------------------------------------------


func test_every_part_uses_a_real_scene_not_coming_soon() -> void:
	_each_part(
		func(machine: String, part: String) -> void:
			var def := PuzzleData.get_part(machine, part)
			assert_str(str(def["part"])).is_equal(part)
			assert_str(str(def["title"])).is_not_empty()
			var path := Paths.puzzle_scene(str(def["type"]))
			assert_str(path).override_failure_message("%s/%s is coming soon" % [machine, part]).is_not_equal(Paths.COMING_SOON)
	)


func test_every_helper_is_the_machines_named_character() -> void:
	var expected := {"fortune_machine": "Seagull", "cookie_machine": "Penguin", "oven": "Gopher"}
	for machine: String in expected:
		var config := _config(machine, "helper")
		assert_str(str(config["speaker"])).is_equal(expected[machine])


func test_non_matching_parts_have_an_intro_and_two_hints() -> void:
	_each_part(
		func(machine: String, part: String) -> void:
			if part == "logic":
				return
			var config := _config(machine, part)
			if part != "helper":
				assert_str(str(config.get("intro", ""))).override_failure_message("%s/%s intro" % [machine, part]).is_not_empty()
				assert_int((config.get("hints", []) as Array).size()).override_failure_message("%s/%s hints" % [machine, part]).is_equal(2)
				for hint: String in config["hints"]:
					assert_str(hint).is_not_empty()
	)


func test_wiring_labels_are_text_and_every_wire_has_both_ends() -> void:
	for machine in Ids.MACHINES:
		var config := _config(machine, "wiring")
		var terminal_ids: Array = []
		var socket_ids: Array = []
		for def: Dictionary in config["terminals"]:
			terminal_ids.append(def["id"])
			assert_str(str(def["label"])).is_not_empty()
		for def: Dictionary in config["sockets"]:
			socket_ids.append(def["id"])
			assert_str(str(def["label"])).is_not_empty()
		var connections: Dictionary = config["connections"]
		assert_int(connections.size()).is_equal(terminal_ids.size())
		assert_int(socket_ids.size()).is_equal(terminal_ids.size())
		var used: Array = []
		for terminal: String in connections:
			assert_bool(terminal_ids.has(terminal)).is_true()
			assert_bool(socket_ids.has(connections[terminal])).is_true()
			assert_bool(used.has(connections[terminal])).override_failure_message("%s: socket used twice" % machine).is_false()
			used.append(connections[terminal])


func test_sequence_order_uses_known_steps_and_labels_are_unique() -> void:
	for machine in Ids.MACHINES:
		var config := _config(machine, "sequence")
		var ids: Array = []
		var labels: Array = []
		for step: Dictionary in config["steps"]:
			ids.append(step["id"])
			labels.append(step["label"])
		assert_int(ids.size()).is_equal(6)
		for id: String in config["order"]:
			assert_bool(ids.has(id)).is_true()
		assert_int((config["order"] as Array).size()).is_equal(ids.size())
		var unique: Dictionary = {}
		for label: String in labels:
			unique[label] = true
		assert_int(unique.size()).is_equal(labels.size())
		assert_str(str(config["hints"][0])).is_not_empty()


func test_word_blanks_have_one_bank_word_each_and_decoys() -> void:
	for machine in Ids.MACHINES:
		var config := _config(machine, "word")
		var bank: Array = config["bank"]
		var seen: Dictionary = {}
		for word: String in bank:
			assert_bool(seen.has(word.to_lower())).override_failure_message("%s: duplicate bank word %s" % [machine, word]).is_false()
			seen[word.to_lower()] = true
		assert_bool(bank.size() > (config["blanks"] as Array).size()).is_true()
		for blank: Dictionary in config["blanks"]:
			assert_bool(bank.has(blank["answer"])).is_true()
			var marker := "{%d}" % int(blank["index"])
			var lines_with_marker := 0
			for line: String in config["lines"]:
				if line.contains(marker):
					lines_with_marker += 1
			assert_int(lines_with_marker).is_equal(1)


func test_rhythm_configs_are_calm() -> void:
	for machine in Ids.MACHINES:
		var config := _config(machine, "rhythm")
		assert_float(float(config["bpm"])).is_between(70.0, 90.0)
		assert_int(int(config["tolerance_ms"])).is_equal(180)
		assert_int(int(config["required"])).is_equal(6)


func test_helper_question_has_a_valid_correct_choice() -> void:
	for machine in Ids.MACHINES:
		var config := _config(machine, "helper")
		var choices: Array = config["choices"]
		assert_int(choices.size()).is_greater_equal(3)
		assert_int(int(config["correct"])).is_between(0, choices.size() - 1)
		assert_str(str(config["question"])).is_not_empty()
		assert_str(str(config["nudge"])).is_not_empty()
		assert_int((config["lines"] as Array).size()).is_greater_equal(3)


# --- Scenes --------------------------------------------------------------------


func test_every_part_loads_with_big_buttons() -> void:
	_each_part(
		func(machine: String, part: String) -> void:
			var puzzle := _make(machine, part)
			_check_buttons(puzzle, "%s/%s" % [machine, part])
	)


func test_every_part_can_be_solved_with_its_stored_answer() -> void:
	_each_part(
		func(machine: String, part: String) -> void:
			var puzzle := _make(machine, part)
			var results: Array = []
			puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
			_drive(machine, part, puzzle)
			assert_array(results).override_failure_message("%s/%s did not solve once with credit" % [machine, part]).contains_exactly([true])
	)


func test_a_wrong_helper_choice_does_not_solve() -> void:
	for machine in Ids.MACHINES:
		var puzzle := _make(machine, "helper")
		var results: Array = []
		puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
		var config := _config(machine, "helper")
		for i in (config["choices"] as Array).size():
			if i != int(config["correct"]):
				puzzle.answer_choice(i)
		assert_array(results).is_empty()


func test_three_hints_reveal_without_credit_on_the_new_machines() -> void:
	for machine in ["fortune_machine", "oven"]:
		for part in ["wiring", "sequence", "word", "rhythm", "helper"]:
			var puzzle := _make(machine, part)
			var results: Array = []
			puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
			assert_str(puzzle.get_hint_text(1)).is_not_empty()
			puzzle.request_hint()
			puzzle.request_hint()
			assert_str(puzzle.get_hint_text(2)).is_not_empty()
			assert_array(results).is_empty()
			puzzle.request_hint()
			assert_array(results).contains_exactly([false])


func test_puzzle_host_opens_every_part_with_its_scene_type() -> void:
	for machine in Ids.MACHINES:
		for part in Ids.PARTS:
			var host := Router.push(Paths.PUZZLE_HOST, {"machine": machine, "part": part})
			await get_tree().process_frame
			var type := str(PuzzleData.get_part(machine, part)["type"])
			assert_object(host.puzzle).override_failure_message("%s/%s not loaded" % [machine, part]).is_not_null()
			assert_str(host.puzzle.scene_file_path).is_equal(Paths.puzzle_scene(type))
			Router.clear()


# --- Shop ----------------------------------------------------------------------


func test_new_machine_fixtures_have_their_own_labels() -> void:
	var shop: Node = auto_free(load(Paths.PLACES["shop"]).instantiate())
	add_child(shop)
	await get_tree().process_frame
	for fixture in shop.find_children("*", "PartFixture", true, false):
		var f := fixture as PartFixture
		if f.machine == "cookie_machine":
			continue
		assert_str(f.broken_label).override_failure_message("%s/%s broken label" % [f.machine, f.part]).is_not_empty()
		assert_str(f.fixed_label).override_failure_message("%s/%s fixed label" % [f.machine, f.part]).is_not_empty()
		assert_str(f.broken_label).is_not_equal(f.fixed_label)
		assert_str((f.get_node("Broken/Label") as Label).text).is_equal(f.broken_label)
		assert_str((f.get_node("Fixed/Label") as Label).text).is_equal(f.fixed_label)
