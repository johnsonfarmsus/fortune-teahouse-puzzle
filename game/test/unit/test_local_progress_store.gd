# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite

const TEST_PATH := "user://test_progress.json"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_starts_with_all_six_parts_at_zero() -> void:
	var store := LocalProgressStore.new(TEST_PATH)
	var progress := store.get_crew_progress("cookie_machine")
	assert_int(progress.size()).is_equal(6)
	for part in Ids.PARTS:
		assert_int(progress[part]).is_equal(0)


func test_round_trip_via_new_instance() -> void:
	var store := LocalProgressStore.new(TEST_PATH)
	store.set_display_name("dev1", "Tux")
	store.join_crew("dev1", "cookie_machine")
	store.record_part_solved("cookie_machine", "logic", "dev1", true)
	var again := LocalProgressStore.new(TEST_PATH)
	assert_int(again.get_crew_progress("cookie_machine")["logic"]).is_equal(1)
	assert_array(again.get_contributors("cookie_machine")).contains_exactly(["Tux"])


func test_revealed_counts_for_progress_but_adds_no_contributor() -> void:
	var store := LocalProgressStore.new(TEST_PATH)
	store.set_display_name("dev1", "Tux")
	store.record_part_solved("oven", "logic", "dev1", false)
	assert_int(store.get_crew_progress("oven")["logic"]).is_equal(1)
	assert_array(store.get_contributors("oven")).is_empty()
	store.record_part_solved("oven", "logic", "dev1", true)
	assert_array(store.get_contributors("oven")).contains_exactly(["Tux"])
	assert_int(store.get_crew_progress("oven")["logic"]).is_equal(1)


func test_anonymous_shows_once() -> void:
	var store := LocalProgressStore.new(TEST_PATH)
	store.record_part_solved("oven", "logic", "dev1", true)
	store.record_part_solved("oven", "wiring", "dev2", true)
	store.set_display_name("dev3", "Gnu")
	store.record_part_solved("oven", "word", "dev3", true)
	assert_array(store.get_contributors("oven")).contains_exactly(["Anonymous", "Gnu"])


func test_duplicates_are_ignored() -> void:
	var store := LocalProgressStore.new(TEST_PATH)
	store.record_part_solved("oven", "logic", "dev1", true)
	store.record_part_solved("oven", "logic", "dev1", true)
	assert_int(store.get_crew_progress("oven")["logic"]).is_equal(1)
	assert_int(store.solves.size()).is_equal(1)


func test_progress_changed_is_emitted() -> void:
	var store := LocalProgressStore.new(TEST_PATH)
	var seen: Array = []
	store.progress_changed.connect(func(machine: String) -> void: seen.append(machine))
	store.record_part_solved("oven", "logic", "dev1", true)
	assert_array(seen).contains_exactly(["oven"])


func test_remote_store_delegates_and_queues() -> void:
	var local := LocalProgressStore.new(TEST_PATH)
	var remote := RemoteProgressStore.new("https://example.invalid", local)
	remote.join_crew("dev1", "oven")
	remote.record_part_solved("oven", "logic", "dev1", true)
	assert_int(remote.get_crew_progress("oven")["logic"]).is_equal(1)
	assert_int(remote.flush()).is_equal(2)
	assert_bool(remote.is_online()).is_false()
