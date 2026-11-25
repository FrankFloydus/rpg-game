class_name CharacterProgression
extends RefCounted
## Campaign level, experience, and the character's allocated primary attributes.

const MAX_LEVEL := 100
const ATTRIBUTE_IDS: Array[StringName] = [&"strength", &"dexterity", &"intelligence"]
const BALANCE_DATA := preload("res://data/player_progression_records.tres")

static var BALANCE: Resource:
	get:
		return BALANCE_DATA

var level: int:
	get:
		return _level
var xp: int:
	get:
		return _xp

var _level := 1
var _xp := 0
var _highest_cleared_depth := 0
var _attributes: Dictionary[StringName, int] = {}


func xp_for_next_level() -> int:
	return _xp_cost(level) if level < MAX_LEVEL else 0


func points_available() -> int:
	var spent := 0
	for value: int in _attributes.values():
		spent += value
	return level - 1 - spent


func attribute(id: StringName) -> int:
	return _attributes.get(id, 0)


func allocate(id: StringName, amount := 1) -> bool:
	if not ATTRIBUTE_IDS.has(id) or amount < 1 or amount > points_available():
		return false
	_attributes[id] = attribute(id) + amount
	return true


func reset_attributes() -> void:
	_attributes.clear()


func max_life() -> float:
	var points: Array[Vector2] = BALANCE.life_by_level
	var lower: Vector2 = points[0]
	if float(level) <= lower.x:
		return lower.y
	for index in range(1, points.size()):
		var upper: Vector2 = points[index]
		if float(level) <= upper.x:
			return lerpf(lower.y, upper.y, inverse_lerp(lower.x, upper.x, float(level)))
		lower = upper
	return lower.y


func max_stamina_bonus() -> float:
	return attribute(&"strength") * BALANCE.stamina_per_strength


func max_mana_bonus() -> float:
	return attribute(&"intelligence") * BALANCE.mana_per_intelligence


func base_damage_multiplier(id: StringName) -> float:
	return 1.0 + attribute(id) * BALANCE.damage_per_point


func critical_chance_bonus(id: StringName) -> float:
	return attribute(&"dexterity") * BALANCE.critical_chance_per_dexterity if id == &"dexterity" else 0.0


## Awards experience for a combat kill. Training should never call this on the campaign model.
func award_kill(enemy_level: int, rarity: String) -> int:
	if enemy_level < 1 or enemy_level <= level - BALANCE.trivial_level_gap or level >= MAX_LEVEL:
		return 0
	var reward_level := mini(enemy_level, MAX_LEVEL)
	var population := mini(BALANCE.max_expected_enemies, BALANCE.base_expected_enemies + 6 * (reward_level - 1))
	var relevance := minf(1.5, 1.0 + float(enemy_level - level) * 0.16)
	var rarity_multiplier := float(BALANCE.kill_rarity_xp.get(rarity, 1.0))
	var award: float = _xp_cost(reward_level) * BALANCE.kill_xp_share / float(population) * relevance * rarity_multiplier
	return _grant_xp(maxi(1, roundi(award)))


## The first clear of a newly reached Depth helps prepare the character for the next unlocked gate.
## A repeat clear grants no completion bonus. Kills on a repeated run still use normal relevance.
func award_clear(depth: int) -> int:
	if depth <= _highest_cleared_depth:
		return 0
	_highest_cleared_depth = depth
	if level >= MAX_LEVEL:
		return 0
	var goal := mini(depth + 1, MAX_LEVEL)
	var catchup := -xp
	for skipped_level in range(level, goal):
		catchup += _xp_cost(skipped_level)
	var close_to_player: bool = depth > level - BALANCE.trivial_level_gap
	var bonus := roundi(_xp_cost(mini(depth, MAX_LEVEL)) * BALANCE.first_clear_xp_share) if close_to_player else 0
	return _grant_xp(maxi(bonus, catchup))


func snapshot() -> Dictionary:
	var saved_attributes := {}
	for id: StringName in _attributes:
		saved_attributes[String(id)] = _attributes[id]
	return {
		"level": level,
		"xp": xp,
		"highest_cleared_depth": _highest_cleared_depth,
		"attributes": saved_attributes,
	}


func restore(saved: Dictionary, deepest_completed_depth := 0) -> void:
	# Older checkpoints have the unlocked dungeon gate, but no experience or allocation.
	_level = clampi(int(saved.get("level", deepest_completed_depth)), 1, MAX_LEVEL)
	_xp = clampi(int(saved.get("xp", 0)), 0, maxi(0, xp_for_next_level() - 1))
	_highest_cleared_depth = maxi(0, maxi(deepest_completed_depth, int(saved.get("highest_cleared_depth", 0))))
	reset_attributes()
	var saved_attributes: Variant = saved.get("attributes", {})
	if saved_attributes is Dictionary:
		for id: StringName in ATTRIBUTE_IDS:
			var restored := clampi(int(saved_attributes.get(String(id), 0)), 0, points_available())
			if restored > 0:
				_attributes[id] = restored


static func for_training(player_level: int) -> CharacterProgression:
	var training := CharacterProgression.new()
	training._level = clampi(player_level, 1, MAX_LEVEL)
	return training


## Under-levelled attacks and stun buildup lose effectiveness against a higher-level target.
static func outgoing_multiplier(attacker_level: int, target_level: int) -> float:
	var gap := maxi(0, target_level - attacker_level - BALANCE.grace_levels)
	var standard := mini(gap, BALANCE.standard_outgoing_levels)
	var overmatched := gap - standard
	var multiplier := pow(BALANCE.outgoing_per_level, standard) * pow(BALANCE.overmatched_outgoing_per_level, overmatched)
	return maxf(BALANCE.minimum_outgoing, multiplier)


## Higher-level enemies deal more damage to the player and put more pressure on guard.
static func incoming_multiplier(attacker_level: int, target_level: int) -> float:
	var gap := maxi(0, attacker_level - target_level - BALANCE.grace_levels)
	return 1.0 + minf(BALANCE.maximum_incoming_bonus, BALANCE.incoming_per_level * gap)


static func _xp_cost(current_level: int) -> int:
	return BALANCE.base_xp_cost + BALANCE.xp_cost_per_level * (current_level - 1)


func _grant_xp(amount: int) -> int:
	_xp += amount
	while level < MAX_LEVEL and _xp >= xp_for_next_level():
		_xp -= xp_for_next_level()
		_level += 1
	if level >= MAX_LEVEL:
		amount -= _xp
		_xp = 0
	return amount
