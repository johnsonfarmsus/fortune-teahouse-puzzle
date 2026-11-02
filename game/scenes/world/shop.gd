# SPDX-License-Identifier: AGPL-3.0-or-later
extends PlaceBase
## The gnu's shop. A tap on a machine hotspot opens its MachineView. Nothing
## here knows which machines exist: the scene's hotspots carry the ids.

@onready var _town_button: Button = $TownButton


func _ready() -> void:
	_town_button.pressed.connect(func() -> void: Router.go_to_place("town"))


func _on_hotspot_hit(hotspot: Hotspot) -> void:
	if hotspot.machine != "":
		Router.push(Paths.MACHINE_VIEW, {"machine": hotspot.machine})
