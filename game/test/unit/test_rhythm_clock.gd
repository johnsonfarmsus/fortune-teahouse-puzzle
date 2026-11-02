# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## 120 bpm gives a 0.5 s interval. With pattern [1,0,1,1], beats fall at 0.5
## (lit), 1.0 (dim), 1.5 (lit), 2.0 (lit), 2.5 (lit, the bar repeats) ...


func _clock(required: int = 3, tolerance_ms: float = 180.0) -> RhythmClock:
	return RhythmClock.new(120.0, [1, 0, 1, 1], tolerance_ms, required)


func test_beat_times_and_lit_pattern() -> void:
	var clock := _clock()
	assert_float(clock.interval()).is_equal_approx(0.5, 0.0001)
	assert_float(clock.beat_time(0)).is_equal_approx(0.5, 0.0001)
	assert_float(clock.beat_time(3)).is_equal_approx(2.0, 0.0001)
	assert_bool(clock.is_lit(0)).is_true()
	assert_bool(clock.is_lit(1)).is_false()
	assert_bool(clock.is_lit(4)).is_true()


func test_advance_emits_beats_in_order() -> void:
	var clock := _clock()
	var seen: Array = []
	clock.beat.connect(func(index: int, lit: bool) -> void: seen.append([index, lit]))
	clock.advance(0.4)
	assert_array(seen).is_empty()
	clock.advance(0.1)
	clock.advance(1.6)
	assert_array(seen).contains_exactly([[0, true], [1, false], [2, true], [3, true]])
	assert_int(clock.last_beat()).is_equal(3)


func test_press_on_the_lit_beat_is_on_beat() -> void:
	var clock := _clock()
	clock.advance(0.5)
	assert_bool(clock.press()).is_true()
	assert_int(clock.streak).is_equal(1)


func test_press_within_tolerance_early_and_late() -> void:
	var early := _clock()
	early.advance(0.5 - 0.17)
	assert_bool(early.press()).is_true()
	var late := _clock()
	late.advance(0.5 + 0.17)
	assert_bool(late.press()).is_true()


func test_press_outside_tolerance_is_off_beat() -> void:
	var early := _clock()
	early.advance(0.5 - 0.19)
	assert_bool(early.press()).is_false()
	var late := _clock()
	late.advance(0.5 + 0.19)
	assert_bool(late.press()).is_false()


func test_tolerance_is_configurable() -> void:
	var tight := _clock(3, 50.0)
	tight.advance(0.5 + 0.1)
	assert_bool(tight.press()).is_false()
	var loose := _clock(3, 220.0)
	loose.advance(0.5 + 0.2)
	assert_bool(loose.press()).is_true()


func test_press_on_a_dim_beat_resets_the_streak() -> void:
	var clock := _clock()
	clock.advance(0.5)
	clock.press()
	assert_int(clock.streak).is_equal(1)
	clock.advance(0.5)  # beat 1 at 1.0 is dim
	assert_bool(clock.press()).is_false()
	assert_int(clock.streak).is_equal(0)
	assert_bool(clock.is_solved()).is_false()


func test_second_press_on_the_same_beat_is_off_beat() -> void:
	var clock := _clock()
	clock.advance(0.5)
	assert_bool(clock.press()).is_true()
	clock.advance(0.05)
	assert_bool(clock.press()).is_false()
	assert_int(clock.streak).is_equal(0)


func test_press_between_beats_is_off_beat() -> void:
	var clock := _clock()
	clock.advance(1.0)  # 1.0 is a dim beat, 0.5 is long gone
	assert_bool(clock.press()).is_false()


func test_light_is_on_only_around_lit_beats() -> void:
	var clock := _clock()
	assert_bool(clock.light_on()).is_false()
	clock.advance(0.5 - 0.1)
	assert_bool(clock.light_on()).is_true()
	clock.advance(0.1 + 0.1)
	assert_bool(clock.light_on()).is_true()
	clock.advance(0.1)  # 0.7: past the window
	assert_bool(clock.light_on()).is_false()
	clock.advance(0.3)  # 1.0: dim beat
	assert_bool(clock.light_on()).is_false()


func test_required_on_beat_presses_solve_it() -> void:
	var clock := _clock(5)
	for i in 5:
		assert_bool(clock.is_solved()).is_false()
		clock.advance(clock.seconds_to_next_lit_beat())
		assert_bool(clock.press()).is_true()
	assert_bool(clock.is_solved()).is_true()
	assert_int(clock.streak).is_equal(5)


func test_off_beat_in_the_middle_starts_the_row_again() -> void:
	var clock := _clock(3)
	for i in 2:
		clock.advance(clock.seconds_to_next_lit_beat())
		clock.press()
	assert_int(clock.streak).is_equal(2)
	clock.advance(0.25)  # between beats
	assert_bool(clock.press()).is_false()
	assert_int(clock.streak).is_equal(0)
	for i in 3:
		clock.advance(clock.seconds_to_next_lit_beat())
		clock.press()
	assert_bool(clock.is_solved()).is_true()


func test_presses_after_solving_change_nothing() -> void:
	var clock := _clock(1)
	clock.advance(0.5)
	clock.press()
	assert_bool(clock.is_solved()).is_true()
	clock.advance(0.25)
	assert_bool(clock.press()).is_true()
	assert_int(clock.streak).is_equal(1)


func test_slow_down_cuts_the_tempo_and_keeps_the_phase() -> void:
	var clock := _clock()
	clock.advance(0.75)  # halfway between beats 0 and 1
	clock.slow_down(25.0)
	assert_float(clock.bpm).is_equal_approx(90.0, 0.0001)
	assert_float(clock.interval()).is_equal_approx(60.0 / 90.0, 0.0001)
	assert_float(clock.time / clock.interval()).is_equal_approx(1.5, 0.0001)


func test_complete_fills_the_row() -> void:
	var clock := _clock(4)
	clock.complete()
	assert_bool(clock.is_solved()).is_true()


func test_fast_tempo_clamps_the_tolerance() -> void:
	var clock := RhythmClock.new(300.0, [1], 180.0, 3)  # 0.2 s interval
	assert_float(clock.effective_tolerance()).is_equal_approx(0.09, 0.0001)


func test_bad_pattern_falls_back_to_every_beat() -> void:
	var clock := RhythmClock.new(100.0, [0, 0], 180.0, 2)
	assert_bool(clock.is_lit(0)).is_true()
	assert_bool(clock.is_lit(1)).is_true()
	var empty := RhythmClock.new(100.0, [], 180.0, 2)
	assert_bool(empty.is_lit(3)).is_true()
