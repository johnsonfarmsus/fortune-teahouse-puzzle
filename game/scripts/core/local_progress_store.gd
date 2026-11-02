# SPDX-License-Identifier: AGPL-3.0-or-later
class_name LocalProgressStore
extends ProgressStore
## Device-local progress saved to a JSON file. It only ever sees this device,
## so "solver count" here is the number of distinct devices it was told about.

const VERSION := 1

var path: String
var names: Dictionary = {}  # device_id -> display name
var crews: Dictionary = {}  # device_id -> machine
var solves: Array = []  # [{machine, part, device_id, credited}]


func _init(p_path: String = "user://progress.json") -> void:
	path = p_path
	_load()


func set_display_name(device_id: String, name: String) -> void:
	names[device_id] = name
	_save()
	_emit_all()


func join_crew(device_id: String, machine: String) -> void:
	crews[device_id] = machine
	_save()
	progress_changed.emit(machine)


func record_part_solved(machine: String, part: String, device_id: String, credited: bool) -> void:
	for entry: Dictionary in solves:
		if entry["machine"] == machine and entry["part"] == part and entry["device_id"] == device_id:
			if credited and not entry["credited"]:
				entry["credited"] = true
				_save()
				progress_changed.emit(machine)
			return
	solves.append({"machine": machine, "part": part, "device_id": device_id, "credited": credited})
	_save()
	progress_changed.emit(machine)


func get_crew_progress(machine: String) -> Dictionary:
	var out := ProgressStore.empty_progress()
	for entry: Dictionary in solves:
		if entry["machine"] == machine and out.has(entry["part"]):
			out[entry["part"]] = int(out[entry["part"]]) + 1
	return out


func get_contributors(machine: String) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in solves:
		if entry["machine"] != machine or not entry["credited"]:
			continue
		var shown: String = str(names.get(entry["device_id"], ""))
		if shown == "":
			shown = "Anonymous"
		if not out.has(shown):
			out.append(shown)
	return out


## Forgets everything on this device (used by "Reset this device").
func clear() -> void:
	names = {}
	crews = {}
	solves = []
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_emit_all()


func _emit_all() -> void:
	for machine in Ids.MACHINES:
		progress_changed.emit(machine)


func _save() -> void:
	JsonFile.write(path, {"version": VERSION, "names": names, "crews": crews, "solves": solves})


func _load() -> void:
	var data := JsonFile.read(path)
	if data.is_empty():
		return
	for device_id in data.get("names", {}):
		names[str(device_id)] = str(data["names"][device_id])
	for device_id in data.get("crews", {}):
		crews[str(device_id)] = str(data["crews"][device_id])
	for entry: Dictionary in data.get("solves", []):
		solves.append(
			{
				"machine": str(entry.get("machine", "")),
				"part": str(entry.get("part", "")),
				"device_id": str(entry.get("device_id", "")),
				"credited": bool(entry.get("credited", false)),
			}
		)
