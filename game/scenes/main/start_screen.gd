# SPDX-License-Identifier: AGPL-3.0-or-later
extends CanvasLayer
## The first screen. The first press on "Tap to start" is the gesture browsers
## need before they allow sound.

signal started

@onready var _button: Button = $StartButton


func _ready() -> void:
	_button.button_down.connect(func() -> void: started.emit())
