# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ChainState
extends RefCounted
## What this phone has learned and is carrying on one machine's chains: facts
## (knowledge such as "the die was mailed"), unshared items held (misdirects and
## Seagull's scrap, which can be put back) and decoys already followed. Shared
## parts and tools live in the crew inventory, not here. Saved to `path` on every
## change ("" keeps it in memory, for tests).

signal changed

const VERSION := 1

var path: String
var facts: Array[String] = []
var held: Array[String] = []
var decoys_seen: Array[String] = []


func _init(p_path: String = "") -> void:
	path = p_path
	if path != "":
		_load()


func knows(fact: String) -> bool:
	return facts.has(fact)


func holds_item(item: String) -> bool:
	return held.has(item)


func has_seen_decoy(decoy: String) -> bool:
	return decoys_seen.has(decoy)


func learn(fact: String) -> void:
	if not facts.has(fact):
		facts.append(fact)
		_changed()


func hold(item: String) -> void:
	if not held.has(item):
		held.append(item)
		_changed()


func release(item: String) -> void:
	if held.has(item):
		held.erase(item)
		_changed()


func see_decoy(decoy: String) -> void:
	if not decoys_seen.has(decoy):
		decoys_seen.append(decoy)
		_changed()


func reset() -> void:
	facts.clear()
	held.clear()
	decoys_seen.clear()
	_changed()


func to_dict() -> Dictionary:
	return {"version": VERSION, "facts": facts.duplicate(), "held": held.duplicate(), "decoys_seen": decoys_seen.duplicate()}


static func from_dict(data: Dictionary) -> ChainState:
	var state := ChainState.new()
	state._read(data)
	return state


func duplicate_state() -> ChainState:
	return ChainState.from_dict(to_dict())


func _read(data: Dictionary) -> void:
	facts.clear()
	held.clear()
	decoys_seen.clear()
	for value: Variant in data.get("facts", []):
		facts.append(str(value))
	for value: Variant in data.get("held", []):
		held.append(str(value))
	for value: Variant in data.get("decoys_seen", []):
		decoys_seen.append(str(value))


func _load() -> void:
	_read(JsonFile.read(path))


func _changed() -> void:
	if path != "":
		JsonFile.write(path, to_dict())
	changed.emit()
