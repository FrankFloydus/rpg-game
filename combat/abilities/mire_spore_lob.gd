@tool
extends AbilityDefinition
## Lobs a pod at a committed point on the floor, where it spills lasting poisonous spores.

## Maximum range at which the caster may begin the wind-up.
@export_range(1.0, 20.0, 0.1, "suffix:m") var throw_range := 8.6
## How quickly the pod advances through its arc.
@export_range(2.0, 22.0, 0.1, "suffix:m/s") var flight_speed := 9.0
## Extra height at the center of the trajectory.
@export_range(0.1, 2.0, 0.05, "suffix:m") var arc_height := 0.66
## Landing, warning, and pool all use this one radius.
@export_range(0.4, 3.0, 0.05, "suffix:m") var pool_radius := 1.40
## How long the pool stays hazardous after the pod lands.
@export_range(0.3, 12.0, 0.1, "suffix:s") var pool_seconds := 3.5
## Time between damages while standing in the pool.
@export_range(0.2, 3.0, 0.05, "suffix:s") var tick_interval := 0.70
## Fraction of the original impact damage applied by one pool tick.
@export_range(0.1, 2.0, 0.05, "suffix:×") var tick_damage_multiplier := 0.52


func runtime_profile() -> Dictionary:
	var profile := super.runtime_profile()
	profile["shape"] = "ray"
	profile["reach"] = throw_range
	profile["start"] = throw_range
	profile["speed"] = flight_speed
	return profile
