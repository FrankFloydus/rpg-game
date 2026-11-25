@tool
class_name EnrageEffectDefinition
extends EffectDefinition
## Reusable outgoing damage and attack speed bonuses while Enrage is active.

## Percent added to the rate at which attack timing advances. A bonus of 15 runs the attack clock at 1.15 times normal speed.
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:%") var attack_speed_bonus_percent := 15.0
## Percent more attack damage dealt while enraged. A bonus of 15 multiplies each attack hit by 1.15.
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:%") var damage_bonus_percent := 15.0


func attack_speed_factor() -> float:
	return 1.0 + attack_speed_bonus_percent / 100.0


func damage_factor() -> float:
	return 1.0 + damage_bonus_percent / 100.0
