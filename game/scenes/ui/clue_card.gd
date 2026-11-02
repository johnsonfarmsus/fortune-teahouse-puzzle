# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ClueCard
extends PanelContainer
## One collected clue: style, the fortune text (18 px or larger) and a
## "Help me read this" button that shows the clue's nudge.

var clue: Dictionary = {}

var _start_here: Label
var _nudge: Label


func setup(p_clue: Dictionary) -> void:
	clue = p_clue


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_start_here = UiKit.label("Start here", UiKit.CLUE_SIZE)
	_start_here.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_start_here.visible = false
	box.add_child(_start_here)
	var style: String = str(clue.get("style", ""))
	box.add_child(UiKit.label(str(Ids.STYLE_LABELS.get(style, style)), UiKit.CLUE_SIZE))
	var text := UiKit.label("%s Lucky word: %s" % [clue.get("fortune_text", ""), clue.get("lucky_word", "")], UiKit.CLUE_SIZE)
	box.add_child(text)
	_nudge = UiKit.label(str(clue.get("nudge", "")), UiKit.CLUE_SIZE)
	_nudge.visible = false
	box.add_child(_nudge)
	var help := UiKit.button("Help me read this", Vector2(0, 48))
	help.pressed.connect(func() -> void: _nudge.visible = not _nudge.visible)
	box.add_child(help)


func mark_start_here(value: bool) -> void:
	if _start_here != null:
		_start_here.visible = value


func is_start_here() -> bool:
	return _start_here != null and _start_here.visible
