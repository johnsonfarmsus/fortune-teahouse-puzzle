# SPDX-License-Identifier: AGPL-3.0-or-later
class_name FinaleState
extends RefCounted
## What this phone knows about the finale, saved to user://finale.json:
## {version, notes_held, settings: {handoff_id: [indices]}, gnu_notes, queue, cache}.
## `queue` holds the writes not yet accepted by the scoreboard (FinaleClient
## sends them): {op: "setting", handoff_id, setting_index}, {op: "note", code}
## and {op: "register"}. `cache` is the last GET /finale object. A device reset
## clears all of it. With an empty `path` nothing is read or written.

signal changed  ## notes, settings, gnu notes or the cache changed
signal queue_added  ## a write was queued

const DEFAULT_PATH := "user://finale.json"
const VERSION := 1

var path: String
var notes_held: Array[String] = []
var settings: Dictionary = {}  # handoff_id -> Array[int], in the order they were set
var gnu_notes: Array[String] = []  # ids of the gnu's notes filed on this phone
var queue: Array[Dictionary] = []
var cache: Dictionary = {}


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	if path != "":
		load_from_disk()


# --- Handoff notes ---------------------------------------------------------------------


func has_note(id: String) -> bool:
	return notes_held.has(id)


## True if the note is new to this phone.
func grant_note(id: String) -> bool:
	if id == "" or notes_held.has(id):
		return false
	notes_held.append(id)
	save()
	changed.emit()
	return true


# --- Handoff settings ------------------------------------------------------------------


func settings_for(handoff_id: String) -> Array[int]:
	var out: Array[int] = []
	for i: Variant in settings.get(handoff_id, []):
		out.append(int(i))
	return out


func has_setting(handoff_id: String, index: int) -> bool:
	return settings_for(handoff_id).has(index)


## Records that a setting was set on this phone and queues the POST. A repeat
## changes nothing and queues nothing. True if it was new.
func add_setting(handoff_id: String, index: int) -> bool:
	if handoff_id == "" or index < 0 or has_setting(handoff_id, index):
		return false
	var list := settings_for(handoff_id)
	list.append(index)
	settings[handoff_id] = list
	queue.append({"op": "setting", "handoff_id": handoff_id, "setting_index": index})
	save()
	changed.emit()
	queue_added.emit()
	return true


# --- The gnu's notes -------------------------------------------------------------------


func has_gnu_note(id: String) -> bool:
	return gnu_notes.has(id)


## Files a gnu note found on this phone and queues its code (already normalised).
## True if it was new.
func add_gnu_note(id: String, code: String) -> bool:
	if id == "" or gnu_notes.has(id):
		return false
	gnu_notes.append(id)
	queue.append({"op": "note", "code": code})
	save()
	changed.emit()
	queue_added.emit()
	return true


# --- Cache -----------------------------------------------------------------------------


func set_cache(data: Dictionary) -> void:
	if cache == data:
		return
	cache = data.duplicate(true)
	save()
	changed.emit()


# --- Saving ----------------------------------------------------------------------------


func reset() -> void:
	notes_held = []
	settings = {}
	gnu_notes = []
	queue = []
	cache = {}
	save()
	changed.emit()


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"notes_held": notes_held.duplicate(),
		"settings": settings.duplicate(true),
		"gnu_notes": gnu_notes.duplicate(),
		"queue": queue.duplicate(true),
		"cache": cache.duplicate(true),
	}


func save() -> void:
	if path != "":
		JsonFile.write(path, to_dict())


func load_from_disk() -> void:
	apply_dict(JsonFile.read(path))


func apply_dict(data: Dictionary) -> void:
	notes_held = []
	settings = {}
	gnu_notes = []
	queue = []
	cache = {}
	for id: Variant in data.get("notes_held", []):
		notes_held.append(str(id))
	var raw: Variant = data.get("settings", {})
	if raw is Dictionary:
		for handoff_id: Variant in raw:
			var list: Array[int] = []
			for i: Variant in raw[handoff_id]:
				list.append(int(i))
			settings[str(handoff_id)] = list
	for id: Variant in data.get("gnu_notes", []):
		gnu_notes.append(str(id))
	for item: Variant in data.get("queue", []):
		if item is Dictionary and item.get("op") is String:
			queue.append(item)
	if data.get("cache") is Dictionary:
		cache = data["cache"]
