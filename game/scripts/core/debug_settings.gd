# SPDX-License-Identifier: AGPL-3.0-or-later
class_name DebugSettings
extends RefCounted
## The switch between the adventure layer and the old screens (the WP3 Town,
## Shop and MachineView), kept until the slices replace them. The project
## setting `fortune/debug_legacy_screens` (default false) is the build's
## default; the Settings toggle saves an override on this phone.

const SETTING := "fortune/debug_legacy_screens"
const PATH := "user://debug.json"

## Tests set this to avoid touching the real file ("" means no file).
static var path: String = PATH
## Tests force the answer: -1 reads the file and setting, 0 is off, 1 is on.
static var forced: int = -1


static func project_default() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, false))


static func legacy_screens() -> bool:
	if forced >= 0:
		return forced == 1
	var saved := JsonFile.read(path) if path != "" else {}
	if saved.has("legacy_screens"):
		return bool(saved["legacy_screens"])
	return project_default()


static func set_legacy_screens(on: bool) -> void:
	if forced >= 0:
		forced = 1 if on else 0
	if path != "":
		JsonFile.write(path, {"legacy_screens": on})
