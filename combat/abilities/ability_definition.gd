@tool
class_name AbilityDefinition
extends Resource
## Authored combat data shared by everyone who equips this ability.


## Stable, unique ability ID. Abilities with the same ID share a cooldown on a single caster.
@export var id: StringName
## Name shown in the Bestiary, feedback, and Combat Log.
@export var display_name: String
## Optional texture for the Bestiary. Leave empty to use the built-in art selected by Icon Key.
@export var icon: Texture2D
## Built-in Bestiary art key, such as [code]cut[/code], [code]slam[/code], or [code]cobweb[/code].
@export var icon_key: String
## Player-facing explanation of the move. The Bestiary and Combat Log include this text in tooltips.
@export_multiline var description: String

@export_group("Activation")
## Mana spent when the ability commits. Zero makes the move free.
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:Mana") var mana_cost := 0.0
## Seconds from commit until this caster can use the ability again. Each caster tracks its own timer.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var cooldown := 0.0

@export_group("Execution")
## Execution category for weapon moves and special abilities, such as [code]weapon_melee[/code] or
## [code]cobweb[/code]. Ordinary attacks use the shape specified in Execution Profile.
@export var action_key: String
## Type of the primary hit. Leave empty to use the caster's default damage type.
@export var damage_type: String
## Primary attribute that scales this ability's base damage. Weapon moves can inherit their weapon's attribute.
@export_enum("default", "strength", "dexterity", "intelligence") var scaling_attribute := "default"
## Base seconds from enemy cast start to release. Playback follows this interval without changing
## the animation's poses. Floor warnings extend it when needed to leave enough time to walk clear.
## Weapon attacks use their AnimationPlayer markers and the Attack tempo settings in Weapons & Player.
@export_range(0.0, 20.0, 0.01, "or_greater", "suffix:s") var windup := 0.0
## Base seconds spent recovering after the attack resolves. The caster cannot start the next
## attack during this window. This can overlap the cooldown. Weapon attacks use their clip timing.
@export_range(0.0, 20.0, 0.01, "or_greater", "suffix:s") var recovery := 0.0
## Multiplies the caster's base hit damage. A value of 1 keeps the base amount.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:x") var damage_multiplier := 1.0
## Shape-specific settings. [code]start[/code] is the enemy's attack trigger distance in meters.
## [code]arc[/code] uses [code]reach[/code] in meters and [code]arc[/code] in degrees from the center line.
## [code]disc[/code] uses [code]reach[/code] for radius and [code]offset[/code] for distance ahead, both in meters.
## [code]lane[/code] uses [code]reach[/code], [code]width[/code] as half-width, and [code]dash_speed[/code] in m/s.
## [code]ray[/code] uses [code]reach[/code] and [code]speed[/code] in m/s, with optional [code]spread[/code]
## in degrees or [code]second[/code] for the delay in seconds before a follow-up shot.
## Set [code]floor_warning[/code] to [code]always[/code] to draw a ground warning during enemy windup.
@export var execution_profile: Dictionary = {}

@export_group("Stun")
## Points added toward the target's stun threshold on an eligible landed hit.
## Leave at zero for abilities that do not build stun. Standard weapon attacks inherit their weapon's buildup.
@export_range(0.0, 200.0, 0.5, "or_greater") var stun_buildup := 0.0
## Protects this ability's active cast and release against stun on both players and enemies.
@export var uninterruptible := false

@export_group("Impact")
## Initial horizontal push speed when this ability lands a damaging hit on the player.
## Leave at zero for ordinary attacks. A block prevents the push.
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var knockback_speed := 0.0

@export_group("Presentation")
## Optional one-shot visual for a confirmed hit.
@export var hit_fx: PackedScene

@export_group("On Hit")
## Effect presets attempted on each landed hit. Create an effect here or select an existing preset
## to reuse its chance, duration, and strength. This list is shared by everyone using the ability.
@export var on_hit_effects: Array[EffectDefinition] = []


func runtime_profile() -> Dictionary:
	var profile := execution_profile.duplicate(true)
	profile["windup"] = windup
	profile["recovery"] = recovery
	profile["damage"] = damage_multiplier
	profile["cooldown"] = cooldown
	return profile


func roll_follow_up_delay(_rng: RandomNumberGenerator) -> float:
	return -1.0


func combat_details() -> Dictionary:
	return {"id": id, "name": display_name, "description": description, "definition": self}
