# SPDX-License-Identifier: AGPL-3.0-or-later
class_name HintBanner
extends Control
## A dismissible banner for a mentor's nudge (Events.hint_received). Hints that
## arrive while one is showing wait their turn. Nothing times out.

var pending: Array[String] = []
var _panel: PanelContainer
var _title: Label
var _text: Label
var _more: Label
var _dismiss: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.3, 0.42)
	style.border_color = Color(0.95, 0.72, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_right = 1.0
	_panel.offset_left = 8
	_panel.offset_right = -8
	_panel.offset_top = 64
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_title = UiKit.label("Hint from a maintainer", 16)
	box.add_child(_title)
	_text = UiKit.label("", UiKit.CLUE_SIZE)
	box.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_dismiss = UiKit.button("Dismiss", Vector2(110, 48))
	_dismiss.pressed.connect(dismiss)
	row.add_child(_dismiss)
	_more = UiKit.label("", 16)
	_more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_more)
	box.add_child(row)
	Events.hint_received.connect(show_hint)


func show_hint(text: String) -> void:
	if _panel.visible:
		pending.append(text)
	else:
		_present(text)
	_update_more()


func dismiss() -> void:
	if pending.is_empty():
		_panel.visible = false
	else:
		_present(pending.pop_front())
	_update_more()


func is_showing() -> bool:
	return _panel.visible


func current_text() -> String:
	return _text.text


func _present(text: String) -> void:
	_text.text = text
	_panel.visible = true


func _update_more() -> void:
	_more.text = "%d more waiting" % pending.size() if not pending.is_empty() else ""
