# SPDX-License-Identifier: AGPL-3.0-or-later
class_name CloseUpBase
extends Control
## A hands-on close-up (DESIGN.md: repairs zoom in). It covers the room view
## and draws pixel art on the same 176x320 grid, `pixel_scale` screen pixels
## per art pixel, with no smoothing. Subclasses lay things out in art pixels
## (px) and turn presses into actions; they never touch chain state, they emit
## `done` (or a lock's `code_entered`) and AdventureView does the rest.

signal done

const VIEW := Vector2(176, 320)

var assets: AssetLoader
var pixel_scale: float = 2.0
var title: String = ""


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	if assets == null:
		assets = AssetLoader.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The scale that fits the art grid into the control's size.
func fit_scale() -> float:
	if size.x <= 0.0:
		return pixel_scale
	return maxf(1.0, size.x / VIEW.x)


func to_px(point: Vector2) -> Vector2:
	return point / fit_scale()


func to_screen(px: Vector2) -> Vector2:
	return px * fit_scale()


func draw_asset(asset: String, at_px: Vector2, frame: int = 0, modulate_color: Color = Color.WHITE, scale_px: float = 1.0) -> void:
	var tex := assets.texture(asset, frame)
	var s := Vector2(tex.get_size()) * fit_scale() * scale_px
	draw_texture_rect(tex, Rect2(to_screen(at_px), s), false, modulate_color)


func asset_rect(asset: String, at_px: Vector2) -> Rect2:
	return Rect2(at_px, Vector2(assets.frame_size(asset)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		for child in get_children():
			if child is Control and child.has_meta("px"):
				var c := child as Control
				c.position = to_screen(c.get_meta("px"))
				c.size = Vector2(float(c.get_meta("width_px")) * fit_scale(), c.size.y)
		queue_redraw()


## A burst of sparks at an art-pixel position (a CPUParticles2D child).
func sparks(at_px: Vector2, color: Color = Color(1, 0.85, 0.3)) -> void:
	var p := CPUParticles2D.new()
	p.position = to_screen(at_px)
	p.amount = 14
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.45
	p.texture = assets.texture("fx.spark", 1)
	p.scale_amount_min = fit_scale()
	p.scale_amount_max = fit_scale()
	p.spread = 180.0
	p.initial_velocity_min = 40.0 * fit_scale()
	p.initial_velocity_max = 90.0 * fit_scale()
	p.gravity = Vector2(0, 200) * fit_scale()
	p.color = color
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func shake_self(px: float = 2.0) -> void:
	var base := position
	var tween := create_tween()
	for i in 6:
		tween.tween_property(self, "position", base + Vector2((1 if i % 2 == 0 else -1) * px * fit_scale(), 0), 0.035)
	tween.tween_property(self, "position", base, 0.035)


func label_at(text: String, at_px: Vector2, width_px: float, font_size: int = 14, color: Color = Color(0.96, 0.93, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.12))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("px", at_px)
	l.set_meta("width_px", width_px)
	l.position = to_screen(at_px)
	l.size = Vector2(width_px * fit_scale(), 0)
	add_child(l)
	return l
