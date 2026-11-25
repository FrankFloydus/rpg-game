extends RefCounted
## Resolves authored effect presets after the caster confirms a hit.

const DefaultBleed = preload("res://combat/effects/bleed.tres")


static func apply_on_hit(effects: Array, target: Node, physical_damage: float, total_damage: float,
		source: Node, context: Dictionary, rng: RandomNumberGenerator, base_physical_damage := 0.0,
		forced_bleed := false) -> bool:
	if not is_instance_valid(target) or not target.has_method("receive_combat_effect"):
		return false
	var caster_level := 1
	if is_instance_valid(source) and source.has_method("combat_ability_level"):
		caster_level = maxi(1, int(source.combat_ability_level()))
	var granted_bleed_chance := 100.0 if forced_bleed else 0.0
	var bleed_damage_bonus := 0.0
	if base_physical_damage > 0.0 and is_instance_valid(source):
		if source.has_method("combat_bleed_chance"):
			granted_bleed_chance += source.combat_bleed_chance()
		if source.has_method("combat_bleed_damage_bonus"):
			bleed_damage_bonus = source.combat_bleed_damage_bonus()

	var applied := false
	for effect: EffectDefinition in effects:
		if effect == null or effect.duration <= 0.0 or caster_level < effect.minimum_on_hit_level():
			continue
		if effect is BleedEffectDefinition:
			var chance := effect.chance + granted_bleed_chance
			granted_bleed_chance = 0.0
			if _apply_bleed(effect, chance, base_physical_damage, bleed_damage_bonus, target, source, context, rng):
				applied = true
			continue
		if effect.requires_physical_hit() and physical_damage <= 0.0:
			continue
		var potency := effect.on_hit_potency(physical_damage if effect.requires_physical_hit() else total_damage)
		var effect_context := context
		if not effect.damage_type.is_empty():
			effect_context = context.merged({"potency_includes_level_gap": true}, true)
		if (effect.damage_type.is_empty() or potency > 0.0) and _roll_chance(effect.chance, rng) \
				and target.receive_combat_effect(effect, effect.duration, potency, source, effect_context):
			applied = true
	if granted_bleed_chance > 0.0 and _apply_bleed(DefaultBleed, granted_bleed_chance, base_physical_damage,
			bleed_damage_bonus, target, source, context, rng):
		applied = true
	return applied


static func _apply_bleed(effect: BleedEffectDefinition, chance: float, base_physical_damage: float,
		damage_bonus: float, target: Node, source: Node, context: Dictionary, rng: RandomNumberGenerator) -> bool:
	if base_physical_damage <= 0.0:
		return false
	var potency := effect.damage_per_second(base_physical_damage, damage_bonus)
	return potency > 0.0 and _roll_chance(chance, rng) \
		and target.receive_combat_effect(effect, effect.duration, potency, source, context)


static func _roll_chance(chance: float, rng: RandomNumberGenerator) -> bool:
	return chance >= 100.0 or (chance > 0.0 and rng != null and rng.randf() * 100.0 < chance)
