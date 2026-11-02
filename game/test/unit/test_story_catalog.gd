# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## StoryCatalog: loading the real files, indexing by where and when, placeholder
## substitution and next_unseen ordering (with a small catalog built in the test).

const STORY_DIR := "res://data/story/"
const NOT_PIECE_FILES := ["schema.json", "side_puzzles.json"]


func _small() -> StoryCatalog:
	var catalog := StoryCatalog.new()
	catalog.add_file(
		{
			"schema_version": 1,
			"pieces":
			[
				{"id": "t.a", "speaker": "Gnu", "kind": "note", "lines": ["First {part}"], "where": "town", "when": "first_visit"},
				{"id": "t.b", "speaker": "Gnu", "kind": "note", "lines": ["Second"], "where": "town", "when": "first_visit"},
				{"id": "t.c", "speaker": "Crab", "kind": "dialogue", "lines": ["Third"], "where": "town", "when": "interval", "group": "g"},
				{"id": "t.d", "speaker": "Crab", "kind": "dialogue", "lines": ["Fourth"], "where": "town", "when": "interval", "group": "g"},
				{"id": "s.a", "speaker": "Gnu", "kind": "sign", "lines": ["Shop"], "where": "shop:counter", "when": "always"},
			]
		}
	)
	return catalog


func _raw_pieces(file: String) -> Array:
	return JsonFile.read(STORY_DIR + file).get("pieces", [])


# --- Loading and indexing ---------------------------------------------------


func test_every_listed_file_loads_and_every_piece_is_indexed() -> void:
	var expected := 0
	for path in StoryCatalog.FILES:
		assert_bool(FileAccess.file_exists(path)).override_failure_message("missing " + path).is_true()
		expected += JsonFile.read(path).get("pieces", []).size()
	assert_int(expected).is_greater(40)
	assert_int(StoryCatalog.load_all().piece_count()).is_equal(expected)


func test_no_piece_file_is_left_out_of_the_list() -> void:
	var listed: Array = []
	for path in StoryCatalog.FILES:
		listed.append(path.get_file())
	var dir := DirAccess.open(STORY_DIR)
	assert_object(dir).is_not_null()
	for file in dir.get_files():
		if file.ends_with(".json") and not NOT_PIECE_FILES.has(file):
			assert_bool(listed.has(file)).override_failure_message("%s is not in StoryCatalog.FILES" % file).is_true()


func test_pieces_are_found_by_where_and_when() -> void:
	var catalog := StoryCatalog.load_all()
	assert_int(catalog.pieces_for("start_screen", "always").size()).is_equal(1)
	assert_int(catalog.pieces_for("loading", "always").size()).is_equal(3)
	assert_int(catalog.pieces_for("machine_view:oven", "idle").size()).is_equal(3)
	assert_int(catalog.pieces_for("merge_celebration", "merged").size()).is_equal(8)
	assert_int(catalog.pieces_for("merge_celebration").size()).is_greater(8)
	assert_int(catalog.pieces_for("town", "interval").size()).is_equal(6)
	assert_int(catalog.pieces_for("lucky_word_entry", "machine_running:crew").size()).is_equal(1)
	assert_int(catalog.pieces_for("puzzle:cookie_machine/logic", "first_visit").size()).is_equal(1)
	assert_array(catalog.pieces_for("nowhere")).is_empty()
	assert_array(catalog.pieces_for("town", "never")).is_empty()


func test_finale_and_other_late_triggers_are_served() -> void:
	var catalog := StoryCatalog.load_all()
	assert_int(catalog.pieces_for("lucky_word_entry", "finale_open").size()).is_equal(1)
	assert_int(catalog.pieces_for("town", "finale_open").size()).is_equal(1)
	assert_int(catalog.pieces_for("town", "line_running").size()).is_equal(1)
	assert_int(catalog.pieces_for("big_screen", "line_running").size()).is_equal(1)
	for when in ["finale_open", "note_found", "handoff_solved", "line_running"]:
		var found := catalog.pieces_for("finale_archive", when)
		assert_int(found.size()).override_failure_message("finale_archive / " + when).is_greater_equal(1)
		assert_str(found[0]["speaker"]).is_equal("Elephant")


func test_pieces_by_speaker_covers_the_gnu_notes_in_town_and_shop() -> void:
	var catalog := StoryCatalog.load_all()
	var town := catalog.pieces_by_speaker("Gnu", "town")
	var shop := catalog.pieces_by_speaker("Gnu", "shop")
	var expected := 0
	for raw: Dictionary in _raw_pieces("gnu.json"):
		if str(raw["id"]).begins_with("gnu.town."):
			expected += 1
	assert_int(expected).is_greater(0)
	assert_int(town.size() + shop.size()).is_equal(expected)
	for piece: Dictionary in town:
		assert_str(piece["id"]).starts_with("gnu.town.")
	var shop_ids := 0
	for raw: Dictionary in _raw_pieces("gnu.json"):
		if raw["where"] == "shop" or str(raw["where"]).begins_with("shop:"):
			shop_ids += 1
	assert_int(shop.size()).is_equal(shop_ids)


func test_duplicate_and_idless_pieces_are_ignored() -> void:
	var catalog := _small()
	assert_bool(catalog.add_piece({"id": "t.a", "lines": ["again"], "where": "town"})).is_false()
	assert_bool(catalog.add_piece({"lines": ["no id"], "where": "town"})).is_false()
	assert_int(catalog.piece_count()).is_equal(5)


# --- Placeholders -----------------------------------------------------------


func test_placeholders_are_substituted() -> void:
	var catalog := _small()
	assert_str(catalog.get_piece("t.a", {"part": "Wiring"})["lines"][0]).is_equal("First Wiring")
	assert_str(catalog.get_piece("t.a", {"part": "Wiring"})["text"]).is_equal("First Wiring")
	# Unknown placeholders stay visible rather than vanish.
	assert_str(catalog.get_piece("t.a")["lines"][0]).is_equal("First {part}")
	assert_str(StoryCatalog.substitute("{name} at {machine}", {"name": "Tux", "machine": "Oven"})).is_equal("Tux at Oven")
	assert_str(StoryCatalog.substitute("See {repo_url}", {})).is_equal("See " + Ids.REPO_URL)


func test_real_pieces_use_machine_part_and_repo_url() -> void:
	var catalog := StoryCatalog.load_all()
	var running := catalog.get_piece("red_panda.machine_running", {"machine": "Oven"})
	assert_str(running["lines"][0]).contains("The Oven is running")
	var merged := catalog.get_piece("crab.merged.2", {"part": "Wiring"})
	assert_str(merged["lines"][1]).is_equal("The Wiring works again.")
	var about := catalog.get_piece("ui.settings.about")
	assert_str(about["lines"][2]).is_equal("Source code: " + Ids.REPO_URL)


func test_with_full_context_no_placeholder_is_left_anywhere() -> void:
	var catalog := StoryCatalog.load_all()
	var context := {"name": "Tux", "machine": "Fortune Machine", "part": "Wiring"}
	for file in StoryCatalog.FILES:
		for raw: Dictionary in _raw_pieces(file.get_file()):
			var piece := catalog.get_piece(raw["id"], context)
			assert_bool(str(piece["text"]).contains("{")).override_failure_message(raw["id"]).is_false()
			assert_bool(str(piece).contains("dev_note")).is_false()


func test_returned_pieces_are_copies() -> void:
	var catalog := _small()
	var piece := catalog.get_piece("t.b")
	piece["lines"].append("scribble")
	piece["text"] = "scribble"
	assert_array(catalog.get_piece("t.b")["lines"]).contains_exactly(["Second"])


# --- next_unseen, unseen, pick ------------------------------------------------


func test_next_unseen_walks_the_data_order() -> void:
	var catalog := _small()
	var seen: Array = []
	assert_str(catalog.next_unseen("town", "first_visit", seen)["id"]).is_equal("t.a")
	seen.append("t.a")
	assert_str(catalog.next_unseen("town", "first_visit", seen)["id"]).is_equal("t.b")
	seen.append("t.b")
	assert_dict(catalog.next_unseen("town", "first_visit", seen)).is_empty()
	# Other triggers at the same place are untouched by what was seen.
	assert_str(catalog.next_unseen("town", "interval", seen)["id"]).is_equal("t.c")
	# A later piece is not skipped to when an earlier one is unseen.
	assert_str(catalog.next_unseen("town", "", ["t.b"])["id"]).is_equal("t.a")


func test_next_unseen_steps_through_a_group_in_turn() -> void:
	var catalog := _small()
	assert_str(catalog.next_unseen("town", "interval", [])["id"]).is_equal("t.c")
	assert_str(catalog.next_unseen("town", "interval", ["t.c"])["id"]).is_equal("t.d")
	assert_dict(catalog.next_unseen("town", "interval", ["t.c", "t.d"])).is_empty()


func test_unseen_returns_a_sequence_in_order() -> void:
	var catalog := StoryCatalog.load_all()
	var welcome := catalog.unseen("lucky_word_entry", "first_visit", [])
	assert_int(welcome.size()).is_equal(2)
	assert_str(welcome[0]["id"]).is_equal("red_panda.welcome.1")
	assert_str(welcome[1]["id"]).is_equal("red_panda.welcome.2")
	assert_int(catalog.unseen("lucky_word_entry", "first_visit", ["red_panda.welcome.1"]).size()).is_equal(1)


func test_pick_chooses_within_the_group() -> void:
	var catalog := StoryCatalog.load_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ids: Dictionary = {}
	for i in 60:
		var piece := catalog.pick("merge_celebration", "merged", rng)
		assert_str(piece["group"]).is_equal("crab.merged")
		ids[piece["id"]] = true
	assert_int(ids.size()).is_greater(3)
	assert_dict(catalog.pick("nowhere", "", rng)).is_empty()
