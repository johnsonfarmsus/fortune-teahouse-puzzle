# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite

const ORDER := ["a", "b", "c", "d"]


func test_correct_order_is_solved() -> void:
	assert_bool(SequenceRules.is_solved(["a", "b", "c", "d"], ORDER)).is_true()
	assert_int(SequenceRules.first_wrong_index(["a", "b", "c", "d"], ORDER)).is_equal(-1)


func test_wrong_order_is_not_solved() -> void:
	var wrong := ["a", "c", "b", "d"]
	assert_bool(SequenceRules.is_solved(wrong, ORDER)).is_false()
	assert_int(SequenceRules.first_wrong_index(wrong, ORDER)).is_equal(1)
	assert_int(SequenceRules.correct_count(wrong, ORDER)).is_equal(2)


func test_partial_order_is_not_solved() -> void:
	assert_bool(SequenceRules.is_solved(["a", "b"], ORDER)).is_false()
	assert_bool(SequenceRules.is_solved([], ORDER)).is_false()
	# A right prefix points at the next empty position.
	assert_int(SequenceRules.first_wrong_index(["a", "b"], ORDER)).is_equal(2)
	assert_int(SequenceRules.first_wrong_index([], ORDER)).is_equal(0)


func test_decoy_in_sequence_is_wrong() -> void:
	assert_bool(SequenceRules.is_solved(["a", "b", "c", "x"], ORDER)).is_false()
	assert_int(SequenceRules.first_wrong_index(["a", "b", "c", "x"], ORDER)).is_equal(3)


func test_moved_puts_the_item_at_the_target_index() -> void:
	assert_array(SequenceRules.moved(["a", "b", "c", "d"], 0, 2)).contains_exactly(["b", "c", "a", "d"])
	assert_array(SequenceRules.moved(["a", "b", "c", "d"], 3, 0)).contains_exactly(["d", "a", "b", "c"])
	assert_array(SequenceRules.moved(["a", "b", "c"], 0, 9)).contains_exactly(["b", "c", "a"])
	assert_array(SequenceRules.moved(["a", "b"], 5, 0)).contains_exactly(["a", "b"])
