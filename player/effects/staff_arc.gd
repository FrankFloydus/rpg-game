extends Node3D
## An authored beam aligned to the two world-space endpoints of the strike.

@onready var _beam: Node3D = $Beam


func _ready() -> void:
	$Lifetime.timeout.connect(queue_free)


func align_to(start: Vector3, end: Vector3, tint: Color) -> void:
	var distance := start.distance_to(end)
	if distance < 0.025:
		queue_free()
		return
	var rotation_basis := Basis(Quaternion(Vector3.UP, start.direction_to(end)))
	global_transform = Transform3D(rotation_basis, start.lerp(end, 0.5))
	_beam.scale.y = distance
	for layer: MeshInstance3D in _beam.get_children():
		layer.set_instance_shader_parameter(&"arc_tint", tint)
	create_tween().tween_method(_fade, 0.0, 1.0, 0.14)


func _fade(age: float) -> void:
	for layer: MeshInstance3D in _beam.get_children():
		layer.set_instance_shader_parameter(&"age", age)
