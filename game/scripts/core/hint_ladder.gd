# SPDX-License-Identifier: AGPL-3.0-or-later
class_name HintLadder
extends RefCounted
## Hint levels per puzzle: 0 none, 1 nudge, 2 stronger nudge, 3 reveal.
## Without a reveal the ladder stops at 2. Wraps a dictionary {puzzle_id: level}
## by reference, so the owner (PlayerState) saves what the ladder changes.

const MAX_LEVEL := 3
const MAX_LEVEL_WITHOUT_REVEAL := 2

var _levels: Dictionary


func _init(levels: Dictionary = {}) -> void:
	_levels = levels


func level(puzzle_id: String) -> int:
	return int(_levels.get(puzzle_id, 0))


func advance(puzzle_id: String, can_reveal: bool) -> int:
	var cap := MAX_LEVEL if can_reveal else MAX_LEVEL_WITHOUT_REVEAL
	var next := mini(level(puzzle_id) + 1, cap)
	_levels[puzzle_id] = next
	return next


func reset(puzzle_id: String) -> void:
	_levels.erase(puzzle_id)


func to_dict() -> Dictionary:
	return _levels.duplicate()


static func from_dict(data: Dictionary) -> HintLadder:
	var levels := {}
	for key in data:
		levels[str(key)] = int(data[key])
	return HintLadder.new(levels)
