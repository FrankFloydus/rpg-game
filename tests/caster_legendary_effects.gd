extends SceneTree
## Runs the equipped legendary hooks through the real player and enemy damage paths.

const Player := preload("res://player/player.tscn")
const Effects := preload("res://combat/effects/caster_legendary_effects.gd")
const Cards := preload("res://combat/cards/card_cast.gd")
const CardData := preload("res://data/card_catalog.gd")
const Items := preload("res://systems/items.gd")
const Roster := preload("res://combat/enemies/enemy_catalog.gd")
const Staff := preload("res://combat/abilities/forked_staff_bolt.tres")
const Slash := preload("res://combat/abilities/heavy_attack.tres")

var _stage := Node3D.new()
var _player: CharacterBody3D
var _events: Array[Dictionary] = []
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(_stage)
	current_scene = _stage
	_player = Player.instantiate()
	_stage.add_child(_player)
	_player.position = Vector3(0.0, 0.08, 3.4)
	_player.combat_enabled = true
	_player.set_physics_process(false)
	_player.combat_event.connect(_events.append)
	_box(Vector3(0.0, -0.15, 0.0), Vector3(22.0, 0.30, 22.0), _stage)
	await physics_frame
	await _test_rime()
	await _test_tithe()
	await _test_cairn()
	await physics_frame
	_stage.free()
	print("Caster legendaries: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_rime() -> void:
	var arena := _new_arena()
	_equip({"main_hand": Items.training_weapon_preview(Effects.RIME)})
	var primary := _spawn(arena, Vector3.ZERO)
	var near := _spawn(arena, Vector3(0.0, 0.0, 1.25))
	var further := _spawn(arena, Vector3(0.0, 0.0, -1.50))
	var edge := _spawn(arena, Vector3(1.78, 0.0, 0.0))
	var fourth := _spawn(arena, Vector3(0.0, 0.0, -2.15))
	var upstairs := _spawn(arena, Vector3(0.0, 1.35, -1.3))
	var behind_wall := _spawn(arena, Vector3(-1.15, 0.0, 0.0))
	_box(Vector3(-0.53, 0.8, 0.0), Vector3(0.12, 1.60, 0.42), arena)
	await physics_frame
	_hit(primary)
	_check(primary.has_combat_effect("chilled") and near.health == near.max_health,
		"The first staff hit applies Chill and cannot fracture from its own fresh status")
	var first := _events.size()
	_hit(primary)
	var arcs := _damage_events(Effects.RIME, first)
	_check(arcs.size() == 3 and near.health < near.max_health and further.health < further.max_health
		and edge.health < edge.max_health and fourth.health == fourth.max_health
		and behind_wall.health == behind_wall.max_health and upstairs.health == upstairs.max_health,
		"A second hit fractures into the three nearest clear targets on the same floor")
	_check(not arcs.is_empty() and arcs[0].detail.contains("Cold")
		and arena.get_node_or_null("RimeFracture") is GPUParticles3D,
		"Rime logs Cold damage and emits the original fracture particles")
	first = _events.size()
	_hit(primary)
	_check(_damage_events(Effects.RIME, first).is_empty(), "Immediate follow-up cannot ignore the fracture rearm")
	_player._caster_legendaries.advance(Effects.Rules.rime_cooldown)
	first = _events.size()
	_hit(primary)
	_check(_damage_events(Effects.RIME, first).size() == 3, "Fracture can trigger again after its full cooldown")
	arena.free()


func _test_tithe() -> void:
	var arena := _new_arena()
	_equip({"main_hand": Items.training_weapon_preview("pale_vesper_staff"),
		"left_ring": {"effect": Effects.TITHE}})
	var primary := _spawn(arena, Vector3.ZERO)
	await physics_frame
	_player.mana = Staff.mana_cost - 0.01
	_check(not _commit_staff(), "An unaffordable cast cannot spend or prime the tithe")
	for cast in 5:
		_player.mana = 25.0
		_commit_staff()
	_player._spend_ability_mana(10.0, Slash)
	_check(not _player._caster_legendaries.is_primed(),
		"Five seven-Mana staff casts and a non-staff expense do not prime the thirty-eight-Mana tithe")
	_player.mana = 25.0
	_check(_commit_staff() and _player._caster_legendaries.is_primed()
		and _player.active_statuses().any(func(status: Dictionary) -> bool: return status.id == &"tithe_of_sparks"),
		"The sixth committed staff cast primes the tithe and its HUD icon")
	_hit(primary)
	_check(_player._caster_legendaries.is_primed(), "An isolated target does not consume the charge")
	var near := _spawn(arena, Vector3(0.0, 0.0, 1.25))
	var far := _spawn(arena, Vector3(0.0, 0.0, -2.95))
	var fourth := _spawn(arena, Vector3(3.25, 0.0, 0.0))
	await physics_frame
	var first := _events.size()
	_hit(primary)
	var arcs := _damage_events(Effects.TITHE, first)
	_check(arcs.size() == 2 and arcs[0].detail.contains("Lightning") and near.health < near.max_health
		and far.health < far.max_health and fourth.health == fourth.max_health
		and not _player._caster_legendaries.is_primed(),
		"The next eligible hit spends the charge on two nearby Lightning arcs")
	for cast in 6:
		_player.mana = 25.0
		_commit_staff()
	first = _events.size()
	_hit(primary)
	_check(_player._caster_legendaries.is_primed() and _damage_events(Effects.TITHE, first).is_empty(),
		"The five-second rearm keeps the stored tithe if another hit lands early")
	_player._caster_legendaries.advance(Effects.Rules.tithe_cooldown)
	_hit(primary)
	_check(not _player._caster_legendaries.is_primed() and _damage_events(Effects.TITHE, first).size() == 2,
		"An eligible staff hit after rearm can spend the newly primed charge")
	arena.free()


func _test_cairn() -> void:
	var arena := _new_arena()
	_equip({"amulet": {"effect": Effects.CAIRN}})
	var run := {"level": 31}
	var empty_run := {}
	var normal := _spawn(arena, Vector3.FORWARD, "normal")
	var allied_kill := _spawn(arena, Vector3.FORWARD * 2.0, "rare")
	var first := _spawn(arena, Vector3.FORWARD * 3.0, "rare")
	var second := _spawn(arena, Vector3.RIGHT * 3.0, "rare")
	await physics_frame
	_kill(normal, run)
	_kill(allied_kill, run, true)
	_kill(first, empty_run)
	_check(not run.has("cairn_oath_used") and empty_run.is_empty()
		and get_nodes_in_group("friendly_skeletons").is_empty(),
		"Normal kills, allied kills and live-training-simulation kills cannot use Cairn Oath")
	Effects.on_rare_kill(_player, first, arena, run)
	_kill(second, run)
	var guard := arena.get_node_or_null("CairnOathGuard")
	_check(guard != null and run.cairn_oath_used and get_nodes_in_group("friendly_skeletons").size() == 1
		and is_equal_approx(guard._lifetime, Effects.Rules.cairn_guard_seconds),
		"Two actual rare deaths in one expedition raise precisely one timed guard")
	Cards.play("oathbound_three", CardData.CARDS.oathbound_three, _player, arena)
	var party := arena.get_node_or_null("OathboundThree")
	_check(guard != null and guard.is_queued_for_deletion()
		and party != null and get_nodes_in_group("friendly_skeletons").size() == 3,
		"Playing the card while the guard serves replaces it with exactly three fighters")
	if party == null:
		arena.free()
		return
	var later_run := {"level": 31}
	var original_time: float = party._lifetime
	var next_rare := _spawn(arena, Vector3.LEFT * 3.0, "rare")
	_kill(next_rare, later_run)
	_check(later_run.cairn_oath_used and get_nodes_in_group("friendly_skeletons").size() == 3
		and is_equal_approx(party._lifetime - original_time, Effects.Rules.cairn_extension_seconds),
		"In a fresh expedition the first qualifying rare kill extends an active company")
	await process_frame
	arena.free()


func _new_arena() -> Node3D:
	var arena := Node3D.new()
	_stage.add_child(arena)
	return arena


func _equip(equipment: Dictionary) -> void:
	_player.update_equipment(equipment)
	_player.restore_full()
	_player.stats.merge({"damage_min": 20.0, "damage_max": 20.0, "crit_chance": -100.0}, true)


func _spawn(arena: Node3D, at: Vector3, rarity := "normal") -> CharacterBody3D:
	var enemy := Roster.instantiate(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 26
	var affixes: Array[String] = []
	if rarity == "rare":
		affixes.append("armored")
	enemy.setup(_player, 1, rarity, rng, Callable(), Callable(), affixes)
	enemy.position = at + Vector3.UP * 0.06
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.health = 1000.0
	enemy.max_health = 1000.0
	return enemy


func _hit(enemy: CharacterBody3D) -> void:
	var contacts: Array[Dictionary] = [
		{"target": enemy, "point": enemy.aim_point(), "direction": Vector3.FORWARD},
	]
	_player._resolve_attack(false, {}, null, contacts, {"count": 0})


func _kill(enemy: CharacterBody3D, run: Dictionary, ally := false) -> void:
	var arena := enemy.get_parent() as Node3D
	enemy.died.connect(func(dead: CharacterBody3D) -> void:
		Effects.on_rare_kill(_player, dead, arena, run))
	enemy.take_hit({"cold": 3000.0}, _player, Vector3.INF, Vector3.ZERO, {"allied_summon": ally})


func _commit_staff() -> bool:
	var runtime = _player._ability_runtime
	runtime.advance(Staff.cooldown)
	return runtime.try_commit(Staff, _player.mana, _player._spend_ability_mana.bind(Staff))


func _box(at: Vector3, size: Vector3, arena: Node3D) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.collision_layer = 1
	body.position = at
	body.add_child(collision)
	arena.add_child(body)


func _damage_events(ability_id: String, start: int) -> Array[Dictionary]:
	return _events.slice(start).filter(func(event: Dictionary) -> bool:
		return event.kind == &"damage" and String(event.ability_id) == ability_id)


func _check(valid: bool, description: String) -> void:
	_checks += 1
	if not valid:
		_failures += 1
		push_error(description)
