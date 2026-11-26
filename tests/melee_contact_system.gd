extends SceneTree
## Verifies contact selection, swept collision, cleave budgets, and live location rules.

const Main := preload("res://main.tscn")
const Sweep := preload("res://player/melee_sweep.gd")
const ContactSession := preload("res://player/melee_contact_session.gd")
const CleaveRules := preload("res://combat/weapons/melee_contact_rules.gd")
const Crate := preload("res://world/modules/breakable_crate.tscn")

class Target extends StaticBody3D:
	var health := 30.0
	var mass := 1.20
	var material := &"body"
	var stunned := false
	var cocoon := false

	func aim_point() -> Vector3:
		return global_position

	func melee_contact_material() -> StringName:
		return material

	func melee_contact_mass() -> float:
		return mass

	func is_stunned() -> bool:
		return stunned

	func is_cocoon() -> bool:
		return cocoon


var _fixture := Node3D.new()
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(_fixture)
	await _check_precision()
	await _check_casts()
	await _check_wall_faces()
	_check_cleave()
	_fixture.free()
	await _ticks(2)
	await _check_live_location_rules()
	print("Melee contact system: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_precision() -> void:
	var aim := Transform3D(Basis.IDENTITY, Vector3.UP * 1.5)
	var main := _shape(Vector3(0.0, 1.5, -1.75), Vector3.ONE * 0.3)
	var right := _shape(Vector3(0.62, 1.5, -1.60), Vector3.ONE * 0.3)
	var left := _shape(Vector3(-0.66, 1.5, -1.80), Vector3.ONE * 0.3)
	var flank := _shape(Vector3(1.4, 1.5, -2.7), Vector3.ONE * 0.3)
	await _ticks(2)
	var space := _fixture.get_world_3d().direct_space_state
	var session := ContactSession.new(true)
	session.begin(space, aim, RID())
	var wall := {"kind": &"terrain", "fraction": 0.2}
	var prop := {"kind": &"prop", "fraction": 0.65}
	var fits_all := func(_target: Node3D) -> bool: return true
	var latest := _actor(left, 0.1)
	var results := session.take_contacts(aim, [prop, _actor(right, 0.19), wall], false, fits_all)
	_check(results == [wall, prop], "Precision defers other actors and passes solid and prop contacts in order")
	results = session.take_contacts(aim, [latest, _actor(main, 0.62), _actor(flank, 0.84)], false, fits_all)
	_check(_actors(results) == [main, left, flank], "A priority overlap permits early replay of the latest eligible saved actor")
	_check(results.size() == 3 and results[1].fraction >= 0.62 and results[1].fraction <= 0.84 \
		and is_equal_approx(latest.fraction, 0.1), "Early replay uses the current reaction time without moving the saved sample")
	_check(_actors(session.take_contacts(aim, [], true)) == [right] and session.take_contacts(aim, [], true).is_empty(),
		"An earlier held actor waits for closure and replays once")

	session.begin(space, aim, RID())
	var fits_earlier := func(target: Node3D) -> bool: return target == right
	session.take_contacts(aim, [_actor(right, 0.1), _actor(left, 0.2)], false, fits_earlier)
	results = session.take_contacts(aim, [_actor(main, 0.40), _actor(flank, 0.84)], false, fits_all)
	_check(_actors(results) == [main, flank], "An ineligible latest result leaves earlier contacts queued for closure")
	_check(_actors(session.take_contacts(aim, [], true)) == [right, left],
		"Closure replays the remaining contacts in observed order for cleave resolution")

	session.begin(space, aim, RID())
	_check(session.take_contacts(aim, [_actor(left, 0.05)]).is_empty(), "Aim selection alone deals no hit")
	_check(_actors(session.take_contacts(aim, [_actor(right, 0.4)], true)) == [left, right] \
		and session.take_contacts(aim, [], true).is_empty(), "Closure consumes held actor contacts once")
	session.begin(space, aim, RID())
	session.take_contacts(aim, [_actor(right, 0.1), _actor(left, 0.7)])
	var turned := Transform3D(Basis(Vector3.UP, 1.0), aim.origin)
	_check(session.take_contacts(turned, []).is_empty(), "Losing the priority target waits for a physical result or closure")
	_check(_actors(session.take_contacts(turned, [_actor(flank, 0.2)])) == [left, flank],
		"The next physical result after target loss replays the latest saved contact")
	_check(_actors(session.take_contacts(turned, [], true)) == [right], "Target loss retains earlier saved contacts for closure")
	session.begin(space, aim, RID())
	session.take_contacts(aim, [_actor(left, 0.7)])
	left.health = 0.0
	_check(session.take_contacts(aim, [], true).is_empty(), "A dead deferred actor is discarded")
	left.health = 30.0

	var broad := ContactSession.new(false)
	broad.begin(space, aim, RID())
	_check(_actors(broad.take_contacts(aim, [_actor(left, 0.7), _actor(right, 0.02)])) == [right, left],
		"Broad attacks resolve earliest recorded actor contact first")
	var cover := _shape(Vector3(0.0, 1.5, -0.9), Vector3(0.4, 1.0, 0.1), Sweep.WORLD_LAYER)
	await _ticks(2)
	session.begin(space, aim, RID())
	_check(_actors(session.take_contacts(aim, [_actor(main, 0.03), _actor(left, 0.24), _actor(flank, 0.5)])) == [left, main, flank],
		"Precision acquisition falls back to a visible actor when the centre ray stops at cover")
	cover.free()
	main.position.z = -3.4
	left.position.x = -3.4
	right.position.x = 3.4
	await _ticks(2)
	session.begin(space, aim, RID())
	_check(_actors(session.take_contacts(aim, [_actor(main, 0.24)])) == [main],
		"Targets outside the precision radius create no lock")


func _check_casts() -> void:
	var aim := Transform3D(Basis.IDENTITY, Vector3(30.0, 1.5, 0.0))
	var target := _shape(aim.origin + Vector3.FORWARD * 1.20, Vector3(0.06, 0.24, 0.14))
	await _ticks(2)
	var left := _blade(aim.origin + Vector3(-0.7, 0.0, -0.55), Vector3.FORWARD)
	var right := _blade(aim.origin + Vector3(0.7, 0.0, -0.55), Vector3.FORWARD)
	var options := {"width": 0.1, "height": 0.2, "length_scale": 1.0, "reach_assist": 0.0}
	var space := _fixture.get_world_3d().direct_space_state
	var sweep := Sweep.new("mace_2h", false, RID(), aim)
	sweep.trace_contact_sweep(space, aim, aim, left, right, options)
	var contacts := sweep.take_contacts()
	_check(contacts.size() == 1 and contacts[0].target == target and contacts[0].fraction > 0.2 \
		and contacts[0].fraction < 0.8, "A moving box strikes a thin target between both endpoint boxes")
	sweep.trace_contact_sweep(space, aim, aim, right, left, options)
	_check(sweep.take_contacts().is_empty(), "A second pass of the same strike cannot repeat an actor hit")
	var heel := aim.origin + Vector3.FORWARD * 0.45
	target.position.z = -1.38
	await _ticks(2)
	sweep = Sweep.new("mace_2h", false, RID(), aim)
	sweep.trace_contact_sweep(space, aim, aim, _blade(heel, Vector3(-1.0, 0.0, -1.0).normalized()),
		_blade(heel, Vector3(1.0, 0.0, -1.0).normalized()), options)
	_check(sweep.take_contacts().size() == 1, "A rotating cut catches a target missed by both endpoint orientations")
	var cover := _shape(aim.origin + Vector3.FORWARD * 0.94, Vector3(1.9, 1.0, 0.1), Sweep.WORLD_LAYER)
	await _ticks(2)
	sweep = Sweep.new("mace_2h", false, RID(), aim)
	sweep.trace_contact_sweep(space, aim, aim, left, right, options)
	_check(sweep.take_contacts().is_empty(), "The box cannot damage an actor beyond solid cover")
	cover.free()


func _check_wall_faces() -> void:
	var aim := Transform3D(Basis.IDENTITY, Vector3(50.0, 1.5, 0.0))
	_shape(aim.origin + Vector3.FORWARD, Vector3(1.8, 1.8, 0.06), Sweep.WORLD_LAYER)
	await _ticks(2)
	var space := _fixture.get_world_3d().direct_space_state
	var beyond := _blade(aim.origin + Vector3(-0.1, 0.0, -1.30), Vector3.RIGHT, 0.2)
	var far_face := _blade(aim.origin + Vector3(-0.1, 0.0, -1.09), Vector3.RIGHT, 0.2)
	var near := _blade(aim.origin + Vector3(-0.1, 0.0, -0.67), Vector3.RIGHT, 0.2)
	var near_face := _blade(aim.origin + Vector3(-0.1, 0.0, -0.93), Vector3.RIGHT, 0.2)
	var options := {"mace_head_stop": true}
	for heavy: bool in [false, true]:
		var sweep := Sweep.new("mace_2h", heavy, RID(), aim)
		sweep.trace_contact_sweep(space, aim, aim, beyond, far_face, options)
		_check(not _stop_present(sweep.take_terrain_contacts()), "A %s rejects the thin wall's hidden exit face" % (
			"heavy" if heavy else "light"))
		sweep.trace_contact_sweep(space, aim, aim, near, near_face, options)
		_check(_stop_present(sweep.take_terrain_contacts()), "A %s records a stop on the exposed wall face" % (
			"heavy" if heavy else "light"))


func _check_cleave() -> void:
	var first := Target.new()
	var second := Target.new()
	var third := Target.new()
	var cleave := CleaveRules.new("mace_2h", false, 1.0, {"damage": 0.8, "stagger": 3.5})
	var opener := cleave.resolve_actor(first)
	var secondary := cleave.resolve_actor(second)
	_check(opener.can_damage and opener.can_stagger and not secondary.can_damage and secondary.can_stagger,
		"Damage and stagger spend separate budgets based on prior accumulated mass")
	_check(cleave.resolve_actor(second).is_empty() and cleave.target_count == 2,
		"The cleave budget counts the same actor only once")
	var final := cleave.resolve_actor(third)
	_check(final.can_stagger and final.stop_kind == &"mass", "The final eligible actor receives its effect before the stop")
	first.material = &"armor"
	var light := CleaveRules.new("mace_2h", false)
	var heavy := CleaveRules.new("mace_2h", true)
	_check(light.resolve_actor(first).stop_kind == &"armor" and not heavy.resolve_actor(first).stops_weapon,
		"Armor stops a light while the default heavy slides through eligible armor")
	first.material = &"guard"
	var guard := CleaveRules.new("mace_2h", true)
	_check(guard.resolve_actor(first).stop_kind == &"guard" and guard.spent_mass > first.mass + 2.9,
		"A guard spends its shield mass bonus and can stop a heavy")
	first.material = &"body"
	first.stunned = true
	var powered := CleaveRules.new("mace_2h", true, 4.0, {"power_reference": 1.0, "power_exponent": 0.5})
	_check(is_equal_approx(powered.damage_budget, heavy.damage_budget * 2.0) \
		and is_equal_approx(powered.resolve_actor(first).mass_spent, first.mass * 0.75),
		"Power scales cleave and a staggered actor spends reduced mass")
	var prop := CleaveRules.new("mace_2h", false)
	_check(not prop.resolve_prop(1.0, false).stops_weapon and prop.resolve_prop(1.0, true).stops_weapon,
		"Both carry-through and stopping props spend cleave mass")
	for actor in [first, second, third]:
		actor.free()


func _check_live_location_rules() -> void:
	var game := Main.instantiate()
	game.save_enabled = false
	root.add_child(game)
	game._create_character(0, "Melee Contact Test")
	await _ticks(2)
	game._enter_training_ground()
	await _ticks(2)
	var player: Node3D = game.player
	var arena: Node3D = game.training_ground
	game._set_training_melee_contact_preset(false, false)
	_check(player.combat_enabled and not player.melee_stops_on_static_world,
		"Carry Through in Training lets swings continue through static surfaces")
	_equip_maul(player)
	var stand := Vector3(0.0, 0.08, 1.0)
	player.place_at(stand, 0.0)
	var practice_wall := _shape(stand + Vector3(0.0, 1.04, -0.9), Vector3(1.7, 2.1, 0.12),
		Sweep.WORLD_LAYER, arena)
	var outcome := await _tap_maul(player)
	_check(outcome.get("world_contact", false) and not outcome.get("rebound", false),
		"A live Training attack registers the wall and finishes the cut without a rebound")
	practice_wall.free()

	for stops: bool in [true, false]:
		player.place_at(stand, 0.0)
		var crate := Crate.instantiate() as Node3D
		crate.melee_hit_through = not stops
		arena.add_child(crate)
		crate.global_position = stand + Vector3(0.0, 1.0, -1.2)
		outcome = await _tap_maul(player)
		_check(crate._broken and outcome.get("rebound", false) == stops,
			"The live crate %s the attack according to its hit-through property" % ("stops" if stops else "lets through"))
		crate.free()

	game._set_training_melee_contact_preset(true, false)
	_check(player.combat_enabled and player.melee_stops_on_static_world,
		"Training Ground applies the hard-stop practice rules")
	_equip_maul(player)
	var pillar := arena.get_node("EastPillar/StaticBody3D2") as Node3D
	var practice_stand := pillar.global_position + Vector3.FORWARD * 2.31
	practice_stand.y = arena.spawn_position.y
	player.place_at(practice_stand, PI)
	outcome = await _tap_maul(player)
	_check(outcome.get("world_contact", false) and outcome.get("rebound", false),
		"The real practice pillar stops the same light attack with a weapon rebound")
	game.free()


func _shape(point: Vector3, size: Vector3, layer := Sweep.ENEMY_LAYER, parent: Node3D = null) -> Target:
	var body := Target.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	var container := _fixture if parent == null else parent
	container.add_child(body)
	body.global_position = point
	if layer == Sweep.ENEMY_LAYER:
		body.add_to_group(&"enemies")
	return body


func _blade(heel: Vector3, axis: Vector3, length := 1.1) -> PackedVector3Array:
	return PackedVector3Array([heel, heel + axis * length])


func _actor(target: Node3D, fraction: float) -> Dictionary:
	return {"kind": &"actor", "target": target, "fraction": fraction}


func _actors(contacts: Array[Dictionary]) -> Array[Node3D]:
	var actors: Array[Node3D] = []
	for contact in contacts:
		if contact.kind == &"actor":
			actors.append(contact.target)
	return actors


func _stop_present(contacts: Array[Dictionary]) -> bool:
	return contacts.any(func(contact: Dictionary) -> bool: return contact.get("can_stop", false))


func _equip_maul(player: Node3D) -> void:
	player.update_equipment({"main_hand": {"type": "mace_2h", "base_id": "quarry_maul"}})


func _tap_maul(player: Node3D) -> Dictionary:
	await _ticks(4)
	player._next_chain_stage = 1
	player._chain_time_left = 1.0
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	var started := false
	for _frame in 50:
		await _ticks(1)
		if player._weapon._mace_rebound_duration > 0.0:
			return {"rebound": true, "world_contact": player._clip_outcome.get("world_contact", false)}
		started = started or player._strike_pending
		if started and not player._strike_pending:
			return player._clip_outcome.duplicate()
	return {}


func _ticks(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame


func _check(condition: bool, caption: String) -> void:
	_checks += 1
	if condition:
		print("PASS  " + caption)
	else:
		_failures += 1
		push_error("FAIL  " + caption)
