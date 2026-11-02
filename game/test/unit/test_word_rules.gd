# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite

const BLANKS := [{"index": 0, "answer": "tight"}, {"index": 1, "answer": "night"}]


func test_parse_line_splits_words_and_blanks() -> void:
	var segs := WordRules.parse_line("The mixer hums when the {0} is tight")
	assert_int(segs.size()).is_equal(8)
	assert_dict(segs[0]).is_equal({"text": "The"})
	assert_dict(segs[5]).is_equal({"blank": 0})
	assert_dict(segs[7]).is_equal({"text": "tight"})


func test_parse_line_handles_edges_and_several_blanks() -> void:
	var segs := WordRules.parse_line("{0} and {12}.")
	assert_dict(segs[0]).is_equal({"blank": 0})
	assert_dict(segs[1]).is_equal({"text": "and"})
	assert_dict(segs[2]).is_equal({"blank": 12})
	assert_dict(segs[3]).is_equal({"text": "."})
	assert_array(WordRules.parse_line("")).is_empty()


func test_all_correct_is_solved() -> void:
	assert_bool(WordRules.is_solved({0: "tight", 1: "night"}, BLANKS)).is_true()
	assert_array(WordRules.wrong_blanks({0: "tight", 1: "night"}, BLANKS)).is_empty()


func test_case_and_spaces_do_not_matter() -> void:
	assert_bool(WordRules.is_solved({0: " Tight", 1: "NIGHT"}, BLANKS)).is_true()


func test_wrong_word_is_not_solved() -> void:
	var filled := {0: "night", 1: "tight"}
	assert_bool(WordRules.is_solved(filled, BLANKS)).is_false()
	assert_array(WordRules.wrong_blanks(filled, BLANKS)).contains_exactly([0, 1])


func test_partial_is_not_solved() -> void:
	assert_bool(WordRules.is_solved({0: "tight"}, BLANKS)).is_false()
	assert_array(WordRules.wrong_blanks({0: "tight"}, BLANKS)).contains_exactly([1])
	assert_bool(WordRules.is_solved({}, [])).is_false()
