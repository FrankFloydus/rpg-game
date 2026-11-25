extends MeshInstance3D
## A short-lived outline of an enemy ability's hit check in the Training Ground.

const DURATION := 2.0
const FADE_DURATION := 0.4
const STROKE_HALF_WIDTH := 0.018
const HIT_COLOR := Color("#8df0a2")
const MISS_COLOR := Color("#efb56e")
const PATH_COLOR := Color("#8adce9")


static func draw(parent: Node3D, data: Dictionary) -> void:
	var origin: Vector3 = data["origin"]
	var outline := SurfaceTool.new()
	outline.begin(Mesh.PRIMITIVE_TRIANGLES)
	if not _draw_shape(outline, data, origin):
		return

	var color := PATH_COLOR
	if data.has("hit"):
		color = HIT_COLOR if data["hit"] else MISS_COLOR
	color.a = 0.82
	var ink := StandardMaterial3D.new()
	ink.roughness = 1.0
	ink.metallic_specular = 0.0
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	ink.albedo_color = color
	ink.render_priority = 1

	var trace := new()
	trace.name = "TrainingAbilityTrace"
	trace.top_level = true
	trace.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trace.mesh = outline.commit()
	trace.material_override = ink
	parent.add_child(trace)
	trace.global_position = origin
	var fade := trace.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	fade.tween_interval(DURATION - FADE_DURATION)
	fade.tween_property(ink, "albedo_color:a", 0.0, FADE_DURATION)
	fade.tween_callback(trace.queue_free)


static func _draw_shape(outline: SurfaceTool, data: Dictionary, origin: Vector3) -> bool:
	var shape := String(data["shape"])
	if shape == "line":
		var endpoint: Vector3 = data["end"]
		var offset := endpoint - origin
		if offset.is_zero_approx():
			return false
		# Crossed ribbons make a world-space trajectory readable from above and from the side.
		var bearing := offset.normalized()
		var lateral := bearing.cross(Vector3.UP).normalized()
		if lateral.is_zero_approx():
			lateral = Vector3.RIGHT
		_stroke(outline, Vector3.ZERO, offset, lateral)
		_stroke(outline, Vector3.ZERO, offset, bearing.cross(lateral))
		return true

	var reach := float(data.get("reach", 0.0))
	if reach <= 0.0:
		return false
	var forward: Vector3 = data.get("direction", Vector3.FORWARD)
	forward.y = 0.0
	forward = Vector3.FORWARD if forward.is_zero_approx() else forward.normalized()
	match shape:
		"disc":
			_arc(outline, forward, reach, PI)
		"arc":
			_arc(outline, forward, reach, deg_to_rad(clampf(float(data["angle"]), 0.0, 180.0)))
		"lane":
			var half_width := float(data.get("width", 0.0))
			if half_width <= 0.0:
				return false
			var side := forward.cross(Vector3.UP) * half_width
			var far_edge := forward * reach
			_ground_stroke(outline, -side, side)
			_ground_stroke(outline, side, far_edge + side)
			_ground_stroke(outline, far_edge + side, far_edge - side)
			_ground_stroke(outline, far_edge - side, -side)
		_:
			return false
	return true


static func _arc(outline: SurfaceTool, forward: Vector3, reach: float, half_angle: float) -> void:
	var previous := forward.rotated(Vector3.UP, -half_angle) * reach
	var has_sides := half_angle < PI
	if has_sides:
		_ground_stroke(outline, Vector3.ZERO, previous)
	var segments := maxi(1, ceili(half_angle * 2.0 / deg_to_rad(7.5)))
	for index in range(1, segments + 1):
		var angle := lerpf(-half_angle, half_angle, float(index) / segments)
		var point := forward.rotated(Vector3.UP, angle) * reach
		_ground_stroke(outline, previous, point)
		previous = point
	if has_sides and half_angle > 0.0:
		_ground_stroke(outline, previous, Vector3.ZERO)


static func _ground_stroke(outline: SurfaceTool, from: Vector3, to: Vector3) -> void:
	var lateral := (to - from).cross(Vector3.UP).normalized()
	if not lateral.is_zero_approx():
		_stroke(outline, from, to, lateral)


static func _stroke(outline: SurfaceTool, from: Vector3, to: Vector3, lateral: Vector3) -> void:
	var edge := lateral * STROKE_HALF_WIDTH
	outline.add_vertex(from - edge)
	outline.add_vertex(from + edge)
	outline.add_vertex(to + edge)
	outline.add_vertex(from - edge)
	outline.add_vertex(to + edge)
	outline.add_vertex(to - edge)
