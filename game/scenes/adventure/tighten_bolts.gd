# SPDX-License-Identifier: AGPL-3.0-or-later
class_name TightenBolts
extends CloseUpBase
## The cutter up close with the die seated: Penguin's spanner turns each of
## the four bolts a quarter at a time (tap a bolt, or drag the spanner across
## it). Three quarters makes a bolt tight; four tight bolts and `done` fires.

const CUTTER := Vector2(24, 120)
const DIE := Vector2(40, 136)
const BOLTS: Array[Vector2] = [Vector2(28, 124), Vector2(132, 124), Vector2(28, 164), Vector2(132, 164)]
const TURNS := 3

var turns: Array[int] = []
var finished := false

var _spanner_px := Vector2(64, 220)
var _spanner_angle := 0.0
var _dragging := false
var _last_bolt := -1


func _ready() -> void:
	super()
	turns.clear()
	for b in BOLTS:
		turns.append(0)
	label_at("Turn each bolt with the spanner.", Vector2(8, 24), 160, 15)


func loose_bolts() -> int:
	var n := 0
	for t in turns:
		if t < TURNS:
			n += 1
	return n


## A quarter turn on bolt `index` (tests call this too).
func turn_bolt(index: int) -> void:
	if finished or index < 0 or index >= BOLTS.size():
		return
	_spanner_px = BOLTS[index] + Vector2(-16, 4)
	if turns[index] >= TURNS:
		Audio.play("tap")
		queue_redraw()
		return
	turns[index] += 1
	_spanner_angle += PI / 2.0
	Audio.play("bolt", 1.0 + 0.15 * turns[index])
	if turns[index] == TURNS:
		sparks(BOLTS[index] + Vector2(8, 8), Color(0.8, 0.95, 1.0))
		Audio.play("click")
	queue_redraw()
	if loose_bolts() == 0:
		finished = true
		Audio.play("clunk")
		var tween := create_tween()
		tween.tween_interval(0.45)
		tween.tween_callback(func() -> void: done.emit())


func bolt_at(px: Vector2) -> int:
	for i in BOLTS.size():
		if Rect2(BOLTS[i] - Vector2(6, 6), Vector2(28, 28)).has_point(px):
			return i
	return -1


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.13, 0.16))
	draw_asset("closeup.cutter", CUTTER)
	draw_asset("closeup.die", DIE)
	for i in BOLTS.size():
		var tight := turns[i] >= TURNS
		draw_asset("closeup.bolt", BOLTS[i], turns[i], Color(0.75, 1.0, 0.8) if tight else Color.WHITE)
	var tex := assets.texture("closeup.spanner")
	var s := fit_scale()
	draw_set_transform(to_screen(_spanner_px + Vector2(24, 8)), _spanner_angle * 0.15, Vector2.ONE)
	draw_texture_rect(tex, Rect2(Vector2(-24, -8) * s, Vector2(tex.get_size()) * s), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if event.pressed:
			var px := to_px(event.position)
			var bolt := bolt_at(px)
			_dragging = true
			_last_bolt = bolt
			if bolt >= 0:
				turn_bolt(bolt)
			else:
				_spanner_px = px - Vector2(24, 8)
				Audio.play("tap")
				queue_redraw()
		else:
			_dragging = false
			_last_bolt = -1
	elif event is InputEventMouseMotion and _dragging:
		accept_event()
		var px := to_px(event.position)
		_spanner_px = px - Vector2(24, 8)
		var bolt := bolt_at(px)
		if bolt >= 0 and bolt != _last_bolt:
			turn_bolt(bolt)
		_last_bolt = bolt
		queue_redraw()
