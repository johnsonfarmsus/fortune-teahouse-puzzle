# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PartFixture
extends Node2D
## One part of one machine in the shop. Shows a Broken or a Fixed look that
## differs in shape and label, never colour alone.

@export var machine: String = ""
@export var part: String = ""
## Optional labels for this machine's part, such as "Ink pump: dry". Empty
## falls back to the generic part title ("Wiring: off").
@export var broken_label: String = ""
@export var fixed_label: String = ""

@onready var _broken: Node2D = $Broken
@onready var _fixed: Node2D = $Fixed


func _ready() -> void:
	var title: String = str(Ids.PART_TITLES.get(part, part))
	$Broken/Label.text = broken_label if not broken_label.is_empty() else "%s: off" % title
	$Fixed/Label.text = fixed_label if not fixed_label.is_empty() else "%s: on" % title
	Events.part_fixed.connect(_on_part_fixed)
	Events.progress_changed.connect(_on_progress_changed)
	refresh()


func is_fixed() -> bool:
	return int(Progress.store.get_crew_progress(machine).get(part, 0)) > 0


func refresh() -> void:
	var fixed := is_fixed()
	_broken.visible = not fixed
	_fixed.visible = fixed


func _on_part_fixed(fixed_machine: String, fixed_part: String) -> void:
	if fixed_machine == machine and fixed_part == part:
		refresh()


func _on_progress_changed(changed_machine: String) -> void:
	if changed_machine == machine:
		refresh()
