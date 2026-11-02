# SPDX-License-Identifier: AGPL-3.0-or-later
class_name SfxBank
extends RefCounted
## The game's sound effects by interaction id, from data/sfx.json, built on
## first use by SfxSynth and cached. An entry may be {"alias": "other_id"}.
## CORE_IDS are the ids the adventure scenes play directly; chain and room data
## name the rest. Tests check that every one of them has a sound.

const PATH := "res://data/sfx.json"
const SPEAKERS: Array[String] = ["gnu", "red_panda", "penguin", "gopher", "seagull", "crab", "anglerfish", "elephant", "narrator"]
const CORE_IDS: Array[String] = [
	"tap", "step", "door", "edge", "select", "pickup", "drop", "deny", "success", "talk", "advance",
	"drag_start", "slot", "jar_drop", "jar_clink", "wobble", "dial", "click", "unlock", "buzz",
	"hammer", "bolt", "clunk", "stamp", "paper", "rattle", "lure", "spark", "menu", "part_fixed", "tick",
]

var rate: int = SfxSynth.DEFAULT_RATE
var sounds: Dictionary = {}
var _cache: Dictionary = {}


func _init(p_data: Dictionary = {}) -> void:
	var source := p_data if not p_data.is_empty() else JsonFile.read(PATH)
	rate = int(source.get("mix_rate", SfxSynth.DEFAULT_RATE))
	sounds = source.get("sounds", {})


static func babble_id(speaker: String) -> String:
	return "babble." + speaker.to_lower().replace(" ", "_")


func has(id: String) -> bool:
	return not definition(id).is_empty()


func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in sounds:
		out.append(id)
	return out


## The definition after following aliases (at most 4 hops), or {}.
func definition(id: String) -> Dictionary:
	var current := id
	for hop in 5:
		var def: Variant = sounds.get(current)
		if not def is Dictionary:
			return {}
		if (def as Dictionary).has("alias"):
			current = str(def["alias"])
			continue
		return def
	return {}


func is_built(id: String) -> bool:
	return _cache.has(id)


## Samples one sound needs (tests keep these within a budget).
func sample_count(id: String) -> int:
	var def := definition(id)
	if def.is_empty():
		return 0
	var notes: Array = def.get("notes", [])
	var seconds := float(def.get("note_len", 0.06)) * notes.size() if not notes.is_empty() else float(def.get("duration", 0.1))
	return int(clampf(seconds, 0.005, SfxSynth.MAX_SECONDS) * int(def.get("rate", rate)))


func stream(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var def := definition(id)
	if def.is_empty():
		return null
	var built := SfxSynth.build(def, int(def.get("rate", rate)))
	_cache[id] = built
	return built


## Every id the adventure needs: the scenes' own, a babble per speaker, room
## ambience, and whatever `extra` (chain and room data) names.
static func required_ids(extra: Array[String] = []) -> Array[String]:
	var out: Array[String] = CORE_IDS.duplicate()
	for speaker in SPEAKERS:
		out.append(babble_id(speaker))
	for id in extra:
		if id != "" and not out.has(id):
			out.append(id)
	return out
