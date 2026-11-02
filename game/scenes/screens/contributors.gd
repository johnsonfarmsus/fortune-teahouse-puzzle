# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Names that fixed each machine. With a `machine` arg only that machine shows.

var _box: VBoxContainer


func _screen_title() -> String:
	return "Contributors"


func _build(box: VBoxContainer) -> void:
	_box = box
	Progress.refresh_contributors()  # one look at the scoreboard when it is on
	Events.progress_changed.connect(_on_progress_changed)
	_fill()
	Story.play(self, Story.unseen("contributors", "first_visit"))  # Crab on the Pier, once


func _on_progress_changed(_machine: String) -> void:
	if is_inside_tree():
		_fill()


func _fill() -> void:
	UiKit.clear_children(_box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var wanted: Array = Ids.MACHINES
	if args.has("machine"):
		wanted = [args["machine"]]
	for machine: String in wanted:
		list.add_child(UiKit.label(Ids.machine_title(machine), 22))
		var names := Progress.store.get_contributors(machine)
		if names.is_empty():
			list.add_child(UiKit.label("No names yet. Fix a part to be first.", 18))
		for contributor in names:
			list.add_child(UiKit.label(contributor, 18))
