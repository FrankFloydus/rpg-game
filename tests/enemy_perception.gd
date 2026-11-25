extends SceneTree
## Targets the longer visual acquisition range and the old ambush wall bypass.

const Game := preload("res://main.tscn")
const Enemy := preload("res://combat/enemies/enemy.gd")
const Catalog := preload("res://combat/enemies/enemy_catalog.gd")

var _game: Node3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game._create_character(0, "Perception Tester")
	_game._enter_training_ground()
	await _ticks(6)
	await _check_approach(0, 14.0, false, &"graveknife_cut")
	await _check_approach(1, 16.4, true, &"ossuary_shot")
	await _check_around_a_wall()
	await _check_arrival()
	_game.free()
	await _ticks(2)
	print("Hearth Below enemy vision: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_approach(archetype: int, distance: float, corridor: bool, attack: StringName) -> void:
	var enemy := _spawn(archetype, Vector3(0.0, 0.05, -distance * 0.5),
		Vector3(0.0, 0.05, distance * 0.5), corridor)
	var starting_position := enemy.position
	await _ticks(22)
	_check(enemy._engaged and enemy._sight, "%s notices a clear player at %.1f m" % [enemy.display_name, distance])
	var attacked := false
	for frame in 430:
		if _started(attack):
			attacked = true
			break
		await _ticks(1)
	_check(attacked and enemy.position.distance_to(starting_position) > 2.0,
		"%s pursues from long range and uses its authored attack" % enemy.display_name)


func _check_around_a_wall() -> void:
	var wall := StaticBody3D.new()
	wall.position.y = 1.5
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 3.0, 0.32)
	collider.shape = box
	wall.add_child(collider)
	_game.training_ground.add_child(wall)
	var enemy := _spawn(0, Vector3(0.0, 0.05, -2.3), Vector3(0.0, 0.05, 2.3), false)
	await _ticks(54)
	_check(not enemy._engaged and not enemy._sight, "A close ambush stays idle behind a solid wall")
	_game.player.place_at(Vector3(3.4, 0.05, 2.3))
	await _ticks(25)
	_check(enemy._engaged and enemy._sight, "The ambush wakes when the player rounds the edge")
	wall.queue_free()


func _check_arrival() -> void:
	_game._leave_training_ground()
	_game._rng.seed = 7395045
	_game._select_depth(1)
	await _ticks(46)
	var engaged := false
	var configured := true
	for id: String in _game._enemies:
		var enemy: CharacterBody3D = _game._enemies[id]
		var entry: Dictionary = _game.dungeon.encounters[int(id)]
		var expected := 18.0 if int(entry.room) < 0 else 16.0
		configured = configured and is_equal_approx(enemy._sight_radius, expected)
		engaged = engaged or enemy._engaged
	_check(_game.in_dungeon and not _game._enemies.is_empty() and configured,
		"Generated rooms and corridors use their respective expedition sight ranges")
	_check(not engaged, "The arrival chamber remains safe")


func _spawn(archetype: int, at: Vector3, target: Vector3, corridor: bool) -> CharacterBody3D:
	_game._reset_training_combat()
	_game.player.place_at(target)
	_game.player.restore_full()
	_game._combat_events.clear()
	var enemy := Catalog.instantiate(archetype)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8491
	enemy.setup(_game.player, 1, "normal", rng, Callable(_game.training_ground, "navigation_route"))
	enemy.configure_encounter(0, true, 6.0, PackedVector3Array(), Enemy.expedition_sight_range(1, corridor))
	enemy.configure_ai(_game._training_encounter, _game._training_pressure)
	enemy.combat_event.connect(_game._record_combat_event)
	enemy.position = at
	_game._training_actors.add_child(enemy)
	return enemy


func _started(ability: StringName) -> bool:
	for event: Dictionary in _game._combat_events:
		if event.get("kind") == &"cast_start" and event.get("ability_id") == ability:
			return true
	return false


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
