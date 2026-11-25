extends MultiMeshInstance3D
## Draws the actual boxes submitted by the player's melee sweep.

const ExpeditionRules := preload("res://data/expedition_rules.tres")
const FADE_SECONDS := 0.35
const CAPACITY := 2048
const EDGES := [
	Vector2i(0, 1), Vector2i(1, 3), Vector2i(3, 2), Vector2i(2, 0),
	Vector2i(4, 5), Vector2i(5, 7), Vector2i(7, 6), Vector2i(6, 4),
	Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
]

var _shapes: Array[Transform3D] = []
var _expires := PackedFloat32Array()
var _time := 0.0
var _head := 0
var _count := 0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _box_outline()
	multimesh.instance_count = CAPACITY
	_shapes.resize(CAPACITY)
	_expires.resize(CAPACITY)
	clear()


func draw_box(pose: Transform3D, size: Vector3) -> void:
	var slot := (_head + _count) % CAPACITY
	_shapes[slot] = pose.scaled_local(size)
	_expires[slot] = _time + ExpeditionRules.player_trace_seconds
	if _count == CAPACITY:
		_head = (_head + 1) % CAPACITY
	else:
		_count += 1
	set_process(true)


func clear() -> void:
	_head = 0
	_count = 0
	multimesh.visible_instance_count = 0
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	while _count > 0 and _expires[_head] <= _time:
		_head = (_head + 1) % CAPACITY
		_count -= 1
	if _count == 0:
		clear()
		return
	for index in _count:
		var slot := (_head + index) % CAPACITY
		var tint := Color("#97daf4")
		tint.a = 0.32 * clampf((_expires[slot] - _time) / FADE_SECONDS, 0.0, 1.0)
		multimesh.set_instance_transform(index, _shapes[slot])
		multimesh.set_instance_color(index, tint)
	multimesh.visible_instance_count = _count


static func _box_outline() -> ArrayMesh:
	var corners := PackedVector3Array()
	for index in 8:
		corners.append(Vector3(0.5 if index & 1 else -0.5, 0.5 if index & 2 else -0.5,
			0.5 if index & 4 else -0.5))
	var vertices := PackedVector3Array()
	for edge: Vector2i in EDGES:
		vertices.append(corners[edge.x])
		vertices.append(corners[edge.y])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return result
