# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PortraitDialogue
extends PanelContainer
## The dialogue bar under the room: a portrait (portrait.<speaker>.<expression>
## from the asset list, a placeholder until art lands), the speaker and one
## line at a time, typed out with the speaker's babble beeps, NES style. A tap
## finishes the line, the next tap moves on. Pieces queue, so several things
## can speak in turn. With nothing to say it shows `idle_text` (the room's name).
## Narrator lines have no portrait.

signal finished
signal page_shown(index: int)

const CHARS_PER_SECOND := 70.0
const BABBLE_EVERY := 3
const PORTRAIT_PX := 32
const KIND_WORDS := {"note": "note", "voicemail": "voicemail", "sticky": "sticky label", "sign": "sign"}

var assets: AssetLoader
var pixel_scale: float = 2.0
var idle_text: String = "":
	set(value):
		idle_text = value
		if not is_open() and _body != null:
			_show_idle()

var _pages: Array[Dictionary] = []  # {speaker, kind, expression, text}
var _index := -1
var _revealed := 0.0
var _babbled := 0
var _done_callbacks: Array[Callable] = []
var _portrait: TextureRect
var _speaker: Label
var _body: Label
var _more: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.075, 0.12, 0.96)
	style.border_color = Color(0.95, 0.76, 0.31)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX) * pixel_scale
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	_speaker = UiKit.label("", 15)
	_speaker.add_theme_color_override("font_color", Color(0.95, 0.76, 0.31))
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_speaker)
	_body = UiKit.label("", 17)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_body)
	_more = UiKit.label("", 13)
	_more.add_theme_color_override("font_color", Color(0.7, 0.68, 0.75))
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_more)
	_show_idle()


func _process(delta: float) -> void:
	if not is_open() or _body.visible_characters < 0:
		return
	_revealed += delta * CHARS_PER_SECOND
	var shown := mini(int(_revealed), _body.text.length())
	if shown != _body.visible_characters:
		_body.visible_characters = shown
		if shown - _babbled >= BABBLE_EVERY:
			_babbled = shown
			Audio.play(SfxBank.babble_id(str(_pages[_index]["speaker"])))
	if shown >= _body.text.length():
		_body.visible_characters = -1
		_more.text = "Tap to go on" if _index < _pages.size() - 1 else "Tap to close"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if is_open():
			advance()


## Queues substituted story pieces (Story.get_piece and friends), one page per line.
func say(pieces: Array, done: Callable = Callable()) -> void:
	var was_open := is_open()
	for piece: Variant in pieces:
		if not piece is Dictionary or (piece as Dictionary).is_empty():
			continue
		for line: Variant in piece.get("lines", []):
			_pages.append({
				"speaker": str(piece.get("speaker", "")), "kind": str(piece.get("kind", "")),
				"expression": str(piece.get("expression", "neutral")), "text": str(line),
			})
	if done.is_valid():
		_done_callbacks.append(done)
	if not was_open:
		if _pages.is_empty():
			_finish()
		else:
			_show(0)


## A plain line from the game itself (no story piece), such as "Found by you".
func say_text(speaker: String, text: String, expression: String = "neutral", done: Callable = Callable()) -> void:
	say([{"speaker": speaker, "kind": "dialogue", "expression": expression, "lines": [text]}], done)


func is_open() -> bool:
	return _index >= 0 and _index < _pages.size()


## Finishes the typing, or moves to the next line, or closes.
func advance() -> void:
	if not is_open():
		return
	if _body.visible_characters >= 0:
		_body.visible_characters = -1
		_more.text = "Tap to go on" if _index < _pages.size() - 1 else "Tap to close"
		return
	Audio.play("advance")
	if _index + 1 < _pages.size():
		_show(_index + 1)
	else:
		_finish()


## Closes everything queued.
func skip_all() -> void:
	if is_open():
		_finish()


func current_text() -> String:
	return str(_pages[_index]["text"]) if is_open() else ""


func current_speaker() -> String:
	return str(_pages[_index]["speaker"]) if is_open() else ""


func current_expression() -> String:
	return str(_pages[_index]["expression"]) if is_open() else ""


func portrait_texture() -> Texture2D:
	return _portrait.texture if _portrait.visible else null


func pages_left() -> int:
	return _pages.size() - _index if is_open() else 0


static func portrait_name(speaker: String, expression: String) -> String:
	return "portrait.%s.%s" % [speaker.to_lower().replace(" ", "_"), expression if expression != "" else "neutral"]


func _show(index: int) -> void:
	_index = index
	var page := _pages[index]
	var speaker := str(page["speaker"])
	var kind := str(KIND_WORDS.get(str(page["kind"]), ""))
	_speaker.text = speaker if kind == "" else "%s (%s)" % [speaker, kind]
	_speaker.visible = speaker != "Narrator" or kind != ""
	if speaker == "Narrator":
		_speaker.text = kind.capitalize() if kind != "" else ""
	var key := portrait_name(speaker, str(page["expression"]))
	_portrait.visible = speaker != "Narrator" and assets != null
	if _portrait.visible:
		if not assets.has(key):
			key = portrait_name(speaker, "neutral")
		_portrait.texture = assets.texture(key)
	_body.add_theme_font_size_override("font_size", 17)
	_body.text = str(page["text"])
	_body.visible_characters = 0
	_revealed = 0.0
	_babbled = 0
	_more.text = ""
	Audio.play(SfxBank.babble_id(speaker))
	page_shown.emit(index)


func _finish() -> void:
	_pages.clear()
	_index = -1
	_show_idle()
	var callbacks := _done_callbacks.duplicate()
	_done_callbacks.clear()
	finished.emit()
	for c: Callable in callbacks:
		if c.is_valid():
			c.call()


func _show_idle() -> void:
	if _body == null:
		return
	_portrait.visible = false
	_speaker.visible = true
	_speaker.text = idle_text
	_body.text = "Tap to walk. Tap people and things. Drag items from the bar onto what they fit."
	_body.visible_characters = -1
	_body.add_theme_font_size_override("font_size", 14)
	_more.text = ""
