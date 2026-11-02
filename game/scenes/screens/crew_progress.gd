# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## One crew's progress: the six parts with how many crewmates fixed each, the
## "Machine runs!" state and the contributors. Online it shows the whole crew
## from the scoreboard; offline it shows this phone only. Maintainers (their
## crew's machine runs) can also send another crew a nudge.

const GREY := Color(0.5, 0.5, 0.5)
const AMBER := Color(0.95, 0.72, 0.2)
const GREEN := Color(0.35, 0.8, 0.4)
const OFFLINE_LINE := "Offline, showing this phone only"
const ONLINE_LINE := "Online, showing your whole crew"

var machine: String = ""
var target_crew: String = ""
var nudge_ids: Array[String] = []

var _status: Label
var _connection: Label
var _queue_line: Label
var _rows: Dictionary = {}  # part -> {light, label}
var _contributors: VBoxContainer
var _nudge_box: VBoxContainer
var _nudge_key := ""
var _nudge_serial := 0
var _nudge_result: Label
var _target_buttons: Dictionary = {}


func setup(p_args: Dictionary) -> void:
	super(p_args)
	machine = str(p_args.get("machine", GameState.crew))
	if not Ids.MACHINES.has(machine):
		machine = Ids.MACHINES[0]


func _screen_title() -> String:
	return "Crew: " + Ids.machine_title(machine)


func _build(box: VBoxContainer) -> void:
	_status = UiKit.label("", 24)
	box.add_child(_status)
	_connection = UiKit.label("", 18)
	box.add_child(_connection)
	_queue_line = UiKit.label("", 18)
	box.add_child(_queue_line)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for part in Ids.PARTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.custom_minimum_size = Vector2(0, 48)
		var light := ColorRect.new()
		light.custom_minimum_size = Vector2(24, 24)
		light.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(light)
		var text := UiKit.label("", UiKit.BODY_SIZE)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(text)
		list.add_child(row)
		_rows[part] = {"light": light, "label": text}

	list.add_child(UiKit.label("Contributors", 22))
	_contributors = VBoxContainer.new()
	_contributors.add_theme_constant_override("separation", 4)
	list.add_child(_contributors)

	_nudge_box = VBoxContainer.new()
	_nudge_box.add_theme_constant_override("separation", 8)
	list.add_child(_nudge_box)

	Events.progress_changed.connect(_on_changed)
	Events.scoreboard_status_changed.connect(_refresh)
	_refresh()


func _on_changed(changed_machine: String) -> void:
	if changed_machine == machine and is_inside_tree():
		_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	var online := Progress.scoreboard_active() and Progress.store.is_online()
	var progress := Progress.store.get_crew_progress(machine)
	var working := 0
	for part: String in Ids.PARTS:
		var count := int(progress.get(part, 0))
		var entry: Dictionary = _rows[part]
		var state := "Broken"
		var colour := GREY
		if GameState.player.is_part_credited(machine, part):
			colour = GREEN
		elif count > 0:
			colour = AMBER
		if count > 0:
			working += 1
			if GameState.player.is_part_credited(machine, part):
				# Green: the words say who, so colour is never the only cue.
				var others := count - 1
				if online and others > 0:
					state = "fixed by you and %d other%s" % [others, "" if others == 1 else "s"]
				else:
					state = "fixed by you"
			elif online:
				state = "fixed by %d crewmate%s" % [count, "" if count == 1 else "s"]
			else:
				state = "fixed on this phone"
		(entry["light"] as ColorRect).color = colour
		(entry["label"] as Label).text = "%s: %s" % [_part_title(part), state]
	if working == Ids.PARTS.size():
		_status.text = "Machine runs!"
	else:
		_status.text = "%d of %d parts working" % [working, Ids.PARTS.size()]
	_connection.text = ONLINE_LINE if online else OFFLINE_LINE
	var waiting := Progress.queue_size()
	_queue_line.text = "%d update%s waiting to send" % [waiting, "" if waiting == 1 else "s"] if waiting > 0 else ""
	_queue_line.visible = waiting > 0
	_fill_contributors()
	_refresh_nudge_section(online)


func _fill_contributors() -> void:
	UiKit.clear_children(_contributors)
	var lines: Array[String] = []
	if Progress.scoreboard_active():
		for entry in (Progress.store as RemoteProgressStore).get_contributor_entries(machine):
			lines.append(str(entry["name"]) + (" (mentor)" if entry["via"] == "mentor" else ""))
	else:
		lines.assign(Progress.store.get_contributors(machine))
	if lines.is_empty():
		_contributors.add_child(UiKit.label("No names yet. Fix a part to be first.", UiKit.CLUE_SIZE))
	for line in lines:
		_contributors.add_child(UiKit.label(line, UiKit.CLUE_SIZE))


func _part_title(part: String) -> String:
	var def := PuzzleData.get_part(machine, part)
	if def.is_empty() or str(def["title"]) == "":
		return str(Ids.PART_TITLES.get(part, part))
	return str(def["title"])


# --- Maintainer: send a nudge --------------------------------------------------------


func _refresh_nudge_section(online: bool) -> void:
	var maintainer := Progress.is_maintainer()
	var key := "%s:%s" % [maintainer, online]
	if key == _nudge_key:
		return
	_nudge_key = key
	_nudge_serial += 1  # answers still on their way for the old section are now stale
	UiKit.clear_children(_nudge_box)
	_target_buttons = {}
	if not maintainer:
		return
	_nudge_box.add_child(UiKit.label("Send a nudge", 22))
	if not online:
		_nudge_box.add_child(UiKit.label("Your crew's machine runs. Connect to the scoreboard to help another crew.", UiKit.CLUE_SIZE))
		return
	_nudge_box.add_child(UiKit.label("Your crew's machine runs. Pick a crew to help, then a nudge.", UiKit.CLUE_SIZE))
	var crews := HFlowContainer.new()
	crews.add_theme_constant_override("h_separation", 6)
	crews.add_theme_constant_override("v_separation", 6)
	for other in Ids.MACHINES:
		if other == GameState.crew:
			continue
		var b := UiKit.button(Ids.machine_title(other), Vector2(120, 48))
		b.pressed.connect(choose_target.bind(other))
		crews.add_child(b)
		_target_buttons[other] = b
		if target_crew == "":
			target_crew = other
	_nudge_box.add_child(crews)
	_nudge_result = UiKit.label("", UiKit.CLUE_SIZE)
	_nudge_box.add_child(_nudge_result)
	_update_target_buttons()
	var store := Progress.store as RemoteProgressStore
	store.fetch_nudge_ids(_on_nudge_ids.bind(_nudge_serial))


func choose_target(crew: String) -> void:
	target_crew = crew
	_update_target_buttons()


func _update_target_buttons() -> void:
	for crew: String in _target_buttons:
		(_target_buttons[crew] as Button).text = Ids.machine_title(crew) + (" (selected)" if crew == target_crew else "")


func _on_nudge_ids(ok: bool, ids: Array[String], serial: int) -> void:
	# An answer for an older section (rebuilt since) is dropped, so buttons never double up.
	if not is_inside_tree() or _nudge_result == null or serial != _nudge_serial:
		return
	if not ok:
		_nudge_result.text = "Could not load the nudges. Try again in a moment."
		_nudge_key = ""  # try again on the next refresh
		return
	nudge_ids = ids
	for id in ids:
		var b := UiKit.button(Nudges.label(id), Vector2(0, 48))
		b.pressed.connect(send_nudge.bind(id))
		_nudge_box.add_child(b)


## Posts the nudge to the chosen crew. Public so tests can drive it.
func send_nudge(nudge_id: String) -> void:
	if target_crew == "" or not Progress.scoreboard_active():
		return
	_nudge_result.text = "Sending..."
	(Progress.store as RemoteProgressStore).send_nudge(target_crew, nudge_id, _on_nudge_sent)


func _on_nudge_sent(_ok: bool, message: String) -> void:
	if is_inside_tree() and _nudge_result != null:
		_nudge_result.text = message
