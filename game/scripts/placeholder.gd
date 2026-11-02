# SPDX-License-Identifier: AGPL-3.0-or-later
extends Control
## Placeholder start screen. The real tap-to-start screen (audio unlock) arrives with WP3.

signal started

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		started.emit()
	elif event is InputEventScreenTouch and event.pressed:
		started.emit()
