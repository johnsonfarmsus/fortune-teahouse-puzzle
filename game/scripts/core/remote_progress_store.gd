# SPDX-License-Identifier: AGPL-3.0-or-later
class_name RemoteProgressStore
extends ProgressStore
## Scoreboard-backed store. In WP3 it only delegates to a local store and
## queues what a server would need to hear; WP7 sends the queue.

var base_url: String
var local: ProgressStore
var queue: Array[Dictionary] = []


func _init(p_base_url: String, p_local: ProgressStore) -> void:
	base_url = p_base_url
	local = p_local
	local.progress_changed.connect(func(machine: String) -> void: progress_changed.emit(machine))


func set_display_name(device_id: String, name: String) -> void:
	local.set_display_name(device_id, name)
	queue.append({"op": "set_display_name", "device_id": device_id, "name": name})


func join_crew(device_id: String, machine: String) -> void:
	local.join_crew(device_id, machine)
	queue.append({"op": "join_crew", "device_id": device_id, "machine": machine})


func record_part_solved(machine: String, part: String, device_id: String, credited: bool) -> void:
	local.record_part_solved(machine, part, device_id, credited)
	queue.append(
		{"op": "record_part_solved", "machine": machine, "part": part, "device_id": device_id, "credited": credited}
	)


func get_crew_progress(machine: String) -> Dictionary:
	return local.get_crew_progress(machine)


func get_contributors(machine: String) -> Array[String]:
	return local.get_contributors(machine)


func is_online() -> bool:
	return false


func refresh() -> void:
	local.refresh()


## Returns how many writes are still waiting to be sent (WP7 sends them).
func flush() -> int:
	return queue.size()
