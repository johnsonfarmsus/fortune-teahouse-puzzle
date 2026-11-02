# SPDX-License-Identifier: AGPL-3.0-or-later
class_name Ids
extends RefCounted
## Shared ids and display strings. Nothing here is an answer.

const MACHINES: Array[String] = ["fortune_machine", "cookie_machine", "oven"]
const MACHINE_TITLES := {
	"fortune_machine": "Fortune Machine",
	"cookie_machine": "Cookie Machine",
	"oven": "Oven",
}
const PARTS: Array[String] = ["logic", "wiring", "sequence", "word", "rhythm", "helper"]
const PART_TITLES := {
	"logic": "Logic",
	"wiring": "Wiring",
	"sequence": "Sequence",
	"word": "Word",
	"rhythm": "Rhythm",
	"helper": "Helper",
}
const STYLE_LABELS := {
	"poem": "Poem",
	"animal": "Animal fact",
	"trivia": "Open source trivia",
	"security": "Light security",
	"code": "Code",
	"hardware": "Hardware",
}
## Clue styles in the order the stronger nudge tries them.
const HINT_STYLE_ORDER: Array[String] = ["security", "code", "hardware", "trivia", "poem", "animal"]
const CLUE_THRESHOLD := 4
const REPO_URL := "https://github.com/johnsonfarmsus/fortune-teahouse-puzzle"


static func machine_title(machine: String) -> String:
	return str(MACHINE_TITLES.get(machine, machine))
