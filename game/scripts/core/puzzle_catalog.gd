# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PuzzleCatalog
extends RefCounted
## Puzzle data for all machines, read from game/data. Answers live only in data.
## _normalise_machine() is the single place that adapts the exporter's JSON
## (floats to ints, display names for items).

var _machines: Dictionary = {}  # machine -> normalised puzzle
var _parts: Dictionary = {}  # machine -> Array of part dictionaries
var _clues: Dictionary = {}  # clue_id -> clue
var _words: Dictionary = {}  # normalised lucky word -> {machine, clue_id}


## Loads every file that exists for Ids.MACHINES (no directory listing).
static func load_all() -> PuzzleCatalog:
	var catalog := PuzzleCatalog.new()
	for machine in Ids.MACHINES:
		var puzzle := JsonFile.read(Paths.puzzle_data(machine))
		if not puzzle.is_empty():
			catalog.add_machine(puzzle, JsonFile.read(Paths.machine_data(machine)))
	return catalog


func add_machine(raw_puzzle: Dictionary, machine_def: Dictionary = {}) -> void:
	var puzzle := _normalise_machine(raw_puzzle)
	var machine: String = puzzle["machine"]
	_machines[machine] = puzzle
	for clue: Dictionary in puzzle["clues"]:
		_clues[clue["id"]] = clue
		_words[LuckyWords.normalise(str(clue["lucky_word"]))] = {"machine": machine, "clue_id": clue["id"]}
	var parts: Array = []
	for raw_part: Dictionary in machine_def.get("parts", []):
		parts.append(
			{
				"part": str(raw_part.get("part", "")),
				"type": str(raw_part.get("type", "")),
				"title": str(raw_part.get("title", "")),
				"config": raw_part.get("config", {}),
			}
		)
	_parts[machine] = parts


func has_machine(machine: String) -> bool:
	return _machines.has(machine)


func get_title(machine: String) -> String:
	if _machines.has(machine):
		return str(_machines[machine]["title"])
	return Ids.machine_title(machine)


func get_puzzle_title(machine: String) -> String:
	return str(_machines.get(machine, {}).get("puzzle_title", ""))


func get_clue(clue_id: String) -> Dictionary:
	return _clues.get(clue_id, {})


func get_clues(machine: String) -> Array:
	return _machines.get(machine, {}).get("clues", [])


func get_domain(machine: String) -> Dictionary:
	return _machines.get(machine, {}).get("domain", {})


func get_answer(machine: String) -> Dictionary:
	return _machines.get(machine, {}).get("answer", {})


func get_parts(machine: String) -> Array:
	return _parts.get(machine, [])


func get_part(machine: String, part: String) -> Dictionary:
	for entry: Dictionary in get_parts(machine):
		if entry["part"] == part:
			return entry
	return {}


## Config for MatchingPuzzle: only the clues the player has collected.
func matching_config(machine: String, collected_ids: Array) -> Dictionary:
	var shown: Array = []
	for clue: Dictionary in get_clues(machine):
		if collected_ids.has(clue["id"]):
			shown.append(clue)
	return {
		"machine": machine,
		"domain": get_domain(machine),
		"answer": get_answer(machine),
		"clues": shown,
		"total_clues": get_clues(machine).size(),
		"threshold": Ids.CLUE_THRESHOLD,
	}


## {machine, clue_id} for a lucky word from any machine, or {} if unknown.
func lookup_lucky_word(word: String) -> Dictionary:
	return _words.get(LuckyWords.normalise(word), {})


func _normalise_machine(raw: Dictionary) -> Dictionary:
	var raw_domain: Dictionary = raw.get("domain", {})
	var items: Array = []
	for item in raw_domain.get("items", []):
		items.append(str(item))
	var names: Dictionary = {}
	var raw_names: Dictionary = raw_domain.get("item_names", {})
	for item: String in items:
		names[item] = str(raw_names.get(item, _item_name(item)))
	var positions: Array = []
	for label in raw_domain.get("positions", []):
		positions.append(str(label))
	var answer: Dictionary = {}
	var raw_answer: Dictionary = raw.get("answer", {})
	for item in raw_answer:
		answer[str(item)] = int(raw_answer[item])
	var clues: Array = []
	for raw_clue: Dictionary in raw.get("clues", []):
		var raw_fact: Dictionary = raw_clue.get("fact", {})
		var fact: Dictionary = {
			"kind": str(raw_fact.get("kind", "")),
			"a": str(raw_fact.get("a", "")),
			"value": int(raw_fact.get("value", 0)),
		}
		if raw_fact.has("b"):
			fact["b"] = str(raw_fact["b"])
		clues.append(
			{
				"id": str(raw_clue.get("id", "")),
				"style": str(raw_clue.get("style", "")),
				"approachable": bool(raw_clue.get("approachable", false)),
				"fortune_text": str(raw_clue.get("fortune_text", "")),
				"lucky_word": str(raw_clue.get("lucky_word", "")),
				"fact": fact,
				"nudge": str(raw_clue.get("nudge", "")),
			}
		)
	var machine := str(raw.get("machine", ""))
	return {
		"machine": machine,
		"title": str(raw.get("title", Ids.machine_title(machine))),
		"puzzle_title": str(raw.get("puzzle_title", "")),
		"domain":
		{
			"items": items,
			"item_names": names,
			"positions": positions,
			"position_noun": str(raw_domain.get("position_noun", "place")),
			"item_noun": str(raw_domain.get("item_noun", "")),
		},
		"answer": answer,
		"clues": clues,
	}


## Display name for an item id when the data carries none: "sugar" becomes
## "Sugar" and "c120" becomes "120 C".
func _item_name(item: String) -> String:
	if item.length() > 1 and item.begins_with("c") and item.substr(1).is_valid_int():
		return item.substr(1) + " C"
	return item.replace("_", " ").capitalize()
