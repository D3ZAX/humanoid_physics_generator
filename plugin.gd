@tool
extends EditorPlugin

const Generator := preload("res://addons/humanoid_physics_generator/humanoid_physics_generator.gd")

func _enter_tree() -> void:
	_ensure_project_setting()
	add_tool_menu_item("Generate Humanoid Physics", _on_generate_pressed)

func _exit_tree() -> void:
	remove_tool_menu_item("Generate Humanoid Physics")

func _ensure_project_setting() -> void:
	var key := "humanoid_physics_generator/use_symmetric_shapes"
	if not ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, true)
	ProjectSettings.add_property_info({
		"name": key,
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"usage": PROPERTY_USAGE_DEFAULT
	})

func _on_generate_pressed() -> void:
	var editor_selection := get_editor_interface().get_selection()
	var selected_nodes := editor_selection.get_selected_nodes()
	var skeleton: Skeleton3D = null
	for node in selected_nodes:
		if node is Skeleton3D:
			skeleton = node
			break
	if skeleton == null:
		push_warning("Select a Skeleton3D node in the current scene first.")
		return

	Generator.generate_for_skeleton(skeleton)
