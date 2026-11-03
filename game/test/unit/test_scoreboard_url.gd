# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite


func test_normalise_accepts_http_and_https_only() -> void:
	assert_str(ScoreboardUrl.normalise("https://board.example.org")).is_equal("https://board.example.org")
	assert_str(ScoreboardUrl.normalise("  https://board.example.org/// ")).is_equal("https://board.example.org")
	assert_str(ScoreboardUrl.normalise("http://localhost:8000/")).is_equal("http://localhost:8000")
	assert_str(ScoreboardUrl.normalise("")).is_empty()
	assert_str(ScoreboardUrl.normalise("board.example.org")).is_empty()
	assert_str(ScoreboardUrl.normalise("javascript:alert(1)")).is_empty()
	assert_str(ScoreboardUrl.normalise("ftp://board.example.org")).is_empty()
	assert_str(ScoreboardUrl.normalise("https://")).is_empty()


func test_from_query_reads_the_scoreboard_parameter() -> void:
	assert_str(ScoreboardUrl.from_query("?scoreboard=https%3A%2F%2Fboard.example.org")).is_equal("https://board.example.org")
	assert_str(ScoreboardUrl.from_query("?a=1&scoreboard=http://localhost:8000/&b=2")).is_equal("http://localhost:8000")
	assert_str(ScoreboardUrl.from_query("scoreboard=https://x.org")).is_equal("https://x.org")
	assert_str(ScoreboardUrl.from_query("?scoreboard=https://x.org#top")).is_equal("https://x.org")


func test_from_query_ignores_anything_else() -> void:
	assert_str(ScoreboardUrl.from_query("")).is_empty()
	assert_str(ScoreboardUrl.from_query("?")).is_empty()
	assert_str(ScoreboardUrl.from_query("?scoreboard=")).is_empty()
	assert_str(ScoreboardUrl.from_query("?scoreboard=nonsense")).is_empty()
	assert_str(ScoreboardUrl.from_query("?scoreboard=javascript:alert(1)")).is_empty()
	assert_str(ScoreboardUrl.from_query("?scoreboards=https://x.org")).is_empty()
	assert_str(ScoreboardUrl.from_query("?other=https://x.org")).is_empty()


func test_override_beats_the_setting_only_when_valid() -> void:
	assert_str(ScoreboardUrl.resolve("https://a.org", "https://b.org")).is_equal("https://b.org")
	assert_str(ScoreboardUrl.resolve("https://a.org", "")).is_equal("https://a.org")
	assert_str(ScoreboardUrl.resolve("https://a.org", "nonsense")).is_equal("https://a.org")
	assert_str(ScoreboardUrl.resolve("", "")).is_empty()
	assert_str(ScoreboardUrl.resolve("", "https://b.org")).is_equal("https://b.org")


func test_web_override_is_a_no_op_off_the_web() -> void:
	if OS.has_feature("web"):
		return
	assert_str(ScoreboardUrl.web_override()).is_empty()


func test_the_game_defaults_to_offline_only() -> void:
	assert_bool(ProjectSettings.has_setting(ScoreboardUrl.SETTING)).is_true()
	assert_str(str(ProjectSettings.get_setting(ScoreboardUrl.SETTING))).is_empty()


func test_retry_after_header_is_parsed() -> void:
	assert_int(HttpTransport.retry_after_seconds(PackedStringArray(["Content-Type: application/json", "Retry-After: 12"]))).is_equal(12)
	assert_int(HttpTransport.retry_after_seconds(PackedStringArray(["retry-after:3"]))).is_equal(3)
	assert_int(HttpTransport.retry_after_seconds(PackedStringArray(["Content-Type: x"]))).is_equal(0)


func test_nudges_have_words_and_the_banner_line_names_the_sender() -> void:
	for id in Nudges.IDS:
		assert_str(Nudges.text(id)).is_not_empty()
	assert_str(Nudges.label("reread_the_clue")).is_equal("Reread the clue")
	var line := Nudges.describe(FakeScoreboard.hint(7, "cookie_machine", "ask_a_crewmate", "Mina"))
	assert_str(line).starts_with("Mina (Oven) says:")
	assert_str(line).contains(Nudges.text("ask_a_crewmate"))
	assert_str(Nudges.describe({"from_name": "anonymous", "nudge_id": "nope"})).starts_with("A maintainer says:")


func test_the_query_accepts_https_and_only_local_http() -> void:
	assert_str(ScoreboardUrl.from_query("?scoreboard=https://board.example.org")).is_equal("https://board.example.org")
	assert_str(ScoreboardUrl.from_query("?scoreboard=http://localhost:8000")).is_equal("http://localhost:8000")
	assert_str(ScoreboardUrl.from_query("?scoreboard=http://127.0.0.1:8000/")).is_equal("http://127.0.0.1:8000")
	assert_str(ScoreboardUrl.from_query("?scoreboard=http://[::1]:8000")).is_equal("http://[::1]:8000")
	assert_str(ScoreboardUrl.from_query("?scoreboard=http://board.example.org")).is_empty()
	assert_str(ScoreboardUrl.from_query("?scoreboard=http://localhost.evil.org")).is_empty()
	assert_str(ScoreboardUrl.from_query("?scoreboard=http://localhost@evil.org")).is_empty()
	assert_str(ScoreboardUrl.from_query("?scoreboard=http://evil.org/localhost")).is_empty()
	# The project setting is the maintainers' own choice, so it may be plain http.
	assert_str(ScoreboardUrl.resolve("http://board.lan:8000", "")).is_equal("http://board.lan:8000")


func test_relative_values_join_the_page_origin() -> void:
	var o := "https://play.example.org"
	assert_str(ScoreboardUrl.normalise_with_origin("/api/v1", o)).is_equal(o)
	assert_str(ScoreboardUrl.normalise_with_origin("/", o)).is_equal(o)
	assert_str(ScoreboardUrl.normalise_with_origin("/api/v1/", o)).is_equal(o)
	assert_str(ScoreboardUrl.normalise_with_origin("/board/api/v1", o)).is_equal(o + "/board")
	assert_str(ScoreboardUrl.normalise_with_origin("https://a.org/", o)).is_equal("https://a.org")


func test_relative_values_are_offline_without_an_origin_or_when_protocol_relative() -> void:
	assert_str(ScoreboardUrl.normalise_with_origin("/api/v1", "")).is_empty()
	assert_str(ScoreboardUrl.normalise_with_origin("//evil.org/api/v1", "https://play.example.org")).is_empty()
	assert_str(ScoreboardUrl.normalise_with_origin("", "https://play.example.org")).is_empty()
	assert_str(ScoreboardUrl.normalise_with_origin("api/v1", "https://play.example.org")).is_empty()


func test_config_json_is_read_defensively() -> void:
	assert_str(ScoreboardUrl.from_config_json('{"scoreboard_url": "/api/v1"}')).is_equal("/api/v1")
	assert_str(ScoreboardUrl.from_config_json("<html>404</html>")).is_empty()
	assert_str(ScoreboardUrl.from_config_json("[]")).is_empty()
	assert_str(ScoreboardUrl.from_config_json('{"scoreboard_url": 5}')).is_empty()
	assert_str(ScoreboardUrl.from_config_json("{}")).is_empty()


func test_resolution_order_query_then_config_then_setting_then_offline() -> void:
	var o := "https://play.example.org"
	assert_str(ScoreboardUrl.resolve_chain("https://q.org", "/api/v1", "https://s.org", o)).is_equal("https://q.org")
	assert_str(ScoreboardUrl.resolve_chain("", "/api/v1", "https://s.org", o)).is_equal(o)
	assert_str(ScoreboardUrl.resolve_chain("nonsense", "/api/v1", "https://s.org", o)).is_equal(o)
	assert_str(ScoreboardUrl.resolve_chain("", "", "https://s.org", o)).is_equal("https://s.org")
	assert_str(ScoreboardUrl.resolve_chain("", "garbage", "/api/v1", o)).is_equal(o)
	assert_str(ScoreboardUrl.resolve_chain("", "", "", o)).is_empty()
	assert_str(ScoreboardUrl.resolve_chain("", "/api/v1", "", "")).is_empty()


func test_site_config_applies_unless_the_query_overrides() -> void:
	# Off the web there is no origin, so a relative value stays offline.
	if OS.has_feature("web"):
		return
	var progress: Node = auto_free(load("res://autoload/progress.gd").new())
	assert_bool(progress.apply_site_config('{"scoreboard_url": "/api/v1"}')).is_false()
	progress._query_override = true
	assert_bool(progress.apply_site_config('{"scoreboard_url": "https://x.org"}')).is_false()
	assert_str(progress.scoreboard_url).is_empty()
