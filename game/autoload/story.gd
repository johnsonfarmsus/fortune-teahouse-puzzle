# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Thin Node over StoryCatalog. Seen pieces are saved in PlayerState (through
## GameState); flags are for triggers whose source does not exist yet (the
## finale sets them in a later package) and are not saved.

signal flags_changed

var catalog: StoryCatalog
var load_msec: int = 0
var rng := RandomNumberGenerator.new()

var _flags: Dictionary = {}
var _rotations: Dictionary = {}


func _init() -> void:
	var started := Time.get_ticks_msec()
	catalog = StoryCatalog.load_all()
	load_msec = Time.get_ticks_msec() - started
	rng.randomize()


## Placeholder values every piece can use, plus `extra` (machine, part).
func context(extra: Dictionary = {}) -> Dictionary:
	var shown := GameState.display_name
	var out: Dictionary = {"name": shown if shown != "" else "friend", "repo_url": Ids.REPO_URL}
	out.merge(extra, true)
	return out


func pieces_for(where: String, when: String = "", extra: Dictionary = {}) -> Array:
	return catalog.pieces_for(where, when, context(extra))


func get_piece(id: String, extra: Dictionary = {}) -> Dictionary:
	return catalog.get_piece(id, context(extra))


func next_unseen(where: String, when: String = "", extra: Dictionary = {}) -> Dictionary:
	return catalog.next_unseen(where, when, GameState.player.seen_story, context(extra))


func unseen(where: String, when: String = "", extra: Dictionary = {}) -> Array:
	return catalog.unseen(where, when, GameState.player.seen_story, context(extra))


func pick(where: String, when: String = "", extra: Dictionary = {}) -> Dictionary:
	return catalog.pick(where, when, rng, context(extra))


func notes_by(speaker: String, place: String, extra: Dictionary = {}) -> Array:
	return catalog.pieces_by_speaker(speaker, place, context(extra))


func is_seen(id: String) -> bool:
	return GameState.player.has_seen_story(id)


func mark_seen(id: String) -> void:
	GameState.mark_story_seen(id)


## True the first time it is called with `key` on this device (a "first open" mark).
func visit(key: String) -> bool:
	var mark := "visit:" + key
	if is_seen(mark):
		return false
	mark_seen(mark)
	return true


## True when `state` differs from the last one recorded under `key`; records it.
func state_changed(key: String, state: String) -> bool:
	return GameState.set_story_state(key, state)


## 0, 1, 2, ... then round to 0 again, per key. Not saved.
func rotate(key: String, size: int) -> int:
	var index: int = int(_rotations.get(key, 0)) % maxi(size, 1)
	_rotations[key] = index + 1
	return index


## Triggers the game cannot know yet (finale_open, note_found, handoff_solved,
## line_running) are raised by whoever owns them with set_flag.
func set_flag(flag_name: String, on: bool = true) -> void:
	if bool(_flags.get(flag_name, false)) != on:
		_flags[flag_name] = on
		flags_changed.emit()


func flag(flag_name: String) -> bool:
	return bool(_flags.get(flag_name, false))


## Whether a piece's `when` currently holds for a note that waits on a trigger
## (a marker in the Town or Shop). Flag-driven triggers are false until set.
func trigger_active(when: String) -> bool:
	if when == "always" or when == "first_visit":
		return true
	if when == "machine_running:crew":
		return GameState.crew != "" and Progress.is_running(GameState.crew)
	if when.begins_with("machine_running:"):
		return Progress.is_running(when.trim_prefix("machine_running:"))
	return flag(when)


## Shows pieces in a DialogueBox on `host` and, unless `mark` is false, marks
## them seen at once (so skipping still counts). Returns the box, or null.
func play(host: Node, pieces: Array, mark: bool = true) -> DialogueBox:
	if pieces.is_empty() or host == null:
		return null
	if mark:
		for piece: Dictionary in pieces:
			mark_seen(str(piece["id"]))
	return DialogueBox.open(host, pieces)
