# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite

const Fixtures := preload("res://test/fixtures/fixtures.gd")


func test_normalise_uppercases_and_strips() -> void:
	assert_str(LuckyWords.normalise(" tux.")).is_equal("TUX")
	assert_str(LuckyWords.normalise("sprinkle!!")).is_equal("SPRINKLE")
	assert_str(LuckyWords.normalise("a b-c 9")).is_equal("ABC9")
	assert_str(LuckyWords.normalise("")).is_equal("")
	assert_str(LuckyWords.normalise("  ...  ")).is_equal("")


func test_known_word_finds_machine_and_clue() -> void:
	var hit := Fixtures.catalog().lookup_lucky_word("tux")
	assert_str(hit["machine"]).is_equal("cookie_machine")
	assert_str(hit["clue_id"]).is_equal("cookie_machine.trivia")


func test_lookup_is_forgiving() -> void:
	var catalog := Fixtures.catalog()
	assert_bool(catalog.lookup_lucky_word("  Sprinkle. ").is_empty()).is_false()


func test_unknown_word_is_empty() -> void:
	assert_bool(Fixtures.catalog().lookup_lucky_word("nonsense").is_empty()).is_true()
	assert_bool(Fixtures.catalog().lookup_lucky_word("").is_empty()).is_true()


func test_other_machine_word_is_found() -> void:
	var hit := Fixtures.catalog().lookup_lucky_word("INKWELL")
	assert_str(hit["machine"]).is_equal("fortune_machine")
	assert_str(hit["clue_id"]).is_equal("fortune_machine.security")
