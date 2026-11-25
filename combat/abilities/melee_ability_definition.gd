@tool
class_name MeleeAbilityDefinition
extends "res://combat/abilities/ability_definition.gd"
## Inspector controls for a melee swing that can follow with a second hit.

@export_group("Melee Hit")
## Maximum distance from the caster that the slash can hit, in meters.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:m") var reach := 2.26
## Distance at which enemy AI is allowed to start this attack, in meters.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:m") var start_range := 2.14
## Angle the slash covers on either side of its center line. 46 degrees covers a 92-degree arc.
@export_range(0.0, 180.0, 0.1, "suffix:°") var half_angle := 46.0

@export_group("Double Slash")
## Percent chance to swing a second time after committing the first slash.
@export_range(0.0, 100.0, 0.5, "suffix:%") var double_slash_chance := 25.0
## Base seconds between slashes. The caster's attack speed adjusts this delay.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var follow_up_delay := 0.22

## Multiplier to the encounter's coordination budget when an enemy commits this attack.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:×") var encounter_attack_cost := 0.6


func _validate_property(property: Dictionary) -> void:
	match property["name"]:
		&"id", &"action_key", &"icon_key", &"execution_profile":
			property["usage"] &= ~PROPERTY_USAGE_EDITOR


func runtime_profile() -> Dictionary:
	var profile := super.runtime_profile()
	profile["shape"] = "arc"
	profile["reach"] = reach
	profile["start"] = start_range
	profile["arc"] = half_angle
	profile["attack_cost"] = encounter_attack_cost
	return profile


func roll_follow_up_delay(rng: RandomNumberGenerator) -> float:
	if double_slash_chance >= 100.0:
		return follow_up_delay
	if double_slash_chance > 0.0 and rng.randf() < double_slash_chance / 100.0:
		return follow_up_delay
	return -1.0
