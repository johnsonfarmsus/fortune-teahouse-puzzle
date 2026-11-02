# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite


func test_every_machine_is_well_formed() -> void:
	var catalog := PuzzleCatalog.load_all()
	for machine in Ids.MACHINES:
		assert_bool(catalog.has_machine(machine)).override_failure_message("missing " + machine).is_true()
		var domain := catalog.get_domain(machine)
		assert_int(domain["items"].size()).is_equal(5)
		assert_int(domain["positions"].size()).is_equal(5)
		assert_str(domain["position_noun"]).is_not_empty()
		assert_int(catalog.get_clues(machine).size()).is_equal(6)
		var answer := catalog.get_answer(machine)
		var positions: Array = answer.values()
		positions.sort()
		assert_array(positions).is_equal([1, 2, 3, 4, 5])
		for item: String in domain["items"]:
			assert_bool(answer.has(item)).is_true()
			assert_str(domain["item_names"][item]).is_not_empty()


func test_clue_facts_refer_to_known_items() -> void:
	var catalog := PuzzleCatalog.load_all()
	for machine in Ids.MACHINES:
		var items: Array = catalog.get_domain(machine)["items"]
		for clue: Dictionary in catalog.get_clues(machine):
			assert_bool(items.has(clue["fact"]["a"])).is_true()
			if clue["fact"]["kind"] == "offset":
				assert_bool(items.has(clue["fact"]["b"])).is_true()
			assert_str(clue["fortune_text"]).is_not_empty()
			assert_bool(clue["fortune_text"].contains("Lucky word")).is_false()


func test_lucky_words_are_unique_across_files() -> void:
	var seen: Dictionary = {}
	var catalog := PuzzleCatalog.load_all()
	for machine in Ids.MACHINES:
		for clue: Dictionary in catalog.get_clues(machine):
			var word := LuckyWords.normalise(clue["lucky_word"])
			assert_bool(seen.has(word)).override_failure_message("duplicate " + word).is_false()
			seen[word] = true
			var hit := catalog.lookup_lucky_word(word)
			assert_str(hit["machine"]).is_equal(machine)
			assert_str(hit["clue_id"]).is_equal(clue["id"])
	assert_int(seen.size()).is_equal(18)


func test_six_parts_per_machine_in_order() -> void:
	var catalog := PuzzleCatalog.load_all()
	for machine in Ids.MACHINES:
		var parts := catalog.get_parts(machine)
		assert_int(parts.size()).is_equal(6)
		for i in 6:
			assert_str(parts[i]["part"]).is_equal(Ids.PARTS[i])


func test_matching_config_has_only_collected_clues() -> void:
	var catalog := PuzzleCatalog.load_all()
	var first: String = catalog.get_clues("cookie_machine")[0]["id"]
	var config := catalog.matching_config("cookie_machine", [first, "oven.poem"])
	assert_int(config["clues"].size()).is_equal(1)
	assert_int(config["total_clues"]).is_equal(6)
	assert_int(config["threshold"]).is_equal(4)
	assert_str(config["machine"]).is_equal("cookie_machine")


func test_json_floats_become_ints() -> void:
	var catalog := PuzzleCatalog.new()
	catalog.add_machine(
		{
			"machine": "oven",
			"domain": {"items": ["a"], "positions": ["Zone 1"], "position_noun": "zone"},
			"answer": {"a": 1.0},
			"clues": [{"id": "oven.x", "lucky_word": "X", "fact": {"kind": "position", "a": "a", "value": 1.0}}],
		}
	)
	assert_bool(typeof(catalog.get_answer("oven")["a"]) == TYPE_INT).is_true()
	assert_bool(typeof(catalog.get_clue("oven.x")["fact"]["value"]) == TYPE_INT).is_true()
