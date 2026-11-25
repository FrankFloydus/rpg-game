@tool
extends Resource
## Shared stat scaling for any progression system that spawns enemies by level.

@export_group("Level Scaling")
## X is enemy level. Y multiplies Base Life before rarity and affixes.
## A Y value of 1.0 preserves Base Life at that level.
@export var life_by_level: Curve
## X is enemy level. Y multiplies Base Attack Damage before rarity, affixes, and the ability
## multiplier. A Y value of 1.0 preserves Base Attack Damage at that level.
@export var damage_by_level: Curve
## X is enemy level. Y adds speed to Base Move Speed in meters per second.
## A Y value of 0.0 adds no speed at that level.
@export var movement_bonus_by_level: Curve
## X is enemy level. Y multiplies the ability's windup time.
## Values below 1.0 shorten the windup. Values above 1.0 lengthen it.
@export var attack_windup_by_level: Curve
## X is enemy level. Y multiplies recovery after attacks with a windup.
## The ability's cooldown is a separate timer.
@export var attack_recovery_by_level: Curve

@export_group("Projectile Scaling")
## X is enemy level. Y multiplies the ability's projectile travel speed.
## A Y value of 1.0 preserves the authored speed.
@export var projectile_speed_by_level: Curve
## X is enemy level. Y scales the lead for projectile flight after release.
## A Y value of 0.0 aims at the predicted release position without leading the flight.
@export var projectile_lead_by_level: Curve
## X is enemy level. Y caps the predicted distance ahead of the target in meters.
@export var projectile_lead_limit_by_level: Curve

@export_group("Beyond the Last Curve Level")
## Amount added to the final Life multiplier as enemy level rises beyond the last point.
## The adjustment approaches this amount gradually. Zero holds the final curve value.
@export_range(0.0, 100.0, 0.1, "or_greater") var life_late_bonus := 0.0
## Levels beyond the final curve point needed to reach half of the Life Late Bonus.
@export_range(1.0, 200.0, 0.1, "or_greater", "suffix: levels") var life_late_span := 50.0
## Amount added to the final damage multiplier as enemy level rises beyond the last point.
## The adjustment approaches this amount gradually. Zero holds the final curve value.
@export_range(0.0, 20.0, 0.01, "or_greater") var damage_late_bonus := 0.0
## Levels beyond the final curve point needed to reach half of the Damage Late Bonus.
@export_range(1.0, 200.0, 0.1, "or_greater", "suffix: levels") var damage_late_span := 50.0


func life_multiplier(enemy_level: int) -> float:
	return _sample_with_late_bonus(life_by_level, enemy_level, life_late_bonus, life_late_span)


func damage_multiplier(enemy_level: int) -> float:
	return _sample_with_late_bonus(damage_by_level, enemy_level, damage_late_bonus, damage_late_span)


func movement_bonus(enemy_level: int) -> float:
	return _sample(movement_bonus_by_level, enemy_level, 0.0)


func windup_multiplier(enemy_level: int) -> float:
	return _sample(attack_windup_by_level, enemy_level, 1.0)


func recovery_multiplier(enemy_level: int) -> float:
	return _sample(attack_recovery_by_level, enemy_level, 1.0)


func projectile_speed_multiplier(enemy_level: int) -> float:
	return _sample(projectile_speed_by_level, enemy_level, 1.0)


func projectile_lead_factor(enemy_level: int) -> float:
	return _sample(projectile_lead_by_level, enemy_level, 0.96)


func projectile_lead_limit(enemy_level: int) -> float:
	return _sample(projectile_lead_limit_by_level, enemy_level, 3.6)


func _sample_with_late_bonus(curve: Curve, enemy_level: int, bonus: float, span: float) -> float:
	if curve == null or curve.point_count == 0:
		return 1.0
	var extra_levels := maxf(0.0, float(enemy_level) - curve.get_point_position(curve.point_count - 1).x)
	return _sample(curve, enemy_level, 1.0) + bonus * extra_levels / (maxf(1.0, span) + extra_levels)


func _sample(curve: Curve, enemy_level: int, fallback: float) -> float:
	if curve == null or curve.point_count == 0:
		return fallback
	return curve.sample(clampf(float(maxi(1, enemy_level)), curve.min_domain, curve.max_domain))
