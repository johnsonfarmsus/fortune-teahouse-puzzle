# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Sound. Muted until the start tap calls unlock() (browsers need a gesture).
## There are no sound files yet: play() quietly does nothing for a missing name.

var unlocked: bool = false
var streams: Dictionary = {}  # name -> AudioStream, filled when art and sound land
var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)


func unlock() -> void:
	unlocked = true


func play(sound_name: String) -> void:
	if not unlocked or not GameState.sound_on:
		return
	var stream: AudioStream = streams.get(sound_name)
	if stream == null:
		return
	_player.stream = stream
	_player.play()
