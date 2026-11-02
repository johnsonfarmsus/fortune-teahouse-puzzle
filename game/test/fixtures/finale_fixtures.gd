# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted
## GET /finale answers for finale tests. Usage:
##   const FinaleFixtures := preload("res://test/fixtures/finale_fixtures.gd")
##   fake.answer("GET", "/finale", 200, FinaleFixtures.finale(true))

const NAMES := {
	"cookie_to_oven": ["Cookie Machine to Oven", "cookie_machine", "oven"],
	"fortune_to_oven": ["Fortune Machine to Oven", "fortune_machine", "oven"],
	"oven_to_packaging": ["Oven to packaging", "oven", "packaging"],
}


## One element of the handoffs list. `solved` are the solved setting indices.
static func handoff(id: String, status: String = "locked", solved: Array = [], available: bool = false) -> Dictionary:
	var info: Array = NAMES[id]
	return {
		"id": id, "name": info[0], "from_machine": info[1], "to_machine": info[2],
		"settings_total": 3, "settings_solved": solved.size(), "solved_indices": solved,
		"complete": status == "connected", "available": available, "status": status,
	}


## A whole GET /finale object. `open` makes every handoff available and in progress
## unless `overrides` ({handoff_id: handoff object}) says otherwise.
static func finale(open: bool, overrides: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var list: Array = []
	for id: String in NAMES:
		if overrides.has(id):
			list.append(overrides[id])
		elif open:
			list.append(handoff(id, "not_started", [], true))
		else:
			list.append(handoff(id))
	var out := {
		"open": open,
		"open_reason": "all_machines_run" if open else "closed",
		"override": null,
		"safety_net_at": "2027-10-30T01:00:00Z",
		"all_machines_run": open,
		"handoffs": list,
		"notes": {"found": 0, "total": 6, "needed": 4, "complete": false},
		"line_ready": false,
		"started": false,
		"started_at": null,
	}
	out.merge(extra, true)
	return out
