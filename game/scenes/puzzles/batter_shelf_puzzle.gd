# SPDX-License-Identifier: AGPL-3.0-or-later
extends PuzzleBase
## The batter-jar logic puzzle, hands on: drag the five jars from the counter
## onto the Cookie Machine's five-slot shelf. Same config as MatchingPuzzle
## ({machine, domain, answer, clues, total_clues, threshold}) and the same
## MatchingRules; no answers in this script. Jars tumble with a little
## gravity and bounce into the slot they are dropped on (a displaced jar
## tumbles back to the counter). With five jars up it checks itself: a right
## shelf glows and solves; a wrong one wobbles and says so, never how many are
## right. Drawn as pixel art on the 176x320 close-up grid.
##
## Test API: place(item, slot), clear_slot(slot), placement(), check(),
## drop_jar(item, at_px), simulate(seconds), settle(), is_settled().

const VIEW := Vector2(176, 320)
const JAR := Vector2(24, 32)
const SHELF_Y := 132.0
const SLOT_X0 := 13.0
const SLOT_GAP := 31.0
const COUNTER_Y := 272.0
const HOME_X0 := 10.0
const HOME_GAP := 32.0
const GRAVITY := 900.0
const BOUNCE := 0.35
const SNAP_PX := 18.0

## One jar's motion: position (top-left, art px), velocity, tilt.
class Jar:
	var item: String
	var pos: Vector2
	var vel: Vector2 = Vector2.ZERO
	var target: Vector2
	var tilt: float = 0.0
	var spin: float = 0.0
	var falling := false
	var bounces := 0


var assets: AssetLoader
var _domain: Dictionary = {}
var _answer: Dictionary = {}
var _clues: Array = []
var _total_clues := 6
var _threshold := 4
var _placement: Dictionary = {}  # item -> slot (1-based)
var _jars: Dictionary = {}  # item -> Jar
var _drag_item := ""
var _drag_offset := Vector2.ZERO
var _press_px := Vector2.ZERO
var _glow := 0.0
var _wobble := 0.0
var _solved := false
var _feedback: Label
var _status: Label
var _level_two_calls := 0
var _pending_check := false


func configure(config: Dictionary) -> void:
	_domain = config.get("domain", {})
	_answer = config.get("answer", {})
	_clues = config.get("clues", [])
	_total_clues = int(config.get("total_clues", 6))
	_threshold = int(config.get("threshold", Ids.CLUE_THRESHOLD))


func _ready() -> void:
	if assets == null:
		assets = AssetLoader.shared()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	var items: Array = _domain.get("items", [])
	for i in items.size():
		var jar := Jar.new()
		jar.item = str(items[i])
		jar.pos = _home(i)
		jar.target = jar.pos
		_jars[jar.item] = jar
	_status = _label(Vector2(6, 6), 164, 14)
	_feedback = _label(Vector2(6, 200), 164, 15)
	_refresh_text()


func _process(delta: float) -> void:
	var moving := false
	for jar: Jar in _jars.values():
		if jar.falling:
			moving = true
			_step(jar, delta)
	if _glow > 0.0:
		_glow = maxf(0.0, _glow - delta * 0.6)
		moving = true
	if _wobble > 0.0:
		_wobble = maxf(0.0, _wobble - delta * 2.5)
		moving = true
	if moving or _drag_item != "":
		queue_redraw()
	if _pending_check and is_settled():
		_pending_check = false
		if _placement.size() == _jars.size():
			check()


# --- Test API -----------------------------------------------------------------------


## Puts `item` in `slot` (1-based) at once. A jar already there goes back to the counter.
func place(item: String, slot: int) -> void:
	if not _jars.has(item) or slot < 1 or slot > _slot_count():
		return
	_put(item, slot)
	settle()


func clear_slot(slot: int) -> void:
	for item: String in _placement.keys():
		if int(_placement[item]) == slot:
			_placement.erase(item)
			_send_home(item)
	settle()


func placement() -> Dictionary:
	return _placement.duplicate()


## A drag released at `at_px` (art pixels): the jar tumbles to the slot under
## it, or back to the counter. Returns the slot, or 0.
func drop_jar(item: String, at_px: Vector2) -> int:
	if not _jars.has(item):
		return 0
	var jar: Jar = _jars[item]
	jar.pos = at_px - JAR / 2.0
	var slot := slot_at(at_px)
	if slot > 0:
		_put(item, slot)
		Audio.play("slot")
	else:
		_placement.erase(item)
		_send_home(item)
	_pending_check = true
	_refresh_text()
	return slot


## Runs the tumbling for `seconds` in 60 Hz steps, as frames would.
func simulate(seconds: float) -> void:
	for i in int(seconds * 60.0):
		_process(1.0 / 60.0)


func settle() -> void:
	for jar: Jar in _jars.values():
		jar.pos = jar.target
		jar.vel = Vector2.ZERO
		jar.tilt = 0.0
		jar.falling = false
	queue_redraw()


func is_settled() -> bool:
	for jar: Jar in _jars.values():
		if jar.falling:
			return false
	return _drag_item == ""


## Checks the shelf once five jars are up. Returns true and solves when right.
func check() -> bool:
	if _placement.size() < _jars.size() or _solved:
		return false
	if MatchingRules.is_solved(_placement, _answer):
		_solved = true
		_glow = 1.0
		_feedback.text = "That works! The hopper fills."
		Audio.play("success")
		finish()
		return true
	_wobble = 1.0
	_feedback.text = "Not quite. Read your clues again."
	Audio.play("wobble")
	return false


func slot_at(px: Vector2) -> int:
	for i in _slot_count():
		var x := _slot_px(i + 1).x
		if absf(px.x - (x + JAR.x / 2.0)) <= SNAP_PX and px.y < SHELF_Y + 24.0 and px.y > SHELF_Y - JAR.y - 60.0:
			return i + 1
	return 0


func jar_position(item: String) -> Vector2:
	return (_jars[item] as Jar).pos if _jars.has(item) else Vector2.ZERO


# --- PuzzleBase ---------------------------------------------------------------------


func can_reveal() -> bool:
	return _clues.size() >= _threshold


func get_hint_text(level: int) -> String:
	if _clues.is_empty():
		return "You have no clues yet. Find your crewmates and enter their lucky words at the Teahouse."
	if level == 1:
		var chosen: Dictionary = _clues[0]
		for clue: Dictionary in _clues:
			if clue["fact"]["kind"] == "position":
				chosen = clue
				break
		return "Start with your %s clue." % str(Ids.STYLE_LABELS.get(chosen["style"], chosen["style"])).to_lower()
	var broken: Array = []
	for style in Ids.HINT_STYLE_ORDER:
		for clue: Dictionary in _clues:
			if clue["style"] == style and not MatchingRules.fact_holds(clue["fact"], _placement):
				broken.append(clue)
	if broken.is_empty():
		return "All your clues fit so far. Keep going."
	var clue: Dictionary = broken[_level_two_calls % broken.size()]
	_level_two_calls += 1
	return "A clue says: %s" % MatchingRules.fact_to_text(clue["fact"], _domain)


func reveal() -> void:
	for item: String in _answer:
		_put(item, int(_answer[item]))
	settle()


# --- Internals ----------------------------------------------------------------------


func _put(item: String, slot: int) -> void:
	for other: String in _placement.keys():
		if int(_placement[other]) == slot and other != item:
			_placement.erase(other)
			_send_home(other)
	_placement[item] = slot
	var jar: Jar = _jars[item]
	jar.target = _slot_px(slot)
	_fall(jar)
	_feedback.text = ""
	_refresh_text()


func _send_home(item: String) -> void:
	var jar: Jar = _jars[item]
	jar.target = _home(_index_of(item))
	_fall(jar)


func _fall(jar: Jar) -> void:
	jar.falling = true
	jar.bounces = 0
	jar.vel = Vector2(0, minf(jar.vel.y, 0.0))
	jar.spin = randf_range(-3.0, 3.0)


## Gravity down to the target height, a bounce or two, sliding over sideways.
func _step(jar: Jar, delta: float) -> void:
	jar.pos.x = lerpf(jar.pos.x, jar.target.x, minf(1.0, delta * 12.0))
	jar.vel.y += GRAVITY * delta
	jar.pos.y += jar.vel.y * delta
	jar.tilt += jar.spin * delta
	jar.spin *= 0.9
	if jar.pos.y >= jar.target.y:
		jar.pos.y = jar.target.y
		if absf(jar.vel.y) > 60.0 and jar.bounces < 3:
			Audio.play("jar_drop" if jar.bounces == 0 else "jar_clink")
			jar.vel.y = -jar.vel.y * BOUNCE
			jar.spin = -jar.tilt * 6.0
			jar.bounces += 1
		else:
			jar.vel = Vector2.ZERO
			jar.tilt = 0.0
			if absf(jar.pos.x - jar.target.x) < 0.5:
				jar.pos = jar.target
				jar.falling = false


func _slot_count() -> int:
	return (_domain.get("positions", []) as Array).size()


func _slot_px(slot: int) -> Vector2:
	return Vector2(SLOT_X0 + (slot - 1) * SLOT_GAP, SHELF_Y - JAR.y)


func _home(index: int) -> Vector2:
	return Vector2(HOME_X0 + index * HOME_GAP, COUNTER_Y - JAR.y)


func _index_of(item: String) -> int:
	return (_domain.get("items", []) as Array).find(item)


func _item_name(item: String) -> String:
	return str(_domain.get("item_names", {}).get(item, item))


func _px_scale() -> float:
	return maxf(1.0, size.x / VIEW.x) if size.x > 0.0 else 2.0


func _label(at: Vector2, width: float, font_size: int) -> Label:
	var l := UiKit.label("", font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.12))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("px", at)
	l.set_meta("w", width)
	add_child(l)
	return l


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		for child in get_children():
			if child is Label and child.has_meta("px"):
				(child as Label).position = child.get_meta("px") * _px_scale()
				(child as Label).size = Vector2(float(child.get_meta("w")) * _px_scale(), 0)
		queue_redraw()


func _refresh_text() -> void:
	if _status == null:
		return
	if _clues.is_empty():
		_status.text = "Drag the jars onto the shelf. Your crew's fortunes say which goes where: find them and enter their lucky words at the Teahouse."
	else:
		_status.text = "Drag each jar onto its place on the shelf. Clues: %d of %d (%d needed)." % [_clues.size(), _total_clues, _threshold]


func _draw() -> void:
	var s := _px_scale()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.17, 0.13, 0.12))
	# The shelf with its numbered places, wobbling after a wrong check.
	var wob := sin(_wobble * 30.0) * 2.0 * _wobble
	var shelf_tex := assets.texture("closeup.shelf")
	draw_texture_rect(shelf_tex, Rect2(Vector2(8 + wob, SHELF_Y) * s, Vector2(shelf_tex.get_size()) * s), false)
	var font := ThemeDB.fallback_font
	var positions: Array = _domain.get("positions", [])
	for i in _slot_count():
		var at := _slot_px(i + 1)
		draw_rect(Rect2(Vector2(at.x - 1, at.y + 4) * s, Vector2(JAR.x + 2, JAR.y - 4) * s), Color(1, 1, 1, 0.06))
		var label := str(positions[i]) if i < positions.size() else str(i + 1)
		draw_string(font, Vector2(at.x * s, (SHELF_Y + 24) * s), label, HORIZONTAL_ALIGNMENT_CENTER, JAR.x * s, int(6 * s), Color(0.95, 0.88, 0.7))
	var counter := assets.texture("closeup.counter")
	draw_texture_rect(counter, Rect2(Vector2(0, COUNTER_Y) * s, Vector2(counter.get_size()) * s), false)
	# Jars; the dragged one last, on top.
	var order: Array = _jars.keys()
	if _drag_item != "":
		order.erase(_drag_item)
		order.append(_drag_item)
	for item: String in order:
		var jar: Jar = _jars[item]
		var tex := assets.texture("closeup.jar." + item)
		var glow := Color(1, 1, 1).lerp(Color(1.6, 1.5, 0.9), _glow)
		var lift := 1.08 if item == _drag_item else 1.0
		var x := jar.pos.x + (wob if _placement.has(item) else 0.0)
		var centre := Vector2(x, jar.pos.y) * s + JAR * s / 2.0
		draw_set_transform(centre, jar.tilt * 0.08, Vector2(lift, lift))
		draw_texture_rect(tex, Rect2(-JAR * s / 2.0, JAR * s), false, glow)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if not _placement.has(item) or item == _drag_item:
			draw_string(font, Vector2(x * s - 4 * s, (jar.pos.y + JAR.y + 9) * s), _item_name(item), HORIZONTAL_ALIGNMENT_CENTER, (JAR.x + 8) * s, int(5 * s), Color(0.98, 0.95, 0.85))


func _gui_input(event: InputEvent) -> void:
	var s := _px_scale()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		var px: Vector2 = event.position / s
		if event.pressed:
			var item := _jar_at(px)
			if item == "" or _solved:
				Audio.play("tap")
				return
			_drag_item = item
			_press_px = px
			var jar: Jar = _jars[item]
			jar.falling = false
			_drag_offset = jar.pos - px
			Audio.play("drag_start")
		elif _drag_item != "":
			var item := _drag_item
			_drag_item = ""
			if px.distance_to(_press_px) < 4.0 and _placement.has(item):
				# A tap on a jar on the shelf takes it back down.
				_placement.erase(item)
				_send_home(item)
				Audio.play("drop")
				_refresh_text()
			else:
				drop_jar(item, px + _drag_offset + JAR / 2.0)
	elif event is InputEventMouseMotion and _drag_item != "":
		accept_event()
		var jar: Jar = _jars[_drag_item]
		jar.pos = event.position / s + _drag_offset
		queue_redraw()


func _jar_at(px: Vector2) -> String:
	var hit := ""
	for item: String in _jars:
		var jar: Jar = _jars[item]
		if Rect2(jar.pos - Vector2(3, 3), JAR + Vector2(6, 6)).has_point(px):
			hit = item
	return hit
