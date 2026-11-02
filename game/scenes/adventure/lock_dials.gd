# SPDX-License-Identifier: AGPL-3.0-or-later
class_name LockDials
extends CloseUpBase
## A code lock up close: turn each dial (tap its top half to go up, its bottom
## half to go down, or drag it), then pull the handle. The code goes to the
## chain through `code_entered`; show_result() plays what happened: the door
## swings open, the screen flashes a forwarding notice, or it buzzes.
## The symbols and digit count come from the lock's data; no code lives here.

signal code_entered(code: String)
signal label_pressed

const DOOR := Vector2(24, 40)
const DIAL_Y := 104.0
const DIAL_GAP := 28.0
const HANDLE := Vector2(56, 168)
const LABEL := Vector2(116, 52)
const DRAG_STEP_PX := 7.0

var lock_id: String = ""
var symbols: Array[String] = ["1", "2", "3", "4", "5"]
var digits: int = 3
var values: Array[int] = []
var opened := false

var _display: Label
var _drag_dial := -1
var _drag_y := 0.0
var _did_drag := false
var _handle_offset := 0.0
var _door_open := 0.0
var _roll: Array[float] = []


func configure(p_lock_id: String, lock: Dictionary) -> void:
	lock_id = p_lock_id
	digits = int(lock.get("digits", 3))
	symbols.clear()
	for s: Variant in lock.get("symbols", ["1", "2", "3", "4", "5"]):
		symbols.append(str(s))
	values.clear()
	_roll.clear()
	for i in digits:
		values.append(0)
		_roll.append(0.0)


func _ready() -> void:
	super()
	if values.is_empty():
		configure(lock_id, {})
	_display = label_at("ENTER CODE", Vector2(32, 64), 112, 15, Color(0.6, 1.0, 0.7))


func code() -> String:
	var out := ""
	for v in values:
		out += symbols[v]
	return out


## Turns dial `index` by `steps` (wrapping round).
func turn(index: int, steps: int) -> void:
	if opened or index < 0 or index >= digits:
		return
	values[index] = posmod(values[index] + steps, symbols.size())
	_roll[index] = -4.0 * signf(steps)
	Audio.play("dial")
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		_roll[index] = v
		queue_redraw(), _roll[index], 0.0, 0.08)
	queue_redraw()


func set_code(text: String) -> void:
	for i in mini(text.length(), digits):
		values[i] = maxi(0, symbols.find(text[i]))
	queue_redraw()


## Pulls the handle: the code goes to the chain.
func pull() -> void:
	if opened:
		return
	Audio.play("click")
	var tween := create_tween()
	tween.tween_method(_set_handle, 0.0, 6.0, 0.06)
	tween.tween_method(_set_handle, 6.0, 0.0, 0.12)
	code_entered.emit(code())


## What the chain decided: "right", "wrong" or "decoy:<id>" (with the decoy's
## destination, from the chain data, for the forwarding notice).
func show_result(result: String, destination: String = "") -> void:
	if result == ChainRules.RIGHT:
		opened = true
		_display.text = "OPEN"
		var tween := create_tween()
		tween.tween_method(func(v: float) -> void:
			_door_open = v
			queue_redraw(), 0.0, 1.0, 0.35)
		sparks(DOOR + Vector2(64, 80))
	elif result.begins_with(ChainRules.DECOY_PREFIX):
		_display.text = "CODE CHANGED\nFORWARDED: %s" % destination.to_upper()
		_display.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
		var flash := create_tween()
		flash.tween_property(self, "modulate", Color(1.5, 0.6, 0.6), 0.08)
		flash.tween_property(self, "modulate", Color.WHITE, 0.3)
		shake_self(2)
	else:
		_display.text = "NOPE"
		_display.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
		shake_self(2)


func _set_handle(v: float) -> void:
	_handle_offset = v
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.11, 0.16))
	draw_asset("closeup.locker", DOOR, 0, Color.WHITE)
	if _door_open > 0.0:
		var inner := Rect2(to_screen(DOOR + Vector2(8, 8)), Vector2(112, 144) * fit_scale() * Vector2(_door_open, 1))
		draw_rect(inner, Color(0.08, 0.06, 0.09))
	draw_rect(Rect2(to_screen(Vector2(32, 60)), Vector2(112, 30) * fit_scale()), Color(0.05, 0.12, 0.08))
	for i in digits:
		var at := _dial_px(i) + Vector2(0, _roll[i] if i < _roll.size() else 0.0)
		draw_asset("closeup.dial", at, values[i] if i < values.size() else 0)
		# Up and down marks on each dial.
		var c := to_screen(_dial_px(i) + Vector2(8, -4))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 2) * fit_scale() / 2, c + Vector2(4, 2) * fit_scale() / 2, c + Vector2(0, -2) * fit_scale() / 2]), Color(0.9, 0.85, 0.7))
		var d := to_screen(_dial_px(i) + Vector2(8, 28))
		draw_colored_polygon(PackedVector2Array([d + Vector2(-4, -2) * fit_scale() / 2, d + Vector2(4, -2) * fit_scale() / 2, d + Vector2(0, 2) * fit_scale() / 2]), Color(0.9, 0.85, 0.7))
	draw_asset("closeup.handle", HANDLE + Vector2(0, _handle_offset))
	draw_asset("prop.sticky", LABEL, 0, Color.WHITE, 2.0)


func _dial_px(index: int) -> Vector2:
	var total := (digits - 1) * DIAL_GAP + 16
	return Vector2((VIEW.x - total) / 2.0 + index * DIAL_GAP, DIAL_Y)


func dial_at(px: Vector2) -> int:
	for i in digits:
		if Rect2(_dial_px(i) - Vector2(4, 8), Vector2(24, 40)).has_point(px):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var px := to_px(event.position)
		if event.pressed:
			accept_event()
			var dial := dial_at(px)
			if dial >= 0:
				_drag_dial = dial
				_drag_y = px.y
				_did_drag = false
				return
			if Rect2(HANDLE - Vector2(4, 4), Vector2(72, 28)).has_point(px):
				pull()
				return
			if Rect2(LABEL, Vector2(32, 32)).has_point(px):
				Audio.play("paper")
				label_pressed.emit()
				return
			Audio.play("tap")
		elif _drag_dial >= 0:
			# A press and release in place is a tap: top half up, bottom half down.
			if not _did_drag:
				turn(_drag_dial, 1 if px.y < _dial_px(_drag_dial).y + 12 else -1)
			_drag_dial = -1
			accept_event()
	elif event is InputEventMouseMotion and _drag_dial >= 0:
		var px := to_px(event.position)
		var moved := px.y - _drag_y
		if absf(moved) >= DRAG_STEP_PX:
			turn(_drag_dial, -1 if moved > 0 else 1)
			_drag_y = px.y
			_did_drag = true
		accept_event()
