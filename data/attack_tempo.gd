@tool
extends Resource
## Converts authored attack timings to the single wall-clock rate used by the player.

## Upper limit after item attack speed, temporary weapon haste, and Enrage are combined.
@export_range(1.0, 3.0, 0.01, "suffix:x") var maximum_effective_rate := 1.60

## Weapon attack speed granted while Soul Hunger is active.
@export_range(0.0, 100.0, 0.5, "suffix:%") var soul_hunger_attack_speed := 34.0


func weapon_rate(item_attack_speed: float, soul_hunger: bool, enrage: float) -> float:
	var bonus := item_attack_speed + (soul_hunger_attack_speed if soul_hunger else 0.0)
	return capped_rate(maxf(0.25, 1.0 + bonus * 0.01) * enrage)


func capped_rate(rate: float) -> float:
	return clampf(rate, 0.25, maximum_effective_rate)
