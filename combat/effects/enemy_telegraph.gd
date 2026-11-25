extends RefCounted

const TelegraphScene = preload("res://combat/effects/enemy_telegraph.tscn")
const PLANE_EXTENT := 1.08
const FLOOR_LIFT := 0.063
const BOX_WARNING := 1
const RING_WARNING := 2

static var _meshes: Dictionary = {}


static func make_node() -> MeshInstance3D:
	return TelegraphScene.instantiate() as MeshInstance3D


## The origin and dimensions use the same ground coordinates as [method contains].
static func present(warning: MeshInstance3D, profile: Dictionary, origin: Vector3,
		direction := Vector3.FORWARD) -> void:
	var facing := _horizontal_direction(direction)
	var center := origin + Vector3.UP * FLOOR_LIFT
	var reach := float(profile["reach"])
	var extent := Vector3(reach, 1.0, reach)
	var shader_shape := 0
	var inner_fraction := 0.0
	match profile["shape"]:
		"lane":
			shader_shape = BOX_WARNING
			center += facing * reach * 0.5
			extent = Vector3(float(profile["width"]), 1.0, reach * 0.5)
		"ring":
			shader_shape = RING_WARNING
			inner_fraction = clampf(float(profile["inner_radius"]) / reach, 0.0, 0.99)
	warning.mesh = shape(profile)
	warning.global_position = center
	warning.rotation = Vector3(0.0, atan2(-facing.x, -facing.z), 0.0)
	warning.scale = extent
	warning.set_instance_shader_parameter("shape_kind", shader_shape)
	warning.set_instance_shader_parameter("ring_inner", inner_fraction)
	set_progress(warning, 0.0)
	warning.show()


static func set_progress(warning: MeshInstance3D, fraction: float) -> void:
	warning.set_instance_shader_parameter("windup", clampf(fraction, 0.0, 1.0))


## Ground-plane contact. The caller decides whether the target is on the same floor.
static func contains(profile: Dictionary, origin: Vector3, direction: Vector3, point: Vector3) -> bool:
	var delta := point - origin
	var offset := Vector3(delta.x, 0.0, delta.z)
	var facing := _horizontal_direction(direction)
	var reach := float(profile["reach"])
	if profile["shape"] == "lane":
		var forward := offset.dot(facing)
		return (forward >= 0.0 and forward <= reach
			and absf(offset.dot(facing.cross(Vector3.UP))) <= float(profile["width"]))
	var distance_squared := offset.length_squared()
	if distance_squared > reach * reach:
		return false
	match profile["shape"]:
		"arc":
			var alignment := cos(deg_to_rad(float(profile["arc"])))
			return distance_squared < 0.01 or offset.normalized().dot(facing) >= alignment
		"ring":
			var inner := float(profile["inner_radius"])
			return distance_squared >= inner * inner
	return true


## A conservative distance from the deepest part of a footprint to an available edge.
static func escape_distance(profile: Dictionary) -> float:
	var reach := float(profile["reach"])
	match profile["shape"]:
		"lane":
			return minf(reach * 0.5, float(profile["width"]))
		"ring":
			return maxf(0.0, (reach - float(profile["inner_radius"])) * 0.5)
	return reach


static func _horizontal_direction(value: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	return Vector3.FORWARD if flat.is_zero_approx() else flat.normalized()


static func shape(profile: Dictionary) -> Mesh:
	var arc := float(profile.get("arc", 0.0)) if profile["shape"] == "arc" else 0.0
	if _meshes.has(arc):
		return _meshes[arc]

	# A little room around the actual footprint lets the border soften into the floor.
	# UVs carry local X/forward coordinates, so the fill stays radial on the floor.
	var half_plane := Vector2.ZERO
	if arc > 0.0:
		half_plane = Vector2(cos(deg_to_rad(arc)), -sin(deg_to_rad(arc)))
	var corners := [
		Vector2(-PLANE_EXTENT, -PLANE_EXTENT), Vector2(PLANE_EXTENT, -PLANE_EXTENT),
		Vector2(PLANE_EXTENT, PLANE_EXTENT), Vector2(-PLANE_EXTENT, PLANE_EXTENT),
	]
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0, 1, 2, 0, 2, 3]:
		var point: Vector2 = corners[index]
		builder.set_uv(point)
		builder.set_uv2(half_plane)
		builder.add_vertex(Vector3(point.x, 0.0, -point.y))

	var mesh := builder.commit()
	_meshes[arc] = mesh
	return mesh
