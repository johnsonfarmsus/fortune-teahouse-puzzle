# SPDX-License-Identifier: AGPL-3.0-or-later
extends PlaceBase
## The town: tap to walk. Shop opens the Shop place, the Teahouse (Red Panda)
## opens lucky-word entry, the Pier (Crab) opens the contributors list.

const WALK_RECT := Rect2(20, 90, 350, 700)
const SPEED := 320.0

@onready var avatar: ColorRect = $Avatar

var _tween: Tween


func _on_hotspot_hit(hotspot: Hotspot) -> void:
	walk_to(hotspot.door_position(), func() -> void: activate(hotspot))


func _on_miss(point: Vector2) -> void:
	walk_to(point)


func walk_to(point: Vector2, then: Callable = Callable()) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var target := Vector2(
		clampf(point.x, WALK_RECT.position.x, WALK_RECT.end.x),
		clampf(point.y, WALK_RECT.position.y, WALK_RECT.end.y)
	)
	var top_left := target - avatar.size / 2.0
	var distance := avatar.position.distance_to(top_left)
	_tween = create_tween()
	_tween.tween_property(avatar, "position", top_left, distance / SPEED)
	if then.is_valid():
		_tween.tween_callback(then)


func activate(hotspot: Hotspot) -> void:
	if Paths.PLACES.has(hotspot.place_id):
		Router.go_to_place(hotspot.place_id)
	elif hotspot.place_id == "teahouse":
		Router.push(Paths.LUCKY_WORD_ENTRY)
	elif hotspot.place_id == "pier":
		Router.push(Paths.CONTRIBUTORS)
