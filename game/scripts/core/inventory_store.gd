# SPDX-License-Identifier: AGPL-3.0-or-later
class_name InventoryStore
extends RefCounted
## A crew's shared inventory (PLAN.md D10, server/API.md): items found and
## installed around town, with who found them. LocalInventoryStore keeps it on
## this phone; RemoteInventoryStore wraps one and shares it through the
## scoreboard. Getters answer at once and never block. A state only moves
## forward (found, then installed) and repeating a write changes nothing.
##
## An entry is {item_id, state, found_by, found_at, place}; found_by is a
## device id (the server's, or this phone's for its own finds).

signal changed(machine: String)

const FOUND := "found"
const INSTALLED := "installed"
const STATES: Array[String] = [FOUND, INSTALLED]


static func rank(state: String) -> int:
	return STATES.find(state)


## Entries for a machine's crew, oldest find first.
func items(_machine: String) -> Array[Dictionary]:
	return []


func entry(machine: String, item_id: String) -> Dictionary:
	for e in items(machine):
		if str(e.get("item_id", "")) == item_id:
			return e
	return {}


## {item_id: state}, the form ChainRules reads.
func states(machine: String) -> Dictionary:
	var out: Dictionary = {}
	for e in items(machine):
		out[str(e["item_id"])] = str(e["state"])
	return out


## Records a find or an install. Returns true if anything changed here.
func mark(_machine: String, _item_id: String, _state: String, _place: String, _device_id: String) -> bool:
	return false


func refresh(_machine: String = "") -> void:
	pass


func is_online() -> bool:
	return false


func reset_local() -> void:
	pass
