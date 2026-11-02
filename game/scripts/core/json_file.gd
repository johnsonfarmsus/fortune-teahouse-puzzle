# SPDX-License-Identifier: AGPL-3.0-or-later
class_name JsonFile
extends RefCounted
## Tiny JSON file helpers. Reading never raises: a missing or bad file is {}.


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if parser.data is Dictionary:
		return parser.data
	return {}


static func write(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "  "))
	return true
