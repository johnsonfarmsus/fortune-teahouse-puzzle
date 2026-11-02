# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## Runs one finale puzzle. args {handoff: id} hosts a handoff's `dials` puzzle
## behind the finale's gates (docs/FINALE-DESIGN.md section 3); args {twin: note
## id} hosts the in-game twin of one of the gnu's notes (a `helper` puzzle) once
## the finale is open. Wires the header (Back, title, Hint) the way PuzzleHost
## does, but nothing here is credited: settings are progress for everyone.

var handoff_id: String = ""
var twin_id: String = ""
var puzzle: PuzzleBase

var _hint_button: Button
var _confirm_row: HBoxContainer
var _hint_label: Label
var _counts: Label
var _gate: Label
var _slot: Control
var _done_box: VBoxContainer
var _done_label: Label
var _title: String = ""


func setup(p_args: Dictionary) -> void:
	super(p_args)
	handoff_id = str(p_args.get("handoff", ""))
	twin_id = str(p_args.get("twin", ""))


func _screen_title() -> String:
	if twin_id != "":
		_title = "Ask %s" % str(Finale.data.gnu_note(twin_id).get("twin", {}).get("speaker", "Elephant"))
	else:
		_title = str(Finale.data.handoff(handoff_id).get("title", handoff_id))
	return _title


func _build(box: VBoxContainer) -> void:
	_hint_button = UiKit.button("Hint", Vector2(80, 48))
	_hint_button.pressed.connect(_on_hint_pressed)
	header.add_child(_hint_button)
	_counts = UiKit.label("", 18)
	box.add_child(_counts)
	_gate = UiKit.label("", UiKit.CLUE_SIZE)
	box.add_child(_gate)
	_hint_label = UiKit.label("", 18)
	_hint_label.visible = false
	box.add_child(_hint_label)
	_confirm_row = HBoxContainer.new()
	_confirm_row.visible = false
	_confirm_row.add_theme_constant_override("separation", 8)
	var sure := UiKit.button("Reveal", Vector2(120, 48))
	sure.pressed.connect(_on_reveal_confirmed)
	var keep := UiKit.button("Keep trying", Vector2(140, 48))
	keep.pressed.connect(func() -> void: _hide_confirm())
	_confirm_row.add_child(sure)
	_confirm_row.add_child(keep)
	box.add_child(_confirm_row)
	_slot = Control.new()
	_slot.name = "PuzzleSlot"
	_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_slot)
	_done_box = VBoxContainer.new()
	_done_box.visible = false
	_done_box.add_theme_constant_override("separation", 8)
	box.add_child(_done_box)
	_done_label = UiKit.label("", 20)
	_done_box.add_child(_done_label)
	var next := UiKit.button("Continue", Vector2(0, 56))
	next.name = "ContinueButton"
	next.pressed.connect(func() -> void: Router.pop())
	_done_box.add_child(next)
	Finale.changed.connect(refresh)
	refresh()
	if is_connected_handoff():
		_show_done()


## True when every setting of this handoff is already set on this phone.
func is_connected_handoff() -> bool:
	return handoff_id != "" and Finale.settings_on_phone(handoff_id).size() >= Finale.settings_total(handoff_id)


## The message that blocks the puzzle, or "" when it can be played.
func gate_text() -> String:
	if twin_id != "":
		return "" if Finale.is_open() else "The finale hasn't opened yet."
	return Finale.gate_message(handoff_id)


func refresh() -> void:
	if not is_inside_tree():
		return
	if handoff_id != "":
		_counts.text = (
			"Settings set by everyone: %d of %d. On this phone: %d of %d."
			% [
				Finale.settings_everyone(handoff_id),
				Finale.settings_total(handoff_id),
				Finale.settings_on_phone(handoff_id).size(),
				Finale.settings_total(handoff_id),
			]
		)
	_counts.visible = handoff_id != ""
	var gate := gate_text()
	_gate.text = gate
	_gate.visible = gate != ""
	_hint_button.disabled = gate != "" or _done_box.visible
	if gate == "":
		if puzzle == null:
			_start_puzzle()
	elif puzzle != null:
		puzzle.queue_free()
		puzzle = null


func _start_puzzle() -> void:
	var type := "helper"
	var config: Dictionary = {}
	if twin_id != "":
		config = Finale.data.gnu_note(twin_id).get("twin", {}).get("config", {}).duplicate(true)
		puzzle = load(Paths.puzzle_scene(type)).instantiate() as PuzzleBase
		puzzle.puzzle_id = "finale/" + twin_id
	else:
		var entry := Finale.data.handoff(handoff_id)
		type = str(entry.get("type", "dials"))
		config = entry.get("config", {}).duplicate(true)
		config["locked_indices"] = Finale.settings_on_phone(handoff_id)
		puzzle = load(Paths.puzzle_scene(type)).instantiate() as PuzzleBase
		puzzle.puzzle_id = "finale/" + handoff_id
	# Opening again starts the ladder from a nudge, as PuzzleHost does.
	Hints.reset(puzzle.puzzle_id)
	puzzle.configure(config)
	puzzle.solved.connect(_on_solved)
	puzzle.hint_requested.connect(_on_hint_requested)
	puzzle.give_up.connect(func() -> void: Router.pop())
	if puzzle.has_signal("setting_set"):
		puzzle.connect("setting_set", _on_setting_set)
	_slot.add_child(puzzle)
	puzzle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_setting_set(setting_index: int) -> void:
	Finale.add_setting(handoff_id, setting_index)
	refresh()


func _on_solved(credited: bool) -> void:
	# A revealed twin files nothing: otherwise k of N could be reached without
	# finding a single note. Only a solve of your own counts.
	if twin_id != "" and credited:
		Finale.collect_gnu_note(twin_id)
	_show_done(credited)


func _show_done(credited: bool = true) -> void:
	if twin_id != "" and not credited:
		_done_label.text = "Elephant smiles. Find the real note, or solve it yourself."
	elif twin_id != "":
		_done_label.text = "Elephant files it. Thank you!"
	else:
		_done_label.text = "%s: connected on this phone. Elephant adds a page to the README." % _title
	_done_box.visible = true
	_hint_button.disabled = true
	_hide_confirm()
	_hint_label.visible = false
	if twin_id != "" and not credited:
		return
	var line := Story.pick("finale_archive", "handoff_solved" if twin_id == "" else "note_found")
	if not line.is_empty():
		Story.play(self, [line], false)


func _on_back() -> void:
	if puzzle != null and not _done_box.visible:
		puzzle.quit()
	else:
		Router.pop()


func _on_hint_pressed() -> void:
	if puzzle == null:
		return
	if puzzle.next_hint_level() >= HintLadder.MAX_LEVEL:
		_hint_label.visible = true
		_hint_label.text = "Reveal the answer? You will not get credit."
		_confirm_row.visible = true
		_hint_button.disabled = true
	else:
		puzzle.request_hint()


func _on_reveal_confirmed() -> void:
	_hide_confirm()
	puzzle.request_hint()


func _hide_confirm() -> void:
	_confirm_row.visible = false
	_hint_button.disabled = gate_text() != "" or _done_box.visible
	_hint_label.text = ""
	_hint_label.visible = false


func _on_hint_requested(level: int) -> void:
	_hint_label.visible = true
	if level >= HintLadder.MAX_LEVEL:
		_hint_label.text = "Answer revealed. No credit this time."
	else:
		_hint_label.text = puzzle.get_hint_text(level)
