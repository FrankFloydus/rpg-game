@tool
extends Node3D
## Bounds of a recessed water surface. Its occupied volume extends downward.

## Full width, depth below the surface, and length, measured in local space.
@export var extent := Vector3.ONE:
	set(value):
		extent = value
		if is_node_ready():
			_update_surface()


func _ready() -> void:
	_update_surface()


func configure(size: Vector3) -> void:
	extent = size


func _update_surface() -> void:
	var plane := $Surface.mesh.duplicate() as PlaneMesh
	plane.size = Vector2(extent.x, extent.z)
	$Surface.mesh = plane
	$BasinBounce.position.y = -extent.y * 0.56


func contains(point: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var local := to_local(point)
	return (absf(local.x) <= extent.x * 0.5 and absf(local.z) <= extent.z * 0.5
		and local.y <= 0.0 and local.y >= -extent.y)
