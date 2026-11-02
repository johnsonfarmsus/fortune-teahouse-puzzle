# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite


func test_levels_climb_to_reveal() -> void:
	var ladder := HintLadder.new()
	assert_int(ladder.level("a/b")).is_equal(0)
	assert_int(ladder.advance("a/b", true)).is_equal(1)
	assert_int(ladder.advance("a/b", true)).is_equal(2)
	assert_int(ladder.advance("a/b", true)).is_equal(3)
	assert_int(ladder.advance("a/b", true)).is_equal(3)


func test_cap_at_two_without_reveal() -> void:
	var ladder := HintLadder.new()
	ladder.advance("a/b", false)
	ladder.advance("a/b", false)
	assert_int(ladder.advance("a/b", false)).is_equal(2)
	assert_int(ladder.advance("a/b", false)).is_equal(2)


func test_puzzles_are_independent() -> void:
	var ladder := HintLadder.new()
	ladder.advance("a/b", true)
	assert_int(ladder.level("c/d")).is_equal(0)


func test_wrapped_dictionary_is_updated_in_place() -> void:
	var saved := {}
	var ladder := HintLadder.new(saved)
	ladder.advance("a/b", true)
	assert_int(int(saved["a/b"])).is_equal(1)


func test_dict_persistence() -> void:
	var ladder := HintLadder.new()
	ladder.advance("a/b", true)
	ladder.advance("a/b", true)
	var copy := HintLadder.from_dict(ladder.to_dict())
	assert_int(copy.level("a/b")).is_equal(2)
	assert_int(copy.advance("a/b", true)).is_equal(3)
	ladder.reset("a/b")
	assert_int(ladder.level("a/b")).is_equal(0)
