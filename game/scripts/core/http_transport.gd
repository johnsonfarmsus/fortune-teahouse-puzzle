# SPDX-License-Identifier: AGPL-3.0-or-later
class_name HttpTransport
extends Node
## The real network for RemoteProgressStore: one HTTPRequest node per request
## (works on the single-threaded web export; nothing blocks). Pass
## `Callable(transport, "request")` as the store's transport.
##
## request(method, url, body, done) calls done(status, data, retry_after) when
## the request ends: status 0 means no answer, data is the parsed JSON body
## ({} if none) and retry_after is the Retry-After header in seconds (0 if none).

const TIMEOUT_SECONDS := 10.0


func request(method: String, url: String, body: Dictionary, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	http.request_completed.connect(_on_completed.bind(http, done))
	var headers := PackedStringArray(["Accept: application/json"])
	var verb := HTTPClient.METHOD_GET
	var payload := ""
	if method == "POST":
		verb = HTTPClient.METHOD_POST
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	var err := http.request(url, headers, verb, payload)
	if err != OK:
		http.queue_free()
		done.call(0, {}, 0)


func _on_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, done: Callable) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		done.call(0, {}, 0)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	done.call(code, data, retry_after_seconds(headers))


static func retry_after_seconds(headers: PackedStringArray) -> int:
	for line in headers:
		if line.to_lower().begins_with("retry-after:"):
			return maxi(0, int(line.substr(line.find(":") + 1).strip_edges()))
	return 0
