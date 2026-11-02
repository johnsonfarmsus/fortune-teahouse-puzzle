# SPDX-License-Identifier: AGPL-3.0-or-later
extends CanvasLayer
## The first screen, and the loading screen: it shows the tagline and one tip
## from the story data. The first press on "Tap to start" (released, since iOS
## unlocks audio on touchend) is the gesture browsers need before they allow sound.
## If loading the puzzle and story data was slow, the button waits until the tip
## has been on screen for MIN_TIP_SECONDS; otherwise there is no wait at all.

signal started

const START_TEXT := "Tap to start"
const SLOW_LOAD_MSEC := 400
const MIN_TIP_SECONDS := 1.5

## How long loading took, in ms. Left at -1 it is read from PuzzleData and Story.
var load_msec: int = -1

@onready var _button: Button = $StartButton
@onready var _tagline: Label = $Tagline
@onready var _tip: Label = $Tip


func _ready() -> void:
	# Build the sound effects in the background while the player reads this.
	Audio.prewarm()
	_button.pressed.connect(func() -> void: started.emit())
	_tagline.text = str(Story.pick("start_screen", "always").get("text", ""))
	var tip := Story.pick("loading", "always")
	_tip.text = str(tip.get("text", ""))
	var took := load_msec if load_msec >= 0 else PuzzleData.load_msec + Story.load_msec
	if took >= SLOW_LOAD_MSEC and tip.size() > 0:
		_button.disabled = true
		_button.text = "Loading..."
		var hold := Timer.new()
		hold.one_shot = true
		hold.timeout.connect(_release_button)
		add_child(hold)
		hold.start(MIN_TIP_SECONDS)


func _release_button() -> void:
	_button.disabled = false
	_button.text = START_TEXT
