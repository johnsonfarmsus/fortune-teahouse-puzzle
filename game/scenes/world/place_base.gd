# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PlaceBase
extends Node2D
## Shared tap handling for places. A press is tested against hotspots with a
## point query at the mouse position (collide_with_areas), never physics
## picking. Subclasses decide what a hit or a miss does. Places also host the
## Gnu's tappable notes (StoryMarker) and open dialogue boxes.

const MARKER_FALLBACK := Vector2(20, 100)

var story_markers: Array[StoryMarker] = []


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


## One StoryMarker for each of the Gnu's pieces whose `where` is `place` or
## "<place>:<spot>". `positions` maps piece id to the marker's top-left corner;
## pieces without one are lined up along the top.
func add_story_markers(place: String, positions: Dictionary) -> void:
	var layer := Node2D.new()
	layer.name = "StoryMarkers"
	add_child(layer)
	var index := 0
	for piece: Dictionary in Story.notes_by("Gnu", place):
		var marker: StoryMarker = load(Paths.STORY_MARKER).instantiate()
		marker.configure(piece)
		marker.position = positions.get(piece["id"], MARKER_FALLBACK + Vector2(index * 80.0, 0.0))
		marker.note_pressed.connect(_on_note_pressed)
		layer.add_child(marker)
		story_markers.append(marker)
		index += 1
	Events.machine_running.connect(_on_machine_running)
	Events.crew_changed.connect(_on_machine_running)  # also fires on reset_device
	Story.flags_changed.connect(refresh_story_markers)


func _on_machine_running(_machine: String) -> void:
	refresh_story_markers()


func refresh_story_markers() -> void:
	for marker in story_markers:
		marker.refresh()


func _on_note_pressed(piece_id: String) -> void:
	Story.play(self, [Story.get_piece(piece_id)])
	refresh_story_markers()
