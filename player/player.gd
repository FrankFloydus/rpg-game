extends CharacterBody3D

const Items = preload("res://systems/items.gd")
const ItemBases = preload("res://data/items/bases.gd")
const StatusCatalog = preload("res://combat/effects/status_catalog.gd")
const AbilityRuntime = preload("res://combat/abilities/ability_runtime.gd")
const EnrageEffect = preload("res://combat/effects/enrage_effect_definition.gd")
const HitEffects = preload("res://combat/effects/hit_effects.gd")
const CombatVisuals = preload("res://combat/effects/combat_visuals.gd")
const BreakableProp = preload("res://world/modules/breakable_prop.gd")
const MeleeSweep = preload("res://player/melee_sweep.gd")
const MeleeContactSession = preload("res://player/melee_contact_session.gd")
const MeleeContactRules = preload("res://combat/weapons/melee_contact_rules.gd")
const MELEE_CONTACT = preload("res://data/melee_contact.tres")
const CombatImpact = preload("res://combat/effects/combat_impact.gd")
const CombatFloaters = preload("res://combat/effects/combat_floaters.gd")
const DamageResolution = preload("res://combat/damage_resolution.gd")
const CardEffects = preload("res://combat/cards/card_effects.gd")
const Progression = preload("res://systems/character_progression.gd")
const StunRuntime = preload("res://combat/effects/stun_runtime.gd")
const DefensiveLegendaries = preload("res://combat/effects/defensive_legendary_runtime.gd")
const WeaponRoles = preload("res://combat/weapons/weapon_roles.gd")
const WeaponHitShake := preload("res://data/weapon_hit_shake.gd")
const LegendaryMelee = preload("res://combat/weapons/legendary_weapon_runtime.gd")
const CasterLegendaryEffects = preload("res://combat/effects/caster_legendary_effects.gd")

signal vitals_changed
signal feedback(message: String, event: String)
signal died
signal struck(enemy: Node3D, amount: float, critical: bool)
signal combat_event(event: Dictionary)
signal active_statuses_changed

const ELEMENTS = ["fire", "cold", "lightning", "poison"]
const AILMENT_LOG_INTERVAL := 0.4
const COMBAT_VISUAL_OFFSET := Vector3(0.0, 1.0, 0.0)
const MELEE_ATTACK := preload("res://combat/abilities/light_attack.tres")
const MELEE_HEAVY := preload("res://combat/abilities/heavy_attack.tres")
const ATTACK_TEMPO := preload("res://data/attack_tempo.tres")
const IMPACT_FEEDBACK := preload("res://data/impact_feedback.tres")
const STAFF_ATTACK := preload("res://combat/abilities/staff_bolt.tres")
const STAFF_HEAVY := preload("res://combat/abilities/forked_staff_bolt.tres")
const AttackAnimation := preload("res://combat/attack_animation.gd")
const STAMINA_RULES := preload("res://data/stamina_rules.tres")
const STAFF_ARC := preload("res://player/effects/staff_arc.tscn")
const ASHWAKE := {"name": "Ashwake", "description": "Heavy attacks release a burst of Fire damage around their first target."}
const STORMCALL := {"name": "Stormcall", "description": "Every fourth landed strike arcs Lightning damage to a nearby enemy."}
const INTERVALS = {"unarmed": 0.43, "dagger_1h": 0.34, "sword_1h": 0.45, "mace_1h": 0.57, "axe_1h": 0.58,
	"sword_2h": 0.82, "mace_2h": 1.00, "axe_2h": 0.90, "staff": 0.57}
const INPUT_BUFFER_SECONDS := 0.22
const ATTACK_CHAIN_GRACE_SECONDS := 0.55
const MACE_LIGHT_CHAIN_BLEND_SECONDS := 0.17
enum MaceStage { RIGHT = 1, LEFT, DOWN_LEFT, DOWN_RIGHT }
const MACE_LIGHT_CHAIN := [
	MaceStage.LEFT, MaceStage.RIGHT, MaceStage.DOWN_LEFT, MaceStage.DOWN_RIGHT,
]
const CHARGED_RELEASE_SECONDS := 0.06
const MANUAL_CHARGE_BLEND_SECONDS := 0.080
const MELEE_RELEASE_SECONDS := 0.078
const TWO_HANDED_RELEASE_SECONDS := 0.125
const COMBAT_BACKPEDAL_FACTOR := 0.62
const COMBAT_STRAFE_FACTOR := 0.85
const GRAVITY := 14.7
const GROUND_ACCELERATION := 45.0
const AIR_ACCELERATION := 16.0
const JUMP_BUFFER_SECONDS := 0.12
const JUMP_GRACE_SECONDS := 0.082
const WATER_TORSO := 0.76
const WATER_SWIM_FACTOR := 0.70
const WATER_SWIM_ACCELERATION := 12.0

@export_group("Abilities")
## Runtime copy of the main scene's Primary Ability. Leave empty for the equipped weapon's normal attack.
## A shared arc or area ability uses its authored hit effects, Mana cost, and cooldown.
@export var light_ability_override: AbilityDefinition
## Runtime copy of the main scene's charged ability. Leave empty for the equipped weapon's charged attack.
## A shared arc or area ability uses its authored hit effects, Mana cost, and cooldown.
@export var heavy_ability_override: AbilityDefinition
## Begin the visible charge after holding this long. Releasing before the charge commits makes a light attack.
@export_range(0.04, 0.35, 0.01, "suffix:s") var tap_seconds := 0.16
## Minimum wind-up after a hold becomes a charged attack. The equipped charge clip can extend it.
@export_range(0.1, 2.0, 0.01, "suffix:s") var charge_seconds := 0.34
## How long a fresh attack press can wait for the two-handed mace's next link. Repeated taps refresh one slot.
@export_range(0.05, 1.0, 0.01, "suffix:s") var mace_followup_buffer_seconds := 0.50

@export_group("Movement")
## Ground speed before direction, stance, and equipment modifiers.
@export_range(0.5, 12.0, 0.05, "suffix:m/s") var base_move_speed := 4.25
## Initial upward speed from a grounded Space press.
@export_range(1.0, 9.0, 0.05, "suffix:m/s") var jump_speed := 6.0
## Peak ground speed multiplier applied to held movement during a two-handed mace swing.
@export_range(1.0, 2.0, 0.01, "suffix:×") var mace_surge_speed_multiplier := 1.40

@export_group("Stun")
## Buildup required from unblocked hits before the player becomes stunned.
@export_range(1.0, 500.0, 1.0, "or_greater") var stun_threshold := StunRuntime.DEFAULT_THRESHOLD

var camera: FirstPersonCameraEffects
var stats: Dictionary
var effects: Array[String] = []
var card_effects := CardEffects.new()
var character_progression := Progression.new()
var life := float(Items.BASE_STATS["max_health"])
var mana := float(Items.BASE_STATS["max_mana"])
var ward := float(Items.BASE_STATS["ward"])
var stamina := float(Items.BASE_STATS["max_stamina"])
var gameplay_enabled := true:
	set(enabled):
		if gameplay_enabled == enabled:
			return
		gameplay_enabled = enabled
		if enabled:
			_ignore_held_attack()
		else:
			# Hold the displayed recovery pose through the menu. It settles when the weapon resumes processing.
			var recovering_strike := _strike_clip != null and _clip_released and not _strike_pending
			_reset_combat_inputs("Combat paused")
			if is_instance_valid(camera):
				camera.clear_combat_shake(recovering_strike)
		if is_instance_valid(_weapon):
			_weapon.set_process(enabled)
var combat_enabled := false:
	set(enabled):
		if combat_enabled == enabled:
			return
		combat_enabled = enabled
		_reset_combat_inputs("Combat ended")
var melee_stops_on_static_world := false
var melee_uses_refuge_sweep := false
var weapon_type := "sword_1h"

var _equipment: Dictionary = {}
var _water_volume: Node3D
var _underwater_blend := 0.0
var _jump_grace := 0.0
@onready var _water_tint: ColorRect = $SubmergedView/WaterTint
var weapon_trace: Callable
var _dual_wield := false
var _offhand_type := ""
var _offhand_base_id := ""
var _weapon_base_id := "oath_blade"
var _neck: Node3D
var _weapon: Node3D
@onready var _weapon_sway := $Neck/Camera3D/WeaponView/WeaponSway
var _lamp: OmniLight3D
var _camera_feedback: CanvasLayer
var _rng := RandomNumberGenerator.new()
var _ability_runtime := AbilityRuntime.new()
var _stun := StunRuntime.new()
var _attack_timer := 0.0
var _strike_tempo := 1.0
var _strike_remaining := 0.0
var _strike_pending := false
var _strike_is_follow_up := false
var _strike_heavy := false
var _strike_is_melee := false
var _strike_ability: AbilityDefinition
var _strike_sweep: MeleeSweep
var _paired_sweep: MeleeSweep
var _contact_session: MeleeContactSession
var _contact_cleave: MeleeContactRules
var _paired_contact_cleave: MeleeContactRules
var _strike_hand := WeaponRoles.MAIN_HAND
var _strike_clip: AttackAnimation
var _strike_animation := &""
var _strike_chain_stage := 1
var _next_chain_stage := 1
var _chain_time_left := 0.0
var _clip_duration := 0.0
var _clip_pose_time := 0.0
var _clip_release_start := 0.0
var _clip_release_impact := 0.0
var _clip_combo_entry := 0.0
var _clip_outcome: Dictionary = {}
var _clip_last_blade := PackedVector3Array()
var _paired_last_blade := PackedVector3Array()
var _clip_last_aim := Transform3D.IDENTITY
var _clip_released := false
var _weapon_card_landed := false
var _attack_commit := 0.0
var _attack_button_down := false
var _attack_intent := false
var _attack_hold_elapsed := 0.0
var _light_buffer := 0.0
var _mace_followup_time := 0.0
var _mace_followup_tapped := false
var _linked_charge_light_stage := 0
var _charging_attack := false
var _charge_duration := 0.0
var _release_duration := CHARGED_RELEASE_SECONDS
var _manual_charge_release_phase := INF
var _jump_buffer := 0.0
var _guard_held := false
var _blocking := false
var _guard_attack := false
var _shield_equipped := false
var _stamina_recovery := 0.0
var _push_velocity := Vector3.ZERO
var _push_rearm := 0.0
var _recovery_timer := 0.0
var _soul_timer := 0.0
var _phase_timer := 0.0
var _storm_hits := 0
var _legendary_melee := LegendaryMelee.new()
var _caster_legendaries := CasterLegendaryEffects.new()
var _ailments: Dictionary = {}
var _defensive_legendaries := DefensiveLegendaries.new()
var _dead := false


func _ready() -> void:
	_rng.randomize()
	_neck = $Neck
	camera = $Neck/Camera3D
	_weapon = $Neck/Camera3D/WeaponView
	_lamp = $Neck/Camera3D/PlayerLamp
	_camera_feedback = get_node_or_null("CameraFeedback")
	update_equipment({})
	restore_full()
	if _camera_feedback != null:
		_camera_feedback.bind_player(self, camera)


func update_equipment(equipment: Dictionary) -> void:
	_equipment = equipment
	_refresh_effective_stats(false)
	effects = Items.legendary_effects(equipment)
	var defensive_changed := _defensive_legendaries.update_equipped(effects)
	var caster_changed := _caster_legendaries.update_equipped(effects)
	if defensive_changed or caster_changed:
		active_statuses_changed.emit()
	var primary: Dictionary = equipment.get("main_hand", {})
	var offhand: Dictionary = equipment.get("off_hand", {})
	if primary.is_empty() and offhand.get("type", "") in WeaponRoles.ONE_HANDED_WEAPONS:
		primary = offhand
		offhand = {}
	weapon_type = String(primary.get("type", "unarmed"))
	_weapon_base_id = String(primary.get("base_id", ""))
	_offhand_type = String(offhand.get("type", ""))
	_offhand_base_id = String(offhand.get("base_id", ""))
	_dual_wield = WeaponRoles.can_dual_wield(weapon_type, _offhand_type)
	_shield_equipped = _offhand_type == "shield"
	_legendary_melee.configure(StringName(primary.get("effect", "")), StringName(offhand.get("effect", "")), _dual_wield)
	if is_instance_valid(_weapon):
		_cancel_strike("Equipment changed")
		_weapon.rebuild(weapon_type, String(primary.get("rarity", "normal")), _offhand_type,
			String(offhand.get("rarity", "normal")), _weapon_base_id, _offhand_base_id)
	vitals_changed.emit()


func set_character_progression(progression: Progression) -> void:
	character_progression = progression
	refresh_character_progression()


func refresh_character_progression(refill_gains := false) -> void:
	_refresh_effective_stats(refill_gains)
	vitals_changed.emit()


func _refresh_effective_stats(refill_gains: bool) -> void:
	var previous_max_life := float(stats.get("max_health", Items.BASE_STATS["max_health"]))
	var previous_max_mana := float(stats.get("max_mana", Items.BASE_STATS["max_mana"]))
	var previous_max_stamina := max_stamina()
	stats = Items.player_stats(_equipment, character_progression)
	if life > 0.0:
		var life_change := float(stats.max_health) - previous_max_life
		life = clampf(life + (life_change if refill_gains else minf(0.0, life_change)), 1.0, stats.max_health)
	if refill_gains:
		mana += maxf(0.0, float(stats.max_mana) - previous_max_mana)
		stamina += maxf(0.0, max_stamina() - previous_max_stamina)
	mana = minf(mana, stats.max_mana)
	ward = minf(ward, stats.ward)
	stamina = minf(stamina, max_stamina())


func restore_full() -> void:
	flush_combat_log()
	life = stats.max_health
	mana = stats.max_mana
	ward = stats.ward
	stamina = max_stamina()
	_stamina_recovery = 0.0
	_push_velocity = Vector3.ZERO
	_push_rearm = 0.0
	_dead = false
	_reset_combat_inputs("Combat reset")
	_legendary_melee.reset_sequences()
	if _caster_legendaries.reset():
		active_statuses_changed.emit()
	_clear_ailments()
	vitals_changed.emit()
	if _camera_feedback != null:
		_camera_feedback.reset_transients()


func place_at(point: Vector3, heading := 0.0, pitch := 0.0) -> void:
	flush_combat_log()
	global_position = point
	rotation.y = heading
	_neck.rotation.x = clampf(pitch, -1.45, 1.45)
	velocity = Vector3.ZERO
	_push_velocity = Vector3.ZERO
	_push_rearm = 0.0
	_attack_timer = 0.0
	_ability_runtime.clear()
	_reset_combat_inputs("Movement reset")
	_clear_ailments()
	_lamp.light_energy = 0.57 if combat_enabled else 0.25
	camera.clear_combat_shake()
	_weapon_sway.reset()
	reset_physics_interpolation()
	camera.sync_view_pose(false)


## Slowest baseline grounded WASD speed and its acceleration, for floor-warning timing.
func warning_walk_profile() -> Vector2:
	var backward := _combat_walk_factor(Vector2.DOWN)
	var backward_diagonal := _combat_walk_factor(Vector2.ONE.normalized())
	return Vector2(base_move_speed * minf(backward, backward_diagonal), GROUND_ACCELERATION)


func set_water_volume(volume: Node3D) -> void:
	_water_volume = volume
	if volume == null and is_instance_valid(_water_tint):
		_underwater_blend = 0.0
		_water_tint.hide()


func _in_water(point: Vector3) -> bool:
	return is_instance_valid(_water_volume) and _water_volume.contains(point)


func _swim(delta: float, steer: Vector2, immobilized: bool) -> void:
	var forward := -get_aim_transform().basis.z
	var direction := global_basis.x * steer.x - forward * steer.y
	if not immobilized and InputMap.has_action("jump") and Input.is_action_pressed("jump"):
		direction += Vector3.UP
	var desired := direction.limit_length() * (base_move_speed * WATER_SWIM_FACTOR)
	if desired.is_zero_approx():
		desired.y = -0.28
	velocity = velocity.move_toward(desired, delta * WATER_SWIM_ACCELERATION)
	if immobilized:
		velocity.x = 0.0
		velocity.z = 0.0
	_jump_buffer = 0.0
	_jump_grace = 0.0


func _update_underwater_view(delta: float) -> void:
	var target := 1.0 if _in_water(camera.global_position) else 0.0
	if _underwater_blend == target:
		return
	_underwater_blend = move_toward(_underwater_blend, target, delta * 5.0)
	_water_tint.visible = _underwater_blend > 0.0
	(_water_tint.material as ShaderMaterial).set_shader_parameter("immersion", _underwater_blend)


func _try_water_exit(planar: Vector3, starting_position: Vector3, delta: float) -> void:
	if not _in_water(global_position - Vector3.UP * 0.27):
		return
	var intended := Vector3(planar.x, 0.0, planar.z)
	if intended.length_squared() < 0.30:
		return
	var direction := intended.normalized()
	if (global_position - starting_position).dot(direction) > intended.length() * delta * 0.34:
		return
	var step := direction * 0.35
	var ahead := global_position + step
	var ray := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * 0.28, ahead - Vector3.UP * 0.13, 1)
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if floor_hit.is_empty() or floor_hit.normal.y < 0.71:
		return
	var rise := float(floor_hit.position.y) - global_position.y
	if rise < 0.035 or rise > 0.22:
		return
	var lift := Vector3.UP * (rise + 0.024)
	if test_move(global_transform, lift) or test_move(global_transform.translated(lift), step):
		return
	global_position += lift + step
	apply_floor_snap()
	reset_physics_interpolation()


func _combat_walk_factor(movement: Vector2) -> float:
	var backward := lerpf(1.0, COMBAT_BACKPEDAL_FACTOR, maxf(0.0, movement.y))
	var strafe := lerpf(1.0, COMBAT_STRAFE_FACTOR, absf(movement.x))
	return backward * strafe


func view_pitch() -> float:
	return _neck.rotation.x


func get_aim_transform() -> Transform3D:
	return camera.aim_transform()


func present_card_impact() -> void:
	if _camera_feedback != null:
		_camera_feedback.present_card_impact()


func look(event: InputEventMouseMotion) -> void:
	if gameplay_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var yaw := -event.relative.x * 0.0023
		var previous_pitch := _neck.rotation.x
		rotate_y(yaw)
		_neck.rotation.x = clampf(previous_pitch - event.relative.y * 0.0023, -1.45, 1.45)
		_weapon_sway.add_look_turn(Vector2(_neck.rotation.x - previous_pitch, yaw))
		camera.sync_view_pose(not Engine.is_in_physics_frame())


func _input(event: InputEvent) -> void:
	if not gameplay_enabled or _dead or is_stunned() or event is InputEventMouseMotion:
		return
	if InputMap.has_action("jump") and event.is_action_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_SECONDS
		return
	if not combat_enabled:
		return
	# Capture button edges even if a complete tap lands between two physics ticks.
	if event.is_action_pressed("block"):
		_set_guard_held(true)
	elif event.is_action_released("block"):
		_set_guard_held(false, true)
	elif event.is_action_pressed("attack"):
		_set_attack_pressed(true)
	elif event.is_action_released("attack"):
		_set_attack_pressed(false)


func _physics_process(delta: float) -> void:
	if not gameplay_enabled or _dead:
		return
	_legendary_melee.tick(delta)
	_caster_legendaries.advance(delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_chain_time_left = maxf(0.0, _chain_time_left - delta)
	_ability_runtime.advance(delta * ATTACK_TEMPO.capped_rate(_attack_speed_factor()))
	_attack_commit = maxf(0.0, _attack_commit - delta)
	if _strike_clip == null or _attack_timer <= 0.0:
		_light_buffer = maxf(0.0, _light_buffer - delta)
	_recovery_timer = maxf(0.0, _recovery_timer - delta)
	_soul_timer = maxf(0.0, _soul_timer - delta)
	_phase_timer = maxf(0.0, _phase_timer - delta)
	var rooted := is_cobweb_rooted()
	_tick_ailments(delta)
	if _dead:
		return
	var stunned := is_stunned()
	var movement := Vector2.ZERO if stunned else Input.get_vector("left", "right", "forward", "back")
	var direction := (transform.basis * Vector3(movement.x, 0.0, movement.y)).normalized()
	if combat_enabled and not stunned:
		_read_combat_buttons()
	_recharge_stamina(delta)
	if combat_enabled and not stunned:
		_advance_attack_input(delta)
	var speed := base_move_speed * (1.0 + float(stats.move_speed) * 0.01)
	speed *= _defensive_legendaries.movement_multiplier()
	var charged_move_limit := float(WeaponRoles.DIRECTIONAL_CHARGE_MOVE_FACTORS.get(weapon_type, 1.0))
	var directional_heavy := charged_move_limit < 1.0 and _strike_is_melee and _strike_heavy
	var charged_move_factor := _directional_charge_movement(charged_move_limit) if directional_heavy else 1.0
	var grounded := is_on_floor()
	if combat_enabled:
		speed *= _combat_walk_factor(movement)
		if _blocking:
			speed *= 0.64
		elif grounded and not _charging_attack and _strike_is_melee and _strike_clip != null \
				and _weapon.is_mace_attack(_strike_animation):
			speed *= _mace_swing_movement(charged_move_limit)
		elif directional_heavy:
			speed *= charged_move_factor
		elif _attack_commit > 0.0 and _strike_is_melee:
			var two_handed := weapon_type.ends_with("2h")
			if _strike_heavy:
				speed *= 0.40 if two_handed else 0.53
			else:
				speed *= 0.57 if two_handed else 0.82
		elif _attack_commit > 0.0:
			speed *= 0.46 if _strike_heavy else 0.69
	var chill := _active_effect("chilled") as ChillEffectDefinition
	if chill != null:
		speed *= chill.movement_speed_multiplier
	if _phase_timer > 0.0:
		speed *= 1.38
	var can_sprint := not combat_enabled or (movement.y < -0.45 and _attack_commit <= 0.0
		and charged_move_factor >= 1.0 and not _blocking)
	var swimming := _in_water(global_position + Vector3.UP * WATER_TORSO)
	var wading := not swimming and _in_water(global_position + Vector3.UP * 0.12)
	var sprinting := can_sprint and Input.is_action_pressed("sprint") and not _ailments.has("dread") and not wading
	if sprinting:
		speed *= 1.28
	elif wading:
		speed *= 0.76
	var planar := direction * speed - global_basis.z * _lunge_speed()
	if not stunned and InputMap.has_action("jump") and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_SECONDS
	if swimming:
		_swim(delta, Vector2.ZERO if rooted else movement, rooted or stunned)
	elif rooted or stunned:
		velocity.x = 0.0
		velocity.z = 0.0
		_jump_buffer = 0.0
		_jump_grace = 0.0
		if not grounded:
			velocity.y -= GRAVITY * delta
	else:
		var acceleration := GROUND_ACCELERATION if grounded else AIR_ACCELERATION
		velocity.x = move_toward(velocity.x, planar.x, delta * acceleration)
		velocity.z = move_toward(velocity.z, planar.z, delta * acceleration)
		_jump_grace = JUMP_GRACE_SECONDS if grounded else maxf(0.0, _jump_grace - delta)
		if _jump_grace > 0.0 and _jump_buffer > 0.0:
			velocity.y = jump_speed
			_jump_buffer = 0.0
			_jump_grace = 0.0
			feedback.emit("", "jump")
		elif not grounded:
			velocity.y -= GRAVITY * delta
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	var incoming_vertical := velocity.dot(up_direction)
	var locomotion_start := global_position
	_move_with_knockback(delta)
	if is_instance_valid(_water_volume) and not swimming and not rooted and not stunned:
		_try_water_exit(planar, locomotion_start, delta)
	camera.sync_view_pose(false)
	_update_underwater_view(delta)
	var stepped: bool = _weapon_sway.advance_after_movement(delta, movement if not rooted else Vector2.ZERO,
		incoming_vertical, sprinting, swimming)
	if not swimming and not grounded and is_on_floor() and incoming_vertical < -2.4:
		feedback.emit("", "land")
	elif stepped:
		feedback.emit("", "sprint" if sprinting else "walk")
	_advance_strike(delta)
	if _dead:
		return
	_update_weapon_pose()
	var life_regen := float(stats.life_regen) + (1.2 if not combat_enabled else 0.0)
	life = minf(stats.max_health, life + delta * life_regen)
	mana = minf(stats.max_mana, mana + delta * (float(stats.mana_regen) + (1.0 if not combat_enabled else 0.0)))
	if _recovery_timer <= 0.0:
		ward = minf(stats.ward, ward + delta * (1.0 + float(stats.ward) * 0.24))


func _move_with_knockback(delta: float) -> void:
	_push_rearm = maxf(0.0, _push_rearm - delta)
	if _push_velocity.is_zero_approx():
		move_and_slide()
		return
	var carry := _push_velocity
	velocity += carry
	move_and_slide()
	for index in get_slide_collision_count():
		var normal := get_slide_collision(index).get_normal()
		if absf(normal.y) < 0.5 and carry.dot(normal) < 0.0:
			carry = carry.slide(normal)
	carry.y = 0.0
	# Keep the post-collision walk velocity independent of the decaying push.
	velocity -= carry
	_push_velocity = carry.move_toward(Vector3.ZERO, IMPACT_FEEDBACK.player_push_deceleration * delta)


func _receive_knockback(speed: float, direction: Vector3) -> void:
	if speed <= 0.0 or _push_rearm > 0.0:
		return
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if not horizontal.is_finite() or horizontal.is_zero_approx():
		return
	_push_velocity = horizontal.normalized() * minf(speed, IMPACT_FEEDBACK.maximum_player_push_speed)
	_push_rearm = IMPACT_FEEDBACK.player_push_reuse


func _read_combat_buttons() -> void:
	# Polling also supports scripted input that sends no InputEvent.
	_set_guard_held(InputMap.has_action("block") and Input.is_action_pressed("block"), true)
	_set_attack_pressed(InputMap.has_action("attack") and Input.is_action_pressed("attack"))


func _set_attack_pressed(pressed: bool) -> void:
	if pressed == _attack_button_down:
		return
	_attack_button_down = pressed
	if pressed:
		if _blocking:
			_guard_attack = true
			_attack_intent = false
			_light_buffer = INPUT_BUFFER_SECONDS
			_update_blocking()
			return
		if _strike_clip != null and not _charging_attack and _is_mace_light():
			# Keep one fresh press through windup, contact, or recovery until the authored gate.
			_mace_followup_time = mace_followup_buffer_seconds
			_attack_intent = true
			_attack_hold_elapsed = 0.0
			return
		if not _can_buffer_attack():
			return
		_attack_intent = true
		_attack_hold_elapsed = 0.0
		return
	if _charging_attack:
		if attack_charge_fraction() >= _manual_charge_release_phase:
			_release_charged_attack_early()
		else:
			_release_charge_as_light()
	elif _mace_followup_time > 0.0:
		_mace_followup_tapped = true
	elif _attack_intent and _attack_hold_elapsed < tap_seconds and _can_buffer_attack():
		_light_buffer = INPUT_BUFFER_SECONDS
	_attack_intent = false


func _release_charge_as_light() -> void:
	var light := _weapon_attack_ability(false)
	var stage := _linked_charge_light_stage if _linked_charge_light_stage > 0 else _strike_chain_stage
	var shown_charge: float = _weapon.rendered_charge_fraction()
	var progress := shown_charge if shown_charge > 0.0 else attack_charge_fraction()
	var light_ready := _ability_runtime.can_start(light, mana)
	_attack_timer = 0.0
	_cancel_strike("Released before full charge", not light_ready)
	if light_ready:
		cast_ability(light, false, false, stage, progress)


func _release_charged_attack_early() -> void:
	var remaining_charge := maxf(_strike_remaining - _release_duration, 0.0)
	_attack_timer = maxf(_attack_timer - remaining_charge, 0.0)
	_attack_commit = maxf(_attack_commit - remaining_charge, 0.0)
	_strike_remaining = _release_duration
	# Finish the visual bridge before the first authored blade sample.
	var pretrace_seconds := _release_duration * _strike_clip.trace_start / maxf(_strike_clip.impact, 0.001)
	_begin_charged_release(minf(MANUAL_CHARGE_BLEND_SECONDS, pretrace_seconds * 0.90))


func _advance_attack_input(delta: float) -> void:
	if _attack_intent:
		_attack_hold_elapsed += delta
	if _guard_attack and not _strike_pending and _attack_timer <= 0.0 and _light_buffer <= 0.0:
		_guard_attack = false
		_update_blocking()
	if _blocking:
		return
	if _mace_followup_time > 0.0:
		_advance_mace_followup(delta)
		return
	if _light_buffer > 0.0 and cast_ability(_weapon_attack_ability(false), false, false, 0, 0.0, true):
		_light_buffer = 0.0
		return
	if _attack_timer > 0.0 or not _attack_intent or _attack_hold_elapsed < tap_seconds:
		return
	var charged := _weapon_attack_ability(true)
	if mana < charged.mana_cost:
		_attack_intent = false
		feedback.emit("Not enough mana", "error")
	elif cast_ability(charged, true, true):
		_attack_intent = false


func _advance_mace_followup(delta: float) -> void:
	if _can_link_mace_light() or _attack_timer <= 0.0:
		var charge := not _mace_followup_tapped
		if not charge or _attack_hold_elapsed >= tap_seconds:
			if cast_ability(_weapon_attack_ability(charge), charge, charge, 0, 0.0, true):
				_clear_mace_followup()
				return
	_mace_followup_time -= delta
	if _mace_followup_time <= 0.000001:
		_clear_mace_followup()


func _clear_mace_followup() -> void:
	_mace_followup_time = 0.0
	_mace_followup_tapped = false
	_attack_intent = false


func _can_buffer_attack() -> bool:
	if _strike_clip == null or _attack_timer <= 0.0:
		return true
	if _charging_attack:
		return false
	var earliest := _strike_clip.input_buffer
	if _is_mace_light():
		var buffer_span := mace_followup_buffer_seconds * _strike_clip.length / maxf(_clip_duration, 0.001)
		earliest = maxf(_strike_clip.trace_start, _mace_light_link_time() - buffer_span)
	return _current_clip_time() >= earliest


func _is_mace_light() -> bool:
	return not _strike_heavy and _weapon.is_mace_attack(_strike_animation)


func _mace_light_link_time() -> float:
	return maxf(_strike_clip.trace_end, _strike_clip.input_buffer)


func _can_link_mace_light() -> bool:
	return _strike_clip != null and _clip_released and not _strike_pending and _chain_time_left > 0.0 \
		and _is_mace_light() and _current_clip_time() >= _mace_light_link_time()


func _lunge_speed() -> float:
	if not _strike_pending or _charging_attack or _strike_clip == null:
		return 0.0
	if _strike_animation not in [&"dual_light_3", &"dual_heavy_3"]:
		return 0.0
	var progress := clampf(inverse_lerp(_strike_clip.trace_start * 0.58, _strike_clip.trace_end,
		_current_clip_time()), 0.0, 1.0)
	return sin(PI * progress) * (2.75 if _strike_heavy else 1.75)


func max_stamina() -> float:
	return maxf(STAMINA_RULES.minimum_to_guard, float(stats.get("max_stamina", Items.BASE_STATS["max_stamina"])))


func restore_stamina(amount: float) -> void:
	stamina = clampf(amount, 0.0, max_stamina())
	if stamina < STAMINA_RULES.minimum_to_guard:
		stamina = 0.0
		_stamina_recovery = STAMINA_RULES.broken_guard_delay
	else:
		_stamina_recovery = 0.0
	_update_blocking()


func is_blocking() -> bool:
	return _blocking


func guard_is_held() -> bool:
	return _guard_held


func attack_charge_fraction() -> float:
	if not _charging_attack:
		return 0.0
	return clampf(1.0 - (_strike_remaining - _release_duration) / _charge_duration, 0.01, 1.0)


func _directional_charge_movement(move_limit: float) -> float:
	if _charging_attack:
		var brace := smoothstep(0.0, 0.30, attack_charge_fraction())
		return lerpf(1.0, move_limit, brace)
	if _strike_clip == null:
		if _attack_commit > 0.0:
			return 0.40 if weapon_type.ends_with("2h") else 0.53
		return 1.0
	var clip_time := _current_clip_time()
	if clip_time <= _strike_clip.trace_end:
		return move_limit
	# Stay planted through the swept hit, then restore speed during the follow-through.
	var recovery_end := minf(_strike_clip.length,
		maxf(_strike_clip.input_buffer, _strike_clip.trace_end + 0.20))
	var unbrace := smoothstep(_strike_clip.trace_end, recovery_end, clip_time)
	return lerpf(move_limit, 1.0, unbrace)


func _mace_swing_movement(charge_move_limit: float) -> float:
	if not _strike_pending:
		return 1.0
	var time := _current_clip_time()
	if time >= _strike_clip.trace_end:
		return 1.0
	var drive_start := 0.0
	var drive_peak: float = _strike_clip.trace_start
	var brace_speed := charge_move_limit
	if not _strike_heavy:
		drive_start = _strike_clip.trace_start * 0.50
		drive_peak = lerpf(_strike_clip.trace_start, _strike_clip.impact, 0.40)
		brace_speed = 0.40
		if time < drive_start:
			return lerpf(1.0, brace_speed, smoothstep(0.0, drive_start, time))
	if time < drive_peak:
		return lerpf(brace_speed, mace_surge_speed_multiplier, smoothstep(drive_start, drive_peak, time))
	if time <= _strike_clip.impact:
		return mace_surge_speed_multiplier
	return lerpf(mace_surge_speed_multiplier, 1.0, smoothstep(_strike_clip.impact, _strike_clip.trace_end, time))


func _set_guard_held(held: bool, manual := false) -> void:
	if _guard_held != held:
		_guard_held = held
		if held:
			_guard_attack = false
		_update_blocking()
		if not held and _defensive_legendaries.has_counterweight():
			var refund := _defensive_legendaries.release_counterweight(manual, effects.has(DefensiveLegendaries.COUNTERWEIGHT))
			if refund > 0.0:
				stamina = minf(max_stamina(), stamina + refund)
				vitals_changed.emit()
				feedback.emit("", "block")
				var shield_point := get_aim_transform() * Vector3(-0.24, -0.21, -0.88)
				CombatImpact.world(self, shield_point, -global_basis.z, &"metal")
			active_statuses_changed.emit()


func _update_blocking() -> void:
	var minimum: float = STAMINA_RULES.minimum_to_guard
	var active := _guard_held and not _guard_attack and stamina >= minimum \
		and gameplay_enabled and combat_enabled and not _dead and not is_stunned()
	if _blocking == active:
		return
	if not active and gameplay_enabled and combat_enabled and stamina >= minimum and stamina < max_stamina():
		_stamina_recovery = maxf(_stamina_recovery, STAMINA_RULES.guard_release_delay)
	_blocking = active
	if _blocking:
		if _mace_followup_time > 0.0:
			_clear_mace_followup()
		# A block takes precedence over a prepared attack.
		if _strike_pending and not _strike_is_follow_up and not _clip_released:
			_attack_timer = 0.0
		_cancel_strike("Guard raised")
	_update_weapon_pose()
	vitals_changed.emit()


func _recharge_stamina(delta: float) -> void:
	var waiting := minf(delta, _stamina_recovery)
	_stamina_recovery -= waiting
	if _blocking or stamina >= max_stamina() or waiting >= delta:
		return
	stamina = move_toward(stamina, max_stamina(), (delta - waiting) * _stamina_recharge_per_second())
	_update_blocking()


func _stamina_recharge_per_second() -> float:
	return STAMINA_RULES.recharge_per_second(max_stamina(), float(Items.BASE_STATS["max_stamina"]))


func _try_block_hit(amount: float, damage_type: String, source: Node3D, ability: Dictionary) -> bool:
	if not _blocking or amount <= 0.0 or bool(ability.get("unblockable", false)):
		return false
	var previous := stamina
	var cost := (STAMINA_RULES.base_block_cost + amount * STAMINA_RULES.damage_cost_factor) \
		* (STAMINA_RULES.shield_cost_multiplier if _shield_equipped else 1.0)
	stamina = maxf(0.0, stamina - cost)
	var exhausted := stamina < STAMINA_RULES.minimum_to_guard
	if exhausted:
		stamina = 0.0
	_stamina_recovery = STAMINA_RULES.broken_guard_delay if exhausted else STAMINA_RULES.hit_recharge_delay
	_update_blocking()
	if is_instance_valid(_weapon):
		# The last absorbed hit has already lowered guard and needs its own recovery.
		_weapon.react_to_guard_hit(exhausted)
	var context := _incoming_ability(ability, source, damage_type)
	_log_status(context, "%s · %.1f Stamina" % ["Guard Broken" if exhausted else "Blocked", previous - stamina])
	feedback.emit("Guard broken" if exhausted else "", "block")
	if _camera_feedback != null:
		var source_point := source.global_position if is_instance_valid(source) else Vector3.INF
		_camera_feedback.present_guard_impact(source_point, (previous - stamina) / max_stamina(), exhausted)
	if _shield_equipped and is_instance_valid(source):
		var point := get_aim_transform() * Vector3(-0.24, -0.21, -0.88)
		var outward := point.direction_to(source.global_position + Vector3.UP * 1.15)
		CombatImpact.world(self, point, outward, &"metal")
	if not exhausted:
		vitals_changed.emit()
	var melee := false
	if effects.has(DefensiveLegendaries.BUTTRESS):
		var definition := ability.get("definition") as AbilityDefinition
		melee = bool(ability.get("melee", definition != null and definition.runtime_profile().get("shape", "") == "arc"))
	if _defensive_legendaries.on_block(effects, stamina / max_stamina(), exhausted, melee):
		active_statuses_changed.emit()
	if effects.has("frostguard") and is_instance_valid(source) and source.has_method("apply_status"):
		source.apply_status("chilled", 3.0, 0.26, self)
	return true


func _update_weapon_pose() -> void:
	if is_instance_valid(_weapon) and _weapon.has_method("set_combat_pose"):
		_weapon.set_combat_pose(is_blocking(), attack_charge_fraction(), _strike_chain_stage, _strike_animation)


func _ignore_held_attack() -> void:
	_attack_button_down = InputMap.has_action("attack") and Input.is_action_pressed("attack")


func _reset_combat_inputs(reason: String) -> void:
	if _strike_pending and not _strike_is_follow_up:
		_attack_timer = 0.0
	_cancel_strike(reason)
	_guard_attack = false
	_set_guard_held(false)
	_jump_buffer = 0.0
	_ignore_held_attack()


func attack(heavy: bool) -> void:
	cast_ability(_weapon_attack_ability(heavy), heavy)


func weapon_audio_type() -> String:
	return _offhand_type if _strike_hand == WeaponRoles.OFF_HAND else weapon_type


func weapon_audio_heft() -> float:
	return _weapon.strike_heft(_strike_heavy, _strike_hand == WeaponRoles.OFF_HAND) if _strike_is_melee else -1.0


func cast_ability(ability: AbilityDefinition, heavy := false, charged_input := false,
		light_release_stage := 0, charge_progress := 0.0, buffered_followup := false) -> bool:
	# At an end-of-clip gate the outgoing clip is still live until _advance_strike runs this tick.
	var linked := buffered_followup and _can_link_mace_light()
	if (_attack_timer > 0.0 and not linked) or _strike_pending \
			or _blocking or not combat_enabled or _dead or is_stunned():
		return false
	if not _ability_runtime.can_start(ability, mana):
		return false
	var weapon_ability := _is_weapon_ability(ability)
	var profile := ability.runtime_profile()
	if not weapon_ability and profile.get("shape", "") not in ["arc", "disc"]:
		return false
	_linked_charge_light_stage = _next_chain_stage if linked and charged_input else 0
	_strike_clip = null
	_strike_animation = &""
	_manual_charge_release_phase = INF
	_strike_chain_stage = _next_chain_stage if weapon_ability and _chain_time_left > 0.0 else 1
	if weapon_ability and light_release_stage > 0:
		_strike_chain_stage = light_release_stage
	var enrage := _attack_speed_factor()
	_strike_tempo = ATTACK_TEMPO.weapon_rate(float(stats.attack_speed), _soul_timer > 0.0, enrage) \
		if weapon_ability else ATTACK_TEMPO.capped_rate(enrage)
	_strike_remaining = ability.windup / _strike_tempo
	_attack_timer = (ability.windup + ability.recovery) / _strike_tempo
	var animation_heavy := heavy
	var authored_charge := 0.0
	_strike_is_melee = ability.action_key == "weapon_melee"
	var two_handed_melee := _strike_is_melee and weapon_type.ends_with("2h")
	if charged_input and _strike_is_melee and not _dual_wield and WeaponRoles.DIRECTIONAL_CHARGE_MOVE_FACTORS.has(weapon_type):
		# Load against the strafe direction so the blow travels with it. Keep that side through release.
		var lateral := Input.get_axis("left", "right")
		if not is_zero_approx(lateral):
			_strike_chain_stage = 2 if lateral < 0.0 else 1
	if weapon_ability:
		animation_heavy = bool(profile.get("heavy", false))
		_attack_timer = maxf(0.18, float(INTERVALS.get(weapon_type, 0.52)) / _strike_tempo)
		if animation_heavy:
			_attack_timer *= 1.19
		var windup_share := 0.39 if two_handed_melee else 0.32
		_strike_remaining = _attack_timer * (0.47 if animation_heavy else windup_share)
		if _strike_is_melee and weapon_type == "mace_2h":
			if animation_heavy:
				# A downstroke queued by the light chain still gives a neutral heavy its side.
				match _strike_chain_stage:
					MaceStage.DOWN_LEFT:
						_strike_chain_stage = MaceStage.LEFT
					MaceStage.DOWN_RIGHT:
						_strike_chain_stage = MaceStage.RIGHT
			elif light_release_stage == 0 and _chain_time_left <= 0.0:
				_strike_chain_stage = MACE_LIGHT_CHAIN[0]
		_strike_animation = _weapon.attack_clip_name(animation_heavy, _strike_chain_stage)
		_strike_clip = AttackAnimation.read(_weapon.attack_animation(animation_heavy, _strike_chain_stage, _strike_animation))
		if _strike_clip != null:
			var timing_type := _offhand_type if _dual_wield and _strike_chain_stage == 2 else weapon_type
			var timing_scale := WeaponRoles.commitment_timing(timing_type, animation_heavy)
			_attack_timer = maxf(0.18, _strike_clip.length * timing_scale / _strike_tempo)
			_strike_remaining = _attack_timer * _strike_clip.impact / _strike_clip.length
			if charged_input:
				var charge_clip: Animation = _weapon.charge_animation(_strike_chain_stage, _strike_animation)
				authored_charge = charge_clip.length / _strike_tempo
				_manual_charge_release_phase = _weapon.manual_charge_release_phase(charge_clip, _strike_animation)
	_charging_attack = charged_input
	if _charging_attack:
		var recovery := _attack_timer - _strike_remaining
		if _strike_clip != null:
			_charge_duration = maxf(charge_seconds, authored_charge)
			_release_duration = maxf(0.001, _strike_remaining)
		else:
			_charge_duration = maxf(charge_seconds, _strike_remaining)
			_release_duration = CHARGED_RELEASE_SECONDS
			if _strike_is_melee:
				_release_duration = TWO_HANDED_RELEASE_SECONDS if two_handed_melee else MELEE_RELEASE_SECONDS
			_release_duration /= _strike_tempo
		_strike_remaining = _charge_duration + _release_duration
		_attack_timer = _strike_remaining + recovery
	_strike_pending = true
	_strike_heavy = animation_heavy
	_strike_ability = ability
	_strike_hand = WeaponRoles.MAIN_HAND
	if _dual_wield and _strike_is_melee:
		if _strike_chain_stage == 2:
			_strike_hand = WeaponRoles.OFF_HAND
		elif _strike_chain_stage == 3 and _strike_heavy:
			_strike_hand = WeaponRoles.BOTH_HANDS
	_weapon_card_landed = false
	_clip_released = false
	_clip_outcome.clear()
	_clip_last_blade.clear()
	_paired_last_blade.clear()
	var commitment := 0.76 if animation_heavy else 0.58
	if two_handed_melee:
		commitment += 0.15
	_attack_commit = _attack_timer * commitment
	if not _charging_attack:
		_prepare_melee_sweep()
		var clip_duration := _attack_timer
		var entry_blend := 0.0
		var combo_entry := 0.0
		if _strike_clip != null and linked:
			# Skip the incoming ready keys visually without skipping time on the attack clock.
			combo_entry = _strike_clip.combo_entry
			var pretrace_seconds := clip_duration * _strike_clip.trace_start / _strike_clip.length
			entry_blend = minf(MACE_LIGHT_CHAIN_BLEND_SECONDS, pretrace_seconds * 0.90)
		elif _strike_clip != null and light_release_stage > 0:
			var light_entry := _strike_clip.trace_start * 0.85 * charge_progress
			var elapsed := clip_duration * light_entry / _strike_clip.length
			_attack_timer -= elapsed
			_strike_remaining -= elapsed
			_attack_commit = maxf(0.0, _attack_commit - elapsed)
			if _weapon.is_mace_attack(_strike_animation):
				var pretrace_seconds := clip_duration * (_strike_clip.trace_start - light_entry) / _strike_clip.length
				entry_blend = minf(MANUAL_CHARGE_BLEND_SECONDS, pretrace_seconds * 0.90)
		_play_strike_animation(clip_duration, false, -1.0, light_release_stage > 0 and entry_blend <= 0.0,
			entry_blend, combo_entry)
	_log_player_cast(&"cast_start", ability.combat_details())
	if _strike_clip == null and _strike_remaining <= 0.0:
		_commit_strike()
	return true


func _advance_strike(attack_delta: float) -> void:
	if _strike_pending:
		_strike_remaining -= attack_delta
		if _charging_attack and _strike_remaining <= _release_duration:
			_begin_charged_release()
	if _strike_clip != null and not _charging_attack:
		_advance_driven_strike()
		return
	if not _strike_pending or _charging_attack:
		return
	if _strike_sweep != null:
		_strike_sweep.sample(get_world_3d().direct_space_state, get_aim_transform(), _strike_remaining)
	if _strike_remaining <= 0.0:
		_commit_strike()


func _begin_charged_release(charge_blend := 0.0) -> void:
	_charging_attack = false
	_prepare_melee_sweep()
	_play_strike_animation(_attack_timer, true, -1.0, false, charge_blend)


func _current_clip_time() -> float:
	if _clip_duration <= 0.0:
		return 0.0
	return _strike_clip.at_elapsed(_clip_duration - _attack_timer, _clip_duration,
		_clip_release_start, _clip_release_impact)


func _mace_light_pose_time(time: float) -> float:
	if not _is_mace_light():
		return time
	var trace_start := _strike_clip.trace_start
	if time < trace_start and _clip_combo_entry > 0.0:
		return lerpf(_clip_combo_entry, trace_start, time / trace_start)
	var trace_end := _strike_clip.trace_end
	var link := _mace_light_link_time()
	var exit := _strike_clip.combo_exit
	if time <= trace_end or exit >= link or time >= _strike_clip.length:
		return time
	if time <= link:
		return lerpf(trace_end, exit, inverse_lerp(trace_end, link, time))
	return lerpf(exit, _strike_clip.length, inverse_lerp(link, _strike_clip.length, time))


func _advance_driven_strike() -> void:
	var time := _current_clip_time()
	var pose_time := _mace_light_pose_time(time)
	if not _strike_pending:
		_weapon.set_swing_phase(pose_time / _strike_clip.length)
		if _attack_timer <= 0.0:
			_strike_clip = null
		return
	var release_marker := _strike_clip.trace_start if _strike_is_melee else _strike_clip.impact
	if not _clip_released and time >= release_marker:
		if not _release_driven_strike():
			return
	if _clip_released and _strike_is_melee and _clip_pose_time <= _strike_clip.trace_end:
		_sample_driven_strike(clampf(_clip_pose_time, _strike_clip.trace_start, _strike_clip.trace_end),
			minf(time, _strike_clip.trace_end), time >= _strike_clip.trace_end)
		if _dead or not _strike_pending:
			return
	_clip_pose_time = time
	_weapon.set_swing_phase(pose_time / _strike_clip.length)
	if _clip_released and time >= (_strike_clip.trace_end if _strike_is_melee else release_marker):
		_finish_driven_strike()


func _release_driven_strike() -> bool:
	var cooldown := Items.attack_interval(_strike_ability.cooldown, stats.cooldown_recovery)
	if not _strike_is_follow_up and not _ability_runtime.try_commit(
			_strike_ability, mana, _spend_ability_mana.bind(_strike_ability), cooldown):
		_cancel_strike("Ability became unavailable")
		return false
	_clip_released = true
	var details := _strike_ability.combat_details()
	if not _strike_is_follow_up:
		_advance_weapon_chain(cooldown)
		_log_player_cast(&"cast_end", details)
	if _strike_is_melee:
		feedback.emit("", "swing")
		_clip_outcome = {"ability": details, "count": 0, "broken_prop": Vector3.INF,
			"critical": false, "damage_factor": 1.0}
	else:
		_resolve_attack(_strike_heavy, details)
	return true


func _sample_driven_strike(from: float, to: float, closes_window: bool) -> void:
	var view := get_aim_transform()
	var offhand := _strike_hand == WeaponRoles.OFF_HAND
	var contacts: Array[Dictionary] = []
	_clip_last_blade = _trace_strike(_strike_sweep, _clip_last_blade, view, from, to, offhand, contacts)
	if _paired_sweep != null:
		_paired_last_blade = _trace_strike(_paired_sweep, _paired_last_blade, view, from, to, true, contacts)
	_clip_last_aim = view
	for contact in _contact_session.take_contacts(view, contacts, closes_window, _contact_cleave.can_fit_saved_actor):
		var stop := _apply_melee_contact(contact, from, to)
		if _dead or not _strike_pending:
			return
		if stop != &"":
			_stop_driven_melee(contact, stop, view, from, to)
			return


func _trace_strike(sweep: MeleeSweep, previous: PackedVector3Array, view: Transform3D,
		from: float, to: float, offhand: bool, contacts: Array[Dictionary]) -> PackedVector3Array:
	var space := get_world_3d().direct_space_state
	var hand := WeaponRoles.OFF_HAND if offhand else WeaponRoles.MAIN_HAND
	if not _weapon.has_trace_sockets(offhand):
		var window := _strike_clip.trace_end - _strike_clip.trace_start
		sweep.sample_fraction(space, view, 1.0 if is_zero_approx(window) else (to - _strike_clip.trace_start) / window)
		_append_melee_contacts(contacts, sweep, hand, 0.0, 1.0)
		var terrain := sweep.terrain_contact()
		if not terrain.is_empty():
			terrain.merge({"kind": &"terrain", "weapon_hand": hand, "direction": -view.basis.z,
				"fraction": 1.0, "can_stop": true}, true)
			contacts.append(terrain)
		return previous

	var normalized := _dual_wield
	var divisor := _strike_clip.length if normalized else 1.0
	var old_view := view if previous.is_empty() else _clip_last_aim
	var type := _offhand_type if offhand else weapon_type
	var head_stop := type == "mace_2h" and melee_stops_on_static_world
	var profile: Dictionary = MELEE_CONTACT.sweep_profile(type, _strike_heavy)
	profile.horizontal_half_angle = MELEE_CONTACT.horizontal_half_angle
	profile.vertical_half_angle = MELEE_CONTACT.vertical_half_angle
	profile.mace_head_stop = head_stop
	if melee_uses_refuge_sweep:
		profile.reach_scale = MELEE_CONTACT.inn_reach_scale
		profile.width_scale = MELEE_CONTACT.inn_width_scale
	if previous.is_empty():
		previous = _weapon.sample_blade(_strike_animation, from / divisor, old_view, offhand, normalized, true)
	# Sample the actual clip between physics frames when a fast swing advances several authored frames.
	var divisions := maxi(1, ceili((to - from) * 60.0 - 0.0001))
	for step in divisions:
		var begin := float(step) / divisions
		var end := float(step + 1) / divisions
		var aim_before := old_view.interpolate_with(view, begin)
		var aim_after := old_view.interpolate_with(view, end)
		var time_before := lerpf(from, to, begin)
		var time_after := lerpf(from, to, end)
		var current: PackedVector3Array = _weapon.sample_blade(
			_strike_animation, time_after / divisor, aim_after, offhand, normalized, true)
		profile.previous_basis = _melee_box_basis(previous, aim_before)
		profile.current_basis = _melee_box_basis(current, aim_after)
		if head_stop:
			profile.previous_head = previous.slice(2, 4)
			profile.current_head = current.slice(2, 4)
			profile.terrain_fraction = _melee_marker_fraction(_strike_clip.terrain_start, time_before, time_after)
			profile.terrain_impact_fraction = _melee_marker_fraction(_strike_clip.impact, time_before, time_after) \
				if _strike_heavy else 0.0
		sweep.trace_contact_sweep(space, aim_before, aim_after, previous, current, profile)
		_append_melee_contacts(contacts, sweep, hand, begin, end)
		previous = current
	return previous


func _melee_box_basis(sample: PackedVector3Array, aim: Transform3D) -> Basis:
	var axis := sample[0].direction_to(sample[1])
	var up := sample[4]
	if absf(up.dot(axis)) > 0.96:
		up = aim.basis.y if absf(aim.basis.y.dot(axis)) < 0.96 else aim.basis.x
	return Basis.looking_at(axis, up)


func _melee_marker_fraction(marker: float, from: float, to: float) -> float:
	return 0.0 if marker <= from else ((marker - from) / (to - from) if to > from else INF)


func _append_melee_contacts(contacts: Array[Dictionary], sweep: MeleeSweep, hand: StringName,
		begin: float, end: float) -> void:
	for contact in sweep.take_terrain_contacts():
		contact.kind = &"terrain"
		contact.weapon_hand = hand
		contact.fraction = lerpf(begin, end, float(contact.fraction))
		contacts.append(contact)
	for contact in sweep.take_contacts():
		contact.kind = &"prop" if contact.target is BreakableProp else &"actor"
		contact.weapon_hand = hand
		contact.fraction = lerpf(begin, end, float(contact.fraction))
		contacts.append(contact)


func _apply_melee_contact(contact: Dictionary, from: float, to: float) -> StringName:
	var paired_offhand: bool = _paired_contact_cleave != null and contact.weapon_hand == WeaponRoles.OFF_HAND
	var cleave := _paired_contact_cleave if paired_offhand else _contact_cleave
	match StringName(contact.kind):
		&"terrain":
			var surface := _melee_surface(contact)
			var stops := melee_stops_on_static_world and bool(contact.get("can_stop", false))
			if (not melee_stops_on_static_world or stops) and not bool(_clip_outcome.get("world_contact", false)):
				_clip_outcome.world_contact = true
				CombatImpact.world(self, contact.point, contact.normal, surface)
			return surface if stops else &""
		&"prop":
			var prop := contact.target as BreakableProp
			if not is_instance_valid(prop) or prop.is_queued_for_deletion() or not prop.allow_melee_damage:
				return &""
			prop.break_from(contact.direction, contact.point, contact.normal)
			var result := cleave.resolve_prop(prop.melee_contact_mass, not prop.melee_hit_through)
			if result.get("stops_weapon", false):
				return &"breakable"
			if _strike_heavy and not bool(_clip_outcome.get("camera_kicked", false)):
				_present_melee_contact_shake(contact, &"breakable", false)
				_clip_outcome.camera_kicked = true
		&"actor":
			var result := cleave.resolve_actor(contact.target, contact)
			if result.is_empty():
				return &""
			contact.merge(result, true)
			contact.phase = lerpf(from, to, float(contact.fraction)) / _strike_clip.length
			_resolve_attack(_strike_heavy, _clip_outcome.ability, null, [contact], _clip_outcome)
			if contact.stop_kind in [&"armor", &"guard"]:
				CombatImpact.world(self, contact.point, contact.normal, &"metal")
			return contact.stop_kind
	return &""


func _stop_driven_melee(contact: Dictionary, kind: StringName, view: Transform3D,
		from: float, to: float) -> void:
	var at := lerpf(from, to, float(contact.fraction))
	var phase := at / _strike_clip.length
	if weapon_type == "mace_2h":
		var recovery := 0.0
		if _is_mace_light():
			var remaining := maxf(0.0, _mace_light_link_time() - at)
			recovery = remaining * _clip_duration / _strike_clip.length + 0.10
		var point: Vector3 = contact.point if contact.kind == &"terrain" else Vector3.INF
		_weapon.start_mace_rebound(phase, view.basis.inverse() * contact.direction, kind,
			recovery, contact.normal, point)
	else:
		_weapon.stop_driven_swing(phase)
	_present_melee_contact_shake(contact, kind, true)
	_finish_driven_strike(true)


func _present_melee_contact_shake(contact: Dictionary, kind: StringName, stopped: bool) -> void:
	if _camera_feedback == null:
		return
	var offhand: bool = contact.weapon_hand == WeaponRoles.OFF_HAND
	var type := _offhand_type if offhand else weapon_type
	_camera_feedback.present_melee_contact(contact.point, contact.direction, contact.normal, type,
		kind, _strike_heavy, _hit_shake_swing(offhand), stopped)


func _finish_driven_strike(stopped := false) -> void:
	var ability := _strike_ability
	var delay := -1.0 if stopped or _strike_is_follow_up else ability.roll_follow_up_delay(_rng) / _strike_tempo
	_strike_pending = false
	_strike_is_follow_up = false
	_strike_ability = null
	_strike_sweep = null
	_paired_sweep = null
	_contact_session = null
	_contact_cleave = null
	_paired_contact_cleave = null
	if delay >= 0.0:
		_attack_timer = delay + ability.recovery / _strike_tempo
		_strike_remaining = delay
		_attack_commit = maxf(_attack_commit, delay)
		_strike_pending = true
		_strike_is_follow_up = true
		_strike_ability = ability
		_clip_released = false
		_clip_outcome.clear()
		_clip_last_blade.clear()
		_paired_last_blade.clear()
		_prepare_melee_sweep()
		_play_strike_animation(_attack_timer, true, delay)


func _commit_strike() -> void:
	var ability := _strike_ability
	var follow_up := _strike_is_follow_up
	var sweep := _strike_sweep
	if not follow_up:
		var cooldown := Items.attack_interval(ability.cooldown, stats.cooldown_recovery)
		if not _ability_runtime.try_commit(ability, mana, _spend_ability_mana.bind(ability), cooldown):
			_cancel_strike("Ability became unavailable")
			return
		_advance_weapon_chain(cooldown)
	_strike_pending = false
	_strike_is_follow_up = false
	_strike_ability = null
	_strike_sweep = null
	_paired_sweep = null
	var details := ability.combat_details()
	if not follow_up:
		_log_player_cast(&"cast_end", details)
		var delay := ability.roll_follow_up_delay(_rng) / _strike_tempo
		if delay >= 0.0:
			_strike_pending = true
			_strike_is_follow_up = true
			_strike_ability = ability
			_strike_remaining = delay
			_attack_timer = delay + ability.recovery / _strike_tempo
			_attack_commit = maxf(_attack_commit, delay)
			_prepare_melee_sweep()
			_play_strike_animation(_attack_timer)
	_resolve_attack(_strike_heavy, details, sweep)


func _prepare_melee_sweep() -> void:
	if _strike_ability.action_key == "weapon_melee":
		var aim := get_aim_transform()
		var type := _offhand_type if _strike_hand == WeaponRoles.OFF_HAND else weapon_type
		_strike_sweep = MeleeSweep.new(type, _strike_heavy, get_rid(), aim)
		_strike_sweep.debug_volume = weapon_trace
		if _strike_clip != null:
			var precision := type == "mace_2h" and _strike_animation in [&"light_down_left", &"light_down_right"]
			_contact_session = MeleeContactSession.new(precision, MELEE_CONTACT.precision_reach, MELEE_CONTACT.precision_dot)
			_contact_session.begin(get_world_3d().direct_space_state, aim, get_rid())
			_contact_cleave = _melee_cleave_for_hand(type, _strike_hand == WeaponRoles.OFF_HAND)
		if _strike_hand == WeaponRoles.BOTH_HANDS:
			_paired_sweep = MeleeSweep.new(_offhand_type, _strike_heavy, get_rid(), aim)
			_paired_sweep.debug_volume = weapon_trace
			if _strike_clip != null:
				_paired_contact_cleave = _melee_cleave_for_hand(_offhand_type, true)


func _melee_cleave_for_hand(type: String, offhand: bool) -> MeleeContactRules:
	var hand := WeaponRoles.OFF_HAND if offhand else WeaponRoles.MAIN_HAND
	var item: Dictionary = _equipment.get(hand, {})
	var base_id := _offhand_base_id if offhand else _weapon_base_id
	var attribute := StringName(_strike_ability.scaling_attribute)
	if attribute == &"default":
		attribute = WeaponRoles.scaling_attribute(type, base_id)
	var gear_power := ItemBases.power_at_item_level(int(item.get("item_level", 1))).x
	var power := gear_power * character_progression.base_damage_multiplier(attribute)
	return MeleeContactRules.new(type, _strike_heavy, power, MELEE_CONTACT.cleave_profile(type, _strike_heavy))


func _advance_weapon_chain(cooldown: float) -> void:
	if _strike_animation.is_empty():
		return
	var mace_attack: bool = _weapon.is_mace_attack(_strike_animation)
	if mace_attack and not _strike_heavy:
		var index := MACE_LIGHT_CHAIN.find(_strike_chain_stage)
		_next_chain_stage = MACE_LIGHT_CHAIN[(index + 1) % MACE_LIGHT_CHAIN.size()]
	else:
		var three_step := _dual_wield or WeaponRoles.DIRECTIONAL_CHARGE_MOVE_FACTORS.has(weapon_type)
		var stage_count := 3 if three_step and not mace_attack else 2
		_next_chain_stage = 1 if _strike_chain_stage >= stage_count else _strike_chain_stage + 1
	# Recovery and ability cooldown must both leave time to start the next strike.
	_chain_time_left = maxf(_attack_timer, cooldown) + ATTACK_CHAIN_GRACE_SECONDS


func _play_strike_animation(duration: float, release := false, impact_override := -1.0, immediate := false,
		charge_blend := 0.0, combo_entry := 0.0) -> void:
	_clip_combo_entry = combo_entry
	if _strike_clip != null:
		_clip_duration = maxf(0.001, duration)
		_clip_release_start = 0.0
		_clip_release_impact = 0.0
		if release:
			if impact_override >= 0.0:
				_clip_release_start = maxf(0.0, _strike_clip.trace_start - _strike_clip.length * 0.12)
			var release_time := impact_override if impact_override >= 0.0 else _strike_remaining
			_clip_release_impact = maxf(0.001, release_time)
		var use_current_time := immediate or (not release and charge_blend > 0.0)
		_clip_pose_time = _current_clip_time() if use_current_time else _clip_release_start
		var pose_time := _mace_light_pose_time(_clip_pose_time)
		_weapon.start_driven_swing(_strike_animation, _strike_heavy, pose_time / _strike_clip.length, immediate,
			charge_blend)
		return
	var contact := maxf(0.0, _strike_remaining)
	# Allow the weapon to reach the contact pose even when a move has no recovery.
	_weapon.swing(_strike_heavy, maxf(0.18, maxf(duration, contact * 1.5)), contact, _strike_animation, immediate)


func _spend_ability_mana(amount: float, ability: AbilityDefinition) -> void:
	mana -= amount
	if ability.action_key == "weapon_staff" and weapon_type == "staff" \
			and _caster_legendaries.record_staff_spend(amount):
		active_statuses_changed.emit()
	vitals_changed.emit()


func _cancel_strike(reason := "Interrupted", recover_charge := false) -> void:
	var pending_ability := _strike_ability if _strike_pending and not _strike_is_follow_up and not _clip_released else null
	if _strike_is_follow_up:
		_attack_timer = minf(_attack_timer, _strike_ability.recovery / _strike_tempo)
	_strike_pending = false
	_strike_is_follow_up = false
	_strike_ability = null
	_strike_sweep = null
	_paired_sweep = null
	_contact_session = null
	_contact_cleave = null
	_paired_contact_cleave = null
	_strike_clip = null
	_strike_animation = &""
	_strike_chain_stage = 1
	_next_chain_stage = 1
	_chain_time_left = 0.0
	_clip_released = false
	_clip_outcome.clear()
	_clip_last_blade.clear()
	_paired_last_blade.clear()
	_strike_remaining = 0.0
	_light_buffer = 0.0
	_clear_mace_followup()
	_linked_charge_light_stage = 0
	_charging_attack = false
	_charge_duration = 0.0
	_manual_charge_release_phase = INF
	_attack_commit = 0.0
	if is_instance_valid(_weapon):
		_weapon.cancel_swing(recover_charge)
	if pending_ability != null:
		_log_player_cast(&"cast_cancel", pending_ability.combat_details(), reason)


func _weapon_attack_ability(heavy: bool) -> AbilityDefinition:
	var override := heavy_ability_override if heavy else light_ability_override
	if override != null:
		return override
	if weapon_type == "staff":
		return STAFF_HEAVY if heavy else STAFF_ATTACK
	return MELEE_HEAVY if heavy else MELEE_ATTACK


func _is_weapon_ability(ability: AbilityDefinition) -> bool:
	return ability.action_key in ["weapon_melee", "weapon_staff"]


func _resolve_attack(heavy: bool, ability: Dictionary = {}, sweep: MeleeSweep = null,
		streamed_targets: Array[Dictionary] = [], strike_outcome: Dictionary = {}) -> void:
	var definition := ability.get("definition") as AbilityDefinition
	if definition == null:
		definition = _weapon_attack_ability(heavy)
		if ability.is_empty():
			ability = definition.combat_details()
	var weapon_ability := _is_weapon_ability(definition)
	var profile := definition.runtime_profile()
	var is_staff := definition.action_key == "weapon_staff"
	var is_melee := definition.action_key == "weapon_melee"
	heavy = weapon_ability and bool(profile.get("heavy", false))
	var attribute := StringName(definition.scaling_attribute)
	if attribute == &"default" and weapon_ability:
		attribute = WeaponRoles.scaling_attribute(weapon_type, _weapon_base_id)
	var attribute_damage := character_progression.base_damage_multiplier(attribute)
	var streamed := not strike_outcome.is_empty()
	var targets: Array[Dictionary] = []
	if streamed:
		targets = streamed_targets
	elif is_staff:
		feedback.emit("", "spell_cast")
		targets = _staff_targets(heavy)
	elif weapon_ability:
		feedback.emit("", "swing")
		targets = _melee_targets(heavy, sweep)
	else:
		feedback.emit("", "spell_cast")
		for enemy in _authored_targets(profile):
			var point: Vector3 = enemy.aim_point()
			targets.append({"target": enemy, "point": point, "direction": camera.global_position.direction_to(point)})
	if targets.is_empty():
		return
	var earlier_contacts := int(strike_outcome.get("count", 0))
	var critical := bool(strike_outcome.get("critical", false))
	var crit_roll := float(strike_outcome.get("critical_roll", 100.0))
	var damage_factor := float(strike_outcome.get("damage_factor", 1.0))
	if earlier_contacts == 0:
		_storm_hits += 1
		var crit_chance := float(stats.crit_chance) + character_progression.critical_chance_bonus(attribute)
		crit_roll = _rng.randf() * 100.0
		critical = crit_roll < clampf(crit_chance, 0.0, 75.0)
		var enrage := _active_effect("enrage") as EnrageEffect
		damage_factor = enrage.damage_factor() if enrage != null else 1.0
		if weapon_ability:
			damage_factor *= card_effects.attack_multiplier()
		if streamed:
			strike_outcome.critical = critical
			strike_outcome.critical_roll = crit_roll
			strike_outcome.damage_factor = damage_factor
	if streamed:
		strike_outcome.count = earlier_contacts + targets.size()
	var weapon_hits := 0
	var first_weapon_contact := Vector3.INF
	var first_weapon_travel := Vector3.ZERO
	var first_weapon_type := weapon_type
	var first_weapon_swing := &""
	var first_weapon_critical := critical
	for index in range(targets.size()):
		var contact: Dictionary = targets[index]
		var enemy: Node3D = contact.target
		if not is_instance_valid(enemy) or not enemy.is_in_group("enemies"):
			continue
		var can_damage := bool(contact.get("can_damage", true))
		var can_stagger := bool(contact.get("can_stagger", true))
		if not can_damage and not can_stagger:
			continue
		var offhand: bool = is_melee and contact.get("weapon_hand", WeaponRoles.MAIN_HAND) == WeaponRoles.OFF_HAND
		var contact_type := _offhand_type if offhand else weapon_type
		var contact_base := _offhand_base_id if offhand else _weapon_base_id
		var legendary := _legendary_melee.effect_for_hand(offhand) if is_melee else &""
		var contact_damage := attribute_damage
		var contact_critical := critical
		if offhand and definition.scaling_attribute == "default":
			var offhand_attribute := WeaponRoles.scaling_attribute(contact_type, contact_base)
			contact_damage = character_progression.base_damage_multiplier(offhand_attribute)
			var chance := float(stats.crit_chance) + character_progression.critical_chance_bonus(offhand_attribute)
			contact_critical = crit_roll < clampf(chance, 0.0, 75.0)
		var stun_buildup := definition.stun_buildup
		if stun_buildup <= 0.0 and (definition == MELEE_ATTACK or definition == MELEE_HEAVY):
			stun_buildup = WeaponRoles.stun_buildup(contact_type, heavy)
		var level_factor := Progression.outgoing_multiplier(combat_ability_level(), int(enemy.combat_ability_level()))
		# Read the guard at impact, including when the hit is about to kill the enemy.
		var reflected: bool = is_melee and enemy.is_thornback_reflecting()
		var damage_min := _weapon_damage_stat("damage_min", is_melee, offhand)
		var damage_max := _weapon_damage_stat("damage_max", is_melee, offhand)
		var amount := _rng.randf_range(damage_min, damage_max) * contact_damage
		var cleave_factor := WeaponRoles.secondary_damage_factor(contact_type) \
			if weapon_ability and earlier_contacts + index > 0 else 1.0
		var stagger_factor := float(contact.get("stagger_falloff", cleave_factor))
		cleave_factor = float(contact.get("damage_falloff", cleave_factor))
		var scalar := definition.damage_multiplier * damage_factor * cleave_factor
		if heavy and is_melee:
			scalar *= WeaponRoles.charged_damage_factor(contact_type)
		var primary_type := "physical" if definition.damage_type.is_empty() else definition.damage_type
		var base_physical_damage := amount * scalar if primary_type == "physical" else 0.0
		if contact_critical:
			scalar *= Items.critical_damage_for_attack(stats.crit_multiplier, contact_type, is_melee) * 0.01
		if effects.has("execution") and enemy.health < enemy.max_health * 0.35:
			scalar *= 1.55
		if definition.hit_fx != null:
			CombatVisuals.landed_hit(enemy, definition, enemy.to_local(contact.point))
		var weapon_contact := WeaponRoles.contact(contact_type, contact_base, heavy, contact) if is_melee else {}
		if not weapon_contact.is_empty():
			weapon_contact.can_stagger = can_stagger
		var damage_by_type := {primary_type: amount * scalar}
		var spends_latch := heavy and legendary == LegendaryMelee.LATCHKNIFE and primary_type == "physical" \
			and _legendary_melee.latch_is_ready(enemy)
		if spends_latch:
			damage_by_type["physical"] *= 1.0 + LegendaryMelee.Rules.latch_damage_bonus * 0.01
		for element in ELEMENTS:
			var added := _weapon_damage_stat(element + "_damage", is_melee, offhand)
			if added > 0.0:
				damage_by_type[element] = float(damage_by_type.get(element, 0.0)) + added * scalar
		var staff_contact := is_staff and weapon_type == "staff"
		var previously_chilled := staff_contact and _caster_legendaries.was_chilled(enemy)
		var hit: Dictionary = enemy.take_hit(damage_by_type, self, contact.point, contact.direction, weapon_contact) \
			if can_damage else {}
		var dealt := float(hit.get("dealt", 0.0))
		var made_contact := dealt > 0.0 or bool(hit.get("glancing", false)) or (not can_damage and can_stagger)
		if can_stagger and heavy and is_melee and made_contact and enemy.health > 0.0 \
				and WeaponRoles.is_blunt_contact(weapon_contact):
			var force := dealt
			if contact.has("stagger_falloff") or not can_damage:
				force = amount * definition.damage_multiplier * damage_factor * stagger_factor * level_factor
			enemy.receive_blunt_knockback(contact.direction, force, weapon_contact)
		if can_damage:
			heal(dealt * float(stats.life_leech) * 0.01 + (1.0 if effects.has("bloodletting") else 0.0))
		if weapon_ability and dealt > 0.0 and not _weapon_card_landed:
			_weapon_card_landed = true
			card_effects.weapon_landed()
		if weapon_ability and made_contact and not bool(contact.get("stops_weapon", false)):
			if weapon_hits == 0:
				if earlier_contacts == 0:
					_weapon.react_to_impact(false, float(contact.get("phase", -1.0)))
				first_weapon_contact = contact.point
				first_weapon_travel = contact.direction
				var shake_offhand: bool = is_melee and contact.get("weapon_hand", _strike_hand) == WeaponRoles.OFF_HAND
				first_weapon_type = _offhand_type if shake_offhand else contact_type
				first_weapon_swing = _hit_shake_swing(shake_offhand)
				first_weapon_critical = contact_critical
			weapon_hits += 1
		if can_damage:
			struck.emit(enemy, dealt, contact_critical)
			report_enemy_hit(enemy, contact.point, hit, ability, contact_critical, level_factor <= 0.5)
		if staff_contact and dealt > 0.0 and _caster_legendaries.on_staff_hit(self, enemy, hit, previously_chilled):
			active_statuses_changed.emit()
		var stunned := false
		if can_stagger and stun_buildup > 0.0 and made_contact and enemy.health > 0.0:
			stunned = enemy.receive_stun_impact(stun_buildup * stagger_factor, self, ability)
		if is_melee and dealt > 0.0 and (legendary != &"" or _legendary_melee.has_pair):
			_apply_legendary_melee(enemy, contact, legendary, offhand, heavy, stunned, spends_latch, strike_outcome)
		if can_damage:
			HitEffects.apply_on_hit(definition.on_hit_effects, enemy, float(hit.physical), dealt, self, ability, _rng,
				base_physical_damage)
		if reflected and dealt > 0.0:
			var returned := DamageResolution.hit(_mitigate_incoming_damage(
				dealt * _incoming_level_multiplier(enemy, {}), "physical"))
			var impact := _apply_damage(returned, enemy.global_position, true, true)
			var reflection := _incoming_ability(enemy.thornback_guard_details(), enemy, "physical")
			_log_incoming_damage(reflection, returned, impact, "Physical · Reflected")
			CombatFloaters.outcome(enemy.get_parent() as Node3D, contact.point, "Reflected")
			feedback.emit("", "player_hit")
			if _dead:
				_combat_defeat()
				return
	var has_breakthrough_shake := not streamed or heavy or first_weapon_type != "mace_2h"
	if weapon_hits > 0 and has_breakthrough_shake and _camera_feedback != null \
			and not bool(strike_outcome.get("camera_kicked", false)):
		if streamed:
			strike_outcome.camera_kicked = true
		_camera_feedback.present_weapon_impact(first_weapon_contact, first_weapon_travel, first_weapon_type,
			heavy, weapon_hits, first_weapon_critical, first_weapon_swing)
	if earlier_contacts == 0 and heavy and effects.has("ashwake"):
		_fire_burst(targets[0].point)
	if earlier_contacts == 0 and effects.has("stormcall") and _storm_hits % 4 == 0:
		var source: Node3D = targets[0].target
		if is_instance_valid(source):
			var neighbor := _nearby_enemy(source, 6.5)
			if neighbor != null:
				var point: Vector3 = neighbor.aim_point()
				_draw_arc(source.aim_point(), point, Color("#8dbbff"))
				var hit: Dictionary = neighbor.take_hit({"lightning": 3.0 + float(stats.lightning_damage)}, self)
				report_enemy_hit(neighbor, point, hit, STORMCALL, false,
					neighbor.level_damage_factor(self) <= 0.5)
				neighbor.apply_status("shocked", 1.7, 0.2, self)


func _apply_legendary_melee(enemy: Node3D, contact: Dictionary, effect: StringName, offhand: bool,
		heavy: bool, stunned: bool, spends_latch: bool, strike: Dictionary) -> void:
	if not heavy:
		_legendary_melee.record_light_hand(offhand)
		if effect == LegendaryMelee.LATCHKNIFE and enemy.health > 0.0 and not _dual_wield and not _strike_is_follow_up \
				and _legendary_melee.add_latch_step(enemy, _strike_chain_stage):
			CombatImpact.contact(enemy.get_parent(), contact.point, -contact.direction, &"metal")
			_log_legendary_melee(effect, "Latchknife", "Three different light steps expose an enemy to the next charged hit.",
				enemy.display_name, "Latch ready")
		return
	if spends_latch:
		_legendary_melee.consume_latch(enemy)
		CombatImpact.contact(enemy.get_parent(), contact.point, -contact.direction, &"metal")
		_log_legendary_melee(effect, "Latchknife", "Charged Physical damage is increased when a latch is ready.",
			enemy.display_name, "Charged strike consumed the latch")
	if stunned and effect == LegendaryMelee.STILLSTONE \
			and WeaponRoles.family(_offhand_type if offhand else weapon_type) == WeaponRoles.BLUNT:
		_restore_stillstone_stamina(enemy)
	if stunned and effect == LegendaryMelee.GRAVEGATE and _legendary_melee.ready(effect):
		enemy.on_next_damaging_cast_interrupted(_on_gravegate_interrupt.bind(offhand, contact.point, contact.direction))
	if _legendary_melee.record_crossover_hand(offhand, _strike_hand, strike):
		_restore_pair_ward()


func _restore_stillstone_stamina(enemy: Node3D) -> void:
	if not _legendary_melee.ready(LegendaryMelee.STILLSTONE) or stamina >= max_stamina() \
			or (stamina < STAMINA_RULES.minimum_to_guard and _stamina_recovery > 0.0):
		return
	var gained := minf(LegendaryMelee.Rules.stillstone_stamina, max_stamina() - stamina)
	stamina += gained
	_legendary_melee.spend(LegendaryMelee.STILLSTONE, LegendaryMelee.Rules.stillstone_rearm)
	CombatImpact.contact(enemy.get_parent(), global_position + Vector3.UP * 0.08, Vector3.UP, &"stone")
	vitals_changed.emit()
	_log_legendary_melee(LegendaryMelee.STILLSTONE, "Stillstone",
		"A charged hit that stuns an enemy restores Stamina outside Guard Break.", "Player", "+%.1f Stamina" % gained)


func _on_gravegate_interrupt(enemy: Node3D, offhand: bool, point: Vector3, travel: Vector3) -> void:
	if _dead or _legendary_melee.effect_for_hand(offhand) != LegendaryMelee.GRAVEGATE \
			or not _legendary_melee.ready(LegendaryMelee.GRAVEGATE):
		return
	var rules := LegendaryMelee.Rules
	enemy.apply_status("chilled", rules.gravegate_chill_seconds, rules.gravegate_chill * 0.01, self)
	_legendary_melee.spend(LegendaryMelee.GRAVEGATE, rules.gravegate_rearm)
	CombatImpact.contact(enemy.get_parent(), point, -travel, &"arcane_cold")
	_log_legendary_melee(LegendaryMelee.GRAVEGATE, "Gravegate", "A charged interruption chills the enemy.",
		enemy.display_name, "Chilled for %.1f s" % rules.gravegate_chill_seconds)


func _restore_pair_ward() -> void:
	var gained := minf(LegendaryMelee.Rules.pair_ward, maxf(0.0, float(stats.ward) - ward))
	_legendary_melee.consume_crossover()
	if gained <= 0.0:
		return
	ward += gained
	for side in [-1.0, 1.0]:
		var point := camera.global_transform * Vector3(side * 0.32, -0.30, -0.79)
		CombatImpact.world(self, point, global_basis.x * side, &"metal")
	vitals_changed.emit()
	_log_legendary_melee(LegendaryMelee.UNMATCHED_PAIR, "The Unmatched Pair",
		"Land both light hands in order, then both hands of a charged crossover to restore Ward.",
		"Player", "+%.1f Ward" % gained)


func _log_legendary_melee(effect: StringName, title: String, description: String, target: String, detail: String) -> void:
	combat_event.emit({"kind": &"status", "side": &"player", "actor": "Player", "target": target,
		"ability_id": effect, "ability": title, "description": description, "detail": detail})


func _weapon_damage_stat(stat: String, melee: bool, offhand: bool) -> float:
	var value := float(stats.get(stat, 0.0))
	if not melee or not _dual_wield:
		return value
	var primary_stats: Dictionary = _equipment.get("main_hand", {}).get("stats", {})
	var secondary_stats: Dictionary = _equipment.get("off_hand", {}).get("stats", {})
	var split := (float(secondary_stats.get(stat, 0.0)) - float(primary_stats.get(stat, 0.0))) * 0.5
	return value + (split if offhand else -split)


func _authored_targets(profile: Dictionary) -> Array[Node3D]:
	var targets: Array[Node3D] = []
	var facing := -global_basis.z
	var center := global_position
	var disc: bool = profile.get("shape") == "disc"
	if disc:
		center += facing * float(profile.get("offset", 0.0))
	var reach := float(profile.get("reach", 0.0))
	var arc := cos(deg_to_rad(float(profile.get("arc", 45.0))))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var offset: Vector3 = enemy.global_position - center
		if absf(offset.y) > 2.0:
			continue
		offset.y = 0.0
		if offset.length_squared() > reach * reach:
			continue
		if not disc and offset.length_squared() > 0.000001 and facing.dot(offset.normalized()) < arc:
			continue
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position, enemy.aim_point(), 1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			targets.append(enemy)
	return targets


func _melee_targets(heavy: bool, sweep: MeleeSweep) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if sweep == null:
		var aim := get_aim_transform()
		sweep = MeleeSweep.new(weapon_type, heavy, get_rid(), aim)
		sweep.debug_volume = weapon_trace
		sweep.sample(get_world_3d().direct_space_state, aim, 0.0)
	var broken_prop_point := Vector3.INF
	var limit := _melee_limit(heavy)
	for hit in sweep.contacts():
		var target: Node3D = hit.target
		if target is BreakableProp:
			target.break_from(hit.direction, hit.point, hit.normal)
			if not broken_prop_point.is_finite():
				broken_prop_point = hit.point
		elif result.size() < limit:
			result.append(hit)
	if result.is_empty():
		_present_melee_terrain(heavy, sweep, broken_prop_point)
	return result


func _melee_limit(heavy: bool) -> int:
	var two_handed := weapon_type.ends_with("2h")
	return (4 if two_handed else 3) if heavy else (3 if two_handed else 1)


func _present_melee_terrain(heavy: bool, sweep: MeleeSweep, broken_prop_point: Vector3) -> void:
	var wall := sweep.terrain_contact()
	var broke_prop := broken_prop_point.is_finite()
	if not broke_prop and wall.is_empty():
		return
	var surface := &"breakable" if broke_prop else _melee_surface(wall)
	if not broke_prop:
		CombatImpact.world(self, wall.point, wall.normal, surface)
	_weapon.react_to_impact(true)
	if _camera_feedback != null:
		var point: Vector3 = broken_prop_point if broke_prop else wall.point
		var hand := WeaponRoles.OFF_HAND if sweep == _paired_sweep else _strike_hand
		if broke_prop:
			hand = _clip_outcome.get("broken_prop_hand", hand)
		var offhand := hand == WeaponRoles.OFF_HAND
		var strike_type := _offhand_type if offhand else weapon_type
		_camera_feedback.present_surface_impact(point, strike_type, surface, heavy, _hit_shake_swing(offhand))


func _hit_shake_swing(offhand: bool) -> StringName:
	return WeaponHitShake.motion_id(_weapon.clip_for_hand(_strike_animation, offhand), offhand)


func _melee_surface(contact: Dictionary) -> StringName:
	var collider_id := int(contact.get("collider_id", 0))
	var collider := instance_from_id(collider_id) if collider_id != 0 else null
	return collider.get_meta(&"impact_surface", &"stone") if is_instance_valid(collider) else &"stone"


func _staff_targets(heavy: bool) -> Array[Dictionary]:
	const REACH := 13.0
	var result: Array[Dictionary] = []
	var aim := get_aim_transform()
	var origin := aim.origin
	var direction := -aim.basis.z
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * REACH, 5, [get_rid()])
	var hit := space.intersect_ray(ray)
	var end := origin + direction * 9.0
	var enemy: Node3D
	var collider := hit.get("collider") as Node3D
	if collider is BreakableProp:
		end = hit.position
		collider.break_from(direction, hit.position, hit.normal)
	elif is_instance_valid(collider) and collider.is_in_group(&"enemies"):
		end = hit.position
		enemy = collider
	else:
		enemy = _staff_aim_assist(space, origin, direction, REACH)
		if is_instance_valid(enemy):
			end = enemy.aim_point()
		elif not hit.is_empty():
			end = hit.position
			CombatImpact.world(self, hit.position, hit.normal, &"arcane")
	_draw_arc(_weapon.staff_origin(origin + direction * 0.65 + aim.basis.x * 0.33), end,
		Color("#9bdad2"))
	if enemy == null:
		if not hit.is_empty() and _camera_feedback != null:
			var surface := &"breakable" if collider is BreakableProp else _melee_surface(hit)
			_camera_feedback.present_surface_impact(end, "staff", surface, heavy, _strike_animation)
		return result
	result.append({"target": enemy, "point": end, "direction": origin.direction_to(end)})
	if heavy:
		var nearby := _nearby_enemy(enemy, 2.6)
		if nearby == null:
			return result
		var point: Vector3 = nearby.aim_point()
		result.append({"target": nearby, "point": point, "direction": end.direction_to(point)})
	return result


func _staff_aim_assist(space: PhysicsDirectSpaceState3D, origin: Vector3,
		direction: Vector3, reach: float) -> Node3D:
	var target: Node3D
	var best_score := -INF
	for candidate in get_tree().get_nodes_in_group(&"enemies"):
		var point: Vector3 = candidate.aim_point()
		var offset := point - origin
		var alignment := direction.dot(offset.normalized())
		if offset.length_squared() > reach * reach or alignment < 0.994:
			continue
		var score := alignment * 4.0 - offset.length() * 0.14
		if score <= best_score:
			continue
		var visibility := PhysicsRayQueryParameters3D.create(origin, point, 1, [get_rid()])
		if space.intersect_ray(visibility).is_empty():
			best_score = score
			target = candidate
	return target


func _fire_burst(center: Vector3) -> void:
	var reach := 2.65
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var target: Vector3 = enemy.aim_point()
		if center.distance_to(target) > reach:
			continue
		if center.distance_squared_to(target) > 0.01:
			var wall := PhysicsRayQueryParameters3D.create(center, target, 1)
			if not get_world_3d().direct_space_state.intersect_ray(wall).is_empty():
				continue
		_draw_arc(center, target, Color("#f09e5e"))
		var hit: Dictionary = enemy.take_hit({"fire": 2.5 + float(stats.damage_max) * 0.23}, self)
		report_enemy_hit(enemy, target, hit, ASHWAKE, false, enemy.level_damage_factor(self) <= 0.5)


func _nearby_enemy(source: Node3D, reach: float) -> Node3D:
	var found: Node3D = null
	for node in get_tree().get_nodes_in_group("enemies"):
		var distance: float = source.global_position.distance_to(node.global_position)
		if node != source and distance < reach:
			var ray := PhysicsRayQueryParameters3D.create(source.aim_point(), node.aim_point(), 1)
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				found = node
				reach = distance
	return found


func _draw_arc(start: Vector3, end: Vector3, tint: Color) -> void:
	if start.distance_squared_to(end) < 0.01:
		return
	var arc := STAFF_ARC.instantiate()
	get_parent().add_child(arc)
	arc.align_to(start, end, tint)


func heal(amount: float) -> void:
	life = minf(stats.max_health, life + amount)


func on_kill() -> void:
	heal(stats.life_on_kill + (2.0 if effects.has("grave_echo") else 0.0))
	mana = minf(stats.max_mana, mana + stats.mana_on_kill + (1.0 if effects.has("grave_echo") else 0.0))
	if effects.has("soul_hunger"):
		_soul_timer = 3.0


func receive_enemy_hit(amount: float, damage_type: String, status := "", source: Node3D = null, ability: Dictionary = {}) -> bool:
	if _dead or not combat_enabled:
		return false
	if _evades_enemy_hit():
		return false
	amount *= _incoming_level_multiplier(source, ability)
	if _try_block_hit(amount, damage_type, source, ability):
		return false
	var definition := ability.get("definition") as AbilityDefinition
	CombatVisuals.landed_hit(self, definition, COMBAT_VISUAL_OFFSET)
	var base_physical_damage := amount if damage_type == "physical" else 0.0
	var resolved := DamageResolution.hit(_mitigate_incoming_damage(amount, damage_type))
	var context := _incoming_ability(ability, source, damage_type)
	var source_point := source.global_position if is_instance_valid(source) else Vector3.INF
	var impact := _apply_damage(resolved, source_point, damage_type == "physical", true,
		bool(ability.get("unblockable", false)))
	_log_incoming_damage(context, resolved, impact, damage_type.capitalize())
	if _dead:
		_combat_defeat()
	else:
		if impact.x > 0.0 and _defensive_legendaries.on_life_hit(effects):
			CombatImpact.world(self, global_position + Vector3.UP * 0.06, Vector3.UP, &"stone")
			active_statuses_changed.emit()
		if resolved > 0 and definition != null and definition.knockback_speed > 0.0:
			var direction: Vector3 = ability.get("push_direction", global_position - source_point)
			_receive_knockback(definition.knockback_speed, direction)
		if definition != null and amount > 0.0 and definition.stun_buildup > 0.0:
			_receive_stun_impact(definition.stun_buildup, source, ability, context)
		var previous: Variant = _ailments.get(status)
		var on_hit_effects: Array = definition.on_hit_effects if definition != null else []
		var physical := resolved if damage_type == "physical" else 0
		HitEffects.apply_on_hit(on_hit_effects, self, physical, resolved, source, context, _rng,
			base_physical_damage, status == "bleed")
		if not status.is_empty() and status != "bleed" and is_same(previous, _ailments.get(status)):
			var effect := StatusCatalog.get_effect(status)
			if effect != null:
				receive_combat_effect(effect, effect.duration, effect.on_hit_potency(resolved), source, context)
	feedback.emit("", "player_hit")
	return true


## Resolves persistent damage from standing on a hazardous floor.
func receive_ground_damage(amount: float, damage_type: String, source: Node3D, ability: Dictionary) -> bool:
	if _dead or not combat_enabled:
		return false
	var scaled := amount * _incoming_level_multiplier(source, ability)
	var resolved := DamageResolution.hit(_mitigate_incoming_damage(scaled, damage_type))
	if resolved <= 0:
		return false
	var impact := _apply_damage(resolved)
	_log_incoming_damage(_incoming_ability(ability, source, damage_type), resolved, impact, damage_type.capitalize())
	if _dead:
		_combat_defeat()
	return true


func _source_level(source: Node, ability: Dictionary) -> int:
	if ability.has("source_level"):
		return maxi(1, int(ability["source_level"]))
	if is_instance_valid(source) and source.has_method("combat_ability_level"):
		return maxi(1, int(source.combat_ability_level()))
	return combat_ability_level()


func _incoming_level_multiplier(source: Node, ability: Dictionary) -> float:
	return Progression.incoming_multiplier(_source_level(source, ability), combat_ability_level())


func _incoming_ability(ability: Dictionary, source: Node, damage_type: String) -> Dictionary:
	var actor := String(ability.get("actor", ""))
	if actor.is_empty() and is_instance_valid(source):
		var display: Variant = source.get("display_name")
		actor = String(display) if display is String else String(source.name)
	if actor.is_empty():
		actor = "Enemy"
	var kind := damage_type.capitalize()
	return {
		"id": ability.get("id", &""),
		"name": String(ability.get("name", "%s Hit" % kind)),
		"description": String(ability.get("description", "A hit that deals %s damage." % kind)),
		"actor": actor,
		"side": StringName(ability.get("side", &"enemy")),
		"source_level": _source_level(source, ability),
	}


func _log_player_cast(kind: StringName, ability: Dictionary, detail := "") -> void:
	if ability.is_empty():
		return
	combat_event.emit({
		"kind": kind, "side": &"player", "actor": "Player",
		"ability_id": ability.get("id", &""),
		"ability": ability["name"], "description": ability["description"], "detail": detail,
	})


func _log_status(ability: Dictionary, detail: String) -> void:
	combat_event.emit({
		"kind": &"status", "side": ability["side"], "actor": ability["actor"], "target": "Player",
		"ability_id": ability.get("id", &""),
		"ability": ability["name"], "description": ability["description"], "detail": detail,
	})


func _log_damage(side: StringName, actor: String, target: String, ability: Dictionary,
		amount: int, detail: String) -> void:
	if amount <= 0:
		return
	combat_event.emit({
		"kind": &"damage", "side": side, "actor": actor, "target": target,
		"ability_id": ability.get("id", &""),
		"ability": ability["name"], "description": ability["description"], "amount": amount, "detail": detail,
	})


func report_enemy_hit(enemy: Node3D, point: Vector3, hit: Dictionary, ability: Dictionary,
		critical := false, glancing := false) -> void:
	var amount: int = hit.amount
	glancing = glancing or bool(hit.glancing)
	if amount == 0:
		if hit.glancing:
			CombatFloaters.damage(enemy, point, amount, false, false, true)
			combat_event.emit({
				"kind": &"status", "side": &"player", "actor": "Player", "target": enemy.display_name,
				"ability_id": ability.get("id", &""), "ability": ability["name"],
				"description": ability["description"], "detail": "Glancing",
			})
		return
	CombatFloaters.damage(enemy, point, amount, critical, false, glancing)
	var detail := " + ".join(hit.types)
	if critical:
		detail += " · Critical"
	if glancing:
		detail += " · Glancing"
	if not is_equal_approx(float(hit.dealt), amount):
		detail += " · %s Life lost" % Items.stat_value("max_health", float(hit.dealt))
	_log_damage(&"player", "Player", enemy.display_name, ability, amount, detail)


func _log_incoming_damage(ability: Dictionary, amount: int, impact: Vector2, detail: String) -> void:
	if amount <= 0:
		return
	var losses := PackedStringArray()
	if impact.x > 0.0:
		losses.append("%s Life" % Items.stat_value("max_health", impact.x))
	if impact.y > 0.0:
		losses.append("%s Ward" % Items.stat_value("ward", impact.y))
	_log_damage(ability["side"], ability["actor"], "Player", ability, amount,
		"%s · %s" % [detail, " + ".join(losses)])


func _combat_defeat() -> void:
	flush_combat_log()
	_clear_ailments()
	_reset_combat_inputs("Interrupted by defeat")


func _clear_ailments() -> void:
	var had_perks := _defensive_legendaries.clear()
	var had_statuses := is_stunned() or not _ailments.is_empty() or had_perks
	_stun.clear()
	for state: Dictionary in _ailments.values():
		CombatVisuals.end_status(self, state, COMBAT_VISUAL_OFFSET)
	_ailments.clear()
	if had_statuses:
		active_statuses_changed.emit()


func active_statuses() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	if _dead or not combat_enabled:
		return active
	if is_stunned():
		var effect := StatusCatalog.get_effect("stunned")
		active.append({"id": effect.id, "name": effect.display_name, "icon": effect.icon,
			"remaining": _stun.remaining, "description": effect.tooltip_description(), "beneficial": false})
	if _phase_timer > 0.0:
		active.append({"id": &"phasewalk", "name": "Phasewalk", "beneficial": true,
			"remaining": _phase_timer, "description": "Move 38% faster after evading a hit.",
			"icon": preload("res://assets/rework/icons/phasewalk.tres")})
	if _soul_timer > 0.0:
		active.append({"id": &"soul_hunger", "name": "Soul Hunger", "beneficial": true,
			"remaining": _soul_timer, "description": "Kills grant %.1f%% increased weapon attack speed." \
				% ATTACK_TEMPO.soul_hunger_attack_speed,
			"icon": preload("res://assets/rework/icons/soul_hunger.tres")})
	if effects.has("dawnward") and life <= float(stats.max_health) * 0.30:
		active.append({"id": &"dawnward", "name": "Dawnward", "beneficial": true,
			"remaining": INF, "description": "Take 31% less incoming hit damage while at or below 30% Life.",
			"icon": preload("res://assets/rework/icons/dawnward.tres")})
	_defensive_legendaries.append_statuses(active, effects)
	_caster_legendaries.append_statuses(active)
	var minimum: float = STAMINA_RULES.minimum_to_guard
	if stamina < minimum:
		var wait := _stamina_recovery + (minimum - stamina) / _stamina_recharge_per_second()
		active.append({"id": &"guard_broken", "name": "Guard Broken", "beneficial": false,
			"remaining": wait, "description": "Blocking returns when you have %s Stamina." % str(minimum),
			"icon": preload("res://assets/rework/icons/guard_broken.tres")})
	for status: String in _ailments:
		var state: Dictionary = _ailments[status]
		var effect: EffectDefinition = state["effect"]
		active.append({"id": effect.id, "name": effect.display_name, "icon": effect.icon,
			"description": effect.tooltip_description(), "remaining": state["remaining"],
			"beneficial": effect.beneficial})
	return active


func _mitigate_incoming_damage(amount: float, damage_type: String) -> float:
	if damage_type == "physical":
		amount = Items.physical_damage_after_armor(amount, stats.armor)
	else:
		amount = Items.damage_after_resistance(amount, float(stats.get(damage_type + "_resist", 0.0)))
	var shock := _active_effect("shocked") as ShockEffectDefinition
	if shock != null:
		amount *= shock.damage_taken_multiplier
	if effects.has("dawnward") and life <= float(stats.max_health) * 0.30:
		amount *= 0.69
	return amount * card_effects.incoming_multiplier()


func _active_effect(status: String) -> EffectDefinition:
	var state: Variant = _ailments.get(status)
	return state["effect"] as EffectDefinition if state != null else null


func _attack_speed_factor() -> float:
	var enrage := _active_effect("enrage") as EnrageEffect
	return enrage.attack_speed_factor() if enrage != null else 1.0


func combat_ability_level() -> int:
	return character_progression.level


func combat_stun_power() -> float:
	return float(stats.get("stun_power", 0.0))


func is_stunned() -> bool:
	return _stun.is_stunned()


func _stun_protected() -> bool:
	return _strike_pending and _strike_ability != null and _strike_ability.uninterruptible


func _receive_stun_impact(amount: float, source: Node, ability: Dictionary, context: Dictionary) -> void:
	if _stun_protected():
		return
	var power := float(ability.get("stun_power", 0.0))
	if not ability.has("stun_power") and is_instance_valid(source) and source.has_method("combat_stun_power"):
		power = float(source.combat_stun_power())
	var level_factor := Progression.outgoing_multiplier(_source_level(source, ability), combat_ability_level())
	var duration := _stun.add_impact(amount * level_factor, stun_threshold, power,
		StunRuntime.PLAYER_BASE_DURATION, StunRuntime.PLAYER_MAX_DURATION)
	if duration > 0.0:
		_on_stunned(context)


func _on_stunned(context: Dictionary) -> void:
	var bell_recovering := _defensive_legendaries.is_still_bell_recovering()
	_stun.remaining = _defensive_legendaries.stun_duration(effects, _stun.remaining)
	if not bell_recovering and _defensive_legendaries.is_still_bell_recovering():
		feedback.emit("", "block")
	velocity.x = 0.0
	velocity.z = 0.0
	_reset_combat_inputs("Interrupted by stun")
	_log_status(context, "Stunned · %.2f s" % _stun.remaining)
	feedback.emit("Stunned", "")
	active_statuses_changed.emit()


func combat_bleed_chance() -> float:
	return float(stats.get("bleed_chance", 0.0))


func combat_bleed_damage_bonus() -> float:
	return float(stats.get("bleed_damage", 0.0)) + float(stats.get("damage_over_time", 0.0))


func receive_combat_effect(effect: EffectDefinition, duration: float, potency: float,
		source: Node, context: Dictionary) -> bool:
	if effect == null or duration <= 0.0 or _dead or not combat_enabled:
		return false
	var status := String(effect.id)
	if status == "stunned":
		if _stun_protected() or _stun.start(minf(duration, StunRuntime.PLAYER_MAX_DURATION)) <= 0.0:
			return false
		_on_stunned(_incoming_ability(context, source, "physical"))
		return true
	var previous: Dictionary = _ailments.get(status, {})
	if not previous.is_empty() and not effect.replaces(float(previous["damage"]), potency):
		return false
	var note := _incoming_ability(context, source, "physical")
	var state := {"remaining": duration, "damage": potency, "effect": effect}
	if not effect.damage_type.is_empty():
		_flush_ailment_damage(previous)
		state.merge({"ability": note, "detail": "%s · %s damage over time" % [
			effect.damage_type.capitalize(), effect.display_name,
		], "impact": Vector2.ZERO, "logged_damage": 0, "elapsed": 0.0,
			"tick_interval": maxf(0.01, effect.tick_interval),
			"pending_time": previous.get("pending_time", 0.0),
			"pending_damage": previous.get("pending_damage", 0.0),
			"damage_remainder": previous.get("damage_remainder", 0.0)})
	_ailments[status] = state
	CombatVisuals.apply_status(self, effect, state, previous, COMBAT_VISUAL_OFFSET)
	active_statuses_changed.emit()
	if status == "rooted":
		velocity.x = 0.0
		velocity.z = 0.0
	var duration_text := "Until defeat" if is_inf(duration) else "%s s" % String.num(duration, 2).trim_suffix(".0")
	_log_status(note, "%s · %s" % [effect.display_name, duration_text])
	return true


func apply_cobweb_root(ability: Dictionary = {}, root_seconds := -1.0) -> bool:
	if _dead or not combat_enabled or root_seconds == 0.0 or _evades_enemy_hit():
		return false
	var root := StatusCatalog.get_effect("rooted")
	var duration := root.duration if root_seconds < 0.0 else root_seconds
	var seconds := String.num(duration, 2).trim_suffix(".0")
	var context := _incoming_ability({
		"name": "Cobweb Trap",
		"description": "A launched web roots movement for %s seconds on hit, while aiming and attacks remain available." % seconds,
	} if ability.is_empty() else ability, null, "physical")
	var definition := ability.get("definition") as AbilityDefinition
	CombatVisuals.landed_hit(self, definition, COMBAT_VISUAL_OFFSET)
	var applied := HitEffects.apply_on_hit(definition.on_hit_effects, self, 0.0, 0.0, null, context, _rng) \
		if definition != null else receive_combat_effect(root, duration, 0.0, null, context)
	if applied and is_cobweb_rooted():
		seconds = String.num(_ailments["rooted"]["remaining"], 2).trim_suffix(".0")
		feedback.emit("Cobweb hit · Rooted for %s seconds" % seconds, "")
	return applied


func is_cobweb_rooted() -> bool:
	return _ailments.has("rooted")


func _evades_enemy_hit() -> bool:
	var evaded := _rng.randf() * 100.0 < clampf(stats.dodge_chance, 0.0, 60.0)
	if evaded:
		if effects.has("phasewalk"):
			_phase_timer = 1.25
			active_statuses_changed.emit()
		feedback.emit("Evaded", "")
	return evaded


func _tick_ailments(delta: float) -> void:
	var was_stunned := is_stunned()
	_stun.advance(delta)
	var display_changed := was_stunned and not is_stunned()
	if display_changed:
		_ignore_held_attack()
	display_changed = _defensive_legendaries.advance(delta) or display_changed
	for key in _ailments.keys():
		var state: Dictionary = _ailments[key]
		var previous_remaining: float = state["remaining"]
		var remaining := previous_remaining - delta
		var active_delta := minf(delta, previous_remaining)
		state["remaining"] = remaining
		if state.has("impact"):
			_tick_ailment_damage(state, active_delta)
			state["elapsed"] += active_delta
			if _dead:
				_combat_defeat()
				return
			if state["elapsed"] >= AILMENT_LOG_INTERVAL or remaining <= 0.000001:
				_flush_ailment_damage(state)
		if remaining <= 0.000001:
			CombatVisuals.end_status(self, state, COMBAT_VISUAL_OFFSET)
			_ailments.erase(key)
			display_changed = true
		elif is_finite(remaining) and ceili(remaining - 0.000001) != ceili(previous_remaining - 0.000001):
			display_changed = true
	if display_changed:
		active_statuses_changed.emit()


func _tick_ailment_damage(state: Dictionary, delta: float) -> void:
	var potency := float(state["damage"])
	var pending_time := float(state["pending_time"]) + delta
	var pending_damage := float(state["pending_damage"]) + potency * delta
	var interval := float(state["tick_interval"])
	var expired: bool = state["remaining"] <= 0.000001
	var ticks := floorf((pending_time + 0.000001) / interval)
	if ticks > 0.0 or expired:
		var leftover_time := 0.0 if expired else maxf(0.0, pending_time - ticks * interval)
		var leftover_damage := potency * leftover_time
		var damage := maxf(0.0, pending_damage - leftover_damage)
		var bleed := state["effect"] as BleedEffectDefinition
		if bleed != null:
			damage = bleed.mitigate_tick(damage, float(stats.get("physical_dot_reduction", 0.0)))
		var resolved := DamageResolution.tick(damage, state)
		state["logged_damage"] += resolved
		state["impact"] += _apply_damage(resolved)
		pending_time = leftover_time
		pending_damage = leftover_damage
	state["pending_time"] = pending_time
	state["pending_damage"] = pending_damage


func flush_combat_log() -> void:
	for state: Dictionary in _ailments.values():
		_flush_ailment_damage(state)


func _flush_ailment_damage(state: Dictionary) -> void:
	if not state.has("impact"):
		return
	_log_incoming_damage(state["ability"], state["logged_damage"], state["impact"], state["detail"])
	state["impact"] = Vector2.ZERO
	state["logged_damage"] = 0
	state["elapsed"] = 0.0


func _apply_damage(amount: float, source := Vector3.INF, blood := false, direct_hit := false,
		hard_hit := false) -> Vector2:
	if amount <= 0.0 or _dead:
		return Vector2.ZERO
	_recovery_timer = 3.0
	var previous_life := life
	var absorbed := minf(ward, amount)
	ward -= absorbed
	life = maxf(0.0, life - amount + absorbed)
	vitals_changed.emit()
	if _camera_feedback != null:
		_camera_feedback.present_hit(previous_life - life, absorbed, source, blood, direct_hit, hard_hit)
	if life <= 0.0:
		_dead = true
		died.emit()
	return Vector2(previous_life - life, absorbed)


func present_nearby_enemy_death(enemy: Node3D) -> void:
	if _camera_feedback == null or enemy.is_cocoon():
		return
	var family: String = enemy.definition().get("family", "")
	if family not in CombatImpact.DRY_CREATURES:
		_camera_feedback.present_nearby_enemy_death(enemy.global_position + Vector3.UP)
