# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## Sound effects: sfx.json loads, every interaction id the scenes and the data
## use has a sound, and the synthesiser makes sensible streams.


func _required() -> Array[String]:
	var extra: Array[String] = []
	extra.append_array(ChainRules.sfx_ids(JsonFile.read("res://data/chains/cookie_machine.json")))
	var graph := RoomGraph.new()
	for id in graph.rooms():
		extra.append(str(graph.room(id).get("sound", "")))
	return SfxBank.required_ids(extra)


func test_sfx_data_loads() -> void:
	var bank := SfxBank.new()
	assert_int(bank.ids().size()).is_greater(30)
	assert_int(bank.rate).is_equal(22050)
	for id in bank.ids():
		var def := bank.definition(id)
		assert_bool(def.is_empty()).override_failure_message(id).is_false()
		assert_bool(SfxSynth.WAVES.has(str(def.get("wave", "")))).override_failure_message(id).is_true()


func test_every_interaction_id_has_a_sound() -> void:
	var bank := SfxBank.new()
	var required := _required()
	assert_array(required).contains(["tap", "pickup", "deny", "unlock", "babble.penguin", "ambient.sea"])
	for id in required:
		assert_bool(bank.has(id)).override_failure_message("no sound for " + id).is_true()
		var stream := bank.stream(id)
		assert_object(stream).is_not_null()
		assert_int(stream.data.size()).override_failure_message(id).is_greater(100)


func test_every_speaker_babbles() -> void:
	var bank := SfxBank.new()
	for speaker in ["Red Panda", "Penguin", "Gopher", "Seagull", "Crab", "Anglerfish", "Gnu", "Narrator"]:
		assert_bool(bank.has(SfxBank.babble_id(speaker))).override_failure_message(speaker).is_true()


func test_synth_shapes() -> void:
	var blip := SfxSynth.samples({"wave": "square", "freq": 440, "duration": 0.1, "volume": 0.5})
	assert_int(blip.size()).is_equal(2205)
	var peak := 0.0
	for s in blip:
		peak = maxf(peak, absf(s))
	assert_float(peak).is_between(0.3, 0.5)
	assert_float(absf(blip[blip.size() - 1])).is_less(0.05)  # decays to silence
	var tune := SfxSynth.samples({"wave": "triangle", "notes": [440, 0, 660], "note_len": 0.05})
	assert_int(tune.size()).is_equal(int(0.15 * 22050))
	assert_float(tune[int(0.075 * 22050)]).is_equal(0.0)  # the rest
	var loop := SfxSynth.build({"wave": "noise", "freq": 200, "duration": 1.0, "loop": true, "lfo": 0.5})
	assert_int(loop.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(loop.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)


func test_alias_and_unknown() -> void:
	var bank := SfxBank.new({"sounds": {"a": {"wave": "sine", "freq": 300, "duration": 0.05}, "b": {"alias": "a"}, "loop1": {"alias": "loop2"}, "loop2": {"alias": "loop1"}}})
	assert_bool(bank.has("b")).is_true()
	assert_bool(bank.has("loop1")).is_false()
	assert_object(bank.stream("zzz")).is_null()
