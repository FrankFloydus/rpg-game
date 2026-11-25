@tool
class_name BleedEffectDefinition
extends EffectDefinition
## Reusable Bleed preset. Each resource sets its own chance, duration, and Physical damage.

const DEFAULT_ICON = preload("res://assets/rework/icons/bleed.tres")
const DEFAULT_APPLICATION_EFFECT = preload("res://combat/effects/bleed_application_particles.tscn")

@export_group("Bleed")
## Bleed applies only when a landed hit has a base Physical damage component.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var application_rule: String:
	get:
		return "Landed Physical hit"
## Total Physical damage over the full duration, as a percentage of the triggering hit's base
## Physical damage. Critical strikes and the target's hit defences do not change the base amount.
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:%") var hit_damage_percent := 70.0
## Compatibility for Bleed assets saved before the separate presentation phases.
var application_effect: PackedScene:
	get:
		return on_applied_fx
	set(value):
		on_applied_fx = value


func _init() -> void:
	id = &"bleed"
	display_name = "Bleeding"
	icon = DEFAULT_ICON
	on_applied_fx = DEFAULT_APPLICATION_EFFECT
	damage_type = "physical"
	duration = 5.0
	stacking = StackingPolicy.KEEP_STRONGEST


func requires_physical_hit() -> bool:
	return true


func _validate_property(property: Dictionary) -> void:
	match property["name"]:
		&"id", &"description", &"damage_type", &"tick_interval":
			property["usage"] &= ~PROPERTY_USAGE_EDITOR


func damage_per_second(base_physical_damage: float, damage_bonus_percent := 0.0) -> float:
	if duration <= 0.0:
		return 0.0
	var multiplier := maxf(0.0, 1.0 + damage_bonus_percent * 0.01)
	return maxf(0.0, base_physical_damage) * hit_damage_percent * 0.01 * multiplier / duration


func mitigate_tick(damage: float, physical_dot_reduction_percent: float) -> float:
	return damage * (1.0 - clampf(physical_dot_reduction_percent, 0.0, 100.0) * 0.01)


func tooltip_description() -> String:
	var reapplication := "Only the strongest Bleed deals damage." if stacking == StackingPolicy.KEEP_STRONGEST \
		else "Reapplying Bleed replaces the active Bleed and restarts its timer."
	return "Deals %s%% of the hit's base Physical damage over %s seconds. %s" % [
		String.num(hit_damage_percent, 2).trim_suffix(".0"), String.num(duration, 2).trim_suffix(".0"),
		reapplication,
	]
