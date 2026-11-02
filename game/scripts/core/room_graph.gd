# SPDX-License-Identifier: AGPL-3.0-or-later
class_name RoomGraph
extends RefCounted
## The town as data (data/rooms.json): rooms of 16 px tiles, their exits,
## spawns, props and characters, walkability and paths. Pure, so tests can
## walk the whole graph without scenes. Cells are Vector2i tile coordinates.

const PATH := "res://data/rooms.json"
const TILE := 16
const WIDTH := 11  # PLAN.md D9: 11 tiles across
const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

var data: Dictionary = {}
var _solid: Dictionary = {}  # room -> {cell: true}
var _astar: Dictionary = {}  # room -> AStarGrid2D


func _init(p_data: Dictionary = {}) -> void:
	data = p_data if not p_data.is_empty() else JsonFile.read(PATH)
	for id: String in rooms():
		_solid[id] = _build_solid(id)


func rooms() -> Array[String]:
	var out: Array[String] = []
	for id: String in data.get("rooms", {}):
		out.append(id)
	return out


func has_room(id: String) -> bool:
	return data.get("rooms", {}).has(id)


func room(id: String) -> Dictionary:
	return data.get("rooms", {}).get(id, {})


func start_room() -> String:
	return str(data.get("start", ""))


func start_spawn() -> String:
	return str(data.get("start_spawn", ""))


func size_tiles(id: String) -> Vector2i:
	var map: Array = room(id).get("map", [])
	return Vector2i(WIDTH, map.size())


func size_px(id: String) -> Vector2i:
	return size_tiles(id) * TILE


func char_at(id: String, cell: Vector2i) -> String:
	var map: Array = room(id).get("map", [])
	if cell.y < 0 or cell.y >= map.size():
		return ""
	var row := str(map[cell.y])
	if cell.x < 0 or cell.x >= row.length():
		return ""
	return row[cell.x]


func tile_asset(id: String, cell: Vector2i) -> String:
	return str(data.get("legend", {}).get(char_at(id, cell), {}).get("tile", ""))


func in_bounds(id: String, cell: Vector2i) -> bool:
	var size := size_tiles(id)
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func is_walkable(id: String, cell: Vector2i) -> bool:
	return in_bounds(id, cell) and not _solid.get(id, {}).has(cell)


func spawn(id: String, spawn_name: String) -> Vector2i:
	var raw: Array = room(id).get("spawns", {}).get(spawn_name, [])
	return Vector2i(int(raw[0]), int(raw[1])) if raw.size() >= 2 else Vector2i(-1, -1)


func has_spawn(id: String, spawn_name: String) -> bool:
	return room(id).get("spawns", {}).has(spawn_name)


func exits(id: String) -> Array:
	return room(id).get("exits", [])


## The exit whose tiles include `cell`, or {}.
func exit_at(id: String, cell: Vector2i) -> Dictionary:
	for e: Dictionary in exits(id):
		for raw: Array in e.get("tiles", []):
			if Vector2i(int(raw[0]), int(raw[1])) == cell:
				return e
	return {}


## Props and characters, each with "kind" set to "prop" or "npc".
func things(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in room(id).get("props", []):
		var copy := p.duplicate(true)
		copy["kind"] = "prop"
		out.append(copy)
	for n: Dictionary in room(id).get("npcs", []):
		var copy := n.duplicate(true)
		copy["kind"] = "npc"
		out.append(copy)
	return out


func thing(id: String, thing_id: String) -> Dictionary:
	for t in things(id):
		if str(t.get("id", "")) == thing_id:
			return t
	return {}


## {room: [prop and npc ids, and the room's own id]}: what chain data may target.
func targets() -> Dictionary:
	var out: Dictionary = {}
	for id in rooms():
		var list: Array[String] = [id]
		for t in things(id):
			list.append(str(t["id"]))
		out[id] = list
	return out


## A thing's hotspot in room pixels.
static func rect_px(t: Dictionary) -> Rect2:
	if t.has("rect_px"):
		var r: Array = t["rect_px"]
		return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var at: Array = t.get("at", [0, 0])
	var size: Array = t.get("size", [1, 1])
	return Rect2(float(at[0]) * TILE, float(at[1]) * TILE, float(size[0]) * TILE, float(size[1]) * TILE)


static func cells_of(t: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := rect_px(t)
	for y in range(int(floor(r.position.y / TILE)), int(ceil(r.end.y / TILE))):
		for x in range(int(floor(r.position.x / TILE)), int(ceil(r.end.x / TILE))):
			out.append(Vector2i(x, y))
	return out


## Where the player stands to use a thing: its `stand`, else the nearest
## walkable cell beside it.
func stand_cell(id: String, t: Dictionary) -> Vector2i:
	if t.has("stand"):
		var s: Array = t["stand"]
		return Vector2i(int(s[0]), int(s[1]))
	var cells := cells_of(t)
	for cell in cells:
		for d in DIRS:
			if is_walkable(id, cell + d) and not cells.has(cell + d):
				return cell + d
	return nearest_walkable(id, cells[0] if not cells.is_empty() else Vector2i.ZERO)


## The thing whose hotspot contains `point` (room pixels), or {}. Later things
## win, so a small hotspot listed after a big one can sit on top of it.
func thing_at(id: String, point: Vector2) -> Dictionary:
	var hit: Dictionary = {}
	for t in things(id):
		if rect_px(t).has_point(point):
			hit = t
	return hit


func nearest_walkable(id: String, cell: Vector2i) -> Vector2i:
	if is_walkable(id, cell):
		return cell
	var size := size_tiles(id)
	for radius in range(1, maxi(size.x, size.y)):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := cell + Vector2i(dx, dy)
				if is_walkable(id, c):
					var d := Vector2(dx, dy).length()
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return cell


## A 4-way path from `from` to `to` (both included), or [] if there is none.
func path(id: String, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_walkable(id, to) or not in_bounds(id, from):
		return out
	if from == to:
		out.append(to)
		return out
	var grid := _grid(id)
	var start_solid := grid.is_point_solid(from)
	if start_solid:
		grid.set_point_solid(from, false)
	for p in grid.get_id_path(from, to):
		out.append(p)
	if start_solid:
		grid.set_point_solid(from, true)
	return out


## Graph problems: maps of the wrong width, exits to missing rooms or spawns,
## one-way doors, spawns that are blocked or sit on an exit.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if not has_room(start_room()) or not has_spawn(start_room(), start_spawn()):
		errors.append("start room or spawn missing")
	for id in rooms():
		var map: Array = room(id).get("map", [])
		for y in map.size():
			if str(map[y]).length() != WIDTH:
				errors.append("%s row %d is %d wide" % [id, y, str(map[y]).length()])
			for x in str(map[y]).length():
				if not data.get("legend", {}).has(str(map[y])[x]):
					errors.append("%s: no legend for '%s'" % [id, str(map[y])[x]])
		for spawn_name: String in room(id).get("spawns", {}):
			var cell := spawn(id, spawn_name)
			if not is_walkable(id, cell):
				errors.append("%s spawn %s is not walkable" % [id, spawn_name])
			if not exit_at(id, cell).is_empty():
				errors.append("%s spawn %s sits on an exit" % [id, spawn_name])
		for e: Dictionary in exits(id):
			var to := str(e.get("to", ""))
			if not has_room(to):
				errors.append("%s: exit to missing room %s" % [id, to])
				continue
			if not has_spawn(to, str(e.get("arrive", ""))):
				errors.append("%s: exit to %s arrives at missing spawn %s" % [id, to, str(e.get("arrive", ""))])
			var back := false
			for b: Dictionary in exits(to):
				if str(b.get("to", "")) == id:
					back = true
			if not back:
				errors.append("%s: no way back from %s" % [id, to])
			for raw: Array in e.get("tiles", []):
				if not is_walkable(id, Vector2i(int(raw[0]), int(raw[1]))):
					errors.append("%s: exit tile %s is blocked" % [id, str(raw)])
		for t in things(id):
			var stand := stand_cell(id, t)
			if not is_walkable(id, stand):
				errors.append("%s: %s has nowhere to stand" % [id, str(t.get("id", "?"))])
	return errors


## Every room reachable from the start by walking through exits.
func reachable_rooms() -> Array[String]:
	var seen: Array[String] = []
	var todo: Array[String] = [start_room()]
	while not todo.is_empty():
		var id: String = todo.pop_back()
		if seen.has(id) or not has_room(id):
			continue
		seen.append(id)
		for e: Dictionary in exits(id):
			todo.append(str(e.get("to", "")))
	return seen


func _build_solid(id: String) -> Dictionary:
	var solid: Dictionary = {}
	var size := size_tiles(id)
	var legend: Dictionary = data.get("legend", {})
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if bool(legend.get(char_at(id, cell), {}).get("solid", false)):
				solid[cell] = true
	for t in things(id):
		if t["kind"] == "npc" or bool(t.get("solid", true)):
			for cell in cells_of(t):
				solid[cell] = true
	for e: Dictionary in exits(id):
		for raw: Array in e.get("tiles", []):
			solid.erase(Vector2i(int(raw[0]), int(raw[1])))
	return solid


func _grid(id: String) -> AStarGrid2D:
	if _astar.has(id):
		return _astar[id]
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size_tiles(id))
	grid.cell_size = Vector2(TILE, TILE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for cell: Vector2i in _solid.get(id, {}):
		if grid.is_in_boundsv(cell):
			grid.set_point_solid(cell, true)
	_astar[id] = grid
	return grid
