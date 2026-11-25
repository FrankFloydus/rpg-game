@tool
class_name EffectApplication
extends Resource
## One effect entry on an ability. All casters using that ability use these values.

const EffectDefinitionScript = preload("res://combat/effects/effect_definition.gd")
const BleedEffectDefinitionScript = preload("res://combat/effects/bleed_effect_definition.gd")

## Shared effect applied by this entry. Edits to that definition affect every ability that uses it.
@export var effect: EffectDefinitionScript:
	set(value):
		if effect != value:
			effect = value
			notify_property_list_changed()
## Percent chance to apply the effect per landed hit, after level and damage requirements are met.
@export_range(0.0, 100.0, 1.0, "suffix:%") var chance := 100.0
## Level required of the caster. Casters without an ability level count as level 1.
@export_range(1, 100, 1, "or_greater") var minimum_caster_level := 1
## Seconds this application lasts. Zero uses the effect definition's default duration.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var duration := 0.0
## Total damage spread across the effect's duration, as a percent of the damage from the triggering hit.
@export_range(0.0, 100.0, 1.0, "or_greater", "suffix:%") var percent_damage := 0.0
## Require a hit that dealt Physical damage. Percent Damage then uses only that portion of the hit.
@export var physical_only := false
## Strength for statuses that use it, such as Chill on enemies. For damage-over-time effects this
## adds flat damage per second on top of Percent Damage.
@export_range(0.0, 100.0, 0.01, "or_greater") var potency := 0.0


func resolved_duration() -> float:
	if effect is BleedEffectDefinitionScript:
		return effect.duration
	if duration > 0.0:
		return duration
	return effect.duration if effect != null else 0.0


func _validate_property(property: Dictionary) -> void:
	if effect is BleedEffectDefinitionScript:
		match property["name"]:
			&"duration", &"percent_damage", &"physical_only", &"potency":
				property["usage"] &= ~PROPERTY_USAGE_EDITOR
