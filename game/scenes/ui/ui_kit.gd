# SPDX-License-Identifier: AGPL-3.0-or-later
class_name UiKit
extends RefCounted
## Small builders so code-built screens follow the phone rules: tap targets of
## at least 44x44 and readable text.

const MIN_TAP := 44.0
const BODY_SIZE := 20
const CLUE_SIZE := 18
const BG_COLOR := Color(0.16, 0.115, 0.09)


static func button(text: String, min_size: Vector2 = Vector2(44, 48)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(maxf(min_size.x, MIN_TAP), maxf(min_size.y, MIN_TAP))
	b.focus_mode = Control.FOCUS_NONE
	return b


static func label(text: String, font_size: int = BODY_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	return l


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
