# SPDX-License-Identifier: AGPL-3.0-or-later
class_name Hotspot
extends Area2D
## A tappable spot in a place. Hit-tested by the place with a point query (no
## physics picking). Walking places go to the Door marker before activating.

@export var place_id: String = ""
@export var machine: String = ""
@export var label_text: String = ""

@onready var _label: Label = $Label
@onready var _door: Marker2D = $Door


func _ready() -> void:
	_label.text = label_text
	add_to_group("hotspots")


func door_position() -> Vector2:
	return _door.global_position
