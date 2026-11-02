# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite

const Fixtures := preload("res://test/fixtures/fixtures.gd")


func test_first_word_joins_crew() -> void:
	var state := PlayerState.new()
	var result := state.enter_lucky_word("tux", Fixtures.catalog())
	assert_int(result).is_equal(PlayerState.COLLECTED_JOINED)
	assert_str(state.crew).is_equal("cookie_machine")
	assert_array(state.collected_clue_ids).contains_exactly(["cookie_machine.trivia"])


func test_later_words_only_collect() -> void:
	var state := PlayerState.new()
	var catalog := Fixtures.catalog()
	state.enter_lucky_word("TUX", catalog)
	assert_int(state.enter_lucky_word("SPRINKLE", catalog)).is_equal(PlayerState.COLLECTED)
	# A word from another machine collects its clue but does not change the crew.
	assert_int(state.enter_lucky_word("INKWELL", catalog)).is_equal(PlayerState.COLLECTED)
	assert_str(state.crew).is_equal("cookie_machine")
	assert_int(state.collected_clue_ids.size()).is_equal(3)


func test_duplicate_and_unknown() -> void:
	var state := PlayerState.new()
	var catalog := Fixtures.catalog()
	state.enter_lucky_word("TUX", catalog)
	assert_int(state.enter_lucky_word(" tux ", catalog)).is_equal(PlayerState.ALREADY_HAVE)
	assert_int(state.enter_lucky_word("zzz", catalog)).is_equal(PlayerState.UNKNOWN)
	assert_int(state.collected_clue_ids.size()).is_equal(1)


func test_choose_crew_with_no_clues() -> void:
	var state := PlayerState.new()
	assert_bool(state.choose_crew("oven")).is_true()
	assert_str(state.crew).is_equal("oven")
	assert_bool(state.choose_crew("not_a_machine")).is_false()
	assert_str(state.crew).is_equal("oven")


func test_switching_crew_keeps_clues_and_solves() -> void:
	var state := PlayerState.new()
	state.enter_lucky_word("TUX", Fixtures.catalog())
	state.mark_solved("cookie_machine", "logic", true)
	state.choose_crew("oven")
	assert_str(state.crew).is_equal("oven")
	assert_int(state.collected_clue_ids.size()).is_equal(1)
	assert_bool(state.is_part_credited("cookie_machine", "logic")).is_true()


func test_revealed_solve_is_not_credited_until_solved_again() -> void:
	var state := PlayerState.new()
	state.mark_solved("oven", "logic", false)
	assert_bool(state.is_part_solved("oven", "logic")).is_true()
	assert_bool(state.is_part_credited("oven", "logic")).is_false()
	state.mark_solved("oven", "logic", true)
	assert_bool(state.is_part_credited("oven", "logic")).is_true()
	state.mark_solved("oven", "logic", false)
	assert_bool(state.is_part_credited("oven", "logic")).is_true()


func test_dict_round_trip_through_json() -> void:
	var state := PlayerState.new()
	state.ensure_device_id()
	state.display_name = "Tux"
	state.name_asked = true
	state.enter_lucky_word("TUX", Fixtures.catalog())
	state.mark_solved("cookie_machine", "logic", true)
	state.hint_levels["cookie_machine/logic"] = 2
	state.sound_on = false
	var parser := JSON.new()
	assert_int(parser.parse(JSON.stringify(state.to_dict()))).is_equal(OK)
	var copy := PlayerState.from_dict(parser.data)
	assert_dict(copy.to_dict()).is_equal(state.to_dict())
	assert_int(copy.hint_levels["cookie_machine/logic"]).is_equal(2)
	assert_str(copy.device_id).has_length(32)


func test_clues_for_machine() -> void:
	var state := PlayerState.new()
	var catalog := Fixtures.catalog()
	state.enter_lucky_word("TUX", catalog)
	state.enter_lucky_word("INKWELL", catalog)
	assert_array(state.clues_for_machine("cookie_machine", catalog)).contains_exactly(["cookie_machine.trivia"])
