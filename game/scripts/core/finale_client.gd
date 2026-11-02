# SPDX-License-Identifier: AGPL-3.0-or-later
class_name FinaleClient
extends RefCounted
## The finale's side of the scoreboard (server/API.md "Finale"). It never
## blocks and plays on when the scoreboard is down:
##  - GET /finale is polled every 15 s, but only while someone is "watching"
##    (FinaleView, HandoffHost or Archive on top of the Router stack), plus
##    one look when watching starts and one at boot (Finale does that).
##  - Writes wait in FinaleState.queue and are sent in order, one at a time:
##    POST /finale/handoffs/{id}/settings and POST /finale/notes. A network
##    error, 5xx or 429 backs off (2, 4, 8, ... up to 60 s). 403 finale_closed
##    and 409 handoff_waiting keep the write, marked held, until a poll shows
##    the finale open (notes) or the handoff available (settings). 404
##    device_not_registered sends POST /devices first, once per write.
##  - The start code is online only: submit_start() asks at once and reports
##    the outcome; it is never queued.
## The network is the same injected transport as RemoteProgressStore:
##   transport(method, url, body, done) ends with done(status, data, retry_after).

signal finale_changed  ## the cached GET /finale object changed
signal status_changed  ## online state or queue size changed

const API_PREFIX := "/api/v1"
const POLL_INTERVAL_MSEC := 15000
const BACKOFF_START_MSEC := 2000
const BACKOFF_MAX_MSEC := 60000
const MAX_CLIENT_ERRORS := 5

const START_STARTED := "started"
const START_WRONG := "wrong"
const START_NOT_READY := "not_ready"
const START_CLOSED := "closed"
const START_OFFLINE := "offline"
const START_BUSY := "busy"

var base_url: String
var state: FinaleState
var transport: Callable
## Tests set this to control time (msec); negative means the real clock.
var clock_override: int = -1

var _device_id := ""
var _crew := ""
var _display_name := ""
var _watching := false
var _in_flight := false
var _fetching := false
var _starting := false
var _online := false
var _failed := false
var _retired := false
var _generation := 0
var _backoff_msec := 0
var _next_attempt_msec := 0
var _next_poll_msec := 0


func _init(p_base_url: String, p_state: FinaleState, p_transport: Callable = Callable()) -> void:
	base_url = p_base_url.strip_edges().rstrip("/")
	state = p_state
	transport = p_transport
	state.queue_added.connect(_pump)


## Stops this client for good (the scoreboard was switched off or moved).
func retire() -> void:
	_retired = true
	_generation += 1
	_in_flight = false
	_watching = false
	transport = Callable()
	if state.queue_added.is_connected(_pump):
		state.queue_added.disconnect(_pump)


func set_identity(device_id: String, crew: String, display_name: String) -> void:
	_device_id = device_id
	_crew = crew
	_display_name = display_name
	_pump()


func is_online() -> bool:
	return _online


## True when the last request got no answer (or a 5xx): the cached finale is all there is.
func unreachable() -> bool:
	return _failed


func queue_size() -> int:
	return state.queue.size()


func is_watching() -> bool:
	return _watching


## The last GET /finale object ({} if none was ever heard).
func finale() -> Dictionary:
	return state.cache


# --- Polling ---------------------------------------------------------------------------


## Polling is on only while a finale screen is on top. Turning it on looks at once.
func set_watching(on: bool) -> void:
	if on == _watching:
		return
	_watching = on
	if on:
		refresh()


## Call regularly (a Timer node does). Polls every 15 s while watching and
## retries the queue after a backoff.
func tick(now_msec: int = -1) -> void:
	if now_msec >= 0:
		clock_override = now_msec
	var now := _now()
	if not state.queue.is_empty() and not _in_flight and now >= _next_attempt_msec:
		_pump()
	if _watching and now >= _next_poll_msec:
		refresh()


## One GET /finale now.
func refresh() -> void:
	if not transport.is_valid() or _retired:
		return
	_next_poll_msec = _now() + POLL_INTERVAL_MSEC
	if _fetching:
		return
	_fetching = true
	_call("GET", "/finale", {}, _on_finale)


## "Sync now": sends the queue at once, ignoring any backoff. Returns how many writes wait.
func flush() -> int:
	_next_attempt_msec = 0
	_pump()
	return state.queue.size()


func _on_finale(status: int, data: Dictionary, retry_after: int) -> void:
	_fetching = false
	if _retired:
		return
	if status == 429:
		_next_poll_msec = maxi(_next_poll_msec, _now() + maxi(retry_after * 1000, POLL_INTERVAL_MSEC))
	if not _note_status(status) or not data.has("open"):
		return
	_set_cache(data)
	_release_held()
	_pump()


func _set_cache(data: Dictionary) -> void:
	if state.cache == data:
		return
	state.set_cache(data)
	finale_changed.emit()


## A held write goes back in line once the cache says it can succeed.
func _release_held() -> void:
	var released := false
	for item in state.queue:
		if not bool(item.get("held", false)):
			continue
		var ok := false
		if item.get("op") == "setting":
			ok = bool(_handoff_info(str(item.get("handoff_id", ""))).get("available", false))
		elif item.get("op") == "note":
			ok = bool(state.cache.get("open", false))
		if ok:
			item.erase("held")
			released = true
	if released:
		state.save()
		status_changed.emit()


func _handoff_info(id: String) -> Dictionary:
	for entry: Variant in state.cache.get("handoffs", []):
		if entry is Dictionary and str(entry.get("id", "")) == id:
			return entry
	return {}


# --- Queue -----------------------------------------------------------------------------


func _pump() -> void:
	if _in_flight or _retired or not transport.is_valid() or _device_id == "":
		return
	if _now() < _next_attempt_msec:
		return
	var item := _next_item()
	if item.is_empty():
		return
	var request := _request_for(item)
	_in_flight = true
	_call(request["method"], request["path"], request["body"], _on_item_done.bind(item, _generation))


func _next_item() -> Dictionary:
	for item in state.queue:
		if not bool(item.get("held", false)):
			return item
	return {}


func _request_for(item: Dictionary) -> Dictionary:
	match str(item.get("op", "")):
		"setting":
			return {
				"method": "POST",
				"path": "/finale/handoffs/%s/settings" % str(item.get("handoff_id", "")),
				"body": {"device_id": _device_id, "setting_index": int(item.get("setting_index", 0))},
			}
		"note":
			return {"method": "POST", "path": "/finale/notes", "body": {"device_id": _device_id, "code": str(item.get("code", ""))}}
	return {"method": "POST", "path": "/devices", "body": _registration_body()}


func _registration_body() -> Dictionary:
	var body := {"device_id": _device_id}
	if _display_name != "":
		body["display_name"] = _display_name
	if _crew != "":
		body["crew"] = _crew
	return body


func _on_item_done(status: int, data: Dictionary, retry_after: int, item: Dictionary, generation: int) -> void:
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
		_apply_answer(item, data)
		_remove(item)
		_pump()
		return
	var code := _error_code(data)
	if (status == 403 and code == "finale_closed") or (status == 409 and code == "handoff_waiting"):
		item["held"] = true
		state.save()
		status_changed.emit()
		_pump()  # other writes may still go
		return
	if status == 404 and code == "device_not_registered" and item.get("op") != "register" and not item.has("registered_first"):
		item["registered_first"] = true  # once per write, so a wiped server cannot loop us
		state.queue.push_front({"op": "register"})
		state.save()
		_pump()
		return
	item["errors"] = int(item.get("errors", 0)) + 1
	if item["errors"] >= MAX_CLIENT_ERRORS:
		_remove(item)
		_pump()
		return
	state.save()
	_back_off(0)


## Folds the server's answer to a write into the cached GET /finale object.
func _apply_answer(item: Dictionary, data: Dictionary) -> void:
	var cache := state.cache.duplicate(true)
	if cache.is_empty():
		return
	if item.get("op") == "setting" and data.get("handoff") is Dictionary:
		var fresh: Dictionary = data["handoff"]
		var list: Array = cache.get("handoffs", [])
		for i in list.size():
			if list[i] is Dictionary and str(list[i].get("id", "")) == str(fresh.get("id", "")):
				list[i] = fresh
		cache["handoffs"] = list
	elif item.get("op") == "note" and data.get("notes") is Dictionary:
		cache["notes"] = data["notes"]
	_set_cache(cache)


func _remove(item: Dictionary) -> void:
	for i in state.queue.size():
		if is_same(state.queue[i], item):
			state.queue.remove_at(i)
			break
	state.save()
	status_changed.emit()


func _back_off(at_least_msec: int) -> void:
	var next := BACKOFF_START_MSEC if _backoff_msec == 0 else _backoff_msec * 2
	_backoff_msec = clampi(maxi(next, at_least_msec), BACKOFF_START_MSEC, BACKOFF_MAX_MSEC)
	_next_attempt_msec = _now() + _backoff_msec


# --- The start code (online only) ---------------------------------------------------------


## POST /finale/start. `done(result: String)` is one of START_STARTED, START_WRONG,
## START_NOT_READY (409), START_CLOSED (403), START_OFFLINE or START_BUSY (429).
func submit_start(typed: String, done: Callable) -> void:
	var digits := ""
	for ch in typed:
		if ch >= "0" and ch <= "9":
			digits += ch
	if _starting:
		return  # a second tap while one is pending is ignored
	if not transport.is_valid() or _retired or _device_id == "":
		_finish_start(done, START_OFFLINE)
		return
	_starting = true
	_start_request(digits, done, false)


func _finish_start(done: Callable, result: String) -> void:
	_starting = false
	if done.is_valid():
		done.call(result)


func _start_request(digits: String, done: Callable, registered: bool) -> void:
	_call("POST", "/finale/start", {"device_id": _device_id, "code": digits}, _on_start.bind(digits, done, registered))


func _on_start(status: int, data: Dictionary, _retry_after: int, digits: String, done: Callable, registered: bool) -> void:
	if _retired:
		return
	if status == 0 or status >= 500:
		_set_online(false)
		_finish_start(done, START_OFFLINE)
		return
	_set_online(true)
	if status == 404 and _error_code(data) == "device_not_registered" and not registered:
		_call("POST", "/devices", _registration_body(), func(_s: int, _d: Dictionary, _r: int) -> void: _start_request(digits, done, true))
		return
	if status == 429:
		_finish_start(done, START_BUSY)
	elif status == 403:
		_finish_start(done, START_CLOSED)
	elif status == 409:
		_finish_start(done, START_NOT_READY)
	elif status >= 200 and status < 300 and bool(data.get("valid", false)) and bool(data.get("started", false)):
		var cache := state.cache.duplicate(true)
		cache["started"] = true
		cache["started_at"] = data.get("started_at")
		_set_cache(cache)
		_finish_start(done, START_STARTED)
		refresh()
	elif status >= 200 and status < 300:
		_finish_start(done, START_WRONG)
	else:
		_finish_start(done, START_OFFLINE)


# --- Plumbing --------------------------------------------------------------------------


func _call(method: String, path: String, body: Dictionary, done: Callable) -> void:
	if not transport.is_valid():
		done.call(0, {}, 0)
		return
	transport.call(method, base_url + API_PREFIX + path, body, done)


func _note_status(status: int) -> bool:
	if status == 0 or status >= 500:
		_set_online(false)
		return false
	_set_online(true)
	return status >= 200 and status < 300


func _set_online(value: bool) -> void:
	_failed = not value
	if _online != value:
		_online = value
		status_changed.emit()


func _error_code(data: Dictionary) -> String:
	var error: Variant = data.get("error")
	return str(error.get("code", "")) if error is Dictionary else ""


func _now() -> int:
	return clock_override if clock_override >= 0 else Time.get_ticks_msec()
