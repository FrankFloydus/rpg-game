extends SceneTree

const Game = preload("res://main.tscn")
const Dungeon = preload("res://world/dungeon.gd")
const CharacterSlots = preload("res://systems/character_slots.gd")
const Items = preload("res://systems/items.gd")
const Inventory = preload("res://systems/inventory.gd")

var _errors := 0
var _checks := 0
var _game: Node3D
var _save_path := "user://test_runs/hearth_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_saved_gear_balance()
	_mount_game(false)
	_check_gold_pacing()
	_check(_game.title_screen.is_open() and _game._modal,
		"Boot shows the title screen with gameplay paused")
	_check(_game.title_screen._buttons.size() == CharacterSlots.SLOT_COUNT and _game.title_screen._characters.is_empty(),
		"An empty roster offers ten character slots")
	_game._save_now()
	await _ticks(30)
	_check(CharacterSlots.list_slots(_save_path).is_empty(), "The title screen does not create a checkpoint")
	_game.title_screen.settings_requested.emit()
	_check(_game._modal and is_instance_valid(_menu_button("Fullscreen")),
		"Title Settings opens while gameplay stays paused")
	await _tap(KEY_ESCAPE)
	_check(_game.title_screen.is_open() and _game._modal,
		"Escape from title Settings returns to the title")
	_game._create_character(0, "Crypt Tester")
	await _ticks(8)
	_check(not _game.title_screen.is_open() and not _game._modal, "New closes the title and starts gameplay")
	_check(not _game.in_dungeon and _game.unlocked == 1, "Fresh character spawns in the hub")
	_check(_game.player.weapon_type == "sword_1h", "Starter sword is equipped")
	var starting_gold: int = _game.inventory.gold
	_check(_game.bestiary_discoveries.is_empty(), "A fresh character starts with an undiscovered bestiary")
	await _tap(KEY_ESCAPE)
	var settings := _menu_button("Settings")
	_check(is_instance_valid(settings), "Pause menu offers Settings")
	if is_instance_valid(settings):
		settings.pressed.emit()
		var fullscreen := _menu_button("Fullscreen") as CheckButton
		_check(is_instance_valid(fullscreen) and not fullscreen.button_pressed, "Fullscreen starts unchecked")
		if is_instance_valid(fullscreen):
			fullscreen.button_pressed = true
			_check(_game._fullscreen, "Fullscreen checkbox updates the game preference")
		var library := _menu_button("Bestiary")
		_check(is_instance_valid(library), "Settings offers the Bestiary")
		if is_instance_valid(library):
			library.pressed.emit()
			_check(_game.bestiary.is_open() and _game._modal, "The Bestiary opens from Settings while gameplay stays paused")
			await _tap(KEY_ESCAPE)
			_check(not _game.bestiary.is_open() and is_instance_valid(_menu_button("Fullscreen")),
				"Escape from the Bestiary grid returns to Settings")

		await _tap(KEY_ESCAPE)
		_check(is_instance_valid(_menu_button("Resume")) and _game._modal,
			"Escape from Settings returns to the paused menu")
		await _tap(KEY_ESCAPE)
		_check(not _game._modal, "Escape from Pause resumes play")
	_check(_game.inventory.get_grid("vendor").get_placements().size() == 10, "Initial vendor catalogue has ten offers")
	var original_stock: Array = _game.inventory.get_grid("vendor").get_placements().duplicate(true)
	var before: Vector3 = _game.player.global_position
	Input.action_press("forward")
	await _ticks(18)
	Input.action_release("forward")
	_check(_game.player.global_position.z < before.z - 0.4, "Forward input moves the player")
	_game._select_depth(2)
	_check(_game.run.is_empty(), "A higher depth stays locked before the previous clear")
	var altar: Vector3 = _game.hub.interaction_position("altar")
	_game.player.place_at(Vector3(altar.x, 0.08, altar.z))
	await _ticks(10)
	_check(_game.hud.is_menu_open(), "Overlapping the altar opens the depth menu")
	_game._rng.seed = 7395045
	_game.hud.level_selected.emit(1)
	await _ticks(14)
	_check(_game.in_dungeon and _game.run.level == 1, "Selecting Depth I mounts the dungeon")
	_check(int(_game.run.generation_version) == Dungeon.GENERATION_VERSION, "New runs record their generator version")
	_check(_game._dungeon_floor_count() == 2 and _game._dungeon_floor_index() == 0 and
		not _game._enemies.is_empty() and _game.dungeon.rooms.size() == 6,
		"Opening depth starts on two compact populated floors")
	_check(not _game.dungeon.room_names.is_empty(), "Generated chambers provide distinct room names")
	var corridor := 0
	var at_entry := 0
	for entry: Dictionary in _game.dungeon.encounters:
		var tile: Vector2i = _game.dungeon.tile_at(entry.position)
		var room := int(_game.dungeon.map_cells.get(tile, -2))
		if room == -1:
			corridor += 1
		if room == 0:
			at_entry += 1
	_check(at_entry == 0 and corridor > 0 and corridor < _game._enemies.size() * 0.33,
		"The arrival room is clear and encounters concentrate in chambers")
	_check(_game._chests.size() >= 2, "Dungeon contains treasure chests")
	_check(_game.bestiary_discoveries.is_empty(), "Dungeon generation leaves unseen enemies undiscovered")

	var anchor: Vector3 = _game.dungeon.spawn_position
	var enemy: CharacterBody3D = _game._enemies.values()[0]
	var focus := enemy.aim_point() as Vector3
	var stand := enemy.global_position + Vector3(0, 0.03, 1.72)
	var space := _game.player.get_world_3d().direct_space_state as PhysicsDirectSpaceState3D
	for direction in [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]:
		var candidate: Vector3 = enemy.global_position + direction * 1.72
		candidate.y = 0.05
		var sight := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 1.56, focus, 1)
		if _game.dungeon.map_cells.has(_game.dungeon.tile_at(candidate)) and space.intersect_ray(sight).is_empty():
			stand = candidate
			break
	_aim(stand, focus)
	await _ticks(3)
	_aim(stand, enemy.aim_point())
	var previous_health: float = enemy.health
	Input.action_press("attack")
	await _ticks(3)
	Input.action_release("attack")
	_check(is_equal_approx(enemy.health, previous_health), "Swing has a committed wind-up before contact")
	await _ticks(14)
	_check(enemy.health < previous_health, "A committed swing hits after releasing the attack button")
	var discovered_id: int = enemy.archetype_id
	var discovered_name: String = enemy.archetype_name
	_check(_game.bestiary_discoveries.has(discovered_id), "A first encounter unlocks that enemy")
	var discovery_message := "%s added to bestiary" % discovered_name
	_check(_game.hud._discovery_text.text == discovery_message or discovered_name in _game.hud._discovery_queue,
		"First encounters display a bestiary discovery message")
	var pending_notices: int = _game.hud._discovery_queue.size()
	var discovered_count: int = _game.bestiary_discoveries.size()
	enemy.encountered.emit(enemy)
	_check(_game.bestiary_discoveries.size() == discovered_count and
		_game.hud._discovery_queue.size() == pending_notices, "Repeat encounters do not duplicate the unlock or notice")
	enemy.take_damage(10000.0, "physical", _game.player)
	_check(_game.run.defeated.size() == 1 and not _game.run.loot.is_empty(), "Enemy death is recorded and produces ground loot")

	var gold_before: int = _game.inventory.gold
	var loose_gold: Node3D
	for candidate in _game._loot.values():
		if candidate.payload.category == "gold":
			loose_gold = candidate
			break
	_check(is_instance_valid(loose_gold) and not loose_gold.pick_available(), "Dropped gold does not need an E interaction")

	_game.player.place_at(anchor + Vector3(0.0, 0.05, 3.0))
	_game._drop({"category": "gold", "amount": 17}, anchor, 0)
	var pickup_id: String = str(_game.run.next_loot - 1)
	await _ticks(8)
	_check(_game._loot.has(pickup_id), "Gold stays on the ground beyond pickup range")

	var obstruction := StaticBody3D.new()
	var obstruction_shape := CollisionShape3D.new()
	var obstruction_box := BoxShape3D.new()
	obstruction_box.size = Vector3(2.2, 2.0, 0.16)
	obstruction_shape.shape = obstruction_box
	obstruction.add_child(obstruction_shape)
	obstruction.position = anchor + Vector3(0.0, 1.0, 0.55)
	_game.dungeon.add_child(obstruction)
	_game.player.place_at(anchor + Vector3(0.0, 0.05, 1.15), PI)
	await _ticks(8)
	_check(_game._loot.has(pickup_id), "Auto-pickup does not reach through walls")
	var before_sweep: int = _game.inventory.gold
	_game.dungeon.remove_child(obstruction)
	obstruction.free()
	await _ticks(8)
	_check(not _game._loot.has(pickup_id) and _game.inventory.gold >= before_sweep + 17,
		"Nearby gold is credited without looking at it or pressing E")
	var after_sweep: int = _game.inventory.gold
	await _ticks(8)
	_check(_game.inventory.gold == after_sweep, "Automatic pickup credits each pile once")

	var locked: Node3D
	for coffer in _game._chests.values():
		if coffer.payload.locked and not coffer.payload.get("guarded", false):
			locked = coffer
			break
	_check(is_instance_valid(locked), "A locked coffer is generated")
	if is_instance_valid(locked):
		_game._open_chest(locked)
		_check(not locked.payload.opened, "Locked coffer rejects a player without a key")
		_game._drop({"category": "key"}, anchor, 0)
		var key: Node3D = _game._loot.values().back()
		_aim(anchor + Vector3(0.0, 0.05, 1.15), key.global_position + key.interaction_point)
		await _ticks(8)
		_check(_game.inventory.treasure_key_count() == 0, "Proximity pickup leaves treasure keys on the ground")
		await _tap(KEY_E)
		_check(_game.inventory.treasure_key_count() == 1, "Aiming at a treasure key and pressing E puts it in the pack")
		_game._open_chest(locked)
		_check(locked.payload.opened and _game.inventory.treasure_key_count() == 0, "A treasure key opens one locked coffer")

	var pending_reliquary := ""
	for coffer in _game._chests.values():
		if coffer.payload.get("guarded", false) and _game._coffer_guards(coffer.payload) > 0:
			pending_reliquary = str(coffer.payload.id)
			_game._open_chest(coffer)
			_check(not coffer.payload.opened, "A warded reliquary stays shut while a room guard lives")
			break
	_check(not pending_reliquary.is_empty(), "Generated depth includes a warded reliquary")

	_game.player.place_at(anchor, _game.dungeon.spawn_yaw)
	await _ticks(3)
	await _tap(KEY_T)
	_check(is_instance_valid(_game._portal_prop), "T opens a return portal")
	if is_instance_valid(_game._portal_prop):
		var portal: Vector3 = _game._portal_prop.global_position + _game._portal_prop.interaction_point
		_aim(anchor, portal)
		await _ticks(5)
		await _tap(KEY_E)
	_check(not _game.in_dungeon and not _game.run.is_empty(), "Portal returns to the hub with an active run")
	var first_run: String = _game.run.get("seed", "")
	var loot_count: int = _game.run.loot.size()
	_check(CharacterSlots.load_slot(_save_path, 0).is_empty(), "Playing a new character does not autosave")
	_game._save_now()
	var parked_checkpoint := CharacterSlots.load_slot(_save_path, 0)
	_check(not parked_checkpoint.is_empty(), "An explicit save checkpoints the current game")
	var parked_files := DirAccess.get_files_at(CharacterSlots.directory_for(_save_path, 0))
	_game.free()
	await _ticks(2)
	_mount_game(false)
	_check(_game.title_screen.is_open() and _game.title_screen._characters.has(0),
		"The character roster lists the saved slot")
	_game._save_now()
	await _ticks(30)
	_check(DirAccess.get_files_at(CharacterSlots.directory_for(_save_path, 0)) == parked_files and
		CharacterSlots.load_slot(_save_path, 0) == parked_checkpoint, "The title leaves an existing checkpoint untouched")
	_game._create_character(1, "Second Tester")
	await _ticks(8)
	_check(not _game.in_dungeon and _game.run.is_empty() and _game.bestiary_discoveries.is_empty(),
		"New starts a fresh character with an existing checkpoint present")
	_check(_game.inventory.gold == starting_gold, "New starts with the starter purse")
	_check(_game._fullscreen, "Global settings apply to a New character")
	_game.inventory.grant_gold(57)
	_game._save_now()
	await _ticks(30)
	_check(DirAccess.get_files_at(CharacterSlots.directory_for(_save_path, 0)) == parked_files and
		CharacterSlots.load_slot(_save_path, 0) == parked_checkpoint and not CharacterSlots.load_slot(_save_path, 1).is_empty(),
		"Saving a second character leaves the first character's checkpoint untouched")
	_game.free()
	await _ticks(2)
	_mount_game()
	await _ticks(9)
	_check(not _game.title_screen.is_open() and not _game._modal, "Continue closes the title and starts gameplay")
	_check(_game.inventory.gold == int(parked_checkpoint.get("inventory", {}).get("gold", -1)),
		"Continue restores checkpoint gold instead of the unsaved character's gold")
	_check(not _game.in_dungeon and _game.run.get("seed", "") == first_run, "Reload preserves a parked dungeon")
	_check(_game._fullscreen, "Fullscreen preference survives a restart")
	_check(_game.bestiary_discoveries.has(discovered_id), "Discovered bestiary entries survive a checkpoint reload")
	_check(_game.run.defeated.size() == 1 and _game.run.loot.size() == loot_count, "Reload preserves defeated enemies and outstanding loot")
	await _use_altar()
	_check(_game.in_dungeon, "Aiming at the main altar and pressing E resumes the same run")
	var survivor_id: String = _game._enemies.keys()[0]
	var wounded: CharacterBody3D = _game._enemies[survivor_id]
	var prior_health: float = wounded.health
	wounded.take_damage(minf(8.0, prior_health * 0.5), "physical", _game.player)
	var saved_health: float = wounded.health
	_check(saved_health > 0.0 and saved_health < prior_health, "The checkpoint fixture injures its survivor without killing it")
	var thrall_id := ""
	for id: String in _game._enemies:
		var thrall: CharacterBody3D = _game._enemies[id]
		if thrall.archetype_id == 0 and id != survivor_id:
			thrall.take_damage(thrall.health - thrall.max_health * 0.25, "fire", _game.player)
			thrall.health = thrall.max_health * 0.5
			thrall_id = id
			break
	_check(not thrall_id.is_empty(), "The checkpoint fixture enrages a surviving Grave Thrall and heals it past its threshold")
	_game._save_now()
	_game.free()
	await _ticks(2)
	_mount_game()
	_check(not _game.in_dungeon and _game.run.seed == first_run, "Reload starts in the hub with the active expedition retained")
	await _use_altar()
	var restored: CharacterBody3D = _game._enemies.get(survivor_id)
	_check(is_instance_valid(restored) and is_equal_approx(restored.health, saved_health),
		"Reload preserves a surviving enemy's life before combat resumes")
	var restored_thrall: CharacterBody3D = _game._enemies.get(thrall_id)
	_check(is_instance_valid(restored_thrall) and restored_thrall.health > restored_thrall.max_health * 0.30 \
		and is_equal_approx(restored_thrall._attack_speed_factor(), 1.15),
		"Reload preserves Grave Thrall Enrage after healing above the trigger threshold")
	await _ticks(8)

	if _game._chests.has(pending_reliquary):
		var reliquary: Node3D = _game._chests[pending_reliquary]
		for id: String in _game._enemies.keys():
			var entry: Dictionary = _game.dungeon.encounters[int(id)]
			if int(entry.room) == int(reliquary.payload.room):
				_game._enemies[id].take_damage(10000.0, "physical", _game.player)
		if reliquary.payload.locked:
			_game.inventory.add_treasure_keys()
		_game._open_chest(reliquary)
		_check(bool(reliquary.payload.opened) and not _game.run.cleared,
			"The warded reliquary opens after its room fight while the dungeon stays active")

	var survivors: Array = _game._enemies.values()
	var last_enemy: Node3D = survivors.pop_back()
	for survivor in survivors:
		survivor.take_damage(10000.0, "physical", _game.player)
	var map_mouse_mode := Input.mouse_mode
	await _tap(KEY_TAB)
	_check(_game.hud.is_map_visible() and _game.hud.map_has_route(),
		"Tab opens the map with a walkable route to the final enemy")
	_check(not _game._modal and _game.player.gameplay_enabled and Input.mouse_mode == map_mouse_mode
		and _game._actors.process_mode == Node.PROCESS_MODE_INHERIT,
		"The map leaves gameplay, mouse capture and enemies active")
	await _tap(KEY_TAB)
	_check(not _game.hud.is_map_visible() and _game.player.gameplay_enabled,
		"Tab closes only the map")
	last_enemy.take_damage(10000.0, "physical", _game.player)
	_check(not _game.run.cleared and _game.unlocked == 1 and _game._enemies.is_empty(),
		"Clearing one floor does not unlock a deeper dungeon")
	var first_floor_chest_count: int = _game.run.opened.size()
	var first_floor_loot_count: int = _game.run.loot.size()
	_game.inventory.clear_treasure_keys()
	_game.inventory.add_treasure_keys()
	await _walk_stair(1, 1)
	_check(_game._dungeon_floor_index() == 1 and not _game._enemies.is_empty() and _game.inventory.treasure_key_count() == 1,
		"The physical stairs enter a distinct populated floor with the same backpack key")
	if _game._dungeon_floor_index() == 1:
		_game._enter_hub()
		_game._save_now()
		_game.free()
		await _ticks(2)
		_mount_game()
		await _ticks(6)
		_check(not _game.in_dungeon and _game._dungeon_floor_index() == 0 and _game.inventory.treasure_key_count() == 1,
			"A parked checkpoint starts in the hub and retains the backpack key")
		await _use_altar()
		_check(_game._dungeon_floor_index() == 0 and _game._enemies.is_empty() and
			_game.run.loot.size() == first_floor_loot_count and _game.run.opened.size() == first_floor_chest_count,
			"Reentering at the start retains defeated enemies, opened chests and loot")
		await _walk_stair(1, 1)
		await _walk_stair(-1, 0)
		await _walk_stair(1, 1)
		for survivor in _game._enemies.values():
			survivor.take_damage(10000.0, "physical", _game.player)
	_check(_game.run.cleared and _game.unlocked == 2 and _game.completions == 1,
		"Clearing the last populated floor unlocks Depth II once")
	_check(_game.inventory.get_grid("vendor").get_placements() != original_stock, "Finishing a dungeon refreshes merchant stock")
	if _game.in_dungeon:
		_game._enter_hub()
	_game.inventory.add_treasure_keys(2)
	_game.hud.open_close(true)
	_game.hud.leave_requested.emit()
	_check(_game.run.is_empty() and not _game.in_dungeon and _game.inventory.treasure_key_count() == 0,
		"Close Dungeon seals the run and clears its backpack keys")
	_game._select_depth(2)
	await _ticks(8)
	_check(_game.in_dungeon and _game.run.level == 2 and _game.inventory.treasure_key_count() == 0,
		"Next depth begins with no previous keys")
	_check(not _game._hazards.is_empty(), "Deeper routes introduce signaled room hazards")

	_game.player.receive_enemy_hit(10000.0, "physical")
	await _ticks(8)
	_check(not _game.in_dungeon and _game.run.is_empty() and _game.player.life == _game.player.stats.max_health,
		"Death ends the current attempt and respawns the player at full Life")
	_check(_game.unlocked == 2 and _game.inventory.gold > gold_before, "Death retains permanent progress and collected gold")
	_game.free()
	await _ticks(4)
	for slot in [0, 1]:
		var directory := CharacterSlots.directory_for(_save_path, slot)
		for filename in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(directory.path_join(filename))
		DirAccess.remove_absolute(directory)
	for filename in DirAccess.get_files_at(_save_path):
		DirAccess.remove_absolute(_save_path.path_join(filename))
	DirAccess.remove_absolute(_save_path)
	print("Hearth Below integration: %d checks, %d failures" % [_checks, _errors])
	quit(1 if _errors > 0 else 0)


func _walk_stair(direction: int, target_floor: int) -> void:
	var flight: Node3D = _game.dungeon.stairs.get(direction)
	_check(is_instance_valid(flight), "This floor has the expected physical stair flight")
	if not is_instance_valid(flight):
		return
	_game.player.place_at(flight.to_global(Vector3(0.0, 0.09, 1.05)), flight.global_rotation.y)
	Input.action_press("forward")
	for tick in 335:
		await physics_frame
		if _game._dungeon_floor_index() == target_floor:
			break
	Input.action_release("forward")
	await _ticks(3)
	_check(_game._dungeon_floor_index() == target_floor,
		"Walking the stone flight enters its linked floor")


func _use_altar() -> void:
	var gate: Vector3 = _game.hub.interaction_position("altar")
	_aim(gate + Vector3(0.0, -gate.y + 0.04, 2.0), gate)
	await _ticks(5)
	await _tap(KEY_E)


func _check_gold_pacing() -> void:
	var rng: RandomNumberGenerator = _game._rng
	var original_state := rng.state
	var fixture_rng := RandomNumberGenerator.new()
	fixture_rng.seed = 39094
	rng.state = fixture_rng.state
	var original_gold_find: float = _game.player.stats.gold_find
	var starter_piles := true
	var scaled_piles := true
	var gold_find_helps := false
	for roll in 96:
		var roll_state := rng.state
		_game.player.stats.gold_find = 0.0
		var normal: int = _game._roll_enemy_gold(1, "normal")
		rng.state = roll_state
		var magic: int = _game._roll_enemy_gold(1, "magic")
		rng.state = roll_state
		var rare: int = _game._roll_enemy_gold(1, "rare")
		rng.state = roll_state
		var deep_normal: int = _game._roll_enemy_gold(10, "normal")
		starter_piles = starter_piles and normal in [1, 2] and magic == normal + 1 and rare == normal + 3
		rng.state = roll_state
		var coffer: int = _game._roll_coffer_gold(1, false)
		rng.state = roll_state
		var protected_coffer: int = _game._roll_coffer_gold(1, true)
		rng.state = roll_state
		var deep_coffer: int = _game._roll_coffer_gold(10, false)
		scaled_piles = scaled_piles and deep_normal > normal and coffer >= 4 and coffer <= 6 \
			and protected_coffer == coffer + 3 and deep_coffer > coffer
		rng.state = roll_state
		_game.player.stats.gold_find = 10.0
		var bonus_gold: int = _game._roll_enemy_gold(1, "normal")
		gold_find_helps = gold_find_helps or bonus_gold > normal
	_game.player.stats.gold_find = 0.0
	var coffer_state := rng.state
	var regular_payout: int = _game._roll_coffer_gold(1, true)
	rng.state = coffer_state
	_game.player.effects.append("deep_pockets")
	var legendary_payout: int = _game._roll_coffer_gold(1, true)
	_game.player.effects.erase("deep_pockets")
	_game.player.stats.gold_find = original_gold_find
	rng.state = original_state
	_check(starter_piles, "Enemy gold starts at one or two coins and rises with rarity")
	_check(scaled_piles, "Enemy level, dungeon depth, and coffer protection increase gold")
	_check(gold_find_helps and legendary_payout == regular_payout * 2,
		"Gold Find benefits small drops and Deep Pockets still doubles coffer gold")
	var shop_item := {"price": 42, "gold_value": 11}
	_check(Inventory.sell_price(shop_item) == 3 and Inventory.buy_price(shop_item) == 42,
		"Merchant resale pays less while preserving listed purchase prices")


func _check_saved_gear_balance() -> void:
	var legacy := Items.starter_weapon()
	legacy.erase("balance_version")
	legacy["id"] = "legacy_sword"
	legacy["rarity"] = "magic"
	legacy["name"] = "Searing Oath Blade"
	legacy["price"] = 35
	legacy["base_stats"] = {"damage_min": 4, "damage_max": 8}
	legacy["prefixes"] = [{"id": "searing", "tier": 4, "name": "Searing", "stats": {"fire_damage": 5}}]
	var inventory := Inventory.new()
	var accepted := inventory.restore_data({"gold": 18, "equipment": [{"item": legacy, "slot": "main_hand"}]})
	_check(accepted, "An earlier equipment snapshot loads with the new balance")
	if not accepted:
		return
	var restored: Dictionary = inventory.equipment["main_hand"]
	_check(restored.id == legacy.id and restored.name == legacy.name and restored.price == 35 and inventory.gold == 18
		and restored.prefixes[0].tier == 4, "Rebalancing saved gear preserves the item, tier, name, and prices")
	_check(is_equal_approx(float(restored.stats.damage_min), 1.0)
		and is_equal_approx(float(restored.stats.damage_max), 3.0)
		and restored.stats.fire_damage == 1,
		"Saved gear adopts the current base and keeps its positive Fire bonus as a whole number")
	_check(Items.restore_item(restored) == restored and not legacy.has("balance_version"),
		"Reopening rebalanced gear keeps the same numbers")
	var old_rapier := Items.training_weapon_item("funeral_rapier", "old_depth_25_rapier")
	old_rapier["item_level"] = 25
	old_rapier["balance_version"] = 2
	old_rapier["prefixes"] = [{"id": "rimed", "tier": 1, "name": "Rimed", "stats": {"cold_damage": 2.4}}]
	old_rapier["price"] = 125
	var upgraded := Items.restore_item(old_rapier)
	_check(upgraded.id == old_rapier.id and upgraded.price == old_rapier.price
		and upgraded.prefixes[0].id == old_rapier.prefixes[0].id
		and upgraded.prefixes[0].tier == old_rapier.prefixes[0].tier and upgraded.stats.cold_damage == 2
		and upgraded.stats.damage_min == 14 and upgraded.stats.damage_max == 24
		and Items.restore_item(upgraded) == upgraded, "High-level saved gear gains item power once without rerolling")
	var scaled_rapier := old_rapier.duplicate(true)
	scaled_rapier["balance_version"] = 3
	scaled_rapier["base_stats"] = {"damage_min": 14.4, "damage_max": 24.0, "lightning_damage": 2.4}
	scaled_rapier["implicit"]["fire_damage"] = 0.7
	scaled_rapier["legendary_stats"] = {"poison_damage": 0.4, "mana_regen": 0.2}
	var rounded := Items.restore_item(scaled_rapier)
	_check(rounded.stats.damage_min == 14 and rounded.stats.damage_max == 24
		and rounded.stats.fire_damage == 1 and rounded.stats.cold_damage == 2
		and rounded.stats.lightning_damage == 2 and rounded.stats.poison_damage == 1
		and is_equal_approx(rounded.stats.mana_regen, 0.2)
		and Items.restore_item(rounded) == rounded,
		"Already-scaled saves round every flat damage type once without rebasing or changing regeneration")
	var crafted := Items.craft(Items.starter_weapon(), "ash_quench")
	var legendary := Items.training_weapon_preview("bell_of_the_lost", 25)
	_check(crafted.stats.fire_damage == 1 and crafted.prefixes[0].stats.fire_damage == 1
		and legendary.stats.fire_damage == 2 and legendary.legendary_stats.lightning_damage == 3,
		"Crafting and Legendary previews produce whole-number Fire and Lightning modifiers")
	var random := RandomNumberGenerator.new()
	random.seed = 25
	var top_stock := true
	for index in range(24):
		var offer: Dictionary = Items.roll_vendor(25, random, 1)[0]
		var base := Items.training_weapon_item(offer.base_id, "test_base")
		top_stock = top_stock and offer.slot in ["main_hand", "one_hand"] and offer.item_level == 25 and base.item_level >= 8
	_check(top_stock, "High-depth vendor reserves a raised item-level offer from its best weapon bases")


func _menu_button(caption: String) -> Button:
	for button: Button in _game.hud.find_children("*", "Button", true, false):
		if button.text == caption:
			return button
	return null


func _mount_game(start_session := true) -> void:
	_game = Game.instantiate()
	_game.save_directory = _save_path
	_game.preferences_path = _save_path.path_join("settings.cfg")
	root.add_child(_game)
	if not start_session:
		return
	_game._select_character(0)


func _aim(point: Vector3, target: Vector3) -> void:
	var direction := (target - point - Vector3.UP * 1.56).normalized()
	var heading := atan2(-direction.x, -direction.z)
	var pitch := asin(direction.y)
	_game.player.place_at(point, heading, pitch)


func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(3)
	event = InputEventKey.new()
	event.physical_keycode = key
	Input.parse_input_event(event)
	await _ticks(3)


func _ticks(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS  " + description)
	else:
		_errors += 1
		push_error("FAIL  " + description)
