# SPDX-License-Identifier: AGPL-3.0-or-later
extends PuzzleBase
## Connect labelled terminals (left) to labelled sockets (right). Tap a terminal,
## then a socket; tap a wire (on the drawing or in the list) to remove it.
## Config: {terminals: [{id, label, color}], sockets: [{id, label, color}],
## connections: {terminal_id: socket_id}, hints: [..], intro (optional)}.
## Colour is only decoration: every terminal and socket carries a text label that
## is enough on its own, and every wire also appears in the list as text.

const ROW_HEIGHT := 56.0
const CANVAS_WIDTH := 56.0
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)
const BASE_COLOR := Color(0.24, 0.17, 0.13)
const WIRE_WIDTH := 6.0
const WIRE_HIT_DISTANCE := 20.0


## Draws the wires between the two columns and reports taps on a wire.
class WireCanvas:
	extends Control
	var segments: Callable  # -> Array of {id, from, to, color}, in local coordinates
	var on_wire_tapped: Callable

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		if not segments.is_valid():
			return
		for s: Dictionary in segments.call():
			draw_line(s["from"], s["to"], Color(0.05, 0.03, 0.02), WIRE_WIDTH + 4.0, true)
			draw_line(s["from"], s["to"], s["color"], WIRE_WIDTH, true)

	func _gui_input(event: InputEvent) -> void:
		var mouse := event as InputEventMouseButton
		if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		var best := ""
		var best_dist := WIRE_HIT_DISTANCE
		for s: Dictionary in segments.call():
			var closest := Geometry2D.get_closest_point_to_segment(mouse.position, s["from"], s["to"])
			var dist := closest.distance_to(mouse.position)
			if dist <= best_dist:
				best_dist = dist
				best = str(s["id"])
		if best != "":
			accept_event()
			on_wire_tapped.call(best)


var _intro: String = ""
var _terminals: Array = []
var _sockets: Array = []
var _answer: Dictionary = {}
var _hints: Array = []

var _wires: Dictionary = {}  # terminal id -> socket id
var _sel_terminal: String = ""
var _sel_socket: String = ""
var _terminal_buttons: Dictionary = {}
var _socket_buttons: Dictionary = {}
var _canvas: WireCanvas
var _list: VBoxContainer
var _status: Label
var _feedback: Label
var _check: Button


func configure(config: Dictionary) -> void:
	_intro = str(config.get("intro", ""))
	_terminals = config.get("terminals", [])
	_sockets = config.get("sockets", [])
	_answer = config.get("connections", {})
	_hints = config.get("hints", [])


func _ready() -> void:
	var body := ScrollContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(body)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	body.add_child(box)
	if _intro != "":
		box.add_child(UiKit.label(_intro, UiKit.CLUE_SIZE))
	box.add_child(UiKit.label("Tap a terminal, then a socket. Tap a wire to remove it.", UiKit.CLUE_SIZE))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	box.add_child(cols)
	var left := _column()
	var right := _column()
	_canvas = WireCanvas.new()
	_canvas.custom_minimum_size = Vector2(CANVAS_WIDTH, 0)
	_canvas.segments = _segments
	_canvas.on_wire_tapped = remove_wire
	cols.add_child(left)
	cols.add_child(_canvas)
	cols.add_child(right)
	for node: Container in [cols, left, right]:
		node.sort_children.connect(_redraw_later)

	for t: Dictionary in _terminals:
		var b := _end_button(t)
		b.pressed.connect(tap_terminal.bind(str(t["id"])))
		left.add_child(b)
		_terminal_buttons[str(t["id"])] = b
	for s: Dictionary in _sockets:
		var b := _end_button(s)
		b.pressed.connect(tap_socket.bind(str(s["id"])))
		right.add_child(b)
		_socket_buttons[str(s["id"])] = b

	_status = UiKit.label("", 20)
	box.add_child(_status)
	box.add_child(UiKit.label("Wires (tap one to remove it):", UiKit.CLUE_SIZE))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	box.add_child(_list)
	_check = UiKit.button("Check", Vector2(140, 52))
	_check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_check.pressed.connect(check)
	box.add_child(_check)
	_feedback = UiKit.label("", UiKit.CLUE_SIZE)
	box.add_child(_feedback)
	_refresh()


func _column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	return col


func _end_button(def: Dictionary) -> Button:
	var b := UiKit.button(str(def.get("label", def.get("id", ""))), Vector2(UiKit.MIN_TAP, ROW_HEIGHT))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	return b


func _redraw_later() -> void:
	_canvas.queue_redraw.call_deferred()


func _color_of(def: Dictionary) -> Color:
	return Color.from_string(str(def.get("color", "")), Color(0.7, 0.7, 0.7))


func _def(list: Array, id: String) -> Dictionary:
	for d: Dictionary in list:
		if str(d.get("id", "")) == id:
			return d
	return {}


func _label_of(list: Array, id: String) -> String:
	return str(_def(list, id).get("label", id))


func _segments() -> Array:
	var out: Array = []
	for terminal_id: String in _wires:
		var tb: Button = _terminal_buttons.get(terminal_id)
		var sb: Button = _socket_buttons.get(str(_wires[terminal_id]))
		if tb == null or sb == null or _canvas == null:
			continue
		var origin := _canvas.global_position
		var from := Vector2(0, tb.global_position.y + tb.size.y * 0.5 - origin.y)
		var to := Vector2(_canvas.size.x, sb.global_position.y + sb.size.y * 0.5 - origin.y)
		out.append({"id": terminal_id, "from": from, "to": to, "color": _color_of(_def(_terminals, terminal_id))})
	return out


func _end_style(color: Color, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BASE_COLOR
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if selected:
		style.set_border_width_all(4)
		style.border_color = SELECTED_COLOR
	else:
		style.border_width_left = 10
		style.border_color = color
	return style


func _style_button(b: Button, def: Dictionary, selected: bool, text: String) -> void:
	var style := _end_style(_color_of(def), selected)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, style)
	b.text = text


# --- Test API -------------------------------------------------------------


## Tap on a terminal: select it, or finish a wire if a socket is waiting.
func tap_terminal(id: String) -> void:
	if not _terminal_buttons.has(id):
		return
	if _sel_socket != "":
		connect_wire(id, _sel_socket)
		return
	_sel_terminal = "" if _sel_terminal == id else id
	_refresh()


## Tap on a socket: finish a wire if a terminal is selected, else select it.
func tap_socket(id: String) -> void:
	if not _socket_buttons.has(id):
		return
	if _sel_terminal != "":
		connect_wire(_sel_terminal, id)
		return
	_sel_socket = "" if _sel_socket == id else id
	_refresh()


## Wires `terminal` to `socket`. Older wires on either end are replaced.
func connect_wire(terminal: String, socket: String) -> void:
	if not _terminal_buttons.has(terminal) or not _socket_buttons.has(socket):
		return
	_wires = WiringRules.with_wire(_wires, terminal, socket)
	_sel_terminal = ""
	_sel_socket = ""
	_feedback.text = ""
	_refresh()


func remove_wire(terminal: String) -> void:
	if _wires.erase(terminal):
		_feedback.text = ""
		_refresh()


func wires() -> Dictionary:
	return _wires.duplicate()


## Returns true and finishes when every wire is right.
func check() -> bool:
	if _wires.size() < _terminals.size():
		_feedback.text = "Every terminal needs a wire first."
		return false
	if WiringRules.is_solved(_wires, _answer):
		_feedback.text = "The motor controller clicks on."
		finish()
		return true
	_feedback.text = "Not quite. A wire is on the wrong socket. Read the labels again."
	return false


# --- PuzzleBase -----------------------------------------------------------


func get_hint_text(level: int) -> String:
	if level == 1:
		if _hints.size() > 0:
			return str(_hints[0])
		return "Read each label. The words and numbers say where a wire goes; colour only helps."
	var wrong := WiringRules.wrong_terminals(_wires, _answer)
	if not wrong.is_empty():
		var terminal: String = wrong[0]
		return "Wire \"%s\" to \"%s\"." % [_label_of(_terminals, terminal), _label_of(_sockets, str(_answer[terminal]))]
	if _hints.size() > 1:
		return str(_hints[1])
	return "Every wire looks right. Press Check."


func reveal() -> void:
	_wires = _answer.duplicate()
	_sel_terminal = ""
	_sel_socket = ""
	_refresh()


# --- Display --------------------------------------------------------------


func _refresh() -> void:
	for t: Dictionary in _terminals:
		var id := str(t["id"])
		var text := str(t.get("label", id))
		var selected := _sel_terminal == id
		if _wires.has(id):
			text += "\n-> " + _label_of(_sockets, str(_wires[id]))
		if selected:
			text += " (selected)"
		_style_button(_terminal_buttons[id], t, selected, text)
	for s: Dictionary in _sockets:
		var id := str(s["id"])
		var selected := _sel_socket == id
		var text := str(s.get("label", id))
		if selected:
			text += " (selected)"
		_style_button(_socket_buttons[id], s, selected, text)
	if _sel_terminal != "":
		_status.text = "Now tap a socket for \"%s\"." % _label_of(_terminals, _sel_terminal)
	elif _sel_socket != "":
		_status.text = "Now tap a terminal for \"%s\"." % _label_of(_sockets, _sel_socket)
	else:
		_status.text = "%d of %d wires connected." % [_wires.size(), _terminals.size()]
	UiKit.clear_children(_list)
	for t: Dictionary in _terminals:
		var id := str(t["id"])
		if not _wires.has(id):
			continue
		var row := UiKit.button("%s -> %s" % [_label_of(_terminals, id), _label_of(_sockets, str(_wires[id]))], Vector2(0, 48))
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.pressed.connect(remove_wire.bind(id))
		_list.add_child(row)
	_check.disabled = _wires.size() < _terminals.size()
	_redraw_later()
