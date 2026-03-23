# Humanoid Physics Generator (Godot 4)

A Godot 4 editor plugin that generates humanoid `PhysicalBone3D` nodes and collision shapes from the selected `Skeleton3D`.

## Features

- Generates physical bones for standard humanoid bones (excluding fingers and toes).
- Creates capsule colliders for most body parts, aligned to the next humanoid bone in the chain.
- Creates sphere colliders for hands and head.
- Creates capsule colliders for feet.
- Uses mesh skin weights to approximate collider sizes from vertex AABBs.
- Optional symmetric shape mode: right-side bones reuse left-side shapes.

## Installation

1. Copy the folder `addons/humanoid_physics_generator` into your Godot project.
2. Open the project in Godot.
3. Go to `Project > Project Settings > Plugins` and enable **Humanoid Physics Generator**.

## Usage

1. Select a `Skeleton3D` node in the current scene.
2. Run `Project > Tools > Generate Humanoid Physics`.

The plugin will add `PhysicalBone3D` children under the selected skeleton and create colliders according to the rules below.

## Collider Rules (Current Behavior)

- **Torso bones (Hips/Spine/Chest/UpperChest/Neck)**
  - Capsule axis is fixed to the model-space horizontal axis (X).
  - Hips center is computed from the average of Spine/LeftUpperLeg/RightUpperLeg bone centers.
  - Hips size is derived from the AABB between Hips and those bones (excluding the target bones).
- **Arms and legs**
  - Capsules follow the bone-to-next-bone direction.
  - Radius is estimated from vertex AABB influenced by the current bone.
- **Hands and head**
  - Sphere size fits the AABB of the bone plus first-level children.
- **Feet**
  - Capsule size fits the AABB of the bone plus first-level children.

## Project Setting

`humanoid_physics_generator/use_symmetric_shapes` (default: `true`)

- **On**: right-side bones reuse the left-side shape of the same limb (no size recalculation on the right side).
- **Off**: each bone computes its own collider size.

## Notes

- This plugin assumes a standard humanoid naming convention (e.g., `Hips`, `LeftUpperArm`, `RightLowerLeg`).
- If your skeleton uses different naming, adjust the bone lists in the script.

## License

MIT (or your preferred license).