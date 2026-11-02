# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Root scene: the world, the Hud and the start screen.

@onready var world: Node2D = $World
@onready var hud: CanvasLayer = $Hud
@onready var start_screen: CanvasLayer = $StartScreen


func _ready() -> void:
	hud.visible = false
	Router.attach_world(world)
	start_screen.started.connect(_on_started, CONNECT_ONE_SHOT)


func _on_started() -> void:
	Audio.unlock()
	start_screen.queue_free()
	hud.visible = true
	Router.go_to_place("town")
	if GameState.crew == "" and GameState.collected_clue_ids.is_empty():
		Router.push(Paths.LUCKY_WORD_ENTRY)
