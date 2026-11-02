# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PlaceBase
extends Node2D
## Shared tap handling for places. A press is tested against hotspots with a
## point query at the mouse position (collide_with_areas), never physics
## picking. Subclasses decide what a hit or a miss does.


func _unhandled_input(event: InputEvent) -> void:
	# Touches arrive as emulated mouse buttons, so only mouse events are handled.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()


## Handles a tap at a world position. Returns the hotspot hit, or null.
func tap_at(point: Vector2) -> Hotspot:
	var hit := hotspot_at(point)
	if hit != null:
		_on_hotspot_hit(hit)
	else:
		_on_miss(point)
	return hit


func hotspot_at(point: Vector2) -> Hotspot:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result in get_world_2d().direct_space_state.intersect_point(query):
		var collider: Object = result["collider"]
		if collider is Hotspot:
			return collider
	return null


func _on_hotspot_hit(_hotspot: Hotspot) -> void:
	pass


func _on_miss(_point: Vector2) -> void:
	pass
