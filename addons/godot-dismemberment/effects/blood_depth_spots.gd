extends Node
## Simulates the Extreme Burst Spots against the owning viewport's opaque depth.

const Layer = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_emitter_layer.gd")
const Bounds = preload("res://addons/godot-dismemberment/effects/blood_depth_spots_bounds.gd")
const COMPUTE_PATH := "res://addons/godot-dismemberment/effects/blood_depth_spots.glsl"
const LIQUID_DRAW = preload("res://addons/godot-dismemberment/effects/blood_gpu_liquid_draw.gdshader")
const STOCK_PROCESS = preload("res://addons/godot-dismemberment/effects/blood_gpu_process.gdshader")
const KEY := &"_blood_spots_depth_backend"
const STEP := 1.0 / 60.0
const MAX_PENDING_STEPS := 8
const GPU_TICK_MASK := 0xffffffff
const CAPACITY := 8192
const MAX_IDLE_BUCKETS := 2
const BYTES_PER_PARTICLE := 112
const DRAW_BYTES_PER_PARTICLE := 80

enum BucketState { UNREQUESTED, PENDING, READY, FAILED }

class DepthPass extends CompositorEffect:
	var rd: RenderingDevice
	var shader: RID
	var pipeline: RID
	var sampler: RID
	var view_buffer: RID
	var buckets := {}
	var _bucket_states: Dictionary[RID, int] = {}
	var _bucket_lock := Mutex.new()
	var target_tick := 0
	var simulated_tick := 0
	var _completed_tick := 0
	var _clock_lock := Mutex.new()
	var _epoch_payload := PackedByteArray()
	var _epoch_tick := -1
	var _epoch_count := 0
	var render_target: RID
	var dispatch_count := 0

	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
		access_resolved_depth = true
		needs_normal_roughness = true

	func initialize(compute: RDShaderFile, report: Callable) -> void:
		if rd != null:
			return
		rd = RenderingServer.get_rendering_device()
		if rd == null:
			report.call_deferred(false, "No RenderingDevice")
			return
		var spirv: RDShaderSPIRV = compute.get_spirv()
		if spirv == null:
			report.call_deferred(false, compute.base_error)
			return
		var failure := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not failure.is_empty():
			report.call_deferred(false, failure)
			return
		shader = rd.shader_create_from_spirv(spirv)
		if shader.is_valid():
			pipeline = rd.compute_pipeline_create(shader)
		if not pipeline.is_valid():
			report.call_deferred(false, "Invalid compute pipeline")
			return
		sampler = rd.sampler_create(RDSamplerState.new())
		view_buffer = rd.storage_buffer_create(224)
		report.call_deferred(sampler.is_valid() and view_buffer.is_valid(), "Could not allocate compute resources")

	func request_bucket(rid: RID) -> bool:
		_bucket_lock.lock()
		var needed := not _bucket_states.has(rid)
		if needed:
			_bucket_states[rid] = BucketState.PENDING
		_bucket_lock.unlock()
		return needed

	func bucket_state(rid: RID) -> int:
		_bucket_lock.lock()
		var state := _bucket_states.get(rid, BucketState.UNREQUESTED) as int
		_bucket_lock.unlock()
		return state

	func _set_bucket_state(rid: RID, state: int) -> void:
		_bucket_lock.lock()
		_bucket_states[rid] = state
		_bucket_lock.unlock()

	func prepare(rid: RID, radius: Vector2, report: Callable) -> void:
		if bucket_state(rid) != BucketState.PENDING:
			return
		if not pipeline.is_valid():
			_fail_bucket(rid, report)
			return
		var instances := RenderingServer.multimesh_get_buffer_rd_rid(rid)
		if not instances.is_valid():
			_fail_bucket(rid, report)
			return
		var state := rd.storage_buffer_create(CAPACITY * BYTES_PER_PARTICLE)
		var epochs := rd.storage_buffer_create(CAPACITY * 4)
		if not state.is_valid() or not epochs.is_valid() \
				or rd.buffer_clear(state, 0, CAPACITY * BYTES_PER_PARTICLE) != OK \
				or rd.buffer_clear(instances, 0, CAPACITY * DRAW_BYTES_PER_PARTICLE) != OK:
			for owned in [state, epochs]:
				if owned.is_valid():
					rd.free_rid(owned)
			_fail_bucket(rid, report)
			return
		buckets[rid] = {&"buffer": state, &"epochs": epochs, &"count": 0, &"radius": radius}
		_set_bucket_state(rid, BucketState.READY)

	func enqueue(rid: RID, offset: int, births: PackedByteArray, count: int, birth_tick: int, report: Callable) -> void:
		if not buckets.has(rid):
			# A launch queued before failure can still publish its main-thread instance count.
			if bucket_state(rid) == BucketState.FAILED:
				RenderingServer.multimesh_set_visible_instances(rid, 0)
			return
		@warning_ignore("integer_division")
		var birth_count := births.size() / BYTES_PER_PARTICLE
		if birth_count <= 0 or births.size() % BYTES_PER_PARTICLE != 0 or offset < 0 \
				or birth_count > count - offset or count > CAPACITY:
			_fail_bucket(rid, report)
			return
		var bucket: Dictionary = buckets[rid]
		if _epoch_tick != birth_tick or _epoch_count != birth_count:
			_epoch_tick = birth_tick
			_epoch_count = birth_count
			var epochs := PackedInt32Array()
			epochs.resize(birth_count)
			var gpu_tick := birth_tick & GPU_TICK_MASK
			epochs.fill(gpu_tick - (1 << 32) if gpu_tick >= (1 << 31) else gpu_tick)
			_epoch_payload = epochs.to_byte_array()
		if rd.buffer_update(bucket.epochs, offset * 4, _epoch_payload.size(), _epoch_payload) != OK \
				or rd.buffer_update(bucket.buffer, offset * BYTES_PER_PARTICLE, births.size(), births) != OK:
			_fail_bucket(rid, report)
			return
		bucket.count = count

	func _free_bucket_buffers(rid: RID) -> void:
		if buckets.has(rid):
			rd.free_rid(buckets[rid].buffer)
			rd.free_rid(buckets[rid].epochs)
			buckets.erase(rid)

	func _fail_bucket(rid: RID, report: Callable) -> void:
		# Its instance buffer may still contain transforms from earlier successful launches.
		RenderingServer.multimesh_set_visible_instances(rid, 0)
		_free_bucket_buffers(rid)
		_set_bucket_state(rid, BucketState.FAILED)
		report.call_deferred(rid)

	func remove(rid: RID) -> void:
		_free_bucket_buffers(rid)
		_bucket_lock.lock()
		_bucket_states.erase(rid)
		_bucket_lock.unlock()

	func clear(rid: RID, offset: int, count: int, high_water: int, report: Callable) -> void:
		if not buckets.has(rid):
			# A launch queued before failure can still publish its main-thread instance count.
			if bucket_state(rid) == BucketState.FAILED:
				RenderingServer.multimesh_set_visible_instances(rid, 0)
			return
		var bucket: Dictionary = buckets[rid]
		var instances := RenderingServer.multimesh_get_buffer_rd_rid(rid)
		if offset < 0 or count <= 0 or count > CAPACITY - offset or high_water < 0 or high_water > CAPACITY \
				or not instances.is_valid() \
				or rd.buffer_clear(bucket.buffer, offset * BYTES_PER_PARTICLE, count * BYTES_PER_PARTICLE) != OK \
				or rd.buffer_clear(instances, offset * DRAW_BYTES_PER_PARTICLE, count * DRAW_BYTES_PER_PARTICLE) != OK:
			_fail_bucket(rid, report)
			return
		bucket.count = high_water

	func advance(tick: int) -> void:
		target_tick = maxi(tick, target_tick)

	func settle_idle(tick: int) -> void:
		# Prior queued clears removed all live slots, so there is no state left to advance.
		simulated_tick = maxi(simulated_tick, tick)
		target_tick = maxi(target_tick, tick)
		_publish_completed_tick()

	func completed_tick() -> int:
		_clock_lock.lock()
		var tick := _completed_tick
		_clock_lock.unlock()
		return tick

	func _publish_completed_tick() -> void:
		_clock_lock.lock()
		_completed_tick = simulated_tick
		_clock_lock.unlock()

	func _render_callback(_callback_type: int, render_data: RenderData) -> void:
		var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
		if buffers == null or buffers.get_view_count() != 1 or buffers.get_render_target() != render_target \
				or target_tick <= simulated_tick or not pipeline.is_valid():
			return
		var data := render_data.get_render_scene_data()
		var transform := data.get_cam_transform()
		var view_projection := data.get_cam_projection() * Projection(transform.affine_inverse())
		var values := PackedFloat32Array()
		for matrix: Projection in [view_projection, view_projection.inverse(), Projection(transform)]:
			for column in [matrix.x, matrix.y, matrix.z, matrix.w]:
				values.append_array(PackedFloat32Array([column.x, column.y, column.z, column.w]))
		var eye := transform.origin
		values.append_array(PackedFloat32Array([eye.x, eye.y, eye.z, STEP, 0.0, 0.0, 0.0, 0.0]))
		var bytes := values.to_byte_array()
		rd.buffer_update(view_buffer, 0, bytes.size(), bytes)
		var depth := buffers.get_depth_layer(0)
		var has_normals := buffers.has_texture(&"forward_clustered", &"normal_roughness")
		var normal := buffers.get_texture_slice(&"forward_clustered", &"normal_roughness", 0, 0, 1, 1) if has_normals else depth
		var attachments: Array[RDUniform] = []
		for texture in [depth, normal]:
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			uniform.binding = attachments.size()
			uniform.add_id(sampler)
			uniform.add_id(texture)
			attachments.append(uniform)
		var steps := mini(target_tick - simulated_tick, MAX_PENDING_STEPS)
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipeline)
		for rid: RID in buckets:
			var bucket: Dictionary = buckets[rid]
			if bucket.count <= 0:
				continue
			var uniforms := attachments.duplicate()
			for buffer in [bucket.buffer, RenderingServer.multimesh_get_buffer_rd_rid(rid), view_buffer, bucket.epochs]:
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
				uniform.binding = uniforms.size()
				uniform.add_id(buffer)
				uniforms.append(uniform)
			var uniform_set := UniformSetCacheRD.get_cache(shader, 0, uniforms)
			var push := PackedByteArray()
			push.resize(20)
			push.encode_float(0, bucket.radius.x)
			push.encode_float(4, bucket.radius.y)
			push.encode_u32(8, bucket.count)
			push.encode_u32(12, int(has_normals))
			rd.compute_list_bind_uniform_set(list, uniform_set, 0)
			for step in steps:
				push.encode_u32(16, (simulated_tick + step + 1) & GPU_TICK_MASK)
				rd.compute_list_set_push_constant(list, push, push.size())
				rd.compute_list_dispatch(list, ceili(float(bucket.count) / 64.0), 1, 1)
				if step + 1 < steps:
					rd.compute_list_add_barrier(list)
				dispatch_count += 1
		rd.compute_list_end()
		simulated_tick += steps
		_publish_completed_tick()

	func readback(rid: RID, callback: Callable) -> void:
		if buckets.has(rid):
			rd.buffer_get_data_async(buckets[rid].buffer, callback, 0, buckets[rid].count * BYTES_PER_PARTICLE)

	func release() -> void:
		if rd == null:
			return
		for rid: RID in buckets.keys():
			remove(rid)
		_bucket_lock.lock()
		_bucket_states.clear()
		_bucket_lock.unlock()
		for handle in [pipeline, shader, sampler, view_buffer]:
			if handle.is_valid():
				rd.free_rid(handle)
		rd = null

var _camera: Camera3D
var _original: Compositor
var _wrapper: Compositor
var _inherited: Compositor
var _base_effects: Array[CompositorEffect] = []
var _pass := DepthPass.new()
var _buckets: Array[Dictionary] = []
var _submitted_tick := 0
var _admitted_frame := -1
var _first_admitted_tick := 0
var _idle_through_tick := 0
var _range_count := 0
var _accumulated := 0.0
var _available := false
var _starting := true
var _warm_layers: Array[Dictionary] = []
var _draw_uniform_names: Array[StringName] = []
var _world_environments: Dictionary[int, WorldEnvironment] = {}
var _reported_bucket_failure := false

static func eligible(layer: Dictionary, emitter: GPUParticles3D, authored_material: Material = null) -> bool:
	var material := authored_material if authored_material != null else emitter.material_override
	var process := emitter.process_material as ShaderMaterial
	return not Engine.is_editor_hint() and layer.get(&"use_scene_depth_collision", false) and layer.enabled and layer.visible \
		and emitter.is_visible_in_tree() \
		and layer.source_motion and not layer.collision_events and layer.collision_kill \
		and layer.stream_rate == 0.0 and layer.stream_spacing == 0.0 and layer.loop_duration == 0.0 and layer.spawn_delay == 0.0 \
		and layer.continuous_inherit_velocity == 0.0 and not emitter.local_coords and emitter.draw_passes == 1 \
		and layer.drag_range.is_finite() and layer.drag_range.x >= 0.0 and layer.drag_range.y >= 0.0 \
		and process != null and process.shader == STOCK_PROCESS and is_equal_approx(emitter.speed_scale, 1.0) \
		and emitter.fixed_fps == 60 and emitter.draw_order == GPUParticles3D.DRAW_ORDER_INDEX \
		and emitter.draw_pass_1 is Mesh and emitter.material_overlay == null and material is ShaderMaterial \
		and material.shader == LIQUID_DRAW and material.next_pass == null and material.get_shader_parameter(&"source_graph") == true \
		and material.get_shader_parameter(&"source_masked") == false \
		and layer.particle_count > 0 and layer.particle_count <= CAPACITY \
		and layer.size_x_curve == layer.size_y_curve and _linear_radius(layer.size_x_curve) \
		and RenderingServer.get_current_rendering_method() == &"forward_plus"

static func _linear_radius(texture: CurveTexture) -> bool:
	if texture == null:
		return true
	var curve := texture.curve
	return curve != null and curve.point_count == 2 \
		and is_equal_approx(curve.get_point_position(0).x, 0.0) \
		and is_equal_approx(curve.get_point_position(1).x, 1.0) \
		and curve.get_point_right_mode(0) == Curve.TANGENT_LINEAR \
		and curve.get_point_left_mode(1) == Curve.TANGENT_LINEAR

static func get_backend(owner: Node3D) -> Node:
	var viewport := owner.get_viewport()
	if viewport == null or viewport.disable_3d or viewport.use_xr or viewport.get_camera_3d() == null \
			or (viewport is SubViewport and viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS):
		return null
	var backend: Node = viewport.get_meta(KEY, null) if viewport.has_meta(KEY) else null
	if backend == null:
		backend = load("res://addons/godot-dismemberment/effects/blood_depth_spots.gd").new()
		backend.name = "BloodDepthSpots"
		viewport.add_child(backend, false, Node.INTERNAL_MODE_BACK)
		viewport.set_meta(KEY, backend)
	return backend

func _ready() -> void:
	set_process(false)
	get_tree().node_added.connect(_track_environment)
	get_tree().node_removed.connect(_forget_environment)
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_track_environment(node)
	var compute := ResourceLoader.load(COMPUTE_PATH, "RDShaderFile") as RDShaderFile \
		if ResourceLoader.exists(COMPUTE_PATH, "RDShaderFile") else null
	if compute == null:
		_finish_startup(false, "Imported compute shader is missing")
		return
	for property in LIQUID_DRAW.get_shader_uniform_list():
		_draw_uniform_names.append(property.name)
	_pass.render_target = RenderingServer.viewport_get_render_target(get_viewport().get_viewport_rid())
	RenderingServer.call_on_render_thread(_pass.initialize.bind(compute, _finish_startup))

func _finish_startup(available: bool, reason: String) -> void:
	_available = available
	_starting = false
	var pending := _warm_layers
	_warm_layers = []
	for item in pending:
		if is_instance_valid(item.emitter) and not item.emitter.is_queued_for_deletion():
			prepare_layer(item.emitter, item.layer, item.material)
	if not available:
		var summary := reason.get_slice("Stage '", 0).strip_edges()
		push_warning("Spots depth simulation unavailable, using regular particles. " + summary)

func prepare_layer(emitter: GPUParticles3D, layer: Dictionary, material: Material) -> void:
	if _starting:
		_warm_layers.append({&"emitter": emitter, &"layer": layer, &"material": material})
		return
	if not _available:
		return
	var bucket := _find_bucket(emitter, layer, material)
	# Prewarming alone leaves this node idle. Keep the requested bucket and bound the cache.
	_trim_idle_buckets(bucket)
	_request_bucket(bucket)

func _request_bucket(bucket: Dictionary) -> int:
	var mesh: MultiMesh = bucket.draw.multimesh
	var rid := mesh.get_rid()
	if _pass.request_bucket(rid):
		RenderingServer.call_on_render_thread(_pass.prepare.bind(rid, bucket.radius, _on_bucket_failed))
	return _pass.bucket_state(rid)

func _on_bucket_failed(rid: RID) -> void:
	for index in _buckets.size():
		var mesh: MultiMesh = _buckets[index].draw.multimesh
		if mesh.get_rid() == rid:
			_discard_bucket(index)
			break
	if not _reported_bucket_failure:
		_reported_bucket_failure = true
		push_warning("Could not prepare or update the Spots depth buffer. This burst may be incomplete.")

func _radius_curve(layer: Dictionary) -> Vector2:
	if layer.size_x_curve == null:
		return Vector2.ONE
	var curve: Curve = layer.size_x_curve.curve
	return Vector2(curve.sample(0.0), curve.sample(1.0))

func emit_layer(emitter: GPUParticles3D, layer: Dictionary, pose: Transform3D, sprite_scale: float, owner_id: int, authored_material: Material = null) -> int:
	if not _available or not _bind_camera():
		return 0
	var material := authored_material if authored_material != null else emitter.material_override
	var count: int = layer.particle_count
	if count <= 0 or count > CAPACITY:
		return 0
	var bucket := _find_bucket(emitter, layer, material, count)
	_trim_idle_buckets(bucket)
	if _request_bucket(bucket) != BucketState.READY:
		if _range_count == 0:
			_restore_camera()
		return 0
	var context := Layer.prepare_layer(emitter, layer, pose, sprite_scale)
	var packed := PackedByteArray()
	if ClassDB.class_has_method(&"BloodParticleBirthBatch", &"sample_world_cone_depth"):
		packed = ClassDB.class_call_static(&"BloodParticleBirthBatch", &"sample_world_cone_depth", layer, context, count)
	if packed.is_empty():
		var births: Array[float] = []
		var contacts: Array[Dictionary] = []
		for particle in count:
			Layer.emit_prepared_sample(emitter, layer, context, 0.0, contacts, false, Vector3.ZERO, Callable(), 0, births)
		packed = PackedFloat32Array(births).to_byte_array()
	if packed.size() != count * BYTES_PER_PARTICLE:
		push_error("Blood depth birth packing produced %d bytes for %d particles" % [packed.size(), count])
		return 0
	var launch_bounds := Bounds.launch_bounds(layer, context, bucket.sprite_shape, bucket.radius)
	var offset := _reserve(bucket, count, maxf(layer.particle_lifetime.x, layer.particle_lifetime.y), owner_id, launch_bounds, emitter)
	if offset < 0:
		return 0
	var mesh: MultiMesh = bucket.draw.multimesh
	bucket.high_water = maxi(bucket.high_water, offset + count)
	mesh.visible_instance_count = bucket.high_water
	bucket.bounds_dirty = true
	_update_bucket_bounds(bucket, Bounds.render_width(get_viewport()))
	RenderingServer.call_on_render_thread(_pass.enqueue.bind(mesh.get_rid(), offset, packed, bucket.high_water,
		_birth_tick(), _on_bucket_failed))
	set_process(true)
	return count

func _birth_tick() -> int:
	var completed := _completed_tick()
	if _admitted_frame == Engine.get_process_frames() and completed == _first_admitted_tick - 1:
		return _first_admitted_tick
	return _submitted_tick + 1

func _completed_tick() -> int:
	# The idle barrier is enqueued after the old buffers clear and before the next upload.
	return maxi(_idle_through_tick, _pass.completed_tick())

func _find_bucket(emitter: GPUParticles3D, layer: Dictionary, material: Material, count := 0) -> Dictionary:
	var curves := Layer.visual_curve_settings(layer)
	var draw_state := _draw_state(material, curves)
	var radius := _radius_curve(layer)
	for bucket in _buckets:
		if bucket.material == material and bucket.curves == curves and bucket.mesh == emitter.draw_pass_1 \
			and bucket.layers == emitter.layers and bucket.world == emitter.get_world_3d() \
			and bucket.draw_state == draw_state and bucket.radius == radius and _has_range(bucket, count):
			return bucket
	return _create_bucket(emitter, layer, material, draw_state, radius)

func _draw_state(material: ShaderMaterial, curves: Dictionary) -> Array:
	var values := [material.render_priority, material.next_pass]
	for property in _draw_uniform_names:
		values.append(_curve_state(material.get_shader_parameter(property)))
	for setting in curves.values():
		values.append(_curve_state(setting))
	return values

func _curve_state(value: Variant) -> Variant:
	if value is CurveTexture and value.curve != null:
		var curve: Curve = value.curve
		var points := [value, value.width, curve.min_domain, curve.max_domain, curve.bake_resolution]
		for i in curve.point_count:
			points.append([curve.get_point_position(i), curve.get_point_left_tangent(i),
				curve.get_point_right_tangent(i), curve.get_point_left_mode(i), curve.get_point_right_mode(i)])
		return points
	return value

func _has_range(bucket: Dictionary, count: int) -> bool:
	var offset := 0
	for used in bucket.ranges:
		if offset + count <= int(used.offset):
			return true
		offset = used.offset + used.count
	return offset + count <= CAPACITY

func _create_bucket(emitter: GPUParticles3D, layer: Dictionary, material: Material, draw_state: Array, radius: Vector2) -> Dictionary:
	var draw := MultiMeshInstance3D.new()
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.use_custom_data = true
	mesh.mesh = emitter.draw_pass_1
	mesh.instance_count = CAPACITY
	mesh.visible_instance_count = 0
	draw.multimesh = mesh
	var bound := Layer.bind_visual_curves(material, layer) as ShaderMaterial
	if bound == material:
		bound = material.duplicate() as ShaderMaterial
	for name in _draw_uniform_names:
		var texture: Variant = bound.get_shader_parameter(name)
		if texture is CurveTexture and texture.curve != null:
			var snapshot := texture.duplicate() as CurveTexture
			snapshot.curve = texture.curve.duplicate() as Curve
			bound.set_shader_parameter(name, snapshot)
	draw.material_override = bound
	draw.layers = emitter.layers
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	draw.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	draw.top_level = true
	add_child(draw, false, Node.INTERNAL_MODE_BACK)
	var bucket := {&"draw": draw, &"material": material, &"curves": Layer.visual_curve_settings(layer),
		&"draw_state": draw_state, &"radius": radius,
		&"mesh": emitter.draw_pass_1, &"layers": emitter.layers, &"world": emitter.get_world_3d(), &"ranges": [], &"high_water": 0,
		&"sprite_shape": Bounds.sprite_shape(emitter.draw_pass_1, bound), &"bounds_dirty": true, &"center_bounds": AABB()}
	_buckets.append(bucket)
	return bucket

func _reserve(bucket: Dictionary, count: int, lifetime: float, owner_id: int, bounds: AABB, emitter: GPUParticles3D) -> int:
	var offset := 0
	var ranges: Array = bucket.ranges
	var reservation := {&"offset": 0, &"count": count, &"expires": _submitted_tick + ceili(lifetime / STEP) + 2,
		&"owner": owner_id, &"bounds": bounds, &"emitter": emitter}
	for index in ranges.size():
		var used: Dictionary = ranges[index]
		if offset + count <= int(used.offset):
			reservation.offset = offset
			ranges.insert(index, reservation)
			_range_count += 1
			return offset
		offset = used.offset + used.count
	if offset + count > CAPACITY:
		return -1
	reservation.offset = offset
	ranges.append(reservation)
	_range_count += 1
	return offset

func clear_owner(owner_id: int) -> void:
	for bucket in _buckets:
		var ranges: Array = bucket.ranges
		for index in range(ranges.size() - 1, -1, -1):
			var used: Dictionary = ranges[index]
			if used.owner == owner_id:
				_release_range(bucket, index)

func _release_range(bucket: Dictionary, index: int) -> void:
	var ranges: Array = bucket.ranges
	var used: Dictionary = ranges.pop_at(index)
	bucket.bounds_dirty = true
	var mesh: MultiMesh = bucket.draw.multimesh
	var high_water := int(ranges.back().offset) + int(ranges.back().count) if not ranges.is_empty() else 0
	bucket.high_water = high_water
	mesh.visible_instance_count = high_water
	RenderingServer.call_on_render_thread(_pass.clear.bind(mesh.get_rid(), used.offset, used.count, high_water, _on_bucket_failed))
	_range_count -= 1
	if _range_count == 0:
		_settle_idle_clock()

func _update_bucket_bounds(bucket: Dictionary, width: float) -> void:
	var mesh: MultiMesh = bucket.draw.multimesh
	if bucket.bounds_dirty:
		var combined := AABB()
		for used in bucket.ranges:
			combined = used.bounds if combined.size == Vector3.ZERO else combined.merge(used.bounds)
		bucket.center_bounds = combined
		bucket.bounds_dirty = false
	var bounds: AABB = bucket.center_bounds
	if bounds.size != Vector3.ZERO:
		bounds = Bounds.add_coverage(bounds, bucket.sprite_shape, _camera, width)
	if mesh.custom_aabb != bounds:
		mesh.custom_aabb = bounds

func _process(delta: float) -> void:
	var has_camera := _bind_camera()
	var completed_tick := _completed_tick()
	var active := false
	var width := Bounds.render_width(get_viewport())
	for bucket in _buckets:
		var draw: MultiMeshInstance3D = bucket.draw
		draw.visible = has_camera
		var ranges: Array = bucket.ranges
		for index in range(ranges.size() - 1, -1, -1):
			var used: Dictionary = ranges[index]
			if used.expires <= completed_tick or not is_instance_valid(used.emitter) or not used.emitter.is_visible_in_tree():
				_release_range(bucket, index)
		_update_bucket_bounds(bucket, width)
		if not ranges.is_empty():
			active = true
	_trim_idle_buckets()
	if active:
		if has_camera:
			# Bound catch-up work while preserving all ticks already queued for rendering.
			var available := maxi(0, MAX_PENDING_STEPS - (_submitted_tick - completed_tick))
			var total := _accumulated + delta
			var whole_steps := floori(total / STEP + 0.00001)
			_accumulated = maxf(total - whole_steps * STEP, 0.0)
			var steps := mini(whole_steps, available)
			if steps > 0:
				_admitted_frame = Engine.get_process_frames()
				_first_admitted_tick = _submitted_tick + 1
				_submitted_tick += steps
				RenderingServer.call_on_render_thread(_pass.advance.bind(_submitted_tick))
	else:
		_restore_camera()
		set_process(false)

func _settle_idle_clock() -> void:
	_accumulated = 0.0
	_admitted_frame = -1
	if _completed_tick() < _submitted_tick:
		_idle_through_tick = _submitted_tick
		RenderingServer.call_on_render_thread(_pass.settle_idle.bind(_submitted_tick))

func _track_environment(node: Node) -> void:
	if node is WorldEnvironment:
		_world_environments[node.get_instance_id()] = node

func _forget_environment(node: Node) -> void:
	if node is WorldEnvironment:
		_world_environments.erase(node.get_instance_id())

func _world_compositor(world: World3D) -> Array:
	var found: Compositor
	for environment in _world_environments.values():
		if not is_instance_valid(environment) or not environment.is_inside_tree() \
				or environment.get_viewport().find_world_3d() != world or environment.compositor == null:
			continue
		if found != null and found != environment.compositor:
			return [false, null]
		found = environment.compositor
	return [true, found]

func _bind_camera() -> bool:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	var world := viewport.find_world_3d()
	for i in range(_buckets.size() - 1, -1, -1):
		var bucket := _buckets[i]
		if bucket.world != world:
			_discard_bucket(i)
	if camera == null or viewport.disable_3d or viewport.use_xr \
			or (viewport is SubViewport and viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS):
		_restore_camera()
		return false
	var camera_base := _original if camera == _camera and camera.compositor == _wrapper else camera.compositor
	var base := camera_base
	if camera_base == null:
		var inherited := _world_compositor(camera.get_world_3d())
		if not inherited[0]:
			_restore_camera()
			return false
		base = inherited[1]
	if camera == _camera and camera.compositor == _wrapper:
		if _inherited != base:
			_bind_effect_list(base)
		elif base != null and base.compositor_effects != _base_effects:
			_sync_effect_list()
		return true
	_restore_camera()
	_camera = camera
	_original = camera.compositor
	_wrapper = Compositor.new()
	_bind_effect_list(base)
	camera.compositor = _wrapper
	return true

func _bind_effect_list(base: Compositor) -> void:
	if _inherited != null and _inherited.changed.is_connected(_sync_effect_list):
		_inherited.changed.disconnect(_sync_effect_list)
	_inherited = base
	if _inherited != null:
		_inherited.changed.connect(_sync_effect_list)
	_sync_effect_list()

func _sync_effect_list() -> void:
	_base_effects.clear()
	if _inherited != null:
		_base_effects.assign(_inherited.compositor_effects)
	var effects := _base_effects.duplicate()
	effects.append(_pass)
	_wrapper.compositor_effects = effects

func _restore_camera() -> void:
	if _inherited != null and _inherited.changed.is_connected(_sync_effect_list):
		_inherited.changed.disconnect(_sync_effect_list)
	if is_instance_valid(_camera) and _camera.compositor == _wrapper:
		_camera.compositor = _original
	_camera = null
	_original = null
	_inherited = null
	_wrapper = null
	_base_effects.clear()

func _discard_bucket(index: int) -> void:
	var bucket: Dictionary = _buckets.pop_at(index)
	var draw: MultiMeshInstance3D = bucket.draw
	draw.hide()
	RenderingServer.call_on_render_thread(_pass.remove.bind(draw.multimesh.get_rid()))
	draw.queue_free()
	if not bucket.ranges.is_empty():
		_range_count -= bucket.ranges.size()
		if _range_count == 0:
			_settle_idle_clock()

func _trim_idle_buckets(keep: Dictionary = {}) -> void:
	var idle := 1 if not keep.is_empty() and keep.ranges.is_empty() else 0
	for index in range(_buckets.size() - 1, -1, -1):
		var bucket := _buckets[index]
		if bucket.ranges.is_empty() and not is_same(bucket, keep):
			idle += 1
			if idle > MAX_IDLE_BUCKETS:
				_discard_bucket(index)

func _exit_tree() -> void:
	var tree := get_tree()
	if tree.node_added.is_connected(_track_environment):
		tree.node_added.disconnect(_track_environment)
		tree.node_removed.disconnect(_forget_environment)
	if is_instance_valid(get_parent()) and get_parent().has_meta(KEY) and get_parent().get_meta(KEY) == self:
		get_parent().remove_meta(KEY)
	_restore_camera()
	RenderingServer.call_on_render_thread(_pass.release)









