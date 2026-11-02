# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Every clue the player has collected, by machine with their crew first.


var _finale_box: VBoxContainer


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
	_finale_box = VBoxContainer.new()
	_finale_box.name = "FinaleNotes"
	_finale_box.add_theme_constant_override("separation", 8)
	list.add_child(_finale_box)
	_refresh_finale()
	Finale.changed.connect(_refresh_finale)
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


## "Handoff notes" on top (each with its handoff word to share), then "The gnu's
## last fortune" once the line has started.
func _refresh_finale() -> void:
	if not is_inside_tree():
		return
	UiKit.clear_children(_finale_box)
	var notes := Finale.held_notes()
	if not notes.is_empty():
		_finale_box.add_child(UiKit.label("Handoff notes", 22))
		for note in notes:
			_finale_box.add_child(_note_card(note))
	if Finale.started():
		_finale_box.add_child(UiKit.label("The gnu's last fortune", 22))
		_finale_box.add_child(UiKit.label(str(Finale.data.readme.get("closing", {}).get("fortune", "")), UiKit.CLUE_SIZE))


func _note_card(note: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Note_" + str(note["id"])
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	card.add_child(inner)
	var title := str(note["title"])
	inner.add_child(UiKit.label(title.substr(0, 1).to_upper() + title.substr(1), UiKit.BODY_SIZE))
	inner.add_child(UiKit.label(str(note["text"]), UiKit.CLUE_SIZE))
	var word := str(note.get("handoff_word", ""))
	if word != "":
		inner.add_child(UiKit.label("Handoff word: %s. Share it with someone from another crew." % word, 26))
	return card
