# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ScreenBase
extends Control
## A full-screen, opaque screen on the Router's stack. Router calls setup(args)
## before add_child; _ready builds the UI. Subclasses override _build() and
## _screen_title(). A top-left Back button and ui_cancel call _on_back().

var args: Dictionary = {}
var header: HBoxContainer
var title_label: Label
var back_button: Button
var content: VBoxContainer


func setup(p_args: Dictionary) -> void:
	args = p_args


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = UiKit.BG_COLOR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	back_button = UiKit.button("Back", Vector2(88, 48))
	back_button.pressed.connect(_on_back)
	header.add_child(back_button)
	title_label = UiKit.label(_screen_title(), 22)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)
	content = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	root.add_child(content)
	_build(content)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and Router.top() == self:
		get_viewport().set_input_as_handled()
		_on_back()


## Override: the header title.
func _screen_title() -> String:
	return ""


## Override: fill the content column.
func _build(_content: VBoxContainer) -> void:
	pass


## Override to change what Back does (default pops the screen).
func _on_back() -> void:
	Router.pop()
