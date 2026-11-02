# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Display name, switch crew, sound, source code link and reset.

var _name_label: Label
var _keypad: LetterKeypad
var _crew_buttons: Dictionary = {}
var _confirm_row: HBoxContainer


func _screen_title() -> String:
	return "Menu"


func _build(box: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	_name_label = UiKit.label("", 20)
	list.add_child(_name_label)
	var change := UiKit.button("Change my name", Vector2(0, 48))
	change.pressed.connect(_on_change_name)
	list.add_child(change)
	_keypad = load(Paths.LETTER_KEYPAD).instantiate()
	_keypad.max_length = 20
	_keypad.visible = false
	_keypad.submitted.connect(_on_name_submitted)
	list.add_child(_keypad)

	list.add_child(UiKit.label("Crew", 20))
	var crews := HFlowContainer.new()
	crews.add_theme_constant_override("h_separation", 6)
	crews.add_theme_constant_override("v_separation", 6)
	for machine in Ids.MACHINES:
		var b := UiKit.button(Ids.machine_title(machine), Vector2(110, 48))
		b.pressed.connect(_on_crew.bind(machine))
		crews.add_child(b)
		_crew_buttons[machine] = b
	list.add_child(crews)

	var sound := CheckButton.new()
	sound.text = "Sound"
	sound.custom_minimum_size = Vector2(120, 48)
	sound.focus_mode = Control.FOCUS_NONE
	sound.button_pressed = GameState.sound_on
	sound.toggled.connect(func(on: bool) -> void: GameState.set_sound_on(on))
	list.add_child(sound)

	var source := UiKit.button("Source code (AGPL)", Vector2(0, 48))
	source.pressed.connect(func() -> void: OS.shell_open(Ids.REPO_URL))
	list.add_child(source)

	var reset := UiKit.button("Reset this device", Vector2(0, 48))
	reset.pressed.connect(func() -> void: _confirm_row.visible = true)
	list.add_child(reset)
	_confirm_row = HBoxContainer.new()
	_confirm_row.visible = false
	_confirm_row.add_theme_constant_override("separation", 8)
	var sure := UiKit.button("Yes, reset", Vector2(120, 48))
	sure.pressed.connect(_on_reset)
	var cancel := UiKit.button("Cancel", Vector2(120, 48))
	cancel.pressed.connect(func() -> void: _confirm_row.visible = false)
	_confirm_row.add_child(sure)
	_confirm_row.add_child(cancel)
	var warn := UiKit.label("This forgets your name, clues, crew and solves on this device.", 18)
	list.add_child(warn)
	list.add_child(_confirm_row)
	refresh()


func refresh() -> void:
	var shown := GameState.display_name
	_name_label.text = "Name: %s" % (shown if shown != "" else "Anonymous")
	for machine: String in _crew_buttons:
		var b: Button = _crew_buttons[machine]
		b.text = Ids.machine_title(machine) + (" (yours)" if machine == GameState.crew else "")


func _on_change_name() -> void:
	_keypad.visible = true


func _on_name_submitted(typed: String) -> void:
	GameState.set_display_name(typed)
	_keypad.clear()
	_keypad.visible = false
	refresh()


func _on_crew(machine: String) -> void:
	GameState.choose_crew(machine)
	refresh()


func _on_reset() -> void:
	GameState.reset_device()
	Router.clear()
	Router.go_to_place("town")
