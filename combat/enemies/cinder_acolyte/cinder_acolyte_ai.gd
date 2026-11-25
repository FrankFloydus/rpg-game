extends "res://combat/enemies/ranged_enemy.gd"

const GroundCast := preload("res://combat/effects/ground_cast.gd")
const SigilFlame := preload("res://combat/effects/cinder_sigil_flame.tscn")
const SigilCharge := preload("res://combat/effects/cinder_sigil_charge.tscn")
const SIGIL := "cinder_sigil"

const DEFINITION := {
	"id": 5,
	"name": "Cinder Acolyte",
	"level": 1,
	"family": "cultist",
	"weapon": "staff",
	"skin": "b37b6b",
	"cloth": "533038",
	"accent": "f78b48",
	"height": 1.96,
	"width": 0.30,
	"scale": 1.0,
	"part": "cursed_ember",
	"ranged": true,
	"additional_moves_level": 1,
}

var _sigil_charge: Node3D


func definition() -> Dictionary:
	return DEFINITION


func _is_projectile_attack() -> bool:
	return _move_id == SIGIL or super._is_projectile_attack()


func _begin_attack(direction: Vector3) -> void:
	if _move_id == SIGIL:
		_profile = _profile.duplicate()
		var reach := float(_profile.reach) * _attack_scale()
		var width := float(_profile.width) * _attack_scale()
		var open := GroundCast.open_length(self, global_position, direction, reach, width)
		_profile.reach = maxf(0.02, open / _attack_scale())
	super._begin_attack(direction)
	if _move_id == SIGIL:
		if _sigil_charge == null:
			_sigil_charge = SigilCharge.instantiate()
			add_child(_sigil_charge)
		_sigil_charge.position = Vector3(-0.20, _body_height * 0.77, -0.41)
		_sigil_charge.scale = Vector3.ONE * 0.38
		_sigil_charge.show()
		_sigil_charge.get_node("Embers").emitting = true


func _advance_windup(delta: float, to_player: Vector3) -> float:
	var fraction := super._advance_windup(delta, to_player)
	if _move_id == SIGIL and _sigil_charge != null and _sigil_charge.visible:
		_sigil_charge.scale = Vector3.ONE * lerpf(0.38, 1.0, fraction)
	return fraction


func _release_attack() -> bool:
	_hide_sigil_charge()
	return super._release_attack()


func _reset_attack() -> void:
	_hide_sigil_charge()
	super._reset_attack()


func _hide_sigil_charge() -> void:
	if _sigil_charge != null:
		_sigil_charge.get_node("Embers").emitting = false
		_sigil_charge.hide()


func _fire_volley() -> void:
	if _move_id != SIGIL:
		super._fire_volley()
		return
	var origin := _floor_warning_origin()
	var reach := float(_warning_footprint.reach)
	var width := float(_warning_footprint.width)
	# A closing door also stops a sigil that was already marked.
	reach = GroundCast.open_length(self, origin, _windup_toward, reach, width)
	if reach <= 0.10:
		return
	var flame := SigilFlame.instantiate() as GPUParticles3D
	get_parent().add_child(flame)
	flame.global_position = origin + _windup_toward * reach * 0.5 + Vector3.UP * 0.14
	flame.look_at(flame.global_position + _windup_toward)
	var flame_material := flame.process_material as ParticleProcessMaterial
	flame_material.emission_box_extents = Vector3(width * 0.79, 0.05, reach * 0.48)
	flame.restart()
	flame.emitting = true
	var footprint := {"shape": "lane", "reach": reach, "width": width}
	var hit := GroundCast.target_in_footprint(self, _player, footprint, origin, _windup_toward) \
		and _damage_player()
	if _ability_trace.is_valid():
		_ability_trace.call({"shape": "lane", "origin": origin + Vector3.UP * ABILITY_TRACE_HEIGHT,
			"direction": _windup_toward, "reach": reach, "width": width, "hit": hit})
