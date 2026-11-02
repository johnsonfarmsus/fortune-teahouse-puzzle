# SPDX-License-Identifier: AGPL-3.0-or-later
class_name Room
extends Node2D
## One walkable room, built from data/rooms.json: tiles, props, characters,
## the Cookie Machine rig, ambient motion, the walking player and a camera
## that follows in rooms taller than the screen. It only presents: taps become
## signals (thing_activated, item_used, exit_reached) that AdventureView turns
## into chain interactions. Hit tests use the data rects (RoomGraph.thing_at),
## not physics picking. Every tap answers at once with a sound and a ring.

signal tapped(point: Vector2)
signal thing_activated(thing: Dictionary)
signal item_used(thing: Dictionary, item: String)
signal exit_reached(exit: Dictionary)
signal walk_finished

const TILE := 16
const WALK_SPEED := 80.0  # pixels per second (5 tiles)
const WATER_SECONDS := 0.45
const VIEW := Vector2(176, 320)


## Draws the static tiles once; animated tiles redraw on their own clock.
class TileLayer:
	extends Node2D
	var room: Room
	var animated := false
	var frame := 0

	func _draw() -> void:
		var size := room.graph.size_tiles(room.room_id)
		for y in size.y:
			for x in size.x:
				var cell := Vector2i(x, y)
				var asset := room.graph.tile_asset(room.room_id, cell)
				if asset == "":
					continue
				var frames := room.assets.frame_count(asset)
				if (frames > 1) != animated:
					continue
				draw_texture(room.assets.texture(asset, (frame + x + y) % frames if animated else 0), Vector2(cell * TILE))


var room_id: String = ""
var graph: RoomGraph
var assets: AssetLoader
var spawn_cell: Vector2i = Vector2i(-1, -1)
var player: AnimatedSprite2D
var camera: Camera2D
var things_layer: Node2D
var rig: CookieMachineRig
## While true, taps do nothing (dialogue or a close-up has the screen).
var input_enabled: bool = true
## An inventory item picked for the next tap on a thing (tap-to-use).
var use_item: String = ""

var _nodes: Dictionary = {}  # thing id -> CanvasItem
var _path: Array[Vector2i] = []
var _then: Callable = Callable()
var _cell: Vector2i
var _facing := "down"
var _steps := 0
var _water: TileLayer
var _water_clock := 0.0
var _shake_tween: Tween


func setup(p_room_id: String, p_graph: RoomGraph, p_assets: AssetLoader, p_spawn: Vector2i) -> void:
	room_id = p_room_id
	graph = p_graph
	assets = p_assets
	spawn_cell = p_spawn
	name = "Room_" + room_id


func _ready() -> void:
	y_sort_enabled = false
	var ground := TileLayer.new()
	ground.name = "Tiles"
	ground.room = self
	add_child(ground)
	_water = TileLayer.new()
	_water.name = "AnimatedTiles"
	_water.room = self
	_water.animated = true
	add_child(_water)
	things_layer = Node2D.new()
	things_layer.name = "Things"
	things_layer.y_sort_enabled = true
	add_child(things_layer)
	for r: Dictionary in graph.room(room_id).get("rigs", []):
		_add_rig(r)
	for t in graph.things(room_id):
		_add_thing(t)
	_add_player()
	_add_ambient()
	camera = Camera2D.new()
	camera.name = "Camera"
	var size := graph.size_px(room_id)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = size.x
	camera.limit_bottom = size.y
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	add_child(camera)
	camera.position = player_center()
	camera.reset_smoothing()
	camera.make_current()


func _process(delta: float) -> void:
	_water_clock += delta
	if _water_clock >= WATER_SECONDS:
		_water_clock = 0.0
		_water.frame += 1
		_water.queue_redraw()
	if not _path.is_empty():
		_walk(delta)
	if camera != null:
		camera.position = player_center()


func _unhandled_input(event: InputEvent) -> void:
	# Touches arrive as emulated mouse buttons.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap_world(get_canvas_transform().affine_inverse() * (event as InputEventMouseButton).position)
		get_viewport().set_input_as_handled()


# --- Taps ---------------------------------------------------------------------------


## A tap at a room position: a ring and a blip at once, then walk to what was tapped.
func tap_world(point: Vector2) -> Dictionary:
	if not input_enabled:
		return {}
	tapped.emit(point)
	_tap_ring(point)
	var t := graph.thing_at(room_id, point)
	if not t.is_empty():
		Audio.play("select")
		flash(str(t["id"]))
		var item := use_item
		use_item = ""
		walk_to(graph.stand_cell(room_id, t), func() -> void:
			face_towards(RoomGraph.rect_px(t).get_center())
			if item != "":
				item_used.emit(t, item)
			else:
				thing_activated.emit(t))
		return t
	Audio.play("tap")
	use_item = ""
	var cell := cell_of(point)
	if not graph.exit_at(room_id, cell).is_empty():
		walk_to(cell)
	else:
		walk_to(graph.nearest_walkable(room_id, cell))
	return {}


## An item dropped on the room. Returns false if it landed on nothing.
func drop_item(point: Vector2, item: String) -> bool:
	var t := graph.thing_at(room_id, point)
	if t.is_empty():
		return false
	_tap_ring(point)
	flash(str(t["id"]))
	walk_to(graph.stand_cell(room_id, t), func() -> void:
		face_towards(RoomGraph.rect_px(t).get_center())
		item_used.emit(t, item))
	return true


func thing_node(id: String) -> CanvasItem:
	return _nodes.get(id)


## A quick bright blink on a thing, so a tap visibly lands.
func flash(id: String) -> void:
	var node := thing_node(id)
	if node == null:
		return
	var tween := create_tween()
	tween.tween_property(node, "modulate", Color(1.6, 1.6, 1.3), 0.05)
	tween.tween_property(node, "modulate", Color.WHITE, 0.12)


func shake(strength: float = 2.0, seconds: float = 0.3) -> void:
	if camera == null:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps := int(seconds / 0.04)
	for i in steps:
		var fade := 1.0 - float(i) / steps
		_shake_tween.tween_property(camera, "offset", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * fade, 0.04)
	_shake_tween.tween_property(camera, "offset", Vector2.ZERO, 0.04)


## Sparks (and a puff) at a room position, for a success.
func burst(point: Vector2, color: Color = Color(1, 0.85, 0.3)) -> void:
	var p := CPUParticles2D.new()
	p.position = point
	p.amount = 18
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.6
	p.texture = assets.texture("fx.spark", 1)
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.gravity = Vector2(0, 120)
	p.color = color
	p.z_index = 50
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# --- Walking ------------------------------------------------------------------------


func player_cell() -> Vector2i:
	return _cell


func player_center() -> Vector2:
	return player.position + Vector2(TILE / 2.0, -TILE / 2.0) if player != null else Vector2.ZERO


func is_walking() -> bool:
	return not _path.is_empty()


static func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(int(floor(point.x / TILE)), int(floor(point.y / TILE)))


## Walks to `target` on a 4-way path, then calls `then`. A new walk replaces the old.
func walk_to(target: Vector2i, then: Callable = Callable()) -> void:
	var route := graph.path(room_id, _cell, target)
	if route.is_empty():
		_path.clear()
		Audio.play("deny")
		return
	route.pop_front()
	_path = route
	_then = then
	if _path.is_empty():
		_arrive()


## Finishes the current walk at once (tests, and the text-assist mode later).
func finish_walk() -> void:
	var guard := 200
	while not _path.is_empty() and guard > 0:
		guard -= 1
		var next: Vector2i = _path[0]
		player.position = _bottom_left(next)
		_reach(next)


func face_towards(point: Vector2) -> void:
	var d := point - player_center()
	if absf(d.x) > absf(d.y):
		_facing = "right" if d.x > 0 else "left"
	else:
		_facing = "down" if d.y > 0 else "up"
	player.play("idle_" + _facing)


func _walk(delta: float) -> void:
	var next: Vector2i = _path[0]
	var goal := _bottom_left(next)
	var d := goal - player.position
	if d.x != 0 and absf(d.x) >= absf(d.y):
		_facing = "right" if d.x > 0 else "left"
	elif d.y != 0:
		_facing = "down" if d.y > 0 else "up"
	if player.animation != "walk_" + _facing:
		player.play("walk_" + _facing)
	var step := WALK_SPEED * delta
	if d.length() <= step:
		player.position = goal
		_reach(next)
	else:
		player.position += d.normalized() * step


func _reach(cell: Vector2i) -> void:
	_path.pop_front()
	_cell = cell
	_steps += 1
	if _steps % 2 == 0:
		Audio.play("step")
	var e := graph.exit_at(room_id, cell)
	if not e.is_empty():
		_path.clear()
		_then = Callable()
		exit_reached.emit(e)
		return
	if _path.is_empty():
		_arrive()


func _arrive() -> void:
	player.play("idle_" + _facing)
	var then := _then
	_then = Callable()
	walk_finished.emit()
	if then.is_valid():
		then.call()


func _bottom_left(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE, (cell.y + 1) * TILE)


# --- Building -----------------------------------------------------------------------


func _add_thing(t: Dictionary) -> void:
	var asset := str(t.get("asset", ""))
	if asset == "":
		return
	var rect := RoomGraph.rect_px(t)
	var sprite := AnimatedSprite2D.new()
	sprite.name = str(t["id"])
	sprite.sprite_frames = assets.frames(asset)
	sprite.centered = false
	var size := assets.frame_size(asset)
	sprite.offset = Vector2(0, -size.y)
	sprite.position = Vector2(rect.position.x, rect.position.y + size.y)
	if t["kind"] == "npc":
		var facing := str(t.get("facing", "down"))
		var anim := "idle_" + facing
		sprite.animation = anim if sprite.sprite_frames.has_animation(anim) else sprite.sprite_frames.get_animation_names()[0]
		sprite.position = Vector2(rect.position.x, rect.end.y)
	else:
		sprite.animation = sprite.sprite_frames.get_animation_names()[0]
	sprite.play()
	sprite.frame = randi() % maxi(1, sprite.sprite_frames.get_frame_count(sprite.animation))
	things_layer.add_child(sprite)
	_nodes[str(t["id"])] = sprite


func _add_rig(r: Dictionary) -> void:
	rig = CookieMachineRig.new()
	rig.name = "Rig_" + str(r.get("id", "machine"))
	var at: Array = r.get("at_px", [0, 0])
	rig.position = Vector2(float(at[0]), float(at[1]))
	rig.setup(str(r.get("machine", "")), assets, self)
	add_child(rig)


func _add_player() -> void:
	player = AnimatedSprite2D.new()
	player.name = "Player"
	player.sprite_frames = assets.frames("char.player")
	player.centered = false
	player.offset = Vector2(0, -TILE)
	_cell = spawn_cell if graph.is_walkable(room_id, spawn_cell) else graph.nearest_walkable(room_id, spawn_cell)
	player.position = _bottom_left(_cell)
	if _cell.y >= graph.size_tiles(room_id).y - 2:
		_facing = "up"
	player.play("idle_" + _facing)
	things_layer.add_child(player)


func _tap_ring(point: Vector2) -> void:
	var ring := AnimatedSprite2D.new()
	ring.sprite_frames = assets.frames("fx.tap")
	ring.position = point
	ring.z_index = 40
	ring.sprite_frames.set_animation_loop("default", false)
	ring.sprite_frames.set_animation_speed("default", 20.0)
	add_child(ring)
	ring.play("default")
	ring.animation_finished.connect(ring.queue_free)


func _add_ambient() -> void:
	for a: Dictionary in graph.room(room_id).get("ambient", []):
		var at: Array = a.get("at", [0, 0])
		var p := Vector2(float(at[0]) * TILE, float(at[1]) * TILE)
		match str(a.get("kind", "")):
			"steam":
				var steam := CPUParticles2D.new()
				steam.name = "Steam"
				steam.position = p + Vector2(8, 2)
				steam.texture = assets.texture("fx.steam")
				steam.amount = 5
				steam.lifetime = 1.6
				steam.direction = Vector2(0, -1)
				steam.spread = 20.0
				steam.gravity = Vector2(0, -12)
				steam.initial_velocity_min = 4.0
				steam.initial_velocity_max = 8.0
				steam.color = Color(1, 1, 1, 0.7)
				steam.z_index = 30
				add_child(steam)
			"gulls":
				for i in 2:
					_gull(p.y + i * 22.0, 7.0 + i * 3.0, i * 2.5)
			"sparkle":
				_sparkle(p)
			"bubbles":
				_bubbles(p)


func _gull(y: float, seconds: float, delay: float) -> void:
	var gull := AnimatedSprite2D.new()
	gull.name = "Gull"
	gull.sprite_frames = assets.frames("fx.gull")
	gull.play()
	gull.position = Vector2(-12, y)
	gull.z_index = 60
	add_child(gull)
	var tween := create_tween().set_loops()
	tween.tween_interval(delay)
	tween.tween_property(gull, "position:x", VIEW.x + 12, seconds).from(-12.0)
	tween.parallel().tween_property(gull, "position:y", y - 10, seconds / 2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(gull, "position:y", y, 0.01)


func _sparkle(p: Vector2) -> void:
	var s := AnimatedSprite2D.new()
	s.name = "Sparkle"
	s.sprite_frames = assets.frames("fx.sparkle")
	s.play()
	s.position = p + Vector2(8, 8)
	s.z_index = 5
	add_child(s)
	var tween := create_tween().set_loops()
	tween.tween_property(s, "modulate:a", 0.0, 0.7)
	tween.tween_callback(func() -> void: s.position = p + Vector2(randf_range(0, 32), randf_range(0, 24)))
	tween.tween_property(s, "modulate:a", 1.0, 0.7)


func _bubbles(p: Vector2) -> void:
	var b := Sprite2D.new()
	b.name = "Bubble"
	b.texture = assets.texture("fx.bubble")
	b.position = p
	b.z_index = 5
	add_child(b)
	var tween := create_tween().set_loops()
	tween.tween_property(b, "position:y", p.y - 14, 1.6).from(p.y)
	tween.parallel().tween_property(b, "modulate:a", 0.0, 1.6).from(1.0)
	tween.tween_interval(0.8)
