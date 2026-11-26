extends CanvasLayer
## Bridges Crimson Carnage's camera effects to Hearth Below's live player.

enum ShakePriority { WEAPON = 1, WEAPON_STOP, BLOCK, DAMAGE, GUARD_BREAK }

const WeaponHitShake := preload("res://data/weapon_hit_shake.gd")
const DEFAULT_WEAPON_HIT_SHAKE := preload("res://data/weapon_hit_shake.tres")
const SCREEN_BLOOD_RULES := preload("res://data/screen_blood_rules.tres")

@onready var _lens := $LensBlood
@onready var _vignette := $DamageVignette
@onready var _indicator := $DamageIndicator
var _player: CharacterBody3D
var _camera: FirstPersonCameraEffects
var weapon_hit_shake: WeaponHitShake = DEFAULT_WEAPON_HIT_SHAKE
var _impact_lean := 0.0
var _combat_was_live := false
var _death_splatter_delay := 0.0


func bind_player(player: CharacterBody3D, camera: FirstPersonCameraEffects) -> void:
	_player = player
	_camera = camera
	_indicator.observer = player
	player.vitals_changed.connect(_refresh_health)
	_refresh_health()


func present_hit(life_lost: float, ward_lost: float, source: Vector3, blood: bool,
		direct_hit := false, hard_hit := false) -> void:
	if not is_instance_valid(_player) or life_lost + ward_lost <= 0.0:
		return
	if life_lost > 0.0:
		_vignette.pulse()
	if source.is_finite():
		_indicator.show_hit(source)
		var lateral := _player.global_basis.x.dot((source - _player.global_position).normalized())
		_impact_lean = clampf(_impact_lean + lateral * (0.018 + 0.005 * life_lost), -0.065, 0.065)
	if SCREEN_BLOOD_RULES.received_hits and blood and life_lost > 0.0:
		_lens.play_splatter()
	if direct_hit:
		var fraction := (life_lost + ward_lost * 0.55) / maxf(1.0, float(_player.stats.max_health))
		if hard_hit or fraction >= 0.075:
			var force := lerpf(0.38, 1.0, smoothstep(0.075, 0.40, fraction))
			if hard_hit:
				force = maxf(0.82, force)
			var side := _impact_side(source)
			_camera.kick_combat_view(Vector3(1.80, side * 1.35, -side * 1.80) * force,
				lerpf(0.15, 0.24, force), ShakePriority.DAMAGE)


func present_nearby_enemy_death(point: Vector3) -> void:
	if not SCREEN_BLOOD_RULES.nearby_deaths or _death_splatter_delay > 0.0 \
			or not is_instance_valid(_camera) or not point.is_finite():
		return
	var radius: float = SCREEN_BLOOD_RULES.nearby_death_distance
	if _camera.get_camera_transform().origin.distance_squared_to(point) >= radius * radius:
		return
	if SCREEN_BLOOD_RULES.visible_deaths_only and not _camera.is_position_in_frustum(point):
		return
	_death_splatter_delay = SCREEN_BLOOD_RULES.nearby_death_interval
	_lens.play_splatter()


func present_guard_impact(source: Vector3, fraction: float, broken: bool) -> void:
	var side := _impact_side(source)
	if broken:
		_camera.kick_combat_view(Vector3(2.10, side * 0.80, -side * 1.65), 0.24,
			ShakePriority.GUARD_BREAK)
	else:
		var force := lerpf(0.36, 0.85, smoothstep(0.18, 0.62, fraction))
		_camera.kick_combat_view(Vector3(0.82, side * 0.52, -side * 0.95) * force, 0.14,
			ShakePriority.BLOCK)


func present_weapon_impact(point: Vector3, travel: Vector3, weapon_type: String, charged: bool,
		hits: int, critical: bool, clip: StringName = &"") -> void:
	_present_weapon_shake(point, travel, Vector3.ZERO, weapon_type, &"body", charged,
		ShakePriority.WEAPON, hits, critical, clip)


func present_surface_impact(point: Vector3, weapon_type: String, kind: StringName, charged: bool,
		clip: StringName = &"") -> void:
	_present_weapon_shake(point, Vector3.ZERO, Vector3.ZERO, weapon_type, kind, charged,
		ShakePriority.WEAPON, 1, false, clip)


func present_mace_contact(point: Vector3, travel: Vector3, normal: Vector3,
		kind: StringName, charged: bool, clip: StringName = &"") -> void:
	present_melee_contact(point, travel, normal, "mace_2h", kind, charged, clip, kind != &"breakable")


func present_melee_contact(point: Vector3, travel: Vector3, normal: Vector3, weapon_type: String,
		kind: StringName, charged: bool, clip: StringName, stopped: bool) -> void:
	var priority := ShakePriority.WEAPON_STOP if stopped else ShakePriority.WEAPON
	_present_weapon_shake(point, travel, normal, weapon_type, kind, charged, priority, 1, false, clip)


func _present_weapon_shake(point: Vector3, travel: Vector3, normal: Vector3, weapon_type: String,
		kind: StringName, charged: bool, priority: int, hits: int, critical: bool, clip: StringName) -> void:
	var aim := _camera.aim_transform()
	var direction := travel.normalized() if travel.is_finite() else Vector3.ZERO
	var to_point := aim.origin.direction_to(point) if point.is_finite() else Vector3.ZERO
	if direction.is_zero_approx():
		direction = -aim.basis.z if to_point.is_zero_approx() else to_point
	var world_to_aim := aim.basis.inverse()
	var point_side := clampf(aim.basis.x.dot(to_point), -1.0, 1.0)
	var kick := weapon_hit_shake.kick_degrees(weapon_type, kind, charged, world_to_aim * direction,
		world_to_aim * normal, point_side, hits, critical, clip)
	var peak := Vector3(kick.x, kick.y, kick.z)
	if not peak.is_zero_approx():
		_camera.kick_combat_view(peak, kick.w, priority, WeaponHitShake.pulse_for(weapon_type, kind, clip))


func present_card_impact() -> void:
	_camera.kick_combat_view(Vector3(-1.48, 0.0, 0.38), 0.19, ShakePriority.BLOCK)


func _impact_side(source: Vector3) -> float:
	if not source.is_finite():
		return 0.0
	var aim := _camera.aim_transform()
	return clampf(aim.basis.x.dot(aim.origin.direction_to(source)), -1.0, 1.0)


func reset_transients() -> void:
	_lens.clear_splatter()
	_indicator.clear_hits()
	_vignette.clear_hit()
	_refresh_health()
	_impact_lean = 0.0
	_death_splatter_delay = 0.0
	if is_instance_valid(_camera):
		_camera.clear_combat_shake()


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var live: bool = _player.combat_enabled
	if _combat_was_live and not live:
		reset_transients()
	_combat_was_live = live
	_death_splatter_delay = maxf(0.0, _death_splatter_delay - delta)
	var actual := _player.get_real_velocity() if _player.gameplay_enabled else Vector3.ZERO
	var body_basis := _player.global_basis
	var forward_speed := -actual.dot(body_basis.z)
	var lateral_speed := actual.dot(body_basis.x)
	var tilt_fraction := clampf(lateral_speed / _camera.full_tilt_speed, -1.0, 1.0)
	var roll := -deg_to_rad(_camera.maximum_tilt) * tilt_fraction
	_impact_lean = move_toward(_impact_lean, 0.0, delta * 0.32)
	_camera.advance_view_roll(roll, _impact_lean, delta)
	_camera.advance_movement_fov(forward_speed / maxf(0.1, _player.base_move_speed), delta)


func _refresh_health() -> void:
	if not is_instance_valid(_player):
		return
	var max_health := maxf(1.0, float(_player.stats.get("max_health", 1.0)))
	var health := clampf(_player.life / max_health, 0.0, 1.0)
	_vignette.set_health_fraction(health if _player.combat_enabled and health > 0.0 else 1.0)
