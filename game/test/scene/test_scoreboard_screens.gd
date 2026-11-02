# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## Scoreboard screens, the Hud badge, the hint banner and Settings, with the
## real autoloads and a fake transport (no network).

const PROGRESS_PATH := "user://test_sb_progress.json"
const QUEUE_PATH := "user://test_sb_queue.json"
const MACHINE := "cookie_machine"
const ALL_SIX := {"logic": 2, "wiring": 1, "sequence": 1, "word": 3, "rhythm": 1, "helper": 1}

var fake: FakeScoreboard
var remote: RemoteProgressStore


func before_test() -> void:
	_cleanup()
	GameState.persist = false
	GameState.player = PlayerState.new()
	GameState.player.ensure_device_id()
	Progress.persist_settings = false
	Progress.scoreboard_url = ""
	Progress.scoreboard_enabled = true
	Progress.set_store(LocalProgressStore.new(PROGRESS_PATH))
	Hints.pushed_nudges = {}
	Router.clear()
	fake = FakeScoreboard.new()
	Progress.transport_override = fake.transport()
	Progress.queue_path = QUEUE_PATH


func after_test() -> void:
	Router.clear()
	Progress.scoreboard_url = ""
	Progress.transport_override = Callable()
	Progress.queue_path = RemoteProgressStore.DEFAULT_QUEUE_PATH
	Progress.set_store(LocalProgressStore.new(PROGRESS_PATH))
	_cleanup()


func _cleanup() -> void:
	for path in [PROGRESS_PATH, QUEUE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Makes the remote store the active one, with this player in `MACHINE`.
func _go_online() -> void:
	Progress.scoreboard_url = FakeScoreboard.BASE
	remote = RemoteProgressStore.new(FakeScoreboard.BASE, LocalProgressStore.new(PROGRESS_PATH), fake.transport(), QUEUE_PATH)
	Progress.set_store(remote)
	GameState.player.choose_crew(MACHINE)
	remote.set_identity(GameState.device_id, MACHINE, "")


func _button_with_text(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node
	return null


func _texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node in root.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out


func _has_text(root: Node, needle: String) -> bool:
	for text in _texts(root):
		if text.contains(needle):
			return true
	return false


func _title(part: String) -> String:
	return str(PuzzleData.get_part(MACHINE, part)["title"])


func _check_buttons(root: Node, label: String) -> void:
	var buttons := root.find_children("*", "BaseButton", true, false)
	assert_bool(buttons.is_empty()).override_failure_message("%s has no buttons" % label).is_false()
	for node in buttons:
		var b := node as BaseButton
		assert_float(b.custom_minimum_size.x).override_failure_message("%s: %s too narrow" % [label, b.name]).is_greater_equal(44.0)
		assert_float(b.custom_minimum_size.y).override_failure_message("%s: %s too short" % [label, b.name]).is_greater_equal(44.0)


# --- Crew progress ---------------------------------------------------------------------


func test_crew_progress_offline_shows_this_phone_only() -> void:
	Progress.store.record_part_solved(MACHINE, "logic", GameState.device_id, true)
	var screen := Router.push(Paths.CREW_PROGRESS, {"machine": MACHINE})
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Offline, showing this phone only")).is_true()
	assert_bool(_has_text(screen, "1 of 6 parts working")).is_true()
	assert_bool(_has_text(screen, "fixed on this phone")).is_true()
	assert_bool(_has_text(screen, "Send a nudge")).is_false()
	_check_buttons(screen, "crew progress offline")
	for part in Ids.PARTS:
		Progress.store.record_part_solved(MACHINE, part, GameState.device_id, true)
	assert_bool(_has_text(screen, "Machine runs!")).is_true()


func test_crew_progress_online_shows_the_crew_and_contributors() -> void:
	_go_online()
	var contributors := [{"name": "Ada", "machine": MACHINE, "via": "solve", "first_merged_at": "2027-10-29T17:31:40Z"}]
	fake.answer("GET", "/crews/cookie_machine", 200, FakeScoreboard.crew(MACHINE, {"logic": 3, "wiring": 1}, false, contributors))
	var screen := Router.push(Paths.CREW_PROGRESS, {"machine": MACHINE})
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Online, showing your whole crew")).is_true()
	assert_bool(_has_text(screen, _title("logic") + ": fixed by 3 crewmates")).is_true()
	assert_bool(_has_text(screen, _title("wiring") + ": fixed by 1 crewmate")).is_true()
	assert_bool(_has_text(screen, _title("sequence") + ": Broken")).is_true()
	assert_bool(_has_text(screen, "2 of 6 parts working")).is_true()
	assert_bool(_has_text(screen, "Ada")).is_true()
	assert_bool(_has_text(screen, "Send a nudge")).is_false()
	_check_buttons(screen, "crew progress online")
	# A progress screen turns polling on; popping it turns polling off.
	assert_array(remote.watched_machines()).contains_exactly([MACHINE])
	Router.pop()
	assert_array(remote.watched_machines()).is_empty()


func test_machine_view_links_to_crew_progress_and_polls() -> void:
	_go_online()
	var view := Router.push(Paths.MACHINE_VIEW, {"machine": MACHINE})
	await get_tree().process_frame
	assert_array(remote.watched_machines()).contains_exactly([MACHINE])
	_button_with_text(view, "See crew progress").pressed.emit()
	assert_str(Router.top().scene_file_path).is_equal(Paths.CREW_PROGRESS)
	assert_int(Router.depth()).is_equal(2)


func test_a_puzzle_screen_polls_hints_but_not_progress() -> void:
	_go_online()
	var fortune_hint := FakeScoreboard.hint(4, MACHINE)
	fake.answer("GET", "/hints", 200, {"crew": MACHINE, "hints": [fortune_hint]})
	Router.push(Paths.PUZZLE_HOST, {"machine": MACHINE, "part": "logic"})
	await get_tree().process_frame
	assert_bool(remote.hint_polling()).is_true()
	assert_array(remote.watched_machines()).is_empty()
	assert_int(fake.count("GET", "/hints?crew=cookie_machine")).is_equal(1)


# --- Maintainers and nudges ---------------------------------------------------------------


func test_maintainer_badge_and_send_a_nudge() -> void:
	_go_online()
	var hud: CanvasLayer = auto_free(load("res://scenes/hud/hud.tscn").instantiate())
	add_child(hud)
	var badge := hud.get_node("Bar/Row/CrewBox/MaintainerBadge") as Label
	assert_bool(badge.visible).is_false()
	assert_bool(Progress.is_maintainer()).is_false()
	fake.answer("GET", "/crews/cookie_machine", 200, FakeScoreboard.crew(MACHINE, ALL_SIX, true))
	fake.answer("GET", "/hints/nudges", 200, {"nudges": ["reread_the_clue", "ask_a_crewmate"]})
	fake.answer("POST", "/hints", 200, {"created": true, "hint": FakeScoreboard.hint(9, "oven")})
	remote.refresh()
	assert_bool(Progress.is_maintainer()).is_true()
	assert_bool(badge.visible).is_true()
	assert_str(badge.text).is_equal("Maintainer")

	var screen := Router.push(Paths.CREW_PROGRESS, {"machine": MACHINE})
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Machine runs!")).is_true()
	assert_bool(_has_text(screen, "Send a nudge")).is_true()
	# Only the other two crews can be nudged.
	assert_object(_button_with_text(screen, "Cookie Machine")).is_null()
	assert_object(_button_with_text(screen, "Oven (selected)")).is_null()
	var first_target := screen.target_crew as String
	assert_bool(first_target != MACHINE and Ids.MACHINES.has(first_target)).is_true()
	screen.choose_target("oven")
	assert_object(_button_with_text(screen, "Oven (selected)")).is_not_null()
	var nudge := _button_with_text(screen, "Ask a crewmate")
	assert_object(nudge).is_not_null()
	_check_buttons(screen, "crew progress maintainer")
	nudge.pressed.emit()
	assert_dict(fake.last_post_body()).is_equal(
		{"device_id": GameState.device_id, "to_crew": "oven", "nudge_id": "ask_a_crewmate"}
	)
	assert_bool(_has_text(screen, "Nudge sent.")).is_true()


func test_non_maintainers_never_see_the_nudge_section() -> void:
	_go_online()
	fake.answer("GET", "/crews/cookie_machine", 200, FakeScoreboard.crew(MACHINE, {"logic": 1}, false))
	var screen := Router.push(Paths.CREW_PROGRESS, {"machine": MACHINE})
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Send a nudge")).is_false()


# --- Incoming hints -----------------------------------------------------------------------


func test_a_polled_hint_reaches_hints_events_and_the_banner() -> void:
	_go_online()
	var banner: HintBanner = auto_free(load(Paths.HINT_BANNER).instantiate())
	add_child(banner)
	var heard: Array = []
	var listener := func(text: String) -> void: heard.append(text)
	Events.hint_received.connect(listener)
	fake.answer("GET", "/hints", 200, {"crew": MACHINE, "hints": [FakeScoreboard.hint(7, MACHINE, "reread_the_clue", "Mina")]})
	remote.set_watching(_none(), true)
	assert_int(heard.size()).is_equal(1)
	assert_str(heard[0]).starts_with("Mina (Oven) says:")
	assert_str(heard[0]).contains(Nudges.text("reread_the_clue"))
	assert_str(Hints.pushed_nudges[""]).is_equal(heard[0])
	assert_bool(banner.is_showing()).is_true()
	assert_str(banner.current_text()).is_equal(heard[0])
	Events.hint_received.disconnect(listener)


func _none() -> Array[String]:
	return []


func test_banner_queues_and_dismisses() -> void:
	var banner: HintBanner = auto_free(load(Paths.HINT_BANNER).instantiate())
	add_child(banner)
	assert_bool(banner.is_showing()).is_false()
	Hints.receive_pushed_nudge("", "First hint")
	Hints.receive_pushed_nudge("", "Second hint")
	assert_str(banner.current_text()).is_equal("First hint")
	assert_int(banner.pending.size()).is_equal(1)
	_check_buttons(banner, "hint banner")
	banner.dismiss()
	assert_str(banner.current_text()).is_equal("Second hint")
	banner.dismiss()
	assert_bool(banner.is_showing()).is_false()


func test_the_hud_hosts_a_banner() -> void:
	var hud: CanvasLayer = auto_free(load("res://scenes/hud/hud.tscn").instantiate())
	add_child(hud)
	assert_int(hud.find_children("*", "HintBanner", true, false).size()).is_equal(1)


# --- Settings ---------------------------------------------------------------------------


func test_settings_scoreboard_section_without_a_url() -> void:
	var screen := Router.push(Paths.SETTINGS)
	await get_tree().process_frame
	var toggle := screen.find_children("*", "CheckButton", true, false).filter(
		func(n: Node) -> bool: return (n as CheckButton).text == "Use scoreboard"
	)[0] as CheckButton
	assert_bool(toggle.disabled).is_true()
	assert_bool(_has_text(screen, "Address: none set")).is_true()
	assert_bool(_has_text(screen, "No scoreboard is set up")).is_true()
	assert_bool((_button_with_text(screen, "Sync now")).disabled).is_true()
	_check_buttons(screen, "settings")


func test_settings_sync_now_flushes_and_shows_the_queue() -> void:
	fake.offline = true
	_go_online()
	Progress.store.record_part_solved(MACHINE, "logic", GameState.device_id, true)
	assert_int(Progress.queue_size()).is_greater_equal(1)
	var screen := Router.push(Paths.SETTINGS)
	await get_tree().process_frame
	assert_bool(_has_text(screen, "Address: " + FakeScoreboard.BASE)).is_true()
	assert_bool(_has_text(screen, "Offline.")).is_true()
	assert_bool(_has_text(screen, "Waiting to send: %d" % Progress.queue_size())).is_true()
	fake.offline = false
	_button_with_text(screen, "Sync now").pressed.emit()
	assert_int(Progress.queue_size()).is_equal(0)
	assert_bool(_has_text(screen, "Waiting to send: 0")).is_true()
	assert_bool(_has_text(screen, "Online")).is_true()


func test_toggle_off_goes_back_to_the_local_store_and_on_returns() -> void:
	_go_online()
	Progress.use_scoreboard(false)
	assert_bool(Progress.store is RemoteProgressStore).is_false()
	assert_bool(Progress.scoreboard_available()).is_true()
	Progress.use_scoreboard(true)
	assert_bool(Progress.store is RemoteProgressStore).is_true()
	# Without a URL the toggle changes nothing.
	Progress.scoreboard_url = ""
	Progress.use_scoreboard(true)
	assert_bool(Progress.store is RemoteProgressStore).is_true()


func test_contributors_screen_asks_the_scoreboard_once() -> void:
	_go_online()
	fake.answer(
		"GET",
		"/contributors",
		200,
		{"total": 1, "contributors": [{"name": "Ada", "machine": "oven", "via": "solve", "first_merged_at": "2027-10-29T17:31:40Z"}]}
	)
	var screen := Router.push(Paths.CONTRIBUTORS)
	await get_tree().process_frame
	assert_int(fake.count("GET", "/contributors")).is_equal(1)
	assert_bool(_has_text(screen, "Ada")).is_true()
