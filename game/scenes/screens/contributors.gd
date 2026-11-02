# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Names that fixed each machine. With a `machine` arg only that machine shows.


func _screen_title() -> String:
	return "Contributors"


func _build(box: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
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
