extends SceneTree
## Retimes live attacks without replacing authored animation resources.

const Game := preload("res://main.tscn")
const Catalog := preload("res://combat/enemies/enemy_catalog.gd")
const Items := preload("res://systems/items.gd")
const Sweep := preload("res://combat/abilities/stone_arm_sweep.tres")
const Slam := preload("res://combat/abilities/sepulchre_slam.tres")
const Timeline := preload("res://combat/attack_animation.gd")

var _game: Node
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
	await _ticks(3)
	_player = _game.player
	var quick := await _sample_enemy(Sweep, 0.42)
	var slow := await _sample_enemy(Sweep, 1.02)
	_compare_enemy(quick, slow)
	var short_warning := await _sample_enemy(Slam, 0.12)
	var edited_warning := await _sample_enemy(Slam, 1.72)
	_compare_warning(short_warning, edited_warning)
	await _check_player_chain()
	_check_enemy_pose_libraries()
	_game.free()
	await process_frame
	print("combat_timeline_editing: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _sample_enemy(original: AbilityDefinition, seconds: float) -> Dictionary:
	_player.place_at(Vector3(0, 0.08, 2.35))
	_player.restore_full()
	var enemy := Catalog.instantiate(16)
	var ability := original.duplicate() as AbilityDefinition
	ability.windup = seconds
	var abilities: Array[AbilityDefinition] = [ability]
	enemy.ability_loadout = abilities
	var affixes: Array[String] = []
	var events: Array = []
	enemy.combat_event.connect(func(event: Dictionary) -> void: events.append(event))
	_game._prepare_training_enemy(enemy, 5, "normal", affixes, Vector3(0, 0.08, 0.3))
	var intended_windup := -1.0
	var total := -1.0
	var started := -1
	var strike_start := -1
	var cast_ended := -1
	var mid_tick := -1
	var mid_rotation := Quaternion.IDENTITY
	var trace_time := -1.0
	var animation_id := 0
	for tick in 255:
		await _ticks(1)
		if started < 0 and events.any(func(event: Dictionary) -> bool: return event.kind == &"cast_start"):
			started = tick
			total = enemy._windup_total
			intended_windup = seconds * enemy._windup_multiplier
			animation_id = enemy._model.strike_clip().get_instance_id()
		if started < 0:
			continue
		if mid_tick < 0 and enemy._windup_pose >= 0.5 and enemy._strike_time < 0.0:
			mid_tick = tick - started
			var skeleton: Skeleton3D = enemy._model._skeleton
			mid_rotation = skeleton.get_bone_pose_rotation(skeleton.find_bone("ArmRight1"))
		if strike_start < 0 and enemy._strike_time >= 0.0:
			strike_start = tick - started
		if events.any(func(event: Dictionary) -> bool: return event.kind == &"cast_end"):
			cast_ended = tick - started
			trace_time = enemy._model.strike_clip().length * enemy._strike_progress()
			break
	enemy.queue_free()
	await _ticks(2)
	return {"model_clip": animation_id, "requested": seconds, "authored": intended_windup, "total": total,
		"mid_tick": mid_tick, "mid_rotation": mid_rotation, "strike_start": strike_start, "cast_ended": cast_ended,
		"trace_phase": trace_time}


func _compare_enemy(quick: Dictionary, slow: Dictionary) -> void:
	_check(quick.strike_start > 0 and slow.strike_start > quick.strike_start + 24
		and quick.model_clip == slow.model_clip, "Editing an ability retimes a real enemy windup on the same rig clip")
	_check(quick.mid_tick > 0 and slow.mid_tick > quick.mid_tick + 12
		and quick.mid_rotation.angle_to(slow.mid_rotation) < 0.22,
		"The model reaches approximately the same half-windup pose at its retimed midpoint")
	_check(quick.cast_ended > quick.strike_start and slow.cast_ended > slow.strike_start
		and absf(quick.trace_phase - slow.trace_phase) < 0.08,
		"The actual melee trace still commits at the same normalized strike phase")
	print("Enemy windups, animation halfway, and trace start in ticks: ", quick, " ", slow)


func _compare_warning(short: Dictionary, slow: Dictionary) -> void:
	_check(short.total > short.requested + 0.35 and short.total < slow.total
		and slow.cast_ended > short.cast_ended and short.model_clip == slow.model_clip,
		"Floor warnings preserve the authored longer windup and expand a too-short edit to a walkable window")
	_check(short.mid_tick > 0 and slow.mid_tick > short.mid_tick
		and short.mid_rotation.angle_to(slow.mid_rotation) < 0.20,
		"The warning and the model share the same expanded windup duration")
	print("Fair warning duration below/above the authored lower bound: ", short.total, " / ", slow.total)


func _check_player_chain() -> void:
	_player.update_equipment({"main_hand": Items.training_weapon_preview("oath_blade")})
	_player.restore_full()
	var clip: Animation = _player._weapon.attack_animation(false, 2)
	var baseline_trace := clip.get_marker_time(Timeline.TRACE_START)
	var baseline_buffer := clip.get_marker_time(Timeline.INPUT_BUFFER)
	var trace_color := clip.get_marker_color(Timeline.TRACE_START)
	var buffer_color := clip.get_marker_color(Timeline.INPUT_BUFFER)
	var later_start := lerpf(baseline_trace, clip.get_marker_time(Timeline.TRACE_END), 0.54)
	var earlier_buffer := lerpf(later_start, baseline_buffer, 0.23)
	var normal := await _sample_player_chain()
	clip.remove_marker(Timeline.TRACE_START)
	clip.remove_marker(Timeline.INPUT_BUFFER)
	clip.add_marker(Timeline.TRACE_START, later_start)
	clip.add_marker(Timeline.INPUT_BUFFER, earlier_buffer)
	var edited := await _sample_player_chain()
	clip.remove_marker(Timeline.TRACE_START)
	clip.remove_marker(Timeline.INPUT_BUFFER)
	clip.add_marker(Timeline.TRACE_START, baseline_trace)
	clip.add_marker(Timeline.INPUT_BUFFER, baseline_buffer)
	clip.set_marker_color(Timeline.TRACE_START, trace_color)
	clip.set_marker_color(Timeline.INPUT_BUFFER, buffer_color)
	_check(normal.stage == 2 and edited.stage == 2 and normal.active and edited.active
		and normal.animation == edited.animation, "Both real casts use the same light chain step")
	_check(normal.sampled > 0.0 and edited.sampled > normal.sampled
		and edited.sampled >= later_start and edited.sampled - later_start <= 1.0 / Engine.physics_ticks_per_second + 0.001,
		"Moving the chain step's Trace Start marker moves collision sampling")
	_check(normal.buffered > 0.0 and edited.buffered > 0.0 and edited.buffered <= normal.buffered
		and edited.buffered >= earlier_buffer and edited.buffered - earlier_buffer <= 1.0 / Engine.physics_ticks_per_second + 0.001,
		"Moving the chain step's Input Buffer marker moves when another action is accepted")
	print("Player chain-2 trace and buffer marker crossings: ", normal, " ", edited)


func _sample_player_chain() -> Dictionary:
	_player.restore_full()
	_player._chain_time_left = 0.8
	_player._next_chain_stage = 2
	var sampling: Array[float] = []
	_player.weapon_trace = func(_transform: Transform3D, _size: Vector3) -> void:
		sampling.append(_player._current_clip_time())
	var active: bool = _player.cast_ability(_player._weapon_attack_ability(false))
	var step := int(_player._strike_chain_stage)
	var animation := StringName(_player._strike_animation)
	var buffered := -1.0
	for tick in 60:
		await _ticks(1)
		if _player._strike_clip == null:
			break
		if buffered < 0.0 and _player._can_buffer_attack():
			buffered = _player._current_clip_time()
	_player.weapon_trace = Callable()
	return {"stage": step, "active": active, "animation": animation, "buffered": buffered,
		"sampled": sampling[0] if not sampling.is_empty() else -1.0}


func _check_enemy_pose_libraries() -> void:
	var edited_pairs := 0
	for archetype in Catalog.ARCHETYPES.size():
		var enemy := Catalog.instantiate(archetype)
		var affixes: Array[String] = []
		_game._prepare_training_enemy(enemy, 5, "normal", affixes, Vector3(0, 0.08, 0.3))
		var model: Node3D = enemy._model
		var strike: Animation = model.strike_clip()
		var title := str(Catalog.ARCHETYPES[archetype].name)
		var skeleton: Skeleton3D = model._skeleton
		var motion_is_valid := strike != null and is_instance_valid(skeleton)
		if motion_is_valid:
			motion_is_valid = _has_continuous_release(model, skeleton)
			for move: StringName in model._attack_clips:
				model.select_attack_animation(move)
				edited_pairs += 1
				motion_is_valid = motion_is_valid and model.strike_clip() != strike and _has_continuous_release(model, skeleton)
		_check(motion_is_valid, "%s has distinct anticipation and impact with a continuous release" % title)
		enemy.free()
	_check(edited_pairs >= 20, "Distinct moves can select their own paired bone animation without changing the AI schema")


func _has_continuous_release(model: Node3D, skeleton: Skeleton3D) -> bool:
	model.animate(0.0, 0.0, 0.0, -1.0)
	var idle := _pose_rotations(skeleton)
	model.animate(0.0, 0.0, 1.0, -1.0)
	var prepared := _pose_rotations(skeleton)
	model.animate(0.0, 0.0, 0.0, 0.0)
	var release := _pose_rotations(skeleton)
	model.animate(0.0, 0.0, 0.0, 0.35)
	var hit := _pose_rotations(skeleton)
	return (_max_angle(idle, prepared) >= 0.19 and _max_angle(prepared, release) < 0.01
		and _max_angle(release, hit) >= 0.20)


func _pose_rotations(skeleton: Skeleton3D) -> Array[Quaternion]:
	var result: Array[Quaternion] = []
	for bone in skeleton.get_bone_count():
		result.append(skeleton.get_bone_pose_rotation(bone))
	return result


func _max_angle(a: Array[Quaternion], b: Array[Quaternion]) -> float:
	var widest := 0.0
	for bone in a.size():
		widest = maxf(widest, a[bone].angle_to(b[bone]))
	return widest


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS " + description)
	else:
		_failures += 1
		printerr("FAIL " + description)
