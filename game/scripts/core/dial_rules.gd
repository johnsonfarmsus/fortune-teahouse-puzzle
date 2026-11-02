# SPDX-License-Identifier: AGPL-3.0-or-later
class_name DialRules
extends RefCounted
## Pure logic for the `dials` handoff puzzle (docs/FINALE-DESIGN.md section 3).
## Each dial holds an index into its `values`. A test marks every dial against
## its answer (ok, low, high or wrong), locks the ones that are right, and shows
## the rest. Nothing here is an engine node, and the answers come from config.
##
## Dial config: {id, setting_index, label, unit, ordered, values, labels, start,
## answer, low, high, wrong, hint}. `start` is an index and is never the answer;
## `answer` is a value. `labels` (if any) are shown instead of the values.

const OK := "ok"
const LOW := "low"
const HIGH := "high"
const WRONG := "wrong"

## The dial dictionaries, in config order (values normalised to ints where whole).
var dials: Array[Dictionary] = []
## Setting indices locked by the last test() or reveal(), in dial order.
var last_locked: Array[int] = []

var _by_id: Dictionary = {}  # id -> dial
var _index: Dictionary = {}  # id -> current index into values
var _locked: Dictionary = {}  # id -> true


func _init(config: Dictionary = {}) -> void:
	for raw: Variant in config.get("dials", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = (raw as Dictionary).duplicate(true)
		var values: Array = []
		for v: Variant in entry.get("values", []):
			values.append(normalise_value(v))
		entry["values"] = values
		entry["answer"] = normalise_value(entry.get("answer"))
		entry["setting_index"] = int(entry.get("setting_index", dials.size()))
		entry["start"] = int(entry.get("start", 0))
		entry["ordered"] = bool(entry.get("ordered", true))
		var id := str(entry.get("id", ""))
		dials.append(entry)
		_by_id[id] = entry
		_index[id] = clampi(int(entry["start"]), 0, maxi(values.size() - 1, 0))
	for setting in config.get("locked_indices", []):
		lock_setting(int(setting))


## JSON numbers arrive as floats: whole ones become ints.
static func normalise_value(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)):
		return int(v)
	return v


# --- Reading ---------------------------------------------------------------------------


func ids() -> Array[String]:
	var out: Array[String] = []
	for d in dials:
		out.append(str(d["id"]))
	return out


func has_dial(id: String) -> bool:
	return _by_id.has(id)


func dial(id: String) -> Dictionary:
	return _by_id.get(id, {})


func current_index(id: String) -> int:
	return int(_index.get(id, 0))


func value(id: String) -> Variant:
	var values: Array = dial(id).get("values", [])
	return values[current_index(id)] if not values.is_empty() else null


## {id: value} for every dial.
func values() -> Dictionary:
	var out: Dictionary = {}
	for id in ids():
		out[id] = value(id)
	return out


## The text shown for a value: its label, or the number with the unit
## ("3 cm per second", "1 tick").
func value_text(id: String, at: int = -1) -> String:
	var d := dial(id)
	var i := current_index(id) if at < 0 else at
	var labels: Array = d.get("labels", [])
	if i >= 0 and i < labels.size():
		return str(labels[i])
	var values: Array = d.get("values", [])
	if i < 0 or i >= values.size():
		return ""
	var unit := str(d.get("unit", ""))
	if unit == "":
		return str(values[i])
	if values[i] is int and values[i] == 1 and unit.ends_with("s"):
		unit = unit.trim_suffix("s")
	return "%s %s" % [str(values[i]), unit]


func answer_value(id: String) -> Variant:
	return dial(id).get("answer")


func setting_index(id: String) -> int:
	return int(dial(id).get("setting_index", -1))


func id_for_setting(setting_index_: int) -> String:
	for d in dials:
		if int(d["setting_index"]) == setting_index_:
			return str(d["id"])
	return ""


func is_locked(id: String) -> bool:
	return _locked.has(id)


func locked_ids() -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		if _locked.has(id):
			out.append(id)
	return out


func all_locked() -> bool:
	return not dials.is_empty() and _locked.size() == dials.size()


func first_unlocked() -> String:
	for id in ids():
		if not _locked.has(id):
			return id
	return ""


## The dial's message for a mark ("" for ok).
func message(id: String, mark: String) -> String:
	match mark:
		LOW:
			return str(dial(id).get("low", ""))
		HIGH:
			return str(dial(id).get("high", ""))
		WRONG:
			return str(dial(id).get("wrong", ""))
	return ""


## The mark of the dial's current value, without testing or locking.
func mark(id: String) -> String:
	return mark_value(dial(id), value(id))


## ok, or low/high for an ordered dial (by position in `values`), or wrong for an unordered one.
static func mark_value(d: Dictionary, v: Variant) -> String:
	var values: Array = d.get("values", [])
	var answer_at := values.find(d.get("answer"))
	var at := values.find(normalise_value(v))
	if at == answer_at:
		return OK
	if not bool(d.get("ordered", true)):
		return WRONG
	return LOW if at < answer_at else HIGH


# --- Changing --------------------------------------------------------------------------


## Moves a dial by `delta` places, stopping at the ends. False if locked or unchanged.
func step(id: String, delta: int) -> bool:
	if not has_dial(id) or is_locked(id):
		return false
	var count := (dial(id)["values"] as Array).size()
	var next := clampi(current_index(id) + delta, 0, count - 1)
	if next == current_index(id):
		return false
	_index[id] = next
	return true


## Sets a dial to a value it can take. False if locked or not one of its values.
func set_value(id: String, v: Variant) -> bool:
	if not has_dial(id) or is_locked(id):
		return false
	var at := (dial(id)["values"] as Array).find(normalise_value(v))
	if at < 0:
		return false
	_index[id] = at
	return true


## Locks the dial that serves a server setting (progress already made on this phone).
func lock_setting(setting_index_: int) -> void:
	var id := id_for_setting(setting_index_)
	if id == "":
		return
	_locked[id] = true
	var values: Array = dial(id)["values"]
	_index[id] = maxi(values.find(answer_value(id)), 0)


## A test run: marks every dial, and locks each dial that is right. Returns
## {id: mark}; a locked dial is always ok. `last_locked` lists the setting
## indices locked by this call.
func test() -> Dictionary:
	var marks: Dictionary = {}
	last_locked = []
	for d in dials:
		var id := str(d["id"])
		var m := OK if is_locked(id) else mark(id)
		marks[id] = m
		if m == OK and not is_locked(id):
			_locked[id] = true
			last_locked.append(int(d["setting_index"]))
	return marks


## Level 3: every dial still open takes its answer and locks. Returns their setting indices.
func reveal() -> Array[int]:
	last_locked = []
	for d in dials:
		var id := str(d["id"])
		if is_locked(id):
			continue
		lock_setting(int(d["setting_index"]))
		last_locked.append(int(d["setting_index"]))
	return last_locked


# --- The beats preview -------------------------------------------------------------------


## Ticks (0 to ticks - 1) where a printed fortune lands: start + dry + chute_ticks + k * every.
static func beats_landing(start: int, dry: int, every: int, chute_ticks: int, ticks: int) -> Array[int]:
	var out: Array[int] = []
	if every < 1:
		return out
	var tick := start + dry + chute_ticks
	while tick < ticks:
		out.append(tick)
		tick += every
	return out
