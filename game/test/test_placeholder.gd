# SPDX-License-Identifier: AGPL-3.0-or-later
extends GdUnitTestSuite
## Smoke test proving the gdUnit4 pipeline runs headless.


func test_project_name() -> void:
	assert_str(ProjectSettings.get_setting("application/config/name")).is_equal("The Fortune Teahouse")


func test_renderer_is_compatibility() -> void:
	assert_str(ProjectSettings.get_setting("rendering/renderer/rendering_method")).is_equal("gl_compatibility")


func test_placeholder_scene_loads() -> void:
	var scene: PackedScene = load("res://scenes/placeholder.tscn")
	assert_object(scene).is_not_null()
	var root := scene.instantiate()
	assert_object(root).is_not_null()
	assert_str(root.get_node("Box/Title").text).is_equal("The Fortune Teahouse")
	root.free()
