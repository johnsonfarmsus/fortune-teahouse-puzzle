# SPDX-License-Identifier: AGPL-3.0-or-later
extends SceneTree
## Finale integration run against a REAL scoreboard (not a fake): three
## simulated phones use the game's own HttpTransport, FinaleClient, FinaleState,
## FinaleData and DialRules. Nothing here ships in the game and CI never runs it.
##
## How to run (see README.md, "Finale integration run"):
##   cd server
##   ADMIN_SECRET=test GNU_NOTE_CODES=KETTLE27,GULLWING41,DRIPCOFFEE08,CROSSWIND63,INKBLOT19,SALTWATER52 \
##   GNU_NOTES_K=4 START_CODE=3141592653 HANDOFF_SETTINGS_TOTAL=3 DATABASE_PATH=/tmp/sb.db \
##   python3 -m uvicorn app.main:create_app --factory --port 8000
##   # in another shell, from the repository root (a fresh database, or reset progress first):
##   godot --headless --path game -s ../tools/dev/finale_integration.gd
## Set SCOREBOARD_URL to use another address (default http://localhost:8000). Exit code 0 means
## every check passed. The run starts the line, so reset the server before running it again:
##   curl -X POST $SCOREBOARD_URL/api/v1/admin/reset -H 'X-Admin-Secret: test' \
##        -H 'Content-Type: application/json' -d '{"confirm":"reset","scope":"progress"}'
##
## What it does: it first runs all three machines through plain API calls (three seed devices, six
## parts each), then plays three phones, one per crew. Each phone holds its own crew's handoff note,
## collects ONE other crew's handoff word, checks which handoffs its notes let it open, solves
## those dials through DialRules (answers read from game/data/finale/handoffs.json) and posts the
## settings through FinaleClient. Then they file four of the gnu's note codes, and one phone posts
## the start code. Every step is checked against GET /finale and GET /summary.

const SEED_PARTS: Array[String] = ["logic", "wiring", "sequence", "word", "rhythm", "helper"]
const START_CODE := "3141592653"
const WAIT_SECONDS := 20.0

var base := ""
var transport: HttpTransport
var data: FinaleData
var failures := 0
var phones: Array = []


## One simulated phone.
class Phone:
	extends RefCounted
	var name := ""
	var crew := ""
	var device_id := ""
	var state: FinaleState
	var client: FinaleClient


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame  # the root joins the tree after _initialize
	var url := OS.get_environment("SCOREBOARD_URL")
	base = (url if url != "" else "http://localhost:8000").rstrip("/")
	transport = HttpTransport.new()
	root.add_child(transport)
	data = FinaleData.new()
	_check(data.errors().is_empty(), "finale data is sound (%s)" % str(data.errors()))

	var health := await _call("GET", "/health")
	if health["status"] != 200:
		print("FAIL - no scoreboard answered at %s (is it running?)" % base)
		quit(1)
		return

	# 1. All three machines run (seed devices; idempotent).
	await _seed_machines()
	var finale := await _finale()
	_check(not bool(finale.get("started", false)), "line has not started yet (reset the server to rerun)")
	_check(bool(finale["open"]) and str(finale["open_reason"]) == "all_machines_run", "finale is open because all machines run")
	for entry: Dictionary in finale["handoffs"]:
		_check(bool(entry["available"]), "handoff %s is available" % entry["id"])
	_check(int(finale["notes"]["total"]) == 6 and int(finale["notes"]["needed"]) == 4, "server expects 4 of 6 notes")

	# 2. Three phones, one per crew. Phone 3 is not registered yet: FinaleClient must register it.
	for spec: Array in [["Cookie phone", "cookie_machine"], ["Fortune phone", "fortune_machine"], ["Oven phone", "oven"]]:
		var phone := Phone.new()
		phone.name = spec[0]
		phone.crew = spec[1]
		phone.device_id = "itest-phone-%s" % phone.crew
		phone.state = FinaleState.new("")  # in memory, nothing written to disk
		phone.client = FinaleClient.new(base, phone.state, Callable(transport, "request"))
		phones.append(phone)
		if phone.crew != "oven":
			var registered := await _call("POST", "/devices", {"device_id": phone.device_id, "display_name": phone.name, "crew": phone.crew})
			_check(registered["status"] == 200, "%s registered with its crew" % phone.name)
		phone.client.set_identity(phone.device_id, phone.crew, phone.name)
		phone.client.refresh()
	for phone: Phone in phones:
		await _wait(func() -> bool: return bool(phone.client.finale().get("open", false)), "%s hears that the finale is open" % phone.name)

	# 3. Each phone holds its own crew's note (its machine runs) and Gopher's free slip.
	for phone: Phone in phones:
		var crew := await _call("GET", "/crews/%s" % phone.crew)
		_check(bool(crew["data"]["runs"]), "%s: the %s machine runs on the server" % [phone.name, phone.crew])
		phone.state.grant_note(data.note_id_for_machine(phone.crew))
		for note in data.notes:
			if bool(note.get("free", false)):
				phone.state.grant_note(str(note["id"]))
		_check(phone.state.has_note(phone.crew) and phone.state.has_note("gopher"), "%s holds its crew note and Gopher's slip" % phone.name)

	# 4. Each phone collects ONE other crew's handoff word, then plays what its notes allow.
	var word_from := {"cookie_machine": "oven", "fortune_machine": "oven", "oven": "cookie_machine"}
	for phone: Phone in phones:
		var word := str(data.note(str(word_from[phone.crew])).get("handoff_word", ""))
		var note := data.note_for_word(word)
		_check(not note.is_empty() and phone.state.grant_note(str(note["id"])), "%s collects the word %s" % [phone.name, word])
	var expected_open := {
		"cookie_machine": ["cookie_to_oven", "oven_to_packaging"],
		"fortune_machine": ["fortune_to_oven", "oven_to_packaging"],
		"oven": ["cookie_to_oven", "oven_to_packaging"],
	}
	for phone: Phone in phones:
		var opened: Array[String] = []
		for handoff_id in data.handoff_ids():
			if _can_open(phone, handoff_id):
				opened.append(handoff_id)
		_check(opened == expected_open[phone.crew], "%s can open %s" % [phone.name, str(opened)])
		for handoff_id in opened:
			_solve_dials(phone, handoff_id)
	for phone: Phone in phones:
		await _wait(func() -> bool: return phone.client.queue_size() == 0, "%s's queue drains (settings sent)" % phone.name)
		_check(phone.client.is_online(), "%s: scoreboard reachable" % phone.name)

	finale = await _finale()
	for entry: Dictionary in finale["handoffs"]:
		_check(int(entry["settings_solved"]) == 3 and bool(entry["complete"]) and str(entry["status"]) == "connected", "handoff %s is 3 of 3, connected (solved_indices %s)" % [entry["id"], ",".join((entry["solved_indices"] as Array).map(func(i: Variant) -> String: return str(int(i))))])
	_check(not bool(finale["line_ready"]), "line is not ready yet (notes missing)")
	var early: Array = []
	phones[0].client.submit_start(START_CODE, func(result: String) -> void: early.append(result))
	await _wait(func() -> bool: return not early.is_empty(), "early start answered")
	_check(early == [FinaleClient.START_NOT_READY], "start code before the line is ready is refused as not ready (got %s)" % str(early))

	# 5. Four gnu-note codes, filed on three phones; one is a repeat that must not count twice.
	var filing := {"cookie_machine": ["note_1", "note_2"], "fortune_machine": ["note_3", "note_4"], "oven": ["note_1"]}
	for phone: Phone in phones:
		for note_id: String in filing[phone.crew]:
			var code := str(data.gnu_note(note_id)["code"])
			_check(phone.state.add_gnu_note(note_id, FinaleData.normalise_code(code)), "%s files %s" % [phone.name, code])
	for phone: Phone in phones:
		await _wait(func() -> bool: return phone.client.queue_size() == 0, "%s's queue drains (notes sent)" % phone.name)
	finale = await _finale()
	_check(int(finale["notes"]["found"]) == 4 and int(finale["notes"]["total"]) == 6 and bool(finale["notes"]["complete"]), "notes are 4 of 6 and complete (got %s)" % _notes_text(finale))
	_check(bool(finale["line_ready"]) and not bool(finale["started"]), "line_ready is true, not started")

	# 6. One phone posts the start code: wrong first, then right.
	var wrong: Array = []
	phones[2].client.submit_start("2718281828", func(result: String) -> void: wrong.append(result))
	await _wait(func() -> bool: return not wrong.is_empty(), "wrong start code answered")
	_check(wrong == [FinaleClient.START_WRONG], "a wrong start code is refused (got %s)" % str(wrong))
	var right: Array = []
	phones[0].client.submit_start(START_CODE, func(result: String) -> void: right.append(result))
	await _wait(func() -> bool: return not right.is_empty(), "start code answered")
	_check(right == [FinaleClient.START_STARTED], "the right start code starts the line (got %s)" % str(right))
	_check(bool(phones[0].client.finale().get("started", false)), "the phone's cached finale says started")

	# 7. Final state, straight from the server.
	finale = await _finale()
	var summary := await _call("GET", "/summary")
	var sfinale: Dictionary = summary["data"]["finale"]
	_check(bool(finale["started"]) and finale["started_at"] != null, "GET /finale: started at %s" % str(finale["started_at"]))
	_check(bool(sfinale["started"]) and bool(sfinale["line_ready"]) and sfinale == finale, "GET /summary finale matches GET /finale")
	_check(int(summary["data"]["machines_running"]) == 3, "GET /summary: 3 machines running")
	print("FINAL /finale: open=%s line_ready=%s started=%s notes=%s handoffs=%s" % [finale["open"], finale["line_ready"], finale["started"], _notes_text(finale), str((finale["handoffs"] as Array).map(func(h: Dictionary) -> String: return "%s %d/%d" % [h["id"], int(h["settings_solved"]), int(h["settings_total"])]))])
	print("FINAL /summary: machines_running=%d devices_total=%d contributors_total=%d" % [int(summary["data"]["machines_running"]), int(summary["data"]["devices_total"]), int(summary["data"]["contributors"]["total"])])
	print("RESULT: %s (%d failed checks)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


# --- Phone behaviour ---------------------------------------------------------------------------


## True when the phone holds every note the handoff needs and the cached finale says it is available.
func _can_open(phone: Phone, handoff_id: String) -> bool:
	for need: Variant in data.handoff(handoff_id).get("needs", []):
		if not phone.state.has_note(str(need)):
			return false
	for entry: Variant in phone.client.finale().get("handoffs", []):
		if entry is Dictionary and entry.get("id") == handoff_id:
			return bool(entry.get("available", false))
	return false


## Plays the dials the way the puzzle does: wrong at the start, then the right settings, one test batch.
func _solve_dials(phone: Phone, handoff_id: String) -> void:
	var rules := DialRules.new(data.handoff(handoff_id)["config"])
	var first := rules.test()  # the start values are never right
	_check(not first.values().has(DialRules.OK), "%s: %s starts with every dial wrong" % [phone.name, handoff_id])
	for id in rules.ids():
		rules.set_value(id, rules.answer_value(id))
	var marks := rules.test()
	_check(not marks.values().has(DialRules.LOW) and not marks.values().has(DialRules.HIGH) and rules.all_locked(), "%s: %s test batch locks all three dials" % [phone.name, handoff_id])
	for setting in rules.last_locked:
		phone.state.add_setting(handoff_id, setting)


func _notes_text(finale: Dictionary) -> String:
	var n: Dictionary = finale["notes"]
	return "found %d of %d, needed %d, complete %s" % [int(n["found"]), int(n["total"]), int(n["needed"]), str(n["complete"])]


# --- Server helpers ----------------------------------------------------------------------------


func _seed_machines() -> void:
	var n := 0
	for crew in ["fortune_machine", "cookie_machine", "oven"]:
		n += 1
		var device := "itest-seed-%d" % n
		await _call("POST", "/devices", {"device_id": device, "display_name": "Seed %d" % n, "crew": crew})
		for part in SEED_PARTS:
			var result := await _call("POST", "/crews/%s/parts/%s/solve" % [crew, part], {"device_id": device, "credited": true})
			if result["status"] != 200:
				_check(false, "seed solve %s/%s answered %d" % [crew, part, result["status"]])
		var state := await _call("GET", "/crews/%s" % crew)
		_check(bool(state["data"]["runs"]), "%s runs after six parts" % crew)


func _finale() -> Dictionary:
	var result := await _call("GET", "/finale")
	return result["data"]


## One real HTTP call through the game's HttpTransport. Returns {status, data}.
func _call(method: String, path: String, body: Dictionary = {}) -> Dictionary:
	var box: Array = []
	transport.request(method, base + "/api/v1" + path, body, func(status: int, parsed: Dictionary, _retry: int) -> void: box.append({"status": status, "data": parsed}))
	while box.is_empty():
		await process_frame
	return box[0]


## Waits (up to WAIT_SECONDS) for a condition, ticking every phone's client like Finale's 1 s timer.
func _wait(condition: Callable, label: String) -> void:
	var started := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - started) / 1000.0 > WAIT_SECONDS:
			_check(false, "timed out: " + label)
			return
		for phone: Phone in phones:
			phone.client.tick()
		await process_frame
	_check(true, label)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("ok   - ", label)
	else:
		failures += 1
		print("FAIL - ", label)
