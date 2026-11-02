# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Owns the ProgressStore: local unless the setting fortune/scoreboard_url is
## set. After writes it diffs progress and emits part_fixed (0 to 1) and
## machine_running (all six parts working).

var store: ProgressStore
var _last: Dictionary = {}  # machine -> {part: count}


func _ready() -> void:
	var url := str(ProjectSettings.get_setting("fortune/scoreboard_url", ""))
	var local := LocalProgressStore.new()
	if url == "":
		set_store(local)
	else:
		set_store(RemoteProgressStore.new(url, local))
	# Tell the store who this device is, only when that is news to it, so a
	# remote store does not queue the same writes at every boot.
	if GameState.display_name != "" and local.names.get(GameState.device_id, "") != GameState.display_name:
		store.set_display_name(GameState.device_id, GameState.display_name)
	if GameState.crew != "" and local.crews.get(GameState.device_id, "") != GameState.crew:
		store.join_crew(GameState.device_id, GameState.crew)


func set_store(new_store: ProgressStore) -> void:
	if store != null and store.progress_changed.is_connected(_on_store_changed):
		store.progress_changed.disconnect(_on_store_changed)
	store = new_store
	store.progress_changed.connect(_on_store_changed)
	_snapshot()


## "Reset this device": the active store forgets this device's local progress
## (a remote store resets its local part and keeps being the remote store).
func reset() -> void:
	store.reset_local()
	_snapshot()
	for machine in Ids.MACHINES:
		Events.progress_changed.emit(machine)


func parts_working(machine: String) -> int:
	var count := 0
	for part in Ids.PARTS:
		if int(store.get_crew_progress(machine).get(part, 0)) > 0:
			count += 1
	return count


func is_running(machine: String) -> bool:
	return parts_working(machine) == Ids.PARTS.size()


func _snapshot() -> void:
	for machine in Ids.MACHINES:
		_last[machine] = store.get_crew_progress(machine)


func _on_store_changed(machine: String) -> void:
	var before: Dictionary = _last.get(machine, ProgressStore.empty_progress())
	var after := store.get_crew_progress(machine)
	_last[machine] = after
	Events.progress_changed.emit(machine)
	var all_before := true
	var all_after := true
	for part: String in Ids.PARTS:
		var was := int(before.get(part, 0)) > 0
		var now := int(after.get(part, 0)) > 0
		all_before = all_before and was
		all_after = all_after and now
		if now and not was:
			Events.part_fixed.emit(machine, part)
	if all_after and not all_before:
		Events.machine_running.emit(machine)
