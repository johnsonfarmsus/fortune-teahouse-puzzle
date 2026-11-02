# SPDX-License-Identifier: AGPL-3.0-or-later
class_name WordRules
extends RefCounted
## Pure logic for the word puzzle. `filled` is {blank_index: word}; `blanks` is
## the config array [{index, answer}].


## Splits "The mixer hums when the {0}, tight" into one segment per
## space-separated token: {"text": word} for a plain word and {"blank": 0} for a
## blank. Punctuation stuck to a blank stays with it as "before" / "after" (keys
## only present when non-empty), so a comma or full stop is rendered with the
## blank and never wraps onto a line of its own.
static func parse_line(line: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("^([^{}\\s]*)\\{(\\d+)\\}([^{}\\s]*)$")
	for token in line.split(" ", false):
		var m := re.search(token)
		if m == null:
			out.append({"text": token})
			continue
		var seg := {"blank": int(m.get_string(2))}
		if m.get_string(1) != "":
			seg["before"] = m.get_string(1)
		if m.get_string(3) != "":
			seg["after"] = m.get_string(3)
		out.append(seg)
	return out


static func normalise(word: String) -> String:
	return word.strip_edges().to_lower()


static func is_correct(filled: Dictionary, blank: Dictionary) -> bool:
	var index := int(blank.get("index", -1))
	return filled.has(index) and normalise(str(filled[index])) == normalise(str(blank.get("answer", "")))


static func is_solved(filled: Dictionary, blanks: Array) -> bool:
	if blanks.is_empty():
		return false
	for blank: Dictionary in blanks:
		if not is_correct(filled, blank):
			return false
	return true


## Blank indexes that are empty or hold a wrong word, in config order.
static func wrong_blanks(filled: Dictionary, blanks: Array) -> Array[int]:
	var out: Array[int] = []
	for blank: Dictionary in blanks:
		if not is_correct(filled, blank):
			out.append(int(blank.get("index", -1)))
	return out
