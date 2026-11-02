# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ProgressStore
extends RefCounted
## Where crew progress lives. Getters return at once from local state or cache.
## A machine's progress counts solves from devices in that crew; the scoreboard
## enforces this (a solve from a device not in the crew is rejected). The local
## store counts this device's solves. Mentors help other crews through hints,
## not solves. A revealed solve counts for progress but adds no contributor.

signal progress_changed(machine: String)


func set_display_name(_device_id: String, _name: String) -> void:
	pass


func join_crew(_device_id: String, _machine: String) -> void:
	pass


func record_part_solved(_machine: String, _part: String, _device_id: String, _credited: bool) -> void:
	pass


## {part: solver_count} with all six parts present.
func get_crew_progress(_machine: String) -> Dictionary:
	return empty_progress()


## Display names in first-solve order. Anonymous shows once as "Anonymous".
func get_contributors(_machine: String) -> Array[String]:
	return []


## Forgets this device's local progress ("Reset this device"). A remote store
## resets the local part it wraps and drops writes it has not sent.
func reset_local() -> void:
	pass


func is_online() -> bool:
	return false


func refresh() -> void:
	pass


static func empty_progress() -> Dictionary:
	var out: Dictionary = {}
	for part in Ids.PARTS:
		out[part] = 0
	return out
