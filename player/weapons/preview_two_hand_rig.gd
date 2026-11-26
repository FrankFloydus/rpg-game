@tool
class_name PreviewTwoHandRig
extends Node3D
## Turns the preview's chest under the held weapon and solves each arm to its grip.

const UPPER_ARM_LENGTH := 0.285
const BEND_LIMIT := deg_to_rad(82.0)
const REACH_MARGIN := 0.006
const SPINE_POSITION := Vector3(0.065, -0.565, 0.045)
const CHEST_OFFSET := Vector3(0.0, 0.155, 0.0)
const CLAVICLE_OFFSET := Vector3(0.084, 0.014, -0.032)
const SHOULDER_OFFSET := Vector3(0.126, -0.006, -0.086)
const LEFT_SLEEVE_WEIGHT_TRACK := ^"PreviewArmRig:left_sleeve_solve_weight"

## Optional animation channel that blends the left sleeve toward the authored elbow pose.
@export_range(0.0, 1.0, 0.01) var left_sleeve_solve_weight := 1.0

class Arm:
	var clavicle: int
	var upper: int
	var forearm: int
	var hand: int
	var elbow: int
	var elbow_parent: int
	var wrist: Marker3D
	var sleeve_anchor: Marker3D
	var collar: Vector3
	var neutral_shoulder: Vector3
	var pole: Vector3

var _skeleton: Skeleton3D
var _sleeves: Skeleton3D
var _grip: Node3D
var _arms: Array[Arm] = []
var _chest: int
@onready var _animation := get_node_or_null("../AnimationPlayer") as AnimationPlayer


func _ready() -> void:
	if Engine.is_editor_hint() and not get_meta(&"workbench_hit_shake_preview", false):
		return
	_grip = get_node_or_null("../Pose") as Node3D
	if _grip == null:
		return
	_sleeves = _grip.get_node_or_null("ForgedModel/Sleeve Armature/Skeleton3D") as Skeleton3D
	if _sleeves == null:
		return
	_skeleton = Skeleton3D.new()
	_skeleton.name = "UpperBody"
	add_child(_skeleton)
	var spine := _add_bone("Spine", -1, SPINE_POSITION)
	_chest = _add_bone("Chest", spine, CHEST_OFFSET)
	_add_arm("Right", 1.0, Vector3(0.68, -0.73, 0.36))
	_add_arm("Left", -1.0, Vector3(-0.58, -0.26, -0.53))


func _add_bone(label: String, parent: int, offset: Vector3) -> int:
	var bone := _skeleton.add_bone(label)
	_skeleton.set_bone_parent(bone, parent)
	var rest := Transform3D(Basis.IDENTITY, offset)
	_skeleton.set_bone_rest(bone, rest)
	_skeleton.set_bone_pose(bone, rest)
	return bone


func _add_arm(side: String, sign_x: float, pole: Vector3) -> void:
	var arm := Arm.new()
	arm.wrist = _grip.get_node_or_null(side + "Wrist") as Marker3D
	arm.sleeve_anchor = get_node_or_null("../" + side + "Shoulder") as Marker3D
	arm.elbow = _sleeves.find_bone(side + " Elbow")
	if arm.wrist == null or arm.elbow < 0:
		return
	arm.elbow_parent = _sleeves.get_bone_parent(arm.elbow)
	if arm.elbow_parent < 0:
		return
	var mirror := Vector3(sign_x, 1.0, 1.0)
	var collar_offset := CLAVICLE_OFFSET * mirror
	var upper_offset := SHOULDER_OFFSET * mirror
	arm.collar = SPINE_POSITION + CHEST_OFFSET + collar_offset
	arm.neutral_shoulder = arm.collar + upper_offset
	arm.pole = pole
	var sleeve_parent := _sleeve_parent_transform(arm)
	var hand_in_sleeve := sleeve_parent.affine_inverse() * arm.wrist.global_position
	var bind_span := _sleeves.get_bone_rest(arm.elbow).origin - hand_in_sleeve
	var forearm_length := (global_basis.inverse() * (sleeve_parent.basis * bind_span)).length()
	arm.clavicle = _add_bone(side + "Clavicle", _chest, collar_offset)
	arm.upper = _add_bone(side + "UpperArm", arm.clavicle, upper_offset)
	arm.forearm = _add_bone(side + "Forearm", arm.upper, Vector3.DOWN * UPPER_ARM_LENGTH)
	arm.hand = _add_bone(side + "Wrist", arm.forearm, Vector3.DOWN * forearm_length)
	_arms.append(arm)


func apply_to_grip(pose: Node3D, blend := 1.0) -> void:
	if pose != _grip or _arms.is_empty():
		return
	var turn := transform.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)
	var strength := maxf(turn / deg_to_rad(12.0), position.length() / 0.055)
	var influence := blend * smoothstep(0.0, 1.0, strength)
	var left_influence := influence * _sample_left_sleeve_weight()
	for arm in _arms:
		_apply_arm(arm, left_influence if arm.wrist.name == &"LeftWrist" else influence)


func _sample_left_sleeve_weight() -> float:
	if _animation == null or _animation.current_animation.is_empty():
		return 1.0
	var clip := _animation.get_animation(_animation.current_animation)
	var track := clip.find_track(LEFT_SLEEVE_WEIGHT_TRACK, Animation.TYPE_VALUE)
	# Manual clip seeks can leave the previous value on a property with no track.
	if track < 0 or not clip.track_is_enabled(track):
		return 1.0
	return clampf(left_sleeve_solve_weight, 0.0, 1.0)


func _sleeve_parent_transform(arm: Arm) -> Transform3D:
	return _sleeves.global_transform * _sleeves.get_bone_global_pose(arm.elbow_parent)


func _apply_arm(arm: Arm, influence: float) -> void:
	var wrist := to_local(arm.wrist.global_position)
	var sleeve_parent := _sleeve_parent_transform(arm)
	var inverse_sleeve_parent := sleeve_parent.affine_inverse()
	var wrist_in_sleeve := inverse_sleeve_parent * arm.wrist.global_position
	var rest := _sleeves.get_bone_rest(arm.elbow)
	var rest_span := rest.origin - wrist_in_sleeve
	var forearm_length := (global_basis.inverse() * (sleeve_parent.basis * rest_span)).length()
	if forearm_length <= REACH_MARGIN:
		return
	var to_wrist := wrist - arm.neutral_shoulder
	var reach := to_wrist.length()
	var axis := to_wrist / reach if reach > 0.00001 else Vector3.FORWARD
	var inner := absf(UPPER_ARM_LENGTH - forearm_length) + REACH_MARGIN
	var outer := UPPER_ARM_LENGTH + forearm_length - REACH_MARGIN
	reach = clampf(reach, inner, outer)
	# Let the shoulder follow overreaches so the target wrist can stay on the grip.
	var shoulder := wrist - axis * reach
	var along := (UPPER_ARM_LENGTH ** 2 + reach ** 2 - forearm_length ** 2) / (2.0 * reach)
	var radius := sqrt(maxf(0.0, UPPER_ARM_LENGTH ** 2 - along ** 2))
	var pole := arm.pole.slide(axis)
	if pole.length_squared() < 0.00001:
		pole = Vector3.DOWN.slide(axis)
	var elbow := shoulder + axis * along + pole.normalized() * radius
	var elbow_in_sleeve := inverse_sleeve_parent * to_global(elbow)
	var authored := _sleeves.get_bone_pose(arm.elbow)
	var rest_direction := rest_span.normalized()
	var solved_direction := (elbow_in_sleeve - wrist_in_sleeve).normalized()
	var bend := rest_direction.angle_to(solved_direction)
	if bend > BEND_LIMIT:
		solved_direction = rest_direction.slerp(solved_direction, BEND_LIMIT / bend)
	var solved_rotation := Quaternion(rest_direction, solved_direction) * rest.basis.get_rotation_quaternion()
	var authored_span := authored.origin - wrist_in_sleeve
	var direction := rest_direction if authored_span.is_zero_approx() else authored_span.normalized()
	direction = direction.slerp(solved_direction, influence)
	var length := lerpf(authored_span.length(), rest_span.length(), influence)
	var elbow_world := sleeve_parent * authored.origin
	if influence > 0.00001:
		var adjusted_elbow := wrist_in_sleeve + direction.normalized() * length
		var rotation := authored.basis.get_rotation_quaternion().slerp(solved_rotation, influence)
		_sleeves.set_bone_pose_position(arm.elbow, adjusted_elbow)
		_sleeves.set_bone_pose_rotation(arm.elbow, rotation)
		var solved_elbow_world := sleeve_parent * adjusted_elbow
		if arm.sleeve_anchor != null:
			arm.sleeve_anchor.global_position += solved_elbow_world - elbow_world
		elbow_world = solved_elbow_world
	var skin_elbow := to_local(elbow_world)
	# Move the shoulder to carry the bend limit without stretching the upper arm.
	shoulder = skin_elbow + (shoulder - skin_elbow).normalized() * UPPER_ARM_LENGTH
	_update_arm_bones(arm, shoulder, skin_elbow, wrist)


func _update_arm_bones(arm: Arm, shoulder: Vector3, elbow: Vector3, wrist: Vector3) -> void:
	var upper := Transform3D(_segment_frame(elbow - shoulder, arm.pole), shoulder)
	var forearm := Transform3D(_segment_frame(wrist - elbow, arm.pole), elbow)
	var hand := Transform3D((global_basis.inverse() * arm.wrist.global_basis).orthonormalized(), wrist)
	var collar := Transform3D(_segment_frame(shoulder - arm.collar, arm.pole), arm.collar)
	_skeleton.set_bone_pose(arm.clavicle, _skeleton.get_bone_global_rest(_chest).affine_inverse() * collar)
	_skeleton.set_bone_pose(arm.upper, collar.affine_inverse() * upper)
	_skeleton.set_bone_pose(arm.forearm, upper.affine_inverse() * forearm)
	_skeleton.set_bone_pose(arm.hand, forearm.affine_inverse() * hand)


func _segment_frame(segment: Vector3, pole: Vector3) -> Basis:
	var y := -segment.normalized()
	if y.is_zero_approx():
		return Basis.IDENTITY
	var x := y.cross(pole).normalized()
	if x.is_zero_approx():
		x = y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))
