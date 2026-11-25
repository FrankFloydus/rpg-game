@tool
class_name EffectDefinition
extends Resource
## Shared behavior and presentation of an effect, independent of the ability applying it.

enum StackingPolicy { REFRESH, KEEP_STRONGEST }

## Unique status ID. Applications with the same ID reapply the same status on a target.
@export var id: StringName
## Name displayed when the effect is applied and in damage-over-time Combat Log entries.
@export var display_name: String
## Optional Bestiary texture. Leave empty to use the built-in icon for this effect.
@export var icon: Texture2D
## Player-facing explanation of the status for Bestiary and ability tooltips.
@export_multiline var description: String
## Treat this effect as a buff when displaying it on a player’s status row.
@export var beneficial := false
@export_group("Application")
## Percent chance this preset applies when a qualifying hit lands.
@export_range(0.0, 100.0, 0.5, "suffix:%") var chance := 100.0
## How many seconds this preset remains active after it applies.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var duration := 2.6
## Refresh replaces the active application's strength and duration. Keep Strongest preserves the
## current strength and timer against weaker applications. Equal or stronger ones replace it.
@export var stacking: StackingPolicy = StackingPolicy.REFRESH
## Type of damage dealt by each tick. Leave empty for a status without damage over time.
@export var damage_type: String
## Seconds between damage ticks while the effect is active.
@export_range(0.01, 5.0, 0.01, "or_greater", "suffix:s") var tick_interval := 0.20

@export_group("Presentation")
## One-shot 3D scene played on the target when the status is successfully applied or refreshed.
@export var on_applied_fx: PackedScene
## Looping 3D scene attached to the target until the status ends. Refresh reuses the same scene instance.
@export var while_active_fx: PackedScene
## Optional enemy-only loop. Keeps combat particles outside the player's first-person camera.
@export var enemy_while_active_fx: PackedScene
## One-shot 3D scene played on the target when the status leaves its active slot.
@export var on_end_fx: PackedScene


func minimum_on_hit_level() -> int:
	return 1


func requires_physical_hit() -> bool:
	return false


func on_hit_potency(_hit_damage: float) -> float:
	return 0.0


func replaces(current_potency: float, incoming_potency: float) -> bool:
	return stacking == StackingPolicy.REFRESH or incoming_potency >= current_potency


func tooltip_description() -> String:
	return description


func legacy_definition() -> Dictionary:
	var result := {
		"name": display_name,
		"duration": duration,
		"damage_type": damage_type,
	}
	if not display_name.is_empty():
		result["bestiary"] = {"name": display_name, "tooltip": tooltip_description()}
	return result
