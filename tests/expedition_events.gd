extends SceneTree
## Integration fixture for rare expedition events on a named character.

const Game := preload("res://main.tscn")
const Dungeon := preload("res://world/dungeon.gd")
const Routes := preload("res://world/dungeon_route_gates.gd")
const CharacterSlots := preload("res://systems/character_slots.gd")
const SaveStore := preload("res://systems/save_store.gd")
const AltarRules := preload("res://data/blood_altar_rules.tres")

const NAME := "Expedition Fixture"
const SEED := 7395045
const LEGATE := 25
const RECLAIMER := 26

var _game: Node
var _save_path: String
var _checks := 0
var _failed := 0
var _awards: Array[String] = []
var _oath_sample_id := ""
var _oath_sample_life := 0.0
var _gate_id := ""
var _coffer_id := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_save_path = "user://test_runs/expedition_%d_%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	if await _boot():
		await _check_gate()
		await _check_altar()
		await _check_trial()
		await _check_legate()
		await _check_reclaimer()
		await _check_reload()
	_game.free()
	print("expedition_events: %d/%d checks passed" % [_checks - _failed, _checks])
	quit(1 if _failed > 0 else 0)


func _mount() -> void:
	_game = Game.instantiate()
	_game.save_directory = _save_path
	_game.preferences_path = _save_path.path_join("window.cfg")
	root.add_child(_game)


func _boot() -> bool:
	_mount()
	_game._create_character(0, NAME)
	if not _check(_game._character_name == NAME and _game._save_now() == OK,
			"A named character can create a native save slot"):
		return false
	var save := CharacterSlots.load_slot(_save_path, 0)
	var masks := [Dungeon.FEATURE_ROUTE_GATE, Dungeon.FEATURE_BLOOD_ALTAR, Dungeon.FEATURE_TRIAL_COFFER]
	save.unlocked = 6
	save.run = {
		"level": 6, "seed": str(SEED), "generation_version": Dungeon.GENERATION_VERSION,
		"rarity_version": _game.RARITY_PROFILE_VERSION, "cleared": false,
		"floor_index": 0, "floor_count": 3, "floor_rise": -1,
		"features": {"masks": masks, "legate": true},
	}
	if not _check(SaveStore.write_game(save, CharacterSlots.directory_for(_save_path, 0)) == OK,
			"Forced feature plan can be written to the isolated named slot"):
		return false
	_game.free()
	_mount()
	_game._select_character(0)
	if not _check(_game._character_name == NAME and _game._dungeon_floors.size() == 3,
			"Continue restores the named native campaign and all three floors"):
		return false
	_freeze_roster()
	_game.lifetime.achievement_unlocked.connect(_on_award)
	_game._enter_dungeon(true)
	await _ticks(4)
	return _check(_game.in_dungeon and _game._dungeon_floor_index() == 0,
		"The actual return portal path enters the saved first floor")


func _check_gate() -> void:
	var floor: Variant = _game._dungeon_floors[0]
	if not _check(floor.geometry.route_gates.size() == 1,
			"Fixed seed has one native route gate on its reserved floor"):
		return
	var route: Dictionary = floor.geometry.route_gates[0]
	_gate_id = String(route.id)
	var gate := _find_prop(floor.props, "route_gate")
	var key: Node3D = floor.loot.get("key_" + _gate_id)
	if not _check(is_instance_valid(gate) and is_instance_valid(key), "Gate and unique route key have physical scene nodes"):
		return
	var start: Vector2i = floor.geometry.tile_at(floor.geometry.to_global(floor.geometry.spawn_position))
	var reachable := Routes.reachable(floor.geometry.map_cells, start, route.gate_tile)
	_check(reachable.has(route.key_tile) and not reachable.has(route.gate_tile),
		"The gate's own key is accessible from the entrance with the gate shut")
	_check(_gate_collision(gate), "Closed portcullis blocks world collision")
	_game.inventory.add_treasure_keys()
	_interact(gate)
	_check(gate.pick_available() and _game.inventory.treasure_key_count() == 1,
		"An ordinary treasure key cannot open or be consumed by a route gate")
	_interact(key)
	_check(_game.run.collected_route_keys.has(_gate_id) and not floor.loot.has("key_" + _gate_id),
		"Interaction picks up the proper key and removes the physical drop")
	_interact(gate)
	await _ticks(48)
	_check(not gate.pick_available() and _game.run.opened_route_gates.has(_gate_id)
		and not _gate_collision(gate) and not _game.inventory.consume_route_key(_gate_id)
		and _game.inventory.treasure_key_count() == 1, "Correct key raises the gate, clears collision, and is spent once")


func _check_altar() -> void:
	await _enter_floor(1)
	var floor: Variant = _game._dungeon_floors[1]
	var altar: Node3D = floor.blood_altar
	if not _check(is_instance_valid(altar) and altar.pick_available(), "Blood Altar spawns usable on its reserved floor"):
		return
	var first_floor: Variant = _game._dungeon_floors[0]
	_oath_sample_id = String(first_floor.enemies.keys()[0])
	var sample: Node3D = first_floor.enemies[_oath_sample_id]
	var before_life: float = sample.max_health
	var before_damage: float = sample._base_damage
	var keys_before: int = _game.inventory.treasure_key_count()
	var oath := AltarRules.choice("key")
	_interact(altar)
	_check(_game._modal and _game.hud.is_menu_open(), "Interacting with the altar opens its native choice menu")
	_game.hud.blood_oath_selected.emit("key")
	_oath_sample_life = sample.max_health
	_check(_game.run.get("blood_oath") == "key" and not altar.pick_available()
		and _game.inventory.treasure_key_count() == keys_before + int(oath.keys),
		"Choosing a Blood Oath spends the altar and grants its key once")
	_check(is_equal_approx(sample.max_health, before_life * float(oath.life))
		and is_equal_approx(sample._base_damage, before_damage * float(oath.damage)),
		"Blood Oath changes a live enemy on another floor by the authored amounts")
	_game.hud.blood_oath_selected.emit("steel")
	_check(_game.run.get("blood_oath") == "key" and is_equal_approx(sample.max_health, _oath_sample_life)
		and _game.inventory.treasure_key_count() == keys_before + int(oath.keys),
		"The expedition cannot replace or compound its oath")


func _check_trial() -> void:
	await _enter_floor(2)
	var floor: Variant = _game._dungeon_floors[2]
	var coffer: Node3D
	for candidate: Node3D in floor.chests.values():
		if int(candidate.payload.trial_waves) > 1:
			coffer = candidate
			break
	if not _check(is_instance_valid(coffer), "A native multi-wave Trial Coffer spawns on its reserved floor"):
		return
	var room := int(coffer.payload.room)
	var total := int(coffer.payload.trial_waves)
	_coffer_id = String(coffer.payload.id)
	_interact(coffer)
	_check(int(_game.run.ambush_triggered.get(str(room), -1)) == 0 and not _game.run.opened.has(_coffer_id),
		"The first touch triggers one wave and leaves the coffer closed")
	for wave in total:
		_interact(coffer)
		var wave_number := int(_game.run.ambush_triggered.get(str(room), -1))
		var live: Array[Node3D] = []
		for id in floor.enemies:
			var entry: Dictionary = floor.enemy_origins[id].entry
			if int(entry.get("room", -1)) != room:
				continue
			_check(int(entry.get("wave", 0)) <= wave, "A future wave does not spawn ahead of schedule")
			live.append(floor.enemies[id])
		if not _check(not live.is_empty() and wave == wave_number and not _game.run.opened.has(_coffer_id),
				"Wave %d blocks the reward while living defenders remain" % (wave + 1)):
			return
		for defender in live:
			_kill(defender)
		_freeze_roster()
		await _ticks(2)
	_check(int(floor.room_enemies.get(room, 0)) == 0 and not _game.run.opened.has(_coffer_id),
		"Finishing the last wave unlocks the still unclaimed coffer")
	_game.inventory.add_treasure_keys()
	_interact(coffer)
	_interact(coffer)
	_check(_game.run.opened.has(_coffer_id) and int(_game.lifetime.snapshot().totals.get("trials_claimed", 0)) == 1,
		"After all waves the native reward and trial counter can only be claimed once")
	_check(_awards.count("trial_survivor") == 1 and "trial_survivor" in _game.lifetime.snapshot().awards,
		"Trial Survivor fires a single native achievement alert")


func _check_legate() -> void:
	await _enter_floor(0)
	var floor: Variant = _game._dungeon_floors[0]
	var arena := _find_site(floor, 4)
	if not _check(not arena.is_empty(), "Fixed first floor has a viable combat site for the incursion"):
		return
	_game._tick_legate_incursion(10.0)
	_check(not _game.run.get("legate_used", false), "An idle player cannot trigger the Legate")
	_game._add_incursion_enemy(floor, 0, "fixture_combat", 0, "normal", arena[0])
	var foe: Node3D = floor.enemies["fixture_combat"]
	foe.set_physics_process(false)
	foe._engaged = true
	foe._sight = true
	_game._tick_legate_incursion(0.5)
	_check(not _game.run.get("legate_used", false), "The Legate waits for sustained combat")
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 200):
		rng.seed = seed_value
		if rng.randf() < _game.LEGATE_CHANCE_PER_POLL:
			_game._rng.seed = seed_value
			break
	_game._tick_legate_incursion(5.0)
	if not _check(_game.run.get("legate_used", false) and floor.enemies.has("legate"),
			"Sustained nearby combat spawns the actual Grave Legate"):
		return
	_check(floor.enemies["legate"].archetype_id == LEGATE, "Incursion spawns the authored Legate archetype")
	var summoned := await _wait_cast(&"raise_the_levy", 330)
	_check(summoned and floor.enemies.has("levy_0") and floor.enemies.has("levy_1")
		and floor.enemies.has("levy_2") and floor.enemies["levy_0"].rarity == "rare",
		"The Legate's own completed cast adds three real reinforcements including a rare")
	_freeze_roster()
	var extra_count: int = _game.run.extra_enemies.size()
	_game._tick_legate_incursion(60.0)
	_check(int(_game.run.extra_enemies.size()) == extra_count, "An expedition does not spawn a second Legate")


func _check_reclaimer() -> void:
	await _enter_floor(1)
	var floor: Variant = _game._dungeon_floors[1]
	var arena := _find_site(floor, 3)
	if not _check(not arena.is_empty(), "Fixed second floor has room for the live Reclaimer fixture"):
		return
	const FALLEN_ID := "fixture_fallen"
	_game._add_incursion_enemy(floor, 1, FALLEN_ID, 0, "magic", arena[0])
	var fallen: Node3D = floor.enemies[FALLEN_ID]
	var original_affixes: Array = Array(fallen.affixes)
	var old_instance := fallen.get_instance_id()
	_kill(fallen)
	if not _check(floor.corpses.get(FALLEN_ID) == fallen and _game.run.defeated.has(FALLEN_ID),
			"A normal dungeon death registers the real corpse and its defeated ID"):
		return
	_game._add_incursion_enemy(floor, 1, "fixture_reclaimer", RECLAIMER, "normal", arena[1])
	var reclaimer: Node3D = floor.enemies["fixture_reclaimer"]
	_check(_game._find_dungeon_corpse(reclaimer, 12.0, 1) == fallen, "The Reclaimer can reach the actual fallen actor")
	var completed := await _wait_cast(&"raise_the_fallen", 430)
	if not _check(completed and floor.enemies.has(FALLEN_ID)
			and _game.run.revived.has(FALLEN_ID) and not floor.corpses.has(FALLEN_ID),
			"The authored cast replaces the old corpse with a live actor under the same stable ID"):
		return
	var raised: Node3D = floor.enemies[FALLEN_ID]
	_check(not is_instance_id_valid(old_instance) and raised.rarity == "magic"
		and Array(raised.affixes) == original_affixes and is_equal_approx(raised.health / raised.max_health, 0.54),
		"The raised actor retains rarity and affixes, has 54% life, and replaces the corpse node")
	_freeze_roster()
	var xp_before: Dictionary = _game.progression.snapshot()
	var drops_before: int = floor.loot.size()
	_kill(raised)
	_check(_game.progression.snapshot() == xp_before and floor.loot.size() == drops_before
		and not floor.corpses.has(FALLEN_ID), "Killing a raised enemy again grants no repeat XP, loot, or revival")


func _check_reload() -> void:
	_game._open_expedition_recap()
	_check(_game.hud.is_menu_open() and _has_label("Route gates opened") and _has_label("Enemies slain"),
		"Recap shows the route and combat records through the actual HUD")
	_game.hud.close_menu()
	_check(_game._save_now() == OK, "The active named campaign writes a checkpoint")
	_game.free()
	_mount()
	_game._select_character(0)
	_game.lifetime.achievement_unlocked.connect(_on_award)
	await _ticks(3)
	if not _check(_game._character_name == NAME and _game._dungeon_floors.size() == 3,
			"The checkpoint restores the right character and expedition"):
		return
	var first: Variant = _game._dungeon_floors[0]
	var second: Variant = _game._dungeon_floors[1]
	var sample: Node3D = first.enemies.get(_oath_sample_id)
	_check(_game.run.get("blood_oath") == "key" and is_instance_valid(second.blood_altar)
		and not second.blood_altar.pick_available() and is_instance_valid(sample)
		and is_equal_approx(sample.max_health, _oath_sample_life),
		"Reload keeps the Blood Oath and applies its bonus exactly once")
	_check(_game._floor_state(0).opened_route_gates.has(_gate_id) and _game._floor_state(2).opened.has(_coffer_id)
		and _game._floor_state(1).revived.has("fixture_fallen"),
		"Reload restores the gate, coffer, and consumed corpse histories on their original floors")
	_check(_awards.count("trial_survivor") == 1 and "trial_survivor" in _game.lifetime.snapshot().awards,
		"Reload restores Trial Survivor without creating another alert")
	_game._open_lifetime_statistics()
	_check(_game.hud.is_menu_open() and _has_label("Trial coffers looted"),
		"The native lifetime view exposes the persisted trial counter")


func _enter_floor(index: int) -> void:
	_game._select_floor_state(index)
	_game._use_dungeon_floor(index)
	var geometry: Node3D = _game._dungeon_floors[index].geometry
	_game.player.place_at(geometry.to_global(geometry.spawn_position), 0.0)
	await _ticks(3)


func _find_site(floor: Variant, count: int) -> Array[Vector3]:
	var geometry: Node3D = floor.geometry
	var tiles: Array = geometry.map_cells.keys()
	for tile: Vector2i in tiles:
		var point: Vector3 = geometry.to_global(geometry.tile_position(tile))
		if not geometry.ground_is_open(point):
			continue
		_game.player.place_at(point, 0.0)
		var candidates: Array[Vector3] = _game._incursion_positions(floor, point, count)
		if candidates.size() >= count:
			return candidates
	return []


func _gate_collision(gate: Node3D) -> bool:
	var position_at_rail := gate.global_position + Vector3.UP * 1.25
	var offset := gate.global_basis.z.normalized() * 0.8
	var ray := PhysicsRayQueryParameters3D.create(position_at_rail - offset, position_at_rail + offset, 1)
	var hit := root.world_3d.direct_space_state.intersect_ray(ray)
	return hit.get("collider") == gate


func _find_prop(props: Node, kind: String) -> Node3D:
	for prop in props.get_children():
		if prop.get("payload") is Dictionary and String(prop.payload.get("kind", "")) == kind:
			return prop
	return null


func _interact(prop: Node3D) -> void:
	_game._last_target = prop
	_game._interact()


func _freeze_roster() -> void:
	for floor in _game._dungeon_floors.values():
		for enemy in floor.enemies.values():
			enemy.set_physics_process(false)


func _kill(enemy: Node3D) -> void:
	for attempt in 2:
		if not is_instance_valid(enemy) or enemy._dead:
			break
		enemy.take_damage(100000.0, "physical")


func _wait_cast(ability: StringName, frame_limit: int) -> bool:
	for tick in frame_limit:
		if _game._combat_events.any(func(event: Dictionary) -> bool:
				return event.kind == &"cast_end" and StringName(event.get("ability_id", "")) == ability):
			await _ticks(2)
			return true
		await physics_frame
	return false


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _on_award(entry: Dictionary) -> void:
	_awards.append(String(entry.id))


func _has_label(value: String) -> bool:
	for label: Label in _game.hud.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text == value:
			return true
	return false


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS " + description)
	else:
		_failed += 1
		printerr("FAIL " + description)
	return condition
