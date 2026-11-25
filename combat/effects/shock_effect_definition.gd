@tool
class_name ShockEffectDefinition
extends EffectDefinition
## A timed increase to damage taken from hits.

## Multiplier applied to hit damage taken while Shocked. A value of 1.22 means 22% more damage.
@export_range(1.0, 5.0, 0.01, "or_greater") var damage_taken_multiplier := 1.22


func on_hit_potency(_total_damage: float) -> float:
	return damage_taken_multiplier - 1.0
