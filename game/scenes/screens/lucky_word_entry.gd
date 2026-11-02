# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Type the lucky word from a fortune cookie. Players with no cookie can pick a crew.

var _result: Label
var _keypad: LetterKeypad


func _screen_title() -> String:
	return "Lucky word"


func _build(box: VBoxContainer) -> void:
	box.add_child(UiKit.label("Type the lucky word from your fortune cookie.", 18))
	_result = UiKit.label("", 18)
	_result.custom_minimum_size = Vector2(0, 52)
	box.add_child(_result)
	_keypad = load(Paths.LETTER_KEYPAD).instantiate()
	_keypad.max_length = 20
	_keypad.submitted.connect(_on_submitted)
	box.add_child(_keypad)
	box.add_child(UiKit.label("No cookie? Choose a crew:", 18))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for machine in Ids.MACHINES:
		var b := UiKit.button(Ids.machine_title(machine), Vector2(110, 48))
		b.pressed.connect(_on_crew_chosen.bind(machine))
		row.add_child(b)
	box.add_child(row)
	_red_panda_speaks()


## Red Panda greets a first visit with the welcome. After that she speaks only
## when the player's situation changes: no crew, then a crew, then a machine that runs.
func _red_panda_speaks() -> void:
	var extra := {}
	var state := "has_crew"
	if GameState.crew == "":
		state = "no_crew"
	elif Progress.is_running(GameState.crew):
		state = "machine_running:crew"
		extra["machine"] = Ids.machine_title(GameState.crew)
	var changed := Story.state_changed("lucky_word_entry", state)
	var welcome := Story.unseen("lucky_word_entry", "first_visit", extra)
	if not welcome.is_empty():
		Story.play(self, welcome)
	elif changed:
		var line := Story.pick("lucky_word_entry", state, extra)
		if not line.is_empty():
			Story.play(self, [line])


func _on_submitted(word: String) -> void:
	var result := GameState.enter_lucky_word(word)
	match result:
		PlayerState.UNKNOWN:
			_on_unknown_word(word)
		PlayerState.ALREADY_HAVE:
			_result.text = "You already have that clue."
			_keypad.clear()
		PlayerState.COLLECTED:
			_result.text = "Clue collected! See it under Clues."
			_keypad.clear()
		PlayerState.COLLECTED_JOINED:
			_result.text = "Clue collected! You joined the %s crew." % Ids.machine_title(GameState.crew)
			_keypad.clear()


## Not a lucky word: it may be a handoff word from a crew's note, or from the gnu's notes.
func _on_unknown_word(word: String) -> void:
	var found := Finale.collect_word(word)
	if found == Finale.WORD_COLLECTED:
		_result.text = "Handoff note collected! See it under Clues."
		_keypad.clear()
	elif found == Finale.WORD_HAVE:
		_result.text = "You already have that note."
		_keypad.clear()
	else:
		_result.text = "That word is not on any cookie we know. Check the spelling. If it's from one of the gnu's notes, take it to Elephant at the Archive."


func _on_crew_chosen(machine: String) -> void:
	GameState.choose_crew(machine)
	_result.text = "You joined the %s crew." % Ids.machine_title(machine)
