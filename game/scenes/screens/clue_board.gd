# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Every clue the player has collected, by machine with their crew first.


func _screen_title() -> String:
	return "Clues"


func _build(box: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for machine in _machines_crew_first():
		var mine: Array = []
		for clue: Dictionary in PuzzleData.get_clues(machine):
			if GameState.collected_clue_ids.has(clue["id"]):
				mine.append(clue)
		var total := PuzzleData.get_clues(machine).size()
		var heading := "%s: %d of %d, %d needed" % [Ids.machine_title(machine), mine.size(), total, Ids.CLUE_THRESHOLD]
		if machine == GameState.crew:
			heading += " (your crew)"
		list.add_child(UiKit.label(heading, 20))
		for clue: Dictionary in mine:
			var card: ClueCard = load(Paths.CLUE_CARD).instantiate()
			card.setup(clue)
			list.add_child(card)


func _machines_crew_first() -> Array[String]:
	var out: Array[String] = []
	if GameState.crew != "":
		out.append(GameState.crew)
	for machine in Ids.MACHINES:
		if not out.has(machine):
			out.append(machine)
	return out
