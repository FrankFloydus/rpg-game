@tool
extends RefCounted

const LevelScaling = preload("res://combat/enemies/enemy_scaling.tres")

static func resolve(base_life: float, base_damage: float, base_move_speed: float,
		approach_factor: float, enemy_level: int, rarity: String,
		affixes: Array[String] = []) -> Dictionary:
	var rarity_health := 1.0
	var rarity_damage := 1.0
	var size_multiplier := 1.0
	match rarity:
		"magic":
			rarity_health = 1.46
			rarity_damage = 1.28
			size_multiplier = 1.10
		"rare":
			rarity_health = 2.27
			rarity_damage = 1.62
			size_multiplier = 1.21
	var life := base_life * rarity_health * LevelScaling.life_multiplier(enemy_level)
	var damage := base_damage * rarity_damage * LevelScaling.damage_multiplier(enemy_level)
	var speed := base_move_speed + LevelScaling.movement_bonus(enemy_level) * approach_factor
	return {
		"life": life * (1.42 if affixes.has("vital") else 1.0),
		"attack_damage": damage * (1.27 if affixes.has("ravaging") else 1.0),
		"move_speed": speed * (1.17 if affixes.has("quick") else 1.0),
		"size_multiplier": size_multiplier,
	}


static func hit_damage(resolved_base_damage: float, ability_damage_multiplier: float) -> float:
	return resolved_base_damage * ability_damage_multiplier
