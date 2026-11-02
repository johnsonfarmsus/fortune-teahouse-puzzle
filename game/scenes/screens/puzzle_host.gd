# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Runs one puzzle. Reads the part from PuzzleData, loads the puzzle scene for
## its type, wires the header (Back, title, Hint) and turns solved(credited)
## into saved progress and the merge celebration.

var machine: String = ""
var part: String = ""
var puzzle: PuzzleBase

var _hint_button: Button
var _confirm_row: HBoxContainer
var _hint_label: Label
var _slot: Control
var _title: String = ""


func setup(p_args: Dictionary) -> void:
	super(p_args)
	machine = str(p_args.get("machine", ""))
	part = str(p_args.get("part", ""))


func _screen_title() -> String:
	var def := PuzzleData.get_part(machine, part)
	_title = str(def.get("title", Ids.PART_TITLES.get(part, part)))
	return _title


func _build(box: VBoxContainer) -> void:
	_hint_button = UiKit.button("Hint", Vector2(80, 48))
	_hint_button.pressed.connect(_on_hint_pressed)
	header.add_child(_hint_button)
	_hint_label = UiKit.label("", 18)
	_hint_label.visible = false
	box.add_child(_hint_label)
	_confirm_row = HBoxContainer.new()
	_confirm_row.visible = false
	_confirm_row.add_theme_constant_override("separation", 8)
	var sure := UiKit.button("Reveal", Vector2(120, 48))
	sure.pressed.connect(_on_reveal_confirmed)
	var keep := UiKit.button("Keep trying", Vector2(140, 48))
	keep.pressed.connect(func() -> void: _hide_confirm())
	_confirm_row.add_child(sure)
	_confirm_row.add_child(keep)
	box.add_child(_confirm_row)
	_slot = Control.new()
	_slot.name = "PuzzleSlot"
	_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_slot)
	var def := PuzzleData.get_part(machine, part)
	var config: Dictionary = def.get("config", {})
	if config.get("from_puzzle_data", false):
		config = PuzzleData.matching_config(machine, GameState.collected_clue_ids)
	var scene: PackedScene = load(Paths.puzzle_scene(str(def.get("type", ""))))
	puzzle = scene.instantiate() as PuzzleBase
	puzzle.puzzle_id = "%s/%s" % [machine, part]
	# A returning player starts the ladder again, so the first tap is a nudge.
	if not GameState.player.is_part_credited(machine, part):
		Hints.reset(puzzle.puzzle_id)
	puzzle.machine = machine
	puzzle.part = part
	puzzle.configure(config)
	puzzle.solved.connect(_on_solved)
	puzzle.hint_requested.connect(_on_hint_requested)
	puzzle.give_up.connect(func() -> void: Router.pop())
	_slot.add_child(puzzle)
	puzzle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The Gnu's note for this part, once, the first time it is opened.
	var note := Story.next_unseen("puzzle:%s/%s" % [machine, part], "first_visit", {"part": _title, "machine": Ids.machine_title(machine)})
	if not note.is_empty():
		Story.play(self, [note])


func _on_back() -> void:
	if puzzle != null:
		puzzle.quit()
	else:
		Router.pop()


func _on_hint_pressed() -> void:
	if puzzle.next_hint_level() >= HintLadder.MAX_LEVEL:
		_hint_label.visible = true
		_hint_label.text = "Reveal the answer? You will not get credit."
		_confirm_row.visible = true
		_hint_button.disabled = true
	else:
		puzzle.request_hint()


func _on_reveal_confirmed() -> void:
	_hide_confirm()
	puzzle.request_hint()


func _hide_confirm() -> void:
	_confirm_row.visible = false
	_hint_button.disabled = false
	_hint_label.text = ""
	_hint_label.visible = false


func _on_hint_requested(level: int) -> void:
	_hint_label.visible = true
	if level >= HintLadder.MAX_LEVEL:
		_hint_label.text = "Answer revealed. No credit this time."
	else:
		_hint_label.text = puzzle.get_hint_text(level)


func _on_solved(credited: bool) -> void:
	var store := Progress.store
	var was_running := Progress.is_running(machine)
	GameState.mark_solved(machine, part, credited)
	store.record_part_solved(machine, part, GameState.device_id, credited)
	var now_running := Progress.is_running(machine) and not was_running
	Router.replace_top(
		Paths.MERGE_CELEBRATION,
		{"machine": machine, "part": part, "credited": credited, "now_running": now_running}
	)
