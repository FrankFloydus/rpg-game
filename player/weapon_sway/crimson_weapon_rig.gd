# Weapon motion ported from Crimson Carnage's CrimsonWeaponRig (Francesco Di Blasi).
extends RefCounted

const Settings := preload("res://player/weapon_sway/weapon_sway_settings.gd")
const BobStyle := preload("res://player/weapon_sway/weapon_bob_style.gd")
const AirMotion := preload("res://player/weapon_sway/weapon_air_motion.gd")

const IDLE_SPEED := 0.25
const AIR_BLEND_TIME := 0.08
const STYLE_BLEND_TIME := 0.10

class Spring:
	var value := Vector2.ZERO
	var velocity := Vector2.ZERO

	func follow(target: Vector2, delta: float, response: float) -> void:
		var omega := 2.0 / maxf(response, 0.001)
		var error := value - target
		var combined := velocity + error * omega
		var decay := exp(-omega * delta)
		value = target + (error + combined * delta) * decay
		velocity = (velocity - combined * (omega * delta)) * decay


class Gait:
	const TRAVEL_SPEED := 0.34
	const RESTART_TIME := 0.14
	const PIVOT_ALIGNMENT := 0.60
	const POSE_RESPONSE := 18.0

	var position := Vector3.ZERO
	var rotation := Vector3.ZERO
	var hand_depth := 0.0
	var active_style: BobStyle

	var _heading := Vector2.ZERO
	var _last_direction := Vector2.ZERO
	var _time_still := INF
	var _stopping := false
	var _motion: WeaponGaitMotion
	var _elapsed := 0.0
	var _motion_heading := Vector2.ZERO
	var _pivot_side := 0.0
	var _loaded_side := 0.0

	func advance(delta: float, velocity: Vector2, grounded: bool, braking: bool,
			to_body: Basis, style: BobStyle, loaded: float) -> void:
		if grounded:
			_track_ground(delta, velocity, braking, style, loaded)
		else:
			_heading = Vector2.ZERO
			_last_direction = Vector2.ZERO
			_time_still = INF
			_stopping = false
			_motion = null

		var target_position := Vector3.ZERO
		var target_rotation := Vector3.ZERO
		var target_depth := 0.0
		if _motion != null and _elapsed < _motion.duration:
			if _motion.envelope != null:
				var amplitude := _motion.envelope.sample(_elapsed / _motion.duration)
				if _pivot_side != 0.0:
					target_position = _motion.position * Vector3(_pivot_side, 1.0, 1.0)
					target_rotation = _motion.rotation_degrees * Vector3(1.0, _pivot_side, _pivot_side)
					target_depth = _motion.pivot_hand_depth * _pivot_side * amplitude
				else:
					var direction := to_body * Vector3(_motion_heading.x, 0.0, _motion_heading.y)
					var frame := Basis.looking_at(direction)
					target_position = frame * _motion.position
					target_position.x += _motion.stop_weight_shift * _loaded_side
					target_rotation = frame * _motion.rotation_degrees
				target_position *= amplitude
				target_rotation *= amplitude
			_elapsed += delta
		else:
			_motion = null
		var weight := 1.0 - exp(-POSE_RESPONSE * delta)
		position = position.lerp(target_position, weight)
		rotation = rotation.lerp(target_rotation, weight)
		hand_depth = lerpf(hand_depth, target_depth, weight)

	func _track_ground(delta: float, velocity: Vector2, braking: bool, style: BobStyle, loaded: float) -> void:
		var moving := velocity.length_squared() >= TRAVEL_SPEED * TRAVEL_SPEED
		if braking or not moving:
			if not _stopping and _time_still == 0.0 and style != null:
				_play(style, style.stop_motion, _last_direction, 0.0, loaded)
			_stopping = true
			if not moving:
				_time_still += delta
			return
		_stopping = false
		var direction := velocity.normalized()
		var alignment := _heading.dot(direction)
		if _time_still >= RESTART_TIME:
			_heading = direction
			if style != null:
				_play(style, style.start_motion, direction)
		elif alignment < PIVOT_ALIGNMENT:
			if style != null:
				if alignment < -0.95:
					_play(style, style.stop_motion, _last_direction, 0.0, loaded)
				else:
					_play(style, style.pivot_motion, direction, signf(_heading.cross(direction)))
			_heading = direction
		_last_direction = direction
		_time_still = 0.0

	func _play(style: BobStyle, motion: WeaponGaitMotion, direction: Vector2, side := 0.0, loaded := 0.0) -> void:
		if motion == null or motion.envelope == null:
			return
		active_style = style
		_motion = motion
		_elapsed = 0.0
		_motion_heading = direction
		_pivot_side = side
		_loaded_side = loaded


var _settings: Settings
var _pending_look := Vector2.ZERO
var _look_target := Vector2.ZERO
var _look_sway := Spring.new()
var _long_look_yaw := Spring.new()
var _turn_in_place_weight := 0.0
var _previous_velocity := Vector2.ZERO
var _movement_lag := Spring.new()
var _movement_lean := Spring.new()
var _movement_position := Vector3.ZERO
var _movement_rotation := Vector3.ZERO
var _directional_carry := Spring.new()
var _carry_axes := Vector2.ZERO
var _bob_motion := Spring.new()
var _bob_phase := 0.0
var _bob_position := Vector3.ZERO
var _bob_rotation := Vector3.ZERO
var _bob_hand_position := Vector3.ZERO
var _bob_hand_pitch := 0.0
var _style_override: BobStyle
var _styles: Dictionary = {}
var _style_carry_position := Vector3.ZERO
var _style_carry_rotation := Vector3.ZERO
var _gait := Gait.new()
var _gait_weight := 0.0
var _breath_phase := 0.0
var _breath_weight := 0.0
var _breath_position := Vector3.ZERO
var _breath_pitch := 0.0
var _air_motion: AirMotion
var _air_elapsed := 0.0
var _air_strength := 0.0
var _hold_jump_pose := false
var _air_previous_position := Vector3.ZERO
var _air_previous_rotation := Vector3.ZERO
var _air_position := Vector3.ZERO
var _air_rotation := Vector3.ZERO


func configure(settings: Settings) -> void:
	_settings = settings


func add_look_turn(angles: Vector2) -> void:
	_pending_look += angles


func preview_bob_style(style: BobStyle) -> void:
	_style_override = style


func play_takeoff_motion() -> void:
	if _settings != null:
		_play_air(_settings.takeoff_motion, 1.0, true)


func play_landing_motion(impact_speed: float) -> void:
	if _settings != null and impact_speed > _settings.landing_min_speed:
		var low := _settings.landing_min_speed
		_play_air(_settings.landing_motion, smoothstep(low, maxf(low + 0.01, _settings.landing_full_speed),
			impact_speed), false)


func advance(delta: float, world_velocity: Vector2, ground_travel: Vector2, body_basis: Basis,
		grounded: bool, dashed: bool, braking: bool, captured: bool, attacking: bool) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var acceleration := (world_velocity - _previous_velocity) / delta
	_previous_velocity = world_velocity
	var turn := _pending_look
	_pending_look = Vector2.ZERO
	if _settings == null:
		_look_target = Vector2.ZERO
		_look_sway = Spring.new()
		_long_look_yaw = Spring.new()
		_turn_in_place_weight = 0.0
		_movement_lag = Spring.new()
		_movement_lean = Spring.new()
		_directional_carry = Spring.new()
		_carry_axes = Vector2.ZERO
		_bob_motion = Spring.new()
		_styles.clear()
		_gait = Gait.new()
		_breath_weight = 0.0
		_clear_air()
		return
	var stepping := grounded and not dashed
	_advance_look(delta, turn, stepping and world_velocity.length_squared() < IDLE_SPEED * IDLE_SPEED, captured)
	_advance_movement(delta, world_velocity, acceleration, ground_travel if stepping else Vector2.ZERO,
		body_basis, stepping, stepping and braking, attacking)
	_advance_air(delta, grounded)


func get_sway(left: bool, short_sword: bool, weight: float) -> Transform3D:
	if _settings == null:
		return Transform3D.IDENTITY
	var yaw := _look_sway.value.x if short_sword else _long_look_yaw.value.x
	var blend := Vector2(yaw, _look_sway.value.y) * weight
	var mirror := -1.0 if left else 1.0
	var inward := blend.x * mirror < 0.0
	var upward := blend.y > 0.0
	var side_position := _settings.inward_position if inward else _settings.outward_position
	var side_rotation := _settings.inward_rotation if inward else _settings.outward_rotation
	var vertical_position := _settings.up_position if upward else _settings.down_position
	var vertical_rotation := _settings.up_rotation if upward else _settings.down_rotation
	var position := side_position * absf(blend.x) + vertical_position * absf(blend.y)
	var rotation := side_rotation * absf(blend.x) + vertical_rotation * absf(blend.y)
	var position_mirror := Vector3(mirror, 1.0, 1.0)
	var rotation_mirror := Vector3(1.0, mirror, mirror)
	position *= position_mirror
	rotation *= rotation_mirror
	position += (_movement_position + _bob_position + _bob_hand_position * mirror) * weight
	rotation += (_movement_rotation + _bob_rotation) * weight
	rotation.x += (_bob_hand_pitch * mirror + _breath_pitch) * weight
	position += (_style_carry_position + _air_position + _breath_position) * position_mirror * weight
	rotation += (_style_carry_rotation + _air_rotation) * rotation_mirror * weight

	var back := _carry_axes.y > 0.0
	var leading := _carry_axes.x * mirror > 0.0
	var fore_position := _settings.directional_carry_backward_position if back else _settings.directional_carry_forward_position
	var fore_rotation := _settings.directional_carry_backward_rotation if back else _settings.directional_carry_forward_rotation
	var strafe_position := _settings.directional_carry_leading_position if leading else _settings.directional_carry_trailing_position
	var strafe_rotation := _settings.directional_carry_leading_rotation if leading else _settings.directional_carry_trailing_rotation
	var axes := _carry_axes.abs() * weight
	position += (fore_position * axes.y + strafe_position * axes.x) * position_mirror
	rotation += (fore_rotation * axes.y + strafe_rotation * axes.x) * rotation_mirror
	var transition_weight := _gait_weight * weight
	position += _gait.position * transition_weight
	position.z += _gait.hand_depth * mirror * transition_weight
	rotation += _gait.rotation * transition_weight
	return Transform3D(Basis.from_euler(rotation * (PI / 180.0)), position)


func _advance_look(delta: float, turn: Vector2, standing: bool, captured: bool) -> void:
	var response := _settings.look_response_time
	var extra := _settings.turn_in_place_extra_response
	_look_target *= exp(-_settings.recenter_rate * delta)
	var fast_turn := 0.0
	if captured:
		var angles := Vector2(turn.y, -turn.x) * (180.0 / PI)
		_look_target = (_look_target + angles * _settings.turn_gain).limit_length()
		if standing:
			var full_rate := _settings.turn_in_place_full_yaw_rate
			fast_turn = smoothstep(full_rate * 0.5, full_rate, absf(angles.x) / delta)
	var release := exp(-delta / maxf(response + extra, 0.001))
	_turn_in_place_weight = maxf(fast_turn, _turn_in_place_weight * release)
	_look_sway.follow(_look_target, delta, response)
	_long_look_yaw.follow(Vector2(_look_target.x, 0.0), delta, response + extra * _turn_in_place_weight)


func _advance_movement(delta: float, velocity: Vector2, acceleration: Vector2,
		ground_travel: Vector2, body_basis: Basis, grounded: bool, braking: bool, attacking: bool) -> void:
	var style := _style_override if _style_override != null else _settings.bob_style
	_advance_styles(delta, style)
	var response_scale := 1.0
	for entry: BobStyle in _styles:
		if entry != null:
			response_scale += (entry.movement_response_scale - 1.0) * float(_styles[entry])
	var response := _settings.movement_response_time
	var full_acceleration := maxf(_settings.movement_full_acceleration, 1.0)
	var full_speed := maxf(_settings.movement_full_speed, 0.1)
	if velocity.dot(acceleration) <= 0.0:
		var near_stop := 1.0 - smoothstep(0.0, full_speed * 0.5, velocity.length())
		response = lerpf(response, _settings.movement_settle_time, near_stop)
	response *= response_scale
	_movement_lag.follow((-acceleration / full_acceleration).limit_length(), delta, response)
	_movement_lean.follow((velocity / full_speed).limit_length(), delta, response)
	var to_body := body_basis.orthonormalized().transposed()
	var lag := to_body * Vector3(_movement_lag.value.x, 0.0, _movement_lag.value.y)
	var lean := to_body * Vector3(_movement_lean.value.x, 0.0, _movement_lean.value.y)
	_movement_position = Vector3(lag.x * _settings.movement_lateral_travel, 0.0, lag.z * _settings.movement_depth_travel)
	_movement_rotation = Vector3(lean.z * _settings.movement_forward_lean, 0.0, -lean.x * _settings.movement_lateral_lean)
	var ground_velocity := ground_travel / delta
	var speed := ground_velocity.length()
	_advance_carry(ground_velocity, to_body, response, delta)
	var loaded_side := sin(_bob_phase)
	_advance_bob(delta, minf(speed / full_speed, 1.0), response, Vector2(lean.x, lean.z), ground_travel.length())
	_advance_breath(delta, speed, grounded, attacking)
	_gait.advance(delta, ground_velocity, grounded, braking, to_body, style, loaded_side)
	_gait_weight = float(_styles.get(_gait.active_style, 0.0))


func _advance_carry(velocity: Vector2, to_body: Basis, response: float, delta: float) -> void:
	var full_speed := maxf(_settings.directional_carry_full_speed, 0.1)
	_directional_carry.follow((velocity / full_speed).limit_length(), delta, response)
	var travel := _directional_carry.value
	var local := to_body * Vector3(travel.x, 0.0, travel.y)
	var direction := Vector2(local.x, local.z)
	var length_squared := direction.length_squared()
	var strength := smoothstep(0.0, 1.0, sqrt(length_squared))
	_carry_axes = direction * direction.abs() * (strength / maxf(length_squared, 0.0001))


func _advance_breath(delta: float, speed: float, grounded: bool, attacking: bool) -> void:
	var curve := _settings.breath_curve
	if curve == null:
		_breath_weight = 0.0
		_breath_position = Vector3.ZERO
		_breath_pitch = 0.0
		return
	var target := 1.0 - smoothstep(0.0, IDLE_SPEED, speed) if grounded and not attacking else 0.0
	var fade_time := _settings.breath_fade_in if target > _breath_weight else _settings.breath_fade_out
	_breath_weight = move_toward(_breath_weight, target, delta / maxf(fade_time, 0.001))
	var blend := smoothstep(0.0, 1.0, _breath_weight)
	var period := maxf(_settings.breath_period, 0.001)
	_breath_phase = fposmod(_breath_phase + delta / period, 1.0)
	var wrist := fposmod(_breath_phase - _settings.breath_wrist_delay / period, 1.0)
	_breath_position = _settings.breath_position * (curve.sample(_breath_phase) * blend)
	_breath_pitch = _settings.breath_pitch * curve.sample(wrist) * blend


func _advance_styles(delta: float, selected: BobStyle) -> void:
	if _styles.size() == 1 and _styles.has(selected):
		return
	var decay := exp(-delta / STYLE_BLEND_TIME)
	var remaining := 0.0
	for style: BobStyle in _styles.keys():
		if style == selected:
			continue
		var weight := float(_styles[style]) * decay
		if weight < 0.0005:
			_styles.erase(style)
		else:
			_styles[style] = weight
			remaining += weight
	_styles[selected] = 1.0 - remaining


func _advance_bob(delta: float, strength: float, response: float, travel: Vector2, distance: float) -> void:
	var cadence_scale := 1.0
	var travel_scale := Vector3.ONE
	var rotation_scale := Vector2.ONE
	var wrist_delay := BobStyle.DEFAULT_WRIST_DELAY
	var plant_travel := 0.0
	var shoulder_yaw := 0.0
	_style_carry_position = Vector3.ZERO
	_style_carry_rotation = Vector3.ZERO
	for style: BobStyle in _styles:
		if style == null:
			continue
		var weight := float(_styles[style])
		cadence_scale += (style.cadence_scale - 1.0) * weight
		travel_scale += (style.travel_scale - Vector3.ONE) * weight
		rotation_scale += (style.rotation_scale - Vector2.ONE) * weight
		wrist_delay += (style.wrist_delay - BobStyle.DEFAULT_WRIST_DELAY) * weight
		plant_travel += style.plant_travel * weight
		shoulder_yaw += style.shoulder_yaw * weight
		_style_carry_position += style.carry_position * weight
		_style_carry_rotation += style.carry_rotation_degrees * weight
	_bob_motion.follow(Vector2(strength, 0.0), delta, response)
	var run_weight := smoothstep(1.0 / 3.0, 1.0, strength)
	var step_length := lerpf(_settings.bob_walk_step_length, _settings.bob_run_step_length, run_weight)
	_bob_phase = fposmod(_bob_phase + PI * distance * cadence_scale / maxf(step_length, 0.001), TAU)

	var amplitude := _bob_motion.value.x
	var direction := travel / maxf(maxf(travel.length(), amplitude), 0.0001)
	var support_shift := sin(_bob_phase)
	var weight_shift := support_shift * lerpf(0.5, 0.68, absf(direction.x)) + 0.32 * direction.x
	var arm_swing := cos(_bob_phase)
	var wrist_phase := wrist_delay * TAU
	var wrist_follow := cos(_bob_phase - wrist_phase)
	var height := _step_height(fposmod(_bob_phase / PI, 1.0), amplitude)
	var plant := direction * minf(height, 0.0) * plant_travel
	var lateral := _settings.bob_lateral_travel * travel_scale.x
	var vertical := _settings.bob_vertical_travel * travel_scale.y
	var depth := _settings.bob_depth_travel * travel_scale.z
	var pitch := _settings.bob_pitch * rotation_scale.x
	_bob_position = Vector3(weight_shift * lateral + plant.x, height * vertical, plant.y) * amplitude
	_bob_hand_position = Vector3(direction.x * arm_swing * lateral,
		support_shift * absf(direction.y) * vertical * 0.2, direction.y * arm_swing * depth) * amplitude
	_bob_rotation = Vector3(sin(_bob_phase * 2.0 - wrist_phase) * pitch * 0.25,
		-arm_swing * shoulder_yaw, -weight_shift * _settings.bob_roll * rotation_scale.y) * amplitude
	_bob_hand_pitch = -direction.y * wrist_follow * pitch * 0.75 * amplitude


func _step_height(phase: float, strength: float) -> float:
	var walk := _settings.bob_walk_step
	var run := _settings.bob_run_step
	var walk_height := walk.sample(phase) if walk != null else cos(phase * TAU)
	var run_height := run.sample(phase) if run != null else walk_height
	var weight := smoothstep(1.0 / 3.0, 1.0, strength)
	var base := lerpf(walk_height, run_height, weight)
	var height := base
	for style: BobStyle in _styles:
		if style != null:
			var styled_walk := style.walk_step.sample(phase) if style.walk_step != null else walk_height
			var styled_run := style.run_step.sample(phase) if style.run_step != null else run_height
			height += (lerpf(styled_walk, styled_run, weight) - base) * float(_styles[style])
	return height


func _play_air(motion: AirMotion, strength: float, hold: bool) -> void:
	if motion == null or motion.envelope == null or motion.duration <= 0.0:
		return
	_air_motion = motion
	_air_strength = strength
	_hold_jump_pose = hold
	_begin_air_blend()


func _begin_air_blend() -> void:
	_air_previous_position = _air_position
	_air_previous_rotation = _air_rotation
	_air_elapsed = 0.0


func _clear_air() -> void:
	_air_motion = null
	_hold_jump_pose = false
	_air_position = Vector3.ZERO
	_air_rotation = Vector3.ZERO


func _advance_air(delta: float, grounded: bool) -> void:
	if _hold_jump_pose and _air_elapsed > 0.0 and grounded:
		_air_motion = null
		_hold_jump_pose = false
		_begin_air_blend()
	if _air_motion == null and _air_position == Vector3.ZERO and _air_rotation == Vector3.ZERO:
		return
	var duration := _air_motion.duration if _air_motion != null else AIR_BLEND_TIME
	if duration <= 0.0:
		_clear_air()
		return
	_air_elapsed = minf(_air_elapsed + delta, duration)
	if not _hold_jump_pose and _air_elapsed >= duration:
		_clear_air()
		return
	var blend := smoothstep(0.0, minf(AIR_BLEND_TIME, duration), _air_elapsed)
	_air_position = _air_previous_position * (1.0 - blend)
	_air_rotation = _air_previous_rotation * (1.0 - blend)
	if _air_motion == null or _air_motion.envelope == null:
		return
	var interrupted := not _air_previous_position.is_zero_approx() or not _air_previous_rotation.is_zero_approx()
	var strength := _air_strength * blend if interrupted else _air_strength
	var phase := _air_elapsed / duration
	var grip_weight := _air_motion.envelope.sample(phase)
	var rotation_curve := _air_motion.rotation_envelope
	var wrist_weight := rotation_curve.sample(phase) if rotation_curve != null else grip_weight
	_air_position += _air_motion.position * (strength * grip_weight)
	_air_rotation += _air_motion.rotation_degrees * (strength * wrist_weight)
