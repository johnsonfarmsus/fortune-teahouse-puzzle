# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ScoreboardUrl
extends RefCounted
## Where the scoreboard lives. The project setting `fortune/scoreboard_url`
## (empty means offline only) can be overridden on the web build with a
## `?scoreboard=https://...` query parameter.

const SETTING := "fortune/scoreboard_url"
const QUERY_KEY := "scoreboard"


## A usable base URL (http or https, no trailing slash) or "".
static func normalise(url: String) -> String:
	var trimmed := url.strip_edges()
	while trimmed.ends_with("/"):
		trimmed = trimmed.substr(0, trimmed.length() - 1)
	if not (trimmed.begins_with("http://") or trimmed.begins_with("https://")):
		return ""
	if trimmed.length() <= trimmed.find("://") + 3:
		return ""
	return trimmed


## Reads `scoreboard` from a query string such as "?a=1&scoreboard=https%3A%2F%2Fx.org".
static func from_query(query: String) -> String:
	var q := query.strip_edges()
	if q.begins_with("?"):
		q = q.substr(1)
	var hash_at := q.find("#")
	if hash_at >= 0:
		q = q.substr(0, hash_at)
	for pair in q.split("&", false):
		var eq := pair.find("=")
		if eq < 0:
			continue
		if pair.substr(0, eq).uri_decode() == QUERY_KEY:
			return normalise(pair.substr(eq + 1).replace("+", " ").uri_decode())
	return ""


## The override from the page address; "" off the web or when absent.
static func web_override() -> String:
	if not OS.has_feature("web"):
		return ""
	var search: Variant = JavaScriptBridge.eval("window.location.search", true)
	return from_query(str(search)) if search != null else ""


## The query override wins over the project setting when it is a valid URL.
static func resolve(setting_value: String, query_override: String) -> String:
	var override := normalise(query_override)
	if override != "":
		return override
	return normalise(setting_value)


## The base URL this run should use ("" means offline only).
static func configured() -> String:
	return resolve(str(ProjectSettings.get_setting(SETTING, "")), web_override())
