# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Sound. Muted until the start tap calls unlock() (browsers need a gesture).
## Effects come from data/sfx.json, synthesised in code (SfxBank, SfxSynth);
## `streams` can override one by name. A few players take turns so quick taps
## overlap instead of cutting each other off, and one more plays the room's
## quiet ambient loop. `played` records the last ids asked for, even while
## muted, so tests can check that every interaction makes a sound.

const VOICES := 6
const HISTORY := 64

var unlocked: bool = false
var streams: Dictionary = {}  # name -> AudioStream, overrides the bank
var bank: SfxBank
var played: Array[String] = []
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambient: AudioStreamPlayer
var _ambient_id := ""


func _ready() -> void:
	bank = SfxBank.new()
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_ambient = AudioStreamPlayer.new()
	_ambient.volume_db = -4.0
	add_child(_ambient)


func unlock() -> void:
	unlocked = true
	_refresh_ambient()


func last_played() -> String:
	return played.back() if not played.is_empty() else ""


func play(sound_name: String, pitch: float = 1.0) -> void:
	played.append(sound_name)
	if played.size() > HISTORY:
		played.pop_front()
	if not unlocked or not GameState.sound_on:
		return
	var stream: AudioStream = streams.get(sound_name)
	if stream == null and bank != null:
		stream = bank.stream(sound_name)
	if stream == null:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


## The quiet loop for the room the player is in ("" for none).
func play_ambient(sound_name: String) -> void:
	if sound_name == _ambient_id:
		return
	_ambient_id = sound_name
	_refresh_ambient()


func ambient_id() -> String:
	return _ambient_id


## GameState calls this when the Sound switch changes.
func sound_setting_changed() -> void:
	_refresh_ambient()


func _refresh_ambient() -> void:
	if _ambient == null:
		return
	if not unlocked or not GameState.sound_on or _ambient_id == "" or bank == null:
		_ambient.stop()
		return
	var stream := bank.stream(_ambient_id)
	if stream == null:
		_ambient.stop()
		return
	if _ambient.stream != stream or not _ambient.playing:
		_ambient.stream = stream
		_ambient.play()
