# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## The adventure layer as scenes: layout, walking and doors, feedback on every
## tap, the cutter chain played through the view and its close-ups, the batter
## shelf, the Cookie Machine rig, the dialogue bar and the legacy switch.

const PROGRESS_PATH := "user://test_adventure_progress.json"
const MACHINE := "cookie_machine"

var view: AdventureView


func before_test() -> void:
	_cleanup()
	GameState.persist = false
	Finale.set_client(null)
	Finale.set_state(FinaleState.new(""))
	GameState.player = PlayerState.new()
	GameState.player.ensure_device_id()
	Progress.set_store(LocalProgressStore.new(PROGRESS_PATH))
	Adventure.use_memory_state()
	DebugSettings.forced = 0
	Audio.unlocked = false
	Router.clear()


func after_test() -> void:
	Router.clear()
	DebugSettings.forced = -1
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(PROGRESS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))


func _view() -> AdventureView:
	view = auto_free(load(Paths.ADVENTURE_VIEW).instantiate())
	view.instant_transitions = true
	add_child(view)
	await get_tree().process_frame
	return view


## Walks to a thing and taps it (the walk is finished at once).
func _tap_thing(id: String) -> void:
	var t := Adventure.rooms.thing(view.room_id, id)
	assert_bool(t.is_empty()).override_failure_message("no %s in %s" % [id, view.room_id]).is_false()
	view.room.input_enabled = true
	view.room.tap_world(RoomGraph.rect_px(t).get_center())
	view.room.finish_walk()


func _go(room_id: String) -> void:
	var spawns: Dictionary = Adventure.rooms.room(room_id)["spawns"]
	view._enter(room_id, Adventure.rooms.spawn(room_id, str(spawns.keys()[0])))


func _drop_on(id: String, item: String) -> void:
	var t := Adventure.rooms.thing(view.room_id, id)
	assert_bool(view.drop_item_at(view.room_to_screen(RoomGraph.rect_px(t).get_center()), item)).is_true()
	view.room.finish_walk()


func _close_dialogue() -> void:
	view.dialogue().skip_all()


func _all_text() -> String:
	var out := ""
	var d := view.dialogue()
	while d.is_open():
		out += d.current_speaker() + ": " + d.current_text() + "\n"
		d.advance()
		d.advance()
	return out


# --- Main and layout ----------------------------------------------------------------


func test_main_starts_into_the_adventure_in_the_teahouse() -> void:
	var main: Node = auto_free(load(Paths.MAIN).instantiate())
	add_child(main)
	await get_tree().process_frame
	main.start_screen.started.emit()
	await get_tree().process_frame
	assert_object(main.adventure).is_not_null()
	assert_str(main.adventure.room_id).is_equal("teahouse")
	assert_bool(main.hud.visible).is_false()
	assert_bool(Audio.unlocked).is_true()
	# A new player still meets Red Panda's lucky-word entry first.
	assert_int(Router.depth()).is_equal(1)


func test_legacy_setting_brings_back_the_old_town() -> void:
	DebugSettings.forced = 1
	var main: Node = auto_free(load(Paths.MAIN).instantiate())
	add_child(main)
	await get_tree().process_frame
	main.start_screen.started.emit()
	await get_tree().process_frame
	assert_str(Router.current_place().name).is_equal("Town")
	assert_object(main.adventure).is_null()
	assert_bool(ProjectSettings.has_setting(DebugSettings.SETTING)).is_true()
	assert_bool(DebugSettings.project_default()).is_false()


func test_settings_has_the_legacy_toggle() -> void:
	var screen := Router.push(Paths.SETTINGS)
	await get_tree().process_frame
	var toggle := screen.find_child("LegacyScreens", true, false) as CheckButton
	assert_object(toggle).is_not_null()
	assert_bool(toggle.button_pressed).is_false()
	assert_float(toggle.custom_minimum_size.y).is_greater_equal(44.0)


func test_room_view_is_integer_scaled_with_bars_above_and_below() -> void:
	await _view()
	var vis := view.get_viewport_rect().size
	var device := view.device_scale()
	var k := view.pixel_scale * device
	assert_float(k - roundf(k)).is_equal_approx(0.0, 0.001)
	assert_float(view.frame_rect.size.x).is_equal_approx(176.0 * view.pixel_scale, 0.01)
	assert_float(view.frame_rect.size.y).is_equal_approx(320.0 * view.pixel_scale, 0.01)
	assert_bool(Rect2(Vector2.ZERO, vis).encloses(view.frame_rect)).is_true()
	assert_float(view.inventory_bar().position.y).is_less(view.frame_rect.position.y + 1)
	assert_float(view.dialogue().position.y).is_greater_equal(view.frame_rect.end.y - 1)
	var frame := view.find_child("RoomFrame", true, false) as SubViewportContainer
	assert_int(frame.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	var vp := view.find_child("RoomViewport", true, false) as SubViewport
	assert_object(vp.size).is_equal(Vector2i(176, 320))


# --- Walking, doors, feedback -------------------------------------------------------


func test_every_tap_answers_at_once_with_a_sound_and_a_ring() -> void:
	await _view()
	Audio.played.clear()
	view.room.tap_world(Vector2(40, 200))
	assert_bool(Audio.played.is_empty()).is_false()
	assert_str(Audio.last_played()).is_equal("tap")
	var rings := view.room.get_children().filter(func(n: Node) -> bool: return n is AnimatedSprite2D and n.z_index == 40)
	assert_int(rings.size()).is_greater_equal(1)
	assert_bool(view.room.is_walking()).is_true()
	view.room.tap_world(RoomGraph.rect_px(Adventure.rooms.thing("teahouse", "kettle")).get_center())
	assert_str(Audio.last_played()).is_equal("select")


func test_player_walks_with_animation_frames() -> void:
	await _view()
	var player := view.room.player
	assert_int(player.sprite_frames.get_frame_count("walk_down")).is_between(2, 4)
	view.room.tap_world(Vector2(5 * 16 + 8, 16 * 16 + 8))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(player.animation).starts_with("walk_")
	view.room.finish_walk()
	assert_object(view.room.player_cell()).is_equal(Vector2i(5, 16))
	assert_str(player.animation).starts_with("idle_")


func test_doors_and_edges_lead_between_rooms_and_back() -> void:
	await _view()
	view.room.walk_to(Vector2i(5, 19))
	view.room.finish_walk()
	assert_str(view.room_id).is_equal("square")
	# The square is taller than the screen, so the camera has room to follow.
	assert_int(view.room.camera.limit_bottom).is_greater(320)
	view.room.walk_to(Vector2i(10, 12))
	view.room.finish_walk()
	assert_str(view.room_id).is_equal("pier")
	view.room.walk_to(Vector2i(0, 12))
	view.room.finish_walk()
	assert_str(view.room_id).is_equal("square")
	view.room.walk_to(Vector2i(5, 2))
	view.room.finish_walk()
	assert_str(view.room_id).is_equal("teahouse")
	assert_str(Adventure.room_id).is_equal("teahouse")


func test_characters_idle_and_talk_with_portraits() -> void:
	await _view()
	var red_panda := view.room.thing_node("red_panda") as AnimatedSprite2D
	assert_bool(red_panda.is_playing()).is_true()
	assert_int(red_panda.sprite_frames.get_frame_count(red_panda.animation)).is_greater_equal(2)
	_tap_thing("red_panda")
	var d := view.dialogue()
	assert_bool(d.is_open()).is_true()
	assert_str(d.current_speaker()).is_equal("Red Panda")
	assert_object(d.portrait_texture()).is_not_null()
	assert_str(Audio.played.back()).starts_with("babble.")
	# Red Panda's help is the first chain step's nudge.
	assert_str(d.current_text()).contains("cutter")


# --- The cutter chain through the view ----------------------------------------------


func test_the_cutter_chain_end_to_end_with_misdirects_and_the_decoy() -> void:
	await _view()
	# 1. The shop: the sticky label on the cutter.
	_go("shop")
	_tap_thing("cutter")
	assert_str(view.dialogue().current_speaker()).is_equal("Gnu")
	assert_str(_all_text()).contains("sharpening")
	# 2. Penguin: the gnu mailed it; here is a spanner.
	_go("workshop")
	_tap_thing("penguin")
	assert_str(_all_text()).contains("depot")
	assert_array(view.inventory_bar().item_ids()).contains(["spanner"])
	# Misdirect: the scrapyard die, and its tell at the cutter.
	_go("scrapyard")
	_tap_thing("scrap_pile")
	_close_dialogue()
	assert_array(view.inventory_bar().item_ids()).contains(["scrap_die"])
	_go("shop")
	_drop_on("cutter", "scrap_die")
	assert_str(_all_text()).contains("teeth")
	# 3. Seagull's outdated scrap, tried at the depot locker: the decoy.
	_go("pier")
	_tap_thing("seagull")
	_close_dialogue()
	assert_array(view.inventory_bar().item_ids()).contains(["old_scrap"])
	_go("depot")
	_tap_thing("gnu_locker")
	assert_str(view.closeup_name()).is_equal("lock:gnu_locker")
	_close_dialogue()
	var lock := view.closeup as LockDials
	lock.set_code("241")
	lock.pull()
	assert_str(_all_text()).contains("HARBOUR")
	assert_bool(Adventure.chain_state(MACHINE).has_seen_decoy("old_locker_code")).is_true()
	view.close_closeup()
	# The harbour explains the mistake and points back; Anglerfish's die fits nothing.
	_go("harbour")
	var explained := _all_text()
	assert_str(explained).contains("September")
	assert_str(explained).contains("fortunes")
	_tap_thing("anglerfish")
	_close_dialogue()
	_go("shop")
	_drop_on("cutter", "cloud_die")
	assert_str(_all_text()).contains("connector")
	# The right code, from the batter jars, opens the locker: a bent die.
	_go("depot")
	_tap_thing("gnu_locker")
	_close_dialogue()
	var answer := PuzzleData.get_answer(MACHINE)
	lock = view.closeup as LockDials
	lock.set_code("%d%d%d" % [int(answer["egg"]), int(answer["vanilla"]), int(answer["sugar"])])
	lock.pull()
	assert_bool(lock.opened).is_true()
	_close_dialogue()
	view.close_closeup()
	assert_array(view.inventory_bar().item_ids()).contains(["die_bent"])
	# 4. Penguin's bench: tap the dents flat.
	_go("workshop")
	_drop_on("bench", "die_bent")
	assert_str(view.closeup_name()).is_equal("straighten")
	var bench := view.closeup as StraightenBench
	for i in StraightenBench.DENTS.size():
		for blow in StraightenBench.BLOWS:
			bench.strike(i)
	assert_int(bench.dents_left()).is_equal(0)
	bench.done.emit()
	_close_dialogue()
	assert_array(view.inventory_bar().item_ids()).contains(["cutter_die"])
	assert_array(view.inventory_bar().item_ids()).not_contains(["die_bent"])
	# 5. Install: drag the die onto the cutter, then tighten the bolts.
	_go("shop")
	_drop_on("cutter", "cutter_die")
	assert_str(view.closeup_name()).is_equal("tighten")
	var bolts := view.closeup as TightenBolts
	for i in TightenBolts.BOLTS.size():
		for t in TightenBolts.TURNS:
			bolts.turn_bolt(i)
	assert_int(bolts.loose_bolts()).is_equal(0)
	bolts.done.emit()
	assert_bool(GameState.player.is_part_credited(MACHINE, "rhythm")).is_true()
	assert_int(int(Progress.store.get_crew_progress(MACHINE)["rhythm"])).is_equal(1)
	assert_str(Adventure.inventory.states(MACHINE)["cutter_die"]).is_equal("installed")
	_close_dialogue()
	# Crab merges it.
	assert_str(Router.top().scene_file_path).is_equal(Paths.MERGE_CELEBRATION)
	Router.clear()
	# The cutter now stamps rounds.
	var rig := view.room.rig
	assert_bool(rig.is_fixed("rhythm")).is_true()
	var before_stamp := rig.rounds.size()
	rig.stamp()
	assert_int(rig.rounds.size()).is_equal(before_stamp + 1)


func test_misdirects_can_be_put_back_where_they_came_from() -> void:
	await _view()
	_go("scrapyard")
	_tap_thing("scrap_pile")
	_close_dialogue()
	assert_bool(Adventure.has_item("scrap_die")).is_true()
	_drop_on("scrap_pile", "scrap_die")
	_close_dialogue()
	assert_bool(Adventure.has_item("scrap_die")).is_false()


func test_a_drop_on_nothing_or_the_wrong_thing_says_so() -> void:
	await _view()
	_go("workshop")
	_tap_thing("penguin")  # no sticky read yet: just Penguin's own lines
	_close_dialogue()
	assert_bool(Adventure.has_item("spanner")).is_false()
	_go("scrapyard")
	_tap_thing("scrap_pile")
	_close_dialogue()
	_drop_on("scrap_sign", "scrap_die")
	assert_str(view.dialogue().current_text()).contains("does not go there")


func test_tap_an_item_then_a_thing_uses_it() -> void:
	await _view()
	_go("scrapyard")
	_tap_thing("scrap_pile")
	_close_dialogue()
	var entry: Dictionary = Adventure.visible_items()[0]
	view.inventory_bar().item_tapped.emit(entry)
	assert_str(view.inventory_bar().selected_item).is_equal("scrap_die")
	assert_str(view.room.use_item).is_equal("scrap_die")
	_close_dialogue()
	_tap_thing("scrap_pile")
	_close_dialogue()
	assert_bool(Adventure.has_item("scrap_die")).is_false()


# --- Batter shelf -------------------------------------------------------------------


func _batter(clue_count: int) -> PuzzleBase:
	var ids: Array = []
	for clue: Dictionary in PuzzleData.get_clues(MACHINE):
		ids.append(clue["id"])
	var puzzle: PuzzleBase = load(Paths.BATTER_SHELF).instantiate()
	puzzle.puzzle_id = MACHINE + "/logic"
	puzzle.machine = MACHINE
	puzzle.part = "logic"
	puzzle.configure(PuzzleData.matching_config(MACHINE, ids.slice(0, clue_count)))
	puzzle.size = Vector2(352, 640)
	add_child(auto_free(puzzle))
	return puzzle


func test_batter_shelf_solves_with_the_answer_and_not_otherwise() -> void:
	var puzzle := _batter(4)
	await get_tree().process_frame
	var results: Array = []
	puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
	var answer := PuzzleData.get_answer(MACHINE)
	var items: Array = answer.keys()
	# A wrong full shelf: swap two jars.
	for item: String in answer:
		puzzle.place(item, int(answer[item]))
	puzzle.place(items[0], int(answer[items[1]]))
	puzzle.place(items[1], int(answer[items[0]]))
	assert_bool(puzzle.check()).is_false()
	assert_array(results).is_empty()
	for item: String in answer:
		puzzle.place(item, int(answer[item]))
	assert_bool(puzzle.check()).is_true()
	assert_array(results).contains_exactly([true])


func test_batter_jars_tumble_into_the_slot_they_are_dropped_on() -> void:
	var puzzle := _batter(4)
	await get_tree().process_frame
	var slot_three: float = puzzle.SLOT_X0 + 2 * puzzle.SLOT_GAP + puzzle.JAR.x / 2.0
	var slot := int(puzzle.drop_jar("egg", Vector2(slot_three, 60)))
	assert_int(slot).is_equal(3)
	assert_bool(puzzle.is_settled()).is_false()  # still falling
	assert_dict(puzzle.placement()).is_equal({"egg": 3})
	# Dropping another jar on the same slot sends the first back to the counter.
	puzzle.drop_jar("sugar", Vector2(slot_three, 60))
	assert_dict(puzzle.placement()).is_equal({"sugar": 3})
	puzzle.simulate(2.0)
	assert_bool(puzzle.is_settled()).is_true()
	# Dropped away from the shelf, a jar goes home.
	assert_int(int(puzzle.drop_jar("flour", Vector2(80, 300)))).is_equal(0)
	assert_bool(puzzle.placement().has("flour")).is_false()


func test_batter_shelf_hints_and_reveal() -> void:
	var puzzle := _batter(4)
	await get_tree().process_frame
	Hints.reset(puzzle.puzzle_id)
	var results: Array = []
	puzzle.solved.connect(func(credited: bool) -> void: results.append(credited))
	assert_str(puzzle.get_hint_text(1)).starts_with("Start with")
	assert_str(puzzle.get_hint_text(2)).starts_with("A clue says")
	puzzle.request_hint()
	puzzle.request_hint()
	puzzle.request_hint()
	assert_array(results).contains_exactly([false])
	assert_dict(puzzle.placement()).is_equal(PuzzleData.get_answer(MACHINE))
	var few := _batter(2)
	await get_tree().process_frame
	assert_bool(few.can_reveal()).is_false()


func test_the_batter_shelf_opens_from_the_shop_and_credits_the_part() -> void:
	await _view()
	_go("shop")
	_tap_thing("batter_shelf")
	assert_str(view.closeup_name()).is_equal("batter_shelf")
	var puzzle := view.closeup as PuzzleBase
	var answer := PuzzleData.get_answer(MACHINE)
	for item: String in answer:
		puzzle.call("place", item, int(answer[item]))
	puzzle.call("check")
	assert_bool(GameState.player.is_part_credited(MACHINE, "logic")).is_true()


# --- Rig and dialogue ---------------------------------------------------------------


func test_cookie_machine_parts_come_alive_as_they_are_fixed() -> void:
	await _view()
	_go("shop")
	var rig := view.room.rig
	assert_object(rig).is_not_null()
	for part in Ids.PARTS:
		assert_bool(rig.is_fixed(part)).is_false()
	var captions: Array = []
	rig.part_celebrated.connect(func(_part: String, caption: String) -> void: captions.append(caption))
	Progress.store.record_part_solved(MACHINE, "wiring", GameState.device_id, true)
	assert_bool(rig.is_fixed("wiring")).is_true()
	assert_array(rig.pending()).contains(["wiring"])
	var paddle := rig.get_children().filter(func(n: Node) -> bool: return n.name == "Paddle")[0] as Sprite2D
	var start_angle := paddle.rotation
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(paddle.rotation).is_not_equal(start_angle)
	assert_array(captions).contains(["narrator.fixed.cookie_machine.wiring"])
	for part in Ids.PARTS:
		Progress.store.record_part_solved(MACHINE, part, GameState.device_id, true)
	assert_bool(rig.is_running()).is_true()


func test_dialogue_types_out_and_advances() -> void:
	await _view()
	var d := view.dialogue()
	d.say([Story.get_piece("penguin.cutter.mailed")])
	assert_str(d.current_speaker()).is_equal("Penguin")
	assert_str(d.current_expression()).is_equal("surprised")
	assert_int(d.pages_left()).is_equal(3)
	d.advance()  # finishes the typing
	d.advance()  # next line
	assert_int(d.pages_left()).is_equal(2)
	d.skip_all()
	assert_bool(d.is_open()).is_false()


func test_room_query_for_playtesting() -> void:
	assert_str(Adventure.room_from_query("?a=1&room=harbour", Adventure.rooms)).is_equal("harbour")
	assert_str(Adventure.room_from_query("?room=nowhere", Adventure.rooms)).is_equal("")
	assert_str(Adventure.room_from_query("", Adventure.rooms)).is_equal("")


# --- Review follow-ups ----------------------------------------------------------------


func test_every_thing_in_every_room_answers_a_tap_with_a_sound_and_a_visual() -> void:
	await _view()
	for id in Adventure.rooms.rooms():
		_go(id)
		for t in Adventure.rooms.things(id):
			view.room.input_enabled = true
			view.room.last_flash = null
			Audio.played.clear()
			view.room.tap_world(RoomGraph.rect_px(t).get_center())
			var label := "%s/%s" % [id, str(t["id"])]
			assert_bool(Audio.played.is_empty()).override_failure_message(label + ": no sound").is_false()
			assert_str(Audio.last_played()).override_failure_message(label).is_equal("select")
			assert_object(view.room.last_flash).override_failure_message(label + ": nothing lit up").is_not_null()
			assert_bool(is_instance_valid(view.room.last_flash) and view.room.last_flash.is_inside_tree()).override_failure_message(label).is_true()


func _wait_transition() -> void:
	for i in 600:
		if not view._transitioning:
			return
		await get_tree().process_frame


func test_edge_slides_use_two_live_views_without_readback() -> void:
	await _view()
	view.instant_transitions = false
	_go("square")
	view.room.walk_to(Vector2i(10, 12))
	view.room.finish_walk()
	var first := view.find_child("RoomFrame", true, false) as SubViewportContainer
	var second := view.find_child("RoomFrame2", true, false) as SubViewportContainer
	assert_bool(first.visible and second.visible).is_true()  # both slide together
	assert_str(view.room_id).is_equal("pier")
	await _wait_transition()
	assert_bool(view._transitioning).is_false()
	assert_int(int(first.visible) + int(second.visible)).is_equal(1)
	assert_str(view.room.get_parent().get_parent().name).is_equal("RoomViewport2")
	# Back the other way reuses the first view; only the active view takes taps.
	view.room.walk_to(Vector2i(0, 12))
	view.room.finish_walk()
	await _wait_transition()
	assert_str(view.room_id).is_equal("square")
	assert_int(first.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_int(second.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_hint_button_walks_the_ladder_and_says_done_at_the_end() -> void:
	await _view()
	var button := view.inventory_bar().find_child("HintButton", true, false) as Button
	assert_object(button).is_not_null()
	assert_float(button.custom_minimum_size.x).is_greater_equal(44.0)
	button.pressed.emit()
	assert_str(view.dialogue().current_speaker()).is_equal("Red Panda")
	assert_str(view.dialogue().current_text()).is_equal(str(Story.get_piece("red_panda.hint.cutter.find.1")["lines"][0]))
	view.dialogue().skip_all()
	button.pressed.emit()
	assert_str(view.dialogue().current_text()).is_equal(str(Story.get_piece("red_panda.hint.cutter.find.2")["lines"][0]))
	view.dialogue().skip_all()
	Adventure.inventory.mark(MACHINE, "cutter_die", "installed", "shop:cutter", GameState.device_id)
	assert_str(Adventure.next_hint()).is_equal(Adventure.HINT_DONE)


func test_a_tap_on_the_ground_drops_the_picked_item() -> void:
	await _view()
	_go("scrapyard")
	_tap_thing("scrap_pile")
	_close_dialogue()
	view.inventory_bar().item_tapped.emit(Adventure.visible_items()[0])
	_close_dialogue()
	assert_str(view.inventory_bar().selected_item).is_equal("scrap_die")
	view.room.input_enabled = true
	view.room.tap_world(Vector2(9 * 16 + 8, 18 * 16 + 8))
	assert_str(view.room.use_item).is_equal("")
	assert_str(view.inventory_bar().selected_item).is_equal("")


func test_portrait_follows_the_pixel_scale() -> void:
	await _view()
	var d := view.dialogue()
	d.set_pixel_scale(3.0)
	var portrait := d.find_child("Portrait", true, false) as TextureRect
	assert_object(portrait.custom_minimum_size).is_equal(Vector2(96, 96))


func test_reset_in_the_adventure_does_not_build_the_old_town() -> void:
	var screen := Router.push(Paths.SETTINGS)
	await get_tree().process_frame
	screen.call("_on_reset")
	assert_object(Router.current_place()).is_null()
	assert_int(Router.depth()).is_equal(0)
	assert_str(Adventure.room_id).is_equal("")
