extends "res://combat/enemies/ranged_enemy.gd"

const BeamScene := preload("res://combat/enemies/grave_reclaimer/reclaim_beam.tscn")
const SoulMotes := preload("res://combat/enemies/grave_legate/levy_fx.tscn")
const REVIVE := &"raise_the_fallen"
const CORPSE_POLL_SECONDS := 0.24
const SAME_FLOOR_HEIGHT := 1.45

const DEFINITION := {
	"id": 26,
	"name": "Grave Reclaimer",
	"level": 5,
	"family": "grave_reclaimer",
	"weapon": "unarmed",
	"skin": "666f67",
	"cloth": "34332a",
	"accent": "a49a72",
	"height": 1.82,
	"width": 0.31,
	"scale": 1.0,
	"part": "wraith_dust",
	"ranged": true,
}

var _find_corpse: Callable
var _revive_corpse: Callable
var _candidate: Node3D
var _casting_at: Node3D
var _corpse_name := ""
var _scan_remaining := 0.0
var _revival_range := 0.0
var _beam: MeshInstance3D
var _motes: GPUParticles3D


func definition() -> Dictionary:
	return DEFINITION


func configure_revival(find_corpse: Callable, revive_corpse: Callable) -> void:
	_find_corpse = find_corpse
	_revive_corpse = revive_corpse


func _ready() -> void:
	super._ready()
	var move := _abilities_by_id.get(String(REVIVE)) as AbilityDefinition
	if move != null:
		_revival_range = float(move.execution_profile["revival_range"])


func _physics_process(delta: float) -> void:
	if _engaged and not _dead and not _attack_cast_open and _find_corpse.is_valid() and _revive_corpse.is_valid():
		_scan_remaining -= delta
		if _scan_remaining <= 0.0:
			_scan_remaining = CORPSE_POLL_SECONDS
			_candidate = _find_corpse.call(self, _revival_range) as Node3D
	super._physics_process(delta)


func _attack_is_ready(move: String) -> bool:
	return is_instance_valid(_candidate) and super._attack_is_ready(move)


func _can_commit_here() -> bool:
	return super._can_commit_here() and can_reach_corpse(_candidate)


func can_reach_corpse(corpse: Node3D) -> bool:
	if not is_instance_valid(corpse) or corpse.is_queued_for_deletion():
		return false
	var offset := corpse.global_position - global_position
	if absf(offset.y) > SAME_FLOOR_HEIGHT or offset.length_squared() > _revival_range * _revival_range:
		return false
	var ray := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * _body_height * 0.65,
		corpse.global_position + Vector3.UP * 0.22, WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _begin_attack(direction: Vector3) -> void:
	_casting_at = _candidate
	var corpse_name: Variant = _casting_at.get("display_name") if "display_name" in _casting_at else null
	_corpse_name = String(corpse_name) if corpse_name != null else String(_casting_at.name)
	var toward_corpse := _flat(_casting_at.global_position - global_position).normalized()
	super._begin_attack(direction if toward_corpse.is_zero_approx() else toward_corpse)
	if _beam == null:
		_beam = BeamScene.instantiate() as MeshInstance3D
		_motes = SoulMotes.instantiate() as GPUParticles3D
		_beam.top_level = true
		_motes.top_level = true
		add_child(_beam)
		add_child(_motes)
	_beam.show()
	_motes.emitting = true
	_present_ritual(0.0)


func _predict_target() -> Vector3:
	if is_instance_valid(_casting_at):
		return _casting_at.global_position + Vector3.UP * 0.20
	return super._predict_target()


func _advance_windup(delta: float, to_player: Vector3) -> float:
	var progress := super._advance_windup(delta, to_player)
	if is_instance_valid(_casting_at):
		_present_ritual(progress)
	return progress


func _present_ritual(progress: float) -> void:
	var start := global_position + Vector3.UP * _body_height * 0.65
	var end := _casting_at.global_position + Vector3.UP * 0.16
	var axis := start.direction_to(end)
	var right := axis.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	var beam_basis := Basis(right, axis, right.cross(axis))
	_beam.global_transform = Transform3D(
		beam_basis.scaled_local(Vector3(1.0, start.distance_to(end), 1.0)), (start + end) * 0.5)
	_beam.set_instance_shader_parameter("progress", progress)
	_motes.global_position = end


func _release_attack() -> bool:
	if not _commit_attack_cost(_cast_definition()):
		return false
	if not can_reach_corpse(_casting_at) or not _revive_corpse.call(self, _casting_at):
		_finish_attack_cast(&"cast_cancel", "Body unavailable")
		return false
	_strike_time = 0.0
	_finish_attack_cast(&"cast_end")
	_candidate = null
	_end_ritual()
	return true


func _emit_cast(kind: StringName, ability: Dictionary, target: String, detail := "") -> void:
	var victim := _corpse_name if ability.get("id") == REVIVE else target
	super._emit_cast(kind, ability, victim, detail)


func _reset_attack() -> void:
	super._reset_attack()
	_end_ritual()


func _end_ritual() -> void:
	_casting_at = null
	_corpse_name = ""
	if is_instance_valid(_beam):
		_beam.hide()
		_motes.emitting = false
