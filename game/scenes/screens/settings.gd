# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Display name, switch crew, sound, scoreboard, source code link and reset.

var _name_label: Label
var _keypad: LetterKeypad
var _crew_buttons: Dictionary = {}
var _confirm_row: HBoxContainer
var _board_toggle: CheckButton
var _board_url: Label
var _board_status: Label
var _board_queue: Label
var _sync_button: Button


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

	_build_scoreboard(list)

	var legacy := CheckButton.new()
	legacy.name = "LegacyScreens"
	legacy.text = "Old screens (debug)"
	legacy.custom_minimum_size = Vector2(200, 48)
	legacy.focus_mode = Control.FOCUS_NONE
	legacy.button_pressed = DebugSettings.legacy_screens()
	legacy.toggled.connect(_on_legacy_toggled)
	list.add_child(legacy)
	list.add_child(UiKit.label("The old menu-style town and machine screens, kept until the adventure replaces them.", UiKit.CLUE_SIZE))

	var about := Story.pick("settings", "always")
	if not about.is_empty():
		list.add_child(UiKit.label("About", 20))
		list.add_child(UiKit.label(str(about["text"]), UiKit.CLUE_SIZE))
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
	_refresh_scoreboard()


func _build_scoreboard(list: VBoxContainer) -> void:
	list.add_child(UiKit.label("Scoreboard", 20))
	_board_toggle = CheckButton.new()
	_board_toggle.text = "Use scoreboard"
	_board_toggle.custom_minimum_size = Vector2(200, 48)
	_board_toggle.focus_mode = Control.FOCUS_NONE
	_board_toggle.button_pressed = Progress.scoreboard_enabled
	_board_toggle.disabled = not Progress.scoreboard_available()
	_board_toggle.toggled.connect(_on_board_toggled)
	list.add_child(_board_toggle)
	_board_url = UiKit.label("", UiKit.CLUE_SIZE)
	list.add_child(_board_url)
	_board_status = UiKit.label("", UiKit.CLUE_SIZE)
	list.add_child(_board_status)
	_sync_button = UiKit.button("Sync now", Vector2(0, 48))
	_sync_button.pressed.connect(_on_sync)
	list.add_child(_sync_button)
	_board_queue = UiKit.label("", UiKit.CLUE_SIZE)
	list.add_child(_board_queue)
	Events.scoreboard_status_changed.connect(_refresh_scoreboard)


func _refresh_scoreboard() -> void:
	if _board_status == null or not is_inside_tree():
		return
	if Progress.scoreboard_available():
		_board_url.text = "Address: " + Progress.scoreboard_url
	else:
		_board_url.text = "Address: none set"
	if not Progress.scoreboard_available():
		_board_status.text = "No scoreboard is set up. This phone plays on its own."
	elif not Progress.scoreboard_enabled:
		_board_status.text = "Off. This phone plays on its own."
	elif Progress.store.is_online():
		_board_status.text = "Online"
	else:
		_board_status.text = "Offline. Updates wait here and send when it is back."
	var waiting := Progress.queue_size()
	_board_queue.text = "Waiting to send: %d" % waiting
	_sync_button.disabled = not Progress.scoreboard_active()


func _on_board_toggled(on: bool) -> void:
	Progress.use_scoreboard(on)
	_refresh_scoreboard()


func _on_sync() -> void:
	Progress.sync_now()
	_refresh_scoreboard()


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


## Forgets this device. The old screens go back to their town; the adventure
## restarts in the Teahouse, where a new player meets the lucky-word entry.
func _on_reset() -> void:
	GameState.reset_device()
	Router.clear()
	if DebugSettings.legacy_screens():
		Router.go_to_place("town")
		return
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene != null and scene.scene_file_path == Paths.MAIN:
		get_tree().reload_current_scene()


## Switches between the adventure layer and the old screens, then restarts the
## main scene (the start tap is not asked for again).
func _on_legacy_toggled(on: bool) -> void:
	DebugSettings.set_legacy_screens(on)
	if not is_inside_tree() or get_tree().current_scene == null or get_tree().current_scene.scene_file_path != Paths.MAIN:
		return
	Router.clear()
	get_tree().reload_current_scene()
