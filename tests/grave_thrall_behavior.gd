extends SceneTree
## Covers Graveknife Cut through an actual Training Ground encounter.

const Game = preload("res://main.tscn")
const Catalog = preload("res://combat/enemies/enemy_catalog.gd")
const AbilityDefinition = preload("res://combat/abilities/ability_definition.gd")
const MeleeAbilityDefinition = preload("res://combat/abilities/melee_ability_definition.gd")
const Bestiary = preload("res://data/bestiary.gd")
const BleedEffectDefinition = preload("res://combat/effects/bleed_effect_definition.gd")
const Enrage = preload("res://combat/effects/enrage.tres")
const THRALL := 0
const ENEMY_NAME := "Grave Thrall"
const ACTION_ID := "graveknife_cut"
const ABILITY_NAME := "Graveknife Cut"
const NATIVE_ATTACK_NODE := 10

var _game: Node3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game._create_character(0, "Thrall Tester")
	_aim(_game.hub.training_arrival_position(), _game.hub.interaction_position("training_portal"))
	await _tap(KEY_E)
	if _check(is_instance_valid(_game.training_ground), "The hub portal opens the Training Ground"):
		var authored := Catalog.instantiate(THRALL)
		var shared := authored.ability_loadout[0] as MeleeAbilityDefinition
		authored.free()
		var authored_chance := shared.double_slash_chance
		var authored_effects := shared.on_hit_effects
		# Keep the F1 fixture deterministic before the roster constructs the actor.
		shared.double_slash_chance = 0.0
		shared.on_hit_effects = []
		var thrall := await _spawn_thrall()
		if is_instance_valid(thrall):
			await _check_chase_facing(thrall)
			await _check_knife(thrall)
			await _check_distance_and_cover(thrall)
			await _check_instance_tuning(thrall)
		shared.double_slash_chance = authored_chance
		shared.on_hit_effects = authored_effects
		await _check_shared_ability(shared)
		await _check_double_slash(shared)
		await _check_animated_hit_window(shared)
		await _check_enrage(shared)
	_game.free()
	await _ticks(2)
	print("Hearth Below Grave Thrall behavior: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_chase_facing(thrall: CharacterBody3D) -> void:
	var intent: Vector3 = thrall._planned_velocity
	for frame in range(60):
		if intent.length_squared() > 0.5:
			break
		await _ticks(1)
		intent = thrall._planned_velocity
	if not _check(intent.length_squared() > 0.5, "The native runner begins the Thrall's chase"):
		return

	# Reverse the body during a live chase to isolate turning from aggro and pathfinding delays.
	var authored_turn_speed: float = thrall.turn_speed
	thrall.turn_speed = 1080.0
	thrall.global_rotation.y = atan2(intent.x, intent.z)
	thrall.velocity = Vector3.ZERO
	var tick_rate := float(Engine.physics_ticks_per_second)
	var turn_budget := ceili(0.20 * tick_rate)
	var aligned_at := -1
	var moved := false
	var moved_forward := true
	for tick in range(1, turn_budget + 1):
		await _ticks(1)
		intent = thrall._planned_velocity
		var forward := -thrall.global_basis.z
		var travel := thrall.get_real_velocity()
		travel.y = 0.0
		if travel.length_squared() > 0.04:
			moved = true
			moved_forward = moved_forward and forward.dot(travel.normalized()) >= cos(deg_to_rad(46.0))
		if aligned_at < 0 and intent.length_squared() > 0.5 \
				and forward.dot(intent.normalized()) >= cos(deg_to_rad(10.0)):
			aligned_at = tick
	_check(aligned_at >= 0 and float(aligned_at) / tick_rate <= 0.20,
		"The Thrall turns into a reversed path heading within 0.20 s (aligned at tick %d)" % aligned_at)
	_check(moved and moved_forward, "The Thrall resumes forward movement without sliding sideways during the pivot")

	# Offer a sideways waypoint while the player remains visible.
	var saved_yaw := thrall.global_rotation.y
	var to_player: Vector3 = _game.player.global_position - thrall.global_position
	to_player.y = 0.0
	var waypoint_heading := to_player.cross(Vector3.UP).normalized()
	thrall._planned_velocity = waypoint_heading
	var waypoint_motion: Vector3 = thrall._steer_locomotion(to_player, 0.20)
	_check(thrall._sight and (-thrall.global_basis.z).dot(waypoint_heading) > 0.98
		and waypoint_motion.dot(waypoint_heading) > 0.98,
		"A melee Thrall faces a sideways waypoint even while the player is visible")
	thrall.global_rotation.y = saved_yaw
	thrall._planned_velocity = intent
	thrall.turn_speed = authored_turn_speed


func _check_knife(thrall: CharacterBody3D) -> void:
	var field_notes := Bestiary.entry(THRALL)
	_check(thrall.archetype_id == THRALL and thrall.enemy_level == 1 and Catalog.action_ids(THRALL) == [ACTION_ID]
		and field_notes.abilities.any(func(move: Dictionary) -> bool: return move.name == ABILITY_NAME)
		and field_notes.traits.any(func(entry: Dictionary) -> bool: return entry.name == "Enrage"),
		"The Level 1 Thrall keeps ID 0 and the Bestiary lists Graveknife Cut and Enrage")
	var initial_gap := _gap(thrall)
	var initial_life: float = _game.player.life
	var brain := thrall.get_node("Brain") as AIBehaviorRunner
	var ability: AbilityDefinition = thrall.ability_loadout[0]
	var authored_cooldown := ability.cooldown
	var frame_budget := roundi((4.0 + 3.0 * (authored_cooldown + ability.windup)) * Engine.physics_ticks_per_second)
	for frame in range(frame_budget):
		await _ticks(1)
		if _cuts(&"damage").size() >= 3:
			break
	var hits := _cuts(&"damage")
	_check(thrall._engaged and _gap(thrall) < initial_gap - 1.0,
		"The Thrall walks into melee range from the training spawn")
	_check(brain != null and brain.get_action_history(NATIVE_ATTACK_NODE).get("attempt_at") != null,
		"The native attack task admits the knife cuts")
	if not _check(hits.size() >= 3 and _game.player.life < initial_life, "The knife applies repeated damage in reach"):
		return
	var starts := _cuts(&"cast_start")
	var ends := _cuts(&"cast_end")
	var instant := is_zero_approx(ability.windup)
	var cast_timing_matches := starts.size() == hits.size() and ends.size() == hits.size()
	var on_cadence := cast_timing_matches
	var intervals := PackedStringArray()
	var tick_seconds := 1.0 / Engine.physics_ticks_per_second
	for index in range(hits.size()):
		if cast_timing_matches:
			var start_time := float(starts[index].time)
			var end_time := float(ends[index].time)
			var windup_matches := is_equal_approx(start_time, end_time) if instant else start_time < end_time
			cast_timing_matches = windup_matches and is_equal_approx(end_time, float(hits[index].time))
		if index > 0 and starts.size() == hits.size() and ends.size() == hits.size():
			var interval := float(starts[index].time) - float(ends[index - 1].time)
			intervals.append("%.3f" % interval)
			on_cadence = on_cadence and interval >= authored_cooldown - tick_seconds - 0.00001
	_check(cast_timing_matches, "Each cut starts and hits immediately" if instant
		else "Each cut winds up before finishing and applying damage")
	_check(on_cadence, "A Thrall respects the authored %.2f s cooldown from commit (%s s observed)"
		% [authored_cooldown, ", ".join(intervals)])


func _check_distance_and_cover(thrall: CharacterBody3D) -> void:
	var ability: AbilityDefinition = thrall.ability_loadout[0]
	var reach := float(ability.runtime_profile().reach)
	var num_starts := _cuts(&"cast_start").size()
	var life_before: float = _game.player.life
	_aim(Vector3(11.0, 0.08, 3.0), thrall.aim_point())
	await _ticks(80)
	_check(_gap(thrall) > reach and _cuts(&"cast_start").size() == num_starts
		and is_equal_approx(float(_game.player.life), life_before), "The Thrall holds its attack while the player is out of reach")

	# Keep the actors within attack reach on either side of a solid wall.
	thrall.global_position = Vector3(0.0, 0.08, -3.0)
	thrall.velocity = Vector3.ZERO
	var cover := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var wall := BoxShape3D.new()
	wall.size = Vector3(12.0, 2.6, 0.35)
	collision.shape = wall
	cover.add_child(collision)
	cover.position = Vector3(0.0, 1.3, -2.2)
	_game.training_ground.add_child(cover)
	_aim(Vector3(0.0, 0.08, -1.25), thrall.aim_point())
	var blocked_in_reach := false
	for frame in range(80):
		await _ticks(1)
		blocked_in_reach = blocked_in_reach or (_gap(thrall) < reach and not thrall._has_sight())
	_check(blocked_in_reach and _cuts(&"cast_start").size() == num_starts
		and is_equal_approx(float(_game.player.life), life_before), "Solid cover stops the cut even within knife reach (blocked %s, starts %d to %d, Life %.2f to %.2f)"
		% [blocked_in_reach, num_starts, _cuts(&"cast_start").size(), life_before, _game.player.life])
	cover.queue_free()


func _check_instance_tuning(authored: CharacterBody3D) -> void:
	var authored_stats := Vector3(authored.base_life, authored.base_attack_damage, authored.base_move_speed)
	var authored_ability: AbilityDefinition = authored.ability_loadout[0]
	var authored_hit := authored_stats.y * authored_ability.damage_multiplier
	var authored_cooldown := authored_ability.cooldown
	var authored_windup := authored_ability.windup
	_game._reset_training_combat()
	_game._combat_events.clear()
	var player: Node3D = _game.player
	player.stats.merge({"armor": 0.0, "ward": 0.0}, true)
	player.restore_full()
	_aim(Vector3(0.0, 0.08, 3.0), Vector3(0.0, 1.0, -3.0))
	var rules: Dictionary = _game._training_encounter.get_attack_rules()
	# Keep the gate open so the ability's cooldown determines the observed cadence.
	rules[&"hearth_melee"]["threshold"] = 20.0
	_game._training_encounter.attack_rules = rules
	var rng := RandomNumberGenerator.new()
	var tuned := Catalog.instantiate(THRALL)
	tuned.base_life = 82.0
	tuned.base_attack_damage = 16.0
	tuned.base_move_speed = 3.5
	var tuned_ability := authored_ability.duplicate() as MeleeAbilityDefinition
	tuned_ability.damage_multiplier = 1.5
	tuned_ability.cooldown = 0.65
	tuned_ability.windup = 0.0
	tuned_ability.recovery = 0.0
	# Keep the stationary fixture inside the trigger distance regardless of the shared asset's reach.
	tuned_ability.reach = 2.26
	tuned_ability.start_range = 2.14
	tuned_ability.on_hit_effects = []
	tuned.ability_loadout[0] = tuned_ability
	tuned.setup(player, 1, "normal", rng, Callable(_game.training_ground, "navigation_route"), Bestiary.combat_ability)
	tuned.configure_encounter(0, false, 16.0)
	tuned.configure_ai(_game._training_encounter, _game._training_pressure)
	tuned.combat_event.connect(_game._record_combat_event)
	tuned.position = Vector3(0.0, 0.08, 1.35)
	_game._training_actors.add_child(tuned)
	var tuned_stats: Dictionary = tuned.combat_tuning_summary()
	_check(tuned_stats.level == 1 and is_equal_approx(tuned_stats.life, 82.0)
		and is_equal_approx(tuned_stats.move_speed, 3.5) and is_equal_approx(tuned_stats.attack_damage, 16.0),
		"A Level 1 actor uses its authored Life, movement speed, and base damage")
	var unchanged := Catalog.instantiate(THRALL)
	unchanged.setup(null, 1, "normal", rng)
	var unchanged_ability: AbilityDefinition = unchanged.ability_loadout[0]
	var original_stats: Dictionary = unchanged.combat_tuning_summary()
	_check(is_equal_approx(original_stats.life, authored_stats.x) and is_equal_approx(original_stats.move_speed, authored_stats.z)
		and is_equal_approx(original_stats.attack_damage, authored_stats.y) and is_equal_approx(unchanged._attack_damage(), authored_hit)
		and unchanged_ability == authored_ability and is_equal_approx(unchanged_ability.cooldown, authored_cooldown)
		and is_equal_approx(unchanged_ability.windup, authored_windup),
		"An ability variant leaves the original equipped asset and another actor's stats unchanged")
	unchanged.free()
	for frame in 180:
		if _cuts(&"damage").size() >= 3:
			break
		await _ticks(1)
	var hits := _cuts(&"damage")
	if not _check(hits.size() >= 3, "The tuned Graveknife Cut repeatedly connects through the native runner"):
		return
	var on_cadence := true
	var exact_damage := true
	var tick_seconds := 1.0 / Engine.physics_ticks_per_second
	for index in hits.size():
		exact_damage = exact_damage and is_equal_approx(float(hits[index].amount), 24.0)
		if index > 0:
			var interval := float(hits[index].time) - float(hits[index - 1].time)
			on_cadence = on_cadence and absf(interval - 0.65) <= tick_seconds + 0.00001
	_check(exact_damage and on_cadence,
		"The ability variant produces 24-damage slashes every 0.65 seconds with open admission")


func _check_shared_ability(authored_ability: AbilityDefinition) -> void:
	_game._reset_training_combat()
	_game._combat_events.clear()
	var shared := authored_ability.duplicate() as MeleeAbilityDefinition
	shared.cooldown = 2.0
	shared.mana_cost = 3.0
	shared.windup = 0.2
	shared.reach = 2.26
	shared.start_range = 2.14
	shared.double_slash_chance = 100.0
	var bleed := authored_ability.on_hit_effects[0].duplicate() as BleedEffectDefinition
	bleed.chance = 100.0
	shared.on_hit_effects = [bleed]

	var player: Node3D = _game.player
	player.light_ability_override = shared
	player.stats.mana_regen = 0.0
	player.restore_full()
	var thrall := Catalog.instantiate(THRALL)
	thrall.base_life = 1000.0
	thrall.mana_regeneration = 0.0
	thrall.ability_loadout[0] = shared
	thrall.setup(player, 1, "normal", RandomNumberGenerator.new(),
		Callable(_game.training_ground, "navigation_route"), Bestiary.combat_ability)
	thrall.configure_encounter(0, false, 16.0)
	thrall.configure_ai(_game._training_encounter, _game._training_pressure)
	thrall.combat_event.connect(_game._record_combat_event)
	thrall.position = Vector3(0.0, 0.08, 1.35)
	_game._training_actors.add_child(thrall)
	thrall.set_physics_process(false)
	_aim(Vector3(0.0, 0.08, 3.0), thrall.aim_point())
	await _ticks(2)

	var starting_mana: float = player.mana
	var enemy_mana: float = thrall.mana
	var started: bool = player.cast_ability(player.light_ability_override)
	if not _check(started and player._strike_pending and player.mana == starting_mana
			and player._ability_runtime.remaining(shared) == 0.0,
			"Player windup leaves the shared ability's mana and cooldown untouched until commit"):
		return
	for frame in 60:
		if thrall._statuses.has("bleed"):
			break
		await _ticks(1)
	if not _check(thrall._statuses.has("bleed") and is_equal_approx(player.mana, starting_mana - shared.mana_cost)
			and player._ability_runtime.remaining(shared) > 0.0 and thrall._ability_runtime.remaining(shared) == 0.0,
			"The shared ability bleeds the player's target and starts only the player's cooldown"):
		return
	for frame in 60:
		if _cuts(&"damage", ABILITY_NAME, "Player").size() == 2:
			break
		await _ticks(1)
	var player_hits := _cuts(&"damage", ABILITY_NAME, "Player")
	_check(player_hits.size() == 2 and float(player_hits[1].time) > float(player_hits[0].time)
		and _cuts(&"cast_start", ABILITY_NAME, "Player").size() == 1
		and _cuts(&"cast_end", ABILITY_NAME, "Player").size() == 1
		and is_equal_approx(player.mana, starting_mana - shared.mana_cost),
		"The shared double slash gives the player two separate hits with one cast and one mana cost")
	thrall.set_physics_process(true)
	for frame in 85:
		if player._ailments.has("bleed"):
			break
		await _ticks(1)
	_check(player._ailments.has("bleed") and is_equal_approx(thrall.mana, enemy_mana - shared.mana_cost)
		and thrall._ability_runtime.remaining(shared) > player._ability_runtime.remaining(shared)
		and player._ability_runtime.remaining(shared) > 0.0,
		"The native enemy commits the same ability and bleeds the player while the player's timer is still running")


func _check_animated_hit_window(authored_ability: MeleeAbilityDefinition) -> void:
	var ability := authored_ability.duplicate() as MeleeAbilityDefinition
	ability.double_slash_chance = 0.0
	ability.on_hit_effects = []
	var thrall := _prepare_duel(ability)
	await _wait_for_cuts(1)
	var baseline := _cuts(&"damage")
	if not _check(baseline.size() == 1, "The authored enemy Strike window produces one hit"):
		return
	var previous_delay := float(baseline[0].time) - float(_cuts(&"cast_start")[0].time)
	var clip := thrall.get_node("Model/Rig/AnimationPlayer").get_animation(&"Strike") as Animation
	var trace_start := clip.get_marker_time(&"Trace Start")
	var trace_end := clip.get_marker_time(&"Trace End")
	clip.remove_marker(&"Trace Start")
	clip.remove_marker(&"Trace End")
	clip.add_marker(&"Trace Start", 0.68 * clip.length)
	clip.add_marker(&"Trace End", 0.92 * clip.length)
	_prepare_duel(ability)
	await _wait_for_cuts(1)
	var retimed := _cuts(&"damage")
	var starts := _cuts(&"cast_start")
	_check(retimed.size() == 1 and starts.size() == 1 and
		float(retimed[0].time) - float(starts[0].time) > previous_delay + 0.055,
		"Moving the editable enemy Strike markers shifts the live hit window")
	clip.remove_marker(&"Trace Start")
	clip.remove_marker(&"Trace End")
	clip.add_marker(&"Trace Start", trace_start)
	clip.add_marker(&"Trace End", trace_end)


func _check_double_slash(authored_ability: MeleeAbilityDefinition) -> void:
	var ability := authored_ability.duplicate() as MeleeAbilityDefinition
	ability.double_slash_chance = 100.0
	ability.on_hit_effects = []
	ability.cooldown = 2.0
	ability.mana_cost = 3.0
	var thrall := _prepare_duel(ability)
	var mana_before: float = thrall.mana
	await _wait_for_cuts(2)
	var hits := _cuts(&"damage")
	if _check(hits.size() == 2, "A guaranteed double slash records two distinct hits"):
		var gap := float(hits[1].time) - float(hits[0].time)
		var tick_seconds := 1.0 / Engine.physics_ticks_per_second
		_check(gap > 0.0 and absf(gap - ability.follow_up_delay) <= tick_seconds * 2.0,
			"The second hit follows the authored delay (%.3f s observed)" % gap)
		_check(_cuts(&"cast_start").size() == 1 and _cuts(&"cast_end").size() == 1
			and is_equal_approx(thrall.mana, mana_before - ability.mana_cost)
			and thrall._ability_runtime.remaining(ability) < ability.cooldown
			and thrall._ability_runtime.remaining(ability) > 0.0,
			"The double slash commits one cast, spends mana once, and keeps the original cooldown")

	for block_with_cover in [false, true]:
		thrall = _prepare_duel(ability)
		await _wait_for_cuts(1)
		if not _check(_cuts(&"damage").size() == 1, "The first slash connects before the counterplay"):
			continue
		var cover: StaticBody3D
		if block_with_cover:
			cover = StaticBody3D.new()
			var collision := CollisionShape3D.new()
			var wall := BoxShape3D.new()
			wall.size = Vector3(6.0, 2.6, 0.20)
			collision.shape = wall
			cover.add_child(collision)
			cover.position = Vector3(0.0, 1.3, 2.25)
			_game.training_ground.add_child(cover)
		else:
			_aim(Vector3(0.0, 0.08, 7.0), thrall.aim_point())
		await _ticks(ceili((ability.follow_up_delay + 0.15) * Engine.physics_ticks_per_second))
		_check(_cuts(&"damage").size() == 1 and _cuts(&"cast_end").size() == 1,
			"The follow-up misses if solid cover comes between the actors" if block_with_cover
			else "The follow-up misses if the player leaves knife range")
		if is_instance_valid(cover):
			cover.queue_free()


func _check_enrage(authored_ability: MeleeAbilityDefinition) -> void:
	var ability := authored_ability.duplicate() as MeleeAbilityDefinition
	ability.double_slash_chance = 0.0
	ability.on_hit_effects = []
	ability.cooldown = 2.0
	var thrall := _prepare_duel(ability)
	await _wait_for_cuts(1)
	if not _check(_cuts(&"damage").size() == 1, "The Thrall attacks before reaching its Enrage threshold"):
		return
	var normal_damage := float(_cuts(&"damage")[0].amount)
	thrall.take_damage(69.0)
	_check(thrall.health == 31.0 and not thrall._statuses.has("enrage"),
		"At 31% Life the Thrall keeps its normal attack speed and damage")
	thrall.take_damage(1.0)
	_check(thrall.health == 30.0 and thrall._statuses.has("enrage") and _cuts(&"status", "Enrage").size() == 1,
		"A surviving hit at exactly 30% Life grants Enrage once")
	var cooldown_before: float = thrall._ability_runtime.remaining(ability)
	var clock_before: float = thrall._combat_time
	await _ticks(18)
	var elapsed: float = thrall._combat_time - clock_before
	var cooldown_spent: float = cooldown_before - thrall._ability_runtime.remaining(ability)
	_check(elapsed > 0.0 and is_equal_approx(cooldown_spent, elapsed * 1.15),
		"Enrage advances an existing attack cooldown 15% faster")
	await _wait_for_cuts(2)
	var hits := _cuts(&"damage")
	_check(hits.size() == 2 and absf(float(hits[1].amount) - normal_damage * 1.15) <= 1.0,
		"Enrage increases the same slash by 15% before whole-damage rounding")
	thrall.health = thrall.max_health
	_check(not thrall.receive_combat_effect(Enrage, Enrage.duration, 0.0, null, {}),
		"A temporary Enrage application preserves the Thrall's permanent Enrage")
	thrall._update_statuses(Enrage.duration + 1.0)
	_check(thrall._statuses.has("enrage") and thrall.health == thrall.max_health,
		"The Thrall's Enrage survives healing and outlasts the reusable effect's temporary duration")
	thrall.take_damage(73.0)
	_check(_cuts(&"status", "Enrage").size() == 1, "Dropping through 30% again does not reapply or log Thrall Enrage")

	var saved: Dictionary = thrall.save_behavior_state()
	var restored := _prepare_duel(ability)
	restored.restore_behavior_state(saved)
	_check(not saved.is_empty() and restored.health > restored.max_health * 0.30
		and restored._statuses.has("enrage") and _cuts(&"status", "Enrage").is_empty(),
		"Restoring a healed Thrall restores its active Enrage without a new status event")

	var temporary_enemy := Catalog.instantiate(1)
	temporary_enemy.setup(null, 1, "normal", RandomNumberGenerator.new())
	var temporary_applied: bool = temporary_enemy.receive_combat_effect(Enrage, Enrage.duration, 0.0, null, {})
	temporary_enemy._update_statuses(Enrage.duration * 0.5)
	_check(temporary_applied and temporary_enemy._statuses.has("enrage"),
		"An unrelated enemy can receive the same Enrage effect for its authored duration")
	temporary_enemy._update_statuses(Enrage.duration * 0.5)
	_check(not temporary_enemy._statuses.has("enrage"), "Temporary Enrage expires on an unrelated enemy")
	temporary_enemy.free()


func _prepare_duel(ability: AbilityDefinition) -> CharacterBody3D:
	_game._reset_training_combat()
	_game._combat_events.clear()
	var player: Node3D = _game.player
	player.stats.merge({"armor": 0.0, "ward": 0.0}, true)
	player.restore_full()
	_aim(Vector3(0.0, 0.08, 3.0), Vector3(0.0, 1.0, 1.35))
	var rules: Dictionary = _game._training_encounter.get_attack_rules()
	rules[&"hearth_melee"]["threshold"] = 20.0
	_game._training_encounter.attack_rules = rules
	var thrall := Catalog.instantiate(THRALL)
	thrall.base_life = 100.0
	thrall.base_attack_damage = 10.0
	thrall.mana_regeneration = 0.0
	thrall.ability_loadout[0] = ability
	thrall.setup(player, 1, "normal", RandomNumberGenerator.new(),
		Callable(_game.training_ground, "navigation_route"), Bestiary.combat_ability)
	thrall.configure_encounter(0, false, 16.0)
	thrall.configure_ai(_game._training_encounter, _game._training_pressure)
	thrall.combat_event.connect(_game._record_combat_event)
	thrall.position = Vector3(0.0, 0.08, 1.35)
	_game._training_actors.add_child(thrall)
	return thrall


func _wait_for_cuts(count: int) -> void:
	for frame in 180:
		if _cuts(&"damage").size() >= count:
			return
		await _ticks(1)


func _cuts(kind: StringName, ability_name: String = ABILITY_NAME, actor: String = ENEMY_NAME) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for event: Dictionary in _game._combat_events:
		if event.kind == kind and event.actor == actor and event.ability == ability_name:
			events.append(event)
	return events


func _spawn_thrall() -> CharacterBody3D:
	var player: Node3D = _game.player
	player.stats.merge({"max_health": 1000.0, "dodge_chance": 0.0, "life_regen": 0.0}, true)
	player.restore_full()
	_aim(Vector3(0.0, 0.08, 3.0), Vector3(0.0, 1.0, -3.0))
	await _tap(KEY_F1)
	var portrait := _game.training_roster.find_child("Enemy%d" % THRALL, true, false) as Button
	if not _check(_game.training_roster.is_open() and is_instance_valid(portrait), "The F1 roster offers Grave Thrall as ID 0"):
		return null
	portrait.grab_focus()
	await _tap(KEY_ENTER)
	for actor in _game._training_actors.get_children():
		if actor is CharacterBody3D and actor.archetype_id == THRALL:
			return actor
	_check(false, "Selecting the portrait spawns Grave Thrall")
	return null


func _gap(thrall: CharacterBody3D) -> float:
	var offset: Vector3 = thrall.global_position - _game.player.global_position
	return Vector2(offset.x, offset.z).length()


func _aim(point: Vector3, target: Vector3) -> void:
	var direction := (target - point - Vector3.UP * 1.56).normalized()
	_game.player.place_at(point, atan2(-direction.x, -direction.z), asin(direction.y))


func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(3)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _ticks(3)


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + description)
	else:
		_failures += 1
		push_error("FAIL  " + description)
	return condition
