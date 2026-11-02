# SPDX-License-Identifier: AGPL-3.0-or-later
extends CanvasLayer
## A 56 px top bar: crew label, "Clues N" (ClueBoard) and "Menu" (Settings).

@onready var _crew: Label = $Bar/Row/CrewLabel
@onready var _clues: Button = $Bar/Row/CluesButton
@onready var _menu: Button = $Bar/Row/MenuButton


func _ready() -> void:
	_clues.pressed.connect(func() -> void: Router.push(Paths.CLUE_BOARD))
	_menu.pressed.connect(func() -> void: Router.push(Paths.SETTINGS))
	Events.crew_changed.connect(func(_machine: String) -> void: refresh())
	Events.clue_collected.connect(func(_clue_id: String) -> void: refresh())
	refresh()


func refresh() -> void:
	if GameState.crew == "":
		_crew.text = "No crew yet"
	else:
		_crew.text = Ids.machine_title(GameState.crew)
	_clues.text = "Clues %d" % GameState.collected_clue_ids.size()
