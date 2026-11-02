# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Places (the world) and a stack of full-screen screens above it.

signal stack_changed(depth: int)

var _world: Node
var _place: Node
var _screens: CanvasLayer
var _stack: Array[ScreenBase] = []


func _ready() -> void:
	_screens = CanvasLayer.new()
	_screens.name = "Screens"
	_screens.layer = 10
	add_child(_screens)


func attach_world(world: Node) -> void:
	_world = world
	_place = null


## Frees the old place and shows the new one. Ids come from Paths.PLACES.
func go_to_place(id: String) -> void:
	if _world == null or not Paths.PLACES.has(id):
		return
	if _place != null and is_instance_valid(_place):
		_place.get_parent().remove_child(_place)
		_place.queue_free()
	var scene: PackedScene = load(Paths.PLACES[id])
	_place = scene.instantiate()
	_world.add_child(_place)


func current_place() -> Node:
	return _place if _place != null and is_instance_valid(_place) else null


func push(path: String, args: Dictionary = {}) -> ScreenBase:
	var scene: PackedScene = load(path)
	var screen := scene.instantiate() as ScreenBase
	screen.setup(args)
	_screens.add_child(screen)
	_stack.append(screen)
	stack_changed.emit(_stack.size())
	return screen


func pop() -> void:
	if _stack.is_empty():
		return
	_remove_top()
	stack_changed.emit(_stack.size())


func replace_top(path: String, args: Dictionary = {}) -> ScreenBase:
	if not _stack.is_empty():
		_remove_top()
	return push(path, args)


func clear() -> void:
	while not _stack.is_empty():
		_remove_top()
	stack_changed.emit(0)


func top() -> ScreenBase:
	return _stack.back() if not _stack.is_empty() else null


func depth() -> int:
	return _stack.size()


func _remove_top() -> void:
	var screen: ScreenBase = _stack.pop_back()
	if is_instance_valid(screen):
		if screen.get_parent() != null:
			screen.get_parent().remove_child(screen)
		screen.queue_free()
