# SPDX-License-Identifier: AGPL-3.0-or-later
class_name RhythmClock
extends RefCounted
## Beat clock for the rhythm puzzle, driven by advance(seconds) so tests (and
## _process) control time. Beat k happens at (k + 1) * interval, so there is one
## beat of lead-in. pattern[k % pattern.size()] != 0 means beat k is lit. A press
## within tolerance of a lit beat that has not been hit yet is on-beat and
## extends the streak; any other press is off-beat and resets it. Nothing here
## can fail: the streak simply starts again.

signal beat(index: int, lit: bool)

const EPSILON := 0.000001

var bpm: float = 90.0
var pattern: Array = [1, 0, 1, 1]
var tolerance: float = 0.18  # seconds
var required: int = 6
var streak: int = 0
var time: float = 0.0  # seconds since start

var _next_beat: int = 0
var _last_hit: int = -1


func _init(p_bpm: float = 90.0, p_pattern: Array = [1, 0, 1, 1], p_tolerance_ms: float = 180.0, p_required: int = 6) -> void:
	bpm = maxf(p_bpm, 1.0)
	pattern = p_pattern.duplicate()
	if not _has_lit_beat():
		pattern = [1]
	tolerance = maxf(p_tolerance_ms, 0.0) / 1000.0
	required = maxi(p_required, 1)


func interval() -> float:
	return 60.0 / bpm


## Largest usable tolerance: windows of neighbouring beats never overlap.
func effective_tolerance() -> float:
	return minf(tolerance, interval() * 0.45)


func beat_time(index: int) -> float:
	return (index + 1) * interval()


func is_lit(index: int) -> bool:
	return index >= 0 and int(pattern[index % pattern.size()]) != 0


func is_solved() -> bool:
	return streak >= required


## Index of the beat that most recently happened, or -1 before the first one.
func last_beat() -> int:
	return _next_beat - 1


## Moves time forward and emits `beat` for every beat passed.
func advance(seconds: float) -> void:
	time += maxf(seconds, 0.0)
	while beat_time(_next_beat) <= time + EPSILON:
		beat.emit(_next_beat, is_lit(_next_beat))
		_next_beat += 1


## Index of the beat closest to now (-1 before the first beat is near).
func nearest_beat() -> int:
	return int(round(time / interval())) - 1


## True while the clock is inside the window of a lit beat (the light is on).
func light_on() -> bool:
	return _nearest_lit(false) != -1


## Seconds from now until the next lit beat that has not been hit yet (0 if it
## is happening right now).
func seconds_to_next_lit_beat() -> float:
	var k := maxi(_last_hit + 1, 0)
	while true:
		if is_lit(k) and beat_time(k) >= time - EPSILON:
			return maxf(beat_time(k) - time, 0.0)
		k += 1
	return 0.0


## A press. Returns true when it was on a lit beat. Presses after the puzzle is
## solved change nothing.
func press() -> bool:
	if is_solved():
		return true
	var k := _nearest_lit(true)
	if k == -1:
		streak = 0
		return false
	_last_hit = k
	streak += 1
	return true


## Slows the tempo by `percent`, keeping the beat phase.
func slow_down(percent: float) -> void:
	var old := interval()
	bpm = maxf(bpm * (1.0 - percent / 100.0), 1.0)
	time = time * interval() / old


## Shows the answer: the whole row is lit.
func complete() -> void:
	streak = required


## The nearest lit beat within tolerance, or -1. With `unhit_only`, a beat
## already pressed on does not count (so one beat gives one point).
func _nearest_lit(unhit_only: bool) -> int:
	var centre := nearest_beat()
	var best := -1
	var best_dist := effective_tolerance() + EPSILON
	for k in range(maxi(centre - 1, 0), centre + 2):
		if not is_lit(k) or (unhit_only and k <= _last_hit):
			continue
		var dist := absf(time - beat_time(k))
		if dist <= best_dist:
			best = k
			best_dist = dist
	return best


func _has_lit_beat() -> bool:
	for v in pattern:
		if int(v) != 0:
			return true
	return false
