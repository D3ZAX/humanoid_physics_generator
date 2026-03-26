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

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_apply_ignore_collisions()

func _apply_ignore_collisions() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var bone_nodes := _get_physical_bones_by_name(parent)
	if bone_nodes.is_empty():
		return
	var pairs := _get_adjacent_pairs(parent)
	for pair in pairs:
		var a_name: String = str(pair[0])
		var b_name: String = str(pair[1])
		if not bone_nodes.has(a_name) or not bone_nodes.has(b_name):
			continue
		var a: PhysicalBone3D = bone_nodes[a_name] as PhysicalBone3D
		var b: PhysicalBone3D = bone_nodes[b_name] as PhysicalBone3D
		if a == null or b == null:
			continue
		a.add_collision_exception_with(b)
		b.add_collision_exception_with(a)

func _get_physical_bones_by_name(root: Node) -> Dictionary:
	var result: Dictionary = {}
	for child in root.get_children():
		if child is PhysicalBone3D:
			var pb: PhysicalBone3D = child
			var name := _get_physical_bone_name(pb)
			if name != "":
				result[name] = pb
	return result

func _get_physical_bone_name(pb: PhysicalBone3D) -> String:
	if pb.has_method("get_bone_name"):
		return str(pb.get_bone_name())
	if pb.has_method("get"):
		return str(pb.get("bone_name"))
	return ""

func _get_adjacent_pairs(root: Node) -> Array:
	var pairs: Array = []
	# Torso chain
	pairs.append(["Hips", "Spine"])
	pairs.append(["Spine", "Chest"])
	pairs.append(["Chest", "UpperChest"])
	pairs.append(["UpperChest", "Neck"])
	pairs.append(["Neck", "Head"])
	# Arms
	pairs.append(["LeftShoulder", "LeftUpperArm"])
	pairs.append(["LeftUpperArm", "LeftLowerArm"])
	pairs.append(["LeftLowerArm", "LeftHand"])
	pairs.append(["RightShoulder", "RightUpperArm"])
	pairs.append(["RightUpperArm", "RightLowerArm"])
	pairs.append(["RightLowerArm", "RightHand"])
	# Legs
	pairs.append(["LeftUpperLeg", "LeftLowerLeg"])
	pairs.append(["LeftLowerLeg", "LeftFoot"])
	pairs.append(["LeftFoot", "LeftToes"])
	pairs.append(["RightUpperLeg", "RightLowerLeg"])
	pairs.append(["RightLowerLeg", "RightFoot"])
	pairs.append(["RightFoot", "RightToes"])
	# Hips branching
	pairs.append(["Hips", "LeftUpperLeg"])
	pairs.append(["Hips", "RightUpperLeg"])
	# UpperChest branching
	pairs.append(["UpperChest", "LeftShoulder"])
	pairs.append(["UpperChest", "RightShoulder"])
	pairs.append(["UpperChest", "LeftUpperArm"])
	pairs.append(["UpperChest", "RightUpperArm"])

	return _filter_existing_pairs(pairs)

func _filter_existing_pairs(pairs: Array) -> Array:
	var filtered: Array = []
	for p in pairs:
		var a: String = str(p[0])
		var b: String = str(p[1])
		if _is_finger_or_toe_name(a) or _is_finger_or_toe_name(b):
			continue
		filtered.append(p)
	return filtered

func _is_finger_or_toe_name(name: String) -> bool:
	var lower := name.to_lower()
	for substr in FINGER_TOE_SUBSTRINGS:
		if lower.find(substr) != -1:
			return true
	return false
