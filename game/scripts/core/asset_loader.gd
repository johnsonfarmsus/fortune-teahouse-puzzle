# SPDX-License-Identifier: AGPL-3.0-or-later
class_name AssetLoader
extends RefCounted
## Every sprite, tile and portrait is loaded by logical name through this class
## (PLAN.md D11). `game/assets.json` maps a name to
##   {file, frame_size: [w, h], frames, kind, origin?, columns?, animations?,
##    color?, outline?, ink?, glyph?, expression?, frame_colors?, frame_glyphs?}
## `file` is relative to res://. When it has not landed yet (no imported
## resource at that path), a labelled placeholder is drawn in code instead: a
## block in a palette colour with a 1 px outline and a letter or glyph, so the
## game runs with no binary art committed. Real art replaces a placeholder by
## adding the file; nothing else changes.
##
## Frames are read left to right, top to bottom from `origin`, `columns` per
## row (default: all frames in one row). `animations` maps an animation name to
## {frames: [indices], fps}; names such as walk_down and idle_left also tell the
## placeholder which way a character faces.

const LIST_PATH := "res://assets.json"
const UNKNOWN_COLOR := Color(0.85, 0.2, 0.75)
const KINDS: Array[String] = ["tile", "character", "portrait", "item", "prop", "fx", "glyph"]

static var _shared: AssetLoader

var tile_size: int = 16
var palette: Dictionary = {}  # name -> Color
var assets: Dictionary = {}  # logical name -> definition
var _textures: Dictionary = {}  # cache key -> Texture2D
var _frames: Dictionary = {}  # name -> SpriteFrames


## The game's one loader (assets.json read once).
static func shared() -> AssetLoader:
	if _shared == null:
		_shared = AssetLoader.new()
	return _shared


## Drops the shared loader and its cached textures (Adventure does this on exit).
static func release_shared() -> void:
	if _shared != null:
		_shared._textures.clear()
		_shared._frames.clear()
	_shared = null


## Reads `list_path`, or uses `data` when given (tests).
func _init(list_path: String = LIST_PATH, data: Dictionary = {}) -> void:
	var source := data if not data.is_empty() else JsonFile.read(list_path)
	tile_size = int(source.get("tile_size", 16))
	var colours: Dictionary = source.get("palette", {})
	for key: String in colours:
		palette[key] = Color.from_string(str(colours[key]), UNKNOWN_COLOR)
	assets = source.get("assets", {})


func has(asset_name: String) -> bool:
	return assets.has(asset_name)


func def(asset_name: String) -> Dictionary:
	return assets.get(asset_name, {})


func names() -> Array[String]:
	var out: Array[String] = []
	for key: String in assets:
		out.append(key)
	return out


## The res:// path the art should land at, or "" for an unknown name.
func path_for(asset_name: String) -> String:
	var file := str(def(asset_name).get("file", ""))
	return "" if file == "" else "res://" + file.trim_prefix("res://")


func file_exists(asset_name: String) -> bool:
	var path := path_for(asset_name)
	return path != "" and ResourceLoader.exists(path)


func is_placeholder(asset_name: String) -> bool:
	return not file_exists(asset_name)


func frame_size(asset_name: String) -> Vector2i:
	var raw: Array = def(asset_name).get("frame_size", [tile_size, tile_size])
	if raw.size() < 2:
		return Vector2i(tile_size, tile_size)
	return Vector2i(int(raw[0]), int(raw[1]))


func frame_count(asset_name: String) -> int:
	return maxi(1, int(def(asset_name).get("frames", 1)))


## A palette colour by name, or any Color.from_string value.
func color(key: String, fallback: Color = UNKNOWN_COLOR) -> Color:
	if palette.has(key):
		return palette[key]
	return Color.from_string(key, fallback)


## One frame. `anim` and `step` only matter for placeholders (which way a
## character faces, which foot is down).
func texture(asset_name: String, frame: int = 0, anim: String = "", step: int = 0) -> Texture2D:
	var key := "%s#%d#%s#%d" % [asset_name, frame, anim, step]
	if _textures.has(key):
		return _textures[key]
	var tex: Texture2D
	if file_exists(asset_name):
		tex = _file_frame(asset_name, frame)
	if tex == null:
		tex = ImageTexture.create_from_image(placeholder_image(asset_name, frame, anim, step))
	_textures[key] = tex
	return tex


## Animations as SpriteFrames. Without `animations` there is one, "default",
## with every frame at the definition's `fps` (default 4).
func frames(asset_name: String) -> SpriteFrames:
	if _frames.has(asset_name):
		return _frames[asset_name]
	var out := SpriteFrames.new()
	var d := def(asset_name)
	var anims: Dictionary = d.get("animations", {})
	if anims.is_empty():
		var all: Array = []
		for i in frame_count(asset_name):
			all.append(i)
		anims = {"default": {"frames": all, "fps": float(d.get("fps", 4))}}
	for anim: String in anims:
		var spec: Dictionary = anims[anim]
		if not out.has_animation(anim):
			out.add_animation(anim)
		out.set_animation_speed(anim, float(spec.get("fps", 4)))
		out.set_animation_loop(anim, bool(spec.get("loop", true)))
		var list: Array = spec.get("frames", [0])
		for step in list.size():
			out.add_frame(anim, texture(asset_name, int(list[step]), anim, step))
	if out.has_animation("default") and not anims.has("default"):
		out.remove_animation("default")
	_frames[asset_name] = out
	return out


func _file_frame(asset_name: String, frame: int) -> Texture2D:
	var whole := load(path_for(asset_name)) as Texture2D
	if whole == null:
		return null
	var d := def(asset_name)
	var size := frame_size(asset_name)
	var columns := maxi(1, int(d.get("columns", frame_count(asset_name))))
	var origin_raw: Array = d.get("origin", [0, 0])
	var origin := Vector2i(int(origin_raw[0]), int(origin_raw[1])) if origin_raw.size() >= 2 else Vector2i.ZERO
	var at := origin + Vector2i((frame % columns) * size.x, (frame / columns) * size.y)
	if at == Vector2i.ZERO and Vector2i(whole.get_size()) == size:
		return whole
	var atlas := AtlasTexture.new()
	atlas.atlas = whole
	atlas.region = Rect2(at, size)
	return atlas


# --- Placeholders -------------------------------------------------------------------


## The labelled placeholder for one frame. An unknown name gives a magenta "?".
func placeholder_image(asset_name: String, frame: int = 0, anim: String = "", step: int = 0) -> Image:
	var d := def(asset_name)
	var size := frame_size(asset_name)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var fill := color(str(d.get("color", "")), UNKNOWN_COLOR) if not d.is_empty() else UNKNOWN_COLOR
	var outline := color(str(d.get("outline", "")), fill.darkened(0.5)) if d.has("outline") else fill.darkened(0.5)
	var ink_default := color("black", Color.BLACK) if fill.get_luminance() > 0.55 else color("cream", Color.WHITE)
	var ink := color(str(d.get("ink", "")), ink_default) if d.has("ink") else ink_default
	var glyph := str(d.get("glyph", "?" if d.is_empty() else asset_name.get_slice(".", asset_name.get_slice_count(".") - 1).left(1).to_upper()))
	# Per-frame colours and glyphs let placeholders show states (a lamp off and on, dial digits).
	var frame_colors: Array = d.get("frame_colors", [])
	if not frame_colors.is_empty():
		fill = color(str(frame_colors[frame % frame_colors.size()]), fill)
		outline = fill.darkened(0.5)
	var frame_glyphs: Array = d.get("frame_glyphs", [])
	if not frame_glyphs.is_empty():
		glyph = str(frame_glyphs[frame % frame_glyphs.size()])
	match str(d.get("kind", "item")):
		"tile":
			_tile(image, fill, outline, ink, glyph, frame, bool(d.get("outline_tile", true)))
		"character":
			_character(image, fill, outline, ink, glyph, anim, step)
		"portrait":
			_portrait(image, fill, outline, ink, glyph, str(d.get("expression", "neutral")), color(str(d.get("bg", "sky")), Color(0.6, 0.78, 0.9)))
		"fx":
			_fx(image, fill, frame)
		"glyph":
			PixelGlyphs.draw_text(image, glyph, Rect2i(Vector2i.ZERO, size), fill, 1)
		_:
			_block(image, Rect2i(Vector2i.ZERO, size), fill, outline, true)
			var scale := 2 if size.x >= 32 and size.y >= 24 and glyph.length() <= 2 else 1
			PixelGlyphs.draw_text(image, glyph, Rect2i(Vector2i.ZERO, size), ink, scale)
	return image


func _block(image: Image, rect: Rect2i, fill: Color, outline: Color, rounded: bool) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var edge_x := x == rect.position.x or x == rect.end.x - 1
			var edge_y := y == rect.position.y or y == rect.end.y - 1
			if rounded and edge_x and edge_y:
				continue
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			image.set_pixel(x, y, outline if edge_x or edge_y else fill)


func _tile(image: Image, fill: Color, outline: Color, ink: Color, glyph: String, frame: int, edged: bool) -> void:
	var w := image.get_width()
	var h := image.get_height()
	image.fill(fill)
	if edged:
		var soft := fill.lerp(outline, 0.55)
		for x in w:
			image.set_pixel(x, h - 1, soft)
		for y in h:
			image.set_pixel(w - 1, y, soft)
	if glyph != "" and glyph != " ":
		# Animated tiles (water) slide their glyph a little each frame.
		var shift := (frame % 4) * 2 - 2
		var mark := fill.lerp(ink, 0.35)
		PixelGlyphs.draw_glyph(image, glyph, Vector2i(3 + shift, 3), mark)
		PixelGlyphs.draw_glyph(image, glyph, Vector2i(10 - shift, 9), mark)


func _character(image: Image, fill: Color, outline: Color, ink: Color, glyph: String, anim: String, step: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var facing := "down"
	for dir: String in ["down", "up", "left", "right"]:
		if anim.ends_with(dir):
			facing = dir
	var walking := anim.begins_with("walk")
	var bob := 1 if (not walking and step % 2 == 1) else 0
	var body := Rect2i(2, 1 + bob, w - 4, h - 3 - bob)
	_block(image, body, fill, outline, true)
	# Feet: both down when idle, one at a time when walking.
	var feet_y := h - 2
	var left_down := not walking or step % 2 == 0
	var right_down := not walking or step % 2 == 1
	for x in range(4, 7):
		image.set_pixel(x, feet_y + (0 if left_down else -1), outline)
	for x in range(w - 7, w - 4):
		image.set_pixel(x, feet_y + (0 if right_down else -1), outline)
	if facing == "up":
		PixelGlyphs.draw_glyph(image, glyph.left(1), Vector2i(w / 2 - 1, 6 + bob), fill.darkened(0.25))
		return
	PixelGlyphs.draw_glyph(image, glyph.left(1), Vector2i(w / 2 - 1, 7 + bob), ink)
	var eye_y := 4 + bob
	match facing:
		"left":
			image.set_pixel(4, eye_y, ink)
		"right":
			image.set_pixel(w - 5, eye_y, ink)
		_:
			image.set_pixel(5, eye_y, ink)
			image.set_pixel(w - 6, eye_y, ink)


func _portrait(image: Image, fill: Color, outline: Color, ink: Color, glyph: String, expression: String, bg: Color) -> void:
	var w := image.get_width()
	var h := image.get_height()
	_block(image, Rect2i(0, 0, w, h), bg, outline, false)
	_block(image, Rect2i(4, 4, w - 8, h - 6), fill, outline, true)
	PixelGlyphs.draw_text(image, glyph.left(1), Rect2i(4, 6, w - 8, 12), ink, 2)
	var cx := w / 2
	var my := h - 9
	var eyes_y := 7
	image.set_pixel(9, eyes_y, ink)
	image.set_pixel(w - 10, eyes_y, ink)
	match expression:
		"happy":
			for x in range(cx - 3, cx + 4):
				image.set_pixel(x, my + (1 if absi(x - cx) < 3 else 0), ink)
		"worried":
			for x in range(cx - 3, cx + 4):
				image.set_pixel(x, my + (0 if absi(x - cx) < 3 else 1), ink)
			image.set_pixel(8, eyes_y - 2, ink)
			image.set_pixel(w - 9, eyes_y - 2, ink)
		"surprised":
			for p: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-2, 0), Vector2i(2, 0)]:
				image.set_pixelv(Vector2i(cx, my) + p, ink)
		"sly":
			for i in 6:
				image.set_pixel(cx - 3 + i, my + (1 if i < 3 else 0), ink)
		_:
			for x in range(cx - 2, cx + 3):
				image.set_pixel(x, my, ink)


func _fx(image: Image, fill: Color, frame: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var r := 1 + frame
	var c := Vector2i(w / 2, h / 2)
	for y in h:
		for x in w:
			var d := Vector2(x - c.x, y - c.y).length()
			if absf(d - r) < 0.8:
				image.set_pixel(x, y, fill)
