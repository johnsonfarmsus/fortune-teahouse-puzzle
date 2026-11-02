# SPDX-License-Identifier: AGPL-3.0-or-later
class_name StraightenBench
extends CloseUpBase
## Penguin's bench up close: the bent cutter die with its dents marked. Tap a
## dent and the mallet comes down on it (clang, sparks); each dent takes two
## blows. When every dent is flat the die is straight and `done` fires.

const BENCH := Vector2(8, 196)
const DIE := Vector2(40, 164)
const DENTS: Array[Vector2] = [Vector2(6, -8), Vector2(30, 18), Vector2(54, -8), Vector2(78, 18)]
const BLOWS := 2

var hits: Array[int] = []
var finished := false

var _mallet_px := Vector2(120, 120)
var _mallet_angle := -0.6


func _ready() -> void:
	super()
	hits.clear()
	for d in DENTS:
		hits.append(0)
	label_at("Tap each bent tooth flat.", Vector2(8, 24), 160, 15)


func dents_left() -> int:
	var n := 0
	for h in hits:
		if h < BLOWS:
			n += 1
	return n


func dent_px(index: int) -> Vector2:
	return DIE + DENTS[index]


## One mallet blow on dent `index` (tests call this too).
func strike(index: int) -> void:
	if finished or index < 0 or index >= DENTS.size():
		return
	_swing_to(dent_px(index) + Vector2(8, 8))
	if hits[index] >= BLOWS:
		Audio.play("tap")
		return
	hits[index] += 1
	Audio.play("hammer", 1.0 + 0.1 * hits[index])
	sparks(dent_px(index) + Vector2(8, 12))
	queue_redraw()
	if dents_left() == 0:
		finished = true
		Audio.play("success")
		var tween := create_tween()
		tween.tween_interval(0.5)
		tween.tween_callback(func() -> void: done.emit())


func _swing_to(target_px: Vector2) -> void:
	_mallet_px = target_px + Vector2(4, -30)
	var tween := create_tween()
	tween.tween_method(_set_angle, -1.1, 0.25, 0.07)
	tween.tween_method(_set_angle, 0.25, -0.6, 0.15)


func _set_angle(a: float) -> void:
	_mallet_angle = a
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.13, 0.12))
	draw_asset("closeup.bench", BENCH)
	draw_asset("closeup.die" if finished else "closeup.die_bent", DIE)
	for i in DENTS.size():
		if hits[i] < BLOWS:
			var fade := 1.0 - 0.45 * hits[i]
			draw_asset("closeup.dent", dent_px(i), 0, Color(1, 1, 1, fade))
	var tex := assets.texture("closeup.mallet")
	var s := fit_scale()
	draw_set_transform(to_screen(_mallet_px + Vector2(16, 28)), _mallet_angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(Vector2(-16, -28) * s, Vector2(tex.get_size()) * s), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		var px := to_px(event.position)
		for i in DENTS.size():
			if Rect2(dent_px(i) - Vector2(4, 4), Vector2(24, 24)).has_point(px) and hits[i] < BLOWS:
				strike(i)
				return
		# A miss still swings, so every tap answers.
		_swing_to(px - Vector2(8, 8))
		Audio.play("tap")
