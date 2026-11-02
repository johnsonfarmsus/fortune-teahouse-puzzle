# SPDX-License-Identifier: AGPL-3.0-or-later
class_name RemoteInventoryStore
extends InventoryStore
## The crew inventory through the scoreboard (server/API.md, crew inventory).
## Same pattern as RemoteProgressStore: it wraps a LocalInventoryStore, writes
## apply locally at once and go into a persistent queue that is sent in order,
## one request at a time, retried with backoff while the scoreboard is down.
## Reads merge the server's rows into the local store (the server is the source
## of truth for who found an item first).
##
##   POST /crews/{machine}/inventory/{item_id}  {device_id, state, place}
##   GET  /crews/{machine}/inventory            {items: [rows]}
##
## A write is idempotent per (machine, item_id, state), so a repeat is never
## queued twice. 403 not_in_crew drops the write (it stays on this phone); any
## other 4xx is retried and dropped after five refusals; a network error, 5xx
## or 429 keeps it and backs off 2, 4, 8 ... 60 s (or Retry-After).
## `transport` is the same Callable shape as RemoteProgressStore's.

signal status_changed

const API_PREFIX := "/api/v1"
const DEFAULT_QUEUE_PATH := "user://inventory_queue.json"
const QUEUE_VERSION := 1
const POLL_INTERVAL_MSEC := 15000
const BACKOFF_START_MSEC := 2000
const BACKOFF_MAX_MSEC := 60000
const MAX_CLIENT_ERRORS := 5

var base_url: String
var local: LocalInventoryStore
var transport: Callable
var queue_path: String
var queue: Array[Dictionary] = []
var watching: Array[String] = []  # machines polled every POLL_INTERVAL_MSEC
## Tests set this to control time (msec); negative means the real clock.
var clock_override: int = -1

var _online := false
var _in_flight := false
var _retired := false
var _generation := 0
var _backoff_msec := 0
var _next_attempt_msec := 0
var _next_poll_msec := 0
var _fetching: Dictionary = {}


func _init(
	p_base_url: String, p_local: LocalInventoryStore, p_transport: Callable = Callable(),
	p_queue_path: String = DEFAULT_QUEUE_PATH
) -> void:
	base_url = p_base_url.strip_edges().rstrip("/")
	local = p_local
	transport = p_transport
	queue_path = p_queue_path
	local.changed.connect(_on_local_changed)
	_load()


func items(machine: String) -> Array[Dictionary]:
	return local.items(machine)


func mark(machine: String, item_id: String, state: String, place: String, device_id: String) -> bool:
	var changed_here := local.mark(machine, item_id, state, place, device_id)
	if _retired or InventoryStore.rank(state) < 0:
		return changed_here
	for q in queue:
		if q["machine"] == machine and q["item_id"] == item_id and q["state"] == state:
			return changed_here  # already waiting to go
	if not changed_here:
		return false  # the crew already had it in that state (or better)
	queue.append({"machine": machine, "item_id": item_id, "state": state, "place": place, "device_id": device_id})
	_save()
	status_changed.emit()
	if _now() >= _next_attempt_msec:
		_pump()
	return true


## Queues this phone's own finds made before the scoreboard was on (the server
## ignores repeats), so a crew sees them once it is online.
func backfill(machine: String, device_id: String) -> void:
	if _retired:
		return
	for e in local.items(machine):
		if str(e.get("found_by", "")) != device_id:
			continue
		var queued := false
		for q in queue:
			if q["machine"] == machine and q["item_id"] == e["item_id"] and q["state"] == e["state"]:
				queued = true
		if not queued:
			queue.append({"machine": machine, "item_id": str(e["item_id"]), "state": str(e["state"]), "place": str(e.get("place", "")), "device_id": device_id})
	_save()
	_pump()


## One GET per machine ("" means every watched machine).
func refresh(machine: String = "") -> void:
	_next_poll_msec = _now() + POLL_INTERVAL_MSEC
	var targets: Array[String] = []
	if machine != "":
		targets.append(machine)
	else:
		targets.assign(watching)
	for m in targets:
		_fetch(m)


func set_watching(machines: Array[String]) -> void:
	var changed_any := machines != watching
	watching = machines.duplicate()
	if changed_any and not watching.is_empty():
		refresh()


## Call regularly (Adventure's 1 s Timer does): retries the queue after its
## backoff and polls the watched machines.
func tick(now_msec: int = -1) -> void:
	if now_msec >= 0:
		clock_override = now_msec
	var now := _now()
	if not queue.is_empty() and not _in_flight and now >= _next_attempt_msec:
		_pump()
	if not watching.is_empty() and now >= _next_poll_msec:
		refresh()


func flush() -> int:
	_next_attempt_msec = 0
	_pump()
	return queue.size()


func queue_size() -> int:
	return queue.size()


func is_online() -> bool:
	return _online


func retire() -> void:
	_retired = true
	_generation += 1
	_in_flight = false
	transport = Callable()
	watching = []
	if local.changed.is_connected(_on_local_changed):
		local.changed.disconnect(_on_local_changed)


func reset_local() -> void:
	queue.clear()
	_generation += 1
	_in_flight = false
	_save()
	local.reset_local()
	status_changed.emit()


# --- Queue --------------------------------------------------------------------------


func _pump() -> void:
	if _in_flight or queue.is_empty() or not transport.is_valid() or _retired:
		return
	var item := queue[0]
	_in_flight = true
	var path := "/crews/%s/inventory/%s" % [item["machine"], item["item_id"]]
	var body := {"device_id": item["device_id"], "state": item["state"]}
	if str(item.get("place", "")) != "":
		body["place"] = item["place"]
	_call("POST", path, body, _on_write_done.bind(item, _generation))


func _on_write_done(status: int, data: Dictionary, retry_after: int, item: Dictionary, generation: int) -> void:
	if generation != _generation:
		return
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
		if local.merge_row(str(item["machine"]), data):
			changed.emit(str(item["machine"]))
		_remove(item)
		_pump()
		return
	if status == 403 and _error_code(data) == "not_in_crew":
		_remove(item)  # stays on this phone only
		_pump()
		return
	item["errors"] = int(item.get("errors", 0)) + 1
	if int(item["errors"]) >= MAX_CLIENT_ERRORS:
		_remove(item)
		_pump()
		return
	_save()
	_back_off(0)


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


func _fetch(machine: String) -> void:
	if not transport.is_valid() or _fetching.has(machine) or _retired:
		return
	_fetching[machine] = true
	_call("GET", "/crews/%s/inventory" % machine, {}, _on_list.bind(machine))


func _on_list(status: int, data: Dictionary, retry_after: int, machine: String) -> void:
	_fetching.erase(machine)
	if _retired:
		return
	if status == 0 or status >= 500:
		_set_online(false)
		return
	_set_online(true)
	if status == 429:
		_next_poll_msec = maxi(_next_poll_msec, _now() + maxi(retry_after * 1000, POLL_INTERVAL_MSEC))
		return
	if status < 200 or status >= 300:
		return
	var any := false
	for row: Variant in data.get("items", []):
		if row is Dictionary and local.merge_row(machine, row):
			any = true
	if any:
		changed.emit(machine)


# --- Plumbing -----------------------------------------------------------------------


func _call(method: String, path: String, body: Dictionary, done: Callable) -> void:
	if not transport.is_valid():
		done.call(0, {}, 0)
		return
	transport.call(method, base_url + API_PREFIX + path, body, done)


func _on_local_changed(machine: String) -> void:
	changed.emit(machine)


func _set_online(value: bool) -> void:
	if _online != value:
		_online = value
		status_changed.emit()


func _error_code(data: Dictionary) -> String:
	var error: Variant = data.get("error")
	return str(error.get("code", "")) if error is Dictionary else ""


func _now() -> int:
	return clock_override if clock_override >= 0 else Time.get_ticks_msec()


func _load() -> void:
	if queue_path == "":
		return
	var data := JsonFile.read(queue_path)
	for raw: Variant in data.get("queue", []):
		if raw is Dictionary and raw.has("machine") and raw.has("item_id") and raw.has("state"):
			queue.append(raw)


func _save() -> void:
	if queue_path == "" or not transport.is_valid():
		return
	JsonFile.write(queue_path, {"version": QUEUE_VERSION, "queue": queue})
