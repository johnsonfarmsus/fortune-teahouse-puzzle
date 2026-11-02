# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Runs one puzzle. Reads the part from PuzzleData, loads the puzzle scene for
## its type, wires the header (Back, title, Hint) and turns solved(credited)
## into saved progress and the merge celebration.

var machine: String = ""
var part: String = ""
var puzzle: PuzzleBase

var _hint_button: Button
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
	_hint_button.pressed.connect(func() -> void: puzzle.request_hint())
	header.add_child(_hint_button)
	_hint_label = UiKit.label("", 18)
	_hint_label.visible = false
	box.add_child(_hint_label)
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
	puzzle.machine = machine
	puzzle.part = part
	puzzle.configure(config)
	puzzle.solved.connect(_on_solved)
	puzzle.hint_requested.connect(_on_hint_requested)
	puzzle.give_up.connect(func() -> void: Router.pop())
	_slot.add_child(puzzle)
	puzzle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_back() -> void:
	if puzzle != null:
		puzzle.quit()
	else:
		Router.pop()


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
