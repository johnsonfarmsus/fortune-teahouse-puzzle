# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ChainRules
extends RefCounted
## The chain logic (PLAN.md D13), pure and static so tests can play a whole
## chain without scenes. `data` is one data/chains/<machine>.json file; `state`
## is this phone's ChainState; `inv` is the crew inventory as {item_id: "found"
## or "installed"}. Rooms only present what these functions decide: a tap or a
## drop becomes resolve(...), the interaction it returns is applied with apply(),
## and the effects that touch the crew (find, install, solve_part) and the screen
## (open) are handed back to the caller.
##
## Answers never live here: a lock's code comes from the logic puzzle's answer
## (`answers` is {machine: {item: position}}, from PuzzleData), and the decoy
## codes are the outdated ones written in the chain data.

const RIGHT := "right"
const WRONG := "wrong"
const DECOY_PREFIX := "decoy:"
const VERBS: Array[String] = ["tap", "use", "code", "done", "enter"]
const EXTERNAL_EFFECTS: Array[String] = ["find", "install", "solve_part", "open"]


# --- Lookups ------------------------------------------------------------------------


static func chains(data: Dictionary) -> Array:
	return data.get("chains", [])


static func chain(data: Dictionary, chain_id: String) -> Dictionary:
	for c: Dictionary in chains(data):
		if str(c.get("id", "")) == chain_id:
			return c
	return {}


static func item_def(data: Dictionary, item: String) -> Dictionary:
	return data.get("items", {}).get(item, {})


static func is_shared(data: Dictionary, item: String) -> bool:
	return bool(item_def(data, item).get("shared", true))


static func lock_def(data: Dictionary, lock_id: String) -> Dictionary:
	for c: Dictionary in chains(data):
		if c.get("locks", {}).has(lock_id):
			return c["locks"][lock_id]
	return {}


static func decoy(data: Dictionary, decoy_id: String) -> Dictionary:
	for c: Dictionary in chains(data):
		for d: Dictionary in c.get("decoys", []):
			if str(d.get("id", "")) == decoy_id:
				return d
	return {}


static func misdirect(data: Dictionary, misdirect_id: String) -> Dictionary:
	for c: Dictionary in chains(data):
		for m: Dictionary in c.get("misdirects", []):
			if str(m.get("id", "")) == misdirect_id:
				return m
	return {}


# --- Items --------------------------------------------------------------------------


## Ever found (or installed) by the crew, or held on this phone.
static func found(data: Dictionary, state: ChainState, inv: Dictionary, item: String) -> bool:
	if not is_shared(data, item):
		return state.holds_item(item)
	return inv.has(item)


static func installed(inv: Dictionary, item: String) -> bool:
	return str(inv.get(item, "")) == "installed"


## In hand right now: found and not installed, and not replaced by a better
## version (the bent die once the straight one is found).
static func has_item(data: Dictionary, state: ChainState, inv: Dictionary, item: String) -> bool:
	if not is_shared(data, item):
		return state.holds_item(item)
	if str(inv.get(item, "")) != "found":
		return false
	var replaced_by := str(item_def(data, item).get("replaced_by", ""))
	return replaced_by == "" or not inv.has(replaced_by)


## Items to show in the inventory bar, in data order.
static func visible_items(data: Dictionary, state: ChainState, inv: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for item: String in data.get("items", {}):
		if has_item(data, state, inv, item):
			out.append(item)
	return out


# --- Requirements -------------------------------------------------------------------


static func holds(data: Dictionary, req: Dictionary, state: ChainState, inv: Dictionary) -> bool:
	for fact: Variant in req.get("facts", []):
		if not state.knows(str(fact)):
			return false
	for fact: Variant in req.get("not_facts", []):
		if state.knows(str(fact)):
			return false
	for item: Variant in req.get("have", []):
		if not has_item(data, state, inv, str(item)):
			return false
	for item: Variant in req.get("not_have", []):
		if has_item(data, state, inv, str(item)):
			return false
	for item: Variant in req.get("found", []):
		if not found(data, state, inv, str(item)):
			return false
	for item: Variant in req.get("installed", []):
		if not installed(inv, str(item)):
			return false
	for item: Variant in req.get("not_installed", []):
		if installed(inv, str(item)):
			return false
	for d: Variant in req.get("decoys_seen", []):
		if not state.has_seen_decoy(str(d)):
			return false
	for d: Variant in req.get("not_decoys_seen", []):
		if state.has_seen_decoy(str(d)):
			return false
	return true


# --- Locks --------------------------------------------------------------------------


## The right code for a lock: an explicit `code`, or the positions of
## `code_from.items` in the `code_from.puzzle` answer, one digit each.
static func lock_code(lock: Dictionary, answers: Dictionary) -> String:
	if lock.has("code"):
		return str(lock["code"])
	var source: Dictionary = lock.get("code_from", {})
	var answer: Dictionary = answers.get(str(source.get("puzzle", "")), {})
	var digits := ""
	for item: Variant in source.get("items", []):
		if not answer.has(str(item)):
			return ""
		digits += str(int(answer[str(item)]))
	return digits


## "right", "decoy:<id>" or "wrong" for `code` tried on `lock_id`.
static func code_result(data: Dictionary, lock_id: String, code: String, answers: Dictionary) -> String:
	var lock := lock_def(data, lock_id)
	if lock.is_empty():
		return WRONG
	var right := lock_code(lock, answers)
	if right != "" and code == right:
		return RIGHT
	for c: Dictionary in chains(data):
		for d: Dictionary in c.get("decoys", []):
			if str(d.get("lock", "")) == lock_id and str(d.get("code", "")) == code:
				return DECOY_PREFIX + str(d["id"])
	return WRONG


# --- Interactions -------------------------------------------------------------------


## The first interaction that fires for this tap, drop, code, close-up or room
## entry, or {} when none does. A drop (`use`) only matches an item in hand.
static func resolve(
	data: Dictionary, state: ChainState, inv: Dictionary, room: String, target: String, verb: String,
	item: String = "", result: String = ""
) -> Dictionary:
	if verb == "use" and not has_item(data, state, inv, item):
		return {}
	for c: Dictionary in chains(data):
		for i: Dictionary in c.get("interactions", []):
			if str(i.get("room", "")) != room or str(i.get("target", "")) != target or str(i.get("verb", "")) != verb:
				continue
			if verb == "use" and str(i.get("item", "")) != item:
				continue
			if verb == "code" and str(i.get("result", "")) != result:
				continue
			if holds(data, i.get("requires", {}), state, inv):
				var out := i.duplicate(true)
				out["chain"] = str(c.get("id", ""))
				return out
	return {}


## Applies the interaction's effects that belong to this phone (learn, hold,
## release, see_decoy) to `state` and returns every effect, in order, so the
## caller can do the rest (find and install through the crew inventory,
## solve_part through Progress, open a close-up).
static func apply(interaction: Dictionary, state: ChainState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect: Dictionary in interaction.get("effects", []):
		if effect.has("learn"):
			state.learn(str(effect["learn"]))
		elif effect.has("hold"):
			state.hold(str(effect["hold"]))
		elif effect.has("release"):
			state.release(str(effect["release"]))
		elif effect.has("see_decoy"):
			state.see_decoy(str(effect["see_decoy"]))
		out.append(effect)
	return out


## The inventory side of `effects`, on a plain dictionary (tests, simulations).
static func apply_to_inventory(effects: Array[Dictionary], inv: Dictionary) -> void:
	for effect in effects:
		if effect.has("find") and not inv.has(str(effect["find"])):
			inv[str(effect["find"])] = "found"
		elif effect.has("install"):
			inv[str(effect["install"])] = "installed"


# --- Steps --------------------------------------------------------------------------


static func step_done(data: Dictionary, step: Dictionary, state: ChainState, inv: Dictionary) -> bool:
	return holds(data, step.get("done_when", {}), state, inv)


## The step after the furthest one done, or {} once the chain's goal holds.
## A crewmate's find can skip this phone past earlier steps.
static func current_step(data: Dictionary, c: Dictionary, state: ChainState, inv: Dictionary) -> Dictionary:
	if goal_reached(data, c, state, inv):
		return {}
	var steps: Array = c.get("steps", [])
	var next := 0
	for i in steps.size():
		if step_done(data, steps[i], state, inv):
			next = i + 1
	return steps[next] if next < steps.size() else {}


static func goal_reached(data: Dictionary, c: Dictionary, state: ChainState, inv: Dictionary) -> bool:
	return holds(data, c.get("goal", {}), state, inv)


# --- Checks -------------------------------------------------------------------------


## Every sfx id the data names (interactions, nothing else).
static func sfx_ids(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in chains(data):
		for i: Dictionary in c.get("interactions", []):
			var id := str(i.get("sfx", ""))
			if id != "" and not out.has(id):
				out.append(id)
	return out


## Every story piece id the data names.
static func piece_ids(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var add := func(id: String) -> void:
		if id != "" and not out.has(id):
			out.append(id)
	for item: String in data.get("items", {}):
		add.call(str(data["items"][item].get("about", "")))
	for c: Dictionary in chains(data):
		for step: Dictionary in c.get("steps", []):
			for id: Variant in step.get("hints", []):
				add.call(str(id))
		for lock_id: String in c.get("locks", {}):
			add.call(str(c["locks"][lock_id].get("label", "")))
		for m: Dictionary in c.get("misdirects", []):
			add.call(str(m.get("tell_piece", "")))
		for d: Dictionary in c.get("decoys", []):
			add.call(str(d.get("flash", "")))
			for id: Variant in d.get("wrong_place_says", []):
				add.call(str(id))
		for i: Dictionary in c.get("interactions", []):
			for id in say_ids(i):
				add.call(id)
	return out


## An interaction's `say` as a list (it may be one id or several).
static func say_ids(interaction: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = interaction.get("say", "")
	if raw is Array:
		for id: Variant in raw:
			out.append(str(id))
	elif str(raw) != "":
		out.append(str(raw))
	return out


## Structural problems: unknown items, verbs, rooms or targets, misdirects
## without a home, decoys that lead nowhere. `targets` is {room: [target ids]}
## (props, npcs and the room itself); close-up names count as targets too.
static func validate(data: Dictionary, targets: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var items: Dictionary = data.get("items", {})
	for item: String in items:
		var def: Dictionary = items[item]
		if not bool(def.get("shared", true)):
			var home: Dictionary = def.get("home", {})
			if not targets.has(str(home.get("room", ""))) or not targets[str(home.get("room", ""))].has(str(home.get("target", ""))):
				errors.append("item %s: unshared items need a home room and target" % item)
		var replaced_by := str(def.get("replaced_by", ""))
		if replaced_by != "" and not items.has(replaced_by):
			errors.append("item %s: replaced_by %s is not an item" % [item, replaced_by])
	for c: Dictionary in chains(data):
		var cid := str(c.get("id", ""))
		if not Ids.PARTS.has(str(c.get("part", ""))):
			errors.append("chain %s: unknown part" % cid)
		for i: Dictionary in c.get("interactions", []):
			var where := "chain %s interaction %s" % [cid, str(i.get("id", "?"))]
			var room := str(i.get("room", ""))
			var verb := str(i.get("verb", ""))
			if not VERBS.has(verb):
				errors.append("%s: unknown verb %s" % [where, verb])
			if not targets.has(room):
				errors.append("%s: unknown room %s" % [where, room])
			elif verb != "done" and not targets[room].has(str(i.get("target", ""))):
				errors.append("%s: unknown target %s" % [where, str(i.get("target", ""))])
			if verb == "use" and not items.has(str(i.get("item", ""))):
				errors.append("%s: unknown item %s" % [where, str(i.get("item", ""))])
			if verb == "code":
				var result := str(i.get("result", ""))
				if result != RIGHT and result != WRONG and decoy(data, result.trim_prefix(DECOY_PREFIX)).is_empty():
					errors.append("%s: unknown code result %s" % [where, result])
			for effect: Dictionary in i.get("effects", []):
				for key: String in ["find", "install", "hold", "release"]:
					if effect.has(key) and not items.has(str(effect[key])):
						errors.append("%s: %s of unknown item %s" % [where, key, str(effect[key])])
				if effect.has("solve_part") and not Ids.PARTS.has(str(effect["solve_part"])):
					errors.append("%s: unknown part %s" % [where, str(effect["solve_part"])])
				for key: String in ["hold", "release"]:
					if effect.has(key) and is_shared(data, str(effect[key])):
						errors.append("%s: %s is for unshared items only" % [where, key])
				if effect.has("find") and not is_shared(data, str(effect["find"])):
					errors.append("%s: find is for shared items only" % where)
		for m: Dictionary in c.get("misdirects", []):
			if is_shared(data, str(m.get("item", ""))) or str(m.get("tell", "")) == "":
				errors.append("chain %s misdirect %s: needs an unshared item and a tell" % [cid, str(m.get("id", "?"))])
		for d: Dictionary in c.get("decoys", []):
			var did := str(d.get("id", "?"))
			if not targets.has(str(d.get("destination", ""))):
				errors.append("chain %s decoy %s: destination is not a room" % [cid, did])
			if str(d.get("mistake", "")) == "" or (d.get("wrong_place_says", []) as Array).is_empty():
				errors.append("chain %s decoy %s: needs a named mistake and what the wrong place says" % [cid, did])
			if lock_def(data, str(d.get("lock", ""))).is_empty():
				errors.append("chain %s decoy %s: unknown lock" % [cid, did])
	return errors
