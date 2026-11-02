# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## The adventure layer's state (game/ARCHITECTURE.md section 15): the town
## (RoomGraph), the art list (AssetLoader), each machine's chain data with this
## phone's ChainState, and the crew inventory (local, or shared through the
## scoreboard when Progress uses one). Rooms and close-ups call interact() for
## every tap, drop, code and finished close-up; this applies the chain's effects
## (finds and installs to the inventory, part solves to Progress) and returns
## what the scene should present. Registered after Finale.

signal inventory_changed
signal chain_changed

const CHAIN_FILES := {"cookie_machine": "res://data/chains/cookie_machine.json"}
const PLACE_PATH := "user://adventure.json"
const TICK_SECONDS := 1.0

## Tests turn this off before calling use_memory_state().
var persist: bool = true
var rooms: RoomGraph
var assets: AssetLoader
var chains: Dictionary = {}  # machine -> chain data
var states: Dictionary = {}  # machine -> ChainState
var inventory: InventoryStore
var local_inventory: LocalInventoryStore
## Where the player is, saved so a reload resumes there.
var room_id: String = ""
var cell: Vector2i = Vector2i(-1, -1)
var _hint_levels: Dictionary = {}  # step key -> times asked
var _tick: Timer


func _ready() -> void:
	rooms = RoomGraph.new()
	assets = AssetLoader.shared()
	for machine: String in CHAIN_FILES:
		chains[machine] = JsonFile.read(CHAIN_FILES[machine])
	_load_states()
	_tick = Timer.new()
	_tick.wait_time = TICK_SECONDS
	_tick.autostart = true
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	Events.scoreboard_status_changed.connect(_build_inventory)
	Events.crew_changed.connect(func(_m: String) -> void: _build_inventory())
	var place := JsonFile.read(PLACE_PATH) if persist else {}
	room_id = str(place.get("room", ""))
	cell = Vector2i(int(place.get("x", -1)), int(place.get("y", -1)))
	# Playtesting and screenshots: ?room=<id> on the web build starts in that room.
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		var jump := room_from_query(str(search) if search != null else "", rooms)
		if jump != "":
			room_id = jump
			cell = rooms.spawn(jump, str((rooms.room(jump).get("spawns", {}) as Dictionary).keys()[0]))
	_build_inventory()


func _exit_tree() -> void:
	assets = null
	AssetLoader.release_shared()


## The `room` value of a query string such as "?room=depot", if it names a room.
func room_from_query(query: String, graph: RoomGraph) -> String:
	var q := query.strip_edges().trim_prefix("?")
	for pair in q.get_slice("#", 0).split("&", false):
		if pair.get_slice("=", 0) == "room":
			var id := pair.get_slice("=", 1).uri_decode()
			return id if graph.has_room(id) else ""
	return ""


## In-memory chain state and inventory with no scoreboard (tests).
func use_memory_state() -> void:
	persist = false
	_retire_remote()
	for machine: String in CHAIN_FILES:
		states[machine] = ChainState.new("")
	local_inventory = LocalInventoryStore.new("")
	_set_inventory(local_inventory)
	room_id = ""
	cell = Vector2i(-1, -1)
	_hint_levels.clear()


func reset() -> void:
	for machine: String in states:
		(states[machine] as ChainState).reset()
	inventory.reset_local()
	room_id = ""
	cell = Vector2i(-1, -1)
	_hint_levels.clear()
	_save_place()
	inventory_changed.emit()
	chain_changed.emit()


func chain_state(machine: String) -> ChainState:
	return states.get(machine)


func answers() -> Dictionary:
	var out: Dictionary = {}
	for machine: String in chains:
		out[machine] = PuzzleData.get_answer(machine)
	return out


func set_place(p_room: String, p_cell: Vector2i) -> void:
	room_id = p_room
	cell = p_cell
	_save_place()


# --- Interactions -------------------------------------------------------------------


## Resolves one action against every machine's chains and applies it. Returns
## {} when no chain has anything to say, else {machine, chain, id, say: [piece
## ids], sfx, open, solved_part, now_running, misdirect, decoy}.
func interact(room: String, target: String, verb: String, item: String = "", code: String = "") -> Dictionary:
	for machine: String in chains:
		var data: Dictionary = chains[machine]
		var state: ChainState = states[machine]
		var inv := inventory.states(machine)
		var result := ""
		if verb == "code":
			result = ChainRules.code_result(data, target, code, answers())
		var i := ChainRules.resolve(data, state, inv, room, target, verb, item, result)
		if i.is_empty():
			continue
		var out := {
			"machine": machine, "chain": str(i.get("chain", "")), "id": str(i.get("id", "")),
			"say": ChainRules.say_ids(i), "sfx": str(i.get("sfx", "")), "open": "", "solved_part": "",
			"now_running": false, "misdirect": str(i.get("misdirect", "")), "decoy": str(i.get("decoy", "")),
			"result": result,
		}
		var place := "%s:%s" % [room, target]
		for effect in ChainRules.apply(i, state):
			if effect.has("find"):
				inventory.mark(machine, str(effect["find"]), InventoryStore.FOUND, place, GameState.device_id)
			elif effect.has("install"):
				inventory.mark(machine, str(effect["install"]), InventoryStore.INSTALLED, place, GameState.device_id)
			elif effect.has("solve_part"):
				out["solved_part"] = str(effect["solve_part"])
				out["now_running"] = record_solve(machine, str(effect["solve_part"]), true)
			elif effect.has("open"):
				out["open"] = str(effect["open"])
		inventory_changed.emit()
		chain_changed.emit()
		return out
	return {}


## A part solved in the adventure layer: saved like PuzzleHost does. Returns
## true if this solve made the machine run.
func record_solve(machine: String, part: String, credited: bool) -> bool:
	var was_running := Progress.is_running(machine)
	GameState.mark_solved(machine, part, credited)
	Progress.store.record_part_solved(machine, part, GameState.device_id, credited)
	return Progress.is_running(machine) and not was_running


# --- Inventory ----------------------------------------------------------------------


## What the inventory bar shows: [{machine, item_id, name, asset, kind, shared,
## found_by_you, about}] in data order.
func visible_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for machine: String in chains:
		var data: Dictionary = chains[machine]
		var inv := inventory.states(machine)
		for item in ChainRules.visible_items(data, states[machine], inv):
			var def := ChainRules.item_def(data, item)
			var entry := inventory.entry(machine, item)
			out.append({
				"machine": machine, "item_id": item, "name": str(def.get("name", item)),
				"asset": str(def.get("asset", "")), "kind": str(def.get("kind", "part")),
				"shared": bool(def.get("shared", true)), "about": str(def.get("about", "")),
				"found_by_you": str(entry.get("found_by", GameState.device_id)) == GameState.device_id,
			})
	return out


func has_item(item: String) -> bool:
	for entry in visible_items():
		if entry["item_id"] == item:
			return true
	return false


func sync_now() -> void:
	if inventory is RemoteInventoryStore:
		(inventory as RemoteInventoryStore).flush()
		inventory.refresh()


func _build_inventory() -> void:
	if local_inventory == null:
		local_inventory = LocalInventoryStore.new(LocalInventoryStore.DEFAULT_PATH if persist else "")
	if not Progress.scoreboard_active() or not persist:
		_retire_remote()
		_set_inventory(local_inventory)
		return
	var crews: Array[String] = []
	if GameState.crew != "":
		crews.append(GameState.crew)
	if inventory is RemoteInventoryStore and (inventory as RemoteInventoryStore).base_url == Progress.scoreboard_url.strip_edges().rstrip("/"):
		(inventory as RemoteInventoryStore).set_watching(crews)
		return
	_retire_remote()
	var remote := RemoteInventoryStore.new(Progress.scoreboard_url, local_inventory, Progress.network())
	_set_inventory(remote)
	for machine: String in chains:
		remote.backfill(machine, GameState.device_id)
	remote.set_watching(crews)


func _set_inventory(store: InventoryStore) -> void:
	if inventory == store:
		return
	if inventory != null and inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.disconnect(_on_inventory_changed)
	inventory = store
	inventory.changed.connect(_on_inventory_changed)
	inventory_changed.emit()


func _retire_remote() -> void:
	if inventory is RemoteInventoryStore:
		var remote := inventory as RemoteInventoryStore
		if remote.changed.is_connected(_on_inventory_changed):
			remote.changed.disconnect(_on_inventory_changed)
		remote.retire()
		inventory = null


func _on_inventory_changed(_machine: String) -> void:
	inventory_changed.emit()


func _on_tick() -> void:
	if inventory is RemoteInventoryStore:
		(inventory as RemoteInventoryStore).tick()


# --- Hints --------------------------------------------------------------------------


## Red Panda's help: the next hint piece id for the first unfinished chain
## step (a nudge, then a stronger nudge; asking again repeats the stronger
## one), or "" when every chain is done.
func next_hint() -> String:
	for machine: String in chains:
		var data: Dictionary = chains[machine]
		for c: Dictionary in ChainRules.chains(data):
			var step := ChainRules.current_step(data, c, states[machine], inventory.states(machine))
			if step.is_empty():
				continue
			var hints: Array = step.get("hints", [])
			if hints.is_empty():
				continue
			var key := "%s/%s/%s" % [machine, str(c["id"]), str(step["id"])]
			var level := int(_hint_levels.get(key, 0))
			_hint_levels[key] = level + 1
			return str(hints[mini(level, hints.size() - 1)])
	return ""


# --- Persistence --------------------------------------------------------------------


func _load_states() -> void:
	for machine: String in CHAIN_FILES:
		states[machine] = ChainState.new("user://chain_%s.json" % machine if persist else "")


func _save_place() -> void:
	if persist:
		JsonFile.write(PLACE_PATH, {"room": room_id, "x": cell.x, "y": cell.y})
