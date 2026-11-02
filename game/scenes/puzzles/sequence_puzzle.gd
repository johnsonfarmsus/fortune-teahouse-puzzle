# SPDX-License-Identifier: AGPL-3.0-or-later
extends PuzzleBase
## Put steps in order. Tap a step chip to add it to the end of your sequence;
## Undo takes the last one back; tap a step in the sequence to take it out;
## Check tests the order. Steps can also be dragged: a chip onto a row inserts
## it there, a row onto another row moves it. Both routes call the same model
## methods (append, insert, move).
## Config: {steps: [{id, label}], order: [ids], hints: [..], intro (optional)}.
## `order` may leave out decoy steps from `steps`.

const ROW_HEIGHT := 52.0
const CHIP_SIZE := Vector2(150, 52)


## A button that can be dragged.
class DragButton:
	extends Button

	## Shows `label` under the finger while a drag is under way.
	func _show_preview(label: String) -> void:
		var preview := Label.new()
		preview.text = label
		if is_inside_tree() and get_viewport().gui_is_dragging():
			set_drag_preview(preview)
		else:
			preview.free()


## A step in the sequence. Drag it to move it; drop a chip or another row on it
## to put that step here.
class SeqRow:
	extends DragButton
	var index: int = 0
	var step_label: String = ""
	var on_drop: Callable  # (data: Dictionary, to_index: int)

	func _get_drag_data(_at: Vector2) -> Variant:
		_show_preview(step_label)
		return {"seq_index": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data.has("seq_index") or data.has("step"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		on_drop.call(data, index)


## A step waiting in the tray. Drag it into the sequence.
class StepChip:
	extends DragButton
	var step_id: String = ""

	func _get_drag_data(_at: Vector2) -> Variant:
		_show_preview(text)
		return {"step": step_id}


## The sequence list. Dropping on empty space appends or moves to the end.
class DropList:
	extends VBoxContainer
	var on_drop: Callable  # (data: Dictionary, to_index: int)
	var end_index: Callable

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data.has("seq_index") or data.has("step"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		on_drop.call(data, end_index.call())


var _intro: String = ""
var _steps: Array = []
var _order: Array = []
var _hints: Array = []

var _sequence: Array[String] = []
var _chips: Dictionary = {}  # step id -> StepChip
var _list: DropList
var _empty_label: Label
var _undo: Button
var _check: Button
var _feedback: Label


func configure(config: Dictionary) -> void:
	_intro = str(config.get("intro", ""))
	_steps = config.get("steps", [])
	_order = config.get("order", [])
	_hints = config.get("hints", [])


func _ready() -> void:
	var body := ScrollContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(body)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	body.add_child(box)
	if _intro != "":
		box.add_child(UiKit.label(_intro, UiKit.CLUE_SIZE))
	box.add_child(UiKit.label("Tap the steps in order, first step first.", UiKit.CLUE_SIZE))

	box.add_child(UiKit.label("Your order:", 20))
	_list = DropList.new()
	_list.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_list.add_theme_constant_override("separation", 4)
	_list.on_drop = _on_drop
	_list.end_index = func() -> int: return _sequence.size()
	box.add_child(_list)
	_empty_label = UiKit.label("Nothing yet. Tap a step below.", UiKit.CLUE_SIZE)
	box.add_child(_empty_label)

	box.add_child(UiKit.label("Steps:", 20))
	var tray := HFlowContainer.new()
	tray.add_theme_constant_override("h_separation", 6)
	tray.add_theme_constant_override("v_separation", 6)
	box.add_child(tray)
	for step: Dictionary in _steps:
		var chip := StepChip.new()
		chip.step_id = str(step["id"])
		chip.text = str(step.get("label", step["id"]))
		chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		chip.custom_minimum_size = CHIP_SIZE
		chip.focus_mode = Control.FOCUS_NONE
		chip.add_theme_font_size_override("font_size", 18)
		chip.pressed.connect(append.bind(chip.step_id))
		tray.add_child(chip)
		_chips[chip.step_id] = chip

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_undo = UiKit.button("Undo", Vector2(120, 52))
	_undo.pressed.connect(undo)
	buttons.add_child(_undo)
	_check = UiKit.button("Check", Vector2(140, 52))
	_check.pressed.connect(check)
	buttons.add_child(_check)
	_feedback = UiKit.label("", UiKit.CLUE_SIZE)
	box.add_child(_feedback)
	_refresh()


# --- Test API -------------------------------------------------------------


func sequence() -> Array[String]:
	return _sequence.duplicate()


## Adds a step to the end. Unknown steps and steps already used are ignored.
func append(id: String) -> void:
	insert(id, _sequence.size())


## Puts a step at position `at` (0-based), pushing later ones along.
func insert(id: String, at: int) -> void:
	if not _chips.has(id) or _sequence.has(id):
		return
	_sequence.insert(clampi(at, 0, _sequence.size()), id)
	_changed()


## Moves the step at `from` so it ends up at `to`.
func move(from: int, to: int) -> void:
	if from < 0 or from >= _sequence.size():
		return
	var moved := SequenceRules.moved(_sequence, from, to)
	_sequence.assign(moved)
	_changed()


## Takes the step at `index` back out of the sequence.
func remove_at(index: int) -> void:
	if index < 0 or index >= _sequence.size():
		return
	_sequence.remove_at(index)
	_changed()


## Takes the last step back out.
func undo() -> void:
	remove_at(_sequence.size() - 1)


## Returns true and finishes when the order is right.
func check() -> bool:
	if _sequence.size() < _order.size():
		_feedback.text = "Add all %d steps first." % _order.size()
		return false
	if SequenceRules.is_solved(_sequence, _order):
		_feedback.text = "That is the right order. The machine hums."
		finish()
		return true
	_feedback.text = "Not quite. Some steps are out of order. Tap a step to take it out."
	return false


# --- PuzzleBase -----------------------------------------------------------


func get_hint_text(level: int) -> String:
	if level == 1:
		if _hints.size() > 0:
			return str(_hints[0])
		return "Think about what must happen before what."
	var wrong := SequenceRules.first_wrong_index(_sequence, _order)
	if wrong != -1 and wrong < _order.size():
		return "Step %d is: %s" % [wrong + 1, _label_of(str(_order[wrong]))]
	if _hints.size() > 1:
		return str(_hints[1])
	return "The order looks right. Press Check."


func reveal() -> void:
	_sequence.clear()
	for id in _order:
		_sequence.append(str(id))
	_changed()


# --- Display --------------------------------------------------------------


func _label_of(id: String) -> String:
	for step: Dictionary in _steps:
		if str(step.get("id", "")) == id:
			return str(step.get("label", id))
	return id


func _on_drop(data: Dictionary, to_index: int) -> void:
	if data.has("seq_index"):
		# The dragged step takes the place of the row it is dropped on.
		move(int(data["seq_index"]), to_index)
	elif data.has("step"):
		insert(str(data["step"]), to_index)


func _changed() -> void:
	_feedback.text = ""
	_refresh()


func _refresh() -> void:
	UiKit.clear_children(_list)
	for i in _sequence.size():
		var row := SeqRow.new()
		row.index = i
		row.step_label = _label_of(_sequence[i])
		row.text = "%d. %s" % [i + 1, row.step_label]
		row.on_drop = _on_drop
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(UiKit.MIN_TAP, ROW_HEIGHT)
		row.focus_mode = Control.FOCUS_NONE
		row.pressed.connect(remove_at.bind(i))
		_list.add_child(row)
	_empty_label.visible = _sequence.is_empty()
	for id: String in _chips:
		(_chips[id] as Button).visible = not _sequence.has(id)
	_undo.disabled = _sequence.is_empty()
	_check.disabled = _sequence.size() < _order.size()
