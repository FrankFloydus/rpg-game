@tool
extends Resource
## Keeps committed floor warnings avoidable on foot when the player has an open escape route.

## Extra space to leave outside a hit boundary. The default also clears the player's body.
@export_range(0.0, 2.0, 0.01, "suffix:m") var edge_clearance_meters := 0.36
## Extra seconds to see the warning at its first visible frame, in addition to the walk itself.
@export_range(0.0, 1.0, 0.01, "suffix:s") var minimum_read_seconds := 0.12


func warning_seconds(authored_seconds: float, escape_distance: float, player: Node3D) -> float:
	if not is_instance_valid(player) or not player.has_method("warning_walk_profile"):
		return authored_seconds
	var walk: Vector2 = player.warning_walk_profile()
	var distance := escape_distance + edge_clearance_meters
	var acceleration_time := walk.x / walk.y
	var acceleration_distance := 0.5 * walk.y * acceleration_time * acceleration_time
	var escape_seconds := sqrt(2.0 * distance / walk.y)
	if distance > acceleration_distance:
		escape_seconds = acceleration_time + (distance - acceleration_distance) / walk.x
	# One tick can start the cast before the warning is rendered. Another can pass before movement.
	var physics_slack := 2.0 / float(Engine.physics_ticks_per_second)
	return maxf(authored_seconds, escape_seconds + minimum_read_seconds + physics_slack)
