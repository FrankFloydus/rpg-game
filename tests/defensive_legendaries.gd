extends SceneTree
## Checks real legendary items through the player's guard, health and stun entry points.

const PlayerScene := preload("res://player/player.tscn")
const Items := preload("res://systems/items.gd")
const Bases := preload("res://data/items/bases.gd")
const Legendaries := preload("res://data/items/legendaries.gd")
const Rules := preload("res://data/defensive_legendary_rules.tres")
const Stunned := preload("res://combat/effects/stunned.tres")

var _checks := 0
var _failures := 0
var _player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_player = PlayerScene.instantiate()
	root.add_child(_player)
	_player.set_physics_process(false)
	_player.combat_enabled = true
	_check_counterweight()
	_check_crown()
	_check_buttress()
	_check_stonewake()
	_player.free()
	print("Defensive legendaries: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_counterweight() -> void:
	_equip("off_hand", "counterweight_gate")
	var melee := _hit("arc")
	_player._set_guard_held(true)
	_player.receive_enemy_hit(3.0, "physical", "", null, melee)
	var spent: float = _player.stamina
	_check(_status(&"counterweight_gate") > 0.0, "An unbroken block arms Counterweight Gate")
	_player._set_guard_held(false, true)
	_check(is_equal_approx(_player.stamina, spent + Rules.counterweight_refund),
		"A manual release restores the configured Stamina")
	_player._set_guard_held(true)
	_player.receive_enemy_hit(3.0, "physical", "", null, melee)
	spent = _player.stamina
	_player._set_guard_held(false, true)
	_check(is_equal_approx(_player.stamina, spent), "The gate has a cooldown between refunds")
	_player.restore_full()
	_player._set_guard_held(true)
	_player.receive_enemy_hit(3.0, "physical", "", null, melee)
	spent = _player.stamina
	_player._reset_combat_inputs("Forced test reset")
	_check(is_equal_approx(_player.stamina, spent) and _status(&"counterweight_gate") == 0.0,
		"A forced input reset cancels the pending refund")
	_player.restore_full()
	_player._set_guard_held(true)
	_player.receive_enemy_hit(3.0, "physical", "", null, melee)
	_player.receive_enemy_hit(100.0, "physical", "", null, melee)
	_player._set_guard_held(false, true)
	_check(is_zero_approx(_player.stamina) and _status(&"counterweight_gate") == 0.0,
		"Breaking guard cancels the pending refund")
	_player.restore_full()
	_player._set_guard_held(true)
	_player.receive_enemy_hit(3.0, "physical", "", null, melee)
	spent = _player.stamina
	_player._tick_ailments(Rules.counterweight_release_window + 0.01)
	_player._set_guard_held(false, true)
	_check(is_equal_approx(_player.stamina, spent), "Releasing after the configured window does not refund")


func _check_crown() -> void:
	_equip("helm", "crown_of_the_still_bell")
	_player.receive_combat_effect(Stunned, 0.10, 0.0, null, {})
	_check(is_equal_approx(_status(&"stunned"), 0.10) and _status(&"still_bell") == 0.0,
		"The Crown never lengthens a brief stun or spends its protection on one below the minimum")
	_player._tick_ailments(2.5)
	_player.receive_combat_effect(Stunned, 0.55, 0.0, null, {})
	_check(is_equal_approx(_status(&"stunned"), 0.55 * (1.0 - Rules.still_bell_reduction * 0.01))
		and _status(&"still_bell") > 0.0, "The Crown shortens a new stun and displays its cooldown")
	_player._tick_ailments(2.6)
	_player.receive_combat_effect(Stunned, 0.55, 0.0, null, {})
	_check(is_equal_approx(_status(&"stunned"), 0.55), "The next stun uses ordinary timing during Crown recovery")


func _check_buttress() -> void:
	_equip("gloves", "hands_of_the_buttress")
	var melee := _hit("arc")
	var ranged := _hit("ray")
	_player._set_guard_held(true)
	_player.receive_enemy_hit(1.0, "physical", "", null, ranged)
	_check(_status(&"buttress_hands") == 0.0, "Buttress ignores blocked projectile hits")
	_player._set_guard_held(false)
	_player.restore_full()
	_player.stamina = _player.max_stamina() * 0.50 + 0.5
	_player._set_guard_held(true)
	_player.receive_enemy_hit(1.0, "physical", "", null, melee)
	_check(_status(&"buttress_hands") == 0.0, "Buttress uses Stamina after cost")
	_player._set_guard_held(false)
	_player.restore_full()
	_player._set_guard_held(true)
	_player.receive_enemy_hit(1.0, "physical", "", null, melee)
	_check(is_equal_approx(_status(&"buttress_hands"), Rules.buttress_duration),
		"A qualifying melee block turns on the timed Buttress buff")
	_player._set_guard_held(false)
	var stunner := _hit("arc")
	stunner.definition.stun_buildup = 100.0
	_player.receive_enemy_hit(1.0, "physical", "", null, stunner)
	_check(is_equal_approx(_status(&"stunned"), 0.30 * (1.0 - Rules.buttress_stun_reduction * 0.01)),
		"Buttress shortens an actual subsequent buildup stun")
	_player._tick_ailments(3.0)
	_player.stamina = _player.max_stamina()
	_player._set_guard_held(true)
	_player.receive_enemy_hit(1.0, "physical", "", null, melee)
	_check(_status(&"buttress_hands") == 0.0, "A second qualifying block respects Buttress recovery")
	_player._set_guard_held(false)
	_player.restore_full()
	_player._set_guard_held(true)
	_player.receive_enemy_hit(1.0, "physical", "", null, melee.merged({"unblockable": true}))
	_check(_status(&"buttress_hands") == 0.0, "Unblockable attacks cannot activate Buttress")
	_player.update_equipment({
		"gloves": _item("hands_of_the_buttress"),
		"helm": _item("crown_of_the_still_bell"),
	})
	_player.restore_full()
	_player._set_guard_held(true)
	_player.receive_enemy_hit(1.0, "physical", "", null, melee)
	_player._set_guard_held(false)
	_player.receive_combat_effect(Stunned, 0.30, 0.0, null, {})
	_check(is_equal_approx(_status(&"stunned"), Rules.still_bell_minimum) and _status(&"still_bell") == 0.0,
		"Buttress can reach the Crown's floor without using its cooldown")


func _check_stonewake() -> void:
	_equip("boots", "stonewake_spurs")
	var direct := _hit("arc")
	_player.receive_ground_damage(1.0, "fire", null, direct)
	_check(_status(&"stonewake_spurs") == 0.0, "Ground damage cannot start Stonewake")
	_player.ward = 10.0
	_player.receive_enemy_hit(2.0, "fire", "", null, direct)
	_check(_player.ward < 10.0 and _status(&"stonewake_spurs") == 0.0, "A hit absorbed by Ward cannot start Stonewake")
	_player.ward = 0.0
	var walking: Vector2 = _player.warning_walk_profile()
	_player.receive_enemy_hit(2.0, "fire", "", null, direct)
	_check(is_equal_approx(_status(&"stonewake_spurs"), Rules.stonewake_duration)
		and is_equal_approx(_player._defensive_legendaries.movement_multiplier(), 1.0 + Rules.stonewake_speed_bonus * 0.01),
		"A Life-damaging direct hit starts the movement boost and shows a countdown")
	_check(_player.warning_walk_profile() == walking, "Temporary speed leaves the base telegraph escape profile intact")
	_player._tick_ailments(2.0)
	_player.receive_enemy_hit(2.0, "fire", "", null, direct)
	_check(_status(&"stonewake_spurs") == 0.0, "Stonewake expires and cannot rearm before its cooldown ends")


func _equip(slot: String, id: String) -> void:
	_player.update_equipment({slot: _item(id)})
	_player.restore_full()


func _item(id: String) -> Dictionary:
	var definition := Items._find_by_id(Legendaries.DROPS, id)
	var base := Items._find_by_id(Bases.BASES, definition.base_id)
	return Items._make_legendary(base, definition, definition.level, id)


func _hit(shape: String) -> Dictionary:
	var ability := AbilityDefinition.new()
	ability.display_name = "Test hit"
	ability.execution_profile = {"shape": shape}
	return ability.combat_details()


func _status(id: StringName) -> float:
	for status: Dictionary in _player.active_statuses():
		if status.id == id:
			return status.remaining
	return 0.0


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS ", description)
	else:
		_failures += 1
		push_error(description)
