# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## What the story remembers about a player: seen ids and the last state shown.


func test_seen_story_round_trips_through_json() -> void:
	var state := PlayerState.new()
	state.ensure_device_id()
	state.mark_story_seen("gnu.town.pier_bottle")
	state.mark_story_seen("visit:machine_view:oven")
	state.mark_story_seen("gnu.town.pier_bottle")
	state.story_state["lucky_word_entry"] = "has_crew"
	assert_array(state.seen_story).contains_exactly(["gnu.town.pier_bottle", "visit:machine_view:oven"])
	var parser := JSON.new()
	assert_int(parser.parse(JSON.stringify(state.to_dict()))).is_equal(OK)
	var copy := PlayerState.from_dict(parser.data)
	assert_array(copy.seen_story).contains_exactly(["gnu.town.pier_bottle", "visit:machine_view:oven"])
	assert_bool(copy.has_seen_story("gnu.town.pier_bottle")).is_true()
	assert_bool(copy.has_seen_story("gnu.town.shop_door")).is_false()
	assert_str(copy.story_state["lucky_word_entry"]).is_equal("has_crew")
	assert_dict(copy.to_dict()).is_equal(state.to_dict())


func test_an_old_save_without_story_fields_loads_empty() -> void:
	var copy := PlayerState.from_dict({"device_id": "abc", "crew": "oven"})
	assert_array(copy.seen_story).is_empty()
	assert_dict(copy.story_state).is_empty()
	assert_str(copy.crew).is_equal("oven")
