# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite

const ANSWER := {"red": "s2", "brown": "s1", "green": "s3"}


func test_correct_wiring_is_solved() -> void:
	assert_bool(WiringRules.is_solved(ANSWER.duplicate(), ANSWER)).is_true()
	assert_array(WiringRules.wrong_terminals(ANSWER.duplicate(), ANSWER)).is_empty()


func test_wrong_wiring_is_not_solved() -> void:
	var swapped := {"red": "s1", "brown": "s2", "green": "s3"}
	assert_bool(WiringRules.is_solved(swapped, ANSWER)).is_false()
	assert_array(WiringRules.wrong_terminals(swapped, ANSWER)).contains_exactly(["red", "brown"])


func test_partial_wiring_is_not_solved() -> void:
	var partial := {"red": "s2"}
	assert_bool(WiringRules.is_solved(partial, ANSWER)).is_false()
	assert_array(WiringRules.wrong_terminals(partial, ANSWER)).contains_exactly(["brown", "green"])
	assert_bool(WiringRules.is_solved({}, {})).is_false()


func test_extra_wire_is_not_solved() -> void:
	var extra := ANSWER.duplicate()
	extra["blue"] = "s4"
	assert_bool(WiringRules.is_solved(extra, ANSWER)).is_false()


func test_with_wire_replaces_both_ends() -> void:
	var wires := WiringRules.with_wire({}, "red", "s2")
	wires = WiringRules.with_wire(wires, "brown", "s2")  # socket taken over
	assert_dict(wires).is_equal({"brown": "s2"})
	wires = WiringRules.with_wire(wires, "brown", "s1")  # terminal re-routed
	assert_dict(wires).is_equal({"brown": "s1"})
