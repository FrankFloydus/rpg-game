extends SceneTree
## Exercises the cleanup encounter through the normal physics and character save paths.

const Main := preload("res://main.tscn")
const Slots := preload("res://systems/character_slots.gd")
const Rules := preload("res://data/expedition_rules.tres")
const Convergence := preload("res://world/dungeon_enemy_convergence.gd")

var _game: Node3D
var _save_dir := "user://tests/convergence_%d" % Time.get_ticks_usec()
var _checks := 0
var _errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_mount()
	_game._create_character(0, "Convergence Tester")
	_game.unlocked = 9
	_game._rng.seed = 7395045
	_game._select_depth(9)
	_game.run.features["legate"] = false
	var origin: Variant = _game._dungeon_floors[0]
	var destination: Variant = _game._dungeon_floors[1]
	var ids: Array = origin.enemies.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return origin.enemies[a].affixes.size() > origin.enemies[b].affixes.size())
	if not _check(ids.size() > Rules.straggler_count, "A native seeded floor has five active enemies for the threshold test"):
		_finish()
		return
	ids.resize(Rules.straggler_count + 1)
	_prune_encounter(ids)
	var removed_id: String = ids.pop_back()
	var original_enemy: CharacterBody3D = origin.enemies[ids[0]]
	var original_parent := original_enemy.get_parent()
	var home := original_enemy.global_position
	var wounded: float = original_enemy.max_health * 0.48
	original_enemy.restore_saved_life(wounded, original_enemy.max_health)
	var affixes: Array = Array(original_enemy.affixes)
	var rarity: String = original_enemy.rarity
	var elite_name: String = original_enemy.display_name
	var species: String = original_enemy.archetype_name
	_check(rarity == "rare" and elite_name != species, "A rare monster has a generated name alongside its canonical archetype")
	var dormant_before := _dormant_counts()
	_game.player.place_at(destination.geometry.to_global(destination.geometry.spawn_position + Vector3.UP * 0.05),
		destination.geometry.spawn_yaw + destination.geometry.rotation.y)
	await _ticks(ceili(Rules.straggler_delay_seconds * 60) + 16)
	_check(_game._dungeon_floor_index() == 1 and _game._remaining_dungeon_enemies() == Rules.straggler_count + 1,
		"The player is detected on the real second floor while the campaign still has five active enemies")
	_check(original_enemy.global_position.is_equal_approx(home), "Five enemies do not trigger convergence")
	var fifth: CharacterBody3D = origin.enemies[removed_id]
	fifth._die(_game.player)
	await _ticks(12)
	_check(original_enemy.global_position.is_equal_approx(home), "Convergence grants the short warning interval")
	await _ticks(ceili(Rules.straggler_delay_seconds * 60) + 12)
	_check(_game._enemies_on_floor(1).size() == Rules.straggler_count,
		"All four active enemies move from their original floor to a valid nearby fight on the current floor")
	_check(origin.enemies[ids[0]] == original_enemy and original_enemy.get_parent() == original_parent,
		"Regrouping preserves the live object, its parent and its origin ID")
	_check(is_equal_approx(original_enemy.health, wounded) and Array(original_enemy.affixes) == affixes
		and original_enemy.rarity == rarity and not affixes.is_empty(), "The relocated elite keeps Life, rarity and affixes")
	_check(_game._remaining_dungeon_enemies() == Rules.straggler_count and dormant_before == _dormant_counts(),
		"Unseen ambush and later wave records neither relocate nor add to the active counter")
	_check(_positions_clear(), "Native floor positions preserve capsule and enemy separation")
	_check(original_enemy.convergence_floor == 1 and original_enemy._route.get_object() == destination.geometry,
		"Original-floor enemies route from the destination geometry")
	var relocated := original_enemy.global_position
	_game._enter_hub()
	_game._enter_dungeon(true)
	_check(original_enemy.global_position.is_equal_approx(relocated) and _game._dungeon_floor_index() == 1,
		"Hub portal round-trip preserves the moved enemy and the player's current floor")
	_game.save_enabled = true
	_check(_game._save_now() == OK and not Slots.load_slot(_save_dir, 0).is_empty(), "A real character checkpoint is written")
	_game.free()
	await _ticks(2)
	_mount()
	_game._select_character(0)
	_check(not _game.in_dungeon and _game._dungeon_floor_index() == 0, "Character reload returns to the hub without consuming the expedition")
	_game._enter_dungeon(false)
	origin = _game._dungeon_floors[0]
	destination = _game._dungeon_floors[1]
	var restored: CharacterBody3D = origin.enemies[ids[0]]
	_check(restored.global_position.is_equal_approx(relocated) and restored.convergence_floor == 1
		and restored._route.get_object() == destination.geometry, "Reload restores the same physical position and destination path map")
	_check(is_equal_approx(restored.health, wounded) and Array(restored.affixes) == affixes and restored.rarity == rarity,
		"Save and reload preserve wounded elite state")
	_check(restored.display_name == elite_name and restored.archetype_name == species,
		"Save and reload preserve the rare enemy name without renaming the bestiary entry")
	_check(_game._remaining_dungeon_enemies() == Rules.straggler_count and dormant_before == _dormant_counts(),
		"Reload preserves the active count and leaves dormant content untouched")
	_game.player.place_at(destination.geometry.to_global(destination.geometry.spawn_position + Vector3.UP * 0.05))
	await _ticks(5)
	var before_kills := int(_game.run.recap.kills)
	var before_xp: int = _game.progression.xp
	var before_level: int = _game.progression.level
	var before_floor_loot: int = destination.loot.size()
	var destination_defeated: Dictionary = _game._floor_state(1).defeated.duplicate()
	for id: String in ids:
		var enemy: CharacterBody3D = origin.enemies[id]
		enemy._die(_game.player)
	_check(_game._floor_state(0).defeated.has(ids[0]) and destination_defeated == _game._floor_state(1).defeated,
		"Relocated kills belong to the original floor and room")
	var gained_xp: bool = _game.progression.level > before_level or _game.progression.xp > before_xp
	_check(int(_game.run.recap.kills) == before_kills + Rules.straggler_count and gained_xp,
		"Each kill contributes once to combat totals and player XP")
	_check(destination.loot.size() >= before_floor_loot + Rules.straggler_count,
		"Gold from the relocated enemies lands on the player's floor")
	_check(_game.run.cleared and _game._remaining_dungeon_enemies() == 0,
		"The last moved enemy completes the expedition without a trip back to the source floor")
	_finish()


func _mount() -> void:
	_game = Main.instantiate()
	_game.save_directory = _save_dir
	root.add_child(_game)


func _prune_encounter(keep: Array) -> void:
	for index: int in _game._dungeon_floors:
		var floor: Variant = _game._dungeon_floors[index]
		var state: Dictionary = _game._floor_state(index)
		for id: String in floor.enemies.keys():
			if index == 0 and keep.has(id):
				floor.enemies[id].set_physics_process(false)
				continue
			var room := int(floor.enemy_origins[id].entry.room)
			if room >= 0:
				floor.room_enemies[room] -= 1
			floor.enemies[id].free()
			floor.enemies.erase(id)
			state.defeated[id] = true
		if floor.enemies.is_empty():
			_game.run.cleared_floors[str(index)] = true


func _dormant_counts() -> Array[int]:
	var sizes: Array[int] = []
	for floor: Variant in _game._dungeon_floors.values():
		for records: Array in floor.dormant_rooms.values():
			sizes.append(records.size())
	return sizes


func _positions_clear() -> bool:
	var used: Array[Vector3] = []
	for enemy: CharacterBody3D in _game._enemies_on_floor(1):
		var point := enemy.global_position
		if point.distance_to(_game.player.global_position) < Convergence.PLAYER_CLEARANCE - 0.05:
			return false
		for other: Vector3 in used:
			if point.distance_to(other) < Convergence.ENEMY_CLEARANCE:
				return false
		used.append(point)
	return used.size() == Rules.straggler_count


func _ticks(count: int) -> void:
	for index in count:
		await physics_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_errors += 1
		printerr("FAIL  ", description)
	else:
		print("PASS  ", description)
	return condition


func _finish() -> void:
	_game.free()
	print("Dungeon convergence: %d checks, %d failures" % [_checks, _errors])
	quit(0 if _errors == 0 else 1)
