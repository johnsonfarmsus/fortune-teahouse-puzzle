# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## DialRules: marks, locking, and the shipped dial data.

var data: FinaleData


func before_test() -> void:
	data = FinaleData.new()


func _rules(handoff_id: String, extra: Dictionary = {}) -> DialRules:
	var config: Dictionary = data.handoff(handoff_id)["config"].duplicate(true)
	config.merge(extra, true)
	return DialRules.new(config)


func test_marks_for_an_ordered_dial() -> void:
	var rules := _rules("cookie_to_oven")
	assert_str(rules.mark("belt_speed")).is_equal(DialRules.LOW)  # starts at 1, answer 3
	rules.set_value("belt_speed", 3)
	assert_str(rules.mark("belt_speed")).is_equal(DialRules.OK)
	rules.set_value("belt_speed", 5)
	assert_str(rules.mark("belt_speed")).is_equal(DialRules.HIGH)


func test_marks_for_an_unordered_dial_are_ok_or_wrong() -> void:
	var rules := _rules("oven_to_packaging")
	assert_str(rules.mark("chute_1")).is_equal(DialRules.WRONG)
	rules.set_value("chute_1", "teahouse_tin")
	assert_str(rules.mark("chute_1")).is_equal(DialRules.WRONG)
	rules.set_value("chute_1", "rooftop_basket")
	assert_str(rules.mark("chute_1")).is_equal(DialRules.OK)
	assert_str(rules.message("chute_2", DialRules.WRONG)).is_equal("Gopher frowns: that's not who wants these.")


func test_test_locks_only_the_right_dials_and_reports_the_rest() -> void:
	var rules := _rules("cookie_to_oven")
	rules.set_value("belt_speed", 3)
	rules.set_value("press_every", 8)
	var marks := rules.test()
	assert_str(marks["belt_speed"]).is_equal(DialRules.OK)
	assert_str(marks["press_every"]).is_equal(DialRules.HIGH)
	assert_str(marks["bowl_every"]).is_equal(DialRules.LOW)
	assert_array(rules.locked_ids()).contains_exactly(["belt_speed"])
	assert_array(rules.last_locked).contains_exactly([0])
	assert_bool(rules.all_locked()).is_false()
	# A locked dial cannot move.
	assert_bool(rules.step("belt_speed", 1)).is_false()
	assert_bool(rules.set_value("belt_speed", 6)).is_false()
	assert_int(rules.value("belt_speed")).is_equal(3)


func test_steps_stop_at_the_ends() -> void:
	var rules := _rules("fortune_to_oven")
	assert_bool(rules.step("dry", -1)).is_false()  # starts at the lowest value
	assert_bool(rules.step("dry", 1)).is_true()
	assert_int(rules.value("dry")).is_equal(1)
	rules.step("dry", 10)
	assert_int(rules.value("dry")).is_equal(3)
	assert_bool(rules.step("dry", 1)).is_false()


func test_setting_the_answers_locks_everything() -> void:
	for entry in data.handoffs:
		var rules := DialRules.new(entry["config"])
		for id in rules.ids():
			assert_bool(rules.set_value(id, rules.answer_value(id))).is_true()
		var marks := rules.test()
		for id in rules.ids():
			assert_str(marks[id]).is_equal(DialRules.OK)
		assert_bool(rules.all_locked()).is_true()
		assert_int(rules.last_locked.size()).is_equal(3)


func test_start_is_never_the_answer() -> void:
	for entry in data.handoffs:
		var rules := DialRules.new(entry["config"])
		for id in rules.ids():
			assert_str(rules.mark(id)).is_not_equal(DialRules.OK)
			assert_bool(rules.is_locked(id)).is_false()


func test_reveal_locks_the_rest_and_reports_their_settings() -> void:
	var rules := _rules("cookie_to_oven")
	rules.set_value("bowl_every", 2)
	rules.test()
	assert_array(rules.last_locked).contains_exactly([2])
	var revealed := rules.reveal()
	assert_array(revealed).contains_exactly([0, 1])
	assert_bool(rules.all_locked()).is_true()
	assert_int(rules.value("belt_speed")).is_equal(3)


func test_locked_indices_lock_dials_at_their_answers() -> void:
	var rules := _rules("oven_to_packaging", {"locked_indices": [0, 2]})
	assert_array(rules.locked_ids()).contains_exactly(["chute_1", "chute_3"])
	assert_str(str(rules.value("chute_1"))).is_equal("rooftop_basket")
	assert_str(rules.first_unlocked()).is_equal("chute_2")


func test_value_text_uses_labels_units_and_singulars() -> void:
	var rules := _rules("fortune_to_oven")
	rules.set_value("dry", 1)
	assert_str(rules.value_text("dry")).is_equal("1 tick")
	rules.set_value("dry", 2)
	assert_str(rules.value_text("dry")).is_equal("2 ticks")
	rules.set_value("start_tick", 3)
	assert_str(rules.value_text("start_tick")).is_equal("3")
	var belt := _rules("cookie_to_oven")
	assert_str(belt.value_text("belt_speed")).is_equal("1 cm per second")
	var chutes := _rules("oven_to_packaging")
	assert_str(chutes.value_text("chute_1")).is_equal("Penguin's shed box")


func test_beats_answers_hit_the_targets() -> void:
	var config: Dictionary = data.handoff("fortune_to_oven")["config"]
	var preview: Dictionary = config["preview"]
	var rules := DialRules.new(config)
	var roles: Dictionary = preview["roles"]
	var landing := DialRules.beats_landing(
		int(rules.answer_value(roles["start"])),
		int(rules.answer_value(roles["dry"])),
		int(rules.answer_value(roles["every"])),
		int(preview["chute_ticks"]),
		int(preview["ticks"])
	)
	var targets: Array[int] = []
	for t: Variant in preview["targets"]:
		targets.append(int(t))
	assert_array(landing).contains_exactly(targets)


func test_beats_landing_with_wrong_settings_misses() -> void:
	assert_array(DialRules.beats_landing(0, 0, 4, 2, 12)).contains_exactly([2, 6, 10])
	assert_array(DialRules.beats_landing(3, 3, 6, 2, 12)).contains_exactly([8])
	assert_array(DialRules.beats_landing(0, 1, 0, 2, 12)).is_empty()
