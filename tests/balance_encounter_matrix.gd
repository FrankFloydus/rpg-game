extends SceneTree
## Samples stored pack plans through the production native attack admission meters.

const Game := preload("res://main.gd")
const Dungeon := preload("res://world/dungeon.gd")
const Features := preload("res://world/expedition_features.gd")
const Catalog := preload("res://combat/enemies/enemy_catalog.gd")
const Enemy := preload("res://combat/enemies/enemy.gd")
const Stats := preload("res://combat/enemies/enemy_stat_resolver.gd")
const Pressure := preload("res://ai/expedition_pressure.gd")
const DepthDifficulty := preload("res://data/depth_difficulty.tres")
const ExpeditionRules := preload("res://data/expedition_rules.tres")
const Progression := preload("res://systems/character_progression.gd")
const Damage := preload("res://combat/damage_resolution.gd")

const SEED := 53119761
const DEPTHS := [1, 3, 5, 7, 10, 15, 25, 40, 50]
const HISTORICAL_GENERATOR := 5
const EXPEDITIONS_PER_DEPTH := 12
const SAMPLES_PER_DEPTH := 16_000
const VARIANT_COMPOSITION := "authored_cost_times_director"

var _game: Node3D
var _target: Node3D
var _affix_probe: Node3D
var _rng := RandomNumberGenerator.new()
var _layouts := RandomNumberGenerator.new()
var _mob_rng := RandomNumberGenerator.new()
var _output := ""
var _replay_legacy_phase_cost := false
var _ability_profiles: Dictionary = {}
var _problems: Array[String] = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument == "--replay-legacy-phase-cost":
			_replay_legacy_phase_cost = true
	_run.call_deferred()


func _run() -> void:
	var started := Time.get_ticks_msec()
	_game = Game.new()
	_target = Node3D.new()
	root.add_child(_target)
	_affix_probe = Catalog.instantiate(0)
	_prepare_ability_profiles()
	var rows: Array[Dictionary] = []
	for depth: int in DEPTHS:
		var director := _director_costs(depth)
		var history := _measure(depth, HISTORICAL_GENERATOR, director)
		var current := _measure(depth, Dungeon.GENERATION_VERSION, director)
		rows.append(history)
		rows.append(current)
		_print_summary(history)
		_print_summary(current)
	var measured := SAMPLES_PER_DEPTH * rows.size()
	var report := {"seed": SEED, "expeditions_per_depth_and_version": EXPEDITIONS_PER_DEPTH,
		"scenarios": measured, "cost_hypothesis": VARIANT_COMPOSITION, "rows": rows,
		"production_phase_cost": "authored_override" if _replay_legacy_phase_cost else "authored_times_director",
		"source_hashes": _source_hashes(), "problems": _problems,
		"model": "Each scenario is one ready pack in unobstructed range during native admission grace. Phases are stratified equally. Assume admitted attacks connect. No gear mitigation, avoidance, dynamic summons, or full fight DPS."}
	if not _output.is_empty():
		var file := FileAccess.open(_output, FileAccess.WRITE)
		if file == null:
			_problems.append("No output file could be opened")
		else:
			file.store_string(JSON.stringify(report, "\t"))
	_game.free()
	_target.free()
	_affix_probe.free()
	print("Encounter admission: %d seeded samples across %d depth/version rows in %d ms, %d problems"
		% [measured, rows.size(), Time.get_ticks_msec() - started, _problems.size()])
	for problem in _problems:
		printerr(problem)
	quit(0 if _problems.is_empty() else 1)


func _director_costs(depth: int) -> Dictionary:
	var pacing := Pressure.new()
	pacing.configure(_target, depth)
	var measured := {"build_up": pacing.attack_cost_multiplier()}
	pacing.record_pressure(pacing._director.peak_pressure + 1.0)
	for frame in 100:
		pacing._director.update_encounter(0.25, {}, [])
		var state := String(pacing._director.get_state())
		measured[state] = pacing.attack_cost_multiplier()
		if measured.has("fade") and measured.has("relax"):
			break
	pacing.free()
	if not measured.has("fade") or not measured.has("relax"):
		_problems.append("Director did not produce both recovery phases at Depth %d" % depth)
	return measured


func _prepare_ability_profiles() -> void:
	for archetype: Dictionary in Catalog.ARCHETYPES:
		var actions: Array[Dictionary] = []
		for ability: Resource in archetype.abilities:
			var profile: Dictionary = ability.runtime_profile()
			var shape := String(profile.get("shape", ""))
			if shape.is_empty() or ability.action_key == "cobweb":
				continue
			actions.append({"category": Enemy.RANGED_ATTACK_CATEGORY if shape == "ray" else Enemy.MELEE_ATTACK_CATEGORY,
				"coefficient": float(profile.get("damage", 1.0)), "cost": float(profile.get("attack_cost", 0.0))})
		if not actions.is_empty():
			_ability_profiles[int(archetype.id)] = actions


func _cache_layouts(depth: int, version: int) -> Dictionary:
	_layouts.seed = hash([SEED, depth, 1933])
	var floor_count := 3 if depth >= ExpeditionRules.third_floor_depth else 2
	var room_budget := maxi(6, ceili(float(mini(24, 6 + depth * 2)) / floor_count))
	var packs: Array[Dictionary] = []
	var opening: Array[int] = []
	var totals: Array[int] = []
	var wave_types := {}
	var elites := 0
	var foes := 0
	for sample in EXPEDITIONS_PER_DEPTH:
		var seed_value := int(_layouts.randi())
		var rise := 1 if _layouts.randf() < ExpeditionRules.ascending_chance else -1
		var feature_plan := Features.make_plan(depth, seed_value, floor_count)
		var total := 0
		for index in floor_count:
			var floor_seed := seed_value + index * Game.FLOOR_SEED_STRIDE
			var floor := Dungeon.new()
			# Execute the production layout/population plan without building renderer surfaces or navigation.
			floor._generation_version = version
			floor._room_limit = room_budget
			floor._population_scale = 0.79 if floor_count == 2 else 0.70
			floor._feature_mask = int(feature_plan.masks[index]) if version >= Dungeon.TRIAL_COFFER_GENERATION_VERSION else -1
			floor._layout_expedition(depth, floor_seed, index, floor_count, rise)
			_mob_rng.seed = floor_seed + 30289
			var roster: Array[Dictionary] = _game._roll_encounter_roster(floor.encounters, depth, _mob_rng, true)
			var pack_members := {}
			var front := 0
			for member in roster.size():
				var entry := floor.encounters[member]
				var roll := roster[member]
				foes += 1
				elites += int(roll.rarity != "normal")
				front += int(entry.room == 1 and not entry.has("spawn_trigger"))
				var actor := _actor_for(depth, entry, roll)
				if actor.is_empty():
					continue
				var kind := String(entry.get("spawn_trigger", ""))
				if kind.is_empty():
					kind = "swarm" if entry.get("swarm", false) else ("corridor" if entry.room < 0 else "room")
				elif entry.has("wave"):
					kind = "trial_wave"
				if not pack_members.has(entry.pack):
					pack_members[entry.pack] = {"kind": kind, "members": [], "life": 0.0}
				pack_members[entry.pack].members.append(actor)
				pack_members[entry.pack].life += float(actor.life)
			for pack: Dictionary in pack_members.values():
				packs.append(pack)
				wave_types[pack.kind] = int(wave_types.get(pack.kind, 0)) + 1
			total += roster.size()
			if index == 0:
				opening.append(front)
			floor.free()
		totals.append(total)
	return {"packs": packs, "opening": opening, "expedition_population": totals, "kinds": wave_types,
		"elite_percent": 100.0 * float(elites) / maxi(1, foes)}


func _actor_for(depth: int, entry: Dictionary, roll: Dictionary) -> Dictionary:
	var archetype := Catalog.ARCHETYPES[int(entry.archetype)]
	var actions: Array = _ability_profiles.get(int(entry.archetype), [])
	if actions.is_empty():
		return {}
	_affix_probe.rarity = roll.rarity
	_mob_rng.seed = int(roll.seed)
	var chosen: Array[String] = []
	chosen.assign(roll.get("affixes", []))
	_affix_probe._select_affixes(_mob_rng, chosen)
	var resolved := Stats.resolve(archetype.hp, archetype.damage, archetype.speed, 1.0,
		depth, roll.rarity, _affix_probe.affixes, DepthDifficulty.for_depth(depth))
	return {"actions": actions, "life": resolved.life, "damage": resolved.attack_damage}


func _measure(depth: int, version: int, director: Dictionary) -> Dictionary:
	var cached := _cache_layouts(depth, version)
	var packs: Array = cached.packs
	var encounter := Enemy.create_ai_encounter(depth, _target, false)
	var phases := ["build_up", "fade", "relax"]
	var phase_totals: Dictionary = {}
	var start_counts := {}
	var member_counts := {}
	var pack_life := {}
	var life_shares := {}
	var outcomes := {}
	var max_life := Progression.for_training(depth).max_life()
	var heavy_count := 0
	var lethal_count := 0
	var doubled_room_lethal := 0
	var shared_admission_lethal := 0
	var total_damage := 0.0
	_rng.seed = hash([SEED, depth, 3317])
	for sample in SAMPLES_PER_DEPTH:
		var pack: Dictionary = packs[_rng.randi_range(0, packs.size() - 1)]
		var mode: String = phases[sample % phases.size()]
		var multiplier := float(director.get(mode, 1.0))
		var attacks := _choose_actions(pack.members)
		var current := _admit(encounter, attacks, multiplier, not _replay_legacy_phase_cost)
		var composition := _admit(encounter, attacks, multiplier, true)
		var phase: Vector3 = phase_totals.get(mode, Vector3.ZERO)
		phase_totals[mode] = phase + Vector3(1, current.x, composition.x)
		_increment(member_counts, pack.members.size())
		_increment(pack_life, roundi(float(pack.life)))
		_increment(start_counts, int(current.x))
		var life_share := float(current.y) / max_life
		_increment(life_shares, clampi(roundi(life_share * 100.0), 0, 999))
		heavy_count += int(life_share >= 0.5)
		lethal_count += int(life_share >= 1.0)
		total_damage += float(current.y)
		var kind: String = pack.kind
		var encounter_types: Vector3 = outcomes.get(kind, Vector3.ZERO)
		outcomes[kind] = encounter_types + Vector3(1, current.x, int(life_share >= 1.0))
		if mode == "build_up":
			# Independent gates in overlapping packs can each admit an opener.
			var second: Dictionary = packs[_rng.randi_range(0, packs.size() - 1)]
			var next_attempts := _choose_actions(second.members)
			var added := _admit(encounter, next_attempts, 1.0, false)
			doubled_room_lethal += int(float(current.y + added.y) >= max_life)
			attacks.append_array(next_attempts)
			var shared := _admit(encounter, attacks, 1.0, false)
			shared_admission_lethal += int(float(shared.y) >= max_life)
	var rules_captured := encounter.get_attack_rules()
	encounter.free()
	var admission := {}
	for mode: String in phase_totals:
		var measurements: Vector3 = phase_totals[mode]
		admission[mode] = {"samples": int(measurements.x), "current": measurements.y / measurements.x,
			"composition_hypothesis": measurements.z / measurements.x}
	return {"depth": depth, "generation_version": version, "samples": SAMPLES_PER_DEPTH,
		"opening_rooms": cached.opening, "population": cached.expedition_population,
		"pack_types": cached.kinds, "elite_percent": cached.elite_percent, "admission": admission,
		"first_burst_mean_damage": total_damage / SAMPLES_PER_DEPTH, "first_burst_p95_life_percent": _percentile(life_shares, 0.95),
		"first_burst_half_life_percent": 100.0 * heavy_count / SAMPLES_PER_DEPTH,
		"first_burst_lethal_percent": 100.0 * lethal_count / SAMPLES_PER_DEPTH,
		"two_independent_packs_lethal_percent": 100.0 * doubled_room_lethal / int(phase_totals.build_up.x),
		"two_packs_shared_admission_hypothesis_lethal_percent": 100.0 * shared_admission_lethal / int(phase_totals.build_up.x),
		"member_p95": _percentile(member_counts, 0.95), "start_p95": _percentile(start_counts, 0.95),
		"pack_life_p50": _percentile(pack_life, 0.50), "pack_life_p95": _percentile(pack_life, 0.95),
		"outcomes_by_type": _outcome_dict(outcomes), "director_costs": director,
		"rules": rules_captured}


func _choose_actions(members: Array) -> Array[Dictionary]:
	var actors := members.duplicate()
	var selected: Array[Dictionary] = []
	while not actors.is_empty():
		var actor: Dictionary = actors.pop_at(_rng.randi_range(0, actors.size() - 1))
		var action: Dictionary = actor.actions[_rng.randi_range(0, actor.actions.size() - 1)]
		selected.append({"category": action.category, "cost": action.cost,
			"damage": Damage.hit(Stats.hit_damage(actor.damage, action.coefficient))})
	return selected


func _admit(encounter: AIEncounter3D, attempts: Array[Dictionary], director_cost: float, compose_cost: bool) -> Vector2i:
	encounter.unregister_target(_target)
	encounter.register_target(_target)
	var result := Vector2i.ZERO
	for attempt: Dictionary in attempts:
		var configured: float = attempt.cost
		var cost := director_cost
		if configured > 0.0:
			cost = configured * director_cost if compose_cost else configured
		if encounter.try_begin_attack(_target, attempt.category, cost):
			result += Vector2i(1, int(attempt.damage))
	return result


func _outcome_dict(outcomes: Dictionary) -> Dictionary:
	var counts := {}
	for kind: String in outcomes:
		var tally: Vector3 = outcomes[kind]
		counts[kind] = {"scenarios": int(tally.x), "average_starts": tally.y / tally.x,
			"lethal_percent": tally.z * 100.0 / tally.x}
	return counts


func _percentile(histogram: Dictionary, share: float) -> int:
	var counts: Array = histogram.keys()
	counts.sort()
	var total := 0
	for frequency: int in histogram.values():
		total += frequency
	var target := ceili(total * share)
	for value: int in counts:
		target -= int(histogram[value])
		if target <= 0:
			return value
	return 0


func _increment(histogram: Dictionary, key: int) -> void:
	histogram[key] = int(histogram.get(key, 0)) + 1


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path in ["main.gd", "world/dungeon.gd", "world/expedition_features.gd", "ai/expedition_pressure.gd",
			"data/expedition_rules.tres", "data/depth_difficulty.tres", "data/player_progression_records.tres",
			"combat/enemies/enemy.gd", "combat/enemies/enemy_stat_resolver.gd", "combat/enemies/enemy_catalog.gd",
			"combat/enemies/enemy_scaling.tres", "tests/balance_encounter_matrix.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes


func _print_summary(row: Dictionary) -> void:
	print("D%02d v%d front %d–%d | pack p95 %d | opener p95 %d | burst p95 %d%% Life | lethal %.2f%% | overlap %.2f%% | fade %.2f → %.2f | relax %.2f → %.2f"
		% [row.depth, row.generation_version, row.opening_rooms.min(), row.opening_rooms.max(), row.member_p95,
			row.start_p95, row.first_burst_p95_life_percent, row.first_burst_lethal_percent, row.two_independent_packs_lethal_percent,
			row.admission.fade.current, row.admission.fade.composition_hypothesis,
			row.admission.relax.current, row.admission.relax.composition_hypothesis])
