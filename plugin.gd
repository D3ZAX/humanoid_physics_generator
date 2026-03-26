@tool
extends EditorPlugin

const Generator := preload("res://addons/humanoid_physics_generator/humanoid_physics_generator.gd")

func _enter_tree() -> void:
	_ensure_project_setting()
	_ensure_rotation_limit_settings()
	add_tool_menu_item("Generate Humanoid Physics", _on_generate_pressed)

func _exit_tree() -> void:
	remove_tool_menu_item("Generate Humanoid Physics")

func _ensure_project_setting() -> void:
	var key := "plugins/humanoid_physics_generator/use_symmetric_shapes"
	if not ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, true)
	ProjectSettings.add_property_info({
		"name": key,
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"usage": PROPERTY_USAGE_DEFAULT
	})
	ProjectSettings.set_as_basic(key, true)
	ProjectSettings.set_initial_value(key, true)

func _ensure_rotation_limit_settings() -> void:
	var sym_key := Generator.ROT_LIMITS_SYMMETRY_KEY
	_ensure_setting(sym_key, 1, TYPE_INT, PROPERTY_HINT_ENUM, "None,RightFromLeft,LeftFromRight")
	ProjectSettings.set_as_basic(sym_key, true)
	ProjectSettings.set_initial_value(sym_key, 1)

	var damp_key := Generator.APPLY_DAMPING_SETTING_KEY
	_ensure_setting(damp_key, true, TYPE_BOOL)
	ProjectSettings.set_as_basic(damp_key, true)
	ProjectSettings.set_initial_value(damp_key, true)
	
	var defaults: Dictionary = Generator.get_default_rotation_limits()
	for bone_name in defaults.keys():
		var d: Dictionary = defaults[bone_name]
		_ensure_setting("%s/%s/enabled" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["enabled"], TYPE_BOOL)
		_ensure_setting("%s/%s/x_lower" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["x_lower"], TYPE_FLOAT)
		_ensure_setting("%s/%s/x_upper" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["x_upper"], TYPE_FLOAT)
		_ensure_setting("%s/%s/y_lower" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["y_lower"], TYPE_FLOAT)
		_ensure_setting("%s/%s/y_upper" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["y_upper"], TYPE_FLOAT)
		_ensure_setting("%s/%s/z_lower" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["z_lower"], TYPE_FLOAT)
		_ensure_setting("%s/%s/z_upper" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["z_upper"], TYPE_FLOAT)
		_ensure_setting("%s/%s/x_softness" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["x_softness"], TYPE_FLOAT)
		_ensure_setting("%s/%s/y_softness" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["y_softness"], TYPE_FLOAT)
		_ensure_setting("%s/%s/z_softness" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["z_softness"], TYPE_FLOAT)
		_ensure_setting("%s/%s/linear_damp" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["linear_damp"], TYPE_FLOAT)
		_ensure_setting("%s/%s/angular_damp" % [Generator.ROT_LIMITS_PREFIX, bone_name], d["angular_damp"], TYPE_FLOAT)

func _ensure_setting(path: String, value, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	if not ProjectSettings.has_setting(path):
		ProjectSettings.set_setting(path, value)
	ProjectSettings.add_property_info({
		"name": path,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
		"usage": PROPERTY_USAGE_DEFAULT
	})
	ProjectSettings.set_initial_value(path, value)

func _on_generate_pressed() -> void:
	var editor_selection := get_editor_interface().get_selection()
	var selected_nodes := editor_selection.get_selected_nodes()
	var skeleton: Skeleton3D = null
	var parent: Node3D = null
	for node in selected_nodes:
		if node is Skeleton3D:
			parent = node
			skeleton = node
			break
		elif node is PhysicalBoneSimulator3D:
			parent = node
			var ske = node.get_parent()
			if ske is Skeleton3D:
				skeleton = ske
			else:
				push_warning("PhysicalBoneSimulator3D node must be a child of Skeleton3D node.")
				return
			break
	if skeleton == null:
		push_warning("Select a Skeleton3D node or PhysicalBoneSimulator3D node in the current scene first.")
		return

	Generator.generate_for_skeleton(skeleton, parent)
