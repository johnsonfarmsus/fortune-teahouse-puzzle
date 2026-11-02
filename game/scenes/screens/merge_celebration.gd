# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## "Patch submitted": Crab slides in and merges the fix. A tap skips the
## animation. The first credited solve asks for a display name.

const SLIDE_SECONDS := 1.2

var machine: String = ""
var part: String = ""
var credited: bool = true
var now_running: bool = false

var _crab: Control
var _merged: Label
var _result: VBoxContainer
var _tween: Tween
var _shown: bool = false


func setup(p_args: Dictionary) -> void:
	super(p_args)
	machine = str(p_args.get("machine", ""))
	part = str(p_args.get("part", ""))
	credited = bool(p_args.get("credited", true))
	now_running = bool(p_args.get("now_running", false))


func _screen_title() -> String:
	return "Patch submitted"


func _build(box: VBoxContainer) -> void:
	back_button.visible = false
	var def := PuzzleData.get_part(machine, part)
	var part_title := str(def.get("title", Ids.PART_TITLES.get(part, part)))
	title_label.text = "Patch submitted: %s" % part_title
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 150)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stage)
	_crab = ColorRect.new()
	(_crab as ColorRect).color = Color(0.85, 0.3, 0.25)
	_crab.size = Vector2(120, 90)
	_crab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var crab_label := UiKit.label("Crab", 20)
	crab_label.position = Vector2(34, 30)
	_crab.add_child(crab_label)
	stage.add_child(_crab)
	_merged = UiKit.label("Merged!", 28)
	_merged.position = Vector2(150, 30)
	_merged.modulate.a = 0.0
	stage.add_child(_merged)
	_result = VBoxContainer.new()
	_result.add_theme_constant_override("separation", 8)
	_result.visible = false
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_result)
	_crab.position = Vector2(-140, 30)
	_tween = create_tween()
	_tween.tween_property(_crab, "position:x", 20.0, SLIDE_SECONDS)
	_tween.parallel().tween_property(_merged, "modulate:a", 1.0, SLIDE_SECONDS)
	_tween.tween_callback(_show_result)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not _shown:
		skip()


## Jumps to the end of the animation.
func skip() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_crab.position.x = 20.0
	_merged.modulate.a = 1.0
	_show_result()


func _show_result() -> void:
	if _shown:
		return
	_shown = true
	_result.visible = true
	if not credited:
		_result.add_child(UiKit.label("Crab merged the fix. Solve one yourself to get on the list.", 20))
		_add_list_and_continue()
	elif not GameState.name_asked:
		_ask_name()
	else:
		_add_list_and_continue()


func _ask_name() -> void:
	_result.add_child(UiKit.label("Put your name on the contributors list?", 20))
	var keypad: LetterKeypad = load(Paths.LETTER_KEYPAD).instantiate()
	keypad.max_length = 20
	_result.add_child(keypad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var add := UiKit.button("Add my name", Vector2(150, 48))
	var anon := UiKit.button("Stay anonymous", Vector2(150, 48))
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(add)
	row.add_child(anon)
	_result.add_child(row)
	var done := func(chosen_name: String) -> void:
		if chosen_name.strip_edges() == "":
			GameState.mark_name_asked()
		else:
			GameState.set_display_name(chosen_name)
		UiKit.clear_children(_result)
		_add_list_and_continue()
	add.pressed.connect(func() -> void: done.call(keypad.text))
	keypad.submitted.connect(func(typed: String) -> void: done.call(typed))
	anon.pressed.connect(func() -> void: done.call(""))


func _add_list_and_continue() -> void:
	if now_running:
		_result.add_child(UiKit.label("%s runs!" % Ids.machine_title(machine), 26))
	_result.add_child(UiKit.label("Contributors:", 20))
	var names := Progress.store.get_contributors(machine)
	if names.is_empty():
		_result.add_child(UiKit.label("No names yet.", 18))
	for contributor in names:
		_result.add_child(UiKit.label(contributor, 18))
	var next := UiKit.button("Continue", Vector2(160, 56))
	next.pressed.connect(func() -> void: Router.pop())
	_result.add_child(next)


func _on_back() -> void:
	skip()
