extends Node3D
## A walkable half-flight. Its sealed far landing joins the reversed flight on the adjacent floor.

signal passed(body: Node3D)

const LENGTH := 6.4
const RISE := 2.16
const JOIN_DEPTH := 5.42
const JOIN_DISTANCE_FROM_LANDING := 5.72 - JOIN_DEPTH

var _direction := 1


func configure(direction: int, _destination_floor: int, continuous := false) -> void:
	_direction = direction
	if direction > 0:
		$Flight.position = Vector3(0.0, -RISE, -LENGTH)
		$Flight.rotation.y = PI
		# The facing half mounts its torch against the other side of the joined shaft.
		$Flight/StairSconce.position.x = absf($Flight/StairSconce.position.x)
		$Flight/StairSconce.rotation.y = -absf($Flight/StairSconce.rotation.y)
	$Landing.position.y = -float(direction) * RISE
	if continuous:
		$Landing/FarAshlar.free()
		$Landing/Blocker.free()
		$Landing/Threshold.free()


func _ready() -> void:
	var threshold := get_node_or_null("Landing/Threshold") as Area3D
	if threshold != null:
		threshold.body_entered.connect(passed.emit)


func landing_endpoint() -> Vector3:
	return transform * Vector3(0.0, -_direction * RISE, -LENGTH)


func arrival_point(lateral_offset: float) -> Vector3:
	var height := -RISE * _direction + _direction * JOIN_DISTANCE_FROM_LANDING * RISE / 5.04
	var point := Vector3(clampf(-lateral_offset, -1.0, 1.0), height + 0.09, -JOIN_DEPTH)
	return to_global(point)
