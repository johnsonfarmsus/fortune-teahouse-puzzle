# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Thin Node over PlayerState. Saved to user://player.json on every change.
## Tests set `persist = false` so they never touch the real save.

const SAVE_PATH := "user://player.json"

var persist: bool = true
var player: PlayerState = PlayerState.new()

var device_id: String:
	get:
		return player.device_id
var display_name: String:
	get:
		return player.display_name
var name_asked: bool:
	get:
		return player.name_asked
var crew: String:
	get:
		return player.crew
var collected_clue_ids: Array[String]:
	get:
		return player.collected_clue_ids
var sound_on: bool:
	get:
		return player.sound_on


func _ready() -> void:
	if persist:
		var data := JsonFile.read(SAVE_PATH)
		if not data.is_empty():
			player = PlayerState.from_dict(data)
	player.ensure_device_id()
	save()


func save() -> void:
	if persist:
		JsonFile.write(SAVE_PATH, player.to_dict())


## Result is one of PlayerState.UNKNOWN, ALREADY_HAVE, COLLECTED, COLLECTED_JOINED.
func enter_lucky_word(word: String) -> int:
	var result := player.enter_lucky_word(word, PuzzleData.catalog)
	if result == PlayerState.COLLECTED or result == PlayerState.COLLECTED_JOINED:
		save()
		Events.clue_collected.emit(PuzzleData.lookup_lucky_word(word)["clue_id"])
		if result == PlayerState.COLLECTED_JOINED:
			Progress.store.join_crew(player.device_id, player.crew)
			Events.crew_changed.emit(player.crew)
	return result


func choose_crew(machine: String) -> void:
	if player.choose_crew(machine):
		save()
		Progress.store.join_crew(player.device_id, machine)
		Events.crew_changed.emit(machine)


func set_display_name(new_name: String) -> void:
	player.display_name = new_name.strip_edges()
	player.name_asked = true
	save()
	Progress.store.set_display_name(player.device_id, player.display_name)
	Events.display_name_changed.emit(player.display_name)


func mark_name_asked() -> void:
	player.name_asked = true
	save()


func mark_solved(machine: String, part: String, credited: bool) -> void:
	player.mark_solved(machine, part, credited)
	save()


func set_sound_on(value: bool) -> void:
	player.sound_on = value
	save()


## Forgets this device: name, clues, crew, solves and local progress.
func reset_device() -> void:
	player = PlayerState.new()
	player.ensure_device_id()
	save()
	Progress.reset()
	Events.crew_changed.emit("")
	Events.display_name_changed.emit("")
