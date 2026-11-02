# SPDX-License-Identifier: AGPL-3.0-or-later
class_name RemoteProgressStore
extends ProgressStore
## Scoreboard-backed store (server/API.md). It wraps a local store: getters
## answer at once from local state merged with the last server answer, and
## nothing here blocks or awaits. Writes go into a persistent queue
## (user://queue.json) that is sent in order, retried with backoff while the
## scoreboard is unreachable, and never lost across restarts.
##
## The network is injected as `transport`, a Callable
##   transport(method: String, url: String, body: Dictionary, done: Callable)
## that ends by calling done(status: int, data: Dictionary, retry_after: int)
## (status 0 = no answer). HttpTransport is the real one; tests use a fake.
## With no transport the store only queues (the WP3 behaviour) and does not
## write the queue file.

signal status_changed  ## online state or queue size changed
signal hint_arrived(hint: Dictionary)  ## one hint object from GET /hints

const API_PREFIX := "/api/v1"
const DEFAULT_QUEUE_PATH := "user://queue.json"
const QUEUE_VERSION := 1
const POLL_INTERVAL_MSEC := 10000  # API.md polling budget: 10 s while a screen is open
const BACKOFF_START_MSEC := 2000
const BACKOFF_MAX_MSEC := 60000
const MAX_CLIENT_ERRORS := 5  # a write the server keeps refusing with another 4xx is dropped
const HINT_PAGE := 50
const NUDGE_ERRORS := {
	"not_a_maintainer": "Your crew's machine has to run before you can send nudges.",
	"own_crew": "Pick a different crew from your own.",
	"unknown_nudge": "That nudge is not known to the scoreboard.",
	"unknown_crew": "That crew is not known to the scoreboard.",
	"rate_limited": "Too many requests. Wait a moment and try again.",
}

var base_url: String
var local: ProgressStore
var queue: Array[Dictionary] = []
var queue_path: String
var transport: Callable
## Tests set this to control time (msec); negative means the real clock.
var clock_override: int = -1

var _device_id := ""
var _own_crew := ""
var _registered_id := ""
var _online := false
var _in_flight := false
var _generation := 0
var _backoff_msec := 0
var _next_attempt_msec := 0
var _next_poll_msec := 0
var _parts: Dictionary = {}  # machine -> {part: solver_count} from the server
var _entries: Dictionary = {}  # machine -> Array[{name, via}] newest first, as served
var _runs: Dictionary = {}  # machine -> true once the server said it runs (kept across restarts)
var _last_hint_ids: Dictionary = {}  # crew -> highest hint id delivered
var _watched: Array[String] = []
var _hint_polling := false
var _fetching: Dictionary = {}
var _polling_hints := false


func _init(
	p_base_url: String,
	p_local: ProgressStore,
	p_transport: Callable = Callable(),
	p_queue_path: String = DEFAULT_QUEUE_PATH
) -> void:
	base_url = p_base_url.strip_edges().rstrip("/")
	local = p_local
	transport = p_transport
	queue_path = p_queue_path
	local.progress_changed.connect(_on_local_changed)
	_load()


## Stop forwarding the local store's signals (Progress calls this when it
## switches the scoreboard off and keeps using the same local store).
func detach() -> void:
	if local.progress_changed.is_connected(_on_local_changed):
		local.progress_changed.disconnect(_on_local_changed)


# --- ProgressStore ------------------------------------------------------------------


func set_display_name(device_id: String, name: String) -> void:
	local.set_display_name(device_id, name)
	_device_id = device_id
	_enqueue({"op": "set_display_name", "device_id": device_id, "name": name})


func join_crew(device_id: String, machine: String) -> void:
	local.join_crew(device_id, machine)
	_device_id = device_id
	_own_crew = machine
	_enqueue({"op": "join_crew", "device_id": device_id, "machine": machine})


func record_part_solved(machine: String, part: String, device_id: String, credited: bool) -> void:
	local.record_part_solved(machine, part, device_id, credited)
	_device_id = device_id
	_enqueue({"op": "record_part_solved", "machine": machine, "part": part, "device_id": device_id, "credited": credited})


## Server solver counts merged with this device's own solves (whichever is higher),
## so a solve the server has not heard of, or refused, still shows on this phone.
func get_crew_progress(machine: String) -> Dictionary:
	var out := local.get_crew_progress(machine)
	var served: Dictionary = _parts.get(machine, {})
	for part: String in Ids.PARTS:
		out[part] = maxi(int(out.get(part, 0)), int(served.get(part, 0)))
	return out


## First-solve order: the server's list (it serves newest first) then any local name it lacks.
func get_contributors(machine: String) -> Array[String]:
	var out: Array[String] = []
	for entry in get_contributor_entries(machine):
		out.append(str(entry["name"]))
	return out


## [{name, via}] in first-merged order; via is "solve" or "mentor".
func get_contributor_entries(machine: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Array[String] = []
	var served: Array = _entries.get(machine, [])
	for i in range(served.size() - 1, -1, -1):
		var entry: Dictionary = served[i]
		var shown := _display(str(entry.get("name", "")))
		if not seen.has(shown):
			seen.append(shown)
			out.append({"name": shown, "via": str(entry.get("via", "solve"))})
	for shown in local.get_contributors(machine):
		if not seen.has(shown):
			seen.append(shown)
			out.append({"name": shown, "via": "solve"})
	return out


func reset_local() -> void:
	queue.clear()
	_generation += 1
	_in_flight = false
	_registered_id = ""
	_last_hint_ids = {}
	_save()
	local.reset_local()
	status_changed.emit()


func is_online() -> bool:
	return _online


## One look at the scoreboard now: the player's crew, every watched machine and,
## when hint polling is on, new hints. Also sets the time of the next poll.
func refresh() -> void:
	local.refresh()
	_next_poll_msec = _now() + POLL_INTERVAL_MSEC
	if not transport.is_valid():
		return
	var targets: Array[String] = []
	if _own_crew != "":
		targets.append(_own_crew)
	for machine in _watched:
		if not targets.has(machine):
			targets.append(machine)
	for machine in targets:
		_fetch_crew(machine)
	if _hint_polling:
		_poll_hints()


## Tries to send the queue now, ignoring any backoff ("Sync now"). Returns how
## many writes are still waiting (as of this call; a real network answers later).
func flush() -> int:
	_next_attempt_msec = 0
	_pump()
	return queue.size()


# --- Remote extras ------------------------------------------------------------------


## Who this device is. Queues a one-time registration (POST /devices) when the
## scoreboard has not seen this device id yet and there is a name or crew to tell it.
func set_identity(device_id: String, crew: String, display_name: String) -> void:
	_device_id = device_id
	_own_crew = crew
	if _registered_id == device_id or (crew == "" and display_name == ""):
		return
	for item in queue:
		if str(item.get("device_id", "")) == device_id and ["register", "join_crew", "set_display_name"].has(item.get("op")):
			return
	_enqueue({"op": "register", "device_id": device_id, "name": display_name, "machine": crew})


## Polling is on only while a progress screen is open. `machines` are polled
## every 10 s; `hints` also polls hints for the player's crew (a puzzle screen
## wants hints but not progress). Calling this with new values refreshes at once.
func set_watching(machines: Array[String], hints: bool) -> void:
	var want_hints := hints or not machines.is_empty()
	var changed := machines != _watched or want_hints != _hint_polling
	_watched = machines.duplicate()
	_hint_polling = want_hints
	if changed and want_hints:
		refresh()


## Call regularly (a Timer node does). Retries the queue after a backoff and
## polls while something is watched.
func tick(now_msec: int = -1) -> void:
	if now_msec >= 0:
		clock_override = now_msec
	var now := _now()
	if not queue.is_empty() and not _in_flight and now >= _next_attempt_msec:
		_pump()
	if (_hint_polling or not _watched.is_empty()) and now >= _next_poll_msec:
		refresh()


func queue_size() -> int:
	return queue.size()


## True once the scoreboard has said this crew's machine runs. The answer is
## remembered, since a machine that has run stays running.
func server_runs(machine: String) -> bool:
	return _runs.has(machine)


func watched_machines() -> Array[String]:
	return _watched


func hint_polling() -> bool:
	return _hint_polling


## One look at GET /contributors, filling every crew's list.
func refresh_contributors() -> void:
	if not transport.is_valid():
		return
	_call("GET", "/contributors", {}, _on_all_contributors)


## done(ok: bool, ids: Array[String]) with GET /hints/nudges.
func fetch_nudge_ids(done: Callable) -> void:
	_call("GET", "/hints/nudges", {}, _on_nudge_ids.bind(done))


## POST /hints. done(ok: bool, message: String).
func send_nudge(to_crew: String, nudge_id: String, done: Callable) -> void:
	var body := {"device_id": _device_id, "to_crew": to_crew, "nudge_id": nudge_id}
	_call("POST", "/hints", body, _on_nudge_sent.bind(done))


# --- Queue --------------------------------------------------------------------------


func _enqueue(item: Dictionary) -> void:
	queue.append(item)
	_save()
	status_changed.emit()
	if _now() >= _next_attempt_msec:
		_pump()


func _pump() -> void:
	if _in_flight or queue.is_empty() or not transport.is_valid():
		return
	var item := queue[0]
	var request := _request_for(item)
	if request.is_empty():
		queue.pop_front()  # an op this version does not know
		_save()
		_pump()
		return
	_in_flight = true
	_call(request["method"], request["path"], request["body"], _on_item_done.bind(item, _generation))


func _request_for(item: Dictionary) -> Dictionary:
	var device_id := str(item.get("device_id", ""))
	match str(item.get("op", "")):
		"set_display_name":
			return _post("/devices", {"device_id": device_id, "display_name": str(item.get("name", ""))})
		"join_crew":
			return _post("/devices", {"device_id": device_id, "crew": str(item.get("machine", ""))})
		"register":
			var body := {"device_id": device_id}
			if str(item.get("name", "")) != "":
				body["display_name"] = str(item["name"])
			if str(item.get("machine", "")) != "":
				body["crew"] = str(item["machine"])
			return _post("/devices", body)
		"record_part_solved":
			var path := "/crews/%s/parts/%s/solve" % [str(item.get("machine", "")), str(item.get("part", ""))]
			return _post(path, {"device_id": device_id, "credited": bool(item.get("credited", true))})
	return {}


func _post(path: String, body: Dictionary) -> Dictionary:
	return {"method": "POST", "path": path, "body": body}


func _on_item_done(status: int, data: Dictionary, retry_after: int, item: Dictionary, generation: int) -> void:
	if generation != _generation:
		return  # the queue was reset while this was in flight
	_in_flight = false
	if status == 0 or status >= 500:
		_set_online(false)
		_back_off(0)
		return
	_set_online(true)
	if status == 429:
		_back_off(retry_after * 1000)
		return
	if status >= 200 and status < 300:
		_backoff_msec = 0
		_next_attempt_msec = 0
		if ["register", "join_crew", "set_display_name"].has(item.get("op")):
			_registered_id = str(item.get("device_id", ""))
		if item.get("op") == "record_part_solved" and data.get("crew") is Dictionary:
			_apply_crew(data["crew"])
		_remove(item)
		_pump()
		return
	var code := _error_code(data)
	if status == 403 and code == "not_in_crew":
		# The device is not in that crew on the server: the solve stays in the
		# local store for this phone's own view but is never retried.
		_remove(item)
		_pump()
		return
	if status == 404 and code == "device_not_registered" and item.get("op") != "register" and not item.has("registered_first"):
		var device_id := str(item.get("device_id", ""))
		item["registered_first"] = true  # once per write, so a wiped server cannot loop us
		queue.push_front(_registration_for(device_id))
		_save()
		_pump()
		return
	# Any other refusal: keep it for a retry, but give up on a write the server
	# keeps rejecting as malformed so it cannot block the queue for ever.
	item["errors"] = int(item.get("errors", 0)) + 1
	if item["errors"] >= MAX_CLIENT_ERRORS:
		_remove(item)
		_pump()
		return
	_save()
	_back_off(0)


func _registration_for(device_id: String) -> Dictionary:
	var name := ""
	var crew := _own_crew if device_id == _device_id else ""
	if local is LocalProgressStore:
		name = str((local as LocalProgressStore).names.get(device_id, ""))
		crew = str((local as LocalProgressStore).crews.get(device_id, crew))
	return {"op": "register", "device_id": device_id, "name": name, "machine": crew}


func _remove(item: Dictionary) -> void:
	for i in queue.size():
		if is_same(queue[i], item):
			queue.remove_at(i)
			break
	_save()
	status_changed.emit()


func _back_off(at_least_msec: int) -> void:
	var next := BACKOFF_START_MSEC if _backoff_msec == 0 else _backoff_msec * 2
	_backoff_msec = clampi(maxi(next, at_least_msec), BACKOFF_START_MSEC, BACKOFF_MAX_MSEC)
	_next_attempt_msec = _now() + _backoff_msec


# --- Reads --------------------------------------------------------------------------


func _fetch_crew(machine: String) -> void:
	if not transport.is_valid() or _fetching.has(machine) or not Ids.MACHINES.has(machine):
		return
	_fetching[machine] = true
	_call("GET", "/crews/" + machine, {}, _on_crew.bind(machine))


func _on_crew(status: int, data: Dictionary, _retry_after: int, machine: String) -> void:
	_fetching.erase(machine)
	if _note_status(status):
		_apply_crew(data)


## Updates the cache from a crew object (GET /crews/{m} or the solve response).
func _apply_crew(data: Dictionary) -> void:
	var machine := str(data.get("machine", ""))
	if not Ids.MACHINES.has(machine):
		return
	var parts := ProgressStore.empty_progress()
	for entry: Variant in data.get("parts", []):
		if entry is Dictionary and parts.has(str(entry.get("part", ""))):
			parts[str(entry["part"])] = int(entry.get("solved_count", 0))
	var first_time := not _parts.has(machine)
	var changed: bool = first_time or _parts[machine] != parts
	_parts[machine] = parts
	if data.has("contributors"):
		var entries := _parse_entries(data["contributors"])
		if _entries.get(machine, []) != entries:
			changed = true
		_entries[machine] = entries
	if bool(data.get("runs", false)) and not _runs.has(machine):
		_runs[machine] = true
		changed = true
		_save()
	if changed:
		progress_changed.emit(machine)


func _on_all_contributors(status: int, data: Dictionary, _retry_after: int) -> void:
	if not _note_status(status):
		return
	var by_machine: Dictionary = {}
	for machine in Ids.MACHINES:
		by_machine[machine] = []
	for raw: Variant in data.get("contributors", []):
		if raw is Dictionary and by_machine.has(str(raw.get("machine", ""))):
			by_machine[str(raw["machine"])].append(raw)
	for machine: String in by_machine:
		var entries := _parse_entries(by_machine[machine])
		if _entries.get(machine, []) != entries:
			_entries[machine] = entries
			progress_changed.emit(machine)


func _parse_entries(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				out.append({"name": str(entry.get("name", "")), "via": str(entry.get("via", "solve"))})
	return out


func _display(server_name: String) -> String:
	return "Anonymous" if server_name == "" or server_name.to_lower() == "anonymous" else server_name


# --- Hints --------------------------------------------------------------------------


func _poll_hints() -> void:
	if _own_crew == "" or _polling_hints or not transport.is_valid():
		return
	var after := int(_last_hint_ids.get(_own_crew, -1))
	var path := "/hints?crew=" + _own_crew
	if after >= 0:
		path += "&after_id=%d" % after
	_polling_hints = true
	_call("GET", path, {}, _on_hints.bind(_own_crew, after))


func _on_hints(status: int, data: Dictionary, _retry_after: int, crew: String, after: int) -> void:
	_polling_hints = false
	if not _note_status(status):
		return
	var hints: Array[Dictionary] = []
	for raw: Variant in data.get("hints", []):
		if raw is Dictionary and int(raw.get("id", 0)) > after:
			hints.append(raw)
	if after < 0:
		# First look for this crew: show only the newest hint, not a backlog.
		if hints.size() > 1:
			hints = hints.slice(hints.size() - 1)
	var highest := maxi(after, 0)
	for hint in hints:
		highest = maxi(highest, int(hint["id"]))
		hint_arrived.emit(hint)
	_last_hint_ids[crew] = highest
	_save()
	if after >= 0 and data.get("hints", []).size() >= HINT_PAGE and crew == _own_crew:
		_poll_hints()  # more than one page waiting: page forward


func _on_nudge_ids(status: int, data: Dictionary, _retry_after: int, done: Callable) -> void:
	var ids: Array[String] = []
	if _note_status(status):
		for id: Variant in data.get("nudges", []):
			ids.append(str(id))
	if done.is_valid():
		done.call(not ids.is_empty(), ids)


func _on_nudge_sent(status: int, data: Dictionary, _retry_after: int, done: Callable) -> void:
	var ok := false
	var message := ""
	var answered := _note_status(status) or (status > 0 and status < 500)
	if not answered:
		message = "The scoreboard is not reachable. Try again when you are online."
	elif status >= 200 and status < 300:
		ok = true
		message = "Nudge sent." if bool(data.get("created", true)) else "You already sent that nudge to that crew."
		refresh_contributors()
	else:
		var code := _error_code(data)
		if status == 404 and code == "device_not_registered":
			queue.push_front(_registration_for(_device_id))
			_save()
			_pump()
			message = "Registering this phone. Try again in a moment."
		else:
			message = str(NUDGE_ERRORS.get(code, "The scoreboard said no (%d)." % status))
	if done.is_valid():
		done.call(ok, message)


# --- Plumbing -----------------------------------------------------------------------


func _call(method: String, path: String, body: Dictionary, done: Callable) -> void:
	if not transport.is_valid():
		done.call(0, {}, 0)
		return
	transport.call(method, base_url + API_PREFIX + path, body, done)


## Records the outcome of a request and returns true for a 2xx answer.
func _note_status(status: int) -> bool:
	if status == 0 or status >= 500:
		_set_online(false)
		return false
	_set_online(true)
	return status >= 200 and status < 300


func _set_online(value: bool) -> void:
	if _online != value:
		_online = value
		status_changed.emit()


func _error_code(data: Dictionary) -> String:
	var error: Variant = data.get("error")
	return str(error.get("code", "")) if error is Dictionary else ""


func _now() -> int:
	return clock_override if clock_override >= 0 else Time.get_ticks_msec()


func _on_local_changed(machine: String) -> void:
	progress_changed.emit(machine)


func _save() -> void:
	if not transport.is_valid():
		return
	JsonFile.write(
		queue_path,
		{
			"version": QUEUE_VERSION,
			"queue": queue,
			"registered_device": _registered_id,
			"last_hint_ids": _last_hint_ids,
			"running": _runs.keys(),
		}
	)


func _load() -> void:
	if not transport.is_valid():
		return
	var data := JsonFile.read(queue_path)
	if data.is_empty():
		return
	for item: Variant in data.get("queue", []):
		if item is Dictionary and item.get("op") is String:
			queue.append(item)
	_registered_id = str(data.get("registered_device", ""))
	for crew: Variant in data.get("last_hint_ids", {}):
		_last_hint_ids[str(crew)] = int(data["last_hint_ids"][crew])
	for machine: Variant in data.get("running", []):
		if Ids.MACHINES.has(str(machine)):
			_runs[str(machine)] = true
