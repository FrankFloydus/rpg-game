extends SceneTree

const Game := preload("res://main.tscn")
const Items := preload("res://systems/items.gd")
const Bases := preload("res://data/items/bases.gd")
const Legendaries := preload("res://data/items/legendaries.gd")
const Supplies := preload("res://systems/pack_supplies.gd")
const Pottery := preload("res://world/modules/breakable_pottery.tscn")
const Wall := preload("res://world/props/secret_passage.gd")
const Clues := preload("res://world/dungeon_wall_clues.gd")

var _game: Node3D
var _save_dir := "user://tests/legendary_exploration_%d" % Time.get_ticks_usec()
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_mount()
	_game._create_character(0, "Exploration Tester")
	_game.unlocked = 9
	_game._rng.seed = 7395045
	_game._select_depth(9)
	_game.run.features["legate"] = false
	_freeze_enemies()
	await _ticks(5)
	var wall_id: String = await _check_mason()
	await _check_tollkeeper()
	_check(_game._save_now() == OK, "The character can save the expedition state")
	_game.free()
	await _ticks(2)
	_mount()
	_game._select_character(0)
	_check(bool(_game.run.get("tollkeepers_mercy_used", false)), "Character reload preserves the spent refund")
	_check(_game._floor_state(0).mason_clues.has(wall_id), "Character reload preserves the individual wall clue")
	_game.free()
	print("Legendary exploration: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_mason() -> String:
	var floor: Variant = _game._dungeon_floors[0]
	var wall := _first_wall(floor.props)
	if not _check(wall != null and _equip("masons_listener", "amulet"), "A generated secret and the equipped Mason's Listener are present"):
		return ""
	var id: String = wall.payload.id
	var concealed: Dictionary = floor.concealed.duplicate()
	_break_pot(floor, "far_pot", floor.geometry.to_global(floor.geometry.spawn_position))
	_check(_game.run.mason_clues.is_empty(), "Breaking a real pot outside clue range leaves all walls concealed")
	var source: Vector3 = wall.to_global(Vector3(0.0, 0.018, 1.60))
	_check(Clues.nearest(floor.geometry, floor.props, source, {}) == wall,
		"The generated secret face is reachable through its real approach")
	_break_pot(floor, "near_pot", source)
	await _ticks(12)
	var dust := wall.get_node_or_null("Slab/MasonWallDust")
	var emitter := dust.get_node_or_null("Dust") as GPUParticles3D if dust != null else null
	var material := (emitter.draw_pass_1 as QuadMesh).material as ShaderMaterial if emitter != null else null
	_check(_game.run.mason_clues.has(id) and material != null and material.get_shader_parameter(&"mask_texture") != null
		and wall._clue_tween != null and wall._clue_tween.is_running(),
		"The native breakable signal flashes the crack and plays textured GPU dust")
	_check(not wall.payload.opened and floor.concealed == concealed and _game.run.secrets_opened.is_empty(),
		"Clue leaves the physical wall, minimap, and secret contents sealed")
	await _ticks(136)
	_break_pot(floor, "another_pot", source)
	_check(wall.get_node_or_null("Slab/MasonWallDust") == null and _game.run.mason_clues.size() == 1,
		"The clue is one exposure per wall after its visual has expired")
	return id


func _check_tollkeeper() -> void:
	if not _check(_equip("tollkeepers_mercy", "left_ring"), "Tollkeeper's Mercy is equipped through the pack"):
		return
	var initial_floor: Variant = _game._dungeon_floors[0]
	var regular := _ordinary_locked_coffer(initial_floor.chests)
	if not _check(regular != null, "A normal locked coffer is generated on the first floor"):
		return
	_game.inventory.add_item(Supplies.route_key("only_route_key", "Fixture Route Key"))
	_game._open_chest(regular)
	_check(not regular.payload.opened and not _game.run.get("tollkeepers_mercy_used", false),
		"An expedition route key cannot pay for a coffer or spend the refund")
	var trial: Node3D = _game._make_prop({"kind": "chest", "id": "trial_fixture", "room": -1,
		"opened": false, "locked": true, "guarded": false, "trial_waves": 2},
		initial_floor.geometry.spawn_position + Vector3(1.2, 0.0, 1.2), initial_floor.props)
	_game.inventory.add_treasure_keys()
	_game._open_chest(trial)
	_check(trial.payload.opened and _game.inventory.treasure_key_count() == 0
		and not _game.run.get("tollkeepers_mercy_used", false), "A locked trial consumes a real key and cannot claim the refund")
	_game.inventory.add_treasure_keys()
	var pack: Dictionary = _game.inventory.save_data()
	_game._open_chest(regular)
	_check(regular.payload.opened and _game.run.tollkeepers_mercy_used and _game.inventory.save_data() == pack,
		"The first locked coffer opens and the exact pack key stays in its slot")
	_game._open_chest(regular)
	_check(_game.inventory.treasure_key_count() == 1, "Clicking an already-opened coffer cannot duplicate a key")
	var another_floor: Variant = _game._dungeon_floors[1]
	_game.player.place_at(another_floor.geometry.to_global(another_floor.geometry.spawn_position + Vector3.UP * 0.05))
	await _ticks(5)
	var second := _ordinary_locked_coffer(another_floor.chests)
	if not _check(_game._dungeon_floor_index() == 1 and second != null, "The player and a second locked coffer occupy the next floor"):
		return
	_game._open_chest(second)
	_check(second.payload.opened and _game.inventory.treasure_key_count() == 0,
		"The refund is per expedition, so the second floor's coffer consumes the key")


func _ordinary_locked_coffer(chests: Dictionary) -> Node3D:
	for coffer: Node3D in chests.values():
		if coffer.payload.locked and not coffer.payload.guarded and coffer.payload.trial_waves < 2:
			return coffer
	return null


func _break_pot(floor: Variant, id: String, point: Vector3) -> void:
	var pot := Pottery.instantiate() as StaticBody3D
	floor.geometry.add_child(pot)
	pot.global_position = point
	pot.broken.connect(floor.geometry._emit_breakable_destroyed.bind(pot, id))
	pot.break_from(Vector3.FORWARD)


func _first_wall(props: Node3D) -> Wall:
	for candidate: Node in props.get_children():
		if candidate is Wall:
			return candidate
	return null


func _equip(id: String, slot: String) -> bool:
	var unique := Items._find_by_id(Legendaries.DROPS, id)
	if unique.is_empty():
		return false
	var base := Items._find_by_id(Bases.BASES, unique.base_id)
	var gear := Items._make_legendary(base, unique, int(unique.level), id)
	return _game.inventory.add_item(gear) and _game.inventory.equip_item(StringName(id), slot).is_empty() \
		and _game.player.effects.has(id)


func _freeze_enemies() -> void:
	for floor: Variant in _game._dungeon_floors.values():
		for enemy: Node3D in floor.enemies.values():
			enemy.set_physics_process(false)


func _mount() -> void:
	_game = Game.instantiate()
	_game.save_directory = _save_dir
	_game.preferences_path = _save_dir.path_join("window.cfg")
	root.add_child(_game)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL  ", description)
	else:
		print("PASS  ", description)
	return condition
