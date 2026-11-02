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


func _on_submitted(word: String) -> void:
	var result := GameState.enter_lucky_word(word)
	match result:
		PlayerState.UNKNOWN:
			_result.text = "That word is not on any cookie we know. Check the spelling."
		PlayerState.ALREADY_HAVE:
			_result.text = "You already have that clue."
			_keypad.clear()
		PlayerState.COLLECTED:
			_result.text = "Clue collected! See it under Clues."
			_keypad.clear()
		PlayerState.COLLECTED_JOINED:
			_result.text = "Clue collected! You joined the %s crew." % Ids.machine_title(GameState.crew)
			_keypad.clear()


func _on_crew_chosen(machine: String) -> void:
	GameState.choose_crew(machine)
	_result.text = "You joined the %s crew." % Ids.machine_title(machine)
