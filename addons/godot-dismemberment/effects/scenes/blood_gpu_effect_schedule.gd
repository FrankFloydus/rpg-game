@tool
extends RefCounted
## Advances source emitter loops while leaving particle motion on the GPU.

const Layer = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_emitter_layer.gd")
const InheritedMotion = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_inherited_motion.gd")
const CollisionParticles = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_collision_particles.gd")
const TIME_TOLERANCE := 0.000001
const SOURCE_FRAME := 1.0 / 60.0

class MovementBirth:
	var pose: Transform3D
	var at: float
	var velocity: Vector3
	var sprite_scale: float

class Emission:
	var emitter: GPUParticles3D
	var layer: Dictionary
	var pose: Transform3D
	var callback: Callable
	var particle_id_provider: Callable
	var pose_provider: Callable
	var source_id: int
	var context: Dictionary
	var requested_sprite_scale: float
	var sprite_scale: float
	var velocity := Vector3.ZERO
	var elapsed := 0.0
	var end := INF
	var next_burst := INF
	var next_stream := INF
	var loop := INF
	var burst_loop := 0
	var stream_interval := INF
	var last_position: Vector3
	var travel_remainder := 0.0
	var pending_movement: Array[MovementBirth] = []
	var movement_batch_start := 0.0
	var motion_source: InheritedMotion.Source
	var motion_impulse: Callable
	var budget: CollisionParticles.FrameBudget
	var sampled_pose: Transform3D
	var sampled_sprite_scale: float
	var sampled_at := 0.0

var _active: Array[Emission] = []
var _finished_motion: Array[Emission] = []
var _motion := InheritedMotion.new()

func bind_inherited_motion(material: Material, ordered := false) -> Material:
	return _motion.bind_material(material, ordered)

func begin(emitter: GPUParticles3D, layer: Dictionary, pose: Transform3D,
		duration: float, callback := Callable(), pose_provider := Callable(), source_id := 0,
		particle_id_provider := Callable(), physics_owned := false,
		receiver_budget: CollisionParticles.FrameBudget = null, sprite_scale := 0.0) -> int:
	if not layer.enabled or not layer.visible or layer.channel == Layer.Channel.COLLISION_EVENT:
		return 0
	var emission := Emission.new()
	emission.emitter = emitter
	emission.layer = layer
	emission.pose = pose
	emission.callback = callback
	emission.particle_id_provider = particle_id_provider
	emission.pose_provider = pose_provider
	emission.source_id = source_id
	emission.requested_sprite_scale = sprite_scale
	emission.sprite_scale = sprite_scale
	if pose_provider.is_valid():
		var source: Dictionary = pose_provider.call()
		if source.is_empty():
			return 0
		emission.pose = source.get(&"pose", pose)
		emission.sprite_scale = _source_sprite_scale(source, sprite_scale)
		emission.velocity = source.get(&"velocity", Vector3.ZERO)
		if layer.source_motion and layer.continuous_inherit_velocity != 0.0:
			var ordered := physics_owned and emitter.fixed_fps == 60 \
				and is_equal_approx(emitter.speed_scale, 1.0) and is_zero_approx(emitter.preprocess)
			var motion_source := _motion.begin(emitter, ordered)
			if motion_source != null:
				emission.motion_source = motion_source
				if motion_source.is_ordered():
					emission.sampled_pose = emission.pose
					emission.sampled_sprite_scale = emission.sprite_scale
					if layer.collision_replay_after <= 0.0:
						emission.budget = receiver_budget
				else:
					emission.motion_impulse = func() -> Vector3: return motion_source.current_impulse()
					_update_motion(emission)
	emission.last_position = emission.pose.origin
	emission.context = Layer.prepare_layer(emitter, layer, emission.pose, emission.sprite_scale)
	if layer.particle_count > 0:
		emission.next_burst = layer.spawn_delay
	if layer.stream_rate > 0.0:
		emission.stream_interval = 1.0 / layer.stream_rate
		emission.next_stream = layer.stream_delay + emission.stream_interval + SOURCE_FRAME

	if layer.loop_duration > 0.0 and duration != 0.0:
		emission.loop = layer.loop_duration
		emission.end = duration if duration > 0.0 else INF
	else:
		emission.end = maxf(layer.spawn_delay, layer.stream_delay + layer.emission_window + SOURCE_FRAME)
		if duration > 0.0:
			emission.end = minf(emission.end, duration)
	var submitted := 0
	if emission.next_burst <= TIME_TOLERANCE and not _is_ordered(emission):
		submitted = _emit(emission, emission.next_burst, layer.particle_count, emission.context)
		_next_burst(emission)
		Layer.request_gpu_update(emitter)
	if minf(emission.next_burst, emission.next_stream) <= emission.end + TIME_TOLERANCE \
			or (pose_provider.is_valid() and layer.stream_spacing > 0.0) \
			or (emission.motion_source != null and emission.end > 0.0):
		_active.append(emission)
	else:
		_end_motion(emission)
	_motion.flush()
	return submitted

func advance(delta: float) -> int:
	if delta <= 0.0 or not is_finite(delta):
		return 0
	var submitted := 0
	for index in range(_active.size() - 1, -1, -1):
		var emission := _active[index]
		if not is_instance_valid(emission.emitter):
			_end_motion(emission)
			_active.remove_at(index)
			continue
		if _is_ordered(emission):
			continue
		var source: Dictionary = {}
		if emission.pose_provider.is_valid():
			source = emission.pose_provider.call()
			if source.is_empty():
				_end_motion(emission)
				_active.remove_at(index)
				continue
		submitted += _advance_emission(emission, source, delta)
		if _has_finished(emission):
			if emission.motion_source != null:
				_finished_motion.append(emission)
			_active.remove_at(index)
	_motion.advance(delta)
	if not _finished_motion.is_empty() and not RenderingServer.frame_post_draw.is_connected(_finish_motion):
		RenderingServer.frame_post_draw.connect(_finish_motion, CONNECT_ONE_SHOT)
	return submitted

func advance_physics(delta: float) -> int:
	if delta <= 0.0 or not is_finite(delta):
		return 0
	var submitted := 0
	for index in range(_active.size() - 1, -1, -1):
		var emission := _active[index]
		if not _is_ordered(emission):
			continue
		if not is_instance_valid(emission.emitter) or not emission.pose_provider.is_valid():
			_end_motion(emission)
			_active.remove_at(index)
			continue
		var source: Dictionary = emission.pose_provider.call()
		if source.is_empty():
			_end_motion(emission)
			_active.remove_at(index)
			continue
		var next_pose: Transform3D = source.get(&"pose", emission.sampled_pose)
		var sprite_scale := _source_sprite_scale(source, emission.requested_sprite_scale)
		var sample_time := emission.sampled_at + delta
		while emission.elapsed + SOURCE_FRAME <= sample_time + TIME_TOLERANCE:
			var weight := clampf((emission.elapsed + SOURCE_FRAME - emission.sampled_at) / delta, 0.0, 1.0)
			var pose := emission.sampled_pose.interpolate_with(next_pose, weight)
			var step_scale := lerpf(emission.sampled_sprite_scale, sprite_scale, weight)
			submitted += _advance_emission(emission, {&"pose": pose, &"sprite_scale": step_scale},
				SOURCE_FRAME, sample_time)
			if _has_finished(emission):
				_end_motion(emission)
				_active.remove_at(index)
				break
		emission.sampled_pose = next_pose
		emission.sampled_sprite_scale = sprite_scale
		emission.sampled_at = sample_time
	return submitted

func has_physics_sources() -> bool:
	for emission in _active:
		if _is_ordered(emission):
			return true
	return false

func _advance_emission(emission: Emission, source: Dictionary, delta: float, contact_interval_end := INF) -> int:
	var submitted := 0
	var interval_end := minf(emission.elapsed + delta, emission.end)
	var previous_origin := emission.pose.origin
	if not source.is_empty():
		var next_pose: Transform3D = source.get(&"pose", emission.pose)
		emission.velocity = source.get(&"velocity", (next_pose.origin - emission.pose.origin) / delta)
		emission.sprite_scale = _source_sprite_scale(source, emission.requested_sprite_scale)
		_update_motion(emission)
		_queue_movement(emission, next_pose, interval_end, delta)
		submitted += _emit_movement_batch(emission, delta, contact_interval_end)
		emission.pose = next_pose
		emission.context = Layer.prepare_layer(emission.emitter, emission.layer, next_pose, emission.sprite_scale)
	while emission.next_burst <= interval_end + TIME_TOLERANCE:
		submitted += _emit_timed(emission, emission.next_burst, emission.layer.particle_count, previous_origin, delta, contact_interval_end)
		_next_burst(emission)
	while emission.next_stream <= interval_end + TIME_TOLERANCE:
		submitted += _emit_timed(emission, emission.next_stream, 1, previous_origin, delta, contact_interval_end)
		emission.next_stream += emission.stream_interval
	if submitted > 0:
		Layer.request_gpu_update(emission.emitter)
	emission.elapsed += delta
	if emission.budget != null:
		# A future birth can still occupy the current boundary through movement
		# spacing tolerance. The previous source interval is fully submitted.
		emission.budget.close_through(roundi(emission.elapsed / SOURCE_FRAME) - 2)
	return submitted

static func _source_sprite_scale(source: Dictionary, fallback: float) -> float:
	var value: Variant = source.get(&"sprite_scale", fallback)
	return float(value) if (value is float or value is int) and is_finite(value) and value > 0.0 else fallback

static func _is_ordered(emission: Emission) -> bool:
	return emission.motion_source != null and emission.motion_source.is_ordered()

static func _has_finished(emission: Emission) -> bool:
	return emission.elapsed >= emission.end and emission.pending_movement.is_empty()

func clear(source_id := 0) -> void:
	for index in range(_active.size() - 1, -1, -1):
		if source_id == 0 or _active[index].source_id == source_id:
			_end_motion(_active[index])
			_active.remove_at(index)
	for index in range(_finished_motion.size() - 1, -1, -1):
		if source_id == 0 or _finished_motion[index].source_id == source_id:
			_end_motion(_finished_motion[index])
			_finished_motion.remove_at(index)
	_motion.flush()

func is_empty() -> bool:
	return _active.is_empty()

func _update_motion(emission: Emission) -> void:
	if emission.motion_source == null:
		return
	var velocity := emission.velocity if emission.velocity.is_finite() else Vector3.ZERO
	var limit: float = emission.layer.continuous_inherit_velocity_limit
	if limit > 0.0:
		velocity = velocity.limit_length(limit)
	var impulse: Vector3 = velocity * emission.layer.continuous_inherit_velocity
	var local_impulse := emission.emitter.global_basis.inverse() * impulse if emission.emitter.local_coords else impulse
	_motion.update(emission.motion_source, impulse, local_impulse, roundi(emission.elapsed / SOURCE_FRAME) if _is_ordered(emission) else -1)

func _end_motion(emission: Emission) -> void:
	if emission.motion_source != null:
		_motion.end(emission.motion_source, maxf(emission.layer.particle_lifetime.x, emission.layer.particle_lifetime.y) + 0.1)

func _finish_motion() -> void:
	# Let the final source sample reach particles in the render step that just completed.
	for emission in _finished_motion:
		_end_motion(emission)
	_finished_motion.clear()
	_motion.flush()

static func _next_burst(emission: Emission) -> void:
	emission.burst_loop += 1
	var limit: int = emission.layer.get(&"burst_loop_limit", 0)
	if limit > 0 and emission.burst_loop >= limit:
		emission.next_burst = INF
		return
	emission.next_burst += emission.loop
	if emission.burst_loop == 1:
		emission.next_burst += SOURCE_FRAME

static func _emit_timed(emission: Emission, at: float, count: int, previous_origin: Vector3, delta: float, contact_interval_end: float) -> int:
	var context := emission.context
	var movement := emission.pose.origin - previous_origin
	if movement != Vector3.ZERO:
		var fraction := clampf((at - emission.elapsed) / delta, 0.0, 1.0)
		var world: Transform3D = context.world
		world.origin -= movement * (1.0 - fraction)
		context = context.duplicate()
		context.world = world
	if is_finite(contact_interval_end):
		return _emit(emission, at, count, context, contact_interval_end)
	if emission.pose_provider.is_valid() and emission.layer.stream_spacing > 0.0:
		return _emit(emission, at, count, context, emission.elapsed + delta)
	return _emit(emission, at, count, context)

static func _emit(emission: Emission, at: float, count: int, context: Dictionary, contact_interval_end := INF) -> int:
	var samples: Array[Dictionary] = []
	var collect := emission.callback.is_valid()
	var delay := maxf(at - emission.elapsed, 0.0)
	var motion_slot := _motion_token(emission, at)
	for index in count:
		Layer.emit_prepared_sample(emission.emitter, emission.layer, context, delay, samples, collect, emission.velocity, emission.particle_id_provider, motion_slot)
	if is_finite(contact_interval_end) or _is_ordered(emission):
		for sample in samples:
			_set_contact_birth_phase(sample, at, contact_interval_end if is_finite(contact_interval_end) else at)
			_set_ordered_contact(emission, sample, at)
	_submit_samples(emission, samples)
	return count

static func _queue_movement(emission: Emission, pose: Transform3D, interval_end: float, delta: float) -> void:
	var spacing: float = emission.layer.stream_spacing
	var movement_time := interval_end - emission.elapsed
	if spacing <= 0.0 or movement_time <= 0.0:
		return
	var displacement := pose.origin - emission.last_position
	var distance := displacement.length()
	if distance < emission.layer.stream_movement_tolerance:
		return
	var speed_limit: float = emission.layer.get(&"stream_max_speed", 0.0)
	var movement_speed := distance / delta
	if distance <= 0.0 or (speed_limit <= 0.0 and distance > emission.layer.stream_max_movement):
		emission.last_position = pose.origin
		emission.travel_remainder = 0.0
		return
	var fraction_until_end := clampf(movement_time / delta, 0.0, 1.0)
	displacement *= fraction_until_end
	distance *= fraction_until_end
	if speed_limit > 0.0 and movement_speed > speed_limit:
		emission.travel_remainder = fposmod(emission.travel_remainder + distance, spacing)
		emission.last_position += displacement
		return
	var offset := spacing - emission.travel_remainder
	var distance_tolerance := minf(0.000001, spacing * 0.001)
	while offset <= distance + distance_tolerance:
		if randf() <= emission.layer.stream_probability:
			var birth := MovementBirth.new()
			var fraction := minf(offset / distance, 1.0)
			birth.pose = pose
			birth.pose.origin = emission.last_position + displacement * fraction
			birth.at = emission.elapsed + movement_time * fraction
			birth.velocity = emission.velocity
			birth.sprite_scale = emission.sprite_scale
			emission.pending_movement.append(birth)
		offset += spacing
	emission.travel_remainder = maxf(0.0, distance - (offset - spacing))
	emission.last_position += displacement

static func _emit_movement_batch(emission: Emission, delta: float, contact_interval_end: float) -> int:
	if emission.layer.stream_spacing <= 0.0:
		return 0
	var interval_end := emission.elapsed + delta
	var batch_steps := floori((interval_end - emission.movement_batch_start + TIME_TOLERANCE) / SOURCE_FRAME)
	if batch_steps <= 0:
		return 0
	var batch_end := emission.movement_batch_start + batch_steps * SOURCE_FRAME
	var samples: Array[Dictionary] = []
	var collect := emission.callback.is_valid()
	var submitted := 0
	for birth: MovementBirth in emission.pending_movement:
		if birth.at > batch_end + TIME_TOLERANCE:
			break
		var delay := maxf(0.0, birth.at - emission.movement_batch_start)
		var old_size := samples.size()
		Layer.emit_sample(emission.emitter, emission.layer, birth.pose, delay, samples, collect, birth.velocity,
			emission.particle_id_provider, _motion_token(emission, birth.at), birth.sprite_scale)
		if samples.size() > old_size:
			_set_contact_birth_phase(samples.back(), birth.at, contact_interval_end if is_finite(contact_interval_end) else interval_end)
			_set_ordered_contact(emission, samples.back(), birth.at)
		submitted += 1
	if submitted == emission.pending_movement.size():
		emission.pending_movement.clear()
	elif submitted > 0:
		emission.pending_movement = emission.pending_movement.slice(submitted)
	emission.movement_batch_start = batch_end
	_submit_samples(emission, samples)
	return submitted

static func _first_motion_tick(birth_time: float) -> int:
	return maxi(0, ceili((birth_time - TIME_TOLERANCE) / SOURCE_FRAME) - 1)

static func _motion_token(emission: Emission, birth_time: float) -> int:
	return emission.motion_source.particle_token(_first_motion_tick(birth_time)) if emission.motion_source != null else 0

static func _set_ordered_contact(emission: Emission, sample: Dictionary, birth_time: float) -> void:
	if _is_ordered(emission):
		sample[&"motion_impulse_at_tick"] = emission.motion_source.impulse_at_tick
		sample[&"motion_first_tick"] = _first_motion_tick(birth_time)
		if birth_time <= TIME_TOLERANCE:
			sample[&"initial_step"] = SOURCE_FRAME
		if emission.budget != null:
			sample[&"first_budget_tick"] = _first_motion_tick(birth_time)

static func _set_contact_birth_phase(sample: Dictionary, birth_time: float, interval_end: float) -> void:
	var boundary := ceilf((birth_time - TIME_TOLERANCE) / SOURCE_FRAME) * SOURCE_FRAME
	sample[&"initial_step"] = maxf(0.0, boundary - birth_time)
	sample[&"contact_start_offset"] = minf(0.0, birth_time - interval_end)

static func _submit_samples(emission: Emission, samples: Array[Dictionary]) -> void:
	if samples.is_empty():
		return
	if emission.motion_impulse.is_valid():
		for sample in samples:
			sample[&"motion_impulse"] = emission.motion_impulse
	emission.callback.call(samples)
