# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Root scene: the start screen, then the adventure layer (AdventureView, the
## default) or, with the debug setting fortune/debug_legacy_screens (or the
## Settings toggle), the old Town, Shop and Hud screens.

@onready var world: Node2D = $World
@onready var hud: CanvasLayer = $Hud
@onready var start_screen: CanvasLayer = $StartScreen

var adventure: AdventureView
var legacy: bool = false


func _ready() -> void:
	hud.visible = false
	Router.attach_world(world)
	legacy = DebugSettings.legacy_screens()
	if Audio.unlocked:
		# Coming back from the Settings toggle: no second tap needed.
		start_screen.queue_free()
		_begin.call_deferred()
		return
	start_screen.started.connect(_on_started, CONNECT_ONE_SHOT)


func _on_started() -> void:
	Audio.unlock()
	start_screen.queue_free()
	_begin()


func _begin() -> void:
	if legacy:
		hud.visible = true
		Router.go_to_place("town")
	else:
		var layer := CanvasLayer.new()
		layer.name = "AdventureLayer"
		layer.layer = 1
		add_child(layer)
		adventure = load(Paths.ADVENTURE_VIEW).instantiate()
		layer.add_child(adventure)
	if GameState.crew == "" and GameState.collected_clue_ids.is_empty():
		Router.push(Paths.LUCKY_WORD_ENTRY)
