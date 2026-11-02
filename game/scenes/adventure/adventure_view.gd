# SPDX-License-Identifier: AGPL-3.0-or-later
class_name AdventureView
extends Control
## The player-facing adventure layer (game/ARCHITECTURE.md section 15). The
## room is rendered in a 176x320 SubViewport (PLAN.md D9: 11 by 20 tiles of
## 16 px), scaled by a whole number of device pixels with no smoothing and
## letterboxed; the inventory bar sits above it and the dialogue bar below.
## Rooms change with a flip-screen slide at edges and a fade at doors. Taps,
## drops and close-ups go through Adventure.interact() and come back here to
## be shown: dialogue, sounds, close-ups, the merge celebration.

signal room_changed(room_id: String)
signal presented(result: Dictionary)

const VIEW := Vector2i(176, 320)
const TOP_MIN := 52.0
const BOTTOM_MIN := 96.0
const FADE_SECONDS := 0.14
const SLIDE_SECONDS := 0.3
const ROOM_SCENE := "res://scenes/adventure/room.tscn"
const DIRS := {"north": Vector2(0, -1), "south": Vector2(0, 1), "east": Vector2(1, 0), "west": Vector2(-1, 0)}

## Tests set this so room changes happen at once.
var instant_transitions: bool = false
var room: Room
var room_id: String = ""
var pixel_scale: float = 2.0
var closeup: Control
var frame_rect: Rect2

var _frame: SubViewportContainer
var _viewport: SubViewport
var _world: Node2D
var _fade: ColorRect
var _slide: Control
var _bar: InventoryBar
var _dialogue: PortraitDialogue
var _catcher: Control
var _closeup_layer: Control
var _closeup_header: HBoxContainer
var _closeup_title: Label
var _closeup_hint_button: Button
var _closeup_hint: Label
var _confirm_row: HBoxContainer
var _closeup_name: String = ""
var _ghost: TextureRect
var _dragging: Dictionary = {}
var _selected: Dictionary = {}
var _transitioning := false
var _known_items: Array[String] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.name = "Letterbox"
	bg.color = Color(0.05, 0.04, 0.07)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_frame = SubViewportContainer.new()
	_frame.name = "RoomFrame"
	_frame.stretch = false
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_frame)
	_viewport = SubViewport.new()
	_viewport.name = "RoomViewport"
	_viewport.size = VIEW
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.snap_2d_transforms_to_pixel = true
	_viewport.snap_2d_vertices_to_pixel = true
	_viewport.handle_input_locally = true
	_viewport.physics_object_picking = false
	_frame.add_child(_viewport)
	_frame.size = Vector2(VIEW)
	_world = Node2D.new()
	_world.name = "World"
	_viewport.add_child(_world)
	_fade = _overlay_rect("Fade", Color(0, 0, 0, 0))
	_slide = Control.new()
	_slide.name = "Slide"
	_slide.clip_contents = true
	_slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide.visible = false
	add_child(_slide)
	_catcher = Control.new()
	_catcher.name = "DialogueCatcher"
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.visible = false
	_catcher.gui_input.connect(_on_catcher_input)
	add_child(_catcher)
	_build_closeup_layer()
	_bar = InventoryBar.new()
	_bar.name = "InventoryBar"
	_bar.assets = Adventure.assets
	add_child(_bar)
	_bar.item_tapped.connect(_on_item_tapped)
	_bar.drag_started.connect(_on_drag_started)
	_bar.clues_pressed.connect(func() -> void: Router.push(Paths.CLUE_BOARD))
	_bar.menu_pressed.connect(func() -> void: Router.push(Paths.SETTINGS))
	_dialogue = PortraitDialogue.new()
	_dialogue.name = "Dialogue"
	_dialogue.assets = Adventure.assets
	add_child(_dialogue)
	_ghost = TextureRect.new()
	_ghost.name = "DragGhost"
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.visible = false
	_ghost.z_index = 100
	add_child(_ghost)
	var banner_layer := CanvasLayer.new()
	banner_layer.layer = 30
	add_child(banner_layer)
	banner_layer.add_child(load(Paths.HINT_BANNER).instantiate())
	Adventure.inventory_changed.connect(_refresh_items)
	Events.crew_changed.connect(func(_m: String) -> void: _refresh_items())
	Events.clue_collected.connect(func(_c: String) -> void: _refresh_items())
	Events.scoreboard_status_changed.connect(_refresh_items)
	get_viewport().size_changed.connect(_layout)
	_layout()
	for e in Adventure.visible_items():
		_known_items.append(str(e["item_id"]))
	_refresh_items()
	var start := Adventure.room_id
	var cell := Adventure.cell
	if not Adventure.rooms.has_room(start) or not Adventure.rooms.is_walkable(start, cell):
		start = Adventure.rooms.start_room()
		cell = Adventure.rooms.spawn(start, Adventure.rooms.start_spawn())
	_enter(start, cell)


func _process(_delta: float) -> void:
	var talking := _dialogue.is_open()
	_catcher.visible = talking and closeup == null
	if room != null:
		room.input_enabled = not talking and closeup == null and not _transitioning and Router.depth() == 0
		room.celebrations_allowed = closeup == null and not _transitioning


# --- Layout -------------------------------------------------------------------------


## Whole device pixels per art pixel; bars above and below; letterboxed.
func _layout() -> void:
	var vis := get_viewport_rect().size
	if vis.x <= 0 or vis.y <= 0:
		return
	var device := device_scale()
	var avail := vis.y - TOP_MIN - BOTTOM_MIN
	var k_device := floorf(minf(vis.x * device / VIEW.x, avail * device / VIEW.y))
	var overlay := k_device < 1.0
	if overlay:
		k_device = maxf(1.0, floorf(minf(vis.x * device / VIEW.x, vis.y * device / VIEW.y)))
	pixel_scale = k_device / device
	var frame_size := Vector2(VIEW) * pixel_scale
	var left := _snap((vis.x - frame_size.x) / 2.0, device)
	var spare := vis.y - frame_size.y
	var top := TOP_MIN if overlay else _snap(TOP_MIN + maxf(0.0, spare - TOP_MIN - BOTTOM_MIN) * 0.35, device)
	if overlay:
		top = _snap(spare / 2.0, device)
	frame_rect = Rect2(Vector2(left, top), frame_size)
	_frame.position = frame_rect.position
	_frame.scale = Vector2(pixel_scale, pixel_scale)
	for c: Control in [_fade, _slide, _catcher, _closeup_layer]:
		c.position = frame_rect.position
		c.size = frame_rect.size
	var bar_h := maxf(TOP_MIN, frame_rect.position.y) if not overlay else TOP_MIN
	_bar.position = Vector2.ZERO
	_bar.size = Vector2(vis.x, bar_h)
	_bar.custom_minimum_size = Vector2(vis.x, bar_h)
	var bottom_h := maxf(BOTTOM_MIN, vis.y - frame_rect.end.y) if not overlay else BOTTOM_MIN
	_dialogue.custom_minimum_size = Vector2(vis.x, bottom_h)
	_dialogue.position = Vector2(0, vis.y - bottom_h)
	_dialogue.size = Vector2(vis.x, bottom_h)
	_dialogue.pixel_scale = pixel_scale
	_dialogue.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Device pixels per layout pixel (the window's stretch). Below 1 (a window
## smaller than the base size, or headless) whole pixels are not possible, so
## layout pixels are used instead.
func device_scale() -> float:
	return maxf(1.0, get_tree().root.get_final_transform().x.x)


func _snap(value: float, device: float) -> float:
	return roundf(value * device) / device


## A room-view point (art pixels in the room) for a screen position, or (-1, -1).
func screen_to_room(screen: Vector2) -> Vector2:
	if not frame_rect.has_point(screen) or room == null:
		return Vector2(-1, -1)
	var vp := (screen - frame_rect.position) / pixel_scale
	return _viewport.get_canvas_transform().affine_inverse() * vp


func room_to_screen(point: Vector2) -> Vector2:
	return frame_rect.position + (_viewport.get_canvas_transform() * point) * pixel_scale


func dialogue() -> PortraitDialogue:
	return _dialogue


func inventory_bar() -> InventoryBar:
	return _bar


# --- Rooms --------------------------------------------------------------------------


## Moves to `to` at spawn `arrive` with the exit's transition.
func go_through(e: Dictionary) -> void:
	var to := str(e.get("to", ""))
	if not Adventure.rooms.has_room(to) or _transitioning:
		return
	var cell := Adventure.rooms.spawn(to, str(e.get("arrive", "")))
	var kind := str(e.get("kind", "door"))
	Audio.play("door" if kind == "door" else "edge")
	if instant_transitions:
		_enter(to, cell)
		return
	if kind == "edge":
		_slide_to(to, cell, DIRS.get(str(e.get("dir", "east")), Vector2(1, 0)))
	else:
		_fade_to(to, cell)


func _enter(to: String, cell: Vector2i) -> void:
	if room != null:
		_world.remove_child(room)
		room.queue_free()
	room_id = to
	room = load(ROOM_SCENE).instantiate()
	room.setup(to, Adventure.rooms, Adventure.assets, cell)
	room.thing_activated.connect(_on_thing_activated)
	room.item_used.connect(_on_item_used)
	room.exit_reached.connect(go_through)
	room.walk_finished.connect(func() -> void: Adventure.set_place(room_id, room.player_cell()))
	_world.add_child(room)
	if room.rig != null:
		room.rig.part_celebrated.connect(_on_part_celebrated)
	Adventure.set_place(to, room.player_cell())
	Audio.play_ambient(str(Adventure.rooms.room(to).get("sound", "")))
	_dialogue.idle_text = _idle_title()
	room_changed.emit(to)
	var arrive := Adventure.interact(to, to, "enter")
	if not arrive.is_empty():
		present(arrive)


func _idle_title() -> String:
	var title := str(Adventure.rooms.room(room_id).get("title", room_id))
	var crew := Ids.machine_title(GameState.crew) + " crew" if GameState.crew != "" else "No crew yet"
	var online := ""
	if Adventure.inventory is RemoteInventoryStore:
		online = ", online" if Adventure.inventory.is_online() else ", offline"
	return "%s  -  %s%s" % [title, crew, online]


func _fade_to(to: String, cell: Vector2i) -> void:
	_transitioning = true
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_SECONDS)
	tween.tween_callback(func() -> void: _enter(to, cell))
	tween.tween_property(_fade, "color:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func() -> void: _transitioning = false)


## The old room slides out as the new one slides in (snapshots of the view).
func _slide_to(to: String, cell: Vector2i, dir: Vector2) -> void:
	var old_image := _viewport.get_texture().get_image()
	if old_image == null or old_image.is_empty():
		_fade_to(to, cell)
		return
	_transitioning = true
	var old_rect := _snapshot_rect(old_image)
	_slide.visible = true
	_slide.add_child(old_rect)
	_enter(to, cell)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var new_image := _viewport.get_texture().get_image()
	var new_rect := _snapshot_rect(new_image if new_image != null else old_image)
	new_rect.position = dir * frame_rect.size
	_slide.add_child(new_rect)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(old_rect, "position", -dir * frame_rect.size, SLIDE_SECONDS).set_trans(Tween.TRANS_SINE)
	tween.tween_property(new_rect, "position", Vector2.ZERO, SLIDE_SECONDS).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(func() -> void:
		old_rect.queue_free()
		new_rect.queue_free()
		_slide.visible = false
		_transitioning = false)


func _snapshot_rect(image: Image) -> TextureRect:
	var r := TextureRect.new()
	r.texture = ImageTexture.create_from_image(image)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = frame_rect.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# --- Things -------------------------------------------------------------------------


func _on_thing_activated(t: Dictionary) -> void:
	var id := str(t.get("id", ""))
	var r := Adventure.interact(room_id, id, "tap")
	if not r.is_empty():
		present(r)
		return
	if t.get("kind", "") == "npc":
		Audio.play("talk")
	var pieces: Array = []
	if bool(t.get("hint", false)):
		var hint := Adventure.next_hint()
		if hint != "":
			pieces.append(Story.get_piece(hint))
	if pieces.is_empty():
		var say: Array = t.get("say", [])
		if not say.is_empty():
			var index := Story.rotate("say:%s:%s" % [room_id, id], say.size())
			pieces.append(Story.get_piece(str(say[index])))
	var open := str(t.get("open", ""))
	if open.begins_with("closeup:") or open.begins_with("lock:"):
		open_target(open)
		if not pieces.is_empty():
			_dialogue.say(pieces)
		return
	if pieces.is_empty():
		open_target(open)
		return
	_dialogue.say(pieces, func() -> void: open_target(open))


func _on_item_used(t: Dictionary, item: String) -> void:
	_deselect()
	var r := Adventure.interact(room_id, str(t.get("id", "")), "use", item)
	if r.is_empty():
		Audio.play("deny")
		_dialogue.say([Story.get_piece("narrator.use.nothing")])
		return
	present(r)


## Shows what an interaction did: its sound, its lines, a close-up, a solve.
func present(r: Dictionary, then: Callable = Callable()) -> void:
	if str(r.get("sfx", "")) != "":
		Audio.play(str(r["sfx"]))
	var pieces: Array = []
	for id: Variant in r.get("say", []):
		var piece := Story.get_piece(str(id))
		if not piece.is_empty():
			pieces.append(piece)
			Story.mark_seen(str(id))
	var open := str(r.get("open", ""))
	if open != "":
		open_target(open)
	if str(r.get("decoy", "")) != "" and room != null:
		room.shake(1.5, 0.25)
	var solved := str(r.get("solved_part", ""))
	if solved != "" and room != null:
		room.burst(room.player_center() + Vector2(0, -12))
		room.shake(2.5, 0.4)
	presented.emit(r)
	_dialogue.say(pieces, func() -> void:
		if solved != "":
			_celebrate_merge(str(r["machine"]), solved, true, bool(r.get("now_running", false)))
		if then.is_valid():
			then.call())


func _celebrate_merge(machine: String, part: String, credited: bool, now_running: bool) -> void:
	Router.push(Paths.MERGE_CELEBRATION, {"machine": machine, "part": part, "credited": credited, "now_running": now_running})


func _on_part_celebrated(_part: String, caption_id: String) -> void:
	var piece := Story.get_piece(caption_id)
	if not piece.is_empty():
		_dialogue.say([piece])


## Opens a menu screen or a close-up by name (room data and chain effects).
func open_target(target: String) -> void:
	if target == "":
		return
	if target == "lucky_word_entry":
		Router.push(Paths.LUCKY_WORD_ENTRY)
	elif target == "contributors":
		Router.push(Paths.CONTRIBUTORS)
	elif target.begins_with("machine_view:"):
		Router.push(Paths.MACHINE_VIEW, {"machine": target.trim_prefix("machine_view:")})
	elif target.begins_with("puzzle:"):
		var id := target.trim_prefix("puzzle:")
		Router.push(Paths.PUZZLE_HOST, {"machine": id.get_slice("/", 0), "part": id.get_slice("/", 1)})
	elif target == "closeup:batter_shelf":
		open_batter_shelf()
	else:
		open_closeup(target)


# --- Inventory ----------------------------------------------------------------------


func _refresh_items() -> void:
	var entries := Adventure.visible_items()
	_bar.show_items(entries)
	for e in entries:
		var id := str(e["item_id"])
		if not _known_items.has(id):
			_known_items.append(id)
			var slot := _bar.slot_for(id)
			if slot != null:
				slot.pivot_offset = slot.custom_minimum_size / 2.0
				slot.scale = Vector2(1.6, 1.6)
				var tween := slot.create_tween()
				tween.tween_property(slot, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	if not _selected.is_empty() and not Adventure.has_item(str(_selected["item_id"])):
		_deselect()
	_dialogue.idle_text = _idle_title() if room_id != "" else ""


## A tap on an item: what it is and who found it, and it is picked for the next tap.
func _on_item_tapped(entry: Dictionary) -> void:
	if not _selected.is_empty() and _selected["item_id"] == entry["item_id"]:
		_deselect()
		return
	_selected = entry
	_bar.selected_item = str(entry["item_id"])
	if room != null:
		room.use_item = str(entry["item_id"])
	var pieces: Array = []
	var about := Story.get_piece(str(entry.get("about", "")))
	if not about.is_empty():
		pieces.append(about)
	if bool(entry.get("shared", true)):
		var who := "you" if bool(entry.get("found_by_you", true)) else "a crewmate"
		pieces.append({"speaker": "Narrator", "kind": "", "lines": ["%s. Found by %s. Tap something in the room to use it, or drag it there." % [entry["name"], who]]})
	_dialogue.skip_all()
	_dialogue.say(pieces)


func _deselect() -> void:
	_selected = {}
	_bar.selected_item = ""
	if room != null:
		room.use_item = ""


func _on_drag_started(entry: Dictionary, at: Vector2) -> void:
	_dragging = entry
	_ghost.texture = Adventure.assets.texture(str(entry["asset"]))
	_ghost.size = Vector2(_ghost.texture.get_size()) * pixel_scale * 1.5
	_ghost.position = at - _ghost.size / 2.0
	_ghost.visible = true
	Audio.play("drag_start")


func _input(event: InputEvent) -> void:
	if _dragging.is_empty():
		return
	if event is InputEventMouseMotion:
		_ghost.position = event.position - _ghost.size / 2.0
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		drop_item_at(event.position, str(_dragging["item_id"]))


## Ends a drag at a screen position. Returns true if it landed on something.
func drop_item_at(screen: Vector2, item: String) -> bool:
	_dragging = {}
	_ghost.visible = false
	_deselect()
	var point := screen_to_room(screen)
	if point.x < 0 or closeup != null or room == null:
		Audio.play("drop")
		return false
	if room.drop_item(point, item):
		Audio.play("select")
		return true
	Audio.play("deny")
	return false


func _on_catcher_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_catcher.accept_event()
		_dialogue.advance()


# --- Close-ups ----------------------------------------------------------------------


func _build_closeup_layer() -> void:
	_closeup_layer = Control.new()
	_closeup_layer.name = "CloseUp"
	_closeup_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_closeup_layer.visible = false
	add_child(_closeup_layer)
	_closeup_header = HBoxContainer.new()
	_closeup_header.add_theme_constant_override("separation", 6)
	_closeup_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_closeup_header.z_index = 10
	_closeup_title = UiKit.label("", 16)
	_closeup_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_closeup_title.add_theme_color_override("font_color", Color(0.95, 0.76, 0.31))
	_closeup_title.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.12))
	_closeup_title.add_theme_constant_override("outline_size", 4)
	_closeup_hint_button = UiKit.button("Hint", Vector2(64, 44))
	_closeup_hint_button.pressed.connect(_on_closeup_hint)
	var close := UiKit.button("X", Vector2(44, 44))
	close.name = "Close"
	close.pressed.connect(func() -> void:
		Audio.play("drop")
		close_closeup())
	_closeup_header.add_child(_closeup_title)
	_closeup_header.add_child(_closeup_hint_button)
	_closeup_header.add_child(close)
	_closeup_hint = UiKit.label("", 15)
	_closeup_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_closeup_hint.offset_top = 48
	_closeup_hint.z_index = 10
	_closeup_hint.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.12))
	_closeup_hint.add_theme_constant_override("outline_size", 4)
	_confirm_row = HBoxContainer.new()
	_confirm_row.visible = false
	_confirm_row.z_index = 10
	_confirm_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_confirm_row.offset_top = 96
	var sure := UiKit.button("Reveal", Vector2(110, 44))
	sure.pressed.connect(func() -> void:
		_confirm_row.visible = false
		(closeup as PuzzleBase).request_hint())
	var keep := UiKit.button("Keep trying", Vector2(130, 44))
	keep.pressed.connect(func() -> void:
		_confirm_row.visible = false
		_closeup_hint.text = "")
	_confirm_row.add_child(sure)
	_confirm_row.add_child(keep)
	for c: Control in [_closeup_header, _closeup_hint, _confirm_row]:
		_closeup_layer.add_child(c)


## Opens a close-up by name: lock:<id>, straighten or tighten.
func open_closeup(target: String) -> void:
	var node: CloseUpBase
	var title := ""
	if target.begins_with("lock:"):
		var lock_id := target.trim_prefix("lock:")
		var lock := LockDials.new()
		lock.configure(lock_id, _lock_def(lock_id))
		lock.code_entered.connect(_on_code_entered.bind(lock))
		lock.label_pressed.connect(func() -> void:
			_dialogue.skip_all()
			_dialogue.say([Story.get_piece(str(_lock_def(lock_id).get("label", "")))]))
		node = lock
		title = "The gnu's locker"
	elif target == "straighten":
		node = StraightenBench.new()
		title = "Penguin's bench"
	elif target == "tighten":
		node = TightenBolts.new()
		title = "The cutter"
	else:
		return
	node.assets = Adventure.assets
	node.pixel_scale = pixel_scale
	node.done.connect(_on_closeup_done.bind(target))
	_show_closeup(node, title, target, false)


func open_batter_shelf() -> void:
	var machine := "cookie_machine"
	var puzzle: PuzzleBase = load(Paths.BATTER_SHELF).instantiate()
	puzzle.puzzle_id = machine + "/logic"
	puzzle.machine = machine
	puzzle.part = "logic"
	if not GameState.player.is_part_credited(machine, "logic"):
		Hints.reset(puzzle.puzzle_id)
	puzzle.configure(PuzzleData.matching_config(machine, GameState.collected_clue_ids))
	puzzle.solved.connect(_on_puzzle_solved.bind(puzzle))
	puzzle.hint_requested.connect(_on_hint_requested)
	puzzle.give_up.connect(close_closeup)
	var title := str(PuzzleData.get_part(machine, "logic").get("title", "Batter recipe"))
	_show_closeup(puzzle, title, "batter_shelf", true)
	var note := Story.next_unseen("puzzle:%s/logic" % machine, "first_visit", {"part": title, "machine": Ids.machine_title(machine)})
	if not note.is_empty():
		Story.mark_seen(str(note["id"]))
		_dialogue.say([note])


func close_closeup() -> void:
	if closeup != null:
		closeup.queue_free()
	closeup = null
	_closeup_name = ""
	_closeup_layer.visible = false
	_confirm_row.visible = false
	_closeup_hint.text = ""


func closeup_name() -> String:
	return _closeup_name


func _show_closeup(node: Control, title: String, target: String, hints: bool) -> void:
	close_closeup()
	closeup = node
	_closeup_name = target
	node.name = "Content"
	_closeup_layer.add_child(node)
	_closeup_layer.move_child(node, 0)  # under the header and hint text
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_closeup_title.text = "  " + title
	_closeup_hint_button.visible = hints
	_closeup_layer.visible = true
	_closeup_layer.scale = Vector2(0.92, 0.92)
	_closeup_layer.pivot_offset = frame_rect.size / 2.0
	var tween := create_tween()
	tween.tween_property(_closeup_layer, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)
	Audio.play("select")


func _on_closeup_done(target: String) -> void:
	var r := Adventure.interact(room_id, target, "done")
	close_closeup()
	if not r.is_empty():
		present(r)


func _on_code_entered(code: String, lock: LockDials) -> void:
	var r := Adventure.interact(room_id, lock.lock_id, "code", "", code)
	var result := str(r.get("result", ChainRules.WRONG))
	var destination := ""
	if result.begins_with(ChainRules.DECOY_PREFIX):
		destination = str(ChainRules.decoy(Adventure.chains.get(str(r.get("machine", "")), {}), result.trim_prefix(ChainRules.DECOY_PREFIX)).get("destination", ""))
	lock.show_result(result, destination)
	_dialogue.skip_all()
	if r.is_empty():
		Audio.play("deny")
		return
	present(r)
	if result == ChainRules.RIGHT:
		var tween := create_tween()
		tween.tween_interval(0.7)
		tween.tween_callback(func() -> void:
			if closeup == lock:
				close_closeup())


func _on_closeup_hint() -> void:
	var puzzle := closeup as PuzzleBase
	if puzzle == null:
		return
	Audio.play("menu")
	if puzzle.next_hint_level() >= HintLadder.MAX_LEVEL:
		_closeup_hint.text = "Reveal the answer? You will not get credit."
		_confirm_row.visible = true
	else:
		puzzle.request_hint()


func _on_hint_requested(level: int) -> void:
	var puzzle := closeup as PuzzleBase
	if level >= HintLadder.MAX_LEVEL:
		_closeup_hint.text = "Answer revealed. No credit this time."
	elif puzzle != null:
		_closeup_hint.text = puzzle.get_hint_text(level)


func _on_puzzle_solved(credited: bool, puzzle: PuzzleBase) -> void:
	var machine := puzzle.machine
	var part := puzzle.part
	var now_running := Adventure.record_solve(machine, part, credited)
	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_callback(func() -> void:
		close_closeup()
		_celebrate_merge(machine, part, credited, now_running))


func _lock_def(lock_id: String) -> Dictionary:
	for machine: String in Adventure.chains:
		var lock := ChainRules.lock_def(Adventure.chains[machine], lock_id)
		if not lock.is_empty():
			return lock
	return {}


func _overlay_rect(node_name: String, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.name = node_name
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r
