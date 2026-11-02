# SPDX-License-Identifier: AGPL-3.0-or-later
class_name CookieMachineRig
extends Node2D
## The Cookie Machine as a contraption in the shop. Each of its six parts
## starts moving once the crew has fixed it (Progress): the jars fill the
## hopper shelf (logic), the mixer paddle turns (wiring), the panel blinks
## through its steps (sequence), the gnu's note glows (word), the cutter stamps
## rounds onto the belt (rhythm, the cutter-die chain) and Penguin's lamp
## lights (helper). All six running sends finished cookies along the belt. A
## part fixed since this phone last saw the shop gets its moment: sparks, a
## shake, a jingle and a caption (part_celebrated).
## Layout is in local pixels; the shop's hotspots in data/rooms.json match it.

signal part_celebrated(part: String, caption_id: String)

const SIZE := Vector2(144, 64)
const JAR_ITEMS: Array[String] = ["sugar", "flour", "butter", "vanilla", "egg"]
const PART_CENTERS := {
	"logic": Vector2(24, 12), "wiring": Vector2(64, 24), "word": Vector2(88, 8),
	"rhythm": Vector2(112, 20), "helper": Vector2(136, 8), "sequence": Vector2(24, 48),
}
const STAMP_SECONDS := 0.9
const BELT_SPEED := 18.0

var machine: String = "cookie_machine"
var assets: AssetLoader
var room: Node2D
var fixed: Dictionary = {}  # part -> bool
var rounds: Array[Sprite2D] = []

var _body: Sprite2D
var _jars: Array[Sprite2D] = []
var _paddle: Sprite2D
var _note: AnimatedSprite2D
var _press: Sprite2D
var _die: Sprite2D
var _lamp: AnimatedSprite2D
var _panel: AnimatedSprite2D
var _belt: Array[AnimatedSprite2D] = []
var _stamp_clock := 0.0
var _blink_clock := 0.0
var _pending: Array[String] = []


func setup(p_machine: String, p_assets: AssetLoader, p_room: Node2D) -> void:
	machine = p_machine
	assets = p_assets
	room = p_room


func _ready() -> void:
	_body = _sprite("machine.cookie.body", Vector2.ZERO)
	var shelf := _sprite("machine.cookie.shelf", Vector2(0, 16))
	shelf.name = "Shelf"
	for i in JAR_ITEMS.size():
		var jar := _sprite("machine.cookie.jar." + JAR_ITEMS[i], Vector2(3 + i * 9, 4))
		_jars.append(jar)
	_sprite("machine.cookie.bowl", Vector2(48, 24))
	_paddle = _sprite("machine.cookie.paddle", Vector2(64, 26), true)
	_paddle.name = "Paddle"
	_note = _anim("machine.cookie.note", Vector2(80, 0))
	_sprite("machine.cookie.die_slot", Vector2(96, 30))
	_die = _sprite("item.cutter_die", Vector2(104, 22))
	_die.scale = Vector2(1, 0.5)
	_press = _sprite("machine.cookie.press", Vector2(96, 4))
	_press.name = "Press"
	_lamp = _anim("machine.cookie.lamp", Vector2(128, 0))
	_panel = _anim("machine.cookie.panel", Vector2(8, 40))
	for i in 9:
		_belt.append(_anim("machine.cookie.belt", Vector2(i * 16, 56)))
	Events.part_fixed.connect(_on_part_fixed)
	Events.progress_changed.connect(func(m: String) -> void:
		if m == machine:
			refresh())
	refresh()
	for part in Ids.PARTS:
		if is_fixed(part) and str(GameState.player.story_state.get(_key(part), "")) != "fixed":
			_pending.append(part)


func _process(delta: float) -> void:
	if is_fixed("wiring"):
		_paddle.rotation += delta * 5.0
	_blink_clock += delta
	if _blink_clock > 0.35:
		_blink_clock = 0.0
		if is_fixed("sequence"):
			_panel.frame = 1 - _panel.frame
		if is_fixed("helper"):
			_lamp.modulate = Color(1, 1, 1) if _lamp.modulate.r < 1.0 else Color(1.25, 1.25, 1.1)
	if is_fixed("rhythm"):
		_stamp_clock += delta
		if _stamp_clock >= STAMP_SECONDS:
			_stamp_clock = 0.0
			stamp()
		for seg in _belt:
			seg.speed_scale = 1.0
	for r in rounds.duplicate():
		r.position.x += BELT_SPEED * delta
		if r.position.x > SIZE.x:
			rounds.erase(r)
			r.queue_free()
	var allowed: bool = room == null or bool(room.get("celebrations_allowed"))
	if not _pending.is_empty() and allowed and Router.depth() == 0 and is_visible_in_tree():
		celebrate(_pending.pop_front())


func is_fixed(part: String) -> bool:
	return bool(fixed.get(part, false))


func is_running() -> bool:
	for part in Ids.PARTS:
		if not is_fixed(part):
			return false
	return true


## Reads the crew's progress and sets every part's look.
func refresh() -> void:
	var progress := Progress.store.get_crew_progress(machine)
	for part in Ids.PARTS:
		fixed[part] = int(progress.get(part, 0)) > 0
	for jar in _jars:
		jar.visible = is_fixed("logic")
	_note.frame = 1 if is_fixed("word") else 0
	_lamp.frame = 1 if is_fixed("helper") else 0
	_panel.frame = 1 if is_fixed("sequence") else 0
	_die.visible = is_fixed("rhythm")
	for seg in _belt:
		if is_fixed("rhythm"):
			seg.play()
		else:
			seg.stop()
	for part in Ids.PARTS:
		var dim := Color(0.62, 0.6, 0.66) if not is_fixed(part) else Color.WHITE
		match part:
			"wiring":
				_paddle.modulate = dim
			"rhythm":
				_press.modulate = dim


## One stroke of the press: a fresh round lands on the belt at once (state
## never waits on an animation or the frame rate), and the press head comes
## down and up over it.
func stamp() -> void:
	var r := _sprite("machine.cookie.cookie" if is_running() else "machine.cookie.round", Vector2(108, 52))
	r.z_index = 2
	rounds.append(r)
	if Router.depth() == 0 and is_visible_in_tree():
		Audio.play("stamp")
	var tween := create_tween()
	tween.tween_property(_press, "position:y", 16.0, 0.08)
	tween.tween_property(_press, "position:y", 4.0, 0.2)


## The moment a part starts working (once per part on this phone).
func celebrate(part: String) -> void:
	GameState.set_story_state(_key(part), "fixed")
	refresh()
	Audio.play("part_fixed")
	if room != null and room.has_method("burst"):
		room.call("burst", position + PART_CENTERS.get(part, SIZE / 2))
		room.call("shake", 2.0, 0.35)
	var caption := "narrator.fixed.%s.%s" % [machine, part]
	if is_running():
		caption = "narrator.fixed.%s.all" % machine
	part_celebrated.emit(part, caption)


func pending() -> Array[String]:
	return _pending


func _on_part_fixed(m: String, part: String) -> void:
	if m != machine:
		return
	refresh()
	if not _pending.has(part):
		_pending.append(part)


func _key(part: String) -> String:
	return "rig:%s/%s" % [machine, part]


func _sprite(asset: String, at: Vector2, centered: bool = false) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = assets.texture(asset)
	s.centered = centered
	s.position = at
	add_child(s)
	return s


func _anim(asset: String, at: Vector2) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = assets.frames(asset)
	s.centered = false
	s.position = at
	s.speed_scale = 1.0
	add_child(s)
	s.stop()
	return s
