@tool
class_name ChillEffectDefinition
extends EffectDefinition
## A timed movement slow.

## Multiplier applied to movement while Chilled. A value of 0.71 means 29% slower movement.
@export_range(0.0, 1.0, 0.01) var movement_speed_multiplier := 0.71


func on_hit_potency(_total_damage: float) -> float:
	return 1.0 - movement_speed_multiplier
