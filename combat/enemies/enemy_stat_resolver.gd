@tool
extends RefCounted

const LevelScaling = preload("res://combat/enemies/enemy_scaling.tres")

# Original Life values for the archetypes retuned in the level balance pass.
# Checkpoints written before this pass stored current Life alone.
const LEGACY_BASE_LIFE := {
	15: 35.0, # Thornback
	16: 32.0, # Sepulcher Colossus
	17: 20.0, # Hollow Cantor
	18: 23.0, # Chalice Fiend
	19: 40.0, # Dread Knight
}
const LEGACY_LIFE_ANCHORS := [
	Vector2(1, 1.0), Vector2(3, 1.2), Vector2(5, 1.5),
	Vector2(8, 1.95), Vector2(10, 2.22), Vector2(15, 2.72),
	Vector2(20, 3.08), Vector2(30, 3.6), Vector2(50, 4.1),
]
const LEGACY_LATE_LIFE_BONUS := 1.244966976
const LEGACY_LATE_LIFE_SPAN := 51.187212017


static func resolve(base_life: float, base_damage: float, base_move_speed: float,
		approach_factor: float, enemy_level: int, rarity: String,
		affixes: Array[String] = [], depth_multiplier := 1.0) -> Dictionary:
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
	var life := base_life * rarity_health * LevelScaling.life_multiplier(enemy_level) * depth_multiplier
	var damage := base_damage * rarity_damage * LevelScaling.damage_multiplier(enemy_level) * depth_multiplier
	var speed := base_move_speed + LevelScaling.movement_bonus(enemy_level) * approach_factor
	return {
		"life": life * (1.42 if affixes.has("vital") else 1.0),
		"attack_damage": damage * (1.27 if affixes.has("ravaging") else 1.0),
		"move_speed": speed * (1.17 if affixes.has("quick") else 1.0),
		"size_multiplier": size_multiplier,
	}


static func hit_damage(resolved_base_damage: float, ability_damage_multiplier: float) -> float:
	return resolved_base_damage * ability_damage_multiplier


static func restored_life(saved_life: float, saved_max_life: float, current_max_life: float,
		base_life: float, enemy_level: int, archetype_id: int) -> float:
	var previous_max_life := saved_max_life
	if not is_finite(previous_max_life) or previous_max_life <= 0.0:
		var previous_base_life := float(LEGACY_BASE_LIFE.get(archetype_id, base_life))
		# Rarity, affixes and metamorphosis remain in the maximum of the restored phase.
		previous_max_life = current_max_life * previous_base_life / base_life \
			* _legacy_life_multiplier(enemy_level) / LevelScaling.life_multiplier(enemy_level)
	return clampf(saved_life * current_max_life / previous_max_life, 0.1, current_max_life)


static func _legacy_life_multiplier(enemy_level: int) -> float:
	var level := float(maxi(1, enemy_level))
	var lower: Vector2 = LEGACY_LIFE_ANCHORS[0]
	for index in range(1, LEGACY_LIFE_ANCHORS.size()):
		var upper: Vector2 = LEGACY_LIFE_ANCHORS[index]
		if level <= upper.x:
			return lerpf(lower.y, upper.y, inverse_lerp(lower.x, upper.x, level))
		lower = upper
	var extra_levels := level - lower.x
	return lower.y + LEGACY_LATE_LIFE_BONUS * extra_levels / (LEGACY_LATE_LIFE_SPAN + extra_levels)
