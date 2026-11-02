# SPDX-License-Identifier: AGPL-3.0-or-later
class_name Paths
extends RefCounted
## Resource paths as strings. Scenes are reached only through these constants
## and load(), never preload(), so scripts do not form load cycles.

const MAIN := "res://scenes/main/main.tscn"
const ADVENTURE_VIEW := "res://scenes/adventure/adventure_view.tscn"
const BATTER_SHELF := "res://scenes/puzzles/batter_shelf_puzzle.tscn"
const PLACES := {
	"town": "res://scenes/world/town.tscn",
	"shop": "res://scenes/world/shop.tscn",
}
const LUCKY_WORD_ENTRY := "res://scenes/screens/lucky_word_entry.tscn"
const CLUE_BOARD := "res://scenes/screens/clue_board.tscn"
const MACHINE_VIEW := "res://scenes/screens/machine_view.tscn"
const PUZZLE_HOST := "res://scenes/screens/puzzle_host.tscn"
const MERGE_CELEBRATION := "res://scenes/screens/merge_celebration.tscn"
const CONTRIBUTORS := "res://scenes/screens/contributors.tscn"
const SETTINGS := "res://scenes/screens/settings.tscn"
const CREW_PROGRESS := "res://scenes/screens/crew_progress.tscn"
const DIALOGUE_BOX := "res://scenes/ui/dialogue_box.tscn"
const STORY_MARKER := "res://scenes/world/story_marker.tscn"
const FINALE_VIEW := "res://scenes/screens/finale_view.tscn"
const HANDOFF_HOST := "res://scenes/screens/handoff_host.tscn"
const ARCHIVE := "res://scenes/screens/archive.tscn"
const README_SCREEN := "res://scenes/screens/readme_screen.tscn"
const HINT_BANNER := "res://scenes/ui/hint_banner.tscn"
const LETTER_KEYPAD := "res://scenes/ui/letter_keypad.tscn"
const CLUE_CARD := "res://scenes/ui/clue_card.tscn"
const COMING_SOON := "res://scenes/puzzles/coming_soon_puzzle.tscn"


static func puzzle_data(machine: String) -> String:
	return "res://data/puzzles/%s.json" % machine


static func machine_data(machine: String) -> String:
	return "res://data/machines/%s.json" % machine


## The scene for a puzzle type, or the coming-soon scene if it does not exist yet.
static func puzzle_scene(type: String) -> String:
	var path := "res://scenes/puzzles/%s_puzzle.tscn" % type
	if type != "" and ResourceLoader.exists(path):
		return path
	return COMING_SOON
