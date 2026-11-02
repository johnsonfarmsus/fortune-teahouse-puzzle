# SPDX-License-Identifier: AGPL-3.0-or-later
extends CanvasLayer
## The first screen. The first tap on "Tap to start" (released, since iOS unlocks audio on touchend) is the gesture browsers
## need before they allow sound.

signal started

@onready var _button: Button = $StartButton


func _ready() -> void:
	_button.pressed.connect(func() -> void: started.emit())
