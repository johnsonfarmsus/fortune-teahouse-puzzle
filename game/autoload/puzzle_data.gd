# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Thin Node over PuzzleCatalog. Loads the data files once.

var catalog: PuzzleCatalog = PuzzleCatalog.load_all()


func get_clue(clue_id: String) -> Dictionary:
	return catalog.get_clue(clue_id)


func get_clues(machine: String) -> Array:
	return catalog.get_clues(machine)


func get_domain(machine: String) -> Dictionary:
	return catalog.get_domain(machine)


func get_answer(machine: String) -> Dictionary:
	return catalog.get_answer(machine)


func get_parts(machine: String) -> Array:
	return catalog.get_parts(machine)


func get_part(machine: String, part: String) -> Dictionary:
	return catalog.get_part(machine, part)


func matching_config(machine: String, collected_ids: Array) -> Dictionary:
	return catalog.matching_config(machine, collected_ids)


func lookup_lucky_word(word: String) -> Dictionary:
	return catalog.lookup_lucky_word(word)


func get_title(machine: String) -> String:
	return catalog.get_title(machine)
