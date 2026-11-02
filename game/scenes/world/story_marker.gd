# SPDX-License-Identifier: AGPL-3.0-or-later
class_name StoryMarker
extends Button
## A small tappable "Note" in the Town or Shop for one story piece. An unread
## note reads "! Note" and is tinted amber; a read one reads "Note" and is
## grey, so colour never carries the meaning alone. Notes that wait on a
## trigger (the answering machine, the finale) stay hidden until it holds.

signal note_pressed(piece_id: String)

const SIZE := Vector2(76, 44)
const UNREAD := Color(1.0, 0.85, 0.4)
const READ := Color(0.75, 0.75, 0.75)

var piece_id: String = ""
var trigger: String = "first_visit"


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	focus_mode = Control.FOCUS_NONE
	pressed.connect(func() -> void: note_pressed.emit(piece_id))
	refresh()


func configure(piece: Dictionary) -> void:
	piece_id = str(piece["id"])
	trigger = str(piece["when"])
	name = "Note_" + piece_id.replace(".", "_")
	if is_node_ready():
		refresh()


## Updates the text, tint and whether the note is there at all.
func refresh() -> void:
	var read := Story.is_seen(piece_id)
	text = "Note" if read else "! Note"
	modulate = READ if read else UNREAD
	visible = Story.trigger_active(trigger)
