# SPDX-License-Identifier: AGPL-3.0-or-later
class_name DialogueBox
extends Control
## Shows story pieces one at a time in a panel along the bottom of the screen:
## the speaker, up to three lines and a Skip button. A tap anywhere advances;
## Skip (or Escape) closes the whole sequence. `finished` fires once, when the
## last piece is dismissed or on Skip. Nothing advances by itself unless
## `auto_advance_seconds` is set above zero (off by default).
##
## Hosts use `DialogueBox.open(host, pieces)`: a Control host (a screen) gets
## the box as a child; any other node (a place) gets a CanvasLayer around it.

signal finished
signal advanced(index: int)  # index of the piece now showing

const SKIP_SIZE := Vector2(88, 44)
const KIND_WORDS := {"note": "note", "voicemail": "voicemail", "sticky": "sticky label", "sign": "sign"}

## Seconds before a piece moves on without a tap. 0 means never.
var auto_advance_seconds: float = 0.0
## Free the box (and its layer) when it finishes.
var free_on_finish: bool = true

var _pieces: Array = []
var _index: int = 0
var _done: bool = false
var _speaker: Label
var _body: Label
var _more: Label
var _skip: Button
var _timer: Timer


## Opens a box on `host` showing `pieces` (substituted piece dictionaries).
static func open(host: Node, pieces: Array) -> DialogueBox:
	var box: DialogueBox = load(Paths.DIALOGUE_BOX).instantiate()
	box.show_pieces(pieces)
	if host is Control or host is CanvasLayer:
		host.add_child(box)
	else:
		var layer := CanvasLayer.new()
		layer.layer = 9  # above the Hud (5), below screens (10)
		host.add_child(layer)
		layer.add_child(box)
		box.finished.connect(layer.queue_free)
	return box


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.075, 0.06, 0.97)
	style.border_color = Color(0.95, 0.72, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(0, 160)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 8
	panel.offset_right = -8
	panel.offset_bottom = -8
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	_speaker = UiKit.label("", 20)
	_speaker.add_theme_color_override("font_color", Color(0.95, 0.72, 0.2))
	_speaker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speaker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_speaker)
	_skip = UiKit.button("Skip", SKIP_SIZE)
	_skip.pressed.connect(skip)
	head.add_child(_skip)
	_body = UiKit.label("", UiKit.CLUE_SIZE)
	_body.custom_minimum_size = Vector2(0, 72)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_body)
	_more = UiKit.label("", 16)
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_more)
	_render()


## Starts (or restarts) showing `pieces`. An empty list finishes at once.
func show_pieces(pieces: Array) -> void:
	_pieces = pieces
	_index = 0
	_done = false
	if is_node_ready():
		_render()


func current_index() -> int:
	return _index


func piece_count() -> int:
	return _pieces.size()


func is_done() -> bool:
	return _done


## The piece now showing, or {}.
func current_piece() -> Dictionary:
	if _index < _pieces.size():
		return _pieces[_index]
	return {}


func speaker_text() -> String:
	return _speaker.text if _speaker != null else ""


func body_text() -> String:
	return _body.text if _body != null else ""


## Moves to the next piece, or finishes after the last.
func advance() -> void:
	if _done:
		return
	_index += 1
	if _index >= _pieces.size():
		_finish()
		return
	advanced.emit(_index)
	_render()


## Closes the whole sequence.
func skip() -> void:
	if not _done:
		_finish()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		advance()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		skip()


func _render() -> void:
	if _pieces.is_empty():
		_finish()
		return
	var piece := current_piece()
	var kind := str(KIND_WORDS.get(str(piece.get("kind", "")), ""))
	var speaker := str(piece.get("speaker", ""))
	_speaker.text = speaker if kind == "" else "%s (%s)" % [speaker, kind]
	var lines: Array = piece.get("lines", [])
	_body.text = "\n".join(PackedStringArray(lines.slice(0, 3)))
	var last := _index >= _pieces.size() - 1
	_more.text = "Tap to close" if last else "Tap to go on (%d of %d)" % [_index + 1, _pieces.size()]
	_restart_auto_advance()


func _restart_auto_advance() -> void:
	if auto_advance_seconds <= 0.0:
		if _timer != null:
			_timer.stop()
		return
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.timeout.connect(advance)
		add_child(_timer)
	_timer.start(auto_advance_seconds)


func _finish() -> void:
	if _done:
		return
	_done = true
	if _timer != null:
		_timer.stop()
	visible = false
	finished.emit()
	if free_on_finish:
		queue_free()
