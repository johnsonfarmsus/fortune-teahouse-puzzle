# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## The Story autoload, the DialogueBox and every screen that speaks. Uses the real
## autoloads but never the real save: GameState does not persist and Progress
## gets a throwaway store file.

const PROGRESS_PATH := "user://test_story_progress.json"
const MACHINE := "cookie_machine"
const GNU_FILE := "res://data/story/gnu.json"


func before_test() -> void:
	_cleanup()
	GameState.persist = false
	Finale.set_client(null)
	Finale.set_state(FinaleState.new(""))  # never touch user://finale.json
	GameState.player = PlayerState.new()
	GameState.player.ensure_device_id()
	Progress.set_store(LocalProgressStore.new(PROGRESS_PATH))
	Router.clear()


func after_test() -> void:
	Router.clear()
	for flag in ["finale_open", "line_running"]:
		Story.set_flag(flag, false)
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(PROGRESS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))


func _pieces(count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append({"id": "t.%d" % i, "speaker": "Gnu", "kind": "note", "lines": ["one", "two", "three"], "where": "town", "when": "always"})
	return out


func _box(count: int) -> DialogueBox:
	var box: DialogueBox = load(Paths.DIALOGUE_BOX).instantiate()
	box.free_on_finish = false
	box.show_pieces(_pieces(count))
	add_child(auto_free(box))
	return box


func _boxes(root: Node) -> Array:
	return root.find_children("*", "DialogueBox", true, false)


func _tap(box: DialogueBox) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	box._gui_input(event)


func _label_texts(root: Node) -> Array:
	var out: Array = []
	for node in root.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out


func _gnu_pieces_where(prefix: String) -> Array:
	var out: Array = []
	for raw: Dictionary in JsonFile.read(GNU_FILE).get("pieces", []):
		var where: String = raw["where"]
		if where == prefix or where.begins_with(prefix + ":"):
			out.append(raw["id"])
	return out


func _run_machine(machine: String) -> void:
	for part in Ids.PARTS:
		Progress.store.record_part_solved(machine, part, GameState.device_id, true)


# --- Story autoload --------------------------------------------------------------


func test_story_autoload_saves_seen_in_the_player_state() -> void:
	assert_bool(Story.is_seen("gnu.town.shop_door")).is_false()
	Story.mark_seen("gnu.town.shop_door")
	assert_bool(Story.is_seen("gnu.town.shop_door")).is_true()
	assert_array(GameState.player.seen_story).contains_exactly(["gnu.town.shop_door"])
	Story.mark_seen("gnu.town.shop_door")
	assert_int(GameState.player.seen_story.size()).is_equal(1)


func test_visit_is_true_once_and_state_changed_only_on_change() -> void:
	assert_bool(Story.visit("machine_view:oven")).is_true()
	assert_bool(Story.visit("machine_view:oven")).is_false()
	assert_bool(Story.visit("machine_view:cookie_machine")).is_true()
	assert_bool(Story.state_changed("k", "a")).is_true()
	assert_bool(Story.state_changed("k", "a")).is_false()
	assert_bool(Story.state_changed("k", "b")).is_true()


func test_next_unseen_follows_what_the_player_has_seen() -> void:
	var first := Story.next_unseen("lucky_word_entry", "first_visit")
	assert_str(first["id"]).is_equal("red_panda.welcome.1")
	Story.mark_seen(first["id"])
	assert_str(Story.next_unseen("lucky_word_entry", "first_visit")["id"]).is_equal("red_panda.welcome.2")
	Story.mark_seen("red_panda.welcome.2")
	assert_dict(Story.next_unseen("lucky_word_entry", "first_visit")).is_empty()


func test_story_context_fills_name_and_machine() -> void:
	assert_str(Story.context()["name"]).is_equal("friend")
	GameState.player.display_name = "Tux"
	assert_str(Story.context({"machine": "Oven"})["name"]).is_equal("Tux")
	assert_str(Story.context({"machine": "Oven"})["machine"]).is_equal("Oven")


func test_flags_drive_the_triggers_nothing_else_raises_yet() -> void:
	assert_bool(Story.trigger_active("first_visit")).is_true()
	assert_bool(Story.trigger_active("finale_open")).is_false()
	Story.set_flag("finale_open")
	assert_bool(Story.trigger_active("finale_open")).is_true()
	Story.set_flag("finale_open", false)
	assert_bool(Story.trigger_active("finale_open")).is_false()


func test_play_marks_seen_unless_told_not_to() -> void:
	var piece := Story.get_piece("gnu.town.pier_bottle")
	var host: Control = auto_free(Control.new())
	add_child(host)
	Story.play(host, [piece], false)
	assert_bool(Story.is_seen("gnu.town.pier_bottle")).is_false()
	Story.play(host, [piece])
	assert_bool(Story.is_seen("gnu.town.pier_bottle")).is_true()
	assert_object(Story.play(host, [])).is_null()


# --- DialogueBox ------------------------------------------------------------------


func test_dialogue_box_covers_the_screen_and_stops_input() -> void:
	var box := _box(1)
	assert_int(box.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_float(box.anchor_left).is_equal(0.0)
	assert_float(box.anchor_top).is_equal(0.0)
	assert_float(box.anchor_right).is_equal(1.0)
	assert_float(box.anchor_bottom).is_equal(1.0)
	assert_float(box.offset_left).is_equal(0.0)
	assert_float(box.offset_bottom).is_equal(0.0)


func test_dialogue_box_shows_speaker_kind_and_up_to_three_lines() -> void:
	var box := _box(2)
	assert_str(box.speaker_text()).is_equal("Gnu (note)")
	assert_str(box.body_text()).is_equal("one\ntwo\nthree")
	assert_int(box.current_index()).is_equal(0)


func test_dialogue_box_advances_on_tap_and_finishes_once() -> void:
	var box := _box(3)
	var done: Array = []
	var seen: Array = []
	box.finished.connect(func() -> void: done.append(true))
	box.advanced.connect(func(i: int) -> void: seen.append(i))
	_tap(box)
	assert_int(box.current_index()).is_equal(1)
	_tap(box)
	assert_int(box.current_index()).is_equal(2)
	assert_array(done).is_empty()
	_tap(box)
	assert_array(done).has_size(1)
	assert_array(seen).contains_exactly([1, 2])
	assert_bool(box.is_done()).is_true()
	_tap(box)
	box.skip()
	assert_array(done).has_size(1)


func test_dialogue_box_skip_ends_the_whole_sequence() -> void:
	var box := _box(3)
	var done: Array = []
	box.finished.connect(func() -> void: done.append(true))
	var skip: Button
	for node in box.find_children("*", "Button", true, false):
		if (node as Button).text == "Skip":
			skip = node
	assert_object(skip).is_not_null()
	assert_float(skip.custom_minimum_size.x).is_greater_equal(44.0)
	assert_float(skip.custom_minimum_size.y).is_greater_equal(44.0)
	skip.pressed.emit()
	assert_array(done).has_size(1)
	assert_bool(box.is_done()).is_true()
	assert_int(box.current_index()).is_equal(0)


func test_dialogue_box_has_no_timer_unless_auto_advance_is_on() -> void:
	var box := _box(2)
	assert_float(box.auto_advance_seconds).is_equal(0.0)
	assert_array(box.find_children("*", "Timer", true, false)).is_empty()
	var auto: DialogueBox = load(Paths.DIALOGUE_BOX).instantiate()
	auto.free_on_finish = false
	auto.auto_advance_seconds = 5.0
	auto.show_pieces(_pieces(2))
	add_child(auto_free(auto))
	assert_array(auto.find_children("*", "Timer", true, false)).has_size(1)


func test_dialogue_box_frees_itself_when_done() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var box := DialogueBox.open(host, _pieces(1))
	assert_array(_boxes(host)).has_size(1)
	box.advance()
	await get_tree().process_frame
	assert_array(_boxes(host)).is_empty()


func test_dialogue_box_on_a_place_gets_its_own_layer() -> void:
	var place: Node2D = auto_free(Node2D.new())
	add_child(place)
	var box := DialogueBox.open(place, _pieces(1))
	assert_object(box.get_parent()).is_instanceof(CanvasLayer)
	box.skip()
	await get_tree().process_frame
	assert_array(_boxes(place)).is_empty()


# --- Start screen, Settings -----------------------------------------------------


func test_start_screen_shows_tagline_and_one_tip_from_data() -> void:
	var screen: CanvasLayer = load("res://scenes/main/start_screen.tscn").instantiate()
	screen.load_msec = 0
	add_child(auto_free(screen))
	await get_tree().process_frame
	var tagline := str(Story.pieces_for("start_screen", "always")[0]["text"])
	assert_str((screen.get_node("Tagline") as Label).text).is_equal(tagline)
	var tips: Array = []
	for tip: Dictionary in Story.pieces_for("loading", "always"):
		tips.append(tip["text"])
	assert_array(tips).contains([(screen.get_node("Tip") as Label).text])
	# Fast loading means no wait.
	assert_bool((screen.get_node("StartButton") as Button).disabled).is_false()
	assert_str((screen.get_node("StartButton") as Button).text).is_equal("Tap to start")


func test_start_screen_button_is_released_after_the_hold() -> void:
	var screen: CanvasLayer = load("res://scenes/main/start_screen.tscn").instantiate()
	screen.load_msec = 100000
	add_child(auto_free(screen))
	await get_tree().process_frame
	var button := screen.get_node("StartButton") as Button
	assert_bool(button.disabled).is_true()
	screen._release_button()
	assert_bool(button.disabled).is_false()
	assert_str(button.text).is_equal("Tap to start")


func test_start_screen_holds_the_button_when_loading_was_slow() -> void:
	var screen: CanvasLayer = load("res://scenes/main/start_screen.tscn").instantiate()
	screen.load_msec = 100000
	add_child(auto_free(screen))
	await get_tree().process_frame
	assert_bool((screen.get_node("StartButton") as Button).disabled).is_true()
	assert_str((screen.get_node("Tip") as Label).text).is_not_empty()


func test_settings_shows_the_about_block_and_the_source_link() -> void:
	var screen := Router.push(Paths.SETTINGS)
	await get_tree().process_frame
	var about := str(Story.pieces_for("settings", "always")[0]["text"])
	assert_array(_label_texts(screen)).contains([about])
	assert_str(about).contains(Ids.REPO_URL)
	var has_source := false
	for node in screen.find_children("*", "Button", true, false):
		if (node as Button).text == "Source code (AGPL)":
			has_source = true
	assert_bool(has_source).is_true()


# --- Teahouse, puzzle host, machine view -------------------------------------


func test_teahouse_welcomes_once_then_speaks_when_things_change() -> void:
	var first := Router.push(Paths.LUCKY_WORD_ENTRY)
	var boxes := _boxes(first)
	assert_array(boxes).has_size(1)
	assert_int((boxes[0] as DialogueBox).piece_count()).is_equal(2)
	assert_str((boxes[0] as DialogueBox).speaker_text()).is_equal("Red Panda")
	assert_bool(Story.is_seen("red_panda.welcome.1")).is_true()
	Router.pop()
	# Same situation (no crew): the panda keeps quiet.
	assert_array(_boxes(Router.push(Paths.LUCKY_WORD_ENTRY))).is_empty()
	Router.pop()
	# A crew is a change: one has_crew line.
	GameState.choose_crew("oven")
	var crew_screen := Router.push(Paths.LUCKY_WORD_ENTRY)
	assert_array(_boxes(crew_screen)).has_size(1)
	var line: Dictionary = (_boxes(crew_screen)[0] as DialogueBox).current_piece()
	assert_str(line["when"]).is_equal("has_crew")
	Router.pop()
	assert_array(_boxes(Router.push(Paths.LUCKY_WORD_ENTRY))).is_empty()
	Router.pop()
	# The machine running is another change, with the machine's name filled in.
	_run_machine("oven")
	var running_screen := Router.push(Paths.LUCKY_WORD_ENTRY)
	assert_array(_boxes(running_screen)).has_size(1)
	var running: Dictionary = (_boxes(running_screen)[0] as DialogueBox).current_piece()
	assert_str(running["id"]).is_equal("red_panda.machine_running")
	assert_str(running["text"]).contains("The Oven is running")


func test_no_crew_line_comes_from_the_no_crew_group() -> void:
	Story.mark_seen("red_panda.welcome.1")
	Story.mark_seen("red_panda.welcome.2")
	var screen := Router.push(Paths.LUCKY_WORD_ENTRY)
	var boxes := _boxes(screen)
	assert_array(boxes).has_size(1)
	var line: Dictionary = (boxes[0] as DialogueBox).current_piece()
	assert_str(line["group"]).is_equal("red_panda.no_crew")
	assert_str(line["when"]).is_equal("no_crew")


func test_puzzle_host_shows_the_gnus_note_once_per_part() -> void:
	var host := Router.push(Paths.PUZZLE_HOST, {"machine": MACHINE, "part": "wiring"})
	var boxes := _boxes(host)
	assert_array(boxes).has_size(1)
	assert_str((boxes[0] as DialogueBox).current_piece()["id"]).is_equal("gnu.part.cookie_machine.wiring")
	assert_str((boxes[0] as DialogueBox).speaker_text()).starts_with("Gnu")
	Router.pop()
	assert_array(_boxes(Router.push(Paths.PUZZLE_HOST, {"machine": MACHINE, "part": "wiring"}))).is_empty()
	Router.pop()
	# Another part has its own note.
	assert_array(_boxes(Router.push(Paths.PUZZLE_HOST, {"machine": MACHINE, "part": "word"}))).has_size(1)


func test_every_part_has_a_note_to_show() -> void:
	for machine in Ids.MACHINES:
		for part in Ids.PARTS:
			var note := Story.next_unseen("puzzle:%s/%s" % [machine, part], "first_visit")
			assert_str(note.get("speaker", "")).override_failure_message("%s/%s" % [machine, part]).is_equal("Gnu")


func test_machine_view_helper_speaks_on_first_open_then_after_idle() -> void:
	var view := Router.push(Paths.MACHINE_VIEW, {"machine": "oven"})
	await get_tree().process_frame
	var boxes := _boxes(view)
	assert_array(boxes).has_size(1)
	assert_str((boxes[0] as DialogueBox).speaker_text()).is_equal("Gopher")
	(boxes[0] as DialogueBox).skip()
	await get_tree().process_frame
	Router.pop()
	# Second open: quiet until the idle wait is over.
	var again := Router.push(Paths.MACHINE_VIEW, {"machine": "oven"})
	await get_tree().process_frame
	assert_array(_boxes(again)).is_empty()
	var timer := again.get_node("IdleTimer") as Timer
	assert_float(timer.wait_time).is_equal(20.0)
	assert_bool(timer.is_stopped()).is_false()
	again._on_idle()
	assert_array(_boxes(again)).has_size(1)
	assert_str((_boxes(again)[0] as DialogueBox).current_piece()["when"]).is_equal("idle")


func test_machine_view_input_restarts_the_idle_wait_and_the_timer_goes_with_the_screen() -> void:
	Story.visit("machine_view:oven")
	var view := Router.push(Paths.MACHINE_VIEW, {"machine": "oven"})
	await get_tree().process_frame
	var timer := view.get_node("IdleTimer") as Timer
	timer.start(5.0)
	timer.wait_time = 20.0  # start(5.0) changed it; the restart uses wait_time
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	view._input(press)
	assert_float(timer.time_left).is_greater(19.0)
	Router.pop()
	await get_tree().process_frame
	assert_bool(is_instance_valid(timer)).is_false()


func test_machine_view_idle_can_be_cancelled() -> void:
	Story.visit("machine_view:oven")
	var view := Router.push(Paths.MACHINE_VIEW, {"machine": "oven"})
	await get_tree().process_frame
	var timer := view.get_node("IdleTimer") as Timer
	assert_bool(timer.is_stopped()).is_false()
	view.cancel_idle()
	assert_bool(timer.is_stopped()).is_true()


func test_contributors_opens_with_crab_once() -> void:
	var screen := Router.push(Paths.CONTRIBUTORS)
	var boxes := _boxes(screen)
	assert_array(boxes).has_size(1)
	assert_str((boxes[0] as DialogueBox).current_piece()["id"]).is_equal("crab.pier")
	Router.pop()
	assert_array(_boxes(Router.push(Paths.CONTRIBUTORS))).is_empty()


# --- Merge celebration ----------------------------------------------------------


func _merge(credited: bool) -> ScreenBase:
	var screen := Router.push(
		Paths.MERGE_CELEBRATION, {"machine": MACHINE, "part": "wiring", "credited": credited}
	)
	await get_tree().process_frame
	screen.skip()
	return screen


func test_merge_celebration_uses_crabs_merged_lines() -> void:
	var screen := await _merge(true)
	var context := {"part": "Mixer motor controller", "machine": "Cookie Machine"}
	var allowed: Array = []
	for piece: Dictionary in Story.pieces_for("merge_celebration", "merged", context):
		allowed.append(piece["text"])
	var found := false
	for text in _label_texts(screen):
		if allowed.has(text):
			found = true
	assert_bool(found).override_failure_message("no merged line from crab.json on screen").is_true()
	assert_array(_label_texts(screen)).not_contains(["Merged!"])


func test_merge_celebration_first_credit_wording_and_explanation() -> void:
	var screen := await _merge(true)
	var prompt := str(Story.get_piece("crab.name_prompt")["text"])
	assert_array(_label_texts(screen)).contains([prompt])
	assert_array(_label_texts(screen)).not_contains(["Put your name on the contributors list?"])
	# The explanation of a pull request opens once, in a box.
	var boxes := _boxes(screen)
	assert_array(boxes).has_size(1)
	assert_str((boxes[0] as DialogueBox).current_piece()["id"]).is_equal("crab.first_contribution")
	assert_bool(Story.is_seen("crab.first_contribution")).is_true()
	Router.pop()
	assert_array(_boxes(await _merge(true))).is_empty()


func test_merge_celebration_uncredited_uses_crabs_words() -> void:
	var screen := await _merge(false)
	var line := str(Story.get_piece("crab.uncredited")["text"])
	assert_array(_label_texts(screen)).contains([line])
	assert_array(_label_texts(screen)).not_contains(["Crab merged the fix. Solve one yourself to get on the list."])
	assert_array(_boxes(screen)).is_empty()


# --- Town and Shop ---------------------------------------------------------------


func _town() -> PlaceBase:
	var town: PlaceBase = auto_free(load(Paths.PLACES["town"]).instantiate())
	add_child(town)
	await get_tree().process_frame
	return town


func _shop() -> PlaceBase:
	var shop: PlaceBase = auto_free(load(Paths.PLACES["shop"]).instantiate())
	add_child(shop)
	await get_tree().process_frame
	return shop


func test_town_has_a_marker_for_every_town_note_in_the_data() -> void:
	var town := await _town()
	var wanted := _gnu_pieces_where("town")
	assert_int(wanted.size()).is_greater(0)
	var markers := town.find_children("*", "StoryMarker", true, false)
	assert_int(markers.size()).is_equal(wanted.size())
	var ids: Array = []
	for node in markers:
		var marker := node as StoryMarker
		ids.append(marker.piece_id)
		assert_float(marker.custom_minimum_size.x).is_greater_equal(44.0)
		assert_float(marker.custom_minimum_size.y).is_greater_equal(44.0)
		assert_float(marker.size.x).is_greater_equal(44.0)
		assert_float(marker.size.y).is_greater_equal(44.0)
		assert_bool(marker.text.contains("Note")).is_true()
	assert_array(ids).contains_same(wanted)


func test_town_and_shop_markers_together_cover_the_gnu_town_notes() -> void:
	var town := await _town()
	var shop := await _shop()
	var ids: Array = []
	for node in town.find_children("*", "StoryMarker", true, false) + shop.find_children("*", "StoryMarker", true, false):
		ids.append((node as StoryMarker).piece_id)
	var six: Array = []
	for raw: Dictionary in JsonFile.read(GNU_FILE).get("pieces", []):
		if str(raw["id"]).begins_with("gnu.town."):
			six.append(raw["id"])
	assert_int(six.size()).is_greater(0)
	assert_array(ids).contains_same(six)


func test_tapping_a_town_note_opens_the_box_and_marks_it_seen() -> void:
	var town := await _town()
	var marker: StoryMarker
	for node in town.find_children("*", "StoryMarker", true, false):
		if (node as StoryMarker).piece_id == "gnu.town.pier_bottle":
			marker = node
	assert_str(marker.text).is_equal("! Note")
	marker.pressed.emit()
	var boxes := _boxes(town)
	assert_array(boxes).has_size(1)
	assert_str((boxes[0] as DialogueBox).current_piece()["id"]).is_equal("gnu.town.pier_bottle")
	assert_bool(Story.is_seen("gnu.town.pier_bottle")).is_true()
	assert_str(marker.text).is_equal("Note")


func test_shop_markers_keep_8_px_from_every_button_and_hotspot() -> void:
	var shop := await _shop()
	# Show every marker so hidden, trigger-gated ones are checked too.
	var markers: Array[Node] = shop.find_children("*", "StoryMarker", true, false)
	assert_int(markers.size()).is_greater(0)
	var obstacles: Array[Rect2] = []
	for node in shop.find_children("*", "Button", true, false):
		if not node is StoryMarker:
			obstacles.append((node as Button).get_global_rect())
	for node in shop.find_children("*", "Hotspot", true, false):
		var hotspot := node as Hotspot
		obstacles.append(Rect2(hotspot.global_position - Vector2(48, 48), Vector2(96, 96)))
	assert_int(obstacles.size()).is_greater(3)
	for node in markers:
		var marker := node as StoryMarker
		var rect := Rect2(marker.global_position, StoryMarker.SIZE).grow(8.0)
		for obstacle in obstacles:
			assert_bool(rect.intersects(obstacle)).override_failure_message("%s is within 8 px of %s" % [marker.piece_id, str(obstacle)]).is_false()


func test_notes_that_wait_for_a_trigger_stay_hidden_until_it_holds() -> void:
	var town := await _town()
	var shop := await _shop()
	var handoffs: StoryMarker
	var machine_note: StoryMarker
	for node in town.find_children("*", "StoryMarker", true, false):
		if (node as StoryMarker).piece_id == "gnu.town.handoffs":
			handoffs = node
	for node in shop.find_children("*", "StoryMarker", true, false):
		if (node as StoryMarker).piece_id == "gnu.town.answering_machine":
			machine_note = node
	assert_bool(handoffs.visible).is_false()
	assert_bool(machine_note.visible).is_false()
	Story.set_flag("finale_open")
	assert_bool(handoffs.visible).is_true()
	GameState.choose_crew(MACHINE)
	_run_machine(MACHINE)
	shop.refresh_story_markers()
	assert_bool(machine_note.visible).is_true()


func test_a_tap_on_an_open_dialogue_is_taken_by_the_box_not_the_town() -> void:
	# Headless Godot does not route pushed mouse events through the GUI, so this checks
	# what makes the real routing work: the open box is a visible, input-stopping control
	# covering every point a Town tap could land on, and the tap is spent advancing it.
	var town := await _town()
	var marker: StoryMarker = town.find_children("*", "StoryMarker", true, false)[0]
	marker.pressed.emit()
	assert_bool(town.dialogue_open()).is_true()
	await get_tree().process_frame
	var box: DialogueBox = _boxes(town)[0]
	assert_bool(box.is_visible_in_tree()).is_true()
	assert_int(box.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	var view := get_viewport().get_visible_rect()
	for point in [Vector2(5, 5), Vector2(195, 422), Vector2(385, 839), town.hotspot_at(Vector2(95, 240)).global_position]:
		assert_bool(box.get_global_rect().has_point(point)).override_failure_message("box misses %s" % point).is_true()
	assert_bool(box.get_global_rect().encloses(Rect2(Vector2.ZERO, Vector2(390, 844)))).is_true()
	assert_bool(view.size.x >= 390.0).is_true()
	_tap(box)
	assert_bool(town.dialogue_open()).is_false()
	assert_bool(town._tween == null or not town._tween.is_valid()).is_true()


func test_anglerfish_does_not_appear_over_a_dialogue_or_while_a_screen_covers_the_town() -> void:
	var town := await _town()
	var marker: StoryMarker = town.find_children("*", "StoryMarker", true, false)[0]
	marker.pressed.emit()
	assert_bool(town.spawn_anglerfish()).is_false()
	for box in _boxes(town):
		(box as DialogueBox).skip()
	assert_bool(town.dialogue_open()).is_false()
	var visit := town.get_node("VisitTimer") as Timer
	assert_bool(visit.paused).is_false()
	Router.push(Paths.SETTINGS)
	assert_bool(visit.paused).is_true()
	Router.pop()
	assert_bool(visit.paused).is_false()


func test_markers_refresh_when_the_device_is_reset() -> void:
	var town := await _town()
	var marker: StoryMarker
	for node in town.find_children("*", "StoryMarker", true, false):
		if (node as StoryMarker).piece_id == "gnu.town.pier_bottle":
			marker = node
	marker.pressed.emit()
	assert_str(marker.text).is_equal("Note")
	GameState.reset_device()
	assert_str(marker.text).is_equal("! Note")


func test_first_tap_on_the_shop_door_reads_the_gnus_sign() -> void:
	var town := await _town()
	var hotspot := town.find_children("*", "Hotspot", true, false).filter(func(h: Node) -> bool: return (h as Hotspot).place_id == "shop")[0] as Hotspot
	town.activate(hotspot)
	var boxes := _boxes(town)
	assert_array(boxes).has_size(1)
	assert_str((boxes[0] as DialogueBox).current_piece()["id"]).is_equal("gnu.town.shop_door")
	assert_bool(Story.is_seen("gnu.town.shop_door")).is_true()


func test_anglerfish_appears_with_a_bit_and_is_read_in_full() -> void:
	var town := await _town()
	assert_bool(town.anglerfish.visible).is_false()
	assert_float(town.anglerfish.custom_minimum_size.y).is_greater_equal(44.0)
	assert_bool(town.spawn_anglerfish()).is_true()
	assert_bool(town.anglerfish.visible).is_true()
	assert_float((town.get_node("LeaveTimer") as Timer).wait_time).is_equal(8.0)
	assert_float((town.get_node("VisitTimer") as Timer).wait_time).is_equal(90.0)
	var shown_label: Label = town.anglerfish.find_children("*", "Label", true, false)[0]
	assert_str(shown_label.text).starts_with("Anglerfish: ")
	assert_bool(town.anglerfish.find_children("*", "ColorRect", true, false).size() > 0).is_true()
	# Already here: a second call does nothing.
	assert_bool(town.spawn_anglerfish()).is_false()
	town.anglerfish.pressed.emit()
	assert_bool(town.anglerfish.visible).is_false()
	var boxes := _boxes(town)
	assert_array(boxes).has_size(1)
	var piece: Dictionary = (boxes[0] as DialogueBox).current_piece()
	assert_str(piece["speaker"]).is_equal("Anglerfish")
	assert_str(piece["when"]).is_equal("interval")
	assert_str(piece["text"]).starts_with(shown_label.text.trim_prefix("Anglerfish: ").trim_suffix("...").substr(0, 20))


func test_anglerfish_bits_come_round_in_turn_and_wait_for_a_free_town() -> void:
	var town := await _town()
	var ids: Array = []
	for i in 7:
		assert_bool(town.spawn_anglerfish()).is_true()
		town.anglerfish.pressed.emit()
		var box: DialogueBox = _boxes(town).back()
		ids.append(box.current_piece()["id"])
		box.skip()
	var distinct: Dictionary = {}
	for id in ids.slice(0, 6):
		distinct[id] = true
	assert_int(distinct.size()).is_equal(6)
	assert_str(ids[6]).is_equal(ids[0])
	Router.push(Paths.SETTINGS)
	assert_bool(town.spawn_anglerfish()).is_false()


func test_anglerfish_farewell_is_inert_until_the_line_runs() -> void:
	var town := await _town()
	assert_bool(Story.is_seen("anglerfish.farewell")).is_false()
	assert_array(_boxes(town)).is_empty()
	Story.set_flag("line_running")
	var boxes := _boxes(town)
	assert_array(boxes).has_size(1)
	assert_str((boxes[0] as DialogueBox).current_piece()["id"]).is_equal("anglerfish.farewell")
	assert_bool(Story.is_seen("anglerfish.farewell")).is_true()
	assert_bool(town.anglerfish_gone()).is_true()
	assert_bool(town.spawn_anglerfish()).is_false()
	assert_bool((town.get_node("VisitTimer") as Timer).is_stopped()).is_true()


func test_shop_markers_match_the_data_and_are_phone_sized() -> void:
	var shop := await _shop()
	var wanted := _gnu_pieces_where("shop")
	var markers := shop.find_children("*", "StoryMarker", true, false)
	assert_int(markers.size()).is_equal(wanted.size())
	for node in markers:
		assert_float((node as StoryMarker).size.x).is_greater_equal(44.0)
		assert_float((node as StoryMarker).size.y).is_greater_equal(44.0)
