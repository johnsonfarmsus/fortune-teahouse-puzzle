# SPDX-License-Identifier: AGPL-3.0-or-later
class_name StoryCatalog
extends RefCounted
## Story text for the whole game, read from data/story/*.json (format in
## data/story/schema.json). Pieces are indexed by `where` (the screen or place)
## and `when` (the trigger). Everything returned is a copy with placeholders
## filled in, so callers can never change the catalog. Pure data: this class
## knows no player state; the Story autoload passes in what has been seen.

## Listed explicitly: there is no directory listing on the web build.
## side_puzzles.json holds design concepts (never shown) and is left out.
const FILES: Array[String] = [
	"res://data/story/gnu.json",
	"res://data/story/red_panda.json",
	"res://data/story/crab.json",
	"res://data/story/helpers.json",
	"res://data/story/elephant.json",
	"res://data/story/anglerfish.json",
	"res://data/story/interface.json",
	"res://data/story/chains.json",
]

var _pieces: Array[Dictionary] = []  # raw pieces in load order
var _by_id: Dictionary = {}  # id -> raw piece
var _by_where: Dictionary = {}  # where -> Array of raw pieces, in load order


static func load_all() -> StoryCatalog:
	var catalog := StoryCatalog.new()
	for path in FILES:
		catalog.add_file(JsonFile.read(path))
	return catalog


## Adds every piece of one parsed story file. Returns how many were added.
## Pieces without an id, or with an id already present, are ignored.
func add_file(data: Dictionary) -> int:
	var added := 0
	for raw: Variant in data.get("pieces", []):
		if raw is Dictionary and add_piece(raw):
			added += 1
	return added


func add_piece(raw: Dictionary) -> bool:
	var id := str(raw.get("id", ""))
	if id == "" or _by_id.has(id):
		return false
	var lines: Array[String] = []
	for line: Variant in raw.get("lines", []):
		lines.append(str(line))
	var piece: Dictionary = {
		"id": id,
		"speaker": str(raw.get("speaker", "Narrator")),
		"kind": str(raw.get("kind", "dialogue")),
		"lines": lines,
		"where": str(raw.get("where", "")),
		"when": str(raw.get("when", "always")),
		"group": str(raw.get("group", "")),
		"expression": str(raw.get("expression", "neutral")),
	}
	_pieces.append(piece)
	_by_id[id] = piece
	var list: Array = _by_where.get(piece["where"], [])
	list.append(piece)
	_by_where[piece["where"]] = list
	return true


func piece_count() -> int:
	return _pieces.size()


func has_piece(id: String) -> bool:
	return _by_id.has(id)


## One piece by id, with placeholders filled from `context`, or {}.
func get_piece(id: String, context: Dictionary = {}) -> Dictionary:
	if not _by_id.has(id):
		return {}
	return _render(_by_id[id], context)


## Every piece shown at `where`, in data order. A non-empty `when` keeps only
## pieces with exactly that trigger ("machine_running:crew" is a trigger, not a pattern).
func pieces_for(where: String, when: String = "", context: Dictionary = {}) -> Array:
	var out: Array = []
	for raw: Dictionary in _by_where.get(where, []):
		if when == "" or raw["when"] == when:
			out.append(_render(raw, context))
	return out


## The first matching piece (data order) whose id is not in `seen`, or {}.
## Pieces of one group are alternatives, so repeated calls walk through them in turn.
func next_unseen(where: String, when: String, seen: Array, context: Dictionary = {}) -> Dictionary:
	for piece: Dictionary in pieces_for(where, when, context):
		if not seen.has(piece["id"]):
			return piece
	return {}


## Every matching piece not in `seen`, in data order (a first-visit sequence).
func unseen(where: String, when: String, seen: Array, context: Dictionary = {}) -> Array:
	var out: Array = []
	for piece: Dictionary in pieces_for(where, when, context):
		if not seen.has(piece["id"]):
			out.append(piece)
	return out


## A random matching piece (the alternatives of a group), or {}.
func pick(where: String, when: String, rng: RandomNumberGenerator, context: Dictionary = {}) -> Dictionary:
	var all := pieces_for(where, when, context)
	if all.is_empty():
		return {}
	return all[rng.randi_range(0, all.size() - 1)]


## Every piece of one speaker whose `where` is `place` or starts with "<place>:",
## in data order. Town and Shop use it to find the Gnu's notes.
func pieces_by_speaker(speaker: String, place: String, context: Dictionary = {}) -> Array:
	var out: Array = []
	for raw: Dictionary in _pieces:
		var where: String = raw["where"]
		if raw["speaker"] == speaker and (where == place or where.begins_with(place + ":")):
			out.append(_render(raw, context))
	return out


## Replaces {key} for each key in `context`; {repo_url} is always known.
## Unknown placeholders stay as written.
static func substitute(text: String, context: Dictionary) -> String:
	var out := text.replace("{repo_url}", Ids.REPO_URL)
	for key: Variant in context:
		out = out.replace("{%s}" % str(key), str(context[key]))
	return out


func _render(raw: Dictionary, context: Dictionary) -> Dictionary:
	var lines: Array[String] = []
	for line: String in raw["lines"]:
		lines.append(substitute(line, context))
	var out: Dictionary = raw.duplicate()
	out["lines"] = lines
	out["text"] = "\n".join(lines)
	return out
