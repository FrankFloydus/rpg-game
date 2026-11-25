extends SceneTree
## A standing Training Ground character at base movement speed can walk past each marked impact.

const Game := preload("res://main.tscn")
const Colossus := 16
const GraveThrall := 0
const Rules := preload("res://data/telegraph_rules.tres")
const Telegraph := preload("res://combat/effects/enemy_telegraph.gd")
const FearsomeRage := preload("res://combat/effects/enrage.tres")
const Hazards: Dictionary[String, PackedScene] = {
	"spike_plate": preload("res://world/hazards/spike_plate.tscn"),
	"ember_vent": preload("res://world/hazards/ember_vent.tscn"),
	"miasma_vent": preload("res://world/hazards/miasma_vent.tscn"),
}

var _game: Node3D
var _player: CharacterBody3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game.title_screen.training_requested.emit()
	_player = _game.player
	_player.stats.move_speed = 0.0
	_player.stats.dodge_chance = 0.0
	_check_footprints()
	await _check_slam()
	await _check_volatile()
	for kind in Hazards:
		await _check_fixture(kind)
	_game.free()
	print("Hearth Below floor warnings: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_footprints() -> void:
	var lane := {"shape": "lane", "reach": 5.0, "width": 0.62}
	var warning := Telegraph.make_node()
	_game.add_child(warning)
	var origin := Vector3(1.0, 0.0, 2.0)
	Telegraph.present(warning, lane, origin, Vector3.RIGHT)
	_check(warning.global_position.is_equal_approx(origin + Vector3(2.5, Telegraph.FLOOR_LIFT, 0.0))
		and warning.scale.is_equal_approx(Vector3(0.62, 1.0, 2.5))
		and Telegraph.contains(lane, origin, Vector3.RIGHT, origin + Vector3(4.0, 0.0, 0.60))
		and not Telegraph.contains(lane, origin, Vector3.RIGHT, origin + Vector3(4.0, 0.0, 0.64)),
		"Rotated straight warning and gameplay footprint share the same origin, length and edges")
	var sector := {"shape": "arc", "reach": 2.0, "arc": 45.0}
	_check(Telegraph.contains(sector, origin, Vector3.FORWARD, origin + Vector3(0.5, 0.0, -1.0))
		and not Telegraph.contains(sector, origin, Vector3.FORWARD, origin + Vector3(1.2, 0.0, -1.0)),
		"Ground arcs use their authored center, radius and angular edge")
	var ring := {"shape": "ring", "reach": 2.4, "inner_radius": 0.8}
	_check(Telegraph.contains(ring, origin, Vector3.FORWARD, origin + Vector3(0.0, 0.0, 1.2))
		and not Telegraph.contains(ring, origin, Vector3.FORWARD, origin)
		and not Telegraph.contains(ring, origin, Vector3.FORWARD, origin + Vector3(0.0, 0.0, 2.5)),
		"Ring warnings leave both the inner safe space and the outside safe")
	warning.free()


func _check_slam() -> void:
	_player.place_at(Vector3(0.0, 0.06, 1.85))
	await _ticks(8)
	var enemy := _spawn_enemy(Colossus, ["quick", "enraged"], Vector3(0.0, 0.06, 0.0))
	enemy.health = enemy.max_health * 0.40
	enemy.receive_combat_effect(FearsomeRage, 20.0, 0.0, null, {})
	var warning: MeshInstance3D
	for _frame in 180:
		await _ticks(1)
		if is_instance_valid(enemy._attack_warning) and enemy._attack_warning.visible:
			warning = enemy._attack_warning
			break
	if not _check(is_instance_valid(warning) and enemy._attack_speed_factor() > 1.0,
			"A quick, enraged Colossus starts the live Sepulchre Slam warning"):
		_game._reset_training_combat()
		return
	var center := warning.global_position
	var radius := warning.scale.x
	var starting_direction := warning.global_basis
	# Put the already-grounded and stationary character at the hardest point of the circle.
	# Clear only the caster's collider so this checks walking on an open escape path.
	enemy.collision_layer = 0
	_player.place_at(Vector3(center.x, _player.global_position.y, center.z))
	var stable := await _walk_out(warning, center, starting_direction, radius, false)
	_check(stable, "Slam's visible perimeter stays fixed while the target moves")
	_game._reset_training_combat()
	await _ticks(1)


func _check_volatile() -> void:
	var center := Vector3(0.0, 0.06, -1.0)
	_player.place_at(center)
	await _ticks(8)
	var enemy := _spawn_enemy(GraveThrall, ["volatile"], center)
	enemy.collision_layer = 0
	enemy.take_damage(enemy.max_health * 5.0, "physical")
	var warning: MeshInstance3D = enemy._attack_warning
	if _check(is_instance_valid(warning) and warning.visible, "Volatile death starts a real burst warning"):
		await _walk_out(warning, warning.global_position, warning.global_basis, warning.scale.x, true)
	_game._reset_training_combat()
	await _ticks(1)


func _check_fixture(kind: String) -> void:
	var center := Vector3(0.0, 0.06, -1.0)
	_player.place_at(center)
	await _ticks(8)
	var trap := Hazards[kind].instantiate() as Node3D
	trap.configure(kind, 5, _player)
	trap.position = center
	_game._training_actors.add_child(trap)
	var warning: MeshInstance3D = trap._warning
	for _frame in 120:
		await _ticks(1)
		if warning.visible:
			break
	if _check(warning.visible and is_equal_approx(warning.scale.x, trap._radius),
			"%s shows the exact contact radius from the first warning frame" % kind):
		await _walk_out(warning, warning.global_position, warning.global_basis, warning.scale.x, false)
	trap.queue_free()
	await _ticks(1)


func _walk_out(warning: MeshInstance3D, center: Vector3, direction: Basis,
		radius: float, freed_after_use: bool) -> bool:
	var label := String(warning.get_parent().name)
	var life: float = _player.life
	var stable := true
	var warning_finished := false
	Input.action_press("back")
	for _frame in 210:
		await _ticks(1)
		if not is_instance_valid(warning):
			warning_finished = freed_after_use
			break
		if not warning.visible:
			warning_finished = true
			break
		stable = (stable and warning.global_position.is_equal_approx(center)
			and warning.global_basis.is_equal_approx(direction))
	Input.action_release("back")
	var offset := _player.global_position - center
	var walked := Vector2(offset.x, offset.z).length()
	_check(warning_finished and walked >= radius + Rules.edge_clearance_meters
		and is_equal_approx(_player.life, life),
		"%s allows a standing player to backpedal clear before damage (%.2f m available, %.2f m needed)"
		% [label, walked, radius + Rules.edge_clearance_meters])
	return stable


func _spawn_enemy(id: int, affixes: Array[String], point: Vector3) -> CharacterBody3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 483
	var enemy: CharacterBody3D = _game.EnemyCatalog.instantiate(id)
	enemy.setup(_player, 25, "rare", rng, _game.training_ground.navigation_route,
		_game.BestiaryData.combat_ability, affixes)
	enemy.configure_encounter(0, false, 16.0)
	enemy.configure_ai(_game._training_encounter, _game._training_pressure)
	enemy.position = point
	_game._training_actors.add_child(enemy)
	return enemy


func _ticks(count: int) -> void:
	for _tick in count:
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + label)
	else:
		_failures += 1
		push_error(label)
	return condition
