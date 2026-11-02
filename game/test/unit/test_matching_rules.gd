# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite

const Fixtures := preload("res://test/fixtures/fixtures.gd")

const ANSWER := {"sugar": 1, "flour": 2, "vanilla": 3, "butter": 4, "egg": 5}


func test_is_solved_for_the_answer() -> void:
	assert_bool(MatchingRules.is_solved(ANSWER.duplicate(), ANSWER)).is_true()


func test_is_solved_false_after_one_swap() -> void:
	var swapped := ANSWER.duplicate()
	swapped["sugar"] = 2
	swapped["flour"] = 1
	assert_bool(MatchingRules.is_solved(swapped, ANSWER)).is_false()


func test_is_solved_false_when_partial() -> void:
	assert_bool(MatchingRules.is_solved({"sugar": 1}, ANSWER)).is_false()
	assert_bool(MatchingRules.is_solved({}, {})).is_false()


func test_fact_holds_position() -> void:
	var fact := {"kind": "position", "a": "sugar", "value": 1}
	assert_bool(MatchingRules.fact_holds(fact, ANSWER)).is_true()
	assert_bool(MatchingRules.fact_holds(fact, {"sugar": 2})).is_false()
	assert_bool(MatchingRules.fact_holds(fact, {})).is_false()


func test_fact_holds_offsets_including_negative() -> void:
	var after := {"kind": "offset", "a": "flour", "b": "sugar", "value": 1}
	var before := {"kind": "offset", "a": "butter", "b": "egg", "value": -1}
	assert_bool(MatchingRules.fact_holds(after, ANSWER)).is_true()
	assert_bool(MatchingRules.fact_holds(before, ANSWER)).is_true()
	assert_bool(MatchingRules.fact_holds(after, {"flour": 1, "sugar": 2})).is_false()
	assert_bool(MatchingRules.fact_holds(before, {"butter": 5, "egg": 4})).is_false()
	# Either-order misreading must not pass: the sign matters.
	assert_bool(MatchingRules.fact_holds({"kind": "offset", "a": "egg", "b": "butter", "value": -1}, ANSWER)).is_false()
	# A fact about an unplaced item does not hold.
	assert_bool(MatchingRules.fact_holds(after, {"flour": 2})).is_false()


func test_fact_to_text() -> void:
	var domain := Fixtures.catalog().get_domain("cookie_machine")
	assert_str(MatchingRules.fact_to_text({"kind": "position", "a": "sugar", "value": 1}, domain)).is_equal(
		"Sugar is in jar 1."
	)
	assert_str(
		MatchingRules.fact_to_text({"kind": "offset", "a": "vanilla", "b": "flour", "value": 1}, domain)
	).is_equal("Vanilla is in the jar right after flour's.")
	assert_str(
		MatchingRules.fact_to_text({"kind": "offset", "a": "butter", "b": "egg", "value": -1}, domain)
	).is_equal("Butter is in the jar right before egg's.")
	assert_str(
		MatchingRules.fact_to_text({"kind": "offset", "a": "egg", "b": "butter", "value": 2}, domain)
	).is_equal("Egg is 2 jars after butter.")
	assert_str(
		MatchingRules.fact_to_text({"kind": "offset", "a": "egg", "b": "butter", "value": -3}, domain)
	).is_equal("Egg is 3 jars before butter.")


func test_item_names_for_the_oven() -> void:
	var catalog := PuzzleCatalog.load_all()
	var domain := catalog.get_domain("oven")
	var fact := {"kind": "offset", "a": "c120", "b": "c200", "value": 1}
	assert_str(MatchingRules.fact_to_text(fact, domain)).is_equal("120 C is in the heat zone right after 200 C's.")


## Every 4 of the 6 clues give exactly the stored answer; no 3 do.
func test_four_clues_are_enough_and_three_are_not() -> void:
	for machine in Ids.MACHINES:
		var data := JsonFile.read(Paths.puzzle_data(machine))
		assert_bool(data.is_empty()).is_false()
		var catalog := PuzzleCatalog.new()
		catalog.add_machine(data)
		var clues := catalog.get_clues(machine)
		var items: Array = catalog.get_domain(machine)["items"]
		var answer := catalog.get_answer(machine)
		var orderings := _orderings(items)
		assert_int(orderings.size()).is_equal(120)
		for subset in _subsets(clues.size(), 4):
			var survivors := _survivors(clues, subset, orderings)
			assert_int(survivors.size()).override_failure_message("%s subset %s" % [machine, subset]).is_equal(1)
			assert_bool(MatchingRules.is_solved(survivors[0], answer)).is_true()
		for subset in _subsets(clues.size(), 3):
			var survivors := _survivors(clues, subset, orderings)
			assert_int(survivors.size()).override_failure_message("%s subset %s" % [machine, subset]).is_greater(1)


func _survivors(clues: Array, subset: Array, orderings: Array) -> Array:
	var out: Array = []
	for placement: Dictionary in orderings:
		var ok := true
		for index: int in subset:
			if not MatchingRules.fact_holds(clues[index]["fact"], placement):
				ok = false
				break
		if ok:
			out.append(placement)
	return out


func _orderings(items: Array) -> Array:
	var out: Array = []
	_permute(items, [], out)
	return out


func _permute(items: Array, chosen: Array, out: Array) -> void:
	if chosen.size() == items.size():
		var placement := {}
		for i in items.size():
			placement[items[i]] = chosen[i]
		out.append(placement)
		return
	for pos in range(1, items.size() + 1):
		if not chosen.has(pos):
			_permute(items, chosen + [pos], out)


func _subsets(n: int, k: int) -> Array:
	var out: Array = []
	_choose(n, k, 0, [], out)
	return out


func _choose(n: int, k: int, start: int, current: Array, out: Array) -> void:
	if current.size() == k:
		out.append(current.duplicate())
		return
	for i in range(start, n):
		current.append(i)
		_choose(n, k, i + 1, current, out)
		current.pop_back()
