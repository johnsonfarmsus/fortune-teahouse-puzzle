# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Elephant's Archive (docs/FINALE-DESIGN.md section 4): type the code from one
## of the gnu's notes, see the six slots, ask a helper for a note's in-game twin
## once the finale is open, and read the README so far. Codes are checked here,
## from game data, so they work offline and early.

const ELEPHANT := "I keep the town's records. The gnu left notes all over the place. Bring me any you find."
const PROMPT := "Type the code from one of the gnu's notes."

var _counts: Label
var _result: Label
var _keypad: LetterKeypad
var _slots: VBoxContainer


func _screen_title() -> String:
	return "Archive"


func _build(box: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var elephant := UiKit.label("Elephant: " + ELEPHANT, UiKit.CLUE_SIZE)
	elephant.name = "ElephantLine"
	list.add_child(elephant)
	_counts = UiKit.label("", UiKit.CLUE_SIZE)
	list.add_child(_counts)
	list.add_child(UiKit.label(PROMPT, UiKit.CLUE_SIZE))
	_result = UiKit.label("", UiKit.CLUE_SIZE)
	_result.custom_minimum_size = Vector2(0, 52)
	list.add_child(_result)
	_keypad = load(Paths.LETTER_KEYPAD).instantiate()
	_keypad.max_length = 20
	_keypad.submitted.connect(_on_submitted)
	list.add_child(_keypad)
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override("separation", 8)
	list.add_child(_slots)
	var readme := UiKit.button("README so far", Vector2(0, 56))
	readme.name = "ReadmeButton"
	readme.pressed.connect(func() -> void: Router.push(Paths.README_SCREEN))
	list.add_child(readme)
	Finale.changed.connect(refresh)
	refresh()
	_play_elephant("first_visit")


func _play_elephant(when: String) -> void:
	var pieces := Story.unseen("finale_archive", when)
	if not pieces.is_empty():
		Story.play(self, pieces)


func refresh() -> void:
	if not is_inside_tree():
		return
	_counts.text = (
		"Notes found by everyone: %d of %d (%d needed). On this phone: %d."
		% [Finale.notes_found(), Finale.notes_total(), Finale.notes_needed(), Finale.state.gnu_notes.size()]
	)
	UiKit.clear_children(_slots)
	for entry in Finale.data.gnu_notes:
		_slots.add_child(_slot_for(entry))


func _slot_for(entry: Dictionary) -> VBoxContainer:
	var id := str(entry["id"])
	var speaker := str(entry["twin"]["speaker"])
	var slot := VBoxContainer.new()
	slot.name = "Slot_" + id
	slot.add_theme_constant_override("separation", 4)
	var label := UiKit.label("", UiKit.CLUE_SIZE)
	slot.add_child(label)
	if Finale.state.has_gnu_note(id):
		label.text = str(entry["text"])
		return slot
	label.text = "Somewhere at the venue, or ask %s." % speaker
	if Finale.is_open():
		var ask := UiKit.button("Ask %s" % speaker, Vector2(0, 48))
		ask.name = "Ask_" + id
		ask.pressed.connect(ask_twin.bind(id))
		slot.add_child(ask)
	return slot


## Opens the in-game twin of a note (a helper puzzle) once the finale is open.
func ask_twin(note_id: String) -> void:
	if Finale.is_open():
		Router.push(Paths.HANDOFF_HOST, {"twin": note_id})


## The line Elephant says for a Finale.CODE_* result.
func result_text(result: int) -> String:
	if result == Finale.CODE_FILED:
		return "Elephant files it. Thank you!"
	if result == Finale.CODE_FILED_EARLY:
		return "Elephant files it. It goes in when the finale opens."
	if result == Finale.CODE_HAVE:
		return "Elephant already has that one."
	return "That isn't one of the gnu's notes. Check the code."


func _on_submitted(code: String) -> void:
	var result := Finale.enter_code(code)
	_result.text = result_text(result)
	if result != Finale.CODE_INVALID:
		_keypad.clear()
	if result == Finale.CODE_FILED or result == Finale.CODE_FILED_EARLY:
		var line := Story.pick("finale_archive", "note_found")
		if not line.is_empty():
			Story.play(self, [line], false)
