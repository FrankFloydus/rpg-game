@tool
class_name FirstPersonCameraEffects
extends Camera3D
## Authors first-person roll, movement FOV, and render-only combat feedback.

@export_group("Aim")
## Maximum upward and downward view pitch in degrees.
@export_range(1.0, 89.9, 0.1, "suffix:°") var pitch_limit: float = 89.0

@export_group("Strafe Roll")
## Maximum camera roll in degrees at full lateral speed. Zero disables lateral tilt.
@export_range(0.0, 15.0, 0.1, "suffix:°") var maximum_tilt: float = 3.0:
	set(value):
		maximum_tilt = value
		notify_property_list_changed()
## Lateral speed in metres per second that produces the maximum camera roll.
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:m/s") var full_tilt_speed: float = 6.0
## Camera roll convergence rate per second. Larger values make the roll respond faster.
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:1/s") var tilt_response: float = 10.0

@export_group("Movement FOV", "movement_fov_")
## FOV change in degrees at full forward speed. Positive values widen the view as you move forward.
## Start with a small value to complement the swords' forward lean. Zero disables this direction.
@export_range(-5.0, 5.0, 0.1, "suffix:°") var movement_fov_forward_offset: float = 0.8
## FOV change in degrees at full backward speed. Negative values narrow the view as you back away.
## Bring it closer to zero if the view tightens too much. Zero disables this direction.
@export_range(-5.0, 5.0, 0.1, "suffix:°") var movement_fov_backward_offset: float = -0.6
## Blend time constant in seconds for a change in movement speed. Raise it if the view shifts too
## quickly when you tap a movement key or reverse direction.
@export_range(0.02, 0.5, 0.01, "suffix:s") var movement_fov_response_time: float = 0.12

@export_group("Combat Shake")
## Scales short, render-only impacts from attacks, received hits, and guards. Zero disables these kicks.
@export_range(0.0, 1.0, 0.05, "suffix:×") var combat_shake_intensity := 1.0

var _base_fov: float
var _movement_fov_offset := 0.0
var _eye_offset := Vector3.ZERO
var _rest_rotation := Vector3.ZERO
var _eye_anchor: Node3D
var _motion_body: Node3D
var _strafe_roll := 0.0
var _damage_roll := 0.0
var _shake_peak := Vector3.ZERO
var _shake_entry := Vector3.ZERO
var _shake_offset := Vector3.ZERO
var _shake_elapsed := 0.0
var _shake_duration := 0.0
var _shake_priority := 0


func _validate_property(property: Dictionary) -> void:
	if property.name == &"full_tilt_speed" and maximum_tilt == 0.0:
		property.usage &= ~PROPERTY_USAGE_EDITOR


func _ready() -> void:
	_base_fov = fov
	_eye_offset = position
	_rest_rotation = rotation
	if Engine.is_editor_hint():
		return
	_eye_anchor = get_parent_node_3d()
	_motion_body = _eye_anchor.get_parent_node_3d()
	top_level = true
	sync_view_pose(false)


## Uses the same eye position and locomotion roll as the view, with no damage or impact rotation.
func aim_transform() -> Transform3D:
	var aim_rotation := _rest_rotation + Vector3(0.0, 0.0, _strafe_roll)
	var aim_pose := Transform3D(Basis.from_euler(aim_rotation, rotation_order), _eye_offset)
	return _eye_anchor.global_transform * aim_pose


func kick_combat_view(degrees: Vector3, duration: float, priority: int) -> void:
	if combat_shake_intensity <= 0.0:
		return
	if _shake_elapsed < _shake_duration:
		if priority < _shake_priority or (priority == _shake_priority and _shake_elapsed < 0.075):
			return
	_shake_entry = _shake_offset
	_shake_peak = degrees * (PI / 180.0 * combat_shake_intensity)
	_shake_duration = duration
	_shake_elapsed = 0.0
	_shake_priority = priority


func clear_combat_shake() -> void:
	_shake_duration = 0.0
	_shake_elapsed = 0.0
	_shake_priority = 0
	_shake_peak = Vector3.ZERO
	_shake_offset = Vector3.ZERO
	sync_view_pose(not Engine.is_in_physics_frame())


func advance_view_roll(strafe: float, damage: float, delta: float) -> void:
	var blend := 1.0 - exp(-tilt_response * delta)
	_strafe_roll = lerp_angle(_strafe_roll, strafe, blend)
	_damage_roll = lerp_angle(_damage_roll, damage, blend)
	if _shake_elapsed < _shake_duration:
		# Measure the brief recoil in wall time so the card hand cannot stretch it.
		_shake_elapsed += delta / maxf(0.01, Engine.time_scale)
		var phase := clampf(_shake_elapsed / _shake_duration, 0.0, 1.0)
		var strike := smoothstep(0.0, 0.16, phase)
		var recoil := clampf((phase - 0.16) / 0.84, 0.0, 1.0)
		var settling := (1.0 - recoil) * (1.0 - recoil) * cos(recoil * TAU * 0.72)
		_shake_offset = _shake_entry * (1.0 - strike) + _shake_peak * strike * settling
	sync_view_pose(not Engine.is_in_physics_frame())


## Follows the character's smoothed translation, with the latest aim and recoil on every rendered frame.
## Physics callers and teleports use the current body position.
func sync_view_pose(interpolate_position: bool) -> void:
	var anchor := _eye_anchor.global_transform
	if interpolate_position:
		anchor.origin += _motion_body.get_global_transform_interpolated().origin - _motion_body.global_position
	var tilt := _rest_rotation + Vector3(0.0, 0.0, _strafe_roll + _damage_roll) + _shake_offset
	var target := anchor * Transform3D(Basis.from_euler(tilt, rotation_order), _eye_offset)
	if not global_transform.is_equal_approx(target):
		global_transform = target


## Updates the lens from signed forward speed as a fraction of the Mover's normal speed.
func advance_movement_fov(forward_fraction: float, delta: float) -> void:
	var fraction := clampf(forward_fraction, -1.0, 1.0)
	var target := maxf(fraction, 0.0) * movement_fov_forward_offset
	target += maxf(-fraction, 0.0) * movement_fov_backward_offset
	_movement_fov_offset = lerpf(
		_movement_fov_offset, target, 1.0 - exp(-delta / movement_fov_response_time)
	)
	_apply_fov()


func _apply_fov() -> void:
	var target := clampf(_base_fov + _movement_fov_offset, 1.0, 179.0)
	if not is_equal_approx(fov, target):
		fov = target
