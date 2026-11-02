# SPDX-License-Identifier: AGPL-3.0-or-later
class_name FinaleData
extends RefCounted
## Loads the finale's three data files (docs/FINALE-DESIGN.md section 7) and
## checks them: handoffs.json (notes and dials handoffs), gnu_notes.json (the
## gnu's six notes with their in-game twins) and readme.json. Answers live in
## these files, never in scripts. Also holds the small pure text helpers the
## finale screens share.

const HANDOFFS_PATH := "res://data/finale/handoffs.json"
const GNU_NOTES_PATH := "res://data/finale/gnu_notes.json"
const README_PATH := "res://data/finale/readme.json"
const CODE_PATTERN := "^[A-Z]+ [0-9]{2}$"
const SETTINGS_PER_HANDOFF := 3

var notes: Array[Dictionary] = []  # [{id, title, handoff_word, free, text}]
var handoffs: Array[Dictionary] = []  # [{id, title, needs, type, config}]
var gnu_notes: Array[Dictionary] = []  # [{id, code, venue, text, twin: {speaker, config}}]
var needed: int = 4
var readme: Dictionary = {}


func _init(
	handoffs_path: String = HANDOFFS_PATH, gnu_notes_path: String = GNU_NOTES_PATH, readme_path: String = README_PATH
) -> void:
	var raw := JsonFile.read(handoffs_path)
	for entry: Variant in raw.get("notes", []):
		if entry is Dictionary:
			notes.append(entry)
	for entry: Variant in raw.get("handoffs", []):
		if entry is Dictionary:
			handoffs.append(entry)
	var gnu := JsonFile.read(gnu_notes_path)
	needed = int(gnu.get("needed", 4))
	for entry: Variant in gnu.get("notes", []):
		if entry is Dictionary:
			gnu_notes.append(entry)
	readme = JsonFile.read(readme_path)


# --- Lookups --------------------------------------------------------------------------


func note(id: String) -> Dictionary:
	for entry in notes:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func handoff(id: String) -> Dictionary:
	for entry in handoffs:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func handoff_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in handoffs:
		out.append(str(entry.get("id", "")))
	return out


func gnu_note(id: String) -> Dictionary:
	for entry in gnu_notes:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


## The gnu note whose code matches what was typed (case, spaces and punctuation ignored), or {}.
func gnu_note_for_code(typed: String) -> Dictionary:
	var wanted := normalise_code(typed)
	if wanted == "":
		return {}
	for entry in gnu_notes:
		if normalise_code(str(entry.get("code", ""))) == wanted:
			return entry
	return {}


## The handoff note that prints this handoff word, or {}.
func note_for_word(typed: String) -> Dictionary:
	var wanted := LuckyWords.normalise(typed)
	if wanted == "":
		return {}
	for entry in notes:
		var word := str(entry.get("handoff_word", ""))
		if word != "" and LuckyWords.normalise(word) == wanted:
			return entry
	return {}


## The crew's note id for a machine (the note whose id is the machine id), or "".
func note_id_for_machine(machine: String) -> String:
	return machine if not note(machine).is_empty() and Ids.MACHINES.has(machine) else ""


func handoff_words() -> Array[String]:
	var out: Array[String] = []
	for entry in notes:
		if str(entry.get("handoff_word", "")) != "":
			out.append(str(entry["handoff_word"]))
	return out


func readme_triggers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: Variant in readme.get("sections", []):
		if section is Dictionary and section.get("trigger") is Dictionary:
			out.append(section["trigger"])
	return out


# --- Validation -----------------------------------------------------------------------


## Problems found in the data, as plain sentences. Empty means the data is sound.
func errors() -> Array[String]:
	var out: Array[String] = []
	var note_ids: Array[String] = []
	for entry in notes:
		var id := str(entry.get("id", ""))
		if id == "" or note_ids.has(id):
			out.append("note id missing or repeated: '%s'" % id)
		note_ids.append(id)
		var free := bool(entry.get("free", false))
		var word := str(entry.get("handoff_word", ""))
		if free != (word == ""):
			out.append("note %s: a free note has no handoff word, any other has one" % id)
		if str(entry.get("text", "")) == "" or str(entry.get("title", "")) == "":
			out.append("note %s: title and text are required" % id)
	if handoffs.is_empty():
		out.append("no handoffs")
	for entry in handoffs:
		out.append_array(_handoff_errors(entry, note_ids))
	if gnu_notes.is_empty():
		out.append("no gnu notes")
	var regex := RegEx.create_from_string(CODE_PATTERN)
	var codes: Array[String] = []
	for entry in gnu_notes:
		var id := str(entry.get("id", ""))
		var code := str(entry.get("code", ""))
		if regex.search(code) == null:
			out.append("gnu note %s: code '%s' is not a word and two digits" % [id, code])
		if codes.has(normalise_code(code)):
			out.append("gnu note %s: code repeated" % id)
		codes.append(normalise_code(code))
		out.append_array(_twin_errors(entry))
	if needed < 1 or needed > gnu_notes.size():
		out.append("needed must be between 1 and the number of gnu notes")
	for trigger in readme_triggers():
		if not _trigger_ok(trigger):
			out.append("README trigger not valid: %s" % str(trigger))
	if readme_triggers().size() != (readme.get("sections", []) as Array).size():
		out.append("every README section needs a trigger")
	return out


func _handoff_errors(entry: Dictionary, note_ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var id := str(entry.get("id", ""))
	for need: Variant in entry.get("needs", []):
		if not note_ids.has(str(need)):
			out.append("handoff %s needs a note that does not exist: %s" % [id, str(need)])
	if str(entry.get("type", "")) != "dials":
		out.append("handoff %s: only the dials type exists" % id)
	var config: Dictionary = entry.get("config", {})
	var indices: Array[int] = []
	var dial_ids: Array[String] = []
	for dial: Variant in config.get("dials", []):
		if not dial is Dictionary:
			out.append("handoff %s: a dial is not an object" % id)
			continue
		indices.append(int(dial.get("setting_index", -1)))
		dial_ids.append(str(dial.get("id", "")))
		out.append_array(_dial_errors(id, dial))
	indices.sort()
	var expected: Array[int] = []
	for i in SETTINGS_PER_HANDOFF:
		expected.append(i)
	if indices != expected:
		out.append("handoff %s: setting indices must be exactly 0 to %d" % [id, SETTINGS_PER_HANDOFF - 1])
	var preview: Dictionary = config.get("preview", {})
	for role: Variant in (preview.get("roles", {}) as Dictionary).values():
		if not dial_ids.has(str(role)):
			out.append("handoff %s: preview role names an unknown dial: %s" % [id, str(role)])
	for chute: Variant in preview.get("chutes", []):
		if not dial_ids.has(str(chute)):
			out.append("handoff %s: preview chute names an unknown dial: %s" % [id, str(chute)])
	return out


func _dial_errors(handoff_id: String, dial: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var label := "%s/%s" % [handoff_id, str(dial.get("id", ""))]
	var values: Array = dial.get("values", [])
	var start := int(dial.get("start", -1))
	if values.size() < 2:
		out.append("dial %s: needs at least two values" % label)
		return out
	if start < 0 or start >= values.size():
		out.append("dial %s: start is not an index of values" % label)
	var answer: Variant = DialRules.normalise_value(dial.get("answer"))
	var normal: Array = []
	for v: Variant in values:
		normal.append(DialRules.normalise_value(v))
	if not normal.has(answer):
		out.append("dial %s: answer is not one of the values" % label)
	elif start >= 0 and start < values.size() and normal[start] == answer:
		out.append("dial %s: start must not be the answer" % label)
	var labels: Array = dial.get("labels", [])
	if not labels.is_empty() and labels.size() != values.size():
		out.append("dial %s: labels and values differ in length" % label)
	if bool(dial.get("ordered", true)):
		if str(dial.get("low", "")) == "" or str(dial.get("high", "")) == "":
			out.append("dial %s: an ordered dial needs low and high messages" % label)
	elif str(dial.get("wrong", "")) == "":
		out.append("dial %s: an unordered dial needs a wrong message" % label)
	if str(dial.get("hint", "")) == "":
		out.append("dial %s: needs a hint" % label)
	return out


func _twin_errors(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var id := str(entry.get("id", ""))
	var twin: Dictionary = entry.get("twin", {})
	var config: Dictionary = twin.get("config", {})
	var choices: Array = config.get("choices", [])
	var correct := int(config.get("correct", -1))
	if choices.size() < 2 or correct < 0 or correct >= choices.size():
		out.append("gnu note %s: twin needs choices and a valid correct index" % id)
	if str(twin.get("speaker", "")) == "" or str(config.get("question", "")) == "":
		out.append("gnu note %s: twin needs a speaker and a question" % id)
	if (config.get("lines", []) as Array).is_empty():
		out.append("gnu note %s: twin needs lines" % id)
	if not str(entry.get("text", "")).ends_with(str(entry.get("code", "?"))):
		out.append("gnu note %s: the text should end with its code" % id)
	return out


func _trigger_ok(trigger: Dictionary) -> bool:
	if trigger.size() != 1:
		return false
	if trigger.has("machine_runs"):
		return Ids.MACHINES.has(str(trigger["machine_runs"]))
	if trigger.has("handoff_connected"):
		return not handoff(str(trigger["handoff_connected"])).is_empty()
	return false


# --- Pure text helpers ----------------------------------------------------------------


## A gnu note code in the form the server compares: uppercase, spaces and punctuation removed.
static func normalise_code(typed: String) -> String:
	return LuckyWords.normalise(typed)


## The status half of a handoff row ("<name>: <status>") from a GET /finale handoff
## object. `waiting_for` are the display names of the machines it waits for.
static func row_status(info: Dictionary, waiting_for: Array[String]) -> String:
	match str(info.get("status", "locked")):
		"connected":
			return "connected"
		"waiting":
			if waiting_for.is_empty():
				return "waiting for the machines"
			return "waiting for the " + " and ".join(waiting_for)
		"in_progress":
			return "%d of %d settings" % [int(info.get("settings_solved", 0)), int(info.get("settings_total", SETTINGS_PER_HANDOFF))]
		"not_started":
			return "not started"
	return "locked"


## "6:00 pm" for an ISO time such as "2027-10-30T01:00:00Z", shifted by
## `bias_minutes` (the viewer's offset from UTC). "" if it cannot be read.
static func format_clock(iso: String, bias_minutes: int) -> String:
	if iso.length() < 16 or not iso.contains("T"):
		return ""
	var unix := Time.get_unix_time_from_datetime_string(iso.substr(0, 19))
	if unix <= 0:
		return ""
	var local := Time.get_datetime_dict_from_unix_time(int(unix) + bias_minutes * 60)
	var hour := int(local["hour"])
	var suffix := "am" if hour < 12 else "pm"
	var shown := hour % 12
	if shown == 0:
		shown = 12
	return "%d:%02d %s" % [shown, int(local["minute"]), suffix]
