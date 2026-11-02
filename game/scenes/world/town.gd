# SPDX-License-Identifier: AGPL-3.0-or-later
extends PlaceBase
## The town: tap to walk. Shop opens the Shop place, the Teahouse (Red Panda)
## opens lucky-word entry, the Pier (Crab) opens the contributors list.
## Story: the Gnu's notes are tappable markers; the Anglerfish drops by now and
## then; the first tap on the Shop door reads the Gnu's sign before it opens.

const WALK_RECT := Rect2(20, 90, 350, 700)
const SPEED := 320.0
const ANGLER_EVERY := 90.0  # seconds between visits
const ANGLER_STAYS := 8.0  # seconds one visit lasts
const ANGLER_POSITION := Vector2(70, 726)
const ANGLER_SIZE := Vector2(310, 64)
const BIT_CHARS := 44
## Top-left corners (390x844) of the Gnu's notes, by piece id.
const NOTE_POSITIONS := {
	"gnu.town.shop_door": Vector2(150, 200),
	"gnu.town.teahouse_board": Vector2(150, 604),
	"gnu.town.pier_bottle": Vector2(262, 500),
	"gnu.town.handoffs": Vector2(150, 330),
}

@onready var avatar: ColorRect = $Avatar

var anglerfish: Button
var _tween: Tween
var _visit_timer: Timer
var _leave_timer: Timer
var _angler_label: Label
var _angler_piece: Dictionary = {}


func _ready() -> void:
	add_story_markers("town", NOTE_POSITIONS)
	_build_anglerfish()
	Story.flags_changed.connect(_on_flags_changed)
	Events.crew_changed.connect(_on_crew_changed)
	Router.stack_changed.connect(_on_stack_changed)
	_on_flags_changed()
	_on_stack_changed(Router.depth())


func _on_hotspot_hit(hotspot: Hotspot) -> void:
	walk_to(hotspot.door_position(), func() -> void: activate(hotspot))


func _on_miss(point: Vector2) -> void:
	walk_to(point)


func walk_to(point: Vector2, then: Callable = Callable()) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var target := Vector2(
		clampf(point.x, WALK_RECT.position.x, WALK_RECT.end.x),
		clampf(point.y, WALK_RECT.position.y, WALK_RECT.end.y)
	)
	var top_left := target - avatar.size / 2.0
	var distance := avatar.position.distance_to(top_left)
	_tween = create_tween()
	_tween.tween_property(avatar, "position", top_left, distance / SPEED)
	if then.is_valid():
		_tween.tween_callback(then)


func activate(hotspot: Hotspot) -> void:
	if hotspot.place_id == "shop":
		# The Gnu's sign on the door comes first, once.
		var sign_piece := Story.next_unseen("town:shop", "first_visit")
		if not sign_piece.is_empty():
			var box := Story.play(self, [sign_piece])
			refresh_story_markers()
			box.finished.connect(Router.go_to_place.bind("shop"))
			return
	if Paths.PLACES.has(hotspot.place_id):
		Router.go_to_place(hotspot.place_id)
	elif hotspot.place_id == "teahouse":
		Router.push(Paths.LUCKY_WORD_ENTRY)
	elif hotspot.place_id == "pier":
		Router.push(Paths.CONTRIBUTORS)


# --- Anglerfish -----------------------------------------------------------------


func _build_anglerfish() -> void:
	anglerfish = Button.new()
	anglerfish.name = "Anglerfish"
	anglerfish.custom_minimum_size = ANGLER_SIZE
	anglerfish.size = ANGLER_SIZE
	anglerfish.position = ANGLER_POSITION
	anglerfish.focus_mode = Control.FOCUS_NONE
	anglerfish.visible = false
	anglerfish.pressed.connect(_on_anglerfish_pressed)
	var sprite := ColorRect.new()  # placeholder art: a glowing lure
	sprite.name = "Sprite"
	sprite.color = Color(0.2, 0.75, 0.8)
	sprite.position = Vector2(8, 8)
	sprite.size = Vector2(48, 48)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anglerfish.add_child(sprite)
	_angler_label = UiKit.label("", 16)
	_angler_label.position = Vector2(64, 4)
	_angler_label.size = Vector2(240, 56)
	_angler_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anglerfish.add_child(_angler_label)
	add_child(anglerfish)
	_visit_timer = Timer.new()
	_visit_timer.name = "VisitTimer"
	_visit_timer.wait_time = ANGLER_EVERY
	_visit_timer.timeout.connect(spawn_anglerfish)
	add_child(_visit_timer)
	_leave_timer = Timer.new()
	_leave_timer.name = "LeaveTimer"
	_leave_timer.one_shot = true
	_leave_timer.wait_time = ANGLER_STAYS
	_leave_timer.timeout.connect(hide_anglerfish)
	add_child(_leave_timer)


## True once the Anglerfish has said goodbye; it never comes back.
func anglerfish_gone() -> bool:
	return Story.is_seen("anglerfish.farewell")


## True while a DialogueBox is showing in this town.
func dialogue_open() -> bool:
	for box in find_children("*", "DialogueBox", true, false):
		if not (box as DialogueBox).is_done():
			return true
	return false


## The visit clock stands still while a screen covers the town and resumes on return.
func _on_stack_changed(depth: int) -> void:
	_visit_timer.paused = depth > 0
	_leave_timer.paused = depth > 0


## A reset (or any crew change) can change which notes and farewell apply.
func _on_crew_changed(_machine: String) -> void:
	_on_flags_changed()


## Shows the next `interval` bit for ANGLER_STAYS seconds. Returns false (and
## does nothing) when the Anglerfish is gone, already here, or a screen is open.
func spawn_anglerfish() -> bool:
	if anglerfish_gone() or anglerfish.visible or Router.depth() > 0 or dialogue_open():
		return false
	var bits := Story.pieces_for("town", "interval")
	if bits.is_empty():
		return false
	_angler_piece = bits[Story.rotate("anglerfish.town", bits.size())]
	var first: String = _angler_piece["lines"][0]
	if first.length() > BIT_CHARS:
		first = first.substr(0, BIT_CHARS - 3).strip_edges() + "..."
	_angler_label.text = "Anglerfish: " + first
	anglerfish.visible = true
	_leave_timer.start()
	return true


func hide_anglerfish() -> void:
	anglerfish.visible = false
	_leave_timer.stop()


func _on_anglerfish_pressed() -> void:
	if _angler_piece.is_empty():
		return
	hide_anglerfish()
	# Read in full; not marked seen, since the bits come round again.
	Story.play(self, [_angler_piece], false)


## The farewell waits for the `line_running` flag, which nothing raises yet. When it
## does, the Anglerfish says goodbye once and then stays away for good.
func _on_flags_changed() -> void:
	if anglerfish_gone():
		hide_anglerfish()
		_visit_timer.stop()
		return
	if Story.flag("line_running"):
		var farewell := Story.next_unseen("town", "line_running")
		if not farewell.is_empty():
			hide_anglerfish()
			_visit_timer.stop()
			Story.play(self, [farewell])
			return
	if _visit_timer.is_stopped() and is_inside_tree():
		_visit_timer.start()
