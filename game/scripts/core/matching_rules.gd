# SPDX-License-Identifier: AGPL-3.0-or-later
class_name MatchingRules
extends RefCounted
## Pure rules for the 5-to-5 matching puzzles. A placement is {item: position}
## with positions 1 to 5; it may be partial.


static func is_solved(placement: Dictionary, answer: Dictionary) -> bool:
	if answer.is_empty() or placement.size() != answer.size():
		return false
	for item in answer:
		if int(placement.get(item, 0)) != int(answer[item]):
			return false
	return true


## True only when every item the fact mentions is placed and the fact holds.
static func fact_holds(fact: Dictionary, placement: Dictionary) -> bool:
	var a: String = str(fact.get("a", ""))
	if not placement.has(a):
		return false
	var value := int(fact.get("value", 0))
	match str(fact.get("kind", "")):
		"position":
			return int(placement[a]) == value
		"offset":
			var b: String = str(fact.get("b", ""))
			if not placement.has(b):
				return false
			return int(placement[a]) == int(placement[b]) + value
	return false


## Plain words for a fact: "Sugar is in jar 1." or "Egg is 2 jars after butter."
static func fact_to_text(fact: Dictionary, domain: Dictionary) -> String:
	var noun: String = str(domain.get("position_noun", "place"))
	var a := _name(str(fact.get("a", "")), domain)
	var value := int(fact.get("value", 0))
	if str(fact.get("kind", "")) == "position":
		return "%s is in %s %d." % [a, noun, value]
	var b := _mid(_name(str(fact.get("b", "")), domain))
	if value == 1:
		return "%s is in the %s right after %s's." % [a, noun, b]
	if value == -1:
		return "%s is in the %s right before %s's." % [a, noun, b]
	if value > 1:
		return "%s is %d %ss after %s." % [a, value, noun, b]
	return "%s is %d %ss before %s." % [a, -value, noun, b]


static func _name(item: String, domain: Dictionary) -> String:
	var names: Dictionary = domain.get("item_names", {})
	return str(names.get(item, item))


## Lowercases a leading letter for use mid-sentence ("120 C" stays as it is).
static func _mid(s: String) -> String:
	if s.length() > 0 and s.substr(0, 1).to_lower() != s.substr(0, 1).to_upper():
		return s.substr(0, 1).to_lower() + s.substr(1)
	return s
