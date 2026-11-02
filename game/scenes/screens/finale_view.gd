# SPDX-License-Identifier: AGPL-3.0-or-later
extends ScreenBase
## "The line": the finale from a phone (docs/FINALE-DESIGN.md sections 1 and 5).
## Three handoff rows ("<name>: <status>", tap opens HandoffHost), a notes row
## (opens the Archive) and the start-code row. Everything shown follows the
## cached GET /finale: `open`, `line_ready`, `started` and each handoff's
## `available` or waiting state. Polling is on while this screen is on top.

const NO_SCOREBOARD := "The finale is played together on the event scoreboard. Open the game from the event link to join in."
const UNREACHABLE := "The scoreboard can't be reached right now. Showing what this phone last heard."
const BEFORE_OPEN := "The gnu ran the handoffs between his machines by hand and never wrote down how. Once all three machines run, everyone connects them into one line. Opens when they all run"
const READY_TEXT := "The line is ready! The start code is the lucky numbers from the backs of two cookies, Pack A then Pack B."
const NOT_READY_TEXT := "Start code: the line isn't ready yet."
const RUNNING_TEXT := "The line is running!"
const START_RESULTS := {
	FinaleClient.START_WRONG: "Wrong code. Read both cookie backs again.",
	FinaleClient.START_NOT_READY: "The line isn't quite ready yet.",
	FinaleClient.START_STARTED: "The line is running!",
	FinaleClient.START_CLOSED: "The finale hasn't opened yet.",
	FinaleClient.START_OFFLINE: "The scoreboard can't be reached. Try again when you're online.",
	FinaleClient.START_BUSY: "Too many tries at once. Wait a moment and try again.",
}

var _intro: Label
var _unreachable: Label
var _machines: VBoxContainer
var _rows: Dictionary = {}  # handoff id -> Button
var _rows_box: VBoxContainer
var _notes_button: Button
var _crew_word: Label
var _start_box: VBoxContainer
var _start_label: Label
var _keypad: LetterKeypad
var _start_result: Label


func _screen_title() -> String:
	return "The line"


func _build(box: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	_intro = UiKit.label("", UiKit.CLUE_SIZE)
	list.add_child(_intro)
	_unreachable = UiKit.label(UNREACHABLE, 16)
	list.add_child(_unreachable)
	_machines = VBoxContainer.new()
	list.add_child(_machines)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	list.add_child(_rows_box)
	for entry in Finale.data.handoffs:
		var id := str(entry["id"])
		var row := UiKit.button("", Vector2(0, 64))
		row.name = "Row_" + id
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.pressed.connect(_open_handoff.bind(id))
		_rows_box.add_child(row)
		_rows[id] = row
	_notes_button = UiKit.button("", Vector2(0, 64))
	_notes_button.name = "NotesRow"
	_notes_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes_button.pressed.connect(func() -> void: Router.push(Paths.ARCHIVE))
	list.add_child(_notes_button)
	_crew_word = UiKit.label("", UiKit.CLUE_SIZE)
	list.add_child(_crew_word)
	_start_box = VBoxContainer.new()
	_start_box.add_theme_constant_override("separation", 6)
	list.add_child(_start_box)
	_start_label = UiKit.label("", UiKit.CLUE_SIZE)
	_start_box.add_child(_start_label)
	_keypad = load(Paths.LETTER_KEYPAD).instantiate()
	_keypad.max_length = 12
	_keypad.submitted.connect(_on_start_submitted)
	_start_box.add_child(_keypad)
	_start_result = UiKit.label("", UiKit.CLUE_SIZE)
	_start_box.add_child(_start_result)
	Finale.changed.connect(refresh)
	Events.progress_changed.connect(_on_progress_changed)
	refresh()
	_play_elephant()


## Elephant says her piece the first time the finale is seen open.
func _play_elephant() -> void:
	if not Finale.is_open():
		return
	var pieces := Story.unseen("finale_archive", "finale_open")
	if not pieces.is_empty():
		Story.play(self, pieces)


func refresh() -> void:
	if not is_inside_tree():
		return
	var online := Finale.scoreboard_in_use()
	var open := Finale.is_open()
	_intro.visible = true
	_unreachable.visible = online and Finale.client.unreachable()
	_machines.visible = online and not open
	_rows_box.visible = online
	_start_box.visible = online
	if not online:
		_intro.text = NO_SCOREBOARD
	elif not open:
		_intro.text = _before_open_text()
	else:
		_intro.text = RUNNING_TEXT if Finale.started() else "The finale is open: make the line run!"
	_refresh_machines()
	for id: String in _rows:
		(_rows[id] as Button).text = Finale.row_text(id)
	_notes_button.text = "Gnu's notes: %d of %d found (%d needed)" % [Finale.notes_found(), Finale.notes_total(), Finale.notes_needed()]
	var word := Finale.crew_word()
	_crew_word.visible = word != "" and Progress.is_maintainer()
	_crew_word.text = "Your crew's handoff word: %s. Share it!" % word if _crew_word.visible else ""
	_refresh_start()


func _before_open_text() -> String:
	var text := BEFORE_OPEN
	var time := Finale.safety_net_text()
	if time != "" and Finale.open_reason() != "admin_closed":
		text += ", or at %s at the latest" % time
	return text + "."


func _refresh_machines() -> void:
	UiKit.clear_children(_machines)
	if not _machines.visible:
		return
	for machine in Ids.MACHINES:
		var status := "running" if Progress.is_running(machine) else "%d of %d parts working" % [Progress.parts_working(machine), Ids.PARTS.size()]
		_machines.add_child(UiKit.label("%s: %s" % [Ids.machine_title(machine), status], UiKit.CLUE_SIZE))


func _refresh_start() -> void:
	if Finale.started():
		_start_label.text = RUNNING_TEXT
		_keypad.visible = false
		_start_result.visible = false
	elif Finale.line_ready():
		_start_label.text = READY_TEXT
		_keypad.visible = true
		_start_result.visible = true
	else:
		_start_label.text = NOT_READY_TEXT
		_keypad.visible = false
		_start_result.visible = false


func _on_progress_changed(_machine: String) -> void:
	refresh()


func _open_handoff(id: String) -> void:
	Router.push(Paths.HANDOFF_HOST, {"handoff": id})


func _on_start_submitted(code: String) -> void:
	Finale.submit_start(code, _on_start_result)


func _on_start_result(result: String) -> void:
	if not is_inside_tree():
		return
	_start_result.text = str(START_RESULTS.get(result, ""))
	if result == FinaleClient.START_STARTED:
		_keypad.clear()
	refresh()
