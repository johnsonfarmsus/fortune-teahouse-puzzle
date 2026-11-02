# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PlayerState
extends RefCounted
## Everything saved about this device's player. Plain data, no engine nodes.

enum { UNKNOWN, ALREADY_HAVE, COLLECTED, COLLECTED_JOINED }

var device_id: String = ""
var display_name: String = ""  # "" means anonymous
var name_asked: bool = false
var crew: String = ""  # "" means no crew yet
var collected_clue_ids: Array[String] = []
var solved_parts: Dictionary = {}  # {machine: {part: credited}}
var hint_levels: Dictionary = {}  # {puzzle_id: level}
var sound_on: bool = true
var seen_story: Array[String] = []  # story piece ids already shown, plus "visit:<key>" marks
var story_state: Dictionary = {}  # {key: last state shown}, so a line shows again only when the state changes


func ensure_device_id() -> void:
	if device_id == "":
		device_id = Crypto.new().generate_random_bytes(16).hex_encode()


## A known word from any machine adds its clue. It sets the crew only if none is set.
func enter_lucky_word(word: String, catalog: PuzzleCatalog) -> int:
	var hit := catalog.lookup_lucky_word(word)
	if hit.is_empty():
		return UNKNOWN
	var clue_id: String = hit["clue_id"]
	if collected_clue_ids.has(clue_id):
		return ALREADY_HAVE
	collected_clue_ids.append(clue_id)
	if crew == "":
		crew = hit["machine"]
		return COLLECTED_JOINED
	return COLLECTED


## For players with no cookie and for switching crews. Keeps clues and solves.
func choose_crew(machine: String) -> bool:
	if not Ids.MACHINES.has(machine):
		return false
	crew = machine
	return true


func clues_for_machine(machine: String, catalog: PuzzleCatalog) -> Array[String]:
	var out: Array[String] = []
	for clue: Dictionary in catalog.get_clues(machine):
		if collected_clue_ids.has(clue["id"]):
			out.append(clue["id"])
	return out


## A revealed solve is stored as not credited; solving it yourself later upgrades it.
func mark_solved(machine: String, part: String, credited: bool) -> void:
	var parts: Dictionary = solved_parts.get(machine, {})
	parts[part] = bool(parts.get(part, false)) or credited
	solved_parts[machine] = parts


func is_part_solved(machine: String, part: String) -> bool:
	return solved_parts.get(machine, {}).has(part)


func is_part_credited(machine: String, part: String) -> bool:
	return bool(solved_parts.get(machine, {}).get(part, false))


func has_seen_story(id: String) -> bool:
	return seen_story.has(id)


func mark_story_seen(id: String) -> void:
	if id != "" and not seen_story.has(id):
		seen_story.append(id)


func to_dict() -> Dictionary:
	return {
		"device_id": device_id,
		"display_name": display_name,
		"name_asked": name_asked,
		"crew": crew,
		"collected_clue_ids": collected_clue_ids.duplicate(),
		"solved_parts": solved_parts.duplicate(true),
		"hint_levels": hint_levels.duplicate(),
		"sound_on": sound_on,
		"seen_story": seen_story.duplicate(),
		"story_state": story_state.duplicate(),
	}


static func from_dict(data: Dictionary) -> PlayerState:
	var state := PlayerState.new()
	state.device_id = str(data.get("device_id", ""))
	state.display_name = str(data.get("display_name", ""))
	state.name_asked = bool(data.get("name_asked", false))
	state.crew = str(data.get("crew", ""))
	for clue_id in data.get("collected_clue_ids", []):
		state.collected_clue_ids.append(str(clue_id))
	var raw_solved: Dictionary = data.get("solved_parts", {})
	for machine in raw_solved:
		var parts: Dictionary = {}
		for part in raw_solved[machine]:
			parts[str(part)] = bool(raw_solved[machine][part])
		state.solved_parts[str(machine)] = parts
	var raw_levels: Dictionary = data.get("hint_levels", {})
	for puzzle_id in raw_levels:
		state.hint_levels[str(puzzle_id)] = int(raw_levels[puzzle_id])
	state.sound_on = bool(data.get("sound_on", true))
	for story_id in data.get("seen_story", []):
		state.mark_story_seen(str(story_id))
	var raw_state: Dictionary = data.get("story_state", {})
	for key in raw_state:
		state.story_state[str(key)] = str(raw_state[key])
	return state
