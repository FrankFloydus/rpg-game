@tool
extends Resource
## Grammar and original word lists for rare enemy names.

const NamePool := preload("res://data/enemy_name_pool.gd")

## Family pools before the general fallback; the first matching family is used.
@export var pools: Array[NamePool]
## Chance that a Rare with at least two affixes also gains one of its family's titles.
@export_range(0.0, 1.0, 0.01) var titled_elite_chance := 0.40


func rare_name(family: String, spawn_seed: int, archetype_id: int, affix_count: int, fallback: String) -> String:
	var pool := _pool_for(family)
	if pool == null or pool.beginnings.is_empty() or pool.endings.is_empty():
		return fallback
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([spawn_seed, archetype_id, &"rare enemy name"])
	var name := pool.beginnings[rng.randi_range(0, pool.beginnings.size() - 1)]
	name += pool.endings[rng.randi_range(0, pool.endings.size() - 1)]
	if affix_count >= 2 and not pool.titles.is_empty() and rng.randf() < titled_elite_chance:
		name += " " + pool.titles[rng.randi_range(0, pool.titles.size() - 1)]
	return name


func _pool_for(family: String) -> NamePool:
	var fallback: NamePool
	for pool: NamePool in pools:
		if pool == null:
			continue
		if pool.families.has(family):
			return pool
		if pool.families.is_empty():
			fallback = pool
	return fallback
