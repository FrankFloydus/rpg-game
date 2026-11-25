extends Node
## Applies Crimson Carnage's weapon motion to the equipped first-person rig.

const SwaySettings := preload("res://player/weapon_sway/weapon_sway_settings.gd")
const BobStyle := preload("res://player/weapon_sway/weapon_bob_style.gd")
const Clearance := preload("res://player/weapon_sway/weapon_clearance.gd")
const Rig := preload("res://player/weapon_sway/crimson_weapon_rig.gd")


## Character whose resolved movement drives the first-person gait.
@export var body: CharacterBody3D
## Camera that defines the motion axes and the weapon clearance origin.
@export var camera: Camera3D
## Mouse lag, gait, breathing, jump and landing settings ported from Crimson Carnage.
@export var settings: SwaySettings

@export_group("Weapon Clearance")
## Physics layers that restrict the rendered weapon's clearance. Zero disables wall fitting.
@export_flags_3d_physics var clearance_mask: int = 1
## Extra spacing between held metal and a wall.
@export_range(0.0, 0.2, 0.001, "suffix:m") var clearance_padding := 0.025
## Seconds for the viewmodel to return to its authored size once the wall clears.
@export_range(0.0, 2.0, 0.001, "suffix:s") var clearance_recovery_time := 0.12
## Smallest eye-centered scale used to fit the held model in a restricted space.
@export_range(0.25, 1.0, 0.01) var clearance_minimum_scale := 0.35

var _rig: Rig
var _active_settings: SwaySettings
var _preview_style: BobStyle
var _was_grounded := false
var _sampled_floor := false
var _right_clearance: Clearance
var _left_clearance: Clearance
var _excluded: Array[RID] = []
var _fit_scale := 1.0
var _rendered_scale := 1.0


func _ready() -> void:
	_excluded.append(body.get_rid())
	reset()


func reset() -> void:
	_rig = Rig.new()
	_active_settings = settings
	_rig.configure(settings)
	_rig.preview_bob_style(_preview_style)
	_was_grounded = false
	_sampled_floor = false
	_fit_scale = 1.0


func add_look_turn(angles: Vector2) -> void:
	if _rig != null:
		_rig.add_look_turn(angles)


## Uses a temporary gait preset while retaining the resource's authored default.
func preview_bob_style(style: BobStyle) -> void:
	_preview_style = style
	if _rig != null:
		_rig.preview_bob_style(style)


func advance_after_movement(delta: float, steering: Vector2, incoming_vertical: float) -> void:
	if _rig == null:
		return
	if _active_settings != settings:
		_rig.configure(settings)
		_active_settings = settings
	var grounded := body.is_on_floor()
	if _sampled_floor:
		if _was_grounded and not grounded and incoming_vertical > 0.0:
			_rig.play_takeoff_motion()
		elif not _was_grounded and grounded:
			_rig.play_landing_motion(maxf(0.0, -incoming_vertical))
	_sampled_floor = true
	_was_grounded = grounded

	var actual := body.get_real_velocity()
	var travel := body.get_position_delta()
	if grounded:
		travel -= body.get_platform_velocity() * delta
	var ground_travel := Vector2(travel.x, travel.z)
	var braking := steering.is_zero_approx() and not ground_travel.is_zero_approx()
	_rig.advance(delta, Vector2(actual.x, actual.z), ground_travel, body.global_basis,
		grounded, false, braking, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, false)
	_update_clearance(delta)


func invalidate_equipment() -> void:
	_right_clearance = null
	_left_clearance = null
	_fit_scale = 1.0


func apply_sockets(main_socket: Node3D, offhand_socket: Node3D, main_pose: Node3D, offhand_pose: Node3D) -> void:
	if _rig == null:
		return
	if clearance_mask != 0:
		if is_instance_valid(main_pose) and _right_clearance == null:
			_right_clearance = Clearance.new(main_pose)
		if is_instance_valid(offhand_pose) and _left_clearance == null:
			_left_clearance = Clearance.new(offhand_pose)
	var view := get_parent() as Node3D
	var eye := view.to_local(camera.get_camera_transform().origin)
	var camera_to_view := (view.global_basis.inverse() * camera.global_basis).orthonormalized()
	_apply_hand(main_socket, main_pose, false, eye, camera_to_view)
	_apply_hand(offhand_socket, offhand_pose, true, eye, camera_to_view)
	_rendered_scale = _fit_scale


func _apply_hand(socket: Node3D, pose: Node3D, left: bool, eye: Vector3, camera_to_view: Basis) -> void:
	if not is_instance_valid(pose):
		return
	var offset: Transform3D = _rig.get_sway(left, false, 1.0)
	var wrist := pose.get_node_or_null(^"LeftWrist" if left else ^"RightWrist") as Node3D
	var view := get_parent() as Node3D
	var grip := view.to_local(wrist.global_position if wrist != null else pose.global_position)
	var rotation_offset := camera_to_view * offset.basis * camera_to_view.transposed()
	# Rotate the keyed pose around its grip before adding camera-relative travel.
	var follow := Transform3D(rotation_offset, grip - rotation_offset * grip + camera_to_view * offset.origin)
	var shifted := follow * socket.transform
	socket.transform = Transform3D(shifted.basis.scaled(Vector3.ONE * _fit_scale),
		eye.lerp(shifted.origin, _fit_scale))


func _update_clearance(delta: float) -> void:
	if clearance_mask == 0:
		_fit_scale = 1.0
		return
	var minimum := clearance_minimum_scale
	if _right_clearance != null:
		minimum = maxf(minimum, _right_clearance.minimum_scale(camera, clearance_padding, _rendered_scale))
	if _left_clearance != null:
		minimum = maxf(minimum, _left_clearance.minimum_scale(camera, clearance_padding, _rendered_scale))
	var limit := 1.0
	if _right_clearance != null:
		limit = minf(limit, _right_clearance.scale_limit(camera, clearance_mask, clearance_padding,
			minimum, _rendered_scale, _excluded))
	if _left_clearance != null:
		limit = minf(limit, _left_clearance.scale_limit(camera, clearance_mask, clearance_padding,
			minimum, _rendered_scale, _excluded))
	if limit > _fit_scale and clearance_recovery_time > 0.0:
		var recovery := (1.0 - clearance_minimum_scale) * delta / clearance_recovery_time
		limit = move_toward(_fit_scale, limit, recovery)
	_fit_scale = maxf(limit, minimum)
