extends SceneTree
## Exercises shared Bleed through actual incoming and outgoing hit resolution.

const Game = preload("res://main.tscn")
const Catalog = preload("res://combat/enemies/enemy_catalog.gd")
const AbilityDefinition = preload("res://combat/abilities/ability_definition.gd")
const BleedEffectDefinition = preload("res://combat/effects/bleed_effect_definition.gd")
const Bleed = preload("res://combat/effects/bleed.tres")
const Poison = preload("res://combat/effects/poisoned.tres")
const Cut = preload("res://combat/abilities/graveknife_cut.tres")
const Lash = preload("res://combat/abilities/thornback_lash.tres")
const HitEffects = preload("res://combat/effects/hit_effects.gd")

var _game: Node3D
var _bleeding_lash: AbilityDefinition
var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game.title_screen.training_requested.emit()
	var player: Node3D = _game.player
	_bleeding_lash = Lash.duplicate() as AbilityDefinition
	var guaranteed_bleed := Bleed.duplicate() as BleedEffectDefinition
	guaranteed_bleed.chance = 100.0
	guaranteed_bleed.while_active_fx = null
	_bleeding_lash.on_hit_effects = [guaranteed_bleed]
	player.stats.merge({
		"max_health": 1000.0, "armor": 0.0, "ward": 0.0, "dodge_chance": 0.0,
		"life_regen": 0.0, "bleed_chance": 0.0,
		"bleed_damage": 0.0, "damage_over_time": 0.0, "physical_dot_reduction": 0.0,
	}, true)
	_check(is_equal_approx(Bleed.duration, 5.0) and is_equal_approx(Bleed.damage_per_second(100.0), 14.0),
		"The standard Bleed preset deals 70% over five seconds")
	_check(Bleed.icon != null and Bleed.icon.get_width() > 0 and Bleed.application_effect != null,
		"The standard Bleed preset supplies the icon and application particles")
	var cut_bleed := Cut.on_hit_effects[0] as BleedEffectDefinition if Cut.on_hit_effects.size() == 1 else null
	_check(cut_bleed != null and cut_bleed.resource_path.begins_with(Cut.resource_path + "::")
		and cut_bleed.id == Bleed.id and cut_bleed.chance == 25.0
		and cut_bleed.duration == 5.0 and cut_bleed.hit_damage_percent == 70.0
		and cut_bleed.icon == Bleed.icon and cut_bleed.application_effect == Bleed.application_effect,
		"Graveknife Cut stores its own inline Bleed preset and shares the standard visuals and status")
	await _check_incoming(player)
	_check_reapplication(player)
	_check_chance(player)
	if cut_bleed != null:
		_check_presets(player, cut_bleed)
	_check_visual_phases(player)
	await _check_outgoing(player)
	_check_outgoing_level_gap(player)
	_game.free()
	await process_frame
	print("Hearth Below Bleed: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_incoming(player: Node3D) -> void:
	player.stats.armor = 500.0
	player.stats.ward = 60.0
	player.stats.physical_dot_reduction = 20.0
	player.restore_full()
	var icon := _game.hud.find_child("BleedStatusIcon", true, false) as TextureRect
	var countdown := _game.hud.find_child("BleedStatusCountdown", true, false) as Label
	var has_hud := is_instance_valid(icon) and is_instance_valid(countdown)
	_check(player.receive_enemy_hit(100.0, "physical", "", null, _bleeding_lash.combat_details())
		and is_equal_approx(player.ward, 10.0) and is_equal_approx(player.life, 1000.0)
		and is_equal_approx(float(player._ailments.get("bleed", {}).get("damage", 0.0)), 14.0),
		"An armored hit absorbed by Ward still applies Bleed from its base Physical damage")
	_check(has_hud and icon.is_visible_in_tree() and icon.texture == Bleed.icon and countdown.text == "5",
		"The player HUD shows the shared Bleed icon with five seconds remaining")

	player._tick_ailments(1.0)
	_check(has_hud and icon.is_visible_in_tree() and countdown.text == "4",
		"The player Bleed countdown updates as combat time elapses")
	player._tick_ailments(3.8)
	_check(player._ailments.has("bleed") and is_equal_approx(player.life, 956.0)
		and is_zero_approx(player.ward),
		"Physical damage-over-time reduction affects the ticks and Ward absorbs damage before Life")
	player._tick_ailments(0.2)
	_check(not player._ailments.has("bleed") and is_equal_approx(player.life, 954.0),
		"The incoming Bleed delivers the exact mitigated total and expires at five seconds")
	_check(has_hud and not icon.is_visible_in_tree() and countdown.text.is_empty(),
		"The player HUD clears the icon and countdown when Bleed expires")

	var original_max_stamina: float = player.stats.max_stamina
	player.stats.max_stamina = 200.0
	player.restore_full()
	player.receive_enemy_hit(100.0, "physical", "", null, _bleeding_lash.combat_details())
	Input.action_press("block")
	await _ticks(1)
	var blocked: bool = not player.receive_enemy_hit(150.0, "physical", "", null, _bleeding_lash.combat_details())
	_check(player.is_blocking() and blocked and player.stamina < player.stats.max_stamina
		and is_equal_approx(player.ward, 10.0)
		and is_equal_approx(float(player._ailments.get("bleed", {}).get("damage", 0.0)), 14.0),
		"A manual block stops a new hit and its Bleed from replacing the one already applied")
	var guarding_stamina: float = player.stamina
	player._tick_ailments(1.0)
	_check(player.is_blocking() and is_equal_approx(player.stamina, guarding_stamina)
		and is_equal_approx(player.life, 999.0) and is_zero_approx(player.ward),
		"Existing Bleed continues through the raised guard without spending Stamina")
	Input.action_release("block")
	await _ticks(1)

	player.stats.merge({"armor": 0.0, "ward": 0.0, "max_stamina": original_max_stamina, "physical_dot_reduction": 0.0}, true)
	player.restore_full()
	var dodge_seed := 1
	var evasion_rng := RandomNumberGenerator.new()
	evasion_rng.seed = dodge_seed
	while evasion_rng.randf() >= 0.60:
		dodge_seed += 1
		evasion_rng.seed = dodge_seed
	player._rng.seed = dodge_seed
	player.stats.dodge_chance = 60.0
	_check(not player.receive_enemy_hit(100.0, "physical", "", null, _bleeding_lash.combat_details())
		and not player._ailments.has("bleed") and is_equal_approx(player.life, 1000.0),
		"A dodged hit cannot apply Bleed")
	player.stats.dodge_chance = 0.0
	_check(player.receive_enemy_hit(100.0, "fire", "", null, _bleeding_lash.combat_details())
		and not player._ailments.has("bleed"), "An elemental-only hit cannot apply Bleed")


func _check_reapplication(player: Node3D) -> void:
	player.restore_full()
	var hit := _bleeding_lash.combat_details()
	player.receive_enemy_hit(100.0, "physical", "", null, hit)
	player._tick_ailments(1.0)
	player.receive_enemy_hit(50.0, "physical", "", null, hit)
	var bleed: Dictionary = player._ailments.get("bleed", {})
	_check(bleed.size() > 0 and is_equal_approx(float(bleed.get("damage", 0.0)), 14.0)
		and is_equal_approx(float(bleed.get("remaining", 0.0)), 4.0),
		"A weaker Bleed leaves the strongest effect and its timer alone")
	player.receive_enemy_hit(100.0, "physical", "", null, hit)
	bleed = player._ailments.get("bleed", {})
	_check(is_equal_approx(float(bleed.get("damage", 0.0)), 14.0)
		and is_equal_approx(float(bleed.get("remaining", 0.0)), 5.0),
		"An equal Bleed refreshes the shared timer")
	player.receive_enemy_hit(150.0, "physical", "", null, hit)
	bleed = player._ailments.get("bleed", {})
	_check(player._ailments.size() == 1 and is_equal_approx(float(bleed.get("damage", 0.0)), 21.0)
		and is_equal_approx(float(bleed.get("remaining", 0.0)), 5.0),
		"A stronger Bleed replaces the current one without stacking")
	player.restore_full()
	player.receive_enemy_hit(100.0, "physical", "", null, hit)
	player._tick_ailments(0.1)
	player.receive_enemy_hit(150.0, "physical", "", null, hit)
	player._tick_ailments(5.0)
	_check(is_equal_approx(player.life, 1000.0 - 100.0 - 150.0 - 106.0),
		"An incoming Bleed replacement preserves damage accrued before the first tick")
	player.restore_full()
	player.receive_combat_effect(Bleed, 2.0, 3.0, null, hit)
	player._tick_ailments(0.2)
	var rounded_first_tick: bool = is_equal_approx(player.life, 999.0)
	player.receive_combat_effect(Bleed, 0.2, 3.2, null, hit)
	player._tick_ailments(0.2)
	_check(rounded_first_tick and is_equal_approx(player.life, 999.0) and not player._ailments.has("bleed"),
		"Replacing Bleed carries the fractional remainder and avoids rounding two small ticks up separately")


func _check_chance(player: Node3D) -> void:
	var enemy := Catalog.instantiate(0)
	enemy.setup(null, 1, "normal", RandomNumberGenerator.new())
	var rng := RandomNumberGenerator.new()
	var expected := RandomNumberGenerator.new()
	for seed_value in range(100):
		expected.seed = seed_value
		var roll := expected.randf() * 100.0
		if roll >= 25.0 and roll < 40.0:
			rng.seed = seed_value
			break
	var roll_seed := rng.seed
	_check(not HitEffects.apply_on_hit(Cut.on_hit_effects, enemy, 100.0, 100.0, player, {}, rng, 100.0)
		and not enemy._statuses.has("bleed"), "A roll above the ability's chance misses without an attacker bonus")
	rng.seed = roll_seed
	player.stats.bleed_chance = 15.0
	_check(HitEffects.apply_on_hit(Cut.on_hit_effects, enemy, 100.0, 100.0, player, {}, rng, 100.0)
		and enemy._statuses.has("bleed") and rng.state == expected.state,
		"25% from an ability and 15% from the attacker use one 40% roll")
	enemy._statuses.clear()
	player.stats.bleed_chance = 80.0
	_check(HitEffects.apply_on_hit(Cut.on_hit_effects, enemy, 100.0, 100.0, player, {}, null, 100.0),
		"Combined Bleed chance caps at a guaranteed 100%")
	enemy._statuses.clear()
	player.stats.merge({"bleed_chance": 100.0, "bleed_damage": 20.0, "damage_over_time": 30.0}, true)
	_check(HitEffects.apply_on_hit([], enemy, 100.0, 100.0, player, {}, rng, 100.0)
		and is_equal_approx(float(enemy._statuses.get("bleed", {}).get("potency", 0.0)), 21.0),
		"Attacker stats grant Bleed to an ordinary hit and scale its shared damage once")
	player.stats.merge({"bleed_chance": 0.0, "bleed_damage": 0.0, "damage_over_time": 0.0}, true)
	enemy.free()


func _check_presets(player: Node3D, cut_bleed: BleedEffectDefinition) -> void:
	var custom_cut := Cut.duplicate() as AbilityDefinition
	var custom_bleed := cut_bleed.duplicate() as BleedEffectDefinition
	custom_bleed.chance = 100.0
	custom_bleed.duration = 2.5
	custom_bleed.hit_damage_percent = 80.0
	custom_cut.on_hit_effects = [custom_bleed]
	player.restore_full()
	player.receive_enemy_hit(100.0, "physical", "", null, _bleeding_lash.combat_details())
	player._tick_ailments(1.0)
	player.receive_enemy_hit(100.0, "physical", "", null, custom_cut.combat_details())
	var active: Dictionary = player._ailments.get("bleed", {})
	var countdown := _game.hud.find_child("BleedStatusCountdown", true, false) as Label
	_check(player._ailments.size() == 1 and active.get("effect") == custom_bleed
		and is_equal_approx(float(active.get("remaining", 0.0)), 2.5)
		and is_equal_approx(float(active.get("damage", 0.0)), 32.0)
		and is_instance_valid(countdown) and countdown.text == "3",
		"The stronger preset takes over with its own damage, duration and HUD countdown")
	player._tick_ailments(0.5)
	player.receive_enemy_hit(100.0, "physical", "", null, _bleeding_lash.combat_details())
	active = player._ailments.get("bleed", {})
	_check(active.get("effect") == custom_bleed and is_equal_approx(float(active.get("remaining", 0.0)), 2.0),
		"A weaker preset leaves the stronger Bleed and its current timer in place")
	player._tick_ailments(2.0)
	_check(not player._ailments.has("bleed") and is_equal_approx(player.life, 606.0),
		"The selected preset expires on time and deals its authored 80% total")


func _check_visual_phases(player: Node3D) -> void:
	player.restore_full()
	var move := Cut.duplicate() as AbilityDefinition
	var effect := Bleed.duplicate() as BleedEffectDefinition
	move.hit_fx = _visual_probe(&"HitVisual")
	move.on_hit_effects = [effect]
	effect.chance = 0.0
	effect.on_applied_fx = _visual_probe(&"AppliedVisual")
	effect.while_active_fx = _visual_probe(&"ActiveVisual")
	effect.on_end_fx = _visual_probe(&"EndVisual")
	_check(player.receive_enemy_hit(10.0, "physical", "", null, move.combat_details())
		and player.has_node("HitVisual") and not player.has_node("AppliedVisual") and not player._ailments.has("bleed"),
		"A confirmed hit plays the ability visual independently of the Bleed roll")

	effect.chance = 100.0
	player.receive_enemy_hit(10.0, "physical", "", null, move.combat_details())
	var loop: Node3D = player.get_node_or_null("ActiveVisual")
	_check(is_instance_valid(loop) and player.has_node("AppliedVisual"),
		"Accepted Bleed spawns its own application burst and one active visual")
	player._tick_ailments(2.0)
	player.receive_enemy_hit(10.0, "physical", "", null, move.combat_details())
	_check(is_instance_valid(loop) and player._ailments.get("bleed", {}).get("active_visual") == loop
		and get_nodes_in_group(&"ActiveVisual").size() == 1
		and is_equal_approx(float(player._ailments.get("bleed", {}).get("remaining", 0.0)), 5.0),
		"An equal refresh keeps one live visual and resets the status timer")
	player._tick_ailments(5.0)
	_check(is_instance_valid(loop) and loop.is_queued_for_deletion() and not loop.visible and player.has_node("EndVisual"),
		"Status expiration removes the loop and plays its end visual")

	player.receive_enemy_hit(10.0, "physical", "", null, move.combat_details())
	var cleanup_loop: Node3D = player._ailments.get("bleed", {}).get("active_visual")
	player.restore_full()
	_check(is_instance_valid(cleanup_loop) and cleanup_loop.is_queued_for_deletion()
		and not player._ailments.has("bleed"), "Restoring the player also removes active status visuals")


func _visual_probe(node_name: StringName) -> PackedScene:
	var node := Node3D.new()
	node.name = node_name
	node.add_to_group(node_name, true)
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


func _check_outgoing(player: Node3D) -> void:
	_game._reset_training_combat()
	player.stats.merge({"damage_min": 50.0, "damage_max": 50.0, "fire_damage": 30.0,
		"crit_chance": 75.0}, true)
	player.restore_full()
	var enemy := Catalog.instantiate(0)
	enemy.base_life = 1000.0
	var affixes: Array[String] = ["armored"]
	enemy.setup(player, 1, "magic", RandomNumberGenerator.new(), Callable(), Callable(), affixes)
	enemy.configure_ai(_game._training_encounter, _game._training_pressure)
	enemy.position = Vector3(0.0, 0.08, 1.35)
	_game._training_actors.add_child(enemy)
	enemy.set_physics_process(false)
	var origin := Vector3(0.0, 0.08, 3.0)
	var direction: Vector3 = (enemy.aim_point() - origin - Vector3.UP * 1.56).normalized()
	player.place_at(origin, atan2(-direction.x, -direction.z), asin(direction.y))
	await _ticks(2)
	var rng := RandomNumberGenerator.new()
	for seed_value in range(100):
		rng.seed = seed_value
		if rng.randf() < 0.75:
			player._rng.seed = seed_value
			break

	var starting_health: float = enemy.health
	if not _check(player.cast_ability(_bleeding_lash), "The player starts an authored Bleed attack"):
		return
	for tick in ceili((_bleeding_lash.windup + 0.25) * Engine.physics_ticks_per_second):
		if enemy._statuses.has("bleed"):
			break
		await _ticks(1)
	var damage_on_impact := roundf((50.0 * 0.70 + 30.0) * 1.5 * _bleeding_lash.damage_multiplier)
	var bleed_damage := 50.0 * _bleeding_lash.damage_multiplier * 0.70
	_check(enemy._statuses.has("bleed") and is_equal_approx(enemy.health, starting_health - damage_on_impact)
		and is_equal_approx(float(enemy._statuses.get("bleed", {}).get("potency", 0.0)), bleed_damage / 5.0),
		"A critical Physical and Fire strike applies Bleed from its pre-crit Physical base only")
	var icon := enemy.find_child("BleedStatusIcon", true, false) as Sprite3D
	_check(is_instance_valid(icon) and icon.visible and icon.texture == Bleed.icon
		and enemy.find_child("BleedStatusCountdown", true, false) == null,
		"A Bleeding enemy shows the same icon with no countdown")
	var particles := enemy.find_child("BleedApplicationParticles", false, false) as GPUParticles3D
	var cleanup := particles.get_node_or_null("Cleanup") as Timer if is_instance_valid(particles) else null
	if _check(is_instance_valid(particles) and particles.one_shot
			and is_instance_valid(cleanup) and cleanup.time_left > 0.0,
			"Applying Bleed to an enemy starts a one-shot particle effect with cleanup"):
		await _ticks(ceili((cleanup.wait_time + 0.1) * Engine.physics_ticks_per_second))
		_check(not is_instance_valid(particles), "The Bleed application particles clean themselves up")
	enemy._update_statuses(4.8)
	_check(enemy._statuses.has("bleed"), "Outgoing Bleed is still active before five seconds")
	enemy._update_statuses(0.2)
	_check(not enemy._statuses.has("bleed")
		and is_equal_approx(enemy.health, starting_health - damage_on_impact - roundf(bleed_damage)),
		"The Armored affix mitigates the hit while outgoing Bleed delivers its rounded total")
	_check(is_instance_valid(icon) and not icon.visible, "The enemy Bleed icon hides on expiry")
	var health_before_refresh: float = enemy.health
	HitEffects.apply_on_hit(_bleeding_lash.on_hit_effects, enemy, 100.0, 100.0, player, {}, null, 100.0)
	enemy._update_statuses(0.1)
	HitEffects.apply_on_hit(_bleeding_lash.on_hit_effects, enemy, 150.0, 150.0, player, {}, null, 150.0)
	enemy._update_statuses(5.0)
	_check(is_equal_approx(enemy.health, health_before_refresh - 106.0),
		"An outgoing Bleed replacement preserves damage accrued before the first tick")

	var effect := Bleed.duplicate() as BleedEffectDefinition
	effect.while_active_fx = _visual_probe(&"EnemyFallbackLoop")
	effect.enemy_while_active_fx = _visual_probe(&"EnemyDefeatLoop")
	effect.on_end_fx = _visual_probe(&"EnemyDefeatEnd")
	enemy.receive_combat_effect(effect, effect.duration, 14.0, player, {})
	var active_fx: Node3D = enemy.get_node_or_null("EnemyDefeatLoop")
	_check(is_instance_valid(active_fx) and not enemy.has_node("EnemyFallbackLoop")
		and enemy._statuses.get("bleed", {}).get("active_visual") == active_fx,
		"Enemies use the authored enemy-specific active Bleed visual if one is provided")
	enemy.take_damage(enemy.health * 2.0, "fire", player)
	_check(is_instance_valid(active_fx) and active_fx.is_queued_for_deletion()
		and not active_fx.visible and enemy.has_node("EnemyDefeatEnd"),
		"Defeat removes the enemy's active visual and plays its end effect")


func _check_outgoing_level_gap(player: Node3D) -> void:
	var enemy := Catalog.instantiate(0)
	enemy.setup(player, 25, "normal", RandomNumberGenerator.new(), Callable())
	_game._training_actors.add_child(enemy)
	enemy.set_physics_process(false)
	var hit: float = enemy.take_damage(100.0, "physical", player)
	_check(is_equal_approx(hit, 1.0), "A level 1 hit takes the level 25 penalty once before rounding")
	var before: float = enemy.health
	HitEffects.apply_on_hit(_bleeding_lash.on_hit_effects, enemy, hit, hit, player, {}, null, 100.0)
	var potency := float(enemy._statuses.get("bleed", {}).get("potency", 0.0))
	enemy._update_statuses(5.0)
	_check(is_equal_approx(potency, 0.07) and is_equal_approx(before, enemy.health),
		"Bleed takes the level penalty once and its sub-half-point total rounds to zero")
	var poison := Poison.duplicate() as EffectDefinition
	poison.chance = 100.0
	hit = enemy.take_damage(1000.0, "physical", player)
	before = enemy.health
	HitEffects.apply_on_hit([poison], enemy, hit, hit, player, {}, null)
	enemy._update_statuses(poison.duration)
	var expected := roundf(poison.on_hit_potency(hit) * poison.duration)
	_check(is_equal_approx(before - enemy.health, expected) and expected > 0.0,
		"Poison seeded from dealt damage keeps its level penalty without applying it again to ticks")


func _ticks(count: int) -> void:
	for tick in count:
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
