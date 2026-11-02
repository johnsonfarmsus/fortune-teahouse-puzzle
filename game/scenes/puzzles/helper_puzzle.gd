# SPDX-License-Identifier: AGPL-3.0-or-later
extends PuzzleBase
## A friendly helper (Penguin, Seagull, Gopher) talks, then asks one
## multiple-choice question whose answer is in the dialogue.
## Config: {speaker, lines, question, choices, correct, nudge}. `correct` is
## the index of the right choice. Hint 1 shows the nudge; hint 2 crosses off a
## wrong choice.

var _speaker: String = "Helper"
var _lines: Array = []
var _question: String = ""
var _choices: Array = []
var _correct: int = 0
var _nudge: String = ""

var _line_index: int = 0
var _removed: Array[int] = []
var _crossed_off_now: bool = false
var _line_label: Label
var _next_button: Button
var _question_box: VBoxContainer
var _feedback: Label
var _choice_buttons: Array[Button] = []


func configure(config: Dictionary) -> void:
	_speaker = str(config.get("speaker", "Helper"))
	_lines = config.get("lines", [])
	_question = str(config.get("question", ""))
	_choices = config.get("choices", [])
	_correct = int(config.get("correct", 0))
	_nudge = str(config.get("nudge", ""))


func _ready() -> void:
	hint_requested.connect(_on_hint_requested)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var portrait := ColorRect.new()
	portrait.color = Color(0.2, 0.2, 0.25)
	portrait.custom_minimum_size = Vector2(0, 80)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UiKit.label(_speaker, 24)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(name_label)
	box.add_child(portrait)
	_line_label = UiKit.label("", UiKit.CLUE_SIZE + 2)
	_line_label.custom_minimum_size = Vector2(0, 140)
	box.add_child(_line_label)
	_next_button = UiKit.button("Next", Vector2(0, 56))
	_next_button.pressed.connect(advance)
	box.add_child(_next_button)
	_question_box = VBoxContainer.new()
	_question_box.add_theme_constant_override("separation", 8)
	_question_box.visible = false
	box.add_child(_question_box)
	_question_box.add_child(UiKit.label(_question, UiKit.CLUE_SIZE + 2))
	for i in _choices.size():
		var b := UiKit.button(str(_choices[i]), Vector2(0, 56))
		b.pressed.connect(answer_choice.bind(i))
		_question_box.add_child(b)
		_choice_buttons.append(b)
	_feedback = UiKit.label("", UiKit.CLUE_SIZE)
	box.add_child(_feedback)
	_show_line()


## Moves to the next line, then to the question after the last line.
func advance() -> void:
	if _line_index < _lines.size() - 1:
		_line_index += 1
		_show_line()
	else:
		_next_button.visible = false
		_line_label.text = "%s: Now a question for you." % _speaker
		_question_box.visible = true


func is_asking() -> bool:
	return _question_box != null and _question_box.visible


## A tap on a choice. The right one finishes the puzzle.
func answer_choice(index: int) -> void:
	if index == _correct:
		_feedback.text = "Squawk! Yes, that is it."
		finish()
	else:
		_feedback.text = "Not quite. Think about what %s said, then try again." % _speaker


func remaining_choices() -> int:
	return _choices.size() - _removed.size()


func get_hint_text(level: int) -> String:
	if level == 1:
		return _nudge
	if _crossed_off_now:
		return "%s crossed one wrong answer off for you." % _speaker
	return "Only two answers are left. Think about what %s said." % _speaker


func reveal() -> void:
	_next_button.visible = false
	_question_box.visible = true
	if _correct >= 0 and _correct < _choices.size():
		_feedback.text = "The answer is: %s" % str(_choices[_correct])


func _show_line() -> void:
	var text := str(_lines[_line_index]) if _line_index < _lines.size() else ""
	_line_label.text = "%s: %s" % [_speaker, text]
	if _line_index >= _lines.size() - 1:
		_next_button.text = "Ask me a question"


func _on_hint_requested(level: int) -> void:
	if level != 2:
		return
	_crossed_off_now = false
	# Cross off one wrong choice, always leaving the right one and one wrong.
	if remaining_choices() <= 2:
		return
	for i in _choices.size():
		if i != _correct and not _removed.has(i):
			_removed.append(i)
			_choice_buttons[i].disabled = true
			_choice_buttons[i].text = "(crossed off)"
			_crossed_off_now = true
			return
