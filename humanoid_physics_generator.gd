@tool
extends Node

const IGNORE_SCRIPT_PATH := "res://addons/humanoid_physics_generator/humanoid_physics_ignore_adjacent.gd"

const HUMANOID_BONES := [
	"Hips",
	"Spine",
	"Chest",
	"UpperChest",
	"Neck",
	"Head",
	"LeftShoulder",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightShoulder",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"LeftToes",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
	"RightToes"
]

const FINGER_TOE_SUBSTRINGS := [
	"finger",
	"thumb",
	"index",
	"middle",
	"ring",
	"little",
	"pinky",
	"toe"
]

const HAND_HEAD_BONES := [
	"LeftHand",
	"RightHand",
	"Head"
]

const FOOT_BONES := [
	"LeftFoot",
	"RightFoot"
]

const SHOULDER_BONES := [
	"LeftShoulder",
	"RightShoulder"
]

const SYMMETRIC_SETTING_KEY := "plugins/humanoid_physics_generator/use_symmetric_shapes"
const ROT_LIMITS_PREFIX := "plugins/humanoid_physics_generator/rot_limits"
const ROT_LIMITS_SYMMETRY_KEY := "plugins/humanoid_physics_generator/rot_limits_symmetry"

const TORSO_BONES := [
	"Hips",
	"Spine",
	"Chest",
	"UpperChest"
]

static func generate_for_skeleton(skeleton: Skeleton3D, parent: Node3D) -> void:
	if skeleton == null:
		return

	var humanoid_bone_indices: Dictionary = {}
	for bone_name in HUMANOID_BONES:
		if _is_finger_or_toe_name(bone_name):
			continue
		var idx := skeleton.find_bone(bone_name)
		if idx != -1:
			humanoid_bone_indices[bone_name] = idx

	if humanoid_bone_indices.is_empty():
		push_warning("No humanoid bones found on selected skeleton.")
		return

	var mesh_instances := _find_mesh_instances_using_skeleton(skeleton)
	var bone_aabbs := _build_bone_aabbs_in_skeleton_space(skeleton, mesh_instances)
	var use_symmetric := _is_symmetric_shapes_enabled()
	var shared_shapes: Dictionary = {}
	var existing_pbs := _get_existing_physical_bones_by_name(parent)

	for bone_name in HUMANOID_BONES:
		if _is_finger_or_toe_name(bone_name):
			continue
		if not humanoid_bone_indices.has(bone_name):
			continue
		if existing_pbs.has(bone_name):
			_apply_6dof_constraints(existing_pbs[bone_name], bone_name, skeleton, humanoid_bone_indices[bone_name])
			continue
		var override_shape: Shape3D = null
		if use_symmetric and bone_name.begins_with("Right"):
			var left_name := _mirror_bone_name(bone_name)
			if shared_shapes.has(left_name):
				override_shape = shared_shapes[left_name]
			elif existing_pbs.has(left_name):
				override_shape = _get_physical_bone_shape(existing_pbs[left_name])

		var shape_used := _create_physical_bone_and_collider(
			skeleton,
			parent,
			bone_name,
			humanoid_bone_indices[bone_name],
			bone_aabbs,
			override_shape
		)
		var created_pb := _get_physical_bone_by_name(parent, bone_name)
		if created_pb != null:
			_apply_6dof_constraints(created_pb, bone_name, skeleton, humanoid_bone_indices[bone_name])
		if use_symmetric and bone_name.begins_with("Left") and shape_used != null:
			shared_shapes[bone_name] = shape_used

	_ensure_ignore_adjacent_node(parent)

static func _cleanup_previous(skeleton: Skeleton3D) -> void:
	for child in skeleton.get_children():
		if child is PhysicalBone3D and child.has_meta("humanoid_physics_generator"):
			child.queue_free()

static func _is_finger_or_toe_name(name: String) -> bool:
	var lower := name.to_lower()
	for substr in FINGER_TOE_SUBSTRINGS:
		if lower.find(substr) != -1:
			return true
	return false

static func _is_symmetric_shapes_enabled() -> bool:
	if ProjectSettings.has_setting(SYMMETRIC_SETTING_KEY):
		return bool(ProjectSettings.get_setting(SYMMETRIC_SETTING_KEY))
	return true

static func _mirror_bone_name(bone_name: String) -> String:
	if bone_name.begins_with("Right"):
		return bone_name.replace("Right", "Left")
	if bone_name.begins_with("Left"):
		return bone_name.replace("Left", "Right")
	return bone_name

static func _get_existing_physical_bones_by_name(parent: Node) -> Dictionary:
	var result: Dictionary = {}
	for child in parent.get_children():
		if child is PhysicalBone3D:
			var pb: PhysicalBone3D = child
			var bone_name := _get_physical_bone_name(pb)
			if bone_name != "":
				result[bone_name] = pb
	return result

static func _get_physical_bone_by_name(parent: Node, bone_name: String) -> PhysicalBone3D:
	for child in parent.get_children():
		if child is PhysicalBone3D:
			var pb: PhysicalBone3D = child
			if _get_physical_bone_name(pb) == bone_name:
				return pb
	return null

static func _get_physical_bone_name(pb: PhysicalBone3D) -> String:
	if pb.has_method("get_bone_name"):
		return str(pb.get_bone_name())
	if pb.has_method("get"):
		return str(pb.get("bone_name"))
	return ""

static func _get_physical_bone_shape(pb: PhysicalBone3D) -> Shape3D:
	for child in pb.get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child
			return cs.shape
	return null

static func _ensure_ignore_adjacent_node(parent: Node3D) -> void:
	var script := load(IGNORE_SCRIPT_PATH)
	if script == null:
		return
	for child in parent.get_children():
		if child.get_script() == script:
			return
	var node := Node.new()
	node.name = "HumanoidPhysicsIgnoreAdjacent"
	node.set_script(script)
	parent.add_child(node)
	node.owner = parent.owner

static func _apply_6dof_constraints(pb: PhysicalBone3D, bone_name: String, skeleton: Skeleton3D, bone_idx: int) -> void:
	if pb == null:
		return
	_set_joint_type_6dof(pb)
	#_set_joint_frame_to_bone_axis(pb, skeleton, bone_name, bone_idx)
	_set_joint_linear_limits_locked(pb)
	var limits := _get_axis_limits_from_settings(bone_name)
	_set_joint_angular_limits_axis_deg(
		pb,
		float(limits["x_lower"]),
		float(limits["x_upper"]),
		float(limits["y_lower"]),
		float(limits["y_upper"]),
		float(limits["z_lower"]),
		float(limits["z_upper"]),
		bool(limits["enabled"])
	)
	_set_joint_limit_softness(pb, "x", float(limits["x_softness"]))
	_set_joint_limit_softness(pb, "y", float(limits["y_softness"]))
	_set_joint_limit_softness(pb, "z", float(limits["z_softness"]))
	_set_joint_damping(pb, float(limits["linear_damp"]), float(limits["angular_damp"]))

static func _set_joint_type_6dof(pb: PhysicalBone3D) -> void:
	if pb.has_method("set_joint_type"):
		pb.set_joint_type(PhysicalBone3D.JOINT_TYPE_6DOF)
	else:
		_set_if_exists(pb, "joint_type", PhysicalBone3D.JOINT_TYPE_6DOF)

static func _set_joint_linear_limits_locked(pb: PhysicalBone3D) -> void:
	_set_if_exists(pb, "joint_constraints/x/linear_limit_lower", 0.0)
	_set_if_exists(pb, "joint_constraints/x/linear_limit_upper", 0.0)
	_set_if_exists(pb, "joint_constraints/y/linear_limit_lower", 0.0)
	_set_if_exists(pb, "joint_constraints/y/linear_limit_upper", 0.0)
	_set_if_exists(pb, "joint_constraints/z/linear_limit_lower", 0.0)
	_set_if_exists(pb, "joint_constraints/z/linear_limit_upper", 0.0)
		
	_set_if_exists(pb, "joint_constraints/x/linear_limit_enabled", true)
	_set_if_exists(pb, "joint_constraints/y/linear_limit_enabled", true)
	_set_if_exists(pb, "joint_constraints/z/linear_limit_enabled", true)

static func _set_joint_angular_limits_axis_deg(
	pb: PhysicalBone3D,
	x_lower_deg: float,
	x_upper_deg: float,
	y_lower_deg: float,
	y_upper_deg: float,
	z_lower_deg: float,
	z_upper_deg: float,
	enabled: bool
) -> void:
	if not enabled:
		_set_joint_limit_axis(pb, "x", 0.0, 0.0, false)
		_set_joint_limit_axis(pb, "y", 0.0, 0.0, false)
		_set_joint_limit_axis(pb, "z", 0.0, 0.0, false)
		return

	_set_joint_limit_axis(pb, "x", x_lower_deg, x_upper_deg, true)
	_set_joint_limit_axis(pb, "y", y_lower_deg, y_upper_deg, true)
	_set_joint_limit_axis(pb, "z", z_lower_deg, z_upper_deg, true)

static func _set_joint_damping(pb: PhysicalBone3D, linear_damp: float, angular_damp: float) -> void:
	_set_if_exists(pb, "joint_constraints/x/linear_damping", linear_damp)
	_set_if_exists(pb, "joint_constraints/x/angular_damping", angular_damp)
	_set_if_exists(pb, "joint_constraints/y/linear_damping", linear_damp)
	_set_if_exists(pb, "joint_constraints/y/angular_damping", angular_damp)
	_set_if_exists(pb, "joint_constraints/z/linear_damping", linear_damp)
	_set_if_exists(pb, "joint_constraints/z/angular_damping", angular_damp)

static func _set_joint_limit_softness(pb: PhysicalBone3D, axis: String, softness: float) -> void:
	var base := "joint_constraints/%s" % axis
	_set_if_exists(pb, "%s/angular_limit_softness" % base, softness)

static func _set_joint_limit_axis(pb: PhysicalBone3D, axis: String, lower: float, upper: float, enabled: bool) -> void:
	var base := "joint_constraints/%s" % axis
	_set_if_exists(pb, "%s/angular_limit_enabled" % base, enabled)
	_set_if_exists(pb, "%s/angular_limit_lower" % base, lower)
	_set_if_exists(pb, "%s/angular_limit_upper" % base, upper)

static func _get_axis_limits_from_settings(bone_name: String) -> Dictionary:
	var defaults := get_default_rotation_limits()
	var use_name := bone_name
	var mirror := false
	var sym := _get_rot_limits_symmetry_mode()
	if sym == 1 and bone_name.begins_with("Right"):
		use_name = _mirror_bone_name(bone_name)
		mirror = true
	elif sym == 2 and bone_name.begins_with("Left"):
		use_name = _mirror_bone_name(bone_name)
		mirror = true

	var d: Dictionary = defaults.get(use_name, defaults.get(bone_name, {}))

	var enabled: bool = bool(_get_setting_or_default("%s/%s/enabled" % [ROT_LIMITS_PREFIX, use_name], d["enabled"]))
	var x_lower: float = float(_get_setting_or_default("%s/%s/x_lower" % [ROT_LIMITS_PREFIX, use_name], d["x_lower"]))
	var x_upper: float = float(_get_setting_or_default("%s/%s/x_upper" % [ROT_LIMITS_PREFIX, use_name], d["x_upper"]))
	var y_lower: float = float(_get_setting_or_default("%s/%s/y_lower" % [ROT_LIMITS_PREFIX, use_name], d["y_lower"]))
	var y_upper: float = float(_get_setting_or_default("%s/%s/y_upper" % [ROT_LIMITS_PREFIX, use_name], d["y_upper"]))
	var z_lower: float = float(_get_setting_or_default("%s/%s/z_lower" % [ROT_LIMITS_PREFIX, use_name], d["z_lower"]))
	var z_upper: float = float(_get_setting_or_default("%s/%s/z_upper" % [ROT_LIMITS_PREFIX, use_name], d["z_upper"]))
	var x_softness: float = float(_get_setting_or_default("%s/%s/x_softness" % [ROT_LIMITS_PREFIX, use_name], d["x_softness"]))
	var y_softness: float = float(_get_setting_or_default("%s/%s/y_softness" % [ROT_LIMITS_PREFIX, use_name], d["y_softness"]))
	var z_softness: float = float(_get_setting_or_default("%s/%s/z_softness" % [ROT_LIMITS_PREFIX, use_name], d["z_softness"]))
	var linear_damp: float = float(_get_setting_or_default("%s/%s/linear_damp" % [ROT_LIMITS_PREFIX, use_name], d["linear_damp"]))
	var angular_damp: float = float(_get_setting_or_default("%s/%s/angular_damp" % [ROT_LIMITS_PREFIX, use_name], d["angular_damp"]))

	if mirror:
		var m := _mirror_limits(x_lower, x_upper, y_lower, y_upper, z_lower, z_upper)
		x_lower = m["x_lower"]
		x_upper = m["x_upper"]
		y_lower = m["y_lower"]
		y_upper = m["y_upper"]
		z_lower = m["z_lower"]
		z_upper = m["z_upper"]

	return {
		"enabled": enabled,
		"x_lower": x_lower,
		"x_upper": x_upper,
		"y_lower": y_lower,
		"y_upper": y_upper,
		"z_lower": z_lower,
		"z_upper": z_upper,
		"x_softness": x_softness,
		"y_softness": y_softness,
		"z_softness": z_softness,
		"linear_damp": linear_damp,
		"angular_damp": angular_damp
	}

static func _mirror_limits(x_lower: float, x_upper: float, y_lower: float, y_upper: float, z_lower: float, z_upper: float) -> Dictionary:
	return {
		"x_lower": x_lower,
		"x_upper": x_upper,
		"y_lower": -y_upper,
		"y_upper": -y_lower,
		"z_lower": -z_upper,
		"z_upper": -z_lower
	}

static func _get_rot_limits_symmetry_mode() -> int:
	if ProjectSettings.has_setting(ROT_LIMITS_SYMMETRY_KEY):
		return int(ProjectSettings.get_setting(ROT_LIMITS_SYMMETRY_KEY))
	return 0

static func _get_setting_or_default(key: String, default_value):
	if ProjectSettings.has_setting(key):
		return ProjectSettings.get_setting(key)
	return default_value

static func get_default_rotation_limits() -> Dictionary:
	var base: Dictionary = {
		"Hips": {
			"x_lower": -180.0, "x_upper": 180.0,
			"y_lower": -180.0, "y_upper": 180.0,
			"z_lower": -180.0, "z_upper": 180.0,
			"x_softness": 0.5, "y_softness": 0.5, "z_softness": 0.5,
			"linear_damp": 0.01, "angular_damp": 0.0, "enabled": false
		},
		"Spine": {
			"x_lower": -60.0, "x_upper": 15.0,
			"y_lower": -15.0, "y_upper": 15.0,
			"z_lower": -15.0, "z_upper": 15.0,
			"x_softness": 0.5, "y_softness": 0.5, "z_softness": 0.5,
			"linear_damp": 0.1, "angular_damp": 0.2, "enabled": true
		},
		"Chest": {
			"x_lower": -30.0, "x_upper": 15.0,
			"y_lower": -15.0, "y_upper": 15.0,
			"z_lower": -15.0, "z_upper": 15.0,
			"x_softness": 0.5, "y_softness": 0.5, "z_softness": 0.5,
			"linear_damp": 0.1, "angular_damp": 0.2, "enabled": true
		},
		"UpperChest": {
			"x_lower": -30.0, "x_upper": 15.0,
			"y_lower": -15.0, "y_upper": 15.0,
			"z_lower": -15.0, "z_upper": 15.0,
			"x_softness": 0.5, "y_softness": 0.5, "z_softness": 0.5,
			"linear_damp": 0.1, "angular_damp": 0.2, "enabled": true
		},
		"Neck": {
			"x_lower": -20.0, "x_upper": 20.0,
			"y_lower": -30.0, "y_upper": 30.0,
			"z_lower": -30.0, "z_upper": 30.0,
			"x_softness": 0.8, "y_softness": 0.8, "z_softness": 0.8,
			"linear_damp": 0.1, "angular_damp": 0.5, "enabled": true
		},
		"Head": {
			"x_lower": -20.0, "x_upper": 20.0,
			"y_lower": -30.0, "y_upper": 30.0,
			"z_lower": -30.0, "z_upper": 30.0,
			"x_softness": 0.8, "y_softness": 0.8, "z_softness": 0.8,
			"linear_damp": 0.1, "angular_damp": 0.5, "enabled": true
		},
		"Shoulder": {
			"x_lower": -45.0, "x_upper": 45.0,
			"y_lower": -80.0, "y_upper": 80.0,
			"z_lower": -45.0, "z_upper": 45.0,
			"x_softness": 0.8, "y_softness": 0.8, "z_softness": 0.8,
			"linear_damp": 0.1, "angular_damp": 0.1, "enabled": true
		},
		"UpperArm": {
			"x_lower": -45.0, "x_upper": 45.0,
			"y_lower": -80.0, "y_upper": 80.0,
			"z_lower": -45.0, "z_upper": 45.0,
			"x_softness": 0.8, "y_softness": 0.8, "z_softness": 0.8,
			"linear_damp": 0.1, "angular_damp": 0.1, "enabled": true
		},
		"LowerArm": {
			"x_lower": -120.0, "x_upper": 10.0,
			"y_lower": -45.0, "y_upper": 45.0,
			"z_lower": 0.0, "z_upper": 0.0,
			"x_softness": 0.9, "y_softness": 0.9, "z_softness": 0.9,
			"linear_damp": 0.1, "angular_damp": 0.1, "enabled": true
		},
		"Hand": {
			"x_lower": -15.0, "x_upper": 15.0,
			"y_lower": -20.0, "y_upper": 20.0,
			"z_lower": -20.0, "z_upper": 20.0,
			"x_softness": 0.8, "y_softness": 0.8, "z_softness": 0.8,
			"linear_damp": 0.0, "angular_damp": 0.0, "enabled": true
		},
		"UpperLeg": {
			"x_lower": -20.0, "x_upper": 90.0,
			"y_lower": -20.0, "y_upper": 20.0,
			"z_lower": -20.0, "z_upper": 20.0,
			"x_softness": 0.8, "y_softness": 0.8, "z_softness": 0.8,
			"linear_damp": 0.1, "angular_damp": 0.1, "enabled": true
		},
		"LowerLeg": {
			"x_lower": -120.0, "x_upper": 10.0,
			"y_lower": 0.0, "y_upper": 0.0,
			"z_lower": 0.0, "z_upper": 0.0,
			"x_softness": 0.9, "y_softness": 0.9, "z_softness": 0.9,
			"linear_damp": 0.1, "angular_damp": 0.1, "enabled": true
		},
		"Foot": {
			"x_lower": -30.0, "x_upper": 30.0,
			"y_lower": -15.0, "y_upper": 15.0,
			"z_lower": -15.0, "z_upper": 15.0,
			"x_softness": 0.8, "y_softness": 0.8, "z_softness": 0.8,
			"linear_damp": 0.0, "angular_damp": 0.0, "enabled": true
		},
		"Toes": {
			"x_lower": 0.0, "x_upper": 0.0,
			"y_lower": -20.0, "y_upper": 20.0,
			"z_lower": 0.0, "z_upper": 0.0,
			"x_softness": 0.8, "y_softness": 0.8, "z_softness": 0.8,
			"linear_damp": 0.0, "angular_damp": 0.0, "enabled": true
		}
	}

	var result: Dictionary = {}
	for bone_name in HUMANOID_BONES:
		var base_name: String = bone_name
		if base_name.begins_with("Left"):
			base_name = base_name.substr(4)
		elif base_name.begins_with("Right"):
			base_name = base_name.substr(5)
		if base.has(base_name):
			result[bone_name] = base[base_name]
		else:
			result[bone_name] = base["Spine"]
	return result

static func _set_body_offset(pb: PhysicalBone3D, offset: Transform3D) -> void:
	if pb.has_method("set_body_offset"):
		pb.set_body_offset(offset)
	else:
		_set_if_exists(pb, "body_offset", offset)

static func _set_joint_frame_to_bone_axis(pb: PhysicalBone3D, skeleton: Skeleton3D, bone_name: String, bone_idx: int) -> void:
	var dir_local := _get_reference_dir_local(skeleton, bone_name, bone_idx)
	if dir_local.length() <= 0.0001:
		return
	var basis := _basis_from_x_dir(dir_local.normalized())
	var offset := Transform3D(basis, Vector3.ZERO)
	_set_if_exists(pb, "body_offset", offset)

static func _get_reference_dir_local(skeleton: Skeleton3D, bone_name: String, bone_idx: int) -> Vector3:
	var next_idx := _get_next_chain_bone_index(skeleton, bone_name)
	var bone_pose := skeleton.get_bone_global_pose(bone_idx)
	if next_idx != -1:
		var next_pose := skeleton.get_bone_global_pose(next_idx)
		var dir := next_pose.origin - bone_pose.origin
		return bone_pose.affine_inverse().basis * dir
	if skeleton.has_method("get_bone_children"):
		var children: PackedInt32Array = skeleton.get_bone_children(bone_idx)
		if children.size() > 0:
			var child_pose := skeleton.get_bone_global_pose(children[0])
			var dir2 := child_pose.origin - bone_pose.origin
			return bone_pose.affine_inverse().basis * dir2
	return Vector3.RIGHT

static func _basis_from_x_dir(x_dir: Vector3) -> Basis:
	var x := x_dir.normalized()
	var up := Vector3.UP
	if abs(x.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var y := (up - x * up.dot(x)).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

static func _get_ue_limits_for_bone(bone_name: String) -> Dictionary:
	var base := bone_name
	if base.begins_with("Left"):
		base = base.substr(4)
	elif base.begins_with("Right"):
		base = base.substr(5)

	var twist_deg := 20.0
	var swing1_deg := 20.0
	var swing2_deg := 20.0
	var enabled := true
	var linear_damp := 0.1
	var angular_damp := 0.1
	var one_sided := false
	var one_sided_deg := 0.0
	match base:
		"Hips":
			enabled = false
			linear_damp = 0.01
			angular_damp = 0.0
			twist_deg = 180.0
			swing1_deg = 180.0
			swing2_deg = 180.0
		"Spine", "Chest", "UpperChest":
			twist_deg = 15.0
			swing1_deg = 15.0
			swing2_deg = 15.0
			linear_damp = 0.1
			angular_damp = 0.2
		"Neck", "Head":
			twist_deg = 20.0
			swing1_deg = 30.0
			swing2_deg = 30.0
			linear_damp = 0.1
			angular_damp = 0.5
		"Shoulder":
			twist_deg = 45.0
			swing1_deg = 45.0
			swing2_deg = 80.0
			linear_damp = 0.5
			angular_damp = 0.5
		"UpperArm":
			twist_deg = 45.0
			swing1_deg = 70.0
			swing2_deg = 70.0
			linear_damp = 0.1
			angular_damp = 0.1
		"LowerArm":
			twist_deg = 10.0
			swing1_deg = 120.0
			swing2_deg = 0.0
			linear_damp = 0.1
			angular_damp = 0.1
		"Hand":
			twist_deg = 15.0
			swing1_deg = 20.0
			swing2_deg = 20.0
			linear_damp = 0.0
			angular_damp = 0.0
		"UpperLeg":
			twist_deg = 20.0
			swing1_deg = 65.0
			swing2_deg = 65.0
			linear_damp = 0.1
			angular_damp = 0.1
		"LowerLeg":
			twist_deg = 10.0
			swing1_deg = 0.0
			swing2_deg = 0.0
			linear_damp = 0.1
			angular_damp = 0.1
		"Foot":
			twist_deg = 10.0
			swing1_deg = 15.0
			swing2_deg = 15.0
			linear_damp = 0.0
			angular_damp = 0.0
		"Toes", "Toe", "Ball":
			twist_deg = 0.0
			swing1_deg = 20.0
			swing2_deg = 0.0
			linear_damp = 0.0
			angular_damp = 0.0

	# Optional one-sided hinge for knees/elbows (Swing1 only)
	if base == "LowerLeg" or base == "LowerArm":
		if swing1_deg > 0.0 and swing2_deg == 0.0:
			one_sided = true
			one_sided_deg = swing1_deg
	if base == "LowerArm":
		one_sided = false
		one_sided_deg = 0.0

	return {
		"twist_deg": twist_deg,
		"swing1_deg": swing1_deg,
		"swing2_deg": swing2_deg,
		"enabled": enabled,
		"linear_damp": linear_damp,
		"angular_damp": angular_damp,
		"one_sided": one_sided,
		"one_sided_deg": one_sided_deg
	}

static func _has_property(obj: Object, property_name: String) -> bool:
	for p in obj.get_property_list():
		if p.name == property_name:
			return true
	return false

static func _set_if_exists(obj: Object, property_name: String, value) -> void:
	if _has_property(obj, property_name):
		obj.set(property_name, value)

static func _find_mesh_instances_using_skeleton(skeleton: Skeleton3D) -> Array:
	var result: Array = []
	var root := skeleton
	if root == null:
		return result
	var nodes := root.get_children()
	var stack: Array = nodes.duplicate()
	while stack.size() > 0:
		var node := stack.pop_back()
		if node is MeshInstance3D:
			var mesh_instance: MeshInstance3D = node
			if mesh_instance.skeleton != NodePath():
				var skel_node := mesh_instance.get_node_or_null(mesh_instance.skeleton)
				if skel_node == skeleton:
					result.append(mesh_instance)
		for child in node.get_children():
			stack.append(child)
	return result

static func _build_bone_aabbs_in_skeleton_space(skeleton: Skeleton3D, mesh_instances: Array) -> Dictionary:
	var bone_aabbs: Dictionary = {}
	var skel_global: Transform3D = skeleton.global_transform
	var skel_global_inv: Transform3D = skel_global.affine_inverse()

	for mesh_instance in mesh_instances:
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		var mesh_global: Transform3D = mesh_instance.global_transform
		var mesh_to_skel: Transform3D = skel_global_inv * mesh_global
		var skin: Skin = mesh_instance.skin
		var bone_map := _build_mesh_bone_index_map(skeleton, skin)

		for surface_i in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface_i)
			if arrays.is_empty():
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty() or weights.is_empty():
				continue
			var vertex_count := vertices.size()
			for v in range(vertex_count):
				var vpos: Vector3 = mesh_to_skel * vertices[v]
				var base := v * 4
				for j in range(4):
					var w := weights[base + j]
					if w <= 0.0001:
						continue
					var mesh_bone_idx := bones[base + j]
					var skel_bone_idx := _map_mesh_bone_to_skeleton(bone_map, mesh_bone_idx)
					if skel_bone_idx == -1:
						continue
					_add_point_to_bone_aabb(bone_aabbs, skel_bone_idx, vpos)
	return bone_aabbs

static func _build_mesh_bone_index_map(skeleton: Skeleton3D, skin: Skin) -> Dictionary:
	var map: Dictionary = {}
	if skin == null:
		return map
	var bind_count := skin.get_bind_count()
	for i in range(bind_count):
		var name := ""
		if skin.has_method("get_bind_name"):
			name = skin.get_bind_name(i)
		elif skin.has_method("get_bind_bone_name"):
			name = skin.get_bind_bone_name(i)
		var skel_idx := skeleton.find_bone(name)
		if skel_idx != -1:
			map[i] = skel_idx
	return map

static func _map_mesh_bone_to_skeleton(map: Dictionary, mesh_bone_idx: int) -> int:
	if map.has(mesh_bone_idx):
		return map[mesh_bone_idx]
	return mesh_bone_idx

static func _add_point_to_bone_aabb(bone_aabbs: Dictionary, bone_idx: int, point: Vector3) -> void:
	if not bone_aabbs.has(bone_idx):
		bone_aabbs[bone_idx] = AABB(point, Vector3.ZERO)
		return
	var aabb: AABB = bone_aabbs[bone_idx]
	bone_aabbs[bone_idx] = aabb.expand(point)

static func _create_physical_bone_and_collider(skeleton: Skeleton3D, parent: Node3D, bone_name: String, bone_idx: int, bone_aabbs: Dictionary, override_shape: Shape3D) -> Shape3D:
	var pb := PhysicalBone3D.new()
	pb.name = "PB_%s" % bone_name
	pb.set_meta("humanoid_physics_generator", true)
	if pb.has_method("set_bone_name"):
		pb.set_bone_name(bone_name)
	else:
		pb.set("bone_name", bone_name)
	pb.transform = skeleton.get_bone_global_pose(bone_idx)
	
	parent.add_child(pb)
	pb.owner = parent.owner

	var collider := CollisionShape3D.new()
	pb.add_child(collider)
	collider.owner = skeleton.owner

	if HAND_HEAD_BONES.has(bone_name):
		return _create_sphere_collider_for_bone(pb, skeleton, bone_idx, bone_aabbs, true, override_shape)
	if FOOT_BONES.has(bone_name):
		return _create_foot_capsule(pb, skeleton, bone_idx, bone_aabbs, override_shape)
	if SHOULDER_BONES.has(bone_name):
		return null

	return _create_chain_capsule(pb, skeleton, bone_name, bone_idx, bone_aabbs, override_shape)

static func _create_sphere_collider_for_bone(pb: PhysicalBone3D, skeleton: Skeleton3D, bone_idx: int, bone_aabbs: Dictionary, include_children: bool, override_shape: Shape3D) -> Shape3D:
	var aabb := _get_combined_aabb_for_bone_and_children(skeleton, bone_idx, bone_aabbs, include_children)
	var local_aabb := _to_bone_local_aabb(skeleton, bone_idx, aabb)
	if local_aabb.size.length() <= 0.0001:
		local_aabb = AABB(Vector3(-0.05, -0.05, -0.05), Vector3(0.1, 0.1, 0.1))
	var center := local_aabb.position + local_aabb.size * 0.5
	var collider := pb.get_child(0)
	if override_shape != null:
		collider.shape = override_shape
		_set_body_offset(pb, Transform3D(Basis(), center))
		collider.transform = Transform3D.IDENTITY
		return override_shape

	var radius := local_aabb.size.length() * 0.5
	var shape := SphereShape3D.new()
	shape.radius = max(radius, 0.01)
	
	collider.shape = shape
	_set_body_offset(pb, Transform3D(Basis(), center))
	collider.transform = Transform3D.IDENTITY
	return shape

static func _create_foot_capsule(pb: PhysicalBone3D, skeleton: Skeleton3D, bone_idx: int, bone_aabbs: Dictionary, override_shape: Shape3D) -> Shape3D:
	var aabb := _get_combined_aabb_for_bone_and_children(skeleton, bone_idx, bone_aabbs, true)
	var local_aabb := _to_bone_local_aabb(skeleton, bone_idx, aabb)
	if local_aabb.size.length() <= 0.0001:
		local_aabb = AABB(Vector3(-0.05, -0.05, -0.05), Vector3(0.1, 0.1, 0.1))
	var size := local_aabb.size
	var center := local_aabb.position + size * 0.5
	var collider := pb.get_child(0)
	if override_shape != null:
		collider.shape = override_shape
		_set_body_offset(pb, Transform3D(Basis(), center))
		collider.transform = Transform3D.IDENTITY
		return override_shape

	var radius: float = max(size.x, size.z) * 0.5
	var height: float = max(0.01, max(size.y, 2.0 * radius))
	
	var shape := CapsuleShape3D.new()
	shape.radius = max(radius, 0.01)
	shape.height = height

	collider.shape = shape
	_set_body_offset(pb, Transform3D(Basis(), center))
	collider.transform = Transform3D.IDENTITY
	return shape

static func _create_chain_capsule(pb: PhysicalBone3D, skeleton: Skeleton3D, bone_name: String, bone_idx: int, bone_aabbs: Dictionary, override_shape: Shape3D) -> Shape3D:
	var next_bone_idx := _get_next_chain_bone_index(skeleton, bone_name)
	if next_bone_idx == -1:
		return null
	var bone_pose := skeleton.get_bone_global_pose(bone_idx)
	var next_pose := skeleton.get_bone_global_pose(next_bone_idx)
	var dir := next_pose.origin - bone_pose.origin
	var length := dir.length()
	if length <= 0.0001:
		return null
	var dir_local := bone_pose.affine_inverse().basis * dir

	var axis_dir := dir_local.normalized()
	var radius: float = 0.0
	var height: float = 0.0
	var center := dir_local.normalized() * (length * 0.5)

	if TORSO_BONES.has(bone_name):
		var local_aabb := AABB(Vector3.ZERO, Vector3.ZERO)
		var has_local_aabb := false

		if bone_name == "Hips":
			var target_names := ["Spine", "LeftUpperLeg", "RightUpperLeg"]
			var targets: Array = []
			for target_name in target_names:
				var t_idx := skeleton.find_bone(target_name)
				if t_idx != -1:
					targets.append(t_idx)
			if targets.size() > 0:
				var sum := Vector3.ZERO
				for t_idx in targets:
					var t_pose := skeleton.get_bone_global_pose(t_idx)
					var t_local := bone_pose.affine_inverse() * t_pose.origin
					sum += t_local
				center = sum / float(targets.size())

				var merged := _get_combined_aabb_for_bone_paths_excluding_end(skeleton, bone_idx, targets, bone_aabbs)
				local_aabb = _to_bone_local_aabb(skeleton, bone_idx, merged)
				has_local_aabb = true
		else:
			var path_aabb := _get_combined_aabb_for_bone_path(skeleton, bone_idx, next_bone_idx, bone_aabbs)
			local_aabb = _to_bone_local_aabb(skeleton, bone_idx, path_aabb)
			has_local_aabb = true

		axis_dir = Vector3.RIGHT

		if override_shape == null:
			if has_local_aabb:
				radius = max(0.01, length * 0.5)
				height = max(0.01, max(_aabb_length_along_axis(local_aabb, axis_dir), 2.0 * radius))
			else:
				radius = max(0.01, length * 0.5)
				height = max(0.01, 2.0 * radius)
	else:
		if override_shape == null:
			var aabb := _get_combined_aabb_for_bone_and_children(skeleton, bone_idx, bone_aabbs, false)
			var local_aabb := _to_bone_local_aabb(skeleton, bone_idx, aabb)
			radius = _radius_from_aabb_and_axis(local_aabb, axis_dir)
			if radius <= 0.0001:
				radius = max(0.02, length * 0.1)
			height = max(0.01, max(length, 2.0 * radius))

	var collider := pb.get_child(0)
	if override_shape != null:
		collider.shape = override_shape
		var basis := _basis_from_up_to_dir(axis_dir.normalized())
		_set_body_offset(pb, Transform3D(Basis(), center))
		collider.transform = Transform3D(basis, Vector3.ZERO)
		return override_shape

	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height

	var basis := _basis_from_up_to_dir(axis_dir.normalized())
	collider.shape = shape
	_set_body_offset(pb, Transform3D(Basis(), center))
	collider.transform = Transform3D(basis, Vector3.ZERO)
	return shape

static func _get_next_chain_bone_index(skeleton: Skeleton3D, bone_name: String) -> int:
	var candidates: Array = []
	match bone_name:
		"Hips":
			candidates = ["Spine"]
		"Spine":
			candidates = ["Chest", "UpperChest", "Neck"]
		"Chest":
			candidates = ["UpperChest", "Neck"]
		"UpperChest":
			candidates = ["Neck"]
		"Neck":
			candidates = ["Head"]
		"LeftUpperArm":
			candidates = ["LeftLowerArm"]
		"LeftLowerArm":
			candidates = ["LeftHand"]
		"RightUpperArm":
			candidates = ["RightLowerArm"]
		"RightLowerArm":
			candidates = ["RightHand"]
		"LeftUpperLeg":
			candidates = ["LeftLowerLeg"]
		"LeftLowerLeg":
			candidates = ["LeftFoot"]
		"RightUpperLeg":
			candidates = ["RightLowerLeg"]
		"RightLowerLeg":
			candidates = ["RightFoot"]
		_:
			candidates = []
	for name in candidates:
		var idx := skeleton.find_bone(name)
		if idx != -1:
			return idx
	return -1

static func _get_combined_aabb_for_bone_and_children(skeleton: Skeleton3D, bone_idx: int, bone_aabbs: Dictionary, include_children: bool) -> AABB:
	var has_aabb := false
	var combined := AABB()
	if bone_aabbs.has(bone_idx):
		combined = bone_aabbs[bone_idx]
		has_aabb = true
	if include_children:
		var children := PackedInt32Array()
		if skeleton.has_method("get_bone_children"):
			children = skeleton.get_bone_children(bone_idx)
		for child_idx in children:
			if bone_aabbs.has(child_idx):
				if not has_aabb:
					combined = bone_aabbs[child_idx]
					has_aabb = true
				else:
					combined = combined.merge(bone_aabbs[child_idx])
	if not has_aabb:
		combined = AABB(Vector3.ZERO, Vector3.ZERO)
	return combined

static func _get_combined_aabb_for_bone_path(skeleton: Skeleton3D, start_idx: int, end_idx: int, bone_aabbs: Dictionary) -> AABB:
	var has_aabb := false
	var combined := AABB()
	var current := end_idx
	while current != -1 and current != start_idx:
		if bone_aabbs.has(current):
			if not has_aabb:
				combined = bone_aabbs[current]
				has_aabb = true
			else:
				combined = combined.merge(bone_aabbs[current])
		current = skeleton.get_bone_parent(current)
	if not has_aabb:
		combined = AABB(Vector3.ZERO, Vector3.ZERO)
	return combined

static func _get_combined_aabb_for_bone_paths(skeleton: Skeleton3D, start_idx: int, end_indices: Array, bone_aabbs: Dictionary) -> AABB:
	var has_aabb := false
	var combined := AABB()
	for end_idx in end_indices:
		var path_aabb := _get_combined_aabb_for_bone_path(skeleton, start_idx, end_idx, bone_aabbs)
		if path_aabb.size.length() <= 0.0001:
			continue
		if not has_aabb:
			combined = path_aabb
			has_aabb = true
		else:
			combined = combined.merge(path_aabb)
	if not has_aabb:
		combined = AABB(Vector3.ZERO, Vector3.ZERO)
	return combined

static func _get_combined_aabb_for_bone_path_excluding_end(skeleton: Skeleton3D, start_idx: int, end_idx: int, bone_aabbs: Dictionary) -> AABB:
	var has_aabb := false
	var combined := AABB()
	var current := skeleton.get_bone_parent(end_idx)
	while current != -1 and current != start_idx:
		if bone_aabbs.has(current):
			if not has_aabb:
				combined = bone_aabbs[current]
				has_aabb = true
			else:
				combined = combined.merge(bone_aabbs[current])
		current = skeleton.get_bone_parent(current)
	if not has_aabb:
		combined = AABB(Vector3.ZERO, Vector3.ZERO)
	return combined

static func _get_combined_aabb_for_bone_paths_excluding_end(skeleton: Skeleton3D, start_idx: int, end_indices: Array, bone_aabbs: Dictionary) -> AABB:
	var has_aabb := false
	var combined: AABB
	if bone_aabbs.has(start_idx):
		has_aabb = true
		combined = bone_aabbs[start_idx]
	else:
		combined = AABB()
	for end_idx in end_indices:
		var path_aabb := _get_combined_aabb_for_bone_path_excluding_end(skeleton, start_idx, end_idx, bone_aabbs)
		if path_aabb.size.length() <= 0.0001:
			continue
		if not has_aabb:
			combined = path_aabb
			has_aabb = true
		else:
			combined = combined.merge(path_aabb)
	if not has_aabb:
		combined = AABB(Vector3.ZERO, Vector3.ZERO)
	return combined

static func _to_bone_local_aabb(skeleton: Skeleton3D, bone_idx: int, aabb: AABB) -> AABB:
	if aabb.size.length() <= 0.0001:
		return aabb
	var bone_pose := skeleton.get_bone_global_pose(bone_idx)
	var inv := bone_pose.affine_inverse()
	var corners := _get_aabb_corners(aabb)
	var local_aabb := AABB(inv * corners[0], Vector3.ZERO)
	for i in range(1, corners.size()):
		local_aabb = local_aabb.expand(inv * corners[i])
	return local_aabb

static func _get_aabb_corners(aabb: AABB) -> Array:
	var p := aabb.position
	var s := aabb.size
	return [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, s.y, s.z),
		p + s
	]

static func _get_aabb_primary_axis(local_aabb: AABB) -> Vector3:
	var size := local_aabb.size
	if size.x >= size.y and size.x >= size.z:
		return Vector3.RIGHT
	if size.y >= size.z:
		return Vector3.UP
	return Vector3.BACK

static func _aabb_length_along_axis(local_aabb: AABB, axis_dir: Vector3) -> float:
	if local_aabb.size.length() <= 0.0001:
		return 0.0
	var axis := axis_dir.normalized()
	var corners := _get_aabb_corners(local_aabb)
	var min_proj := axis.dot(corners[0])
	var max_proj := min_proj
	for i in range(1, corners.size()):
		var proj := axis.dot(corners[i])
		if proj < min_proj:
			min_proj = proj
		if proj > max_proj:
			max_proj = proj
	return max_proj - min_proj

static func _radius_from_aabb_and_axis(local_aabb: AABB, axis_dir: Vector3) -> float:
	if local_aabb.size.length() <= 0.0001:
		return 0.0
	var axis := axis_dir.normalized()
	var basis := _basis_from_dir_to_up(axis)
	var max_r := 0.0
	var corners := _get_aabb_corners(local_aabb)
	for c in corners:
		var v: Vector3 = basis * c
		var r := Vector2(v.x, v.z).length()
		if r > max_r:
			max_r = r
	return max_r

static func _basis_from_up_to_dir(dir: Vector3) -> Basis:
	var up := Vector3.UP
	var axis := up.cross(dir)
	var dot := up.dot(dir)
	if axis.length() <= 0.0001:
		if dot >= 0:
			return Basis()
		return Basis(Vector3.RIGHT, PI)
	axis = axis.normalized()
	var angle := acos(clamp(dot, -1.0, 1.0))
	return Basis(axis, angle)

static func _basis_from_dir_to_up(dir: Vector3) -> Basis:
	var up := Vector3.UP
	var axis := dir.cross(up)
	var dot := dir.dot(up)
	if axis.length() <= 0.0001:
		if dot >= 0:
			return Basis()
		return Basis(Vector3.RIGHT, PI)
	axis = axis.normalized()
	var angle := acos(clamp(dot, -1.0, 1.0))
	return Basis(axis, angle)
