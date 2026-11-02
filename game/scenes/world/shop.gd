# SPDX-License-Identifier: AGPL-3.0-or-later
extends PlaceBase
## The gnu's shop. A tap on a machine hotspot opens its MachineView. Nothing
## here knows which machines exist: the scene's hotspots carry the ids. The
## Gnu's notes for the shop (data `where` = "shop") sit along the bottom edge.

## Top-left corners (390x844) of the Gnu's notes, by piece id.
const NOTE_POSITIONS := {
	"gnu.town.shop_counter": Vector2(160, 786),
	"gnu.town.answering_machine": Vector2(250, 786),
}

@onready var _town_button: Button = $TownButton


func _ready() -> void:
	_town_button.pressed.connect(func() -> void: Router.go_to_place("town"))
	$LineButton.pressed.connect(func() -> void: Router.push(Paths.FINALE_VIEW))
	add_story_markers("shop", NOTE_POSITIONS)


func _on_hotspot_hit(hotspot: Hotspot) -> void:
	if hotspot.machine != "":
		Router.push(Paths.MACHINE_VIEW, {"machine": hotspot.machine})
