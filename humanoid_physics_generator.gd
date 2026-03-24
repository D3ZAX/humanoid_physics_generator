@tool
extends Node

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

const SYMMETRIC_SETTING_KEY := "humanoid_physics_generator/use_symmetric_shapes"

const TORSO_BONES := [
	"Hips",
	"Spine",
	"Chest",
	"UpperChest"
]

static func generate_for_skeleton(skeleton: Skeleton3D, parent: Node3D) -> void:
	if skeleton == null:
		return

	_cleanup_previous(skeleton)

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

	for bone_name in HUMANOID_BONES:
		if _is_finger_or_toe_name(bone_name):
			continue
		if not humanoid_bone_indices.has(bone_name):
			continue
		var override_shape: Shape3D = null
		if use_symmetric and bone_name.begins_with("Right"):
			var left_name := _mirror_bone_name(bone_name)
			if shared_shapes.has(left_name):
				override_shape = shared_shapes[left_name]

		var shape_used := _create_physical_bone_and_collider(
			skeleton,
			parent,
			bone_name,
			humanoid_bone_indices[bone_name],
			bone_aabbs,
			override_shape
		)
		if use_symmetric and bone_name.begins_with("Left") and shape_used != null:
			shared_shapes[bone_name] = shape_used

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
		collider.transform = Transform3D(Basis(), center)
		return override_shape

	var radius := local_aabb.size.length() * 0.5
	var shape := SphereShape3D.new()
	shape.radius = max(radius, 0.01)
	
	collider.shape = shape
	collider.transform = Transform3D(Basis(), center)
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
		collider.transform = Transform3D(Basis(), center)
		return override_shape

	var radius: float = max(size.x, size.z) * 0.5
	var height: float = max(0.01, max(size.y, 2.0 * radius))
	
	var shape := CapsuleShape3D.new()
	shape.radius = max(radius, 0.01)
	shape.height = height

	collider.shape = shape
	collider.transform = Transform3D(Basis(), center)
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
		collider.transform = Transform3D(basis, center)
		return override_shape

	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height

	var basis := _basis_from_up_to_dir(axis_dir.normalized())
	collider.shape = shape
	collider.transform = Transform3D(basis, center)
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
