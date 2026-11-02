# SPDX-License-Identifier: AGPL-3.0-or-later
class_name Nudges
extends RefCounted
## Mentor nudges. The scoreboard knows only the ids (GET /hints/nudges); the
## words live here. A nudge never names an answer.

const TEXTS := {
	"reread_the_clue": "Read the clue again, slowly. Every word is there for a reason.",
	"ask_a_crewmate": "Ask a crewmate what their clue says. Two clues beat one.",
	"start_with_the_sure_thing": "Start with the thing you are surest about and build from there.",
	"try_the_help_button": "Try the Hint button. The first hint is gentle.",
	"check_neighbours": "Check what sits next to each piece. Neighbours give things away.",
	"look_at_the_order": "Look at the order. Which piece has to come first?",
	"follow_the_wires": "Follow each wire from end to end, one at a time.",
	"listen_for_the_beat": "Listen for the beat, or watch the lights, and say it out loud.",
	"take_a_short_break": "Take a short break. Drink some tea and look again in a minute.",
	"compare_with_another_crew": "Compare notes with someone from another crew. They may see it differently.",
}
## Display order, and the fallback when the server list cannot be loaded.
const IDS: Array[String] = [
	"reread_the_clue",
	"ask_a_crewmate",
	"start_with_the_sure_thing",
	"try_the_help_button",
	"check_neighbours",
	"look_at_the_order",
	"follow_the_wires",
	"listen_for_the_beat",
	"take_a_short_break",
	"compare_with_another_crew",
]


## Short button text: "Reread the clue".
static func label(nudge_id: String) -> String:
	var words := nudge_id.replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)


static func text(nudge_id: String) -> String:
	return str(TEXTS.get(nudge_id, label(nudge_id) + "."))


## The banner line for a hint object from GET /hints.
static func describe(hint: Dictionary) -> String:
	var who := str(hint.get("from_name", ""))
	if who == "" or who == "anonymous":
		who = "A maintainer"
	var from_crew := str(hint.get("from_crew", ""))
	if Ids.MACHINES.has(from_crew):
		who += " (%s)" % Ids.machine_title(from_crew)
	return "%s says: %s" % [who, text(str(hint.get("nudge_id", "")))]
