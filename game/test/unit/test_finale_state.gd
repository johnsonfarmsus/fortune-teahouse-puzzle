# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## FinaleState: round trip through user://, idempotent adds, reset.

const PATH := "user://test_finale_state.json"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_round_trip() -> void:
	var state := FinaleState.new(PATH)
	state.grant_note("oven")
	state.add_setting("cookie_to_oven", 1)
	state.add_setting("cookie_to_oven", 0)
	state.add_gnu_note("note_3", "DRIPCOFFEE08")
	state.set_cache({"open": true, "handoffs": []})
	var again := FinaleState.new(PATH)
	assert_array(again.notes_held).contains_exactly(["oven"])
	assert_array(again.settings_for("cookie_to_oven")).contains_exactly([1, 0])
	assert_array(again.gnu_notes).contains_exactly(["note_3"])
	assert_bool(bool(again.cache["open"])).is_true()
	assert_int(again.queue.size()).is_equal(3)
	assert_str(str(again.queue[2]["code"])).is_equal("DRIPCOFFEE08")
	assert_int(int(again.queue[0]["setting_index"])).is_equal(1)
	var saved := JsonFile.read(PATH)
	for key in ["version", "notes_held", "settings", "gnu_notes", "queue", "cache"]:
		assert_bool(saved.has(key)).override_failure_message("missing " + key).is_true()


func test_adds_are_idempotent() -> void:
	var state := FinaleState.new("")
	assert_bool(state.grant_note("oven")).is_true()
	assert_bool(state.grant_note("oven")).is_false()
	assert_bool(state.add_setting("oven_to_packaging", 2)).is_true()
	assert_bool(state.add_setting("oven_to_packaging", 2)).is_false()
	assert_bool(state.add_gnu_note("note_1", "KETTLE27")).is_true()
	assert_bool(state.add_gnu_note("note_1", "KETTLE27")).is_false()
	assert_array(state.notes_held).contains_exactly(["oven"])
	assert_int(state.queue.size()).is_equal(2)


func test_queue_added_fires_only_for_new_writes() -> void:
	var state := FinaleState.new("")
	var count := [0]
	state.queue_added.connect(func() -> void: count[0] += 1)
	state.add_setting("cookie_to_oven", 0)
	state.add_setting("cookie_to_oven", 0)
	state.add_gnu_note("note_2", "GULLWING41")
	assert_int(count[0]).is_equal(2)


func test_reset_clears_everything_on_disk_too() -> void:
	var state := FinaleState.new(PATH)
	state.grant_note("cookie_machine")
	state.add_setting("fortune_to_oven", 2)
	state.set_cache({"open": true})
	state.reset()
	assert_bool(state.notes_held.is_empty()).is_true()
	assert_bool(state.settings.is_empty()).is_true()
	assert_bool(state.queue.is_empty()).is_true()
	assert_bool(state.cache.is_empty()).is_true()
	var again := FinaleState.new(PATH)
	assert_bool(again.notes_held.is_empty()).is_true()
	assert_bool(again.queue.is_empty()).is_true()


func test_a_missing_or_bad_file_starts_empty() -> void:
	var state := FinaleState.new(PATH)
	assert_bool(state.notes_held.is_empty()).is_true()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	assert_bool(FinaleState.new(PATH).queue.is_empty()).is_true()


func test_an_empty_path_never_touches_disk() -> void:
	var state := FinaleState.new("")
	state.grant_note("oven")
	assert_bool(FileAccess.file_exists(PATH)).is_false()
