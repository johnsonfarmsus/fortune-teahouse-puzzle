# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ScoreboardUrl
extends RefCounted
## Where the scoreboard lives. Resolution order, first valid wins:
##   1. `?scoreboard=https://...` on the web build (https only; http for localhost)
##   2. `config.json` next to index.html, {"scoreboard_url": "/api/v1"} (the VPS deploy
##      writes it; the game fetches it at startup, see Progress)
##   3. the project setting `fortune/scoreboard_url`
##   4. "" which means offline only.
## Values 2 and 3 may be relative ("/api/v1" or "/"): the scoreboard is then on the
## page's own origin. HTTPRequest needs an absolute URL, so they are joined to the origin.

const SETTING := "fortune/scoreboard_url"
const QUERY_KEY := "scoreboard"
const CONFIG_FILE := "config.json"
const API_SUFFIX := "/api/v1"  # the stores add this themselves; the base is the server root


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
			var url := normalise(pair.substr(eq + 1).replace("+", " ").uri_decode())
			return url if allowed_in_query(url) else ""
	return ""


## A link must not point the game at an unencrypted remote server: https, or
## http only for this machine (localhost, 127.0.0.1, [::1]).
static func allowed_in_query(url: String) -> bool:
	if url.begins_with("https://"):
		return true
	if not url.begins_with("http://"):
		return false
	var authority := url.substr(7).get_slice("/", 0)
	if authority.contains("@"):
		return false
	var host := authority
	if authority.begins_with("["):
		host = authority.get_slice("]", 0) + "]"
	else:
		host = authority.get_slice(":", 0)
	return ["localhost", "127.0.0.1", "[::1]"].has(host)


## The override from the page address; "" off the web or when absent.
static func web_override() -> String:
	if not OS.has_feature("web"):
		return ""
	var search: Variant = JavaScriptBridge.eval("window.location.search", true)
	return from_query(str(search)) if search != null else ""


## An absolute URL as `normalise` does, or a same-origin path ("/api/v1", "/") joined to
## `origin` (for example "https://play.example.org"). "" when unusable or no origin is known.
static func normalise_with_origin(url: String, origin: String) -> String:
	var trimmed := url.strip_edges()
	if not trimmed.begins_with("/") or trimmed.begins_with("//"):
		return normalise(trimmed)
	var base := normalise(origin)
	if base == "":
		return ""
	while trimmed.ends_with("/"):
		trimmed = trimmed.substr(0, trimmed.length() - 1)
	if trimmed.ends_with(API_SUFFIX):
		trimmed = trimmed.substr(0, trimmed.length() - API_SUFFIX.length())
	return base + trimmed


## The `scoreboard_url` value of a config.json body, or "" when absent or not JSON.
static func from_config_json(text: String) -> String:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and (parsed as Dictionary).get("scoreboard_url") is String:
		return str((parsed as Dictionary)["scoreboard_url"])
	return ""


## Query override, then config.json value, then the project setting, then "" (offline).
static func resolve_chain(query_override: String, config_value: String, setting_value: String, origin: String = "") -> String:
	var from_query_url := normalise(query_override)
	if from_query_url != "":
		return from_query_url
	var from_config := normalise_with_origin(config_value, origin)
	if from_config != "":
		return from_config
	return normalise_with_origin(setting_value, origin)


## The query override wins over the project setting when it is a valid URL.
static func resolve(setting_value: String, query_override: String) -> String:
	return resolve_chain(query_override, "", setting_value)


## The page's origin on the web ("https://host[:port]"), else "".
static func page_origin() -> String:
	if not OS.has_feature("web"):
		return ""
	var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
	return str(origin) if origin != null else ""


## Absolute URL of config.json beside index.html on the web, else "".
static func config_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var url: Variant = JavaScriptBridge.eval("new URL('%s', window.location.href).href" % CONFIG_FILE, true)
	return str(url) if url != null else ""


## The base URL this run should use ("" means offline only).
static func configured() -> String:
	return resolve_chain(web_override(), "", str(ProjectSettings.get_setting(SETTING, "")), page_origin())
