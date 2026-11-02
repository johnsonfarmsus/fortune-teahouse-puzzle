# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PuzzleBase
extends Control
## Contract for every puzzle type. Subclasses never touch Router, GameState or
## Progress: they emit signals and PuzzleHost does the rest.

signal solved(credited: bool)
signal hint_requested(level: int)
signal give_up

var puzzle_id: String = ""  # "<machine>/<part>"
var machine: String = ""
var part: String = ""


## Called by PuzzleHost before add_child.
func configure(_config: Dictionary) -> void:
	pass


func can_reveal() -> bool:
	return true


## Text for hint levels 1 and 2.
func get_hint_text(_level: int) -> String:
	return ""


## Shows the answer (level 3). request_hint() emits solved(false) afterwards.
func reveal() -> void:
	pass


func request_hint() -> void:
	var level := Hints.advance(puzzle_id, can_reveal())
	hint_requested.emit(level)
	if level >= HintLadder.MAX_LEVEL:
		reveal()
		solved.emit(false)


func quit() -> void:
	give_up.emit()


## The player solved it themselves.
func finish() -> void:
	solved.emit(true)
