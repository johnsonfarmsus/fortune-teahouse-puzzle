# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node
## Global signals. Nothing here holds state.

signal part_fixed(machine: String, part: String)
signal machine_running(machine: String)
signal clue_collected(clue_id: String)
signal crew_changed(machine: String)
signal display_name_changed(name: String)
signal progress_changed(machine: String)
