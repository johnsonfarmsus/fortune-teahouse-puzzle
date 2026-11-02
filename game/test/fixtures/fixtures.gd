# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted
## Small hand-made puzzles for unit tests, in the exporter's JSON shape. Unit
## tests use these, never autoload state. Usage:
##   const Fixtures := preload("res://test/fixtures/fixtures.gd")


static func cookie_raw() -> Dictionary:
	return {
		"schema_version": 1,
		"machine": "cookie_machine",
		"title": "Cookie Machine",
		"puzzle_title": "Batter recipe",
		"domain":
		{
			"items": ["sugar", "flour", "vanilla", "butter", "egg"],
			"positions": ["Jar 1", "Jar 2", "Jar 3", "Jar 4", "Jar 5"],
			"position_noun": "jar",
		},
		"answer": {"sugar": 1.0, "flour": 2.0, "vanilla": 3.0, "butter": 4.0, "egg": 5.0},
		"clues":
		[
			_clue("cookie_machine.security", "security", true, "CIPHER", "sugar", "", 1),
			_clue("cookie_machine.poem", "poem", true, "SPRINKLE", "flour", "sugar", 1),
			_clue("cookie_machine.animal", "animal", true, "HUDDLE", "vanilla", "flour", 1),
			_clue("cookie_machine.trivia", "trivia", true, "TUX", "egg", "", 5),
			_clue("cookie_machine.code", "code", false, "PATCH", "butter", "egg", -1),
			_clue("cookie_machine.hardware", "hardware", false, "SOLDER", "butter", "vanilla", 1),
		],
	}


static func fortune_raw() -> Dictionary:
	return {
		"schema_version": 1,
		"machine": "fortune_machine",
		"title": "Fortune Machine",
		"puzzle_title": "Phrase banks",
		"domain":
		{
			"items": ["luck", "love", "work", "travel", "wisdom"],
			"positions": ["Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5"],
			"position_noun": "printer slot",
		},
		"answer": {"luck": 5, "love": 2, "work": 1, "travel": 3, "wisdom": 4},
		"clues":
		[
			_clue("fortune_machine.security", "security", true, "INKWELL", "work", "", 1),
			_clue("fortune_machine.poem", "poem", true, "QUILL", "love", "work", 1),
			_clue("fortune_machine.animal", "animal", true, "GULL", "travel", "love", 1),
			_clue("fortune_machine.trivia", "trivia", true, "EMACS", "wisdom", "travel", 1),
			_clue("fortune_machine.code", "code", false, "SUDO", "luck", "", 5),
			_clue("fortune_machine.hardware", "hardware", false, "RELAY", "luck", "wisdom", 1),
		],
	}


## A catalog with the cookie and fortune fixtures (no parts defined).
static func catalog() -> PuzzleCatalog:
	var c := PuzzleCatalog.new()
	c.add_machine(cookie_raw())
	c.add_machine(fortune_raw())
	return c


static func _clue(id: String, style: String, approachable: bool, word: String, a: String, b: String, value: int) -> Dictionary:
	var fact: Dictionary = {"kind": "position" if b == "" else "offset", "a": a, "value": value}
	if b != "":
		fact["b"] = b
	return {
		"id": id,
		"style": style,
		"approachable": approachable,
		"fortune_text": "Fixture text for %s." % id,
		"lucky_word": word,
		"fact": fact,
		"nudge": "Fixture nudge for %s." % id,
	}
