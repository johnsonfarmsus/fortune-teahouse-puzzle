# SPDX-License-Identifier: AGPL-3.0-or-later
extends PuzzleBase
## Five items to five ordered places, driven entirely by data. Config:
## {machine, domain, answer, clues (collected only), total_clues, threshold}.
## Tap a chip, then a slot; or drag. A wrong Check never says how many are right.

const SLOT_HEIGHT := 60.0
const CHIP_SIZE := Vector2(104, 48)
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)


## A slot row. Drags its item out and accepts dropped items.
class SlotButton:
	extends Button
	var slot: int = 0
	var item_in_slot: Callable
	var item_text: Callable
	var on_drop: Callable

	func _get_drag_data(_at: Vector2) -> Variant:
		var item: String = item_in_slot.call(slot)
		if item == "":
			return null
		var preview := Label.new()
		preview.text = item_text.call(item)
		set_drag_preview(preview)
		return {"item": item}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("item")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		on_drop.call(data["item"], slot)


## A tray chip. Can be dragged to a slot.
class ChipButton:
	extends Button
	var item: String = ""

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = text
		set_drag_preview(preview)
		return {"item": item}


var _domain: Dictionary = {}
var _answer: Dictionary = {}
var _clues: Array = []
var _total_clues: int = 6
var _threshold: int = 4

var _placement: Dictionary = {}  # item -> slot (1-based)
var _selected: String = ""
var _slots: Array[SlotButton] = []
var _chips: Dictionary = {}  # item -> ChipButton
var _cards: Dictionary = {}  # clue id -> ClueCard
var _check: Button
var _feedback: Label
var _status: Label
var _start_here_id: String = ""
var _level_two_calls: int = 0


func configure(config: Dictionary) -> void:
	_domain = config.get("domain", {})
	_answer = config.get("answer", {})
	_clues = config.get("clues", [])
	_total_clues = int(config.get("total_clues", 6))
	_threshold = int(config.get("threshold", Ids.CLUE_THRESHOLD))


func _ready() -> void:
	# The whole body scrolls, so nothing is cut off on a 390x844 viewport.
	var body := ScrollContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(body)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	body.add_child(box)
	var noun := str(_domain.get("position_noun", "place"))
	var item_noun := str(_domain.get("item_noun", ""))
	if item_noun == "":
		box.add_child(UiKit.label("Which one goes in which %s?" % noun, 20))
	else:
		box.add_child(UiKit.label("Which %s goes in which %s?" % [item_noun, noun], 20))

	var positions: Array = _domain.get("positions", [])
	for i in positions.size():
		var slot := SlotButton.new()
		slot.slot = i + 1
		slot.item_in_slot = _item_in_slot
		slot.item_text = _item_name
		slot.on_drop = place
		slot.custom_minimum_size = Vector2(UiKit.MIN_TAP, SLOT_HEIGHT)
		slot.focus_mode = Control.FOCUS_NONE
		slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slot.pressed.connect(_on_slot_pressed.bind(i + 1))
		box.add_child(slot)
		_slots.append(slot)

	_status = UiKit.label("", 18)
	box.add_child(_status)
	var tray := HFlowContainer.new()
	tray.add_theme_constant_override("h_separation", 6)
	tray.add_theme_constant_override("v_separation", 6)
	box.add_child(tray)
	for item: String in _domain.get("items", []):
		var chip := ChipButton.new()
		chip.item = item
		chip.text = _item_name(item)
		chip.custom_minimum_size = CHIP_SIZE
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(_on_chip_pressed.bind(item))
		tray.add_child(chip)
		_chips[item] = chip

	_check = UiKit.button("Check", Vector2(140, 52))
	_check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_check.pressed.connect(check)
	box.add_child(_check)
	_feedback = UiKit.label("", 18)
	box.add_child(_feedback)

	box.add_child(UiKit.label("Clues: %d of %d (%d needed)" % [_clues.size(), _total_clues, _threshold], 20))
	if _clues.is_empty():
		box.add_child(UiKit.label("Find your crewmates and enter their lucky words at the Teahouse.", UiKit.CLUE_SIZE))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 0)
	list.add_theme_constant_override("separation", 6)
	box.add_child(list)
	for clue: Dictionary in _clues:
		var card: ClueCard = load(Paths.CLUE_CARD).instantiate()
		card.setup(clue)
		list.add_child(card)
		_cards[clue["id"]] = card
	_refresh()


# --- Test API -------------------------------------------------------------


## Puts `item` in `slot` (1-based). A displaced item returns to the tray.
func place(item: String, slot: int) -> void:
	if not _chips.has(item) or slot < 1 or slot > _slots.size():
		return
	_placement.erase(item)
	for other: String in _placement.keys():
		if int(_placement[other]) == slot:
			_placement.erase(other)
	_placement[item] = slot
	if _selected == item:
		_selected = ""
	_refresh()


func clear_slot(slot: int) -> void:
	for item: String in _placement.keys():
		if int(_placement[item]) == slot:
			_placement.erase(item)
	_refresh()


func placement() -> Dictionary:
	return _placement.duplicate()


## Returns true and finishes when the placement is the answer.
func check() -> bool:
	if _placement.size() < _chips.size():
		return false
	if MatchingRules.is_solved(_placement, _answer):
		_feedback.text = "That works! The machine hums."
		finish()
		return true
	_feedback.text = "Not quite. Read your clues again."
	return false


# --- PuzzleBase -----------------------------------------------------------


func can_reveal() -> bool:
	return _clues.size() >= _threshold


func get_hint_text(level: int) -> String:
	if level == 1:
		return _hint_one()
	return _hint_two()


func reveal() -> void:
	_placement = _answer.duplicate()
	_refresh()


# --- Internals ------------------------------------------------------------


func _hint_one() -> String:
	if _clues.is_empty():
		return "You have no clues yet. Find your crewmates and enter their lucky words at the Teahouse."
	var chosen: Dictionary = _clues[0]
	for clue: Dictionary in _clues:
		if clue["fact"]["kind"] == "position":
			chosen = clue
			break
	_start_here_id = chosen["id"]
	for id: String in _cards:
		(_cards[id] as ClueCard).mark_start_here(id == _start_here_id)
	return "Start with the clue marked Start here."


func _hint_two() -> String:
	var broken: Array = []
	for style in Ids.HINT_STYLE_ORDER:
		for clue: Dictionary in _clues:
			if clue["style"] == style and not MatchingRules.fact_holds(clue["fact"], _placement):
				broken.append(clue)
	if broken.is_empty():
		if _clues.is_empty():
			return "Find your crewmates and enter their lucky words at the Teahouse."
		return "All your clues fit so far. Keep going."
	var clue: Dictionary = broken[_level_two_calls % broken.size()]
	_level_two_calls += 1
	return "A clue says: %s" % MatchingRules.fact_to_text(clue["fact"], _domain)


func _item_name(item: String) -> String:
	var names: Dictionary = _domain.get("item_names", {})
	return str(names.get(item, item))


func _item_in_slot(slot: int) -> String:
	for item: String in _placement:
		if int(_placement[item]) == slot:
			return item
	return ""


func _on_chip_pressed(item: String) -> void:
	_selected = "" if _selected == item else item
	_refresh()


func _on_slot_pressed(slot: int) -> void:
	if _selected != "":
		place(_selected, slot)
	elif _item_in_slot(slot) != "":
		clear_slot(slot)


func _refresh() -> void:
	var positions: Array = _domain.get("positions", [])
	for i in _slots.size():
		var item := _item_in_slot(i + 1)
		var label := str(positions[i])
		_slots[i].text = "%s: %s" % [label, _item_name(item) if item != "" else "(empty)"]
	for item: String in _chips:
		var chip: ChipButton = _chips[item]
		chip.visible = not _placement.has(item)
		if item == _selected:
			var outline := StyleBoxFlat.new()
			outline.bg_color = Color(0.25, 0.2, 0.15)
			outline.set_border_width_all(4)
			outline.border_color = SELECTED_COLOR
			chip.add_theme_stylebox_override("normal", outline)
			chip.add_theme_stylebox_override("hover", outline)
			chip.add_theme_stylebox_override("pressed", outline)
		else:
			chip.remove_theme_stylebox_override("normal")
			chip.remove_theme_stylebox_override("hover")
			chip.remove_theme_stylebox_override("pressed")
	_check.disabled = _placement.size() < _chips.size()
	if _selected != "":
		_status.text = "Selected: %s. Now tap a %s." % [_item_name(_selected), _domain.get("position_noun", "place")]
	else:
		_status.text = "Tap an item, then tap where it goes."
