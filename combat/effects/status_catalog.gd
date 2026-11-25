extends RefCounted

const EffectDefinitionScript = preload("res://combat/effects/effect_definition.gd")

const DEFAULT_DURATION := 2.6
const ENEMY_DAMAGE_TICK := 0.20

const _ROOTED_EFFECT = preload("res://combat/effects/rooted.tres")

const ROOTED := {"name": _ROOTED_EFFECT.display_name, "duration": _ROOTED_EFFECT.duration}

const _EFFECTS := {
	"bleed": preload("res://combat/effects/bleed.tres"),
	"poisoned": preload("res://combat/effects/poisoned.tres"),
	"burning": preload("res://combat/effects/burning.tres"),
	"chilled": preload("res://combat/effects/chilled.tres"),
	"shocked": preload("res://combat/effects/shocked.tres"),
	"dread": preload("res://combat/effects/dread.tres"),
	"rooted": _ROOTED_EFFECT,
	"stunned": preload("res://combat/effects/stunned.tres"),
}


static func get_effect(status_id: String) -> EffectDefinitionScript:
	return _EFFECTS.get(status_id) as EffectDefinitionScript


static func definition(status_id: String) -> Dictionary:
	var effect := get_effect(status_id)
	return effect.legacy_definition() if effect != null else {}
