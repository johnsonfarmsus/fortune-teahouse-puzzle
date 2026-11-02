# SPDX-License-Identifier: AGPL-3.0-or-later
extends PuzzleBase
## Sync the press to the conveyor beat. Visual first, no time pressure, no fail
## state: a light pulses at a steady tempo, the player taps Press on the lit
## beats, and each on-beat tap lights one indicator. An off-beat tap just starts
## the row again with a gentle message. Sound (Audio "tick") and haptics are
## optional extras.
## Config: {bpm, pattern: [1,0,1,1], tolerance_ms (default 180), required
## (default 6), hints: [..], intro (optional)}.
## Hint 1 says to watch the light; hint 2 slows the tempo by 25 percent;
## reveal() lights the whole row. The beat clock is RhythmClock, advanced from
## _process with the frame delta (no Timer nodes). Tests set manual_clock and
## drive it with advance() and press().

const SLOW_PERCENT := 25.0
const MAX_FRAME := 0.25  # a stalled tab never fires a burst of beats
const LIT_COLOR := Color(1.0, 0.8, 0.2)
const DIM_COLOR := Color(0.22, 0.16, 0.12)

## Tests set this before add_child to stop _process from moving the clock.
var manual_clock: bool = false
var clock: RhythmClock

var _intro: String = ""
var _hints: Array = []
var _bpm: float = 90.0
var _pattern: Array = [1, 0, 1, 1]
var _tolerance_ms: float = 180.0
var _required: int = 6

var _light: ColorRect
var _light_label: Label
var _steps: Array[Label] = []
var _lamps: Array[Label] = []
var _count: Label
var _press: Button
var _message: Label
var _shown_key: String = ""
var _slowed: bool = false


func configure(config: Dictionary) -> void:
	_intro = str(config.get("intro", ""))
	_hints = config.get("hints", [])
	_bpm = float(config.get("bpm", 90))
	_pattern = config.get("pattern", [1, 0, 1, 1])
	_tolerance_ms = float(config.get("tolerance_ms", 180))
	_required = int(config.get("required", 6))
	clock = RhythmClock.new(_bpm, _pattern, _tolerance_ms, _required)


func _ready() -> void:
	if clock == null:
		configure({})
	clock.beat.connect(_on_beat)
	hint_requested.connect(_on_hint_requested)
	set_process(not manual_clock)

	var body := ScrollContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(body)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	body.add_child(box)
	if _intro != "":
		box.add_child(UiKit.label(_intro, UiKit.CLUE_SIZE))
	box.add_child(
		UiKit.label(
			"Watch the conveyor light. Tap Press when it glows. Get %d in a row. There is no hurry." % clock.required,
			UiKit.CLUE_SIZE
		)
	)

	_light = ColorRect.new()
	_light.custom_minimum_size = Vector2(0, 110)
	_light.color = DIM_COLOR
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_light)
	_light_label = UiKit.label("", 32)
	_light_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_light_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_light_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_light.add_child(_light_label)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	box.add_child(bar)
	for i in clock.pattern.size():
		var step := UiKit.label("Press" if clock.is_lit(i) else "Rest", 18)
		step.custom_minimum_size = Vector2(UiKit.MIN_TAP, UiKit.MIN_TAP)
		step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		step.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bar.add_child(step)
		_steps.append(step)

	var lamps := HBoxContainer.new()
	lamps.add_theme_constant_override("separation", 6)
	box.add_child(lamps)
	for i in clock.required:
		var lamp := UiKit.label("( )", 24)
		lamp.custom_minimum_size = Vector2(UiKit.MIN_TAP, UiKit.MIN_TAP)
		lamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lamps.add_child(lamp)
		_lamps.append(lamp)
	_count = UiKit.label("", 20)
	box.add_child(_count)

	_press = UiKit.button("Press", Vector2(0, 96))
	_press.add_theme_font_size_override("font_size", 32)
	_press.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_press.button_down.connect(press)
	box.add_child(_press)
	_message = UiKit.label("", UiKit.CLUE_SIZE)
	box.add_child(_message)
	_refresh()


func _process(delta: float) -> void:
	advance(minf(delta, MAX_FRAME))


# --- Test API -------------------------------------------------------------


## Moves the beat clock forward and updates the display.
func advance(seconds: float) -> void:
	clock.advance(seconds)
	_refresh()


## A tap on Press. Returns true when it was on a lit beat.
func press() -> bool:
	if clock.is_solved():
		return true
	var on_beat := clock.press()
	if on_beat:
		if OS.has_feature("web") or OS.has_feature("mobile"):
			Input.vibrate_handheld(30)
		_message.text = "Nice! %d in a row." % clock.streak
	else:
		_message.text = "Not on the light. No problem, the row starts again."
	_refresh()
	if clock.is_solved():
		_message.text = "In sync! The press is thumping with the conveyor."
		finish()
	return on_beat


func streak() -> int:
	return clock.streak


# --- PuzzleBase -----------------------------------------------------------


func get_hint_text(level: int) -> String:
	if level == 1:
		if _hints.size() > 0:
			return str(_hints[0])
		return "Watch the light. Tap Press while it glows, and rest while it is dim."
	if _hints.size() > 1:
		return str(_hints[1])
	return "The beat is a little slower now. Take your time."


func reveal() -> void:
	clock.complete()
	_message.text = "Here is how it sounds: press on every lit beat."
	_refresh()


# --- Display --------------------------------------------------------------


func _on_hint_requested(level: int) -> void:
	if level == 2 and not _slowed:
		_slowed = true
		clock.slow_down(SLOW_PERCENT)


func _on_beat(_index: int, _lit: bool) -> void:
	Audio.play("tick")


func _refresh() -> void:
	if _light == null:
		return
	var lit := clock.light_on()
	var current := clock.nearest_beat()
	var key := "%s|%d|%d" % [lit, current, clock.streak]
	if key == _shown_key:
		return
	_shown_key = key
	_light.color = LIT_COLOR if lit else DIM_COLOR
	_light_label.text = "PRESS NOW" if lit else "wait"
	_light_label.add_theme_color_override("font_color", Color(0.1, 0.05, 0.0) if lit else Color(0.85, 0.8, 0.7))
	var step := current % clock.pattern.size() if current >= 0 else -1
	for i in _steps.size():
		var base := "Press" if clock.is_lit(i) else "Rest"
		_steps[i].text = "> %s <" % base if i == step else base
	for i in _lamps.size():
		_lamps[i].text = "(*)" if i < clock.streak else "( )"
	_count.text = "%d of %d in a row" % [clock.streak, clock.required]
