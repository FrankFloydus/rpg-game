extends RefCounted
## Conservative world-space bounds for a finite, manually emitted depth burst.

const STEP := 1.0 / 60.0

static func sprite_shape(mesh: Mesh, material: ShaderMaterial) -> Dictionary:
	var box := mesh.get_aabb()
	var pivot: Vector2 = material.get_shader_parameter(&"source_sprite_pivot")
	var pivot_offset := Vector2(0.5 - pivot.x, pivot.y - 0.5)
	var min_corner := Vector2(box.position.x, box.position.y) + pivot_offset
	var max_corner := Vector2(box.end.x, box.end.y) + pivot_offset
	var plane := min_corner.abs().max(max_corner.abs())
	var depth := maxf(absf(box.position.z), absf(box.end.z))
	var stretch := Vector2.ONE
	if float(material.get_shader_parameter(&"source_speed_scale_threshold")) > 0.0:
		var start: Vector2 = material.get_shader_parameter(&"source_speed_scale_min")
		var end: Vector2 = material.get_shader_parameter(&"source_speed_scale_max")
		stretch = start.abs().max(end.abs())
	var curves := Vector2(
		_curve_peak(material, &"has_size_x_curve", &"source_size_x_curve"),
		_curve_peak(material, &"has_size_y_curve", &"source_size_y_curve"))
	var mode := int(material.get_shader_parameter(&"source_pixel_coverage"))
	var use_coverage := mode > 1 or (mode == 0 and not bool(material.get_shader_parameter(&"source_masked")))
	return {&"plane": plane, &"depth": depth, &"stretch": stretch * curves,
		&"camera_offset": absf(float(material.get_shader_parameter(&"source_camera_offset"))),
		&"coverage": use_coverage}

static func launch_bounds(layer: Dictionary, context: Dictionary, shape: Dictionary, radius_curve: Vector2) -> AABB:
	var world: Transform3D = context.world
	var world_scale: Vector3 = context.scale
	var dimensions: Vector3 = context.dimensions
	var shape_scale: Vector3 = layer.spawn_shape_scale
	var radius := maxf(maxf(0.0, context.radius), maxf(layer.spawn_radius_range.x, layer.spawn_radius_range.y))
	var spawn_extent := Vector3.ONE * radius
	if layer.spawn_ring or layer.spawn_disc:
		# The sampler's ring coordinates are independent of its spherical shape scale.
		spawn_extent.x = 0.0
		if layer.spawn_shape_world_space:
			spawn_extent = Vector3(radius, 0.0, radius)
	else:
		spawn_extent *= shape_scale.abs()
	var offset: Vector3 = layer.spawn_offset
	var position := world * (Vector3.ZERO if layer.spawn_offset_world_space else offset)
	if layer.spawn_offset_world_space:
		position += offset * world_scale
	var spawn_box := AABB(position, Vector3.ZERO)
	if radius > 0.0:
		if layer.spawn_shape_world_space:
			var extent := spawn_extent * world_scale
			spawn_box = AABB(position - extent, extent * 2.0)
		else:
			spawn_box = Transform3D(world.basis, position) * AABB(-spawn_extent, spawn_extent * 2.0)
	var max_speed := _max_vector(layer.velocity_min, layer.velocity_max).length()
	max_speed += _max_vector(layer.velocity_add_min, layer.velocity_add_max).length()
	max_speed += _max_abs(layer.radial_speed) + _max_abs(layer.cone_speed)
	var acceleration := _max_vector(layer.gravity_min, layer.gravity_max).length()
	var life := maxf(0.001, maxf(layer.particle_lifetime.x, layer.particle_lifetime.y))
	var steps := maxi(2, ceili(life / STEP))
	var time := steps * STEP
	var distance := _travel_distance(max_speed, acceleration, minf(layer.drag_range.x, layer.drag_range.y), steps, time)
	var jitter := _max_abs(layer.size_scale_range)
	var size := Vector2(_max_abs(layer.width), _max_abs(layer.width if layer.uniform_sprite_size else layer.length))
	size *= Vector2(dimensions.x, dimensions.y) * jitter
	# In each of the two initial-overlap ticks the solver can correct twice,
	# by at most two collision radii each. Later overlap keeps its center.
	var overlap := 4.0 * size.length() * absf(layer.collision_radius_scale) * _max_abs(radius_curve)
	var plane: Vector2 = shape.plane
	var stretch: Vector2 = shape.stretch
	var draw_radius := Vector3(plane.x * size.x * stretch.x, plane.y * size.y * stretch.y, shape.depth).length()
	var pad := (position.abs().length() + distance + draw_radius + 1.0) * 0.000002
	return spawn_box.grow(distance + overlap + draw_radius + float(shape.camera_offset) + pad)

static func _travel_distance(speed: float, acceleration: float, drag: float, steps: int, time: float) -> float:
	# After collision, a partial-step velocity gets projected and the remaining
	# step uses drag again. Do not assume gravity accelerates along the path.
	if drag <= 0.001:
		return speed * time + 0.5 * acceleration * time * (time + STEP)
	var decay := 1.0 / (1.0 + drag * STEP)
	var integrated_decay := (1.0 - pow(decay, steps)) / drag
	var terminal := acceleration / drag
	# Full-step velocities are monotone toward terminal. Using the maximum
	# endpoint speed over each step also covers an early contact projection.
	var end_speed_integral := terminal * time + (speed - terminal) * integrated_decay
	var begin_speed_integral := terminal * time + (speed - terminal) * integrated_decay / decay
	# A split gravity/drag update may keep the pre-projection speed during part
	# of a step, but never exceeds the no-drag gravity increment for that step.
	return maxf(end_speed_integral, begin_speed_integral) + acceleration * time * STEP

static func add_coverage(box: AABB, shape: Dictionary, camera: Camera3D, render_width: float) -> AABB:
	if camera == null or not shape.coverage or camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return box
	var projection := camera.get_camera_projection()
	var transform := camera.get_camera_transform()
	var forward := -transform.basis.z.normalized()
	var farthest := forward.dot(box.get_center() - transform.origin) + forward.abs().dot(box.size * 0.5)
	# The draw shader enlarges both dimensions together to a minimum screen footprint.
	var min_size := maxf(0.0, farthest) * 4.0 / maxf(0.0001, render_width * absf(projection.x.x))
	var plane: Vector2 = shape.plane
	return box.grow(min_size * plane.length())

static func render_width(viewport: Viewport) -> float:
	var visible := viewport.get_visible_rect().size.x
	var target := float(viewport.get_texture().get_width())
	var width := minf(visible, target) if visible > 0.0 and target > 0.0 else maxf(visible, target)
	var scaling := viewport.scaling_3d_scale
	# A scaled render target may round dimensions down before allocating its buffers.
	return maxf(1.0, floorf(width * minf(scaling, 1.0)) - 2.0)

static func _curve_peak(material: ShaderMaterial, enabled: StringName, parameter: StringName) -> float:
	if not material.get_shader_parameter(enabled):
		return 1.0
	var texture := material.get_shader_parameter(parameter) as CurveTexture
	if texture == null or texture.curve == null:
		return 1.0
	var peak := 0.0
	for i in texture.width:
		peak = maxf(peak, absf(texture.curve.sample_baked(float(i) / float(texture.width))))
	return peak

static func _max_abs(values: Vector2) -> float:
	return maxf(absf(values.x), absf(values.y))

static func _max_vector(a: Vector3, b: Vector3) -> Vector3:
	return a.abs().max(b.abs())



