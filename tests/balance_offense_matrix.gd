extends SceneTree
## Deterministic offense simulation using the live player hit and enemy mitigation code.

const PlayerScene := preload("res://player/player.tscn")
const Items := preload("res://systems/items.gd")
const BaseItems := preload("res://data/items/bases.gd")
const EnemyCatalog := preload("res://combat/enemies/enemy_catalog.gd")
const EnemyStats := preload("res://combat/enemies/enemy_stat_resolver.gd")
const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const LOADOUTS_PER_ROW := 64
const STRIKES_PER_LOADOUT := 16
const ENEMY_LEVELS := [1, 5, 6, 7, 15, 30]
const WEAPONS := ["dagger_1h", "sword_1h", "axe_1h", "mace_1h", "sword_2h", "axe_2h", "mace_2h", "staff"]
const RANKS := ["normal", "magic", "rare"]
const LEVEL_OFFSETS := [-2, 0, 2]
const ITEM_SOURCES := ["normal", "magic", "magic", "rare"]
const JEWELRY_AND_GLOVES := {"left_ring": "ring", "right_ring": "ring", "amulet": "amulet", "gloves": "gloves"}

class AttackProbe extends "res://player/player.gd":
	var last_critical := false

	func report_enemy_hit(_enemy: Node3D, _point: Vector3, _hit: Dictionary, _ability: Dictionary,
			critical := false, _glancing := false) -> void:
		last_critical = critical


class TargetProbe extends "res://combat/enemies/enemy.gd":
	var last_resolved_damage := 0
	var body_resistance := 1.0

	func definition() -> Dictionary:
		return {}

	func _ready() -> void:
		add_to_group("enemies")

	func _notice_hit(_source: Node3D) -> void:
		pass

	func _lose_life(amount: int, _source: Node3D, _hit_point := Vector3.INF,
			_impact_direction := Vector3.ZERO, _weapon_contact: Dictionary = {}) -> float:
		last_resolved_damage = amount
		return minf(health, float(amount))

	func receive_stun_impact(_amount: float, _source: Node, _ability: Dictionary = {}) -> bool:
		return false

	func apply_impulse(_direction: Vector3, _strength: float) -> void:
		pass

	func sample_target(player: Node3D, archetype: Dictionary, rank: String, depth: int,
			rng: RandomNumberGenerator, resistance_data: Resource) -> void:
		_player = player
		rarity = rank
		enemy_level = depth
		_select_affixes(rng, [])
		var resolved := EnemyStats.resolve(archetype.hp, archetype.damage, archetype.speed,
			1.0, depth, rank, affixes)
		max_health = resolved.life
		health = max_health
		_statuses.clear()
		body_resistance = resistance_data.body_resistance(
			float(archetype.width) * resolved.size_multiplier,
			float(archetype.height) * 0.86 * resolved.size_multiplier)


const ImpactRules := preload("res://data/impact_feedback.tres")
var _player: AttackProbe
var _target: TargetProbe
var _rng := RandomNumberGenerator.new()
var _rows: PackedStringArray = []
var _summary: Dictionary = {}
var _trials := 0
var _cadence_failures := 0
var _csv := ""
var _uncapped := false
var _white_starters := false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--csv="):
			_csv = argument.trim_prefix("--csv=")
		elif argument == "--uncapped":
			_uncapped = true
		elif argument == "--white":
			_white_starters = true
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 0xCE6B9A
	for action: StringName in [&"left", &"right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var player := PlayerScene.instantiate()
	player.set_script(AttackProbe)
	_player = player as AttackProbe
	_target = TargetProbe.new()
	root.add_child(_player)
	root.add_child(_target)
	_player.set_physics_process(false)
	_player._weapon.set_process(false)
	_player._camera_feedback = null
	_player._rng.seed = 0x22E4F
	_player.combat_enabled = true
	if _uncapped:
		_player.ATTACK_TEMPO.set("maximum_effective_rate", 1000.0)
	_target.position = Vector3(0.0, 0.0, -1.0)
	_rows.append("depth,weapon,mode,player_level,enemy_rank,trials,oneshot_pct,noncrit_oneshot_pct,p50_damage,p90_damage,p99_damage,p90_overkill,mean_life,mean_total_seconds,mean_charge_seconds,extra_cut_eligible_pct")
	var started := Time.get_ticks_usec()
	for depth: int in ENEMY_LEVELS:
		for type: String in WEAPONS:
			_player.update_equipment({"main_hand": Items.training_weapon_preview(_bases(type, depth)[0].id, depth)})
			for heavy: bool in [false, true]:
				for gap: int in LEVEL_OFFSETS:
					if depth + gap < 1:
						continue
					for rank: String in RANKS:
						_measure_row(depth, type, heavy, gap, rank)
	if not _csv.is_empty():
		var report := FileAccess.open(_csv, FileAccess.WRITE)
		if report == null:
			push_error("Unable to write offense matrix: " + _csv)
			quit(1)
			return
		report.store_string("\n".join(_rows) + "\n")
		report.close()
	for key: String in _summary:
		var totals: Vector4 = _summary[key]
		print("%s  %d hits  %5.1f%% one-shot  %5.1f%% noncrit one-shot" % [
			key, int(totals.x), 100.0 * totals.y / totals.x, 100.0 * totals.w / maxf(1.0, totals.z)])
	print("Hearth Below offense matrix: %d actual hit resolutions, %.2fs, %d stratified rows, %s" % [
		_trials, float(Time.get_ticks_usec() - started) / 1000000.0, _rows.size() - 1,
		"level-one white weapons only" if _white_starters else "rolled equipment"])
	if _cadence_failures > 0:
		push_error("%d loadouts failed to start a measured cast" % _cadence_failures)
	_target.free()
	_player.free()
	quit(0 if _trials >= 250000 and _cadence_failures == 0 else 1)


func _measure_row(depth: int, type: String, heavy: bool, gap: int, rank: String) -> void:
	var player_level := depth + gap
	var progression := CharacterProgression.for_training(player_level)
	var damage_samples := PackedFloat32Array()
	var overkill_samples := PackedFloat32Array()
	var kills := 0
	var noncrit_kills := 0
	var noncrits := 0
	var extra_cuts := 0
	var life_total := 0.0
	var cadence_total := 0.0
	var charge_total := 0.0
	var weapon_bases := _bases(type, depth)
	var contacts: Array[Dictionary] = [{
		"target": _target, "point": Vector3(0.0, 0.9, -1.0), "direction": Vector3.FORWARD
	}]
	var ability: AbilityDefinition = _player._weapon_attack_ability(heavy)
	for loadout: int in LOADOUTS_PER_ROW:
		var gear := _sample_gear(depth, weapon_bases, loadout)
		var weapon: Dictionary = gear.main_hand
		progression.reset_attributes()
		var relevant := WeaponRoles.scaling_attribute(type, weapon.base_id)
		if player_level > 1:
			progression.allocate(relevant, loadout % (player_level - 1) + 1)
		_player.character_progression = progression
		_player._equipment = gear
		_player.stats = Items.player_stats(gear, progression)
		_player.effects = Items.legendary_effects(gear)
		_player._weapon_base_id = weapon.base_id
		_player.restore_full()
		_player._attack_timer = 0.0
		if _player.cast_ability(ability, heavy, heavy):
			cadence_total += _player._attack_timer
			charge_total += _player._charge_duration if heavy else 0.0
		else:
			_cadence_failures += 1
		for strike: int in STRIKES_PER_LOADOUT:
			var archetype: Dictionary = EnemyCatalog.ARCHETYPES[EnemyCatalog.pick_archetype(depth, _rng)]
			_target.sample_target(_player, archetype, rank, depth, _rng, ImpactRules)
			life_total += _target.health
			_target.last_resolved_damage = 0
			_player._resolve_attack(heavy, ability.combat_details(), null, contacts, {"count": 0})
			var amount := _target.last_resolved_damage
			damage_samples.append(amount)
			var lethal := float(amount) >= _target.health
			if lethal:
				kills += 1
				var excess := float(amount) - _target.health
				overkill_samples.append(excess)
				if WeaponRoles.family(type) == WeaponRoles.EDGED and ImpactRules.cut_count(excess, _target.body_resistance) > 1:
					extra_cuts += 1
			if not _player.last_critical:
				noncrits += 1
				noncrit_kills += int(lethal)
	var count := damage_samples.size()
	_trials += count
	damage_samples.sort()
	overkill_samples.sort()
	var mode := "charged" if heavy else "light"
	_rows.append("%d,%s,%s,%d,%s,%d,%.4f,%.4f,%.1f,%.1f,%.1f,%.2f,%.2f,%.4f,%.4f,%.4f" % [
		depth, type, mode, player_level, rank, count, 100.0 * kills / count,
		100.0 * noncrit_kills / maxi(1, noncrits), _quantile(damage_samples, 0.50), _quantile(damage_samples, 0.90),
		_quantile(damage_samples, 0.99), _quantile(overkill_samples, 0.90), life_total / count,
		cadence_total / LOADOUTS_PER_ROW, charge_total / LOADOUTS_PER_ROW, 100.0 * extra_cuts / count])
	if gap == 0:
		var key := "Depth %d %s %s" % [depth, rank, mode]
		_summary[key] = _summary.get(key, Vector4.ZERO) + Vector4(count, kills, noncrits, noncrit_kills)


func _sample_gear(depth: int, weapon_bases: Array[Dictionary], iteration: int) -> Dictionary:
	if _white_starters:
		return {"main_hand": Items.training_weapon_preview(weapon_bases[0].id)}
	var best: Dictionary = {}
	var best_score := -INF
	for attempt: int in 3:
		var base := weapon_bases[_rng.randi_range(0, weapon_bases.size() - 1)]
		var source: String = ITEM_SOURCES[_rng.randi_range(0, ITEM_SOURCES.size() - 1)]
		var weapon := Items.roll_item(depth, source, _rng, 0.0, base)
		var score := _score_weapon(weapon.stats)
		if score > best_score:
			best = weapon
			best_score = score
	var gear := {"main_hand": best}
	for slot: String in JEWELRY_AND_GLOVES:
		if not slot in ["gloves", "left_ring"] and iteration % 4 == 0:
			continue
		var bases := _bases(JEWELRY_AND_GLOVES[slot], depth)
		var base := bases[_rng.randi_range(0, bases.size() - 1)]
		gear[slot] = Items.roll_item(depth, "magic", _rng, 0.0, base)
	return gear


func _bases(category: String, depth: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for base: Dictionary in BaseItems.BASES:
		if base.type == category and int(base.level) <= depth:
			result.append(base)
	return result


func _score_weapon(stats: Dictionary) -> float:
	var typical := (float(stats.get("damage_min", 0.0)) + float(stats.get("damage_max", 0.0))) * 0.5
	for element: String in ["fire_damage", "cold_damage", "lightning_damage", "poison_damage"]:
		typical += float(stats.get(element, 0.0))
	return typical * (1.0 + 0.01 * float(stats.get("attack_speed", 0.0)))


func _quantile(samples: PackedFloat32Array, q: float) -> float:
	return 0.0 if samples.is_empty() else samples[roundi(q * (samples.size() - 1))]
