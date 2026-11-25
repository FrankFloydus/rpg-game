@tool
class_name DamageOverTimeEffectDefinition
extends EffectDefinition
## An ailment whose total damage is a percentage of the hit that applies it.

## Percentage of dealt hit damage spread over the effect's full duration.
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:%") var hit_damage_percent := 41.6


func on_hit_potency(hit_damage: float) -> float:
	return maxf(0.0, hit_damage) * hit_damage_percent * 0.01 / duration if duration > 0.0 else 0.0
