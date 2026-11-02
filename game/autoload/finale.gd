# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Thin Node over FinaleData, FinaleState and FinaleClient (docs/FINALE-DESIGN.md).
## Registered after Progress. It owns the finale's state (user://finale.json),
## the scoreboard client (only when a scoreboard is configured and on), a 1 s
## Timer that drives the client, and the hooks that give out handoff notes:
## a crew's note when its machine runs (or on joining a running crew), Gopher's
## slip once the finale is open. It also raises the Story flags `finale_open`
## and `line_running`. Screens read everything through the methods below.

signal changed  ## notes, settings, gnu notes or the cached finale changed

enum { WORD_UNKNOWN, WORD_COLLECTED, WORD_HAVE }
enum { CODE_INVALID, CODE_FILED, CODE_FILED_EARLY, CODE_HAVE }

const STATE_PATH := "user://finale.json"
const TICK_SECONDS := 1.0
const WATCHED_SCREENS: Array[String] = [Paths.FINALE_VIEW, Paths.HANDOFF_HOST, Paths.ARCHIVE]

var persist: bool = true  # tests turn this off before touching state
var transport_override: Callable = Callable()  # tests inject a fake network here
var data: FinaleData
var state: FinaleState
var client: FinaleClient  # null while no scoreboard is in use

var _transport: HttpTransport
var _tick: Timer


func _ready() -> void:
	data = FinaleData.new()
	set_state(FinaleState.new(STATE_PATH if persist else ""))
	_tick = Timer.new()
	_tick.wait_time = TICK_SECONDS
	_tick.autostart = true
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	Events.machine_running.connect(func(_machine: String) -> void: sync_notes())
	Events.progress_changed.connect(func(_machine: String) -> void: sync_notes())
	Events.crew_changed.connect(_on_identity_changed)
	Events.display_name_changed.connect(_on_identity_changed)
	Events.scoreboard_status_changed.connect(_rebuild_client)
	_rebuild_client()
	sync_notes()
	_connect_router.call_deferred()


## Swaps the state (tests use an in-memory one) and rewires the client to it.
func set_state(new_state: FinaleState) -> void:
	if state != null and state.changed.is_connected(_on_state_changed):
		state.changed.disconnect(_on_state_changed)
	state = new_state
	state.changed.connect(_on_state_changed)
	if client != null:
		var url := client.base_url
		_drop_client()
		_make_client(url)
	_sync_flags()
	changed.emit()


## Swaps the client (tests inject one built on a fake transport).
func set_client(new_client: FinaleClient) -> void:
	_drop_client()
	client = new_client
	if client != null:
		client.finale_changed.connect(_on_cache_changed)
		_identify()


## "Reset this device": forgets notes, settings, found gnu notes, the queue and the cache.
func reset() -> void:
	state.reset()
	sync_notes()


# --- The scoreboard ----------------------------------------------------------------------


## True when a scoreboard is in use, so the finale can be played together.
func scoreboard_in_use() -> bool:
	return client != null


func _wanted_url() -> String:
	if Progress.scoreboard_url == "" or not Progress.scoreboard_enabled:
		return ""
	return Progress.scoreboard_url.strip_edges().rstrip("/")


func _rebuild_client() -> void:
	var url := _wanted_url()
	if url == "":
		if client != null:
			_drop_client()
		return
	if client != null and client.base_url == url:
		return
	_drop_client()
	_make_client(url)


func _make_client(url: String) -> void:
	var send := transport_override if transport_override.is_valid() else Progress.transport_override
	if not send.is_valid():
		if _transport == null:
			_transport = HttpTransport.new()
			_transport.name = "HttpTransport"
			add_child(_transport)
		send = Callable(_transport, "request")
	set_client(FinaleClient.new(url, state, send))
	client.refresh()  # one look at boot, and when the scoreboard is switched on


func _drop_client() -> void:
	if client == null:
		return
	if client.finale_changed.is_connected(_on_cache_changed):
		client.finale_changed.disconnect(_on_cache_changed)
	client.retire()
	client = null


func _identify() -> void:
	if client != null:
		client.set_identity(GameState.device_id, GameState.crew, GameState.display_name)


func _on_identity_changed(_value: String) -> void:
	_identify()
	sync_notes()


func _on_tick() -> void:
	if client != null:
		client.tick()


func _connect_router() -> void:
	if not Router.stack_changed.is_connected(_on_stack_changed):
		Router.stack_changed.connect(_on_stack_changed)


## Poll only while the finale view, a handoff or the archive is on top.
func _on_stack_changed(_depth: int) -> void:
	if client == null:
		return
	var top := Router.top()
	client.set_watching(top != null and WATCHED_SCREENS.has(top.scene_file_path))


func _on_cache_changed() -> void:
	sync_notes()


func _on_state_changed() -> void:
	_sync_flags()
	changed.emit()


func _sync_flags() -> void:
	Story.set_flag("finale_open", is_open())
	Story.set_flag("line_running", started())


# --- What the scoreboard last said ---------------------------------------------------------


func info() -> Dictionary:
	return state.cache


func is_open() -> bool:
	return bool(state.cache.get("open", false))


func line_ready() -> bool:
	return bool(state.cache.get("line_ready", false))


func started() -> bool:
	return bool(state.cache.get("started", false))


func open_reason() -> String:
	return str(state.cache.get("open_reason", "closed"))


func handoff_info(handoff_id: String) -> Dictionary:
	for entry: Variant in state.cache.get("handoffs", []):
		if entry is Dictionary and str(entry.get("id", "")) == handoff_id:
			return entry
	return {}


func handoff_available(handoff_id: String) -> bool:
	return is_open() and bool(handoff_info(handoff_id).get("available", false))


## Machines a handoff waits for: the ones it touches that are not running.
func waiting_machines(handoff_id: String) -> Array[String]:
	var out: Array[String] = []
	var entry := handoff_info(handoff_id)
	for key in ["from_machine", "to_machine"]:
		var machine := str(entry.get(key, ""))
		if Ids.MACHINES.has(machine) and not Progress.is_running(machine) and not out.has(Ids.machine_title(machine)):
			out.append(Ids.machine_title(machine))
	return out


## "<name>: <status>" for a handoff row.
func row_text(handoff_id: String) -> String:
	var title := str(data.handoff(handoff_id).get("title", handoff_id))
	var entry := handoff_info(handoff_id)
	if not is_open():
		entry = {"status": "locked"}
	return "%s: %s" % [title, FinaleData.row_status(entry, waiting_machines(handoff_id))]


## Settings set by everyone, as far as this phone knows (its own count if higher).
func settings_everyone(handoff_id: String) -> int:
	return maxi(int(handoff_info(handoff_id).get("settings_solved", 0)), settings_on_phone(handoff_id).size())


func settings_on_phone(handoff_id: String) -> Array[int]:
	return state.settings_for(handoff_id)


func settings_total(handoff_id: String) -> int:
	return int(handoff_info(handoff_id).get("settings_total", FinaleData.SETTINGS_PER_HANDOFF))


## True when every setting is set on this phone or the server says it is connected.
func handoff_connected(handoff_id: String) -> bool:
	if bool(handoff_info(handoff_id).get("complete", false)):
		return true
	return settings_on_phone(handoff_id).size() >= settings_total(handoff_id)


## Why a handoff can't be played now (the design's gate messages), or "" when it can.
func gate_message(handoff_id: String) -> String:
	if not is_open():
		return "The finale hasn't opened yet."
	var lines: Array[String] = []
	for need: Variant in data.handoff(handoff_id).get("needs", []):
		if state.has_note(str(need)):
			continue
		var note := data.note(str(need))
		var title := str(note.get("title", need))
		if bool(note.get("free", false)):
			lines.append("You need %s. It is free once the finale opens." % title)
		else:
			lines.append("You need %s. Find someone from the %s crew and ask for their handoff word." % [title, Ids.machine_title(str(need))])
	if not lines.is_empty():
		return "\n".join(lines)
	if not handoff_available(handoff_id):
		var waiting := waiting_machines(handoff_id)
		return "This handoff waits for the %s." % (" and ".join(waiting) if not waiting.is_empty() else "machines")
	return ""


## Records a setting set on this phone (queued for the scoreboard). True if new.
func add_setting(handoff_id: String, index: int) -> bool:
	return state.add_setting(handoff_id, index)


## "6:00 pm" for the safety-net time in the viewer's own time zone, or "".
func safety_net_text() -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return FinaleData.format_clock(str(state.cache.get("safety_net_at", "")), bias)


# --- Handoff notes -----------------------------------------------------------------------------


func held_notes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in data.notes:
		if state.has_note(str(entry["id"])):
			out.append(entry)
	return out


## Gives out the notes this phone has earned: the crew's own when its machine
## runs (or it joined a running crew), and every free note once the finale is open.
func sync_notes() -> void:
	var crew := GameState.crew
	if crew != "" and (Progress.is_running(crew) or Progress.is_maintainer()):
		state.grant_note(data.note_id_for_machine(crew))
	if is_open():
		for entry in data.notes:
			if bool(entry.get("free", false)):
				state.grant_note(str(entry["id"]))


## The handoff word of the player's own crew's note, or "".
func crew_word() -> String:
	if GameState.crew == "" or not state.has_note(GameState.crew):
		return ""
	return str(data.note(GameState.crew).get("handoff_word", ""))


## A handoff word typed on the Lucky word keypad. Returns WORD_UNKNOWN, WORD_COLLECTED or WORD_HAVE.
func collect_word(typed: String) -> int:
	var entry := data.note_for_word(typed)
	if entry.is_empty():
		return WORD_UNKNOWN
	return WORD_COLLECTED if state.grant_note(str(entry["id"])) else WORD_HAVE


# --- The gnu's notes -----------------------------------------------------------------------------


## A code typed in the Archive. CODE_INVALID, CODE_FILED, CODE_FILED_EARLY (the finale is
## not open yet; it goes to the scoreboard when it opens) or CODE_HAVE.
func enter_code(typed: String) -> int:
	var entry := data.gnu_note_for_code(typed)
	if entry.is_empty():
		return CODE_INVALID
	if state.has_gnu_note(str(entry["id"])):
		return CODE_HAVE
	state.add_gnu_note(str(entry["id"]), FinaleData.normalise_code(str(entry["code"])))
	return CODE_FILED if is_open() else CODE_FILED_EARLY


## Files a gnu note by id (its in-game twin was solved). True if it was new.
func collect_gnu_note(note_id: String) -> bool:
	var entry := data.gnu_note(note_id)
	if entry.is_empty():
		return false
	return state.add_gnu_note(note_id, FinaleData.normalise_code(str(entry["code"])))


func notes_found() -> int:
	var served: Dictionary = state.cache.get("notes", {})
	return maxi(int(served.get("found", 0)), state.gnu_notes.size())


func notes_total() -> int:
	return int((state.cache.get("notes", {}) as Dictionary).get("total", data.gnu_notes.size()))


func notes_needed() -> int:
	return int((state.cache.get("notes", {}) as Dictionary).get("needed", data.needed))


# --- The start code and the README -----------------------------------------------------------------


## POST /finale/start; `done(result: String)` gets a FinaleClient.START_* value.
func submit_start(typed: String, done: Callable) -> void:
	if client == null:
		done.call(FinaleClient.START_OFFLINE)
		return
	client.submit_start(typed, done)


## The README sections whose triggers hold now, in order.
func readme_sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: Variant in data.readme.get("sections", []):
		if not section is Dictionary:
			continue
		var trigger: Dictionary = section.get("trigger", {})
		var holds := false
		if trigger.has("machine_runs"):
			holds = Progress.is_running(str(trigger["machine_runs"]))
		elif trigger.has("handoff_connected"):
			holds = handoff_connected(str(trigger["handoff_connected"]))
		if holds:
			out.append(section)
	return out


## Everyone who fixed a machine, as far as the progress store knows.
func contributor_names() -> Array[String]:
	var out: Array[String] = []
	for machine in Ids.MACHINES:
		for person in Progress.store.get_contributors(machine):
			if not out.has(person):
				out.append(person)
	return out
