# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Owns the ProgressStore: local unless a scoreboard URL is configured (the
## project setting fortune/scoreboard_url, or ?scoreboard= on the web build)
## and "Use scoreboard" is on. After writes it diffs progress and emits
## part_fixed (0 to 1) and machine_running (all six parts working).
##
## With a scoreboard it also drives the remote store: a 1 s Timer calls
## store.tick() (queue retries and the 10 s poll while a progress screen is
## open), pushed hints go to Hints, and the Router stack decides what to poll.

const SETTINGS_PATH := "user://scoreboard.json"
const TICK_SECONDS := 1.0

var store: ProgressStore
var scoreboard_url: String = ""  # "" means this run is offline only
var scoreboard_enabled: bool = true  # the Settings toggle
var persist_settings: bool = true  # tests turn this off
var transport_override: Callable = Callable()  # tests inject a fake network here
var queue_path: String = RemoteProgressStore.DEFAULT_QUEUE_PATH
var _last: Dictionary = {}  # machine -> {part: count}
var _local: LocalProgressStore
var _transport: HttpTransport
var _tick: Timer


func _ready() -> void:
	scoreboard_url = ScoreboardUrl.configured()
	if persist_settings:
		var saved := JsonFile.read(SETTINGS_PATH)
		scoreboard_enabled = bool(saved.get("enabled", true))
	_local = LocalProgressStore.new()
	_tick = Timer.new()
	_tick.wait_time = TICK_SECONDS
	_tick.autostart = true
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	_build_store()
	# Tell the store who this device is, only when that is news to it, so a
	# remote store does not queue the same writes at every boot.
	if GameState.display_name != "" and _local.names.get(GameState.device_id, "") != GameState.display_name:
		store.set_display_name(GameState.device_id, GameState.display_name)
	if GameState.crew != "" and _local.crews.get(GameState.device_id, "") != GameState.crew:
		store.join_crew(GameState.device_id, GameState.crew)
	Events.crew_changed.connect(func(_machine: String) -> void: store.refresh())
	# Router is registered after this autoload, so it only exists once _ready is done.
	_connect_router.call_deferred()


func set_store(new_store: ProgressStore) -> void:
	if store != null:
		if store.progress_changed.is_connected(_on_store_changed):
			store.progress_changed.disconnect(_on_store_changed)
		if store is RemoteProgressStore:
			_unwire(store as RemoteProgressStore)
	store = new_store
	store.progress_changed.connect(_on_store_changed)
	if store is RemoteProgressStore:
		var remote := store as RemoteProgressStore
		remote.status_changed.connect(_on_status_changed)
		remote.hint_arrived.connect(_on_hint_arrived)
	_snapshot()
	Events.scoreboard_status_changed.emit()


## "Reset this device": the active store forgets this device's local progress
## (a remote store resets its local part and keeps being the remote store).
func reset() -> void:
	store.reset_local()
	_snapshot()
	for machine in Ids.MACHINES:
		Events.progress_changed.emit(machine)


func parts_working(machine: String) -> int:
	var count := 0
	for part in Ids.PARTS:
		if int(store.get_crew_progress(machine).get(part, 0)) > 0:
			count += 1
	return count


func is_running(machine: String) -> bool:
	return parts_working(machine) == Ids.PARTS.size()


# --- Scoreboard ---------------------------------------------------------------------


## True when this run could talk to a scoreboard (a URL is set).
func scoreboard_available() -> bool:
	return scoreboard_url != ""


## True while the remote store is the active store.
func scoreboard_active() -> bool:
	return store is RemoteProgressStore


## The Settings toggle. Switching off keeps the unsent queue on disk for later.
func use_scoreboard(on: bool) -> void:
	scoreboard_enabled = on
	if persist_settings:
		JsonFile.write(SETTINGS_PATH, {"enabled": on})
	if scoreboard_available():
		_build_store()


## The network the stores share: the injected fake in tests, else one
## HttpTransport. The crew inventory (Adventure) sends through it too.
func network() -> Callable:
	if transport_override.is_valid():
		return transport_override
	if _transport == null:
		_transport = HttpTransport.new()
		_transport.name = "HttpTransport"
		add_child(_transport)
	return Callable(_transport, "request")


## "Sync now": tries the queue at once and looks at the scoreboard. Returns
## the number of writes still waiting.
func sync_now() -> int:
	if not scoreboard_active():
		return 0
	Adventure.sync_now()
	var remote := store as RemoteProgressStore
	var waiting := remote.flush()
	remote.refresh()
	return waiting


func queue_size() -> int:
	return (store as RemoteProgressStore).queue_size() if scoreboard_active() else 0


## A maintainer is a player whose crew's machine runs, as the scoreboard says.
func is_maintainer() -> bool:
	if not scoreboard_active() or GameState.crew == "":
		return false
	return (store as RemoteProgressStore).server_runs(GameState.crew)


## One look at GET /contributors for the Contributors screen.
func refresh_contributors() -> void:
	if scoreboard_active():
		(store as RemoteProgressStore).refresh_contributors()


## Makes `store` match the settings. A remote store for the same address is
## kept; any other is retired (set_store does that) before a new one starts.
func _build_store() -> void:
	if scoreboard_url == "" or not scoreboard_enabled:
		if store != _local:
			set_store(_local)
		return
	if store is RemoteProgressStore and (store as RemoteProgressStore).base_url == scoreboard_url:
		return
	var send := network()
	var remote := RemoteProgressStore.new(scoreboard_url, _local, send, queue_path)
	set_store(remote)
	remote.set_identity(GameState.device_id, GameState.crew, GameState.display_name)
	# Solves made before the scoreboard was on reach it too (the server ignores repeats).
	remote.backfill_solves(GameState.device_id, GameState.player.solved_parts)
	remote.refresh()


func _unwire(remote: RemoteProgressStore) -> void:
	if remote.status_changed.is_connected(_on_status_changed):
		remote.status_changed.disconnect(_on_status_changed)
	if remote.hint_arrived.is_connected(_on_hint_arrived):
		remote.hint_arrived.disconnect(_on_hint_arrived)
	remote.retire()


func _connect_router() -> void:
	if not Router.stack_changed.is_connected(_on_stack_changed):
		Router.stack_changed.connect(_on_stack_changed)


func _on_tick() -> void:
	if store is RemoteProgressStore:
		(store as RemoteProgressStore).tick()


## Poll only while a progress screen is open (machine view or crew progress, or a
## finale screen, which watches all three machines); a puzzle screen polls hints alone.
func _on_stack_changed(_depth: int) -> void:
	if not store is RemoteProgressStore:
		return
	var machines: Array[String] = []
	var hints := false
	var top := Router.top()
	if top != null:
		if top.scene_file_path == Paths.MACHINE_VIEW or top.scene_file_path == Paths.CREW_PROGRESS:
			var machine := str(top.args.get("machine", GameState.crew))
			if Ids.MACHINES.has(machine):
				machines.append(machine)
		elif Finale.WATCHED_SCREENS.has(top.scene_file_path):
			# The finale screens show every machine's progress (the pre-open
			# "N of 6 parts working" rows, note grants, README triggers).
			machines.append_array(Ids.MACHINES)
		elif top.scene_file_path == Paths.PUZZLE_HOST:
			hints = true
	(store as RemoteProgressStore).set_watching(machines, hints)


func _on_status_changed() -> void:
	Events.scoreboard_status_changed.emit()


func _on_hint_arrived(hint: Dictionary) -> void:
	Hints.receive_pushed_nudge("", Nudges.describe(hint))


func _snapshot() -> void:
	for machine in Ids.MACHINES:
		_last[machine] = store.get_crew_progress(machine)


func _on_store_changed(machine: String) -> void:
	var before: Dictionary = _last.get(machine, ProgressStore.empty_progress())
	var after := store.get_crew_progress(machine)
	_last[machine] = after
	Events.progress_changed.emit(machine)
	var all_before := true
	var all_after := true
	for part: String in Ids.PARTS:
		var was := int(before.get(part, 0)) > 0
		var now := int(after.get(part, 0)) > 0
		all_before = all_before and was
		all_after = all_after and now
		if now and not was:
			Events.part_fixed.emit(machine, part)
	if all_after and not all_before:
		Events.machine_running.emit(machine)
