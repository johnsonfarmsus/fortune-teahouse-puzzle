# SPDX-License-Identifier: AGPL-3.0-or-later
extends PuzzleBase
## A short rhyming note with missing words. Tap a blank, then tap a word from
## the bank; tap a filled blank to clear it. Check tests every blank.
## Config: {lines: ["The mixer hums when the {0} is tight", ...],
## blanks: [{index, answer}], bank: [words incl. distractors], hints: [..],
## intro (optional)}. `{n}` in a line is blank n.

const BLANK_SIZE := Vector2(88, 48)
const WORD_SIZE := Vector2(96, 48)
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)

var _intro: String = ""
var _lines: Array = []
var _blanks: Array = []
var _bank: Array = []
var _hints: Array = []

var _filled: Dictionary = {}  # blank index -> word
var _selected: int = -1
var _blank_buttons: Dictionary = {}  # blank index -> Button
var _word_buttons: Array[Button] = []  # same order as _bank
var _check: Button
var _feedback: Label


func configure(config: Dictionary) -> void:
	_intro = str(config.get("intro", ""))
	_lines = config.get("lines", [])
	_blanks = config.get("blanks", [])
	_bank = config.get("bank", [])
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
	box.add_child(UiKit.label("Tap a blank, then tap a word. Tap a filled blank to clear it.", UiKit.CLUE_SIZE))

	var poem := VBoxContainer.new()
	poem.add_theme_constant_override("separation", 6)
	box.add_child(poem)
	for line: String in _lines:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 4)
		poem.add_child(flow)
		for seg: Dictionary in WordRules.parse_line(line):
			if seg.has("blank"):
				var index: int = seg["blank"]
				var b := UiKit.button("", BLANK_SIZE)
				b.add_theme_font_size_override("font_size", 20)
				b.pressed.connect(tap_blank.bind(index))
				_blank_buttons[index] = b
				if seg.has("before") or seg.has("after"):
					# Punctuation travels with its blank.
					var unit := HBoxContainer.new()
					unit.add_theme_constant_override("separation", 0)
					if seg.has("before"):
						unit.add_child(UiKit.label(str(seg["before"]), 22))
					unit.add_child(b)
					if seg.has("after"):
						unit.add_child(UiKit.label(str(seg["after"]), 22))
					flow.add_child(unit)
				else:
					flow.add_child(b)
			else:
				flow.add_child(UiKit.label(str(seg["text"]), 22))

	box.add_child(UiKit.label("Words:", 20))
	var bank := HFlowContainer.new()
	bank.add_theme_constant_override("h_separation", 6)
	bank.add_theme_constant_override("v_separation", 6)
	box.add_child(bank)
	for word in _bank:
		var b := UiKit.button(str(word), WORD_SIZE)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(choose_word.bind(str(word)))
		bank.add_child(b)
		_word_buttons.append(b)

	_check = UiKit.button("Check", Vector2(140, 52))
	_check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_check.pressed.connect(check)
	box.add_child(_check)
	_feedback = UiKit.label("", UiKit.CLUE_SIZE)
	box.add_child(_feedback)
	_refresh()


# --- Test API -------------------------------------------------------------


func filled() -> Dictionary:
	return _filled.duplicate()


func selected_blank() -> int:
	return _selected


## Tap on a blank: clear it if filled, otherwise select it (or unselect it).
func tap_blank(index: int) -> void:
	if not _blank_buttons.has(index):
		return
	if _filled.has(index):
		_filled.erase(index)
		_selected = -1
	else:
		_selected = -1 if _selected == index else index
	_changed()


## Tap on a bank word: it goes into the selected blank, or the first empty one.
func choose_word(word: String) -> void:
	var target := _selected if _selected != -1 else _first_empty()
	if target != -1:
		fill(target, word)


## Puts `word` in blank `index` if the bank still has that word to spare.
func fill(index: int, word: String) -> void:
	if not _blank_buttons.has(index):
		return
	_filled.erase(index)
	if _unused_count(word) <= 0:
		_changed()
		return
	_filled[index] = word
	_selected = -1
	_changed()


func clear_blank(index: int) -> void:
	if _filled.erase(index):
		_changed()


## Returns true and finishes when every blank is right.
func check() -> bool:
	if _filled.size() < _blanks.size():
		_feedback.text = "Fill every blank first."
		return false
	if WordRules.is_solved(_filled, _blanks):
		_feedback.text = "The note makes sense now. The machine hums."
		finish()
		return true
	_feedback.text = "Not quite. Read the lines aloud: do the pairs rhyme and make sense?"
	return false


# --- PuzzleBase -----------------------------------------------------------


func get_hint_text(level: int) -> String:
	if level == 1:
		if _hints.size() > 0:
			return str(_hints[0])
		return "Read each pair of lines aloud. Lines that rhyme end in the same sound."
	var wrong := WordRules.wrong_blanks(_filled, _blanks)
	if not wrong.is_empty():
		for blank: Dictionary in _blanks:
			if int(blank["index"]) == wrong[0]:
				var answer := str(blank["answer"])
				return "Blank %d is a word of %d letters that starts with \"%s\"." % [wrong[0] + 1, answer.length(), answer.left(1)]
	if _hints.size() > 1:
		return str(_hints[1])
	return "Every word fits. Press Check."


func reveal() -> void:
	_filled.clear()
	for blank: Dictionary in _blanks:
		_filled[int(blank["index"])] = str(blank["answer"])
	_selected = -1
	_refresh()


# --- Display --------------------------------------------------------------


func _first_empty() -> int:
	for blank: Dictionary in _blanks:
		var index := int(blank["index"])
		if not _filled.has(index):
			return index
	return -1


func _unused_count(word: String) -> int:
	var in_bank := 0
	for w in _bank:
		if str(w) == word:
			in_bank += 1
	var used := 0
	for index in _filled:
		if str(_filled[index]) == word:
			used += 1
	return in_bank - used


func _changed() -> void:
	_feedback.text = ""
	_refresh()


func _refresh() -> void:
	for index: int in _blank_buttons:
		var b: Button = _blank_buttons[index]
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		if index == _selected:
			style.bg_color = Color(0.3, 0.22, 0.12)
			style.set_border_width_all(4)
			style.border_color = SELECTED_COLOR
			b.text = "[ %d ]" % (index + 1) if not _filled.has(index) else str(_filled[index])
		else:
			style.bg_color = Color(0.24, 0.17, 0.13) if not _filled.has(index) else Color(0.2, 0.3, 0.22)
			style.set_border_width_all(2)
			style.border_color = Color(0.8, 0.7, 0.5)
			b.text = "( %d )" % (index + 1) if not _filled.has(index) else str(_filled[index])
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, style)
	# A bank button is greyed once its word is in a blank; a word that appears
	# twice in the bank stays usable for its second copy.
	var used: Dictionary = {}
	for index in _filled:
		var word := str(_filled[index])
		used[word] = int(used.get(word, 0)) + 1
	var seen: Dictionary = {}
	for i in _bank.size():
		var word := str(_bank[i])
		seen[word] = int(seen.get(word, 0)) + 1
		_word_buttons[i].disabled = seen[word] <= int(used.get(word, 0))
	_check.disabled = _filled.size() < _blanks.size()
