# SPDX-License-Identifier: AGPL-3.0-or-later
class_name FakeScoreboard
extends RefCounted
## A stand-in for the network: RemoteProgressStore's `transport` is
## `fake.transport()`. Requests are logged; answers are canned and no socket is
## opened. Usage:
##   var fake := FakeScoreboard.new()
##   fake.answer("POST", "/devices", 200, {"created": true})   # sticky answer
##   fake.answer_once("GET", "/hints", 500, {})                # used once, then the sticky one
##   fake.offline = true                                       # status 0 for everything
##   fake.hold = true                                          # keep callbacks in `held`, run with release()

const BASE := "https://board.test"

var requests: Array[Dictionary] = []  # {method, path, body}
var offline := false
var hold := false
var held: Array[Callable] = []
var _sticky: Dictionary = {}
var _once: Dictionary = {}


func transport() -> Callable:
	return Callable(self, "handle")


## `path` is matched without the query string.
func answer(method: String, path: String, status: int, data: Dictionary, retry_after: int = 0) -> void:
	_sticky[method + " " + path] = [status, data, retry_after]


func answer_once(method: String, path: String, status: int, data: Dictionary, retry_after: int = 0) -> void:
	var key := method + " " + path
	if not _once.has(key):
		_once[key] = []
	_once[key].append([status, data, retry_after])


func handle(method: String, url: String, body: Dictionary, done: Callable) -> void:
	var path := url.trim_prefix(BASE + RemoteProgressStore.API_PREFIX)
	requests.append({"method": method, "path": path, "body": body})
	var key := method + " " + path.get_slice("?", 0)
	var reply: Array = [200, {}, 0]
	if offline:
		reply = [0, {}, 0]
	elif _once.has(key) and not _once[key].is_empty():
		reply = _once[key].pop_front()
	elif _sticky.has(key):
		reply = _sticky[key]
	if hold:
		held.append(func() -> void: done.call(reply[0], reply[1], reply[2]))
	else:
		done.call(reply[0], reply[1], reply[2])


## Runs every held callback (the network "answers").
func release() -> void:
	var now := held.duplicate()
	held.clear()
	for callback in now:
		callback.call()


## Requests that changed state, as "METHOD /path".
func posts() -> Array[String]:
	var out: Array[String] = []
	for r in requests:
		if r["method"] == "POST":
			out.append("POST " + str(r["path"]))
	return out


func last_post_body() -> Dictionary:
	for i in range(requests.size() - 1, -1, -1):
		if requests[i]["method"] == "POST":
			return requests[i]["body"]
	return {}


func count(method: String, path_prefix: String) -> int:
	var n := 0
	for r in requests:
		if r["method"] == method and str(r["path"]).begins_with(path_prefix):
			n += 1
	return n


static func crew(machine: String, counts: Dictionary, runs: bool = false, contributors: Array = []) -> Dictionary:
	var parts: Array = []
	for part in Ids.PARTS:
		var n := int(counts.get(part, 0))
		parts.append({"part": part, "solved": n > 0, "solved_count": n, "first_solved_at": null})
	return {
		"machine": machine,
		"name": Ids.machine_title(machine),
		"runs": runs,
		"parts_solved": counts.size(),
		"parts_total": 6,
		"members": 3,
		"parts": parts,
		"contributors": contributors,
	}


static func hint(id: int, to_crew: String, nudge_id: String = "reread_the_clue", from_name: String = "Mina") -> Dictionary:
	return {
		"id": id, "to_crew": to_crew, "from_crew": "oven", "from_name": from_name,
		"nudge_id": nudge_id, "created_at": "2027-10-29T18:05:00Z",
	}


static func error(code: String) -> Dictionary:
	return {"error": {"code": code, "message": code}}
