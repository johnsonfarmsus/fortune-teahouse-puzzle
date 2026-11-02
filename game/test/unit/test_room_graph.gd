# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## The town graph: every door leads to an existing room and back, every room
## is reachable, everything can be walked to, and all art names are listed.

const SLICE_ROOMS: Array[String] = ["teahouse", "shop", "pier", "workshop", "depot", "scrapyard", "harbour"]

var graph: RoomGraph


func before_test() -> void:
	graph = RoomGraph.new()


func test_graph_validates() -> void:
	assert_array(graph.validate()).is_empty()


func test_the_slice_rooms_exist_and_are_reachable() -> void:
	var reachable := graph.reachable_rooms()
	for id in SLICE_ROOMS:
		assert_bool(graph.has_room(id)).override_failure_message(id).is_true()
		assert_array(reachable).contains([id])
	assert_str(graph.start_room()).is_equal("teahouse")


func test_every_door_leads_to_an_existing_room_and_back() -> void:
	for id in graph.rooms():
		for e: Dictionary in graph.exits(id):
			var to := str(e["to"])
			assert_bool(graph.has_room(to)).is_true()
			var arrive := graph.spawn(to, str(e["arrive"]))
			assert_bool(graph.is_walkable(to, arrive)).override_failure_message("%s -> %s" % [id, to]).is_true()
			var back: Array = []
			for b: Dictionary in graph.exits(to):
				if str(b["to"]) == id:
					back.append(b)
			assert_bool(back.is_empty()).override_failure_message("no way back %s -> %s" % [to, id]).is_false()
			# Walking back through that exit from where you arrive is possible.
			var tile: Array = back[0]["tiles"][0]
			assert_bool(graph.path(to, arrive, Vector2i(int(tile[0]), int(tile[1]))).is_empty()).is_false()
			assert_bool(["door", "edge"].has(str(e["kind"]))).is_true()


func test_everything_in_a_room_can_be_walked_to() -> void:
	for id in graph.rooms():
		var start: Vector2i = graph.spawn(id, str((graph.room(id)["spawns"] as Dictionary).keys()[0]))
		for t in graph.things(id):
			var stand := graph.stand_cell(id, t)
			assert_bool(graph.path(id, start, stand).is_empty()).override_failure_message("%s: %s" % [id, str(t["id"])]).is_false()
		for e: Dictionary in graph.exits(id):
			for raw: Array in e["tiles"]:
				assert_bool(graph.path(id, start, Vector2i(int(raw[0]), int(raw[1]))).is_empty()).is_false()


func test_rooms_are_eleven_tiles_wide_and_some_are_taller_than_the_screen() -> void:
	var tall := 0
	for id in graph.rooms():
		assert_int(graph.size_tiles(id).x).is_equal(11)
		assert_int(graph.size_tiles(id).y).is_greater_equal(20)
		if graph.size_tiles(id).y > 20:
			tall += 1
	assert_int(tall).is_greater_equal(3)


func test_every_tile_and_sprite_has_an_asset_entry() -> void:
	var assets := AssetLoader.new()
	for ch: String in graph.data["legend"]:
		var tile := str(graph.data["legend"][ch]["tile"])
		assert_bool(assets.has(tile)).override_failure_message(tile).is_true()
	for id in graph.rooms():
		for t in graph.things(id):
			var asset := str(t.get("asset", ""))
			if asset != "":
				assert_bool(assets.has(asset)).override_failure_message(asset).is_true()


func test_every_piece_and_sound_the_rooms_name_exists() -> void:
	var story := StoryCatalog.load_all()
	var sfx := SfxBank.new()
	for id in graph.rooms():
		assert_bool(sfx.has(str(graph.room(id).get("sound", "")))).override_failure_message(id).is_true()
		for t in graph.things(id):
			for piece: Variant in t.get("say", []):
				assert_bool(story.get_piece(str(piece)).is_empty()).override_failure_message(str(piece)).is_false()


func test_tap_hit_test_and_paths() -> void:
	var red_panda := graph.thing_at("teahouse", Vector2(5 * 16 + 8, 2 * 16 + 8))
	assert_str(str(red_panda.get("id", ""))).is_equal("red_panda")
	assert_bool(graph.thing_at("teahouse", Vector2(80, 200)).is_empty()).is_true()
	# Inside the Cookie Machine, the cutter is its own hotspot.
	assert_str(str(graph.thing_at("shop", Vector2(120, 40)).get("id", ""))).is_equal("cutter")
	assert_bool(graph.is_walkable("teahouse", Vector2i(5, 2))).is_false()
	var path := graph.path("teahouse", Vector2i(5, 11), Vector2i(5, 18))
	assert_object(path.front()).is_equal(Vector2i(5, 11))
	assert_object(path.back()).is_equal(Vector2i(5, 18))
	assert_object(graph.nearest_walkable("teahouse", Vector2i(0, 8))).is_equal(Vector2i(1, 8))
	assert_str(str(graph.exit_at("teahouse", Vector2i(5, 19)).get("to", ""))).is_equal("square")
