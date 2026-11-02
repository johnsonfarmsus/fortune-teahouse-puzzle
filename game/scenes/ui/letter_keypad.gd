# SPDX-License-Identifier: AGPL-3.0-or-later
class_name LetterKeypad
extends VBoxContainer
## An in-game keyboard (A to Z, 0 to 9, Space, Delete, Enter) so the game
## never needs LineEdit or the browser's virtual keyboard. Physical keys work
## too. Used for lucky words and display names.

signal text_changed(text: String)
signal submitted(text: String)

const KEY_SIZE := Vector2(48, 48)
const COLUMNS := 7

@export var max_length: int = 20

var text: String = ""

var _display: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_display = UiKit.label("", 26)
	_display.custom_minimum_size = Vector2(0, 48)
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_display)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(grid)
	for code in range(65, 91):
		grid.add_child(_key(char(code)))
	for code in range(48, 58):
		grid.add_child(_key(char(code)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	add_child(row)
	var space := UiKit.button("Space", KEY_SIZE)
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.pressed.connect(func() -> void: type_char(" "))
	row.add_child(space)
	var delete := UiKit.button("Delete", KEY_SIZE)
	delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete.pressed.connect(delete_last)
	row.add_child(delete)
	var enter := UiKit.button("Enter", KEY_SIZE)
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enter.pressed.connect(submit)
	row.add_child(enter)
	_refresh()


func type_char(ch: String) -> void:
	if text.length() >= max_length:
		return
	text += ch
	_changed()


func delete_last() -> void:
	if text != "":
		text = text.substr(0, text.length() - 1)
		_changed()


func submit() -> void:
	submitted.emit(text)


func clear() -> void:
	text = ""
	_changed()


func _key(ch: String) -> Button:
	var b := UiKit.button(ch, KEY_SIZE)
	b.custom_minimum_size = KEY_SIZE
	b.pressed.connect(func() -> void: type_char(ch))
	return b


func _changed() -> void:
	_refresh()
	text_changed.emit(text)


func _refresh() -> void:
	if _display != null:
		_display.text = text + "_"


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed:
		return
	var key := event as InputEventKey
	if key.keycode == KEY_BACKSPACE:
		delete_last()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		submit()
	elif key.unicode > 0:
		var ch := char(key.unicode).to_upper()
		if ch == " " or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			type_char(ch)
	else:
		return
	get_viewport().set_input_as_handled()
