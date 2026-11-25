extends SceneTree
## Exercises creature abilities through the live Training Ground and its F1 roster.

const Game = preload("res://main.tscn")
const Catalog = preload("res://combat/enemies/enemy_catalog.gd")
const AbilityDefinition = preload("res://combat/abilities/ability_definition.gd")
const Bestiary = preload("res://data/bestiary.gd")
const Cobweb = preload("res://combat/effects/enemy_cobweb.gd")
const EffectDefinition = preload("res://combat/effects/effect_definition.gd")
const Projectile = preload("res://combat/effects/enemy_projectile.gd")
const Arena = preload("res://world/training_ground.gd")

var _game: Node3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game._create_character(0, "Creature Tester")
	_aim(_game.hub.training_arrival_position(), _game.hub.interaction_position("training_portal"))
	await _tap(KEY_E)
	if _check(is_instance_valid(_game.training_ground), "The hub portal opens the Training Ground"):
		_game.player.stats.dodge_chance = 0.0
		_game.player.stats.life_regen = 0.0
		await _check_spider(3)
		await _check_spider(7)
		await _check_authored_cobweb()
		await _check_cover_and_dodge()
		await _check_moth()
	_game.free()
	await _ticks(2)
	print("Hearth Below creature abilities: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_spider(archetype: int) -> void:
	await _reset_arena()
	_game.player.place_at(Vector3(0.0, 0.08, 3.0))
	var spider := await _spawn(archetype)
	if spider == null:
		return
	var web_ability := _ability_for(spider, "cobweb")
	if not _check(web_ability != null and not web_ability.on_hit_effects.is_empty(),
			"%s equips an ability with an authored root effect" % spider.display_name):
		return
	var root_duration: float = web_ability.on_hit_effects[0].duration
	var starting_life: float = _game.player.life
	var runner := spider.get_node("Brain") as AIBehaviorRunner
	var saw_native_windup := false
	var saw_web := false
	for frame in 150:
		saw_native_windup = saw_native_windup or (spider._casting_cobweb and runner.get_active_node_ids().has(10))
		for actor in _game._training_actors.get_children():
			saw_web = saw_web or actor.get_script() == Cobweb
		if _game.player.is_cobweb_rooted():
			break
		await _ticks(1)
	_check(saw_native_windup and saw_web, "%s launches a cobweb through its native attack task" % spider.display_name)
	if not _check(_game.player.is_cobweb_rooted() and is_equal_approx(_game.player.life, starting_life),
			"%s lands a non-damaging root" % spider.display_name):
		return
	spider.set_physics_process(false)
	var origin: Vector3 = _game.player.global_position
	Input.action_press("forward")
	Input.action_press("sprint")
	Input.action_press("jump")
	_game.player.attack(false)
	_check(_game.player._strike_pending, "Weapon attacks still start while rooted")
	await _ticks(1)
	Input.action_release("jump")
	_check(absf(_game.player.global_position.y - origin.y) < 0.01, "The root prevents starting a jump")
	var remained_still := true
	var root_ticks := roundi(root_duration * Engine.physics_ticks_per_second)
	var elapsed := 1
	while _game.player.is_cobweb_rooted() and elapsed < root_ticks + 5:
		var offset: Vector3 = _game.player.global_position - origin
		remained_still = remained_still and Vector2(offset.x, offset.z).length_squared() < 0.0001
		await _ticks(1)
		elapsed += 1
	_check(remained_still, "Walking and sprinting cannot move the rooted player")
	_check(not _game.player.is_cobweb_rooted() and absi(elapsed - root_ticks) <= 1,
		"The root expires after the authored %.2f seconds (observed %d physics ticks)" % [root_duration, elapsed])
	await _ticks(8)
	Input.action_release("forward")
	Input.action_release("sprint")
	_check(_game.player.global_position.z < origin.z - 0.05, "Held movement resumes after the web releases")
	spider.set_physics_process(true)
	var ranged := bool(Catalog.ARCHETYPES[archetype].get("ranged", false))
	_check(await _observe_regular_attack(ranged), "%s still uses its regular %s attack after the web" % [
		spider.display_name, "ranged" if ranged else "melee",
	])


func _observe_regular_attack(ranged: bool) -> bool:
	var starting_life: float = _game.player.life
	for frame in 300:
		await _ticks(1)
		if ranged:
			for actor in _game._training_actors.get_children():
				if actor.get_script() == Projectile:
					return true
		elif _game.player.life < starting_life:
			return true
	return false


func _ability_for(actor: CharacterBody3D, action_key: String) -> AbilityDefinition:
	for ability: AbilityDefinition in actor.ability_loadout:
		if ability.action_key == action_key:
			return ability
	return null


func _check_authored_cobweb() -> void:
	await _reset_arena()
	var player: Node3D = _game.player
	player.place_at(Vector3(0.0, 0.08, 3.0))
	var spider := Catalog.instantiate(3)
	var stock_web := _ability_for(spider, "cobweb")
	var web_ability := stock_web.duplicate() as AbilityDefinition
	var root_effect := stock_web.on_hit_effects[0].duplicate() as EffectDefinition
	root_effect.duration = 0.75
	web_ability.on_hit_effects = [root_effect]
	web_ability.cooldown = 11.0
	spider.ability_loadout[spider.ability_loadout.find(stock_web)] = web_ability
	spider.setup(player, 3, "normal", RandomNumberGenerator.new(),
		Callable(_game.training_ground, "navigation_route"), Bestiary.combat_ability)
	spider.configure_encounter(0, false, 16.0)
	spider.configure_ai(_game._training_encounter, _game._training_pressure)
	spider.position = Vector3(0.0, 0.08, -3.0)
	_game._training_actors.add_child(spider)
	for frame in 150:
		if player.is_cobweb_rooted():
			break
		await _ticks(1)
	if not _check(player.is_cobweb_rooted() and spider._ability_runtime.remaining(web_ability) > 10.0,
			"The authored web ability starts its longer cooldown at release"):
		return
	spider.set_physics_process(false)
	var root_ticks := roundi(0.75 * Engine.physics_ticks_per_second)
	var elapsed := 0
	while player.is_cobweb_rooted() and elapsed < root_ticks + 3:
		await _ticks(1)
		elapsed += 1
	_check(not player.is_cobweb_rooted() and absi(elapsed - root_ticks) <= 1,
		"The authored 0.75-second root duration reaches the player through the projectile")


func _check_cover_and_dodge() -> void:
	await _reset_arena()
	var pillar_x: float = Arena.PILLAR_CENTERS[0]
	_game.player.place_at(Vector3(pillar_x, 0.08, 4.0))
	await _ticks(2)
	var spider := Catalog.instantiate(3)
	var web_ability := _ability_for(spider, "cobweb")
	spider.free()
	var profile := web_ability.execution_profile
	var web := preload("res://combat/effects/cobweb_projectile.tscn").instantiate() as Node3D
	_game._training_actors.add_child(web)
	web.launch(Vector3(pillar_x, 1.0, -4.0), _game.player.global_position + Vector3.UP,
		float(profile.speed), null, _game.player, float(profile.reach), web_ability.combat_details())
	for frame in 50:
		if not is_instance_valid(web) or web._speed == 0.0:
			break
		await _ticks(1)
	_check(is_instance_valid(web) and web._speed == 0.0 and web.global_position.z < -1.0
		and not _game.player.is_cobweb_rooted(), "A solid arena pillar stops the cobweb before it reaches the player")
	_game.player.place_at(Vector3(0.0, 0.08, 3.0))
	await _ticks(5)
	Input.action_press("jump")
	await _ticks(4)
	Input.action_release("jump")
	_check(not _game.player.is_on_floor() and _game.player.apply_cobweb_root(),
		"A jumping player can still be rooted by an incoming cobweb")
	for _tick in Engine.physics_ticks_per_second:
		if _game.player.is_on_floor() or not _game.player.is_cobweb_rooted():
			break
		await _ticks(1)
	_check(_game.player.is_on_floor() and _game.player.is_cobweb_rooted(),
		"Gravity still lands the player while they are rooted")


func _check_moth() -> void:
	await _reset_arena()
	var moth := await _spawn(9)
	if moth == null:
		return
	moth.global_position = Vector3(0.0, 0.08, -7.0)
	_game.player.place_at(Vector3(0.0, 0.08, 6.5))
	var deaths := [0]
	moth.died.connect(func(_enemy: CharacterBody3D): deaths[0] += 1)
	var identity := moth.get_instance_id()
	var original_life: float = moth.max_health
	var original_damage: float = moth._attack_damage()
	var original_speed: float = moth._movement_speed()
	var cocoon := _ability_for(moth, "cocoon")
	var profile := cocoon.execution_profile
	var gold: int = _game.inventory.gold
	moth.take_damage(100000.0, "physical", _game.player)
	if not _check(moth.is_cocoon() and deaths[0] == 0 and moth.is_in_group("enemies"),
			"Defeating a Grave Moth leaves its same attackable actor as a cocoon"):
		return
	var remaining := float(moth.save_metamorphosis().cocoon_remaining)
	_check(is_equal_approx(remaining, float(profile.hatch_seconds))
		and is_equal_approx(moth.health, original_life * float(profile.health_fraction)),
		"The cocoon starts with its own Life pool and a full hatch timer")
	await _ticks(4)
	var timer := _hatch_label(moth)
	_check(timer != null and moth._bar.visible and moth._bar.is_visible_in_tree(),
		"A living cocoon displays both a countdown and a Life bar")
	var shot := PhysicsRayQueryParameters3D.create(_game.player.camera.global_position, moth.aim_point(), 4)
	var collision := moth.get_world_3d().direct_space_state.intersect_ray(shot)
	_check(collision.get("collider") == moth, "A player weapon ray can hit the cocoon's body")
	await _tap(KEY_F1)
	var paused := float(moth.save_metamorphosis().cocoon_remaining)
	await _ticks(30)
	_check(_game.training_roster.is_open() and is_equal_approx(float(moth.save_metamorphosis().cocoon_remaining), paused),
		"Opening the F1 roster pauses the cocoon countdown")
	await _tap(KEY_F1)
	if not await _check_hatch(moth, identity, 1):
		return
	var stronger_life: float = moth.max_health
	var stronger_damage: float = moth._attack_damage()
	var stronger_speed: float = moth._movement_speed()
	_check(stronger_life > original_life and stronger_damage > original_damage and stronger_speed > original_speed,
		"The revived moth gains Life, attack damage, and movement speed")
	moth.take_damage(100000.0, "physical", _game.player)
	if not _check(moth.is_cocoon() and deaths[0] == 0, "A revived moth forms another cocoon when defeated"):
		return
	if not await _check_hatch(moth, identity, 2):
		return
	_check(moth.max_health > stronger_life and moth._attack_damage() > stronger_damage and moth._movement_speed() > stronger_speed,
		"A second hatch strengthens the moth again")
	moth.take_damage(100000.0, "physical", _game.player)
	_check(moth.is_cocoon() and deaths[0] == 0, "The cocoon cycle remains available after two hatches")
	moth.take_damage(100000.0, "physical", _game.player)
	_check(deaths[0] == 1 and not moth.is_in_group("enemies"), "Breaking the cocoon finishes the kill exactly once")
	await _ticks(260)
	var remaining_corpse_time := moth.get_node("CorpseLifetime") as Timer if is_instance_valid(moth) else null
	_check(is_instance_valid(moth) and moth._dead and moth.collision_layer == 0
		and remaining_corpse_time != null and remaining_corpse_time.time_left > 55.0
		and deaths[0] == 1 and _game.inventory.gold == gold,
		"A broken cocoon cannot revive or award campaign gold in training")


func _check_hatch(moth: CharacterBody3D, identity: int, expected_count: int) -> bool:
	var remaining := float(moth.save_metamorphosis().cocoon_remaining)
	var expected_ticks := ceili(remaining * Engine.physics_ticks_per_second)
	var elapsed := 0
	while moth.is_cocoon() and elapsed < expected_ticks + 5:
		await _ticks(1)
		elapsed += 1
	return _check(not moth.is_cocoon() and moth.get_instance_id() == identity
		and int(moth.save_metamorphosis().hatches) == expected_count and absi(elapsed - expected_ticks) <= 1,
		"Hatch %d occurs when the cast timer expires on the same actor" % expected_count)


func _hatch_label(moth: CharacterBody3D) -> Label3D:
	for node in moth.find_children("*", "Label3D", true, false):
		var label := node as Label3D
		if label.is_visible_in_tree() and "hatch" in label.text.to_lower():
			return label
	return null


func _reset_arena() -> void:
	_game._reset_training_combat()
	_game.player.restore_full()
	_game.player.place_at(_game.training_ground.spawn_position)
	await _ticks(4)


func _spawn(archetype: int) -> CharacterBody3D:
	await _tap(KEY_F1)
	var card := _game.training_roster.find_child("Enemy%d" % archetype, true, false) as Button
	if not _check(_game.training_roster.is_open() and is_instance_valid(card), "The F1 roster offers %s" % Catalog.ARCHETYPES[archetype].name):
		return null
	card.grab_focus()
	await _tap(KEY_ENTER)
	for actor in _game._training_actors.get_children():
		if actor is CharacterBody3D and actor.archetype_id == archetype:
			return actor
	_check(false, "The selected portrait spawns its creature")
	return null


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
