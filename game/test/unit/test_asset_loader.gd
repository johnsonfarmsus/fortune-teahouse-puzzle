# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## AssetLoader: the asset list is well formed, a missing file falls back to a
## labelled placeholder, and a file that exists is used instead.

var assets: AssetLoader


func before_test() -> void:
	assets = AssetLoader.new()


func test_asset_list_is_well_formed() -> void:
	assert_int(assets.names().size()).is_greater(50)
	assert_int(assets.tile_size).is_equal(16)
	for asset_name in assets.names():
		var d := assets.def(asset_name)
		assert_bool(AssetLoader.KINDS.has(str(d.get("kind", "")))).override_failure_message(asset_name).is_true()
		assert_str(str(d.get("file", ""))).override_failure_message(asset_name).starts_with("art/")
		var size := assets.frame_size(asset_name)
		assert_bool(size.x > 0 and size.y > 0).is_true()
		var frames := assets.frame_count(asset_name)
		for anim: String in d.get("animations", {}):
			for index: Variant in d["animations"][anim]["frames"]:
				assert_int(int(index)).override_failure_message("%s %s" % [asset_name, anim]).is_less(frames)
		if d.has("color"):
			assert_bool(assets.palette.has(str(d["color"]))).override_failure_message(asset_name).is_true()
		if asset_name.begins_with("tile."):
			assert_object(size).is_equal(Vector2i(16, 16))
			# Pack tiles, or composites baked from them (art-src/tiles/composites.json).
			var file := str(d["file"])
			assert_bool(file.begins_with("art/ninja/") or file.begins_with("art/tiles/")).override_failure_message(asset_name).is_true()


func test_every_asset_draws_at_its_size_from_its_file_or_a_placeholder() -> void:
	# The neutral portraits have landed (WP27); the rest are still placeholders.
	assert_bool(assets.is_placeholder("portrait.red_panda.neutral")).is_false()
	assert_bool(assets.is_placeholder("portrait.red_panda.happy")).is_true()
	for asset_name in assets.names():
		var landed := ResourceLoader.exists(assets.path_for(asset_name))
		assert_bool(assets.is_placeholder(asset_name)).override_failure_message(asset_name).is_equal(not landed)
		var tex := assets.texture(asset_name)
		assert_object(tex).is_not_null()
		assert_object(Vector2i(tex.get_size())).override_failure_message(asset_name).is_equal(assets.frame_size(asset_name))


func test_placeholder_is_a_block_with_an_outline_and_a_glyph() -> void:
	var image := assets.placeholder_image("item.spanner")
	var fill := assets.color("silver")
	var corner := image.get_pixel(0, 0)
	assert_float(corner.a).is_equal(0.0)  # rounded corner
	var edge := image.get_pixel(8, 0)
	assert_bool(edge.is_equal_approx(fill)).is_false()  # outline
	var inks := 0
	var fills := 0
	for y in range(1, 15):
		for x in range(1, 15):
			var c := image.get_pixel(x, y)
			if c.is_equal_approx(fill):
				fills += 1
			elif c.a > 0.0:
				inks += 1
	assert_int(fills).is_greater(100)
	assert_int(inks).is_greater(5)  # the glyph


func test_unknown_name_still_draws_something() -> void:
	assert_bool(assets.has("nope.nothing")).is_false()
	var tex := assets.texture("nope.nothing")
	assert_object(Vector2i(tex.get_size())).is_equal(Vector2i(16, 16))


func test_character_placeholders_animate() -> void:
	var frames := assets.frames("char.player")
	for anim in ["walk_down", "walk_up", "walk_left", "walk_right", "idle_down"]:
		assert_bool(frames.has_animation(anim)).is_true()
	assert_int(frames.get_frame_count("walk_down")).is_between(2, 4)
	var a := frames.get_frame_texture("walk_down", 0).get_image()
	var b := frames.get_frame_texture("walk_down", 1).get_image()
	assert_bool(a.get_data() == b.get_data()).is_false()
	var left := frames.get_frame_texture("walk_left", 0).get_image()
	assert_bool(a.get_data() == left.get_data()).is_false()
	var npc := assets.frames("char.penguin")
	var i0 := npc.get_frame_texture("idle_down", 0).get_image()
	var i1 := npc.get_frame_texture("idle_down", 1).get_image()
	assert_bool(i0.get_data() == i1.get_data()).is_false()  # idle bob


func test_portraits_cover_every_speaker_and_expression_used() -> void:
	var story := StoryCatalog.load_all()
	for piece: Dictionary in story.pieces_for("room:shop") + story.pieces_for("room:workshop") + story.pieces_for("room:harbour"):
		var speaker := str(piece["speaker"])
		if speaker == "Narrator":
			continue
		var key := "portrait.%s.%s" % [speaker.to_lower().replace(" ", "_"), str(piece.get("expression", "neutral"))]
		assert_bool(assets.has(key)).override_failure_message(key).is_true()


func test_a_file_that_exists_replaces_the_placeholder() -> void:
	var loader := AssetLoader.new("", {
		"tile_size": 16, "palette": {"red": "#ff0000"},
		"assets": {
			"real": {"file": "icon.svg", "frame_size": [128, 128], "frames": 1, "kind": "prop", "color": "red"},
			"part": {"file": "icon.svg", "frame_size": [64, 64], "frames": 4, "columns": 2, "kind": "prop", "color": "red"},
			"missing": {"file": "art/none/missing.png", "frame_size": [16, 16], "frames": 1, "kind": "prop", "color": "red"},
		},
	})
	assert_bool(loader.is_placeholder("real")).is_false()
	assert_bool(loader.texture("real") is ImageTexture).is_false()
	var frame := loader.texture("part", 3)
	assert_bool(frame is AtlasTexture).is_true()
	assert_object((frame as AtlasTexture).region).is_equal(Rect2(64, 64, 64, 64))
	assert_bool(loader.is_placeholder("missing")).is_true()
	assert_bool(loader.texture("missing") is ImageTexture).is_true()


func test_a_portrait_falls_back_to_neutral_until_its_own_art_lands() -> void:
	var loader := AssetLoader.new("", {
		"tile_size": 16, "palette": {"red": "#ff0000"},
		"assets": {
			"portrait.fox.neutral": {"file": "icon.svg", "frame_size": [32, 32], "frames": 1, "kind": "portrait", "color": "red"},
			"portrait.fox.happy": {"file": "art/none/fox_happy.png", "frame_size": [32, 32], "frames": 1, "kind": "portrait", "color": "red"},
			"portrait.owl.neutral": {"file": "art/none/owl_neutral.png", "frame_size": [32, 32], "frames": 1, "kind": "portrait", "color": "red"},
			"portrait.owl.happy": {"file": "art/none/owl_happy.png", "frame_size": [32, 32], "frames": 1, "kind": "portrait", "color": "red"},
		},
	})
	# Neutral art has landed and happy has not: show the real neutral portrait.
	assert_str(PortraitDialogue.portrait_key(loader, "Fox", "happy")).is_equal("portrait.fox.neutral")
	# An unlisted expression falls back to neutral too.
	assert_str(PortraitDialogue.portrait_key(loader, "Fox", "sly")).is_equal("portrait.fox.neutral")
	# All placeholders: keep the expression's own placeholder (it draws the mouth).
	assert_str(PortraitDialogue.portrait_key(loader, "Owl", "happy")).is_equal("portrait.owl.happy")
	assert_str(PortraitDialogue.portrait_key(loader, "Owl", "")).is_equal("portrait.owl.neutral")
