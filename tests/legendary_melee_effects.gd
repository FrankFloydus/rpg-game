extends SceneTree
## Exercises legendary melee mechanics through the real hit resolver and enemy combat lifecycle.

const Game := preload("res://main.tscn")
const Items := preload("res://systems/items.gd")
const Roster := preload("res://combat/enemies/enemy_catalog.gd")
const Roles := preload("res://combat/weapons/weapon_roles.gd")
const Sweep := preload("res://combat/abilities/stone_arm_sweep.tres")
const Ritual := preload("res://combat/abilities/standard_rally.tres")

var _game: Node
var _player: CharacterBody3D
var _checked := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game.title_screen.training_requested.emit()
	await _ticks(3)
	_player = _game.player
	_check_latchknife()
	_check_stillstone()
	_check_gravegate()
	_check_pair()
	await _ticks(4)
	_game.free()
	print("legendary_melee_effects: %d/%d checks passed" % [_checked - _failures, _checked])
	quit(1 if _failures > 0 else 0)


func _check_latchknife() -> void:
	if not _equip("latchknife"):
		return
	var first := _spawn()
	var other := _spawn()
	_player._strike_chain_stage = 1
	var baseline := _hit(first, true)
	_hit(first, false)
	_hit(first, false)
	_player._strike_chain_stage = 2
	_hit(first, false)
	_player._strike_chain_stage = 3
	_hit(other, false)
	_check(not _player._legendary_melee.latch_is_ready(first), "Repeated steps and hits on another enemy do not complete a latch")
	_player._strike_chain_stage = 3
	_hit(first, false)
	_check(_player._legendary_melee.latch_is_ready(first) and not _player._legendary_melee.latch_is_ready(other),
		"The third distinct light strike completes the latch on its own target")
	var boosted := _hit(first, true)
	var spent := _hit(first, true)
	_check(boosted > baseline and spent == baseline and not _player._legendary_melee.latch_is_ready(first),
		"Only the next charged hit spends the mark for increased Physical damage")
	for step in range(1, 4):
		_player._strike_chain_stage = step
		_hit(first, false)
	_check(not _player._legendary_melee.latch_is_ready(first), "The target cannot relatch during its five-second rearm")
	first.queue_free()
	other.queue_free()


func _check_stillstone() -> void:
	if not _equip("stillstone"):
		return
	var resistant := _spawn(200.0)
	_player.stamina = 4.0
	_hit(resistant, true)
	_check(is_equal_approx(_player.stamina, 4.0), "A landed charged hit without an actual stun restores no Stamina")
	var first := _spawn(12.0)
	_player.stamina = 0.0
	_player._stamina_recovery = 2.0
	_hit(first, true)
	_check(first.is_stunned() and is_zero_approx(_player.stamina), "A real stun cannot erase Guard Break")
	var second := _spawn(12.0)
	_player.stamina = 5.0
	_player._stamina_recovery = 0.0
	_hit(second, true)
	var third := _spawn(12.0)
	_hit(third, true)
	_check(second.is_stunned() and third.is_stunned() and is_equal_approx(_player.stamina, 7.0),
		"Stillstone restores exactly two Stamina once while its rearm is active")
	for enemy in [resistant, first, second, third]:
		enemy.queue_free()


func _check_gravegate() -> void:
	if not _equip("gravegate"):
		return
	var utility := _spawn(12.0, Ritual)
	utility._begin_attack(Vector3.BACK)
	_hit(utility, true)
	utility._drive_attack(&"stop", {})
	_check(utility.is_stunned() and not utility._statuses.has("chilled"), "Interrupting a utility rally does not proc Gravegate")
	var normal := _spawn(12.0, Sweep)
	normal._begin_attack(Vector3.BACK)
	_hit(normal, true)
	_check(normal.is_stunned() and not normal._statuses.has("chilled"), "Gravegate waits for the real cast-cancel event")
	normal._drive_attack(&"stop", {})
	_check(not normal._attack_cast_open and normal._statuses.has("chilled")
		and is_equal_approx(float(normal._statuses["chilled"].potency), 0.18),
		"A confirmed stun interrupt Chills the same enemy by 18%")
	var next := _spawn(12.0, Sweep)
	next._begin_attack(Vector3.BACK)
	_hit(next, true)
	next._drive_attack(&"stop", {})
	_check(not next._statuses.has("chilled"), "Gravegate cannot retry during the shared item rearm")
	for enemy in [utility, normal, next]:
		enemy.queue_free()


func _check_pair() -> void:
	if not _equip("unmatched_pair", "crypt_knife"):
		return
	var target := _spawn()
	_player.ward = 0.0
	_player._strike_hand = Roles.OFF_HAND
	_hit(target, false, Roles.OFF_HAND)
	_player._strike_hand = Roles.BOTH_HANDS
	var reversed := {"count": 0}
	_hit(target, true, Roles.MAIN_HAND, reversed)
	_hit(target, true, Roles.OFF_HAND, reversed)
	_check(is_zero_approx(_player.ward), "An off-hand hit first does not prime the crossover")
	_player._strike_hand = Roles.MAIN_HAND
	_hit(target, false, Roles.MAIN_HAND)
	_player._strike_hand = Roles.OFF_HAND
	_hit(target, false, Roles.OFF_HAND)
	_player._strike_hand = Roles.BOTH_HANDS
	var clipped := {"count": 0}
	_hit(target, true, Roles.MAIN_HAND, clipped)
	_check(is_zero_approx(_player.ward), "A crossover that lands one weapon cannot restore Ward")
	var both := {"count": 0}
	_hit(target, true, Roles.MAIN_HAND, both)
	_hit(target, true, Roles.OFF_HAND, both)
	_check(is_equal_approx(_player.ward, 3.0), "Both physical contacts from the same charged crossover restore three Ward")
	_player.ward = 0.0
	_player._strike_hand = Roles.MAIN_HAND
	_hit(target, false, Roles.MAIN_HAND)
	_player._strike_hand = Roles.OFF_HAND
	_hit(target, false, Roles.OFF_HAND)
	_player._strike_hand = Roles.BOTH_HANDS
	var next := {"count": 0}
	_hit(target, true, Roles.MAIN_HAND, next)
	_hit(target, true, Roles.OFF_HAND, next)
	_check(is_zero_approx(_player.ward), "Another crossover cannot restore Ward during the item rearm")
	target.queue_free()


func _equip(item_id: String, offhand_id := "") -> bool:
	var equipment := {"main_hand": Items.training_weapon_preview(item_id)}
	if not offhand_id.is_empty():
		equipment["off_hand"] = Items.training_weapon_preview(offhand_id)
	if not _check(equipment.main_hand.get("effect", "") == item_id, "%s exists and equips from the training catalogue" % item_id):
		return false
	_player.update_equipment(equipment)
	_player.restore_full()
	_player.stats.merge({"damage_min": 20.0, "damage_max": 20.0, "crit_chance": 0.0}, true)
	return true


func _spawn(stun := 200.0, move: AbilityDefinition = null) -> CharacterBody3D:
	var target := Roster.instantiate(16 if move != null else 0)
	if move != null:
		var actions: Array[AbilityDefinition] = [move]
		target.ability_loadout = actions
	var affixes: Array[String] = []
	_game._prepare_training_enemy(target, 1, "normal", affixes, Vector3(0.0, 0.08, -1.25))
	target.set_physics_process(false)
	target.stun_threshold = stun
	target.health = 1000.0
	target.max_health = 1000.0
	return target


func _hit(target: CharacterBody3D, heavy: bool, hand := Roles.MAIN_HAND, strike := {}) -> float:
	var health: float = target.health
	var contacts: Array[Dictionary] = [
		{"target": target, "point": target.aim_point(), "direction": Vector3.FORWARD, "weapon_hand": hand},
	]
	if strike.is_empty():
		strike = {"count": 0}
	_player._resolve_attack(heavy, {}, null, contacts, strike)
	return health - target.health


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> bool:
	_checked += 1
	if condition:
		print("PASS " + description)
	else:
		_failures += 1
		printerr("FAIL " + description)
	return condition
