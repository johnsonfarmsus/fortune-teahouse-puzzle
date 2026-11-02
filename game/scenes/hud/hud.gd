# SPDX-License-Identifier: AGPL-3.0-or-later
extends CanvasLayer
## A 56 px top bar: crew label (with a "Maintainer" badge once the scoreboard
## says the crew's machine runs), "Clues N" (ClueBoard) and "Menu" (Settings).
## Also hosts the banner for mentor hints, above every screen.

@onready var _crew: Label = $Bar/Row/CrewBox/CrewLabel
@onready var _badge: Label = $Bar/Row/CrewBox/MaintainerBadge
@onready var _clues: Button = $Bar/Row/CluesButton
@onready var _menu: Button = $Bar/Row/MenuButton


func _ready() -> void:
	_clues.pressed.connect(func() -> void: Router.push(Paths.CLUE_BOARD))
	_menu.pressed.connect(func() -> void: Router.push(Paths.SETTINGS))
	Events.crew_changed.connect(func(_machine: String) -> void: refresh())
	Events.clue_collected.connect(func(_clue_id: String) -> void: refresh())
	Events.progress_changed.connect(func(_machine: String) -> void: refresh())
	var banner_layer := CanvasLayer.new()
	banner_layer.layer = 30
	add_child(banner_layer)
	banner_layer.add_child(load(Paths.HINT_BANNER).instantiate())
	refresh()


func refresh() -> void:
	if GameState.crew == "":
		_crew.text = "No crew yet"
	else:
		_crew.text = Ids.machine_title(GameState.crew)
	_clues.text = "Clues %d" % GameState.collected_clue_ids.size()
	_badge.visible = Progress.is_maintainer()
