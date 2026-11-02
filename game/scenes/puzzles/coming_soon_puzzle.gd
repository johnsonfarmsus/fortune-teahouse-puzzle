# SPDX-License-Identifier: AGPL-3.0-or-later
extends PuzzleBase
## Stands in for puzzle types whose scene does not exist yet (WP4).


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	box.add_child(UiKit.label("This part is still being built", 24))
	var back := UiKit.button("Back", Vector2(120, 56))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(quit)
	box.add_child(back)


func can_reveal() -> bool:
	return false


func get_hint_text(_level: int) -> String:
	return "Nothing to hint at yet."
