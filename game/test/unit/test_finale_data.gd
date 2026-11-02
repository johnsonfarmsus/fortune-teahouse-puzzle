# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## The three finale data files: shape, references and uniqueness.

var data: FinaleData


func before_test() -> void:
	data = FinaleData.new()


func test_the_shipped_data_has_no_errors() -> void:
	assert_array(data.errors()).is_empty()


func test_each_handoff_has_setting_indices_0_to_2_exactly() -> void:
	assert_int(data.handoffs.size()).is_equal(3)
	for entry in data.handoffs:
		var indices: Array[int] = []
		for dial: Dictionary in entry["config"]["dials"]:
			indices.append(int(dial["setting_index"]))
		indices.sort()
		assert_array(indices).contains_exactly([0, 1, 2])


func test_needs_name_real_notes() -> void:
	for entry in data.handoffs:
		assert_int(entry["needs"].size()).is_equal(2)
		for need: String in entry["needs"]:
			assert_bool(data.note(need).is_empty()).is_false()
	assert_array(data.handoff("cookie_to_oven")["needs"]).contains_exactly(["cookie_machine", "oven"])
	assert_array(data.handoff("fortune_to_oven")["needs"]).contains_exactly(["fortune_machine", "oven"])
	assert_array(data.handoff("oven_to_packaging")["needs"]).contains_exactly(["oven", "gopher"])


func test_gnu_note_codes_are_six_unique_and_well_formed() -> void:
	assert_int(data.gnu_notes.size()).is_equal(6)
	assert_int(data.needed).is_equal(4)
	var regex := RegEx.create_from_string(FinaleData.CODE_PATTERN)
	var seen: Array[String] = []
	for entry in data.gnu_notes:
		var code := str(entry["code"])
		assert_object(regex.search(code)).override_failure_message("bad code " + code).is_not_null()
		assert_bool(seen.has(code)).is_false()
		seen.append(code)
		assert_str(str(entry["text"])).ends_with(code)


func test_codes_normalise_to_the_servers_form() -> void:
	assert_str(FinaleData.normalise_code("kettle 27")).is_equal("KETTLE27")
	assert_str(FinaleData.normalise_code(" Gull-wing 41.")).is_equal("GULLWING41")
	assert_str(str(data.gnu_note_for_code("dripcoffee08")["id"])).is_equal("note_3")
	assert_bool(data.gnu_note_for_code("KETTLE 28").is_empty()).is_true()
	assert_bool(data.gnu_note_for_code("").is_empty()).is_true()
	var server: Array[String] = []
	for entry in data.gnu_notes:
		server.append(FinaleData.normalise_code(str(entry["code"])))
	assert_array(server).contains_exactly(["KETTLE27", "GULLWING41", "DRIPCOFFEE08", "CROSSWIND63", "INKBLOT19", "SALTWATER52"])


func test_the_21_lucky_and_handoff_words_are_unique() -> void:
	var words: Array[String] = []
	for machine in Ids.MACHINES:
		for clue: Dictionary in PuzzleData.get_clues(machine):
			words.append(LuckyWords.normalise(str(clue["lucky_word"])))
	assert_int(words.size()).is_equal(18)
	for word in data.handoff_words():
		words.append(LuckyWords.normalise(word))
	assert_int(words.size()).is_equal(21)
	var unique: Dictionary = {}
	for word in words:
		unique[word] = true
	assert_int(unique.size()).is_equal(21)


func test_handoff_words_find_their_notes() -> void:
	assert_str(str(data.note_for_word(" goldenround ")["id"])).is_equal("oven")
	assert_str(str(data.note_for_word("BATTERBOWL")["id"])).is_equal("cookie_machine")
	assert_str(str(data.note_for_word("paper-chute")["id"])).is_equal("fortune_machine")
	assert_bool(data.note_for_word("").is_empty()).is_true()
	assert_bool(data.note_for_word("TUX").is_empty()).is_true()
	assert_bool(bool(data.note("gopher")["free"])).is_true()
	assert_str(str(data.note("gopher")["handoff_word"])).is_equal("")


func test_readme_has_six_valid_triggers_and_a_closing() -> void:
	var triggers := data.readme_triggers()
	assert_int(triggers.size()).is_equal(6)
	var machines := 0
	var handoffs := 0
	for trigger in triggers:
		if trigger.has("machine_runs"):
			assert_bool(Ids.MACHINES.has(str(trigger["machine_runs"]))).is_true()
			machines += 1
		else:
			assert_bool(data.handoff_ids().has(str(trigger["handoff_connected"]))).is_true()
			handoffs += 1
	assert_int(machines).is_equal(3)
	assert_int(handoffs).is_equal(3)
	assert_str(str(data.readme["closing"]["heading"])).is_equal("Maintainers")


func test_every_twin_puts_the_correct_answer_among_its_choices() -> void:
	for entry in data.gnu_notes:
		var config: Dictionary = entry["twin"]["config"]
		assert_int(config["choices"].size()).is_equal(3)
		assert_int(int(config["correct"])).is_between(0, 2)
		assert_str(str(entry["twin"]["speaker"])).is_equal(str(config["speaker"]))


func test_validation_catches_bad_data() -> void:
	var broken := FinaleData.new()
	broken.handoffs[0]["needs"] = ["nobody"]
	broken.gnu_notes[0]["code"] = "kettle27"
	broken.gnu_notes[1]["code"] = broken.gnu_notes[2]["code"]
	broken.handoffs[1]["config"]["dials"][0]["start"] = 2  # print_every 4 is the answer
	var problems := "\n".join(broken.errors())
	assert_str(problems).contains("needs a note that does not exist")
	assert_str(problems).contains("not a word and two digits")
	assert_str(problems).contains("code repeated")
	assert_str(problems).contains("start must not be the answer")


func test_row_status_and_clock_helpers() -> void:
	var none: Array[String] = []
	assert_str(FinaleData.row_status({"status": "not_started"}, none)).is_equal("not started")
	assert_str(FinaleData.row_status({"status": "in_progress", "settings_solved": 2, "settings_total": 3}, none)).is_equal("2 of 3 settings")
	assert_str(FinaleData.row_status({"status": "connected"}, none)).is_equal("connected")
	assert_str(FinaleData.row_status({"status": "locked"}, none)).is_equal("locked")
	assert_str(FinaleData.row_status({"status": "waiting"}, ["Fortune Machine", "Oven"])).is_equal("waiting for the Fortune Machine and Oven")
	assert_str(FinaleData.format_clock("2027-10-30T01:00:00Z", -7 * 60)).is_equal("6:00 pm")
	assert_str(FinaleData.format_clock("2027-10-30T00:05:00Z", 0)).is_equal("12:05 am")
	assert_str(FinaleData.format_clock("2027-10-30T12:30:00Z", 0)).is_equal("12:30 pm")
	assert_str(FinaleData.format_clock("soon", 0)).is_equal("")


func test_no_gnu_note_code_equals_a_lucky_word_or_handoff_word() -> void:
	var words: Array[String] = []
	for machine in Ids.MACHINES:
		for clue: Dictionary in PuzzleData.get_clues(machine):
			words.append(LuckyWords.normalise(str(clue["lucky_word"])))
	for word in data.handoff_words():
		words.append(LuckyWords.normalise(word))
	for entry in data.gnu_notes:
		var code := FinaleData.normalise_code(str(entry["code"]))
		assert_bool(words.has(code)).override_failure_message("code %s collides with a word" % code).is_false()
		# Typed on the Lucky word keypad it must not be a lucky word or a handoff word either.
		assert_bool(PuzzleData.lookup_lucky_word(code).is_empty()).is_true()
		assert_bool(data.note_for_word(code).is_empty()).is_true()
