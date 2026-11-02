# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## Scene tests for the four WP4 puzzle components, configured from the real
## Cookie Machine data. Answers are read from the config, never hard-coded.

const MACHINE := "cookie_machine"


func before_test() -> void:
	GameState.persist = false
	Finale.set_client(null)
	Finale.set_state(FinaleState.new(""))  # never touch user://finale.json
	GameState.player = PlayerState.new()
	GameState.player.ensure_device_id()
	Router.clear()


func after_test() -> void:
	Router.clear()


func _config(part: String) -> Dictionary:
	return PuzzleData.get_part(MACHINE, part)["config"]


func _make(part: String, config: Dictionary = {}) -> PuzzleBase:
	var def := PuzzleData.get_part(MACHINE, part)
	var puzzle: PuzzleBase = load(Paths.puzzle_scene(str(def["type"]))).instantiate()
	puzzle.puzzle_id = "%s/%s" % [MACHINE, part]
	puzzle.machine = MACHINE
	puzzle.part = part
	Hints.reset(puzzle.puzzle_id)
	puzzle.configure(config if not config.is_empty() else def["config"])
	if part == "rhythm":
		puzzle.manual_clock = true
	add_child(auto_free(puzzle))
	return puzzle


func _results(puzzle: PuzzleBase) -> Array:
	var results: Array = []
	puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
	return results


func _check_buttons(root: Node, label: String) -> void:
	var buttons := root.find_children("*", "BaseButton", true, false)
	assert_bool(buttons.is_empty()).override_failure_message("%s has no buttons" % label).is_false()
	for node in buttons:
		var b := node as BaseButton
		assert_float(b.custom_minimum_size.x).override_failure_message("%s: %s too narrow" % [label, b.name]).is_greater_equal(44.0)
		assert_float(b.custom_minimum_size.y).override_failure_message("%s: %s too short" % [label, b.name]).is_greater_equal(44.0)


func _button_with_text(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node
	return null


# --- All four ------------------------------------------------------------------


func test_all_four_are_found_by_naming_convention() -> void:
	for type in ["wiring", "sequence", "word", "rhythm"]:
		assert_str(Paths.puzzle_scene(type)).is_equal("res://scenes/puzzles/%s_puzzle.tscn" % type)


func test_all_four_instantiate_with_big_buttons_and_a_scroll_container() -> void:
	for part in ["wiring", "sequence", "word", "rhythm"]:
		var puzzle := _make(part)
		_check_buttons(puzzle, part)
		var scrolls := puzzle.find_children("*", "ScrollContainer", true, false)
		assert_int(scrolls.size()).is_equal(1)
		# The content never needs more than a phone's width.
		var content := (scrolls[0] as ScrollContainer).get_child(0) as Control
		assert_float(content.get_combined_minimum_size().x).override_failure_message("%s too wide" % part).is_less_equal(390.0)
		assert_bool(puzzle.can_reveal()).is_true()


func test_every_hint_level_has_text() -> void:
	for part in ["wiring", "sequence", "word", "rhythm"]:
		var puzzle := _make(part)
		assert_str(puzzle.get_hint_text(1)).is_not_empty()
		assert_str(puzzle.get_hint_text(2)).is_not_empty()


func test_three_hints_reveal_without_credit() -> void:
	for part in ["wiring", "sequence", "word", "rhythm"]:
		var puzzle := _make(part)
		var results := _results(puzzle)
		puzzle.request_hint()
		puzzle.request_hint()
		assert_array(results).is_empty()
		puzzle.request_hint()
		assert_array(results).contains_exactly([false])


func test_cookie_machine_parts_use_the_new_scenes() -> void:
	for part in ["wiring", "sequence", "word", "rhythm"]:
		var def := PuzzleData.get_part(MACHINE, part)
		assert_str(Paths.puzzle_scene(str(def["type"]))).is_not_equal(Paths.COMING_SOON)
		assert_bool((def["config"] as Dictionary).is_empty()).is_false()


# --- Wiring --------------------------------------------------------------------


func _wire_answer(puzzle: PuzzleBase) -> void:
	var answer: Dictionary = _config("wiring")["connections"]
	for terminal: String in answer:
		puzzle.tap_terminal(terminal)
		puzzle.tap_socket(answer[terminal])


func test_wiring_labels_carry_the_meaning_not_just_colour() -> void:
	var config := _config("wiring")
	for def: Dictionary in config["terminals"] + config["sockets"]:
		assert_str(str(def["label"])).is_not_empty()
		assert_str(str(def["color"])).is_not_empty()
	var puzzle := _make("wiring")
	# Every wire appears as text in the list once made.
	_wire_answer(puzzle)
	var texts: Array = []
	for b in puzzle.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	var first: String = config["connections"].keys()[0]
	var socket: String = config["connections"][first]
	var row := "%s -> %s" % [_label_of(config["terminals"], first), _label_of(config["sockets"], socket)]
	assert_bool(texts.has(row)).is_true()


func test_wiring_solves_with_the_answer() -> void:
	var puzzle := _make("wiring")
	var results := _results(puzzle)
	_wire_answer(puzzle)
	assert_dict(puzzle.wires()).is_equal(_config("wiring")["connections"])
	assert_bool(puzzle.check()).is_true()
	assert_array(results).contains_exactly([true])


func test_wiring_wrong_and_partial_emit_nothing() -> void:
	var puzzle := _make("wiring")
	var results := _results(puzzle)
	assert_bool(puzzle.check()).is_false()
	var answer: Dictionary = _config("wiring")["connections"]
	var terminals: Array = answer.keys()
	puzzle.connect_wire(terminals[0], answer[terminals[0]])
	assert_bool(puzzle.check()).is_false()  # partial
	for t: String in terminals:
		puzzle.connect_wire(t, answer[t])
	puzzle.connect_wire(terminals[0], answer[terminals[1]])
	puzzle.connect_wire(terminals[1], answer[terminals[0]])
	assert_int(puzzle.wires().size()).is_equal(terminals.size())
	assert_bool(puzzle.check()).is_false()  # swapped
	assert_array(results).is_empty()


func _label_of(list: Array, id: String) -> String:
	for def: Dictionary in list:
		if def["id"] == id:
			return str(def["label"])
	return id


func test_wiring_tap_flow_and_removal() -> void:
	var puzzle := _make("wiring")
	var config := _config("wiring")
	var answer: Dictionary = config["connections"]
	var t: Array = answer.keys()
	var s0: String = answer[t[0]]
	var s1: String = answer[t[1]]
	puzzle.tap_terminal(t[0])
	puzzle.tap_socket(s0)
	assert_dict(puzzle.wires()).is_equal({t[0]: s0})
	# Socket first, then terminal, also works.
	puzzle.tap_socket(s1)
	puzzle.tap_terminal(t[1])
	assert_dict(puzzle.wires()).is_equal({t[0]: s0, t[1]: s1})
	# Re-using a socket moves the wire.
	puzzle.connect_wire(t[2], s0)
	assert_dict(puzzle.wires()).is_equal({t[1]: s1, t[2]: s0})
	puzzle.remove_wire(t[2])
	assert_dict(puzzle.wires()).is_equal({t[1]: s1})
	# The list row removes a wire when tapped.
	var row := "%s -> %s" % [_label_of(config["terminals"], t[1]), _label_of(config["sockets"], s1)]
	_button_with_text(puzzle, row).pressed.emit()
	assert_dict(puzzle.wires()).is_empty()


func test_wiring_tapping_the_drawn_wire_removes_it() -> void:
	var puzzle := _make("wiring")
	var answer: Dictionary = _config("wiring")["connections"]
	var t: Array = answer.keys()
	puzzle.connect_wire(t[0], answer[t[0]])
	puzzle.connect_wire(t[1], answer[t[1]])
	await get_tree().process_frame
	await get_tree().process_frame
	var segments: Array = puzzle._segments()
	assert_int(segments.size()).is_equal(2)
	var first: Dictionary = segments.filter(func(s: Dictionary) -> bool: return s["id"] == t[0])[0]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = (first["from"] as Vector2).lerp(first["to"], 0.5)
	puzzle._canvas._gui_input(click)
	assert_dict(puzzle.wires()).is_equal({t[1]: answer[t[1]]})
	# A tap far from every wire does nothing.
	click.position = Vector2(-500, -500)
	puzzle._canvas._gui_input(click)
	assert_dict(puzzle.wires()).is_equal({t[1]: answer[t[1]]})


func test_wiring_hints_and_reveal() -> void:
	var puzzle := _make("wiring")
	var config := _config("wiring")
	assert_str(puzzle.get_hint_text(1)).is_equal(config["hints"][0])
	# Hint 2 names one wire that is not right yet.
	assert_str(puzzle.get_hint_text(2)).starts_with("Wire \"")
	puzzle.reveal()
	assert_dict(puzzle.wires()).is_equal(config["connections"])
	assert_str(puzzle.get_hint_text(2)).is_equal(config["hints"][1])


# --- Sequence ------------------------------------------------------------------


func _order_answer(puzzle: PuzzleBase) -> void:
	for id: String in _config("sequence")["order"]:
		puzzle.append(id)


func test_sequence_solves_with_the_order() -> void:
	var puzzle := _make("sequence")
	var results := _results(puzzle)
	_order_answer(puzzle)
	assert_array(puzzle.sequence()).contains_exactly(_config("sequence")["order"])
	assert_bool(puzzle.check()).is_true()
	assert_array(results).contains_exactly([true])


func test_sequence_chip_buttons_append_in_tap_order() -> void:
	var puzzle := _make("sequence")
	var config := _config("sequence")
	var first: Dictionary = config["steps"][0]
	_button_with_text(puzzle, str(first["label"])).pressed.emit()
	assert_array(puzzle.sequence()).contains_exactly([first["id"]])


func test_sequence_wrong_and_partial_emit_nothing() -> void:
	var puzzle := _make("sequence")
	var results := _results(puzzle)
	var order: Array = _config("sequence")["order"]
	puzzle.append(order[0])
	assert_bool(puzzle.check()).is_false()  # partial
	for id: String in order.slice(1):
		puzzle.append(id)
	puzzle.move(0, 1)  # first two swapped
	assert_bool(puzzle.check()).is_false()
	assert_array(results).is_empty()


func test_sequence_undo_and_remove() -> void:
	var puzzle := _make("sequence")
	var order: Array = _config("sequence")["order"]
	puzzle.append(order[0])
	puzzle.append(order[1])
	puzzle.append(order[1])  # already used: ignored
	puzzle.append("nope")
	assert_int(puzzle.sequence().size()).is_equal(2)
	puzzle.undo()
	assert_array(puzzle.sequence()).contains_exactly([order[0]])
	puzzle.undo()
	puzzle.undo()  # nothing left: safe
	assert_array(puzzle.sequence()).is_empty()


func test_sequence_drag_calls_the_same_model_methods() -> void:
	var puzzle := _make("sequence")
	var order: Array = _config("sequence")["order"]
	for id: String in order:
		puzzle.append(id)
	# Drag the first row onto the third: it takes that place.
	var rows := puzzle.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return "step_label" in b)
	assert_int(rows.size()).is_equal(order.size())
	var data: Variant = rows[0]._get_drag_data(Vector2.ZERO)
	assert_bool(rows[2]._can_drop_data(Vector2.ZERO, data)).is_true()
	rows[2]._drop_data(Vector2.ZERO, data)
	var expected := order.duplicate()
	expected.remove_at(0)
	expected.insert(2, order[0])
	assert_array(puzzle.sequence()).contains_exactly(expected)
	assert_bool(rows[0]._can_drop_data(Vector2.ZERO, "not a drag")).is_false()


func test_sequence_chip_drag_inserts_at_the_row() -> void:
	var puzzle := _make("sequence")
	var order: Array = _config("sequence")["order"]
	puzzle.append(order[1])
	puzzle.append(order[2])
	var chips := puzzle.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return "step_id" in b and b.step_id == order[0])
	var data: Variant = chips[0]._get_drag_data(Vector2.ZERO)
	assert_dict(data).is_equal({"step": order[0]})
	var rows := puzzle.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return "step_label" in b)
	rows[0]._drop_data(Vector2.ZERO, data)
	assert_array(puzzle.sequence()).contains_exactly([order[0], order[1], order[2]])


func test_sequence_hints_and_reveal() -> void:
	var puzzle := _make("sequence")
	var config := _config("sequence")
	var order: Array = config["order"]
	assert_str(puzzle.get_hint_text(1)).is_equal(config["hints"][0])
	assert_str(puzzle.get_hint_text(2)).starts_with("Step 1 is:")
	puzzle.append(order[1])
	assert_str(puzzle.get_hint_text(2)).starts_with("Step 1 is:")
	puzzle.reveal()
	assert_array(puzzle.sequence()).contains_exactly(order)
	assert_str(puzzle.get_hint_text(2)).is_equal(config["hints"][1])


# --- Word ----------------------------------------------------------------------


func _fill_answer(puzzle: PuzzleBase) -> void:
	for blank: Dictionary in _config("word")["blanks"]:
		puzzle.tap_blank(int(blank["index"]))
		puzzle.choose_word(str(blank["answer"]))


func test_word_note_is_a_four_line_rhyme_with_a_bank_of_decoys() -> void:
	var config := _config("word")
	assert_int(config["lines"].size()).is_equal(4)
	assert_bool(config["bank"].size() > config["blanks"].size()).is_true()
	for blank: Dictionary in config["blanks"]:
		assert_bool(config["bank"].has(blank["answer"])).is_true()


func test_word_solves_with_the_answers() -> void:
	var puzzle := _make("word")
	var results := _results(puzzle)
	_fill_answer(puzzle)
	assert_bool(puzzle.check()).is_true()
	assert_array(results).contains_exactly([true])


func test_word_wrong_and_partial_emit_nothing() -> void:
	var puzzle := _make("word")
	var results := _results(puzzle)
	var blanks: Array = _config("word")["blanks"]
	puzzle.fill(int(blanks[0]["index"]), blanks[0]["answer"])
	assert_bool(puzzle.check()).is_false()  # partial
	for i in blanks.size():  # every word shifted one blank along
		puzzle.fill(int(blanks[i]["index"]), blanks[(i + 1) % blanks.size()]["answer"])
	assert_bool(puzzle.check()).is_false()
	assert_array(results).is_empty()


func test_word_tap_blank_then_word_and_clear() -> void:
	var puzzle := _make("word")
	var blanks: Array = _config("word")["blanks"]
	var i0 := int(blanks[0]["index"])
	var i1 := int(blanks[1]["index"])
	var a0: String = blanks[0]["answer"]
	var a1: String = blanks[1]["answer"]
	puzzle.tap_blank(i1)
	assert_int(puzzle.selected_blank()).is_equal(i1)
	puzzle.choose_word(a1)
	assert_dict(puzzle.filled()).is_equal({i1: a1})
	assert_int(puzzle.selected_blank()).is_equal(-1)
	# A used word cannot go in a second blank.
	puzzle.fill(i0, a1)
	assert_dict(puzzle.filled()).is_equal({i1: a1})
	# Tapping a filled blank clears it.
	puzzle.tap_blank(i1)
	assert_dict(puzzle.filled()).is_empty()
	# With nothing selected a word goes in the first empty blank.
	puzzle.choose_word(a0)
	assert_dict(puzzle.filled()).is_equal({i0: a0})


func test_word_hints_and_reveal() -> void:
	var puzzle := _make("word")
	var config := _config("word")
	assert_str(puzzle.get_hint_text(1)).is_equal(config["hints"][0])
	assert_str(puzzle.get_hint_text(2)).starts_with("Blank %d" % (int(config["blanks"][0]["index"]) + 1))
	puzzle.reveal()
	assert_bool(WordRules.is_solved(puzzle.filled(), config["blanks"])).is_true()
	assert_str(puzzle.get_hint_text(2)).is_equal(config["hints"][1])


# --- Rhythm --------------------------------------------------------------------


func _play_row(puzzle: PuzzleBase, presses: int) -> void:
	for i in presses:
		puzzle.advance(puzzle.clock.seconds_to_next_lit_beat())
		puzzle.press()


func test_rhythm_uses_the_configured_clock() -> void:
	var puzzle := _make("rhythm")
	var config := _config("rhythm")
	assert_float(puzzle.clock.bpm).is_equal(float(config["bpm"]))
	assert_int(puzzle.clock.required).is_equal(int(config["required"]))
	assert_float(puzzle.clock.tolerance).is_equal_approx(float(config["tolerance_ms"]) / 1000.0, 0.0001)
	assert_array(puzzle.clock.pattern).contains_exactly(config["pattern"])


func test_rhythm_defaults_apply() -> void:
	var puzzle := _make("rhythm", {"bpm": 100, "hints": ["a", "b"]})
	assert_array(puzzle.clock.pattern).contains_exactly([1, 0, 1, 1])
	assert_int(puzzle.clock.required).is_equal(6)
	assert_float(puzzle.clock.tolerance).is_equal_approx(0.18, 0.0001)


func test_rhythm_solves_after_the_required_on_beat_presses() -> void:
	var puzzle := _make("rhythm")
	var results := _results(puzzle)
	var required: int = int(_config("rhythm")["required"])
	_play_row(puzzle, required - 1)
	assert_array(results).is_empty()
	assert_int(puzzle.streak()).is_equal(required - 1)
	_play_row(puzzle, 1)
	assert_array(results).contains_exactly([true])


func test_rhythm_off_beat_resets_but_never_fails() -> void:
	var puzzle := _make("rhythm")
	var results := _results(puzzle)
	_play_row(puzzle, 3)
	assert_int(puzzle.streak()).is_equal(3)
	puzzle.advance(puzzle.clock.interval() * 0.5)  # halfway between beats
	assert_bool(puzzle.press()).is_false()
	assert_int(puzzle.streak()).is_equal(0)
	assert_array(results).is_empty()
	# And it can still be solved afterwards.
	_play_row(puzzle, int(_config("rhythm")["required"]))
	assert_array(results).contains_exactly([true])


func test_rhythm_hint_two_slows_the_tempo_by_a_quarter() -> void:
	var puzzle := _make("rhythm")
	var bpm: float = puzzle.clock.bpm
	puzzle.request_hint()
	assert_float(puzzle.clock.bpm).is_equal(bpm)
	assert_str(puzzle.get_hint_text(1)).is_equal(_config("rhythm")["hints"][0])
	puzzle.request_hint()
	assert_float(puzzle.clock.bpm).is_equal_approx(bpm * 0.75, 0.0001)


func test_rhythm_reveal_lights_the_whole_row() -> void:
	var puzzle := _make("rhythm")
	var results := _results(puzzle)
	puzzle.request_hint()
	puzzle.request_hint()
	puzzle.request_hint()
	assert_bool(puzzle.clock.is_solved()).is_true()
	assert_array(results).contains_exactly([false])
