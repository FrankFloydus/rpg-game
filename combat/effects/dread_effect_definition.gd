@tool
class_name DreadEffectDefinition
extends EffectDefinition
## A Physical hit can prevent sprinting when the attacker is strong enough.

## Lowest caster level that can inflict Dread.
@export_range(1, 100, 1, "or_greater") var minimum_caster_level := 4


func minimum_on_hit_level() -> int:
	return minimum_caster_level


func requires_physical_hit() -> bool:
	return true
