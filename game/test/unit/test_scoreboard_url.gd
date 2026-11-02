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
