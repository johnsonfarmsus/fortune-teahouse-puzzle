# SPDX-License-Identifier: AGPL-3.0-or-later
class_name LocalInventoryStore
extends InventoryStore
## The inventory on this phone only, saved to `path` ("" keeps it in memory):
## {version, crews: {machine: [entries]}}. Without a scoreboard everything can
## still be found alone, so this is the whole inventory offline.

const DEFAULT_PATH := "user://inventory.json"
const VERSION := 1

var path: String
var crews: Dictionary = {}  # machine -> Array[Dictionary] in find order
## Tests set this to fix found_at; empty means the real clock.
var now_override: String = ""


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	if path != "":
		var data := JsonFile.read(path)
		var raw: Dictionary = data.get("crews", {})
		for machine: String in raw:
			var list: Array[Dictionary] = []
			for e: Variant in raw[machine]:
				if e is Dictionary and InventoryStore.rank(str(e.get("state", ""))) >= 0:
					list.append(e)
			crews[machine] = list


func items(machine: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in crews.get(machine, []):
		out.append(e.duplicate())
	return out


## Records a find or an install. Returns true if anything changed.
func mark(machine: String, item_id: String, state: String, place: String, device_id: String) -> bool:
	if InventoryStore.rank(state) < 0 or item_id == "":
		return false
	if not crews.has(machine):
		crews[machine] = [] as Array[Dictionary]
	var list: Array = crews[machine]
	for e: Dictionary in list:
		if str(e["item_id"]) == item_id:
			if InventoryStore.rank(state) <= InventoryStore.rank(str(e["state"])):
				return false
			e["state"] = state
			if place != "":
				e["place"] = place
			_save()
			changed.emit(machine)
			return true
	list.append({"item_id": item_id, "state": state, "found_by": device_id, "found_at": _now(), "place": place})
	_save()
	changed.emit(machine)
	return true


## Takes a row the scoreboard sent (a crewmate's find, or a better state).
func merge_row(machine: String, row: Dictionary) -> bool:
	var item_id := str(row.get("item_id", ""))
	var state := str(row.get("state", ""))
	if item_id == "" or InventoryStore.rank(state) < 0:
		return false
	if not crews.has(machine):
		crews[machine] = [] as Array[Dictionary]
	var list: Array = crews[machine]
	for e: Dictionary in list:
		if str(e["item_id"]) == item_id:
			var changed_any := false
			if InventoryStore.rank(state) > InventoryStore.rank(str(e["state"])):
				e["state"] = state
				changed_any = true
			# First writer wins: the server knows who that was.
			var server_by := str(row.get("found_by", ""))
			if server_by != "" and server_by != str(e.get("found_by", "")):
				e["found_by"] = server_by
				e["found_at"] = str(row.get("found_at", e.get("found_at", "")))
				changed_any = true
			if changed_any:
				_save()
			return changed_any
	list.append({
		"item_id": item_id, "state": state, "found_by": str(row.get("found_by", "")),
		"found_at": str(row.get("found_at", "")), "place": str(row.get("place", "")) if row.get("place") != null else "",
	})
	_save()
	return true


func reset_local() -> void:
	crews.clear()
	_save()
	for machine in Ids.MACHINES:
		changed.emit(machine)


func _now() -> String:
	return now_override if now_override != "" else Time.get_datetime_string_from_system(true) + "Z"


func _save() -> void:
	if path != "":
		JsonFile.write(path, {"version": VERSION, "crews": crews})
