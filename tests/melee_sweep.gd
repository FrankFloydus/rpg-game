extends SceneTree
## Exercises weapon sweeps against Godot physics shapes independent of enemy AI.

const MeleeSweep = preload("res://player/melee_sweep.gd")
const WeaponRoles = preload("res://combat/weapons/weapon_roles.gd")
const WeaponView = preload("res://player/weapon_view.gd")
const AttackAnimation = preload("res://combat/attack_animation.gd")
const WEAPONS := ["unarmed", "sword_1h", "mace_1h", "axe_1h", "sword_2h", "mace_2h", "axe_2h", "staff"]
const EDGED_BASES := {"axe_1h": "grave_hatchet", "axe_2h": "tithe_cleaver", "sword_2h": "vigil_greatsword"}
const TRACE_SAMPLES := 18

class Target extends StaticBody3D:
	func aim_point() -> Vector3:
		return global_position

var _world := Node3D.new()
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(_world)
	var center := _target(Vector3(0.02, 1.2, -1.75))
	var right := _target(Vector3(1.02, 1.2, -1.55))
	var left := _target(Vector3(-0.86, 1.2, -1.78))
	var rear := _target(Vector3(0.0, 1.2, 1.0))
	var distant := _target(Vector3(20.0, 1.2, -3.16))
	var behind_wall := _target(Vector3(40.0, 1.2, -1.75))
	var wall := _target(Vector3(40.0, 1.2, -0.96), 1, Vector3(2.8, 2.0, 0.17))
	var prop := _target(Vector3(60.0, 1.2, -1.42), 1)
	var blade_target := _target(Vector3(80.0, 1.5, -1.72))
	prop.add_to_group(&"breakable_props")
	# Bodies enter the physics space before the sweep is sampled.
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

	var sword := _sweep("sword_1h", 0.0)
	var hits := _hit_bodies(sword)
	_check(hits == [center, left, right] or hits == [center, right, left],
		"The sword catches both flanks once and resolves the aimed enemy first")
	_check(not hits.has(rear) and sword.terrain_contact().is_empty(),
		"The swept volume leaves enemies behind the player and empty terrain alone")
	if not sword.contacts().is_empty():
		var hit := sword.contacts()[0]
		_check(Vector3(hit.point).distance_to(center.global_position) < 0.34
			and Vector3(hit.direction).x < -0.1,
			"The aimed enemy receives a local contact and right-to-left swing direction")
	_check(_hit_bodies(_sweep("mace_1h", 20.0)).is_empty()
		and _hit_bodies(_sweep("sword_2h", 20.0)) == [distant],
		"The longsword can reach a target outside the one-handed mace's strike")
	var occluded := _sweep("sword_2h", 40.0)
	_check(not _hit_bodies(occluded).has(behind_wall) and occluded.terrain_contact().get("rid") == wall.get_rid(),
		"A solid wall prevents damage and supplies terrain impact coordinates")
	var impact := occluded.terrain_contact()
	_check(Vector3(impact.get("point", Vector3.INF)).is_equal_approx(Vector3(40.0, 1.5, -0.875))
		and Vector3(impact.get("normal", Vector3.ZERO)).dot(Vector3.BACK) > 0.99,
		"The contact stays near the aim on the front face when the swing reaches it")
	var prop_attack := _sweep("axe_1h", 60.0)
	_check(_hit_bodies(prop_attack) == [prop] and prop_attack.terrain_contact().is_empty(),
		"A breakable receives one contact separate from ordinary terrain")
	_test_blade_motion(blade_target)
	await _test_authored_attacks()

	_world.free()
	print("Hearth Below melee sweep: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_blade_motion(target: Target) -> void:
	var view := Transform3D(Basis.IDENTITY, Vector3(target.position.x, target.position.y, 0.0))
	var space := _world.get_world_3d().direct_space_state
	var heel := view.origin + Vector3.FORWARD * 0.7
	var tip := view.origin + Vector3.FORWARD * 1.86
	var blade := PackedVector3Array([heel, tip])
	var thrust := MeleeSweep.new("sword_1h", false, RID(), view)
	thrust.trace_blade(space, view,
		PackedVector3Array([heel + Vector3.BACK * 0.7, tip + Vector3.BACK * 0.7]), blade)
	var cut := MeleeSweep.new("sword_1h", false, RID(), view)
	cut.trace_blade(space, view,
		PackedVector3Array([heel + Vector3.RIGHT * 0.7, tip + Vector3.RIGHT * 0.7]), blade)
	if _hit_bodies(thrust) != [target] or _hit_bodies(cut) != [target]:
		_check(false, "Both authored blade paths reach the same contact target")
		return
	var thrust_contact := WeaponRoles.contact("sword_1h", "funeral_rapier", false, thrust.contacts()[0])
	var cut_contact := WeaponRoles.contact("sword_1h", "funeral_rapier", false, cut.contacts()[0])
	_check(not WeaponRoles.can_sever(thrust_contact) and WeaponRoles.can_sever(cut_contact),
		"The moving blade trace distinguishes an axial thrust from an edged swing")


func _test_authored_attacks() -> void:
	var weapon_view := WeaponView.new()
	for socket_name: StringName in [&"MainHand", &"OffHand"]:
		var socket := Node3D.new()
		socket.name = socket_name
		weapon_view.add_child(socket)
	_world.add_child(weapon_view)
	weapon_view.set_process(false)
	var targets := {}
	for index in WEAPONS.size():
		var weapon: String = WEAPONS[index]
		if weapon == "staff":
			continue
		var origin := Vector3(100.0 + float(index) * 14.0, 1.5, 0.0)
		var covered_origin := origin + Vector3.RIGHT * 6.0
		var target_distance := 1.24 if weapon == "unarmed" else 1.53
		var target_offset := Vector3(0.0, -0.08, -target_distance)
		var target_size := Vector3(0.45, 0.66, 0.33)
		var target := _target(origin + target_offset, 4, target_size)
		_target(covered_origin + target_offset, 4, target_size)
		var wall := _target(covered_origin + Vector3.FORWARD * (target_distance - 0.35), 1,
			Vector3(2.8, 2.0, 0.12))
		targets[weapon] = {"origin": origin, "target": target, "cover_origin": covered_origin,
			"wall": wall}
	await physics_frame
	await process_frame
	await physics_frame

	var timings := {}
	for weapon: String in WEAPONS:
		weapon_view.rebuild(weapon, "normal", "")
		var authored := {}
		timings[weapon] = authored
		var has_overhead := EDGED_BASES.has(weapon) or weapon == "mace_2h"
		var expected_stages := 3 if has_overhead else 2
		if weapon.begins_with("axe_"):
			_check_axe_ready_pose(weapon_view, weapon)
		for heavy: bool in [false, true]:
			var lane := "%s %s" % [weapon, "charged" if heavy else "light"]
			var tip_travel := PackedVector3Array()
			var impact_directions := PackedVector3Array()
			var clip_names: Array[StringName] = []
			for stage in range(1, expected_stages + 1):
				var name_key := weapon_view.attack_clip_name(heavy, stage)
				var animation := weapon_view.attack_animation(heavy, stage)
				var clip_label := "%s %s" % [weapon, name_key]
				if not clip_names.has(name_key):
					clip_names.append(name_key)
				var timing := AttackAnimation.read(animation) as AttackAnimation
				if not _check(timing != null and animation.has_marker(AttackAnimation.IMPACT)
						and timing.trace_start < timing.impact and timing.impact < timing.trace_end
						and timing.trace_end <= timing.input_buffer and timing.input_buffer < timing.length,
						"%s keeps ordered and editable Trace, Impact, and Buffer markers" % clip_label):
					continue
				authored[name_key] = timing
				if weapon == "staff":
					continue
				var fixture: Dictionary = targets[weapon]
				var aim := Transform3D(Basis.IDENTITY, fixture.origin)
				var covered_aim := Transform3D(Basis.IDENTITY, fixture.cover_origin)
				var open_sweep := _sweep_authored_clip(weapon_view, weapon, heavy, name_key, timing, aim)
				var covered_sweep := _sweep_authored_clip(weapon_view, weapon, heavy, name_key, timing, covered_aim)
				var contacts := open_sweep.take_contacts()
				if _check(contacts.size() == 1 and contacts[0].target == fixture.target
						and open_sweep.take_contacts().is_empty(), "%s hits a frontal target only once" % clip_label):
					impact_directions.append(contacts[0].direction)
					if EDGED_BASES.has(weapon):
						_check_edged_contact(weapon_view, weapon, name_key, heavy, contacts[0], aim)
				_check(covered_sweep.take_contacts().is_empty()
					and covered_sweep.terrain_contact().get("rid") == fixture.wall.get_rid(),
					"%s produces a wall contact and cannot reach through cover" % clip_label)
				var blade_start := weapon_view.sample_blade(name_key, timing.trace_start, aim)
				var blade_end := weapon_view.sample_blade(name_key, timing.trace_end, aim)
				tip_travel.append(blade_end[1] - blade_start[1])
				if has_overhead:
					_check_strike_endpoints(clip_label, stage, blade_start[1] - aim.origin, blade_end[1] - aim.origin)
			_check(clip_names.size() == expected_stages, "%s has %d distinct chain stages" % [lane, expected_stages])
			if has_overhead:
				_check_three_strike_directions(lane, tip_travel, impact_directions)
			elif weapon != "staff":
				_check(tip_travel.size() == 2 and tip_travel[0].x * tip_travel[1].x < -0.01,
					"%s follows through from opposing sides across the chain (%s)" % [lane, tip_travel])
				_check(impact_directions.size() == 2 and impact_directions[0].x * impact_directions[1].x < -0.01,
					"%s reports the opposite impact direction on its follow-up (%s)" % [lane, impact_directions])
	weapon_view.free()
	for family: String in ["sword", "mace", "axe"]:
		for clip: StringName in [&"light", &"light_2", &"heavy", &"heavy_2"]:
			var one: AttackAnimation = timings[family + "_1h"].get(clip)
			var two: AttackAnimation = timings[family + "_2h"].get(clip)
			_check(one != null and two != null and two.length > one.length * 1.15
				and two.impact > one.impact and two.length - two.trace_end > one.length - one.trace_end,
				"Two-handed %s %s spends more time on anticipation and recovery" % [family, clip])


func _check_axe_ready_pose(weapon_view: WeaponView, weapon: String) -> void:
	var model := weapon_view.get_node("MainHand").get_child(0)
	var pose := model.get_node("Pose") as Node3D
	var animator := model.get_node("AnimationPlayer") as AnimationPlayer
	animator.play(&"idle")
	animator.seek(0.0, true, true)
	# Both meshes' cutting edges extend along the weapon's local positive X.
	var edge := pose.global_basis.x.normalized()
	_check(pose.global_position.x > 0.0 and edge.x < -0.10,
		"%s holds its blade facing inward in the ready pose (%s)" % [weapon, edge])


func _check_edged_contact(weapon_view: WeaponView, weapon: String, clip: StringName, heavy: bool,
		contact: Dictionary, aim: Transform3D) -> void:
	var hit := WeaponRoles.contact(weapon, EDGED_BASES[weapon], heavy, contact)
	_check(not Vector3(contact.blade_axis).is_zero_approx() and WeaponRoles.can_sever(hit),
		"%s %s registers its moving edge contact as a cut" % [weapon, clip])
	weapon_view.sample_blade(clip, contact.fixture_time, aim)
	var pose := weapon_view.get_node("MainHand").get_child(0).get_node("Pose") as Node3D
	var leading_edge := pose.global_basis.x.normalized().dot(Vector3(contact.direction))
	if weapon == "sword_2h":
		# The blade is sharpened on both sides, so either edge can lead a cut.
		leading_edge = absf(leading_edge)
	_check(leading_edge > 0.1,
		"%s %s leads the physical impact with its visible cutting edge (%.3f at %.3fs)" \
		% [weapon, clip, leading_edge, contact.fixture_time])


func _check_three_strike_directions(lane: String, tip_travel: PackedVector3Array,
		impact_directions: PackedVector3Array) -> void:
	_check(tip_travel.size() == 3 and tip_travel[0].x > 0.65 and tip_travel[1].x < -0.65,
		"%s sweeps left-to-right and then right-to-left over the active window (%s)" % [lane, tip_travel])
	_check(impact_directions.size() == 3 and impact_directions[0].x > 0.35 and impact_directions[1].x < -0.35,
		"%s applies the corresponding direction on each side hit (%s)" % [lane, impact_directions])
	_check(tip_travel.size() == 3 and tip_travel[2].y < -0.75 and absf(tip_travel[2].x) < 0.32,
		"%s ends in a strong vertical stroke with little sideways travel (%s)" % [lane, tip_travel])
	_check(impact_directions.size() == 3 and impact_directions[2].y < -0.55 and absf(impact_directions[2].x) < 0.35,
		"%s reports a predominantly downward third contact (%s)" % [lane, impact_directions])


func _check_strike_endpoints(clip: String, stage: int, start: Vector3, finish: Vector3) -> void:
	if stage < 3:
		var sign := 1.0 if stage == 1 else -1.0
		_check(start.x * sign < -0.30 and finish.x * sign > 0.30,
			"%s crosses the view from its own side (%s to %s)" % [clip, start, finish])
	else:
		_check(start.y > 0.32 and finish.y < -0.28 and maxf(absf(start.x), absf(finish.x)) < 0.35,
			"%s begins above the view center and finishes below it (%s to %s)" % [clip, start, finish])


func _sweep_authored_clip(weapon_view: WeaponView, weapon: String, heavy: bool,
		clip: StringName, timing: AttackAnimation, aim: Transform3D) -> MeleeSweep:
	var sweep := MeleeSweep.new(weapon, heavy, RID(), aim)
	var space := _world.get_world_3d().direct_space_state
	var previous := weapon_view.sample_blade(clip, timing.trace_start, aim)
	var previous_time := timing.trace_start
	for sample in range(1, TRACE_SAMPLES + 1):
		var at := lerpf(timing.trace_start, timing.trace_end, float(sample) / TRACE_SAMPLES)
		var current := weapon_view.sample_blade(clip, at, aim)
		sweep.trace_blade(space, aim, previous, current)
		if EDGED_BASES.has(weapon):
			for contact in sweep.contacts():
				if not contact.has("fixture_time"):
					contact.fixture_time = lerpf(previous_time, at, contact.fraction)
		previous = current
		previous_time = at
	return sweep


func _sweep(weapon: String, x: float) -> MeleeSweep:
	var view := Transform3D(Basis.IDENTITY, Vector3(x, 1.5, 0.0))
	var sweep := MeleeSweep.new(weapon, false, RID(), view)
	for tick in range(1, 10):
		sweep.sample(_world.get_world_3d().direct_space_state, view,
			MeleeSweep.CONTACT_WINDOW * (1.0 - float(tick) / 9.0))
	return sweep


func _hit_bodies(sweep: MeleeSweep) -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for contact in sweep.contacts():
		bodies.append(contact.target)
	return bodies


func _target(point: Vector3, layer := 4, size := Vector3(0.34, 0.46, 0.30)) -> Target:
	var actor := Target.new()
	actor.collision_layer = layer
	actor.collision_mask = 0
	if layer == 4:
		actor.add_to_group(&"enemies")
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	actor.add_child(collision)
	actor.position = point
	_world.add_child(actor)
	return actor


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + description)
	else:
		_failures += 1
		push_error("FAIL  " + description)
	return condition
