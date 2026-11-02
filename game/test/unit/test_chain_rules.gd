# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## The cutter-die chain played through ChainRules alone: step order,
## prerequisites, misdirects and their tells, the outdated-locker-code decoy to
## the harbour, and "nothing is lost for good" over every reachable state.

const CHAIN_PATH := "res://data/chains/cookie_machine.json"
const MACHINE := "cookie_machine"

var data: Dictionary
var answers: Dictionary
var story: StoryCatalog
var state: ChainState
var inv: Dictionary


func before_test() -> void:
	data = JsonFile.read(CHAIN_PATH)
	var catalog := PuzzleCatalog.load_all()
	answers = {MACHINE: catalog.get_answer(MACHINE)}
	story = StoryCatalog.load_all()
	state = ChainState.new()
	inv = {}


## Resolves and applies one action like the adventure layer does. Returns the interaction.
func _do(room: String, target: String, verb: String, item: String = "", code: String = "") -> Dictionary:
	var result := ""
	if verb == "code":
		result = ChainRules.code_result(data, target, code, answers)
	var i := ChainRules.resolve(data, state, inv, room, target, verb, item, result)
	if not i.is_empty():
		ChainRules.apply_to_inventory(ChainRules.apply(i, state), inv)
	return i


func _right_code() -> String:
	return ChainRules.lock_code(ChainRules.lock_def(data, "gnu_locker"), answers)


func _chain() -> Dictionary:
	return ChainRules.chain(data, "cutter")


func _step_id() -> String:
	return str(ChainRules.current_step(data, _chain(), state, inv).get("id", ""))


func test_chain_data_is_sound() -> void:
	assert_bool(data.is_empty()).is_false()
	var errors := ChainRules.validate(data, RoomGraph.new().targets())
	assert_array(errors).is_empty()
	var c := _chain()
	assert_str(str(c["part"])).is_equal("rhythm")
	var kinds: Array = []
	for step: Dictionary in c["steps"]:
		kinds.append(step["kind"])
	for kind in ["find", "decode", "repair", "install"]:
		assert_array(kinds).contains([kind])


func test_every_piece_the_chain_names_exists() -> void:
	for id in ChainRules.piece_ids(data):
		assert_bool(story.get_piece(id).is_empty()).override_failure_message("missing piece " + id).is_false()


func test_lock_code_comes_from_the_batter_answer_not_the_data() -> void:
	var lock := ChainRules.lock_def(data, "gnu_locker")
	assert_bool(lock.has("code")).is_false()
	var code := _right_code()
	assert_int(code.length()).is_equal(int(lock["digits"]))
	var answer: Dictionary = answers[MACHINE]
	assert_str(code).is_equal("%d%d%d" % [int(answer["egg"]), int(answer["vanilla"]), int(answer["sugar"])])
	assert_str(ChainRules.code_result(data, "gnu_locker", code, answers)).is_equal(ChainRules.RIGHT)
	assert_str(ChainRules.code_result(data, "gnu_locker", "111", answers)).is_equal(ChainRules.WRONG)
	assert_str(ChainRules.code_result(data, "gnu_locker", "241", answers)).is_equal("decoy:old_locker_code")


func test_decoy_code_is_never_the_right_code() -> void:
	var c := _chain()
	for d: Dictionary in c["decoys"]:
		assert_str(str(d["code"])).is_not_equal(_right_code())
		# It follows from its named mistake: the code written on Seagull's scrap.
		var scrap := story.get_piece(str(ChainRules.item_def(data, str(d["source_item"]))["about"]))
		var spaced := " ".join(str(d["code"]).split(""))
		assert_str(str(scrap["text"])).contains(spaced)
		assert_str(str(d["mistake"])).contains("Seagull")


func test_full_chain_in_step_order() -> void:
	assert_str(_step_id()).is_equal("find")
	assert_str(str(_do("shop", "cutter", "tap")["say"])).is_equal("gnu.sticky.cutter")
	assert_str(_step_id()).is_equal("ask")
	var penguin := _do("workshop", "penguin", "tap")
	assert_str(str(penguin["id"])).is_equal("penguin_mailed")
	assert_bool(ChainRules.has_item(data, state, inv, "spanner")).is_true()
	assert_str(_step_id()).is_equal("decode")
	var opened := _do("depot", "gnu_locker", "tap")
	assert_bool(opened["effects"][0].has("open")).is_true()
	assert_str(str(_do("depot", "gnu_locker", "code", "", _right_code())["id"])).is_equal("locker_right")
	assert_bool(ChainRules.has_item(data, state, inv, "die_bent")).is_true()
	assert_str(_step_id()).is_equal("repair")
	var bench := _do("workshop", "bench", "use", "die_bent")
	assert_str(str(bench["effects"][0]["open"])).is_equal("straighten")
	assert_str(str(_do("workshop", "straighten", "done")["id"])).is_equal("straightened")
	# The bent die is replaced by the straight one in the inventory bar.
	assert_bool(ChainRules.has_item(data, state, inv, "die_bent")).is_false()
	assert_array(ChainRules.visible_items(data, state, inv)).contains_exactly(["spanner", "cutter_die"])
	assert_str(_step_id()).is_equal("install")
	var seat := _do("shop", "cutter", "use", "cutter_die")
	assert_str(str(seat["effects"][0]["open"])).is_equal("tighten")
	var done := _do("shop", "tighten", "done")
	var solved := false
	for effect: Dictionary in done["effects"]:
		if effect.has("solve_part"):
			solved = str(effect["solve_part"]) == "rhythm"
	assert_bool(solved).is_true()
	assert_bool(ChainRules.installed(inv, "cutter_die")).is_true()
	assert_bool(ChainRules.goal_reached(data, _chain(), state, inv)).is_true()
	assert_str(_step_id()).is_equal("")
	assert_str(str(_do("shop", "cutter", "tap")["id"])).is_equal("cutter_running")


func test_prerequisites_hold_steps_back() -> void:
	# Penguin has nothing to say about the die before the sticky label is read.
	assert_bool(_do("workshop", "penguin", "tap").is_empty()).is_true()
	assert_bool(ChainRules.has_item(data, state, inv, "spanner")).is_false()
	# A close-up cannot finish without the part, and nothing unheld can be used.
	assert_bool(_do("workshop", "straighten", "done").is_empty()).is_true()
	assert_bool(_do("shop", "tighten", "done").is_empty()).is_true()
	assert_bool(_do("shop", "cutter", "use", "cutter_die").is_empty()).is_true()
	# The die without the spanner wobbles and is not installed.
	inv["cutter_die"] = "found"
	var wobble := _do("shop", "cutter", "use", "cutter_die")
	assert_str(str(wobble["id"])).is_equal("install_die_no_spanner")
	assert_bool(ChainRules.installed(inv, "cutter_die")).is_false()
	# The bent die never goes in.
	inv.erase("cutter_die")
	inv["die_bent"] = "found"
	assert_str(str(_do("shop", "cutter", "use", "die_bent")["id"])).is_equal("bent_on_cutter")
	assert_bool(ChainRules.installed(inv, "die_bent")).is_false()
	# The locker stays shut on a wrong code.
	inv.erase("die_bent")
	_do("depot", "gnu_locker", "code", "", "555" if _right_code() != "555" else "554")
	assert_bool(inv.has("die_bent")).is_false()


func test_misdirects_have_a_tell_and_can_be_put_back() -> void:
	var c := _chain()
	assert_int((c["misdirects"] as Array).size()).is_equal(2)
	for m: Dictionary in c["misdirects"]:
		var item := str(m["item"])
		assert_bool(ChainRules.is_shared(data, item)).is_false()
		assert_str(str(m["tell"])).is_not_empty()
		assert_bool(story.get_piece(str(m["tell_piece"])).is_empty()).is_false()
	# Scrapyard: a die that looks right but has the wrong number of teeth.
	_do("scrapyard", "scrap_pile", "tap")
	assert_bool(state.holds_item("scrap_die")).is_true()
	var tried := _do("shop", "cutter", "use", "scrap_die")
	assert_str(str(tried["say"])).is_equal("narrator.cutter.scrap_die_tell")
	assert_str(str(story.get_piece(str(tried["say"]))["text"])).contains("teeth")
	assert_bool(ChainRules.installed(inv, "scrap_die")).is_false()
	_do("scrapyard", "scrap_pile", "use", "scrap_die")
	assert_bool(state.holds_item("scrap_die")).is_false()
	# Harbour: Anglerfish's gleaming die with a connector that fits nothing.
	_do("harbour", "anglerfish", "tap")
	assert_bool(state.holds_item("cloud_die")).is_true()
	var cloud := _do("shop", "cutter", "use", "cloud_die")
	assert_str(str(story.get_piece(str(cloud["say"]))["text"])).contains("connector")
	_do("harbour", "anglerfish", "use", "cloud_die")
	assert_bool(state.holds_item("cloud_die")).is_false()
	# Misdirects never sync to the crew.
	assert_bool(inv.has("scrap_die") or inv.has("cloud_die")).is_false()


func test_outdated_scrap_decoy_routes_to_the_harbour_which_explains() -> void:
	var d := ChainRules.decoy(data, "old_locker_code")
	assert_str(str(d["destination"])).is_equal("harbour")
	assert_str(str(d["mistake"])).is_equal("trusting Seagull's outdated scrap")
	assert_bool(RoomGraph.new().has_room("harbour")).is_true()
	_do("pier", "seagull", "tap")
	assert_bool(state.holds_item("old_scrap")).is_true()
	var flash := _do("depot", "gnu_locker", "code", "", str(d["code"]))
	assert_str(str(flash["say"])).is_equal(str(d["flash"]))
	assert_str(str(story.get_piece(str(flash["say"]))["text"])).contains("HARBOUR")
	assert_bool(state.has_seen_decoy("old_locker_code")).is_true()
	assert_bool(inv.has("die_bent")).is_false()
	# The wrong place says what went wrong and points back.
	var arrive := _do("harbour", "harbour", "enter")
	assert_array(ChainRules.say_ids(arrive)).contains_exactly(Array(d["wrong_place_says"]))
	var slip := str(story.get_piece("narrator.cutter.harbour_slip")["text"])
	assert_str(slip).contains("September")
	assert_str(slip).contains("fortunes")
	assert_str(str(story.get_piece("seagull.item.old_scrap")["text"])).contains("March")
	# Only once; Seagull now admits the scrap was old.
	assert_bool(_do("harbour", "harbour", "enter").is_empty()).is_true()
	assert_str(str(_do("pier", "seagull", "tap")["id"])).is_equal("seagull_after_decoy")
	# The right code still opens the locker afterwards.
	assert_str(str(_do("depot", "gnu_locker", "code", "", _right_code())["id"])).is_equal("locker_right")


func test_crew_finds_count_for_everyone() -> void:
	# A crewmate found and straightened the die; this phone only needs the spanner.
	inv["die_bent"] = "found"
	inv["cutter_die"] = "found"
	state.learn("die_out")
	assert_str(_step_id()).is_equal("install")
	_do("workshop", "penguin", "tap")
	assert_bool(ChainRules.has_item(data, state, inv, "spanner")).is_true()
	assert_bool(_do("shop", "cutter", "use", "cutter_die").is_empty()).is_false()


func test_nothing_is_lost_for_good() -> void:
	# Breadth-first over every state the chain can reach from a fresh start;
	# from each of them the goal must still be reachable.
	var actions := _all_actions()
	var start := {"state": ChainState.new(), "inv": {}}
	var seen: Dictionary = {}
	var edges: Dictionary = {}
	var nodes: Dictionary = {}
	var todo: Array = [start]
	while not todo.is_empty():
		var node: Dictionary = todo.pop_front()
		var key := _key(node)
		if seen.has(key):
			continue
		seen[key] = true
		nodes[key] = node
		edges[key] = []
		for next in _successors(node, actions):
			edges[key].append(_key(next))
			if not seen.has(_key(next)):
				todo.append(next)
	assert_int(seen.size()).is_greater(10)
	var good: Dictionary = {}
	for key: String in nodes:
		if ChainRules.goal_reached(data, _chain(), nodes[key]["state"], nodes[key]["inv"]):
			good[key] = true
	assert_bool(good.is_empty()).is_false()
	var grew := true
	while grew:
		grew = false
		for key: String in nodes:
			if good.has(key):
				continue
			for to: String in edges[key]:
				if good.has(to):
					good[key] = true
					grew = true
					break
	for key: String in nodes:
		assert_bool(good.has(key)).override_failure_message("dead end: " + key).is_true()


func _all_actions() -> Array:
	var out: Array = []
	var items: Array = data["items"].keys()
	for i: Dictionary in _chain()["interactions"]:
		var room := str(i["room"])
		var target := str(i["target"])
		match str(i["verb"]):
			"tap":
				out.append([room, target, "tap", "", ""])
			"enter":
				out.append([room, target, "enter", "", ""])
			"use":
				for item: String in items:
					out.append([room, target, "use", item, ""])
			"code":
				for code: String in [_right_code(), "241", "000"]:
					out.append([room, target, "code", "", code])
	return out


func _successors(node: Dictionary, actions: Array) -> Array:
	var out: Array = []
	for a: Array in actions:
		var s: ChainState = (node["state"] as ChainState).duplicate_state()
		var v: Dictionary = (node["inv"] as Dictionary).duplicate()
		var result := ""
		if a[2] == "code":
			result = ChainRules.code_result(data, a[1], a[4], answers)
		var i := ChainRules.resolve(data, s, v, a[0], a[1], a[2], a[3], result)
		if i.is_empty():
			continue
		var effects := ChainRules.apply(i, s)
		ChainRules.apply_to_inventory(effects, v)
		out.append({"state": s, "inv": v})
		# A close-up the action opened can also be finished at once.
		for effect in effects:
			if effect.has("open") and not str(effect["open"]).begins_with("lock:"):
				var s2 := s.duplicate_state()
				var v2 := v.duplicate()
				var done := ChainRules.resolve(data, s2, v2, a[0], str(effect["open"]), "done")
				if not done.is_empty():
					ChainRules.apply_to_inventory(ChainRules.apply(done, s2), v2)
					out.append({"state": s2, "inv": v2})
	return out


func _key(node: Dictionary) -> String:
	var s: ChainState = node["state"]
	var f := s.facts.duplicate()
	f.sort()
	var h := s.held.duplicate()
	h.sort()
	var d := s.decoys_seen.duplicate()
	d.sort()
	var v: Dictionary = node["inv"]
	var keys: Array = v.keys()
	keys.sort()
	var inv_parts: Array[String] = []
	for k: String in keys:
		inv_parts.append("%s=%s" % [k, v[k]])
	return "%s|%s|%s|%s" % [",".join(f), ",".join(h), ",".join(d), ",".join(inv_parts)]


func test_chain_state_round_trip_and_file() -> void:
	var path := "user://test_chain_state.json"
	var s := ChainState.new(path)
	s.learn("die_out")
	s.hold("old_scrap")
	s.see_decoy("old_locker_code")
	var again := ChainState.new(path)
	assert_array(again.facts).contains_exactly(["die_out"])
	assert_array(again.held).contains_exactly(["old_scrap"])
	assert_array(again.decoys_seen).contains_exactly(["old_locker_code"])
	again.reset()
	assert_array(ChainState.new(path).facts).is_empty()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
