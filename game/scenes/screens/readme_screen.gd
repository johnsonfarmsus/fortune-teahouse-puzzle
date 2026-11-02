# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## "README so far" (docs/FINALE-DESIGN.md section 5): the gnu's README, written
## by everyone. A section appears when its trigger holds (a machine runs, a
## handoff is connected). Once the line has started the closing shows, with the
## names of everyone who fixed a machine.

const EMPTY_TEXT := "Nothing is written yet. Fix a machine to start the README."

var _list: VBoxContainer


func _screen_title() -> String:
	return "README"


func _build(box: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	Finale.changed.connect(refresh)
	Events.progress_changed.connect(_on_progress_changed)
	Progress.refresh_contributors()
	refresh()


func _on_progress_changed(_machine: String) -> void:
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	UiKit.clear_children(_list)
	var readme: Dictionary = Finale.data.readme
	_list.add_child(UiKit.label(str(readme.get("title", "README")), 24))
	_list.add_child(UiKit.label(str(readme.get("subtitle", "")), UiKit.CLUE_SIZE))
	var sections := Finale.readme_sections()
	if sections.is_empty():
		_list.add_child(UiKit.label(EMPTY_TEXT, UiKit.CLUE_SIZE))
	for section in sections:
		var heading := UiKit.label(str(section["heading"]), 20)
		heading.add_theme_color_override("font_color", Color(0.95, 0.72, 0.2))
		_list.add_child(heading)
		_list.add_child(UiKit.label(str(section["body"]), UiKit.CLUE_SIZE))
	if Finale.started():
		var closing: Dictionary = readme.get("closing", {})
		var heading := UiKit.label(str(closing.get("heading", "")), 20)
		heading.add_theme_color_override("font_color", Color(0.95, 0.72, 0.2))
		_list.add_child(heading)
		_list.add_child(UiKit.label(str(closing.get("line", "")), UiKit.CLUE_SIZE))
		for person in Finale.contributor_names():
			_list.add_child(UiKit.label(person, UiKit.CLUE_SIZE))
