# SPDX-License-Identifier: AGPL-3.0-or-later
class_name LuckyWords
extends RefCounted
## Lucky words are typed on a phone, so compare them forgivingly.


## Uppercases and keeps only A to Z and 0 to 9 (" tux." becomes "TUX").
static func normalise(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		var code := ch.unicode_at(0)
		if (code >= 65 and code <= 90) or (code >= 48 and code <= 57):
			out += ch
	return out
