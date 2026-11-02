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


## Forgets the ladder for a puzzle (PuzzleHost does this when it opens an uncredited part).
func reset(puzzle_id: String) -> void:
	HintLadder.new(GameState.player.hint_levels).reset(puzzle_id)
	GameState.save()


## A mentor's pushed nudge arrives here (Progress passes puzzle_id "" for a
## nudge to the whole crew). The Hud shows it as a dismissible banner.
func receive_pushed_nudge(puzzle_id: String, text: String) -> void:
	pushed_nudges[puzzle_id] = text
	nudge_received.emit(puzzle_id, text)
	Events.hint_received.emit(text)
