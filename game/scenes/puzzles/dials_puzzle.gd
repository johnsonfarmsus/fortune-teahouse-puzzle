# SPDX-License-Identifier: AGPL-3.0-or-later
extends PuzzleBase
## A handoff puzzle (docs/FINALE-DESIGN.md section 3): three dials, a live
## preview and a test button. One dial is one server setting. A test locks every
## dial that is right (emitting setting_set with its setting index) and tells the
## others "too low", "too high" or "wrong". When all are locked the puzzle is
## solved. No timers and no fail state.
## Config: {intro, test_label, preview, hints, dials: [..], locked_indices?}
## (the dial shape is in DialRules). `locked_indices` are settings already set on
## this phone: those dials start locked at their answers.
## Hints: level 1 is hints[0], level 2 the first open dial's hint, level 3
## reveal() locks the rest. Test API: step, set_value, values, locked, test_run.

## A dial was set (right on a test, or revealed). `setting_index` is the server setting.
signal setting_set(setting_index: int)

const LOCKED_TEXT := "Set - OK"

var rules: DialRules

var _config: Dictionary = {}
var _rows: Dictionary = {}  # dial id -> {value, tag, minus, plus}
var _preview: DialPreview
var _test_button: Button
var _marks: Dictionary = {}  # dial id -> last test mark


func configure(config: Dictionary) -> void:
	_config = config
	rules = DialRules.new(config)


func _ready() -> void:
	if rules == null:
		configure({})
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	if str(_config.get("intro", "")) != "":
		box.add_child(UiKit.label(str(_config["intro"]), UiKit.CLUE_SIZE))
	var preview_config: Variant = _config.get("preview")
	if preview_config is Dictionary:
		_preview = DialPreview.new()
		_preview.name = "Preview"
		box.add_child(_preview)
		_preview.setup(rules, preview_config)
	for id in rules.ids():
		box.add_child(_build_dial(id))
	_test_button = UiKit.button(str(_config.get("test_label", "Test")), Vector2(0, 56))
	_test_button.name = "TestButton"
	_test_button.pressed.connect(test_run)
	box.add_child(_test_button)
	_refresh()


func _build_dial(id: String) -> VBoxContainer:
	var dial := rules.dial(id)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(UiKit.label(str(dial.get("label", id)), UiKit.CLUE_SIZE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var minus := UiKit.button("-", Vector2(48, 48))
	minus.name = "Minus_" + id
	minus.pressed.connect(step.bind(id, -1))
	row.add_child(minus)
	var value := UiKit.label("", 22)
	value.name = "Value_" + id
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	var plus := UiKit.button("+", Vector2(48, 48))
	plus.name = "Plus_" + id
	plus.pressed.connect(step.bind(id, 1))
	row.add_child(plus)
	var tag := UiKit.label("", 16)
	tag.name = "Tag_" + id
	column.add_child(tag)
	_rows[id] = {"value": value, "tag": tag, "minus": minus, "plus": plus}
	return column


# --- Test API --------------------------------------------------------------------------


## Moves a dial by `delta` places. Ignored when locked.
func step(id: String, delta: int) -> void:
	if rules.step(id, delta):
		_marks.erase(id)
		_refresh()


## Sets a dial to one of its values (a number, or a package id for a chute).
func set_value(id: String, v: Variant) -> void:
	if rules.set_value(id, v):
		_marks.erase(id)
		_refresh()


## {dial id: current value}
func values() -> Dictionary:
	return rules.values()


## Ids of the locked dials.
func locked() -> Array[String]:
	return rules.locked_ids()


## The test button: locks every right dial (setting_set for each), returns
## {dial id: ok|low|high|wrong}, and finishes when all are locked.
func test_run() -> Dictionary:
	var marks := rules.test()
	_marks = marks
	_refresh()
	for setting in rules.last_locked:
		setting_set.emit(setting)
	if rules.all_locked():
		finish()
	return marks


# --- PuzzleBase ------------------------------------------------------------------------


func get_hint_text(level: int) -> String:
	var hints: Array = _config.get("hints", [])
	if level <= 1:
		return str(hints[0]) if not hints.is_empty() else ""
	var open := rules.first_unlocked()
	if open != "":
		return str(rules.dial(open).get("hint", ""))
	return str(hints[1]) if hints.size() > 1 else ""


func reveal() -> void:
	var revealed := rules.reveal()
	_marks = {}
	_refresh()
	for setting in revealed:
		setting_set.emit(setting)


# --- Drawing ---------------------------------------------------------------------------


func _refresh() -> void:
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		var locked_now := rules.is_locked(id)
		(row["value"] as Label).text = rules.value_text(id)
		(row["minus"] as Button).disabled = locked_now
		(row["plus"] as Button).disabled = locked_now
		var tag := row["tag"] as Label
		if locked_now:
			tag.text = LOCKED_TEXT
		else:
			var mark := str(_marks.get(id, ""))
			tag.text = rules.message(id, mark) if mark != "" else ""
	if _preview != null:
		_preview.refresh()
