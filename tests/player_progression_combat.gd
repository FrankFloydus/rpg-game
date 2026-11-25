extends SceneTree
## Exercises the player scene's attribute, level-gap, and stun integration.

const PlayerScene := preload("res://player/player.tscn")
const ThrallScene := preload("res://combat/enemies/grave_thrall/grave_thrall.tscn")
const Progression := preload("res://systems/character_progression.gd")
const HeavyAttack := preload("res://combat/abilities/heavy_attack.tres")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player := PlayerScene.instantiate() as CharacterBody3D
	root.add_child(player)
	player.set_physics_process(false)
	player.combat_enabled = true
	_check_incoming(player)
	_check_outgoing(player)
	player.free()
	print("Hearth Below player progression combat: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_incoming(player: CharacterBody3D) -> void:
	var ability := AbilityDefinition.new()
	ability.display_name = "Test mace hit"
	ability.stun_buildup = 100.0
	var context := ability.combat_details()
	context["source_level"] = 25
	context["stun_power"] = 200.0
	player._set_guard_held(true)
	_check(not player.receive_enemy_hit(2.0, "physical", "", null, context)
		and is_equal_approx(player.stamina, 5.8) and not player.is_stunned(),
		"A level-25 hit spends doubled-damage guard cost and cannot stun through a block")
	player._set_guard_held(false)
	_check(player.cast_ability(HeavyAttack, true, true), "The player can begin charging before the stunning hit")
	player.receive_enemy_hit(2.0, "physical", "", null, context)
	_check(is_equal_approx(player.life, 20.0) and player.is_stunned() and not player._strike_pending
		and is_equal_approx(player.mana, 12.0), "An unguarded hit doubles damage and interrupts an unpaid charge")
	var statuses: Array[Dictionary] = player.active_statuses()
	_check(statuses.size() == 1 and statuses[0].id == &"stunned"
		and is_equal_approx(float(statuses[0].remaining), 0.65), "Stun status exposes the capped player duration")
	player._set_guard_held(true)
	_check(not player.is_blocking() and not player.cast_ability(HeavyAttack, true),
		"Stunned player cannot guard or cast")
	player._set_guard_held(false)
	player._tick_ailments(0.65)
	player.receive_enemy_hit(2.0, "physical", "", null, context)
	_check(not player.is_stunned() and player.cast_ability(HeavyAttack, true),
		"Recovery restores attack control and prevents the next hit from chaining another stun")
	player.restore_full()


func _check_outgoing(player: CharacterBody3D) -> void:
	var progression := Progression.for_training(25)
	for attribute in Progression.ATTRIBUTE_IDS:
		progression.allocate(attribute, 8)
	player.set_character_progression(progression)
	player.update_equipment({"main_hand": _weapon("pilgrim_cudgel", "mace_1h")})
	player.restore_full()
	_check(player.combat_ability_level() == 25 and is_equal_approx(player.life, 49.0)
		and is_equal_approx(player.mana, 16.0) and is_equal_approx(player.stamina, 13.6),
		"Character level, Strength, and Intelligence adjust the player's effective resource caps")
	var enemy := ThrallScene.instantiate() as CharacterBody3D
	enemy.base_life = 1000.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	enemy.setup(player, 25, "normal", rng)
	enemy.position = Vector3(0.0, 0.0, -1.0)
	root.add_child(enemy)
	enemy.set_physics_process(false)
	var crit_seed := 0
	for candidate in range(512):
		rng.seed = candidate
		var roll := rng.randf()
		if roll > 0.05 and roll < 0.062:
			crit_seed = candidate
			break
	var initial_life: float = enemy.health
	_strike(player, enemy, crit_seed)
	_check(is_equal_approx(initial_life - float(enemy.health), 15.0),
		"Strength scales the base strike and leaves the Fire component unchanged before rounding (%.4f)" %
		(initial_life - float(enemy.health)))
	player.update_equipment({"main_hand": _weapon("funeral_rapier")})
	initial_life = enemy.health
	_strike(player, enemy, crit_seed)
	_check(is_equal_approx(initial_life - float(enemy.health), 29.0),
		"The same roll crits on a Dexterity weapon at the 200% melee baseline")
	var critical_gear := {
		"left_ring": {"stats": {"crit_multiplier": 20.0}},
		"right_ring": {"stats": {"crit_multiplier": 15.0}},
	}
	player.update_equipment(critical_gear.merged({"main_hand": _weapon("funeral_rapier")}))
	initial_life = enemy.health
	_strike(player, enemy, crit_seed)
	_check(is_equal_approx(float(player.stats.crit_multiplier), 235.0)
		and is_equal_approx(initial_life - float(enemy.health), 34.0),
		"Critical Damage affixes add 35 percentage points to a melee critical hit")
	player.update_equipment({"main_hand": _weapon("yew_crook", "staff")})
	initial_life = enemy.health
	_strike(player, enemy, crit_seed)
	_check(is_equal_approx(initial_life - float(enemy.health), 13.0),
		"Staff Bolt scales with Intelligence and its 90% multiplier, with no Dexterity crit bonus")
	player.update_equipment(critical_gear.merged({"main_hand": _weapon("yew_crook", "staff")}))
	player.stats.crit_chance = 75.0
	initial_life = enemy.health
	_strike(player, enemy, crit_seed)
	_check(is_equal_approx(float(player.stats.crit_multiplier), 185.0)
		and is_equal_approx(initial_life - float(enemy.health), 24.0),
		"Critical Damage affixes add the same points to the staff's 150% baseline")
	player.set_character_progression(Progression.for_training(1))
	player.update_equipment({"main_hand": _weapon("funeral_rapier")})
	player.stats.crit_chance = 0.0
	initial_life = enemy.health
	var initial_buildup: float = enemy._stun.buildup
	_strike(player, enemy, crit_seed)
	_check(is_equal_approx(initial_life - float(enemy.health), 0.0),
		"A level-one strike glances for zero after the level gap and damage rounding")
	_check(is_equal_approx(float(enemy._stun.buildup) - initial_buildup, 0.07),
		"The same mismatch also reduces weapon stun buildup to 0.5%")
	enemy.free()


func _weapon(base_id: String, type := "sword_1h") -> Dictionary:
	return {"base_id": base_id, "type": type, "stats": {"damage_min": 10.0,
		"damage_max": 10.0, "fire_damage": 4.0}}


func _strike(player: CharacterBody3D, enemy: CharacterBody3D, seed_value: int) -> void:
	player._rng.seed = seed_value
	var contacts: Array[Dictionary] = [{"target": enemy, "point": enemy.aim_point(),
		"direction": Vector3.FORWARD}]
	player._resolve_attack(false, {}, null, contacts, {"count": 0})


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  %s" % label)
	else:
		_failures += 1
		push_error("FAIL  %s" % label)
