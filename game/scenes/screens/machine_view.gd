# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## The six parts of one machine. Each row is a light plus text: Broken (grey),
## Fixed by your crew (amber) or Fixed by you (green). The machine's helper
## speaks when the screen is first opened and after IDLE_SECONDS without input.

const GREY := Color(0.5, 0.5, 0.5)
const AMBER := Color(0.95, 0.72, 0.2)
const GREEN := Color(0.35, 0.8, 0.4)
const IDLE_SECONDS := 20.0

var machine: String = ""
var _summary: Label
var _rows: Dictionary = {}  # part -> {button, light, label}
var _idle_timer: Timer


func setup(p_args: Dictionary) -> void:
	super(p_args)
	machine = str(p_args.get("machine", ""))


func _screen_title() -> String:
	return Ids.machine_title(machine)


func _build(box: VBoxContainer) -> void:
	_summary = UiKit.label("", 22)
	box.add_child(_summary)
	for part in Ids.PARTS:
		var row := UiKit.button("", Vector2(0, 64))
		row.pressed.connect(_on_row_pressed.bind(part))
		var inner := HBoxContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 12
		inner.add_theme_constant_override("separation", 12)
		var light := ColorRect.new()
		light.custom_minimum_size = Vector2(24, 24)
		light.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(light)
		var text := UiKit.label("", 18)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(text)
		row.add_child(inner)
		box.add_child(row)
		_rows[part] = {"light": light, "label": text}
	var crew := UiKit.button("See crew progress", Vector2(0, 48))
	crew.pressed.connect(func() -> void: Router.push(Paths.CREW_PROGRESS, {"machine": machine}))
	box.add_child(crew)
	Events.progress_changed.connect(_on_progress_changed)
	refresh()
	_idle_timer = Timer.new()
	_idle_timer.name = "IdleTimer"
	_idle_timer.one_shot = true
	_idle_timer.wait_time = IDLE_SECONDS
	_idle_timer.timeout.connect(_on_idle)
	add_child(_idle_timer)
	if Story.visit("machine_view:" + machine):
		_helper_speaks()
	else:
		_idle_timer.start()


## Any press or key restarts the wait; a pushed screen on top never gets the line.
func _input(event: InputEvent) -> void:
	if _idle_timer != null and not _idle_timer.is_stopped() and (event is InputEventMouseButton or event is InputEventKey):
		_idle_timer.start()


## Stops the idle line for good (the screen is closing or the player is busy).
func cancel_idle() -> void:
	if _idle_timer != null:
		_idle_timer.stop()


func _on_idle() -> void:
	if Router.top() == self:
		_helper_speaks()
	else:
		_idle_timer.start()


## One of the helper's idle lines in a dialogue box; the wait starts again when it closes.
func _helper_speaks() -> void:
	var line := Story.pick("machine_view:" + machine, "idle")
	if line.is_empty():
		return
	var box := Story.play(self, [line], false)
	box.finished.connect(_idle_timer.start)


func refresh() -> void:
	var progress := Progress.store.get_crew_progress(machine)
	var working := 0
	for part: String in Ids.PARTS:
		var entry: Dictionary = _rows[part]
		var title := _part_title(part)
		var state := "Broken"
		var colour := GREY
		if GameState.player.is_part_credited(machine, part):
			state = "Fixed by you"
			colour = GREEN
			working += 1
		elif int(progress.get(part, 0)) > 0:
			state = "Fixed by your crew"
			colour = AMBER
			working += 1
		(entry["light"] as ColorRect).color = colour
		(entry["label"] as Label).text = "%s: %s" % [title, state]
	if working == Ids.PARTS.size():
		_summary.text = "Running!"
	else:
		_summary.text = "%d of %d parts working" % [working, Ids.PARTS.size()]


func _part_title(part: String) -> String:
	var def := PuzzleData.get_part(machine, part)
	if def.is_empty() or str(def["title"]) == "":
		return str(Ids.PART_TITLES.get(part, part))
	return str(def["title"])


func _on_row_pressed(part: String) -> void:
	Router.push(Paths.PUZZLE_HOST, {"machine": machine, "part": part})


func _on_progress_changed(changed_machine: String) -> void:
	if changed_machine == machine and is_inside_tree():
		refresh()
