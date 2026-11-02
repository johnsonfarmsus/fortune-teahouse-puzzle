# SPDX-License-Identifier: AGPL-3.0-or-later
class_name DialPreview
extends VBoxContainer
## The live picture under the dials of a handoff puzzle (docs/FINALE-DESIGN.md
## section 3): simple shapes plus a word for each, so colour is never the only
## signal. Three kinds, chosen by the preview config's `kind`:
##   belt   rounds on a belt, spacing, and a batter bowl
##   beats  two rows of numbered ticks: arms ready and fortune lands
##   routes a line from each chute to its package, dashed until locked
## It only reads DialRules; the puzzle calls refresh() after every change.

const GOLD := Color(0.95, 0.72, 0.2)
const GREEN := Color(0.35, 0.8, 0.4)
const ORANGE := Color(0.9, 0.5, 0.25)
const DIM := Color(0.25, 0.19, 0.15)
const BELT := Color(0.12, 0.1, 0.09)
const GREY := Color(0.55, 0.55, 0.55)
const ROUND_COLORS := {"burnt": Color(0.25, 0.14, 0.08), "golden": Color(0.95, 0.72, 0.2), "raw": Color(0.93, 0.87, 0.7)}
const SPACING_GAPS := {"touching": 0, "even": 14, "gappy": 40}
const BOWL_FILL := {"overflowing": 1.0, "full": 0.75, "empty": 0.08}
const ROUND_SIZE := 28
const ROUND_COUNT := 5
const CELL_SIZE := Vector2(28, 40)

var rules: DialRules
var config: Dictionary = {}
var kind: String = ""

# belt
var _rounds_box: HBoxContainer
var _round_panels: Array[Panel] = []
var _bowl_fill: ColorRect
var _bowl_spill: ColorRect
var _belt_words: Label
# beats
var _arm_cells: Array[ColorRect] = []
var _fortune_cells: Array[ColorRect] = []
var _beats_words: Label
# routes
var _route_rows: Dictionary = {}  # dial id -> {line, dashes, package, state}


func setup(p_rules: DialRules, p_config: Dictionary) -> void:
	rules = p_rules
	config = p_config
	kind = str(p_config.get("kind", ""))
	add_theme_constant_override("separation", 6)
	match kind:
		"belt":
			_build_belt()
		"beats":
			_build_beats()
		"routes":
			_build_routes()
	refresh()


func refresh() -> void:
	if rules == null:
		return
	match kind:
		"belt":
			_refresh_belt()
		"beats":
			_refresh_beats()
		"routes":
			_refresh_routes()


## What the preview says in words right now (tests and screen readers).
func words() -> String:
	match kind:
		"belt":
			return _belt_words.text
		"beats":
			return _beats_words.text
	var out: Array[String] = []
	for id: String in _route_rows:
		out.append(((_route_rows[id]["state"]) as Label).text)
	return "\n".join(out)


# --- belt -----------------------------------------------------------------------------


func _build_belt() -> void:
	var belt := ColorRect.new()
	belt.color = BELT
	belt.custom_minimum_size = Vector2(0, ROUND_SIZE + 16)
	belt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(belt)
	_rounds_box = HBoxContainer.new()
	_rounds_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rounds_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rounds_box.offset_left = 8
	_rounds_box.offset_top = 8
	belt.add_child(_rounds_box)
	for i in ROUND_COUNT:
		var round_panel := Panel.new()
		round_panel.custom_minimum_size = Vector2(ROUND_SIZE, ROUND_SIZE)
		round_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rounds_box.add_child(round_panel)
		_round_panels.append(round_panel)
	var bowl_row := HBoxContainer.new()
	bowl_row.add_theme_constant_override("separation", 12)
	add_child(bowl_row)
	var bowl := Panel.new()
	bowl.custom_minimum_size = Vector2(60, 60)
	bowl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := StyleBoxFlat.new()
	outline.bg_color = DIM
	outline.set_border_width_all(3)
	outline.border_color = GREY
	bowl.add_theme_stylebox_override("panel", outline)
	bowl_row.add_child(bowl)
	_bowl_fill = ColorRect.new()
	_bowl_fill.color = Color(0.93, 0.87, 0.7)
	_bowl_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bowl.add_child(_bowl_fill)
	_bowl_spill = ColorRect.new()
	_bowl_spill.color = Color(0.93, 0.87, 0.7)
	_bowl_spill.size = Vector2(60, 6)
	_bowl_spill.position = Vector2(0, -8)
	_bowl_spill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bowl.add_child(_bowl_spill)
	_belt_words = UiKit.label("", UiKit.CLUE_SIZE)
	_belt_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bowl_row.add_child(_belt_words)


func _role(name_: String) -> String:
	return str((config.get("roles", {}) as Dictionary).get(name_, ""))


func _refresh_belt() -> void:
	var rounds := _word_for(rules.mark(_role("speed")), ["burnt", "golden", "raw"])
	var spacing := _word_for(rules.mark(_role("spacing")), ["touching", "even", "gappy"])
	var bowl := _word_for(rules.mark(_role("bowl")), ["overflowing", "full", "empty"])
	_rounds_box.add_theme_constant_override("separation", int(SPACING_GAPS[spacing]))
	for panel in _round_panels:
		var style := StyleBoxFlat.new()
		style.bg_color = ROUND_COLORS[rounds]
		style.set_corner_radius_all(ROUND_SIZE / 2)
		style.set_border_width_all(2)
		style.border_color = Color(0.05, 0.04, 0.03)
		panel.add_theme_stylebox_override("panel", style)
	var fill := float(BOWL_FILL[bowl])
	var height := 54.0 * minf(fill, 1.0)
	_bowl_fill.size = Vector2(54, height)
	_bowl_fill.position = Vector2(3, 57.0 - height)
	_bowl_spill.visible = bowl == "overflowing"
	_belt_words.text = "Rounds: %s\nSpacing: %s\nBowl: %s" % [rounds, spacing, bowl]


## low, ok, high -> the three words in that order.
func _word_for(mark: String, three: Array) -> String:
	if mark == DialRules.LOW:
		return str(three[0])
	if mark == DialRules.HIGH:
		return str(three[2])
	return str(three[1])


# --- beats ----------------------------------------------------------------------------


func _build_beats() -> void:
	var ticks := int(config.get("ticks", 12))
	add_child(UiKit.label("Arms ready", 16))
	_arm_cells = _cell_row(ticks)
	add_child(UiKit.label("Fortune lands", 16))
	_fortune_cells = _cell_row(ticks)
	_beats_words = UiKit.label("", 16)
	add_child(_beats_words)


func _cell_row(ticks: int) -> Array[ColorRect]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	add_child(row)
	var cells: Array[ColorRect] = []
	for i in ticks:
		var cell := ColorRect.new()
		cell.custom_minimum_size = CELL_SIZE
		cell.color = DIM
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var text := Label.new()
		text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.add_theme_font_size_override("font_size", 12)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(text)
		row.add_child(cell)
		cells.append(cell)
	return cells


func _refresh_beats() -> void:
	var ticks := int(config.get("ticks", 12))
	var targets: Array[int] = []
	for t: Variant in config.get("targets", []):
		targets.append(int(t))
	var every_id := _role("every")
	var dry_id := _role("dry")
	var landing := DialRules.beats_landing(
		int(rules.value(_role("start"))), int(rules.value(dry_id)), int(rules.value(every_id)), int(config.get("chute_ticks", 2)), ticks
	)
	var smudged := rules.mark(dry_id) == DialRules.LOW
	var folded: Array[int] = []
	for t in landing:
		if targets.has(t):
			folded.append(t)
	for i in ticks:
		var arm := targets.has(i)
		_set_cell(_arm_cells[i], i, GOLD if arm else DIM, "arm" if arm else "", arm)
		var lands := landing.has(i)
		var color := DIM
		var tag := ""
		if lands:
			color = ORANGE
			tag = "ink"
			if smudged:
				tag = "~~"
			elif arm:
				color = GREEN
				tag = "ok"
		_set_cell(_fortune_cells[i], i, color, tag, lands)
	var lines: Array[String] = []
	lines.append("Folded: %d of %d." % [folded.size(), targets.size()])
	if smudged:
		lines.append("Smudged: the ink is still wet.")
	if landing.is_empty():
		lines.append("No fortune lands in time.")
	_beats_words.text = "\n".join(lines)


func _set_cell(cell: ColorRect, tick: int, color: Color, tag: String, lit: bool) -> void:
	cell.color = color
	var label := cell.get_child(0) as Label
	label.text = str(tick) if tag == "" else "%d\n%s" % [tick, tag]
	label.add_theme_color_override("font_color", Color.BLACK if lit else Color.WHITE)


# --- routes ---------------------------------------------------------------------------


func _build_routes() -> void:
	var n := 0
	for id: Variant in config.get("chutes", []):
		n += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		var chute := UiKit.label("Chute %d" % n, 16)
		chute.custom_minimum_size = Vector2(68, 0)
		row.add_child(chute)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 3)
		line.custom_minimum_size = Vector2(70, 0)
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(line)
		var package := UiKit.label("", 16)
		package.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(package)
		_route_rows[str(id)] = {"line": line, "package": package, "state": UiKit.label("", 14)}
		add_child(_route_rows[str(id)]["state"])


func _refresh_routes() -> void:
	for id: String in _route_rows:
		var row: Dictionary = _route_rows[id]
		var line := row["line"] as HBoxContainer
		UiKit.clear_children(line)
		var locked := rules.is_locked(id)
		# Solid when locked, dashed until then.
		var pieces := 1 if locked else 5
		for i in pieces:
			var piece := ColorRect.new()
			piece.color = GREEN if locked else GREY
			piece.custom_minimum_size = Vector2(70 if locked else 10, 4)
			piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(piece)
		(row["package"] as Label).text = rules.value_text(id)
		(row["state"] as Label).text = "Chute %s: connected" % id.trim_prefix("chute_") if locked else "Chute %s: dashed, not set yet" % id.trim_prefix("chute_")
