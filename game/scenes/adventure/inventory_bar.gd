# SPDX-License-Identifier: AGPL-3.0-or-later
class_name InventoryBar
extends PanelContainer
## The bar above the room: the crew's items (shared through the scoreboard)
## and this phone's own finds, then Clues and Menu (the only menus). Press an
## item and drag it onto something in the room to use it; a tap shows what it
## is and who found it, and picks it for the next tap in the room.

signal item_tapped(entry: Dictionary)
signal drag_started(entry: Dictionary, at: Vector2)
signal clues_pressed
signal menu_pressed
signal hint_pressed

const SLOT := 44.0
const DRAG_START_PX := 8.0


## One item slot: draws the item's pixel art and turns a press into a tap or a drag.
class ItemSlot:
	extends Control
	var entry: Dictionary = {}
	var texture: Texture2D
	var bar: InventoryBar
	var selected := false
	var _press_at := Vector2.ZERO
	var _pressing := false
	var _dragged := false

	func _ready() -> void:
		custom_minimum_size = Vector2(SLOT, SLOT)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var bg := Color(0.24, 0.2, 0.3) if not selected else Color(0.55, 0.42, 0.18)
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.76, 0.31) if selected else Color(0.45, 0.4, 0.5), false, 2.0)
		if texture != null:
			var px := floorf((size.x - 8.0) / texture.get_width())
			var s := texture.get_size() * maxf(px, 1.0)
			draw_texture_rect(texture, Rect2((size - s) / 2.0, s), false)
		if not bool(entry.get("shared", true)):
			draw_circle(Vector2(size.x - 6, 6), 3.0, Color(0.6, 0.8, 0.9))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressing = true
				_dragged = false
				_press_at = event.position
				Audio.play("select")
				_bounce()
			elif _pressing:
				_pressing = false
				if not _dragged:
					bar.item_tapped.emit(entry)
			accept_event()
		elif event is InputEventMouseMotion and _pressing and not _dragged:
			if (event.position - _press_at).length() > DRAG_START_PX:
				_dragged = true
				_pressing = false
				bar.drag_started.emit(entry, get_global_transform_with_canvas() * event.position)
				accept_event()

	func _bounce() -> void:
		pivot_offset = size / 2.0
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector2(1.12, 1.12), 0.05)
		tween.tween_property(self, "scale", Vector2.ONE, 0.08)


var assets: AssetLoader
var selected_item: String = "":
	set(value):
		selected_item = value
		for slot in _slots:
			slot.selected = str(slot.entry.get("item_id", "")) == value
			slot.queue_redraw()

var _row: HBoxContainer
var _slots_box: HBoxContainer
var _slots: Array[ItemSlot] = []
var _empty: Label
var _clues: Button


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.075, 0.12, 0.96)
	style.border_color = Color(0.45, 0.4, 0.5)
	style.border_width_bottom = 2
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	add_child(_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, SLOT)
	_row.add_child(scroll)
	_slots_box = HBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_slots_box)
	_empty = UiKit.label("Nothing yet. Things you find go here.", 13)
	_empty.add_theme_color_override("font_color", Color(0.7, 0.68, 0.75))
	_empty.custom_minimum_size = Vector2(150, SLOT)
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slots_box.add_child(_empty)
	var hint := UiKit.button("?", Vector2(SLOT, SLOT))
	hint.name = "HintButton"
	hint.add_theme_font_size_override("font_size", 18)
	hint.pressed.connect(func() -> void:
		Audio.play("menu")
		hint_pressed.emit())
	_row.add_child(hint)
	_clues = UiKit.button("Clues", Vector2(58, SLOT))
	_clues.add_theme_font_size_override("font_size", 15)
	_clues.pressed.connect(func() -> void:
		Audio.play("menu")
		clues_pressed.emit())
	_row.add_child(_clues)
	var menu := UiKit.button("Menu", Vector2(56, SLOT))
	menu.add_theme_font_size_override("font_size", 15)
	menu.pressed.connect(func() -> void:
		Audio.play("menu")
		menu_pressed.emit())
	_row.add_child(menu)


## Shows `entries` (Adventure.visible_items()).
func show_items(entries: Array[Dictionary]) -> void:
	for slot in _slots:
		slot.queue_free()
	_slots.clear()
	for entry in entries:
		var slot := ItemSlot.new()
		slot.name = "Slot_" + str(entry["item_id"])
		slot.entry = entry
		slot.bar = self
		slot.texture = assets.texture(str(entry["asset"])) if assets != null else null
		slot.selected = str(entry["item_id"]) == selected_item
		_slots_box.add_child(slot)
		_slots.append(slot)
	_empty.visible = entries.is_empty()
	_clues.text = "Clues %d" % GameState.collected_clue_ids.size() if GameState.collected_clue_ids.size() > 0 else "Clues"


func slot_for(item_id: String) -> Control:
	for slot in _slots:
		if str(slot.entry.get("item_id", "")) == item_id:
			return slot
	return null


func item_ids() -> Array[String]:
	var out: Array[String] = []
	for slot in _slots:
		out.append(str(slot.entry["item_id"]))
	return out
