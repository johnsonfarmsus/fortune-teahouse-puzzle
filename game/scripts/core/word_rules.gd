# SPDX-License-Identifier: AGPL-3.0-or-later
class_name WordRules
extends RefCounted
## Pure logic for the word puzzle. `filled` is {blank_index: word}; `blanks` is
## the config array [{index, answer}].


## Splits "The mixer hums when the {0} is tight" into segments: {"text": word}
## for each plain word and {"blank": 0} for a blank. Plain text is split per
## word so a flow container can wrap it.
static func parse_line(line: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\{(\\d+)\\}")
	var pos := 0
	for m in re.search_all(line):
		_add_words(out, line.substr(pos, m.get_start() - pos))
		out.append({"blank": int(m.get_string(1))})
		pos = m.get_end()
	_add_words(out, line.substr(pos))
	return out


static func _add_words(out: Array, text: String) -> void:
	for word in text.split(" ", false):
		out.append({"text": word})


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
