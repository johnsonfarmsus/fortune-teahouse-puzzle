# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Thin Node over HintLadder. Levels are stored in GameState.player.hint_levels.

signal nudge_received(puzzle_id: String, text: String)

var pushed_nudges: Dictionary = {}  # puzzle_id -> text


## 0 none, 1 nudge, 2 stronger nudge, 3 reveal. Capped at 2 without can_reveal.
func advance(puzzle_id: String, can_reveal: bool) -> int:
	var level := HintLadder.new(GameState.player.hint_levels).advance(puzzle_id, can_reveal)
	GameState.save()
	return level


func level(puzzle_id: String) -> int:
	return HintLadder.new(GameState.player.hint_levels).level(puzzle_id)


## Stub for WP7: a mentor's pushed nudge arrives here.
func receive_pushed_nudge(puzzle_id: String, text: String) -> void:
	pushed_nudges[puzzle_id] = text
	nudge_received.emit(puzzle_id, text)
