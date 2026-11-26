@abstract
extends CharacterBody3D

signal died(enemy: CharacterBody3D)
signal encountered(enemy: CharacterBody3D)
signal metamorphosis_changed
signal behavior_changed
signal combat_event(event: Dictionary)

const AbilityRuntime = preload("res://combat/abilities/ability_runtime.gd")
const AttackAnimation = preload("res://combat/attack_animation.gd")
const CombatVisuals = preload("res://combat/effects/combat_visuals.gd")
const CombatImpact = preload("res://combat/effects/combat_impact.gd")
const ImpactFeedback = preload("res://data/impact_feedback.tres")
const CombatFloaters = preload("res://combat/effects/combat_floaters.gd")
const DamageResolution = preload("res://combat/damage_resolution.gd")
const WeaponRoles = preload("res://combat/weapons/weapon_roles.gd")
const EnemyRagdoll = preload("res://combat/enemies/enemy_ragdoll.gd")
const EnemyModel = preload("res://combat/enemies/enemy_model.gd")
const Affixes = preload("res://combat/effects/enemy_affixes.gd")
const Naming := preload("res://data/enemy_naming_rules.tres")
const Statuses = preload("res://combat/effects/status_catalog.gd")
const ProjectilePool = preload("res://combat/effects/enemy_projectile_pool.gd")
const Cobweb = preload("res://combat/effects/enemy_cobweb.gd")
const CobwebProjectile = preload("res://combat/effects/cobweb_projectile.tscn")
const MothCocoon = preload("res://combat/effects/moth_cocoon_visual.tscn")
const MothCocoonVisual = preload("res://combat/effects/moth_cocoon_visual.gd")
const EnemyTree = preload("res://ai/hearth_enemy_tree.tres")
const Telegraph = preload("res://combat/effects/enemy_telegraph.gd")
const TelegraphRules := preload("res://data/telegraph_rules.tres")
const EnemyIndicator := preload("res://ui/enemy_indicator.tscn")
const EnemyStatusIcon := preload("res://ui/enemy_status_icon.tscn")
const LevelScaling = preload("res://combat/enemies/enemy_scaling.tres")
const EnemyStats = preload("res://combat/enemies/enemy_stat_resolver.gd")
const Progression = preload("res://systems/character_progression.gd")
const StunRuntime = preload("res://combat/effects/stun_runtime.gd")
const StunnedEffect = preload("res://combat/effects/stunned.tres")
const RageEffect = preload("res://combat/effects/enrage.tres")
const Feedback = preload("res://data/combat_feedback.tres")

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
const BASE_ALERT := 9.8
const TRACKING_SIGHT_RANGE := 25.0
const MELEE_ATTACK_CATEGORY := &"hearth_melee"
const RANGED_ATTACK_CATEGORY := &"hearth_ranged"
const DEFAULT_RANGED_PREFERRED_RANGE := 4.8
const DEFAULT_RANGED_RETREAT_DURATION := 0.8
const RANGED_RETREAT_REARM_MARGIN := 0.75
const ARRIVAL_DISTANCE := 0.24
const SWING_STEP_DISTANCE := 1.15
const SWING_STEP_SPEED := 3.9
const STRIKE_CLIP_SECONDS := 0.24
const ATTACK_ACCELERATION := 29.0
const PROJECTILE_AIM_LOCK_SECONDS := 0.14
const DISCOVERY_RANGE := 10.0
const ABILITY_TRACE_HEIGHT := 0.075
const VOLATILE_RADIUS := 2.05
const VOLATILE_WARNING := {"shape": "disc", "reach": VOLATILE_RADIUS}
const VOLATILE_WINDUP := 0.62
const CombatLifetimeRules := preload("res://data/combat_lifetime_rules.tres")
const HEALTH_BAR_MAX_PIXELS := 108.0
const INDICATOR_GAP := 0.13
const REGENERATION_DELAY := 1.8
const COCOON_HEIGHT := 1.10
const COCOON_RADIUS := 0.41
const COCOON_LIFE_BAR_HEIGHT := 1.25

enum AttackPhase { READY, WINDUP, DASH, SECOND_SHOT, FOLLOW_UP, RECOVERY, AREA_TRACE }

const RARITY_COLORS := {
	"normal": Color("b05b52"),
	"magic": Color("81adf1"),
	"rare": Color("deb96b")
}
const ELEMENT_COLORS := {
	"physical": Color("cf7955"),
	"fire": Color("f9783b"),
	"cold": Color("70c6ee"),
	"lightning": Color("c698ee"),
	"poison": Color("a9cd66")
}


@export_group("Base Stats")
## Starting Life at enemy level 1. Level scaling, rarity, and affixes adjust the maximum.
@export_range(1.0, 1000.0, 0.1, "or_greater") var base_life := 1.0
## Starting attack damage at enemy level 1. Level scaling, rarity, affixes, the ability's
## damage multiplier, and the target's defenses determine the damage actually dealt.
@export_range(0.0, 1000.0, 0.1, "or_greater") var base_attack_damage := 1.0
## Reduces Physical damage over time by this percentage. Armour and hit-only defenses are separate.
@export_range(0.0, 100.0, 0.1, "suffix:%") var physical_dot_reduction := 0.0
## Amount of accumulated stun buildup needed to interrupt this enemy.
@export_range(1.0, 500.0, 1.0, "or_greater") var stun_threshold := StunRuntime.DEFAULT_THRESHOLD
## Increases the duration of stuns that this enemy inflicts, up to the target's cap.
@export_range(0.0, 100.0, 1.0, "or_greater", "suffix:%") var stun_power := 0.0
## Ground speed at enemy level 1 in meters per second, before level or affix bonuses.
@export_range(0.0, 20.0, 0.0001, "or_greater", "suffix:m/s") var base_move_speed := 1.0
## Maximum body turn rate while navigating, in degrees per second.
## Higher values let the enemy face its movement direction sooner.
@export_range(90.0, 1800.0, 5.0, "or_greater", "suffix:°/s") var turn_speed := 1080.0

@export_group("Ability Loadout")
## Shared ability resources this enemy can use. The default AI rotates through ready attacks
## in list order and uses the first ordinary attack until additional moves unlock.
## Open an ability resource to change its authored effects or cooldown for every caster.
## Each caster maintains its own cooldown timers.
@export var ability_loadout: Array[AbilityDefinition] = []
## Starting and maximum Mana. Abilities spend their authored Mana cost when the cast commits.
@export_range(0.0, 1000.0, 0.1, "or_greater") var max_mana := 44.0
## Mana restored per second up to Max Mana. Zero disables passive recovery.
@export_range(0.0, 100.0, 0.1, "or_greater") var mana_regeneration := 3.0

var archetype_id := 0
var enemy_level := 1
var archetype_name := ""
var display_name := ""
var rarity := "normal"
var part_key := ""
var affixes: Array[String] = []
var max_health := 1.0
var health := 1.0
var mana := 44.0

var _player: Node3D
var _route: Callable
var _ability_details: Callable
var _spec: Dictionary
var _ability_runtime := AbilityRuntime.new()
var _abilities_by_id: Dictionary[String, AbilityDefinition] = {}
var _cobweb_ability: AbilityDefinition
var _cocoon_ability: AbilityDefinition
var _guard_ability: AbilityDefinition
var _attack_profiles: Dictionary
var _cobweb_profile: Dictionary
var _cocoon_profile: Dictionary
var _guard_profile: Dictionary
var _size_multiplier := 1.0
var _body_height := 1.9
var _base_damage := 1.0
var _base_speed := 1.0
var _ranged := false
var _ranged_preferred_range := DEFAULT_RANGED_PREFERRED_RANGE
var _ranged_retreat_duration := DEFAULT_RANGED_RETREAT_DURATION
var _ranged_retreat_until := -1.0
var _has_cobweb := false
var _has_cocoon := false
var _has_thornback_guard := false
var _thornback_guard_warmup := 0.0
var _thornback_guard_remaining := 0.0
var _thornback_guard_visual: Node3D
var _affix_enrage_visual: Node3D
var _model: EnemyModel
var _hitbox: CollisionShape3D
var _living_shape: CapsuleShape3D
var _living_hitbox_position := Vector3.ZERO
var _cocoon_visual: MothCocoonVisual
var _cocoon_remaining := 0.0
var _moth_life := 1.0
var _hatches := 0
var _bar: MeshInstance3D
var _title: Label3D
var _bleed_icon: Sprite3D
var _stun_icon: Sprite3D
var _stun := StunRuntime.new()
var _stun_visual: Dictionary = {}
var _pack := -1
var _alert_radius := BASE_ALERT
var _sight_radius := BASE_ALERT
var _engaged := false
var _encountered := false
var _dead := false
var _waypoints := PackedVector3Array()
var _waypoint_tail := PackedFloat32Array()
var _waypoint_index := 0
var _route_timer := 0.0
var _attack_phase := AttackPhase.READY
var _attack_remaining := 0.0
var _windup_total := 0.0
var _floor_warning_locked := false
var _warning_footprint: Dictionary = {}
var _attack_origin := Vector3.ZERO
var _swing_step_origin := Vector3.ZERO
var _swing_steps_in := false
var _swing_step_started := false
var _aim_position := Vector3.ZERO
var _dash_travel := 0.0
var _recovery := 0.0
var _combat_time := 0.0
var _strike_time := -1.0
var _trace_markers: AttackAnimation
var _area_contacted := false
var _area_hit := false
var _follow_up_delay := -1.0
var _attack_serial := 0
var _attack_rng := RandomNumberGenerator.new()
var _sight := false
var _world_ray := PhysicsRayQueryParameters3D.new()
var _decision_time := 0.0
var _decision_interval := 0.16
var _rest_offset := 0.0
var _planned_velocity := Vector3.ZERO
var _impulse := Vector3.ZERO
var _blunt_push_rearm := 0.0
var _last_hurt := 0.0
var _statuses: Dictionary = {}
var _attack_elements: Array[Vector2i] = []
var _selected_element := Vector2i.ZERO
var _selected_damage_type := "physical"
var _windup_toward := Vector3.FORWARD
var _profile: Dictionary
var _move_id := ""
var _patterns: Array[String] = []
var _attack_ability: Dictionary = {}
var _ability_trace: Callable
var _attack_cast_open := false
var _on_cast_interrupted: Callable
var _windup_multiplier := 1.0
var _recovery_multiplier := 1.0
var _projectile_speed_multiplier := 1.0
var _projectile_lead_factor := 0.0
var _projectile_lead_limit := 0.0
var _pack_group: StringName
var _attack_warning: MeshInstance3D
var _casting_cobweb := false
var _cobweb_windup: Node3D
var _patrol_points := PackedVector3Array()
var _patrol_route: Array = []
var _brain: AIBehaviorRunner
var _encounter: AIEncounter3D
var _encounter_pressure: Node
var _target: Node3D
var _melee_ring := AIEncounter3D.RING_NORMAL
var _shooting_lane := false
var _has_move_goal := false
var _tactical_goal := Vector3.ZERO
var _path_goal := Vector3.INF
var _contact_point := Vector3.ZERO
var _attack_claim := false
var _dashed_this_tick := false
var _windup_pose := 0.0


const DAMAGE_TYPES := ["physical", "fire", "cold", "lightning", "poison"]
const ATTACK_STATUSES := ["", "bleed", "chilled", "shocked", "poisoned", "burning"]

@abstract func definition() -> Dictionary

func ranged_positioning() -> Dictionary:
	return {}

func setup(player: Node3D, spawn_level: int, rank: String, rng: RandomNumberGenerator,
		route: Callable = Callable(), ability_details: Callable = Callable(),
		selected_affixes: Array[String] = []) -> void:
	_player = player
	_route = route
	_ability_details = ability_details
	_spec = definition()
	archetype_id = _spec["id"]
	var behavior: Dictionary = _spec.get("behavior", {})
	archetype_name = _spec["name"]
	display_name = archetype_name
	part_key = _spec["part"]
	rarity = rank if RARITY_COLORS.has(rank) else "normal"
	_ranged = _spec.get("ranged", false)
	if behavior.has("positioning"):
		_ranged = behavior["positioning"] == "ranged"
	if _ranged:
		var positioning := ranged_positioning()
		_ranged_preferred_range = float(positioning.get("preferred_range", _ranged_preferred_range))
		_ranged_retreat_duration = float(positioning.get("retreat_duration", _ranged_retreat_duration))
	_bind_abilities()
	mana = max_mana
	enemy_level = maxi(1, spawn_level)
	_windup_multiplier = LevelScaling.windup_multiplier(enemy_level)
	_recovery_multiplier = LevelScaling.recovery_multiplier(enemy_level)
	_projectile_speed_multiplier = LevelScaling.projectile_speed_multiplier(enemy_level)
	_projectile_lead_factor = LevelScaling.projectile_lead_factor(enemy_level)
	_projectile_lead_limit = LevelScaling.projectile_lead_limit(enemy_level)
	_select_affixes(rng, selected_affixes)
	if not bool(_spec.get("proper_name", false)):
		if rarity == "rare":
			display_name = Naming.rare_name(String(_spec.get("family", "")), int(rng.seed), archetype_id, affixes.size(), archetype_name)
		elif rarity == "magic" and not affixes.is_empty():
			display_name = "%s %s" % [Affixes.AFFIX_NAMES[affixes[0]], archetype_name]
	var stats := EnemyStats.resolve(base_life, base_attack_damage, base_move_speed,
		float(behavior.get("advance_speed", 1.0)), enemy_level, rarity, affixes)
	_size_multiplier = stats["size_multiplier"]
	_body_height = float(_spec["height"]) * _size_multiplier
	max_health = stats["life"]
	health = max_health
	_moth_life = max_health
	_base_damage = stats["attack_damage"]
	_base_speed = stats["move_speed"]
	_decision_time = rng.randf_range(0.0, 0.19)
	_decision_interval = rng.randf_range(0.14, 0.19)
	_rest_offset = rng.randf_range(0.03, 0.16)
	_attack_rng.seed = rng.state
	if _has_thornback_guard:
		_thornback_guard_warmup = float(_guard_profile["first_delay"]) + _rest_offset * 10.0
	_choose_profile()

func _bind_abilities() -> void:
	for ability in ability_loadout:
		if ability == null or ability.id.is_empty():
			continue
		var id := String(ability.id)
		_abilities_by_id[id] = ability
		match ability.action_key:
			"cobweb":
				_cobweb_ability = ability
				_cobweb_profile = ability.runtime_profile()
				_has_cobweb = true
			"cocoon":
				_cocoon_ability = ability
				_cocoon_profile = ability.runtime_profile()
				_has_cocoon = true
			"thornback_guard":
				_guard_ability = ability
				_guard_profile = ability.runtime_profile()
				_has_thornback_guard = true
			_:
				var profile := ability.runtime_profile()
				if not String(profile.get("shape", "")).is_empty():
					_patterns.append(id)
					if not _attack_profiles.has(id):
						_attack_profiles[id] = profile

func _spend_mana(amount: float) -> void:
	mana -= amount


func combat_tuning_summary() -> Dictionary:
	return {"level": enemy_level, "life": max_health, "move_speed": _movement_speed(),
		"attack_damage": _base_damage}

func combat_ability_level() -> int:
	return enemy_level


func is_fighting_player() -> bool:
	return not _dead and not is_cocoon() and _engaged and (_sight or _attack_cast_open)


func can_be_raised() -> bool:
	return _dead and not is_cocoon() and archetype_id not in [25, 26] and not is_queued_for_deletion()


func combat_stun_power() -> float:
	return stun_power

func set_ability_trace(trace: Callable) -> void:
	_ability_trace = trace

func combat_traits() -> Array[Dictionary]:
	return []

func on_surviving_damage() -> void:
	pass

func save_behavior_state() -> Dictionary:
	return {}

func restore_behavior_state(_state: Dictionary) -> void:
	pass

func aim_point() -> Vector3:
	var height := COCOON_HEIGHT if is_cocoon() else _body_height
	return global_position + Vector3.UP * height * 0.48

func is_cocoon() -> bool:
	return not _dead and _cocoon_remaining > 0.0

func is_thornback_reflecting() -> bool:
	return _thornback_guard_remaining > 0.0

func melee_contact_material() -> StringName:
	if is_cocoon() or is_thornback_reflecting():
		return &"guard"
	return &"armor" if affixes.has("armored") else &"body"


func melee_contact_mass() -> float:
	return clampf(_body_resistance(), 0.65, 2.5)


func thornback_guard_details() -> Dictionary:
	return _combat_ability("thornback_guard")

func save_metamorphosis() -> Dictionary:
	if not _has_cocoon or _dead or (_hatches == 0 and not is_cocoon()):
		return {}
	return {"hatches": _hatches, "cocoon_remaining": _cocoon_remaining}

func configure_encounter(pack: int, _ambush: bool, alert_radius: float,
		patrol_points: PackedVector3Array = PackedVector3Array(), sight_radius := 0.0) -> void:
	_pack = pack
	_alert_radius = maxf(2.0, alert_radius)
	_sight_radius = maxf(_alert_radius, sight_radius)
	_patrol_points = patrol_points

static func create_ai_encounter(rating: int, target: Node3D, use_navigation: bool = true) -> AIEncounter3D:
	var encounter := AIEncounter3D.new()
	encounter.obstacle_mask = WORLD_LAYER
	encounter.use_navigation_mesh = use_navigation
	encounter.ranged_preferred_spacing = 1.8
	encounter.ranged_reposition_clear_shooters = true
	encounter.ranged_candidates_per_step = 24
	encounter.ranged_paths_per_step = 4
	apply_encounter_attack_rating(encounter, rating)
	if is_instance_valid(target):
		encounter.register_target(target)
	return encounter

static func apply_encounter_attack_rating(encounter: AIEncounter3D, rating: int) -> void:
	var rating_offset := float(maxi(1, rating) - 1)
	var melee_limit := 1 + mini(2, floori(rating_offset / 4.0))
	var ranged_limit := 1 + mini(1, floori(rating_offset / 5.0))
	encounter.attack_rules = {
		MELEE_ATTACK_CATEGORY: {"threshold": float(melee_limit) - 0.5, "grace": 0.60, "decay": 3.65, "reset": 0.14},
		RANGED_ATTACK_CATEGORY: {"threshold": float(ranged_limit) - 0.5, "grace": 0.60, "decay": 3.7, "reset": 0.14},
	}

func configure_ai(encounter: AIEncounter3D, pacing: Node = null) -> void:
	_encounter = encounter
	_encounter_pressure = pacing

func _ensure_encounter() -> void:
	if is_instance_valid(_encounter):
		return
	# Standalone actors and fixtures use the same native coordinator without a nav region.
	if _pack_group.is_empty():
		_encounter = create_ai_encounter(1, _player, false)
		add_child(_encounter)
		return
	var owner_node := get_parent()
	if owner_node.has_meta(_pack_group):
		_encounter = owner_node.get_meta(_pack_group) as AIEncounter3D
	if not is_instance_valid(_encounter):
		_encounter = create_ai_encounter(1, _player, false)
		owner_node.set_meta(_pack_group, _encounter)
		owner_node.add_child.call_deferred(_encounter)

func _bind_behavior() -> void:
	_brain.set_value(&"attack_driver", _drive_attack)
	_brain.set_value(&"move_driver", _drive_movement)
	_brain.set_value(&"patrol_driver", _drive_patrol)
	_brain.set_value(&"has_patrol", not _patrol_route.is_empty())
	_brain.set_value(&"patrol_route", _patrol_route)

func _exit_tree() -> void:
	if is_instance_valid(_brain):
		_finish_attack_cast(&"cast_cancel", "Left the encounter")
		_brain.reset()
		_bind_behavior()
	if is_instance_valid(_encounter):
		_encounter.release_agent(self)


func _ready() -> void:
	if _spec.is_empty():
		setup(null, 1, "normal", RandomNumberGenerator.new())
	name = archetype_name
	if health < max_health:
		_last_hurt = REGENERATION_DELAY
	add_to_group("enemies")
	if _pack >= 0:
		_pack_group = StringName("enemy_pack_%d_%d" % [get_parent().get_instance_id(), _pack])
		add_to_group(_pack_group)
	collision_layer = ENEMY_LAYER
	_world_ray.collision_mask = WORLD_LAYER
	collision_mask = WORLD_LAYER | PLAYER_LAYER | ENEMY_LAYER
	floor_snap_length = 0.22
	_hitbox = $BodyCollision
	var authored_shape := _hitbox.shape as CapsuleShape3D
	_living_shape = authored_shape.duplicate() as CapsuleShape3D
	_living_shape.height *= _size_multiplier
	_living_shape.radius *= _size_multiplier
	_living_hitbox_position = _hitbox.position + Vector3.UP * (_living_shape.height - authored_shape.height) * 0.5
	_hitbox.shape = _living_shape
	_hitbox.position = _living_hitbox_position
	_model = $Model as EnemyModel
	_model.scale *= _size_multiplier
	_model.configure(rarity)
	_make_indicators()
	_ensure_encounter()
	_initialize_patrol()
	_brain = AIBehaviorRunner.new()
	_brain.name = "Brain"
	_brain.tree = EnemyTree
	add_child(_brain)
	_bind_behavior()
	if is_cocoon():
		_show_cocoon()
		_emit_cast(&"cast_start", _combat_ability("cocoon"), "", "Hatching resumed from checkpoint")

func _initialize_patrol() -> void:
	if _patrol_points.size() < 2:
		return
	var nearest := 0
	for index in range(1, _patrol_points.size()):
		if global_position.distance_squared_to(_patrol_points[index]) < global_position.distance_squared_to(_patrol_points[nearest]):
			nearest = index
	if global_position.distance_squared_to(_patrol_points[nearest]) > 36.0:
		return
	var authored := _patrol_points.duplicate()
	if nearest == authored.size() - 1:
		authored.reverse()
	for point in authored:
		_patrol_route.append({"position": point, "wait": 0.36 + _rest_offset})

func _process(_delta: float) -> void:
	if _dead or not _bar:
		return
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	if not camera:
		return
	var to_bar := _bar.global_position - camera.global_position
	if to_bar.length_squared() > 625.0:
		return
	var depth := -camera.global_basis.z.dot(to_bar)
	var in_front := depth > maxf(camera.near, 0.15)
	_bar.visible = in_front
	_title.visible = in_front and _engaged and not is_cocoon()
	if not in_front:
		return
	var depth_factor := 1.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else depth
	var projection_scale := absf(camera.get_camera_projection().y.y)
	var projection_height := viewport.get_visible_rect().size.y * projection_scale
	var world_width := 2.0 * HEALTH_BAR_MAX_PIXELS * depth_factor / maxf(projection_height, 1.0)
	var ratio := minf(1.0, world_width / (_bar.mesh as QuadMesh).size.x)
	if not is_equal_approx(_bar.scale.x, ratio):
		_bar.scale = Vector3.ONE * ratio
		_title.scale = _bar.scale
		_title.position.y = _bar.position.y + INDICATOR_GAP * ratio

func take_damage(amount: float, damage_type: String = "physical", source: Node3D = null,
		hit_point := Vector3.INF, impact_direction := Vector3.ZERO, weapon_contact: Dictionary = {}) -> float:
	return take_hit({damage_type: amount}, source, hit_point, impact_direction, weapon_contact).dealt


func take_hit(damage_by_type: Dictionary, source: Node3D, hit_point := Vector3.INF,
		impact_direction := Vector3.ZERO, weapon_contact: Dictionary = {}) -> Dictionary:
	if _dead:
		return {"amount": 0, "dealt": 0.0, "physical": 0.0, "types": PackedStringArray(), "glancing": false}
	var total := 0.0
	var physical := 0.0
	var types := PackedStringArray()
	var level_factor := level_damage_factor(source)
	for damage_type: String in damage_by_type:
		var amount := _mitigate_damage(float(damage_by_type[damage_type]) * level_factor, damage_type)
		if amount <= 0.0:
			continue
		total += amount
		if damage_type == "physical":
			physical = amount
		types.append(damage_type.capitalize())
	# Apply all damage types as one hit, including when it kills or creates a cocoon.
	var resolved := DamageResolution.hit(total)
	var glancing := total > 0.0 and resolved == 0
	if glancing:
		_notice_hit(source)
	var dealt := _lose_life(resolved, source, hit_point, impact_direction, weapon_contact)
	return {"amount": resolved, "dealt": dealt, "physical": minf(physical, dealt),
		"types": types, "glancing": glancing}


func level_damage_factor(source: Node) -> float:
	if is_instance_valid(source) and source == _player and source.has_method("combat_ability_level"):
		return Progression.outgoing_multiplier(int(source.combat_ability_level()), enemy_level)
	return 1.0


func _mitigate_damage(amount: float, damage_type: String) -> float:
	var applied := amount
	if affixes.has("armored") and damage_type == "physical":
		applied *= 0.70
	if _statuses.has("shocked"):
		applied *= 1.0 + float(_statuses["shocked"]["potency"])
	return applied


func _notice_hit(source: Node3D) -> void:
	if is_instance_valid(_player) and source == _player:
		_record_encounter()
	if not _engaged:
		_engage()


func _lose_life(amount: int, source: Node3D, hit_point := Vector3.INF,
		impact_direction := Vector3.ZERO, weapon_contact: Dictionary = {}) -> float:
	if _dead or amount <= 0:
		return 0.0
	_notice_hit(source)
	var overkill := maxf(0.0, float(amount) - health)
	var dealt := minf(health, amount)
	health = maxf(0.0, health - amount)
	_last_hurt = REGENERATION_DELAY
	var cocoon := is_cocoon()
	if cocoon:
		_cocoon_visual.flash_hit()
	elif _model:
		_model.flash()
	_update_health_bar()
	var defeated := health <= 0.0
	var hatching_defense := (defeated and _has_cocoon and not cocoon
		and _ability_runtime.try_commit(_cocoon_ability, mana, _spend_mana))
	var direction := impact_direction
	if direction.is_zero_approx() and is_instance_valid(source):
		direction = (global_position - source.global_position).normalized()
	var resistance := _body_resistance() if defeated and not hatching_defense else 1.0
	if _model != null and not cocoon and hit_point.is_finite():
		CombatImpact.enemy(self, _model, hit_point, direction, amount, defeated and not hatching_defense,
			source, weapon_contact, overkill, resistance)
		if not defeated and bool(weapon_contact.get("can_stagger", true)):
			_model.react_to_hit(direction, bool(weapon_contact.get("heavy", false)))
	if hatching_defense:
		_begin_cocoon()
	elif defeated:
		_die(source, direction, weapon_contact, overkill, resistance)
	else:
		on_surviving_damage()
	return dealt

func apply_status(status_name: String, duration: float, potency: float, source: Node3D = null) -> void:
	if status_name == "poison":
		status_name = "poisoned"
	if status_name == "freeze":
		status_name = "chilled"
	var effect := Statuses.get_effect(status_name)
	if effect != null:
		receive_combat_effect(effect, duration, potency, source, {})


func has_combat_effect(id: String) -> bool:
	return _statuses.has(id)


func is_stunned() -> bool:
	return _stun.is_stunned()


func receive_stun_impact(amount: float, source: Node, ability: Dictionary = {}) -> bool:
	if amount <= 0.0 or _resists_stun():
		return false
	var source_level := int(source.combat_ability_level()) if is_instance_valid(source) \
		and source.has_method("combat_ability_level") else enemy_level
	var source_power := float(source.combat_stun_power()) if is_instance_valid(source) \
		and source.has_method("combat_stun_power") else 0.0
	var buildup := amount * Progression.outgoing_multiplier(source_level, enemy_level)
	var duration := _stun.add_impact(buildup, stun_threshold, source_power,
		StunRuntime.ENEMY_BASE_DURATION, StunRuntime.ENEMY_MAX_DURATION)
	return _present_stun(duration, source, ability)


func _resists_stun() -> bool:
	if _dead or is_cocoon():
		return true
	var ability := _attack_ability.get("definition") as AbilityDefinition
	return ability != null and ability.uninterruptible and _attack_phase != AttackPhase.READY \
		and _attack_phase != AttackPhase.RECOVERY


func _present_stun(duration: float, source: Node, ability: Dictionary) -> bool:
	if duration <= 0.0:
		return false
	_planned_velocity = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	_strike_time = -1.0
	if is_instance_valid(_brain):
		# The native task observes this condition and cancels its cast before the next commit.
		_set_brain_flag(&"stunned", true)
	var previous := _stun_visual
	_stun_visual = {"effect": StunnedEffect}
	CombatVisuals.apply_status(self, StunnedEffect, _stun_visual, previous, _status_visual_offset())
	_show_stun_icon()
	var player_source := is_instance_valid(source) and source == _player
	if player_source:
		CombatFloaters.outcome(get_parent() as Node3D, aim_point(), StunnedEffect.display_name)
	combat_event.emit({"kind": &"status", "side": &"player" if player_source else &"enemy",
		"actor": "Player" if player_source else str(ability.get("actor", display_name)), "target": display_name,
		"ability_id": StunnedEffect.id, "ability": StunnedEffect.display_name,
		"description": StunnedEffect.tooltip_description(), "detail": "Stunned for %.2f s" % duration})
	return true


func _show_stun_icon() -> void:
	if StunnedEffect.icon == null or not is_instance_valid(_bar):
		return
	if not is_instance_valid(_stun_icon):
		_stun_icon = EnemyStatusIcon.instantiate() as Sprite3D
		_stun_icon.name = "StunStatusIcon"
		_stun_icon.texture = StunnedEffect.icon
		_stun_icon.pixel_size = 0.16 / float(StunnedEffect.icon.get_height())
		_bar.add_child(_stun_icon)
	var clearance := 0.15 if affixes.is_empty() else 0.20
	_stun_icon.position = Vector3(0.20, INDICATOR_GAP + clearance, 0.0)
	_stun_icon.show()


func _end_stun_visual() -> void:
	if not _stun_visual.is_empty():
		CombatVisuals.end_status(self, _stun_visual, _status_visual_offset())
		_stun_visual.clear()
	if is_instance_valid(_stun_icon):
		_stun_icon.hide()


func receive_combat_effect(effect: EffectDefinition, duration: float, potency: float,
		source: Node, context: Dictionary) -> bool:
	if _dead or duration <= 0.0 or effect == null:
		return false
	var status_name := String(effect.id)
	var gap_factor := level_damage_factor(source)
	if not effect.damage_type.is_empty():
		# Bleed uses the original Physical hit. Other on-hit DoTs use damage already dealt.
		if effect is BleedEffectDefinition or not bool(context.get("potency_includes_level_gap", false)):
			potency *= gap_factor
	elif not effect.beneficial:
		duration *= gap_factor
		if duration < 0.05:
			if is_instance_valid(source) and source == _player:
				CombatFloaters.outcome(get_parent() as Node3D, aim_point(), "Resisted")
			return false
	if status_name == "stunned":
		if _resists_stun():
			return false
		return _present_stun(_stun.start(minf(duration, StunRuntime.ENEMY_MAX_DURATION)), source, context)
	var previous: Dictionary = _statuses.get(status_name, {})
	if not previous.is_empty():
		if effect is EnrageEffectDefinition and is_inf(float(previous["duration"])) and not is_inf(duration):
			return false
		if not effect.replaces(float(previous["potency"]), potency):
			return false
	var state := {
		"duration": duration,
		"potency": potency,
		"source": weakref(source) if is_instance_valid(source) else previous.get("source"),
		"effect": effect,
		"tick_elapsed": 0.0,
		"damage_remainder": previous.get("damage_remainder", 0.0),
	}
	_statuses[status_name] = state
	CombatVisuals.apply_status(self, effect, state, previous, _status_visual_offset())
	if previous.is_empty() and not effect.beneficial and is_instance_valid(source) and source == _player:
		CombatFloaters.outcome(get_parent() as Node3D, aim_point(), effect.display_name)
	if effect is BleedEffectDefinition:
		state["tick_elapsed"] = previous.get("tick_elapsed", 0.0)
		state["pending_damage"] = previous.get("pending_damage", 0.0)
		_show_bleed_icon(effect)
	if status_name == "rooted":
		velocity.x = 0.0
		velocity.z = 0.0
	return true


func _status_visual_offset() -> Vector3:
	return Vector3.UP * (COCOON_HEIGHT * 0.55 if is_cocoon() else _body_height * 0.56)


func _show_bleed_icon(effect: BleedEffectDefinition) -> void:
	if effect.icon != null and is_instance_valid(_bar):
		if _bleed_icon == null:
			_bleed_icon = EnemyStatusIcon.instantiate() as Sprite3D
			_bleed_icon.name = "BleedStatusIcon"
			_bar.add_child(_bleed_icon)
		_bleed_icon.texture = effect.icon
		_bleed_icon.pixel_size = 0.16 / float(effect.icon.get_height())
		var clearance := 0.15 if affixes.is_empty() else 0.20
		_bleed_icon.position.y = 0.16 if is_cocoon() else INDICATOR_GAP + clearance
		_bleed_icon.show()
	elif _bleed_icon != null:
		_bleed_icon.hide()


func _clear_statuses() -> void:
	for status: Dictionary in _statuses.values():
		CombatVisuals.end_status(self, status, _status_visual_offset())
	_statuses.clear()
	_stun.clear()
	_end_stun_visual()
	_affix_enrage_visual = CombatVisuals.sync_loop(self, _affix_enrage_visual, null, Vector3.ZERO, false)
	if _bleed_icon != null:
		_bleed_icon.hide()

func apply_impulse(direction: Vector3, strength: float) -> void:
	if not _dead and not is_cocoon():
		_impulse += Vector3(direction.x, 0.0, direction.z).normalized() * clampf(strength, 0.0, 4.5)
		_impulse = _impulse.limit_length(6.5)


func _body_resistance() -> float:
	if is_instance_valid(_hitbox) and _hitbox.shape is CapsuleShape3D:
		var shape := _hitbox.shape as CapsuleShape3D
		return ImpactFeedback.body_resistance(shape.radius, shape.height)
	return 1.0


func receive_blunt_knockback(direction: Vector3, damage: float, contact: Dictionary) -> bool:
	if _dead or is_cocoon() or _blunt_push_rearm > 0.0 or not direction.is_finite() \
			or not bool(contact.get("heavy", false)) or not WeaponRoles.is_blunt_contact(contact) \
			or contact.get("weapon_type", "") == "unarmed":
		return false
	var strength := ImpactFeedback.surviving_blunt_speed(damage / maxf(1.0, max_health),
		_body_resistance(), bool(contact.get("two_handed", false)))
	if strength <= 0.0 or _flat(direction).is_zero_approx():
		return false
	apply_impulse(direction, strength)
	_blunt_push_rearm = ImpactFeedback.enemy_push_reuse
	return true


func on_projectile_hit() -> void:
	if not _dead and not is_cocoon() and affixes.has("draining"):
		health = minf(max_health, health + max_health * 0.065)
		_update_health_bar()

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_blunt_push_rearm = maxf(0.0, _blunt_push_rearm - delta)
	_stun.advance(delta)
	if not _stun.is_stunned() and not _stun_visual.is_empty():
		_end_stun_visual()
	var was_cocoon := is_cocoon()
	_update_statuses(delta)
	if _dead:
		return
	if affixes.has("enraged"):
		_affix_enrage_visual = CombatVisuals.sync_loop(self, _affix_enrage_visual, RageEffect.enemy_while_active_fx,
			_status_visual_offset(), _enraged() and not is_cocoon() and _active_enrage() == null)
	var attack_delta := delta * _attack_speed_factor()
	_ability_runtime.advance(attack_delta)
	mana = minf(max_mana, mana + mana_regeneration * delta)
	if is_cocoon():
		if was_cocoon:
			_tick_cocoon(delta)
		return
	if not is_instance_valid(_player) or not is_instance_valid(_encounter):
		return
	var to_player := _flat(_player.global_position - global_position)
	var distance := to_player.length()
	var was_retreating := _ranged_retreat_until > _combat_time
	_combat_time += delta
	if not _engaged and distance > maxf(20.0, _sight_radius):
		return
	_recovery = maxf(0.0, _recovery - attack_delta)
	if _attack_phase == AttackPhase.READY and not _patterns.is_empty() and not _attack_is_ready(_move_id):
		_choose_profile()
	if _strike_time >= 0.0:
		_strike_time += attack_delta
		if _strike_time >= STRIKE_CLIP_SECONDS and _attack_phase != AttackPhase.AREA_TRACE:
			_strike_time = -1.0
	_route_timer -= delta
	_dashed_this_tick = false
	_windup_pose = 0.0
	_planned_velocity = Vector3.ZERO
	_decision_time -= delta
	if _decision_time <= 0.0 or (was_retreating and _combat_time >= _ranged_retreat_until):
		_decision_time = _decision_interval
		_sample_perception()
		if _engaged and (_attack_phase == AttackPhase.READY or _attack_phase == AttackPhase.RECOVERY):
			_update_tactical_goal(distance)

	if _has_thornback_guard:
		_update_thornback_guard(delta, distance)
	_publish_brain_facts(distance)
	_brain.tick(delta)
	if _dashed_this_tick:
		_model.animate(delta, 0.9, 0.0, _strike_progress())
		return

	var committed := _attack_phase == AttackPhase.WINDUP or _attack_phase == AttackPhase.SECOND_SHOT \
		or _attack_phase == AttackPhase.FOLLOW_UP or _attack_phase == AttackPhase.AREA_TRACE
	var locomotion := Vector3.ZERO
	if not _stun.is_stunned():
		locomotion = _planned_velocity if committed else _steer_locomotion(to_player, delta)
	var speed := _movement_speed()
	if _statuses.has("rooted"):
		speed = 0.0
	elif _statuses.has("chilled"):
		speed *= 1.0 - clampf(float(_statuses["chilled"]["potency"]), 0.15, 0.65)
	var desired := locomotion * speed + _impulse * (0.11 if committed else 1.0)
	var acceleration := ATTACK_ACCELERATION if committed else 19.0
	velocity.x = move_toward(velocity.x, desired.x, delta * acceleration)
	velocity.z = move_toward(velocity.z, desired.z, delta * acceleration)
	velocity.y = -0.08 if is_on_floor() else velocity.y - 18.0 * delta
	_impulse = _impulse.move_toward(Vector3.ZERO, delta * 12.0)
	move_and_slide()
	var stride := clampf(_flat(get_real_velocity()).length() / maxf(speed, 1.0), 0.0, 1.0)
	var strike := _strike_progress()
	_model.animate(delta, stride, _windup_pose, strike)

func _sample_perception() -> void:
	var distance := global_position.distance_to(_player.global_position)
	var sight_limit := TRACKING_SIGHT_RANGE if _engaged else maxf(_sight_radius, DISCOVERY_RANGE)
	_sight = distance <= sight_limit and _has_sight()
	if _sight:
		_brain.set_value(&"target_position", _player.global_position)
		if not _encountered and distance <= DISCOVERY_RANGE:
			_record_encounter()
	if _sight and not _engaged and distance <= _sight_radius:
		_engage()
	if _engaged:
		var target := _encounter.select_target(self, _target, _melee_ring, not _ranged)
		if target != _target:
			_ranged_retreat_until = -1.0
		_target = target

func _update_thornback_guard(delta: float, distance: float) -> void:
	if is_thornback_reflecting():
		_thornback_guard_remaining -= delta
		if _thornback_guard_remaining <= 0.000001:
			_end_thornback_guard()
		return
	if not _engaged or not _sight or distance > _alert_radius or _stun.is_stunned():
		return
	_thornback_guard_warmup = maxf(0.0, _thornback_guard_warmup - delta)
	if _thornback_guard_warmup <= 0.0 and _ability_runtime.try_commit(_guard_ability, mana, _spend_mana,
			_guard_ability.cooldown + _rest_offset * 10.0):
		_thornback_guard_remaining = float(_guard_profile["duration"])
		_model.set_thornback_reflecting(true)
		_thornback_guard_visual = CombatVisuals.sync_loop(self, _thornback_guard_visual,
			Feedback.thornback_guard_loop, _status_visual_offset(), true)
		_emit_cast(&"cast_start", _combat_ability("thornback_guard"), "", "Melee reflection active")

func _end_thornback_guard(defeated := false) -> void:
	_thornback_guard_remaining = 0.0
	_model.set_thornback_reflecting(false)
	_thornback_guard_visual = CombatVisuals.sync_loop(self, _thornback_guard_visual, null, Vector3.ZERO, false)
	_emit_cast(&"cast_cancel" if defeated else &"cast_end", _combat_ability("thornback_guard"), "",
		"Thornback defeated" if defeated else "Reflection expired")

func _publish_brain_facts(distance: float) -> void:
	var awake := _engaged and is_instance_valid(_target) and _encounter.is_target_valid(_target)
	_set_brain_flag(&"combat_awake", awake)
	_set_brain_flag(&"target_visible", _sight)
	_set_brain_flag(&"stunned", _stun.is_stunned())
	_set_brain_flag(&"has_move_goal", _has_move_goal)
	var attack_ready := awake and _attack_phase == AttackPhase.READY and _recovery <= 0.0 \
		and (_can_cast_cobweb(distance) or (_attack_is_ready(_move_id) and distance <= _attack_trigger() and _can_commit_here()))
	_set_brain_flag(&"attack_ready", attack_ready)

func _set_brain_flag(key: StringName, value: bool) -> void:
	if _brain.get_value(key, false) != value:
		_brain.set_value(key, value)

func _attack_trigger() -> float:
	return float(_profile.get("start", 0.0)) * (1.0 if _is_projectile_attack() else _attack_scale())

func _is_projectile_attack() -> bool:
	return _profile.get("shape", "") == "ray"

func _can_commit_here() -> bool:
	if not _sight or not _encounter.can_attack(_target, _attack_category()):
		return false
	if _is_projectile_attack():
		return _shooting_lane if _ranged else true
	return _encounter.owns_melee_slot(self, _target)

func _can_cast_cobweb(distance: float) -> bool:
	return _has_cobweb and _ability_runtime.can_start(_cobweb_ability, mana) and distance <= float(_cobweb_profile["start"]) \
		and _sight and _target.has_method("is_cobweb_rooted") and not _target.is_cobweb_rooted() \
		and _encounter.can_attack(_target, RANGED_ATTACK_CATEGORY)

func _attack_category() -> StringName:
	return RANGED_ATTACK_CATEGORY if _is_projectile_attack() else MELEE_ATTACK_CATEGORY

func _update_tactical_goal(distance: float) -> void:
	_has_move_goal = false
	_shooting_lane = false
	if not is_instance_valid(_target):
		return
	if _ranged and _is_projectile_attack():
		var max_range := _attack_trigger()
		var preferred_range := minf(_ranged_preferred_range, max_range)
		if distance >= preferred_range + RANGED_RETREAT_REARM_MARGIN:
			_ranged_retreat_until = -1.0
		elif distance < preferred_range and _ranged_retreat_until < 0.0:
			_ranged_retreat_until = _combat_time + _ranged_retreat_duration
		# Once the retreat is spent, the muzzle check can approve a shot from up close.
		var hold_position := _ranged_retreat_until >= 0.0 and _combat_time >= _ranged_retreat_until
		var min_range := 0.0 if hold_position else preferred_range
		var lane := _encounter.update_ranged_position(self, _target, min_range, max_range,
			WORLD_LAYER | PLAYER_LAYER, _body_height * 0.61, 1.05, RID(), 1, _recovery > 0.0 and not hold_position)
		_shooting_lane = bool(lane.get("can_fire", false))
		if lane.get("found", false):
			_set_move_goal(lane["position"])
	else:
		var slot := _encounter.update_position(self, _target, _melee_ring)
		var status: StringName = slot.get("status", &"invalid_target")
		if status in [&"slot", &"side_approach"]:
			_set_move_goal(_melee_attack_position(slot, distance))
		elif status in [&"queue", &"fallback", &"yielding"]:
			_set_move_goal(slot["position"])
		elif status == &"pending" and slot.get("has_slot", false):
			_set_move_goal(slot["slot_position"])
	if not _has_move_goal and not _sight:
		var remembered: Vector3 = _brain.get_value(&"last_seen_position", _contact_point)
		_set_move_goal(remembered if _brain.get_value(&"has_last_seen_position", false) else _contact_point)
	elif not _has_move_goal and not _ranged and distance > _attack_trigger():
		_set_move_goal(_target.global_position)

func _melee_attack_position(slot: Dictionary, distance: float) -> Vector3:
	var goal: Vector3 = slot["position"]
	if not _sight or _is_projectile_attack() or not slot["has_slot"]:
		return goal
	var center := _target.global_position
	var slot_offset := _flat(slot["slot_position"] - center)
	var start_range := _attack_trigger()
	if slot_offset.length_squared() <= start_range * start_range:
		return goal
	var approach_radius := maxf(0.0, start_range - ARRIVAL_DISTANCE)
	if slot["status"] == &"slot":
		# Keep the claimed bearing and close past a ring slot outside this attack's start range.
		return goal + slot_offset.limit_length(approach_radius) - slot_offset
	if distance <= start_range + ARRIVAL_DISTANCE:
		# Preserve contact through recovery when a moving target invalidates the old side waypoint.
		return Vector3(center.x, goal.y, center.z) + _flat(global_position - center).limit_length(approach_radius)
	return goal


func _set_move_goal(goal: Vector3) -> void:
	if not goal.is_finite():
		return
	_tactical_goal = goal
	_has_move_goal = _flat(goal - global_position).length_squared() > ARRIVAL_DISTANCE * ARRIVAL_DISTANCE
	if _has_move_goal and _brain.get_value(&"move_goal") != goal:
		_brain.set_value(&"move_goal", goal)

func _drive_movement(command: StringName, _initial_goal: Variant, reason: StringName) -> Variant:
	match command:
		&"step":
			return _move_toward(_tactical_goal, 1.0)
		&"recover":
			var rejected_goal := _tactical_goal
			if _ranged:
				_encounter.reject_ranged_position(self, rejected_goal)
			else:
				_encounter.report_melee_stuck(self)
			_route_timer = 0.0
			_update_tactical_goal(_flat(_player.global_position - global_position).length())
			if _has_move_goal:
				return _tactical_goal
		&"stop":
			_planned_velocity = Vector3.ZERO
			if reason == &"failed":
				_route_timer = 0.0
				_has_move_goal = false
	return null

func _drive_patrol(command: StringName, context: Dictionary) -> int:
	if command == &"stop":
		_planned_velocity = Vector3.ZERO
		return AIBehaviorRunner.SUCCESS
	var motion := _move_toward(context["goal"], 0.46)
	match motion["status"]:
		&"arrived":
			return AIBehaviorRunner.SUCCESS
		&"blocked":
			return AIBehaviorRunner.FAILURE
	return AIBehaviorRunner.RUNNING

func _move_toward(goal: Vector3, speed_fraction: float) -> Dictionary:
	var offset := _flat(goal - global_position)
	if offset.length_squared() <= ARRIVAL_DISTANCE * ARRIVAL_DISTANCE:
		return {"status": &"arrived"}
	if _route.is_valid() and (_route_timer <= 0.0 or _path_goal.distance_squared_to(goal) > 0.72):
		_path_goal = goal
		_refresh_move_path(goal)
		_route_timer = 0.48
		if _waypoints.is_empty():
			return {"status": &"blocked"}
	while _waypoint_index < _waypoints.size():
		var next := _flat(_waypoints[_waypoint_index] - global_position)
		if next.length_squared() > ARRIVAL_DISTANCE * ARRIVAL_DISTANCE:
			_planned_velocity = next.normalized() * speed_fraction
			var remaining := next.length() + _waypoint_tail[_waypoint_index]
			return {"status": &"moving", "remaining": remaining}
		_waypoint_index += 1
	if _route.is_valid() and _waypoints.is_empty():
		return {"status": &"waiting"}
	_planned_velocity = offset.normalized() * speed_fraction
	return {"status": &"moving", "remaining": offset.length()}

func _refresh_move_path(goal: Vector3) -> void:
	var direct := _flat(goal - global_position)
	if not test_move(global_transform, direct):
		_waypoints = PackedVector3Array([goal])
	else:
		_waypoints = _route.call(global_position, goal)
	_waypoint_index = 0
	_waypoint_tail.resize(_waypoints.size())
	var distance := 0.0
	for index in range(_waypoints.size() - 1, -1, -1):
		_waypoint_tail[index] = distance
		if index > 0:
			distance += _flat(_waypoints[index] - _waypoints[index - 1]).length()

func _drive_attack(command: StringName, context: Dictionary) -> StringName:
	if command == &"stop":
		_finish_attack_cast(&"cast_cancel", "Stunned" if _stun.is_stunned() else "Interrupted")
		_release_attack_claim()
		_reset_attack()
		return &"success"
	var delta := float(context["delta"])
	var attack_delta := delta * _attack_speed_factor()
	match context["phase"]:
		&"telegraph":
			if context["first"]:
				if not _admit_attack():
					return &"failure"
				_begin_attack(_flat(_target.global_position - global_position).normalized())
				if _windup_total == 0.0:
					# The native task advances one phase per tick. Resolve this hit now and keep its cooldown.
					_turn(_windup_toward, 1.0)
					if not _release_attack():
						return &"failure"
					if _attack_phase != AttackPhase.DASH and _attack_phase != AttackPhase.SECOND_SHOT \
							and _attack_phase != AttackPhase.FOLLOW_UP:
						_start_recovery()
					return &"success"
			var windup_delta := delta if _floor_warning_locked else attack_delta
			_windup_pose = _advance_windup(windup_delta, _flat(_target.global_position - global_position))
			return &"success" if _attack_remaining <= 0.0 else &"running"
		&"commit":
			var releasing := bool(context["first"]) and _attack_phase == AttackPhase.WINDUP
			if releasing and not _release_attack():
				return &"failure"
			if _attack_phase == AttackPhase.DASH:
				_dashed_this_tick = true
				return &"success" if _advance_dash(delta) else &"running"
			if _attack_phase == AttackPhase.AREA_TRACE:
				return &"success" if _advance_area_trace() else &"running"
			if _attack_phase == AttackPhase.SECOND_SHOT:
				_attack_remaining -= attack_delta
				if _attack_remaining > 0.0:
					return &"running"
				if _has_sight():
					_strike_time = 0.0
					_finish_attack_cast(&"cast_end")
					_fire_volley()
				else:
					_finish_attack_cast(&"cast_cancel", "Second shot lost line of sight")
			elif _attack_phase == AttackPhase.FOLLOW_UP:
				if not releasing:
					_attack_remaining -= attack_delta
				if _attack_remaining > 0.000001:
					return &"running"
				_attack_origin = global_position
				_strike_time = 0.0
				if _trace_markers != null:
					_start_area_trace()
					return &"running"
				_resolve_area_attack()
			return &"success"
		&"recover":
			if context["first"] and _attack_phase != AttackPhase.RECOVERY:
				_start_recovery()
			if _windup_total == 0.0:
				return &"success"
			if _recovery <= 0.0:
				return &"success"
			if _has_move_goal:
				_move_toward(_tactical_goal, 0.85)
			return &"running"
	return &"failure"

func _admit_attack() -> bool:
	var distance := _flat(_target.global_position - global_position).length()
	var use_cobweb := _can_cast_cobweb(distance)
	if not use_cobweb and (not _attack_is_ready(_move_id) or distance > _attack_trigger() or not _can_commit_here()):
		return false
	if not use_cobweb and float(_profile["windup"]) == 0.0 and not _has_sight():
		return false
	var cost := 1.0
	if is_instance_valid(_encounter_pressure):
		cost = _encounter_pressure.attack_cost_multiplier()
	if not use_cobweb:
		cost *= float(_profile.get("attack_cost", 1.0))
	var category := RANGED_ATTACK_CATEGORY if use_cobweb else _attack_category()
	if not _encounter.try_begin_attack(_target, category, cost):
		return false
	_casting_cobweb = use_cobweb
	if not _is_projectile_attack() and not _casting_cobweb:
		_encounter.set_slot_locked(self, true)
		_attack_claim = true
	return true

func _release_attack_claim() -> void:
	if _attack_claim and is_instance_valid(_encounter):
		_encounter.set_slot_locked(self, false)
	_attack_claim = false


func _begin_attack(direction: Vector3) -> void:
	_attack_phase = AttackPhase.WINDUP
	_windup_toward = direction if direction != Vector3.ZERO else -global_basis.z
	var ability := _cast_definition()
	var base_damage_type := ability.damage_type if not ability.damage_type.is_empty() else "physical"
	var elements_count := _attack_elements.size()
	if elements_count > 1 and base_damage_type == "physical":
		var has_innate_effect := ability.on_hit_effects.any(func(effect: EffectDefinition):
			return effect != null and effect.chance > 0.0 and effect.minimum_on_hit_level() == 1
		)
		if not has_innate_effect:
			elements_count -= 1
	_selected_element = _attack_elements[_attack_serial % elements_count]
	_selected_damage_type = base_damage_type if _selected_element.x < 0 else DAMAGE_TYPES[_selected_element.x]
	var windup: float = _cobweb_profile["windup"] if _casting_cobweb else _profile["windup"]
	_windup_total = windup * _windup_multiplier
	if affixes.has("quick"):
		_windup_total *= 0.91
	if _enraged():
		_windup_total *= 0.90
	if windup > 0.0:
		_windup_total = maxf(minf(0.35, windup), _windup_total)
	_floor_warning_locked = not _casting_cobweb and _profile_warns_on_floor()
	if _floor_warning_locked:
		_warning_footprint = _profile.duplicate()
		for dimension in ["reach", "width", "inner_radius"]:
			if _warning_footprint.has(dimension):
				_warning_footprint[dimension] *= _attack_scale()
		var exit_distance := Telegraph.escape_distance(_warning_footprint)
		_windup_total = TelegraphRules.warning_seconds(_windup_total / _attack_speed_factor(), exit_distance, _player)
	_attack_remaining = _windup_total
	_swing_steps_in = not _casting_cobweb and not _floor_warning_locked and _profile.get("shape", "") == "arc"
	_swing_step_started = false
	_swing_step_origin = global_position
	_planned_velocity = Vector3.ZERO
	velocity.x *= 0.20
	velocity.z *= 0.20
	_attack_origin = global_position
	_aim_position = _predict_target()
	if _casting_cobweb:
		if not _cobweb_windup:
			_cobweb_windup = Cobweb.windup_visual()
			_cobweb_windup.position = Vector3(0.0, _body_height * 0.61, -0.31)
			add_child(_cobweb_windup)
		_cobweb_windup.scale = Vector3.ONE * 0.08
		_cobweb_windup.show()
	elif _floor_warning_locked:
		_show_ground_warning(_warning_footprint, _floor_warning_origin(), _windup_toward)
	_attack_ability = _combat_ability("cobweb" if _casting_cobweb else _move_id)
	_model.select_attack_animation(ability.id)
	if _floor_warning_locked:
		_attack_ability["unblockable"] = true
	_attack_cast_open = true
	_emit_cast(&"cast_start", _attack_ability, "Player")

func _advance_windup(delta: float, to_player: Vector3) -> float:
	_attack_remaining = maxf(0.0, _attack_remaining - delta)
	var fraction := 1.0 - _attack_remaining / _windup_total
	# The player can read and step out of the final committed direction.
	var aim_projectile := _is_projectile_attack() or _casting_cobweb
	var lock_fraction := 0.72 if _swing_steps_in else (0.66 if _casting_cobweb else 0.52)
	var tracks_target := _attack_remaining > PROJECTILE_AIM_LOCK_SECONDS * _attack_speed_factor() \
		if _is_projectile_attack() and not _casting_cobweb else fraction < lock_fraction
	if tracks_target and not _floor_warning_locked:
		_aim_position = _predict_target()
		var track := _flat(_aim_position - global_position).normalized() if aim_projectile else to_player.normalized()
		if _swing_steps_in:
			# Lead ordinary swings during windup. The final direction stays locked through the strike.
			var lead := _player_ground_velocity() * minf(0.16, _attack_remaining + 0.08)
			track = (to_player + lead.limit_length(0.48)).normalized()
		if track != Vector3.ZERO:
			var track_speed := 20.0 if _swing_steps_in else 12.0
			_windup_toward = _windup_toward.slerp(track, minf(1.0, delta * track_speed)).normalized()
	if _swing_steps_in and fraction >= 0.12 and to_player.length_squared() > 0.95 * 0.95:
		# A foe can step after retreat, but cannot start a new pursuit after committing the swing.
		if not _swing_step_started and fraction < 0.45:
			_swing_step_started = to_player.normalized().dot(_player_ground_velocity()) > 0.65
		if _swing_step_started:
			_step_into_swing()
	_turn(_windup_toward, delta * 1.4)
	if not _floor_warning_locked:
		_attack_origin = global_position
	if _attack_warning and _attack_warning.visible:
		_set_warning_progress(fraction)
	if _casting_cobweb:
		_cobweb_windup.scale = Vector3.ONE * lerpf(0.08, 0.31, fraction)
	return fraction

func _step_into_swing() -> void:
	var remaining := maxf(0.0, SWING_STEP_DISTANCE - _flat(global_position - _swing_step_origin).length())
	var movement_speed := _movement_speed()
	if movement_speed > 0.0 and remaining > 0.0:
		# Slow down near the end of the step so a swing cannot become a dash.
		var speed := minf(minf(SWING_STEP_SPEED, movement_speed * 1.6), sqrt(2.0 * ATTACK_ACCELERATION * remaining))
		_planned_velocity = _windup_toward * (speed / movement_speed)

func _cast_definition() -> AbilityDefinition:
	return _cobweb_ability if _casting_cobweb else _abilities_by_id.get(_move_id)

func _release_attack() -> bool:
	var ability := _cast_definition()
	var area: bool = not _casting_cobweb and _profile["shape"] in ["arc", "disc", "ring"]
	_trace_markers = AttackAnimation.read(_model.strike_clip()) as AttackAnimation \
		if area and _windup_total > 0.0 else null
	if _trace_markers == null and not _commit_attack_cost(ability):
		return false
	if not _floor_warning_locked:
		_attack_origin = global_position
	_strike_time = 0.0
	if _casting_cobweb:
		_finish_attack_cast(&"cast_end")
		_fire_cobweb()
	elif _is_projectile_attack():
		var has_sight := _has_sight()
		if _profile.has("second"):
			_attack_phase = AttackPhase.SECOND_SHOT
			_attack_remaining = float(_profile["second"])
		elif has_sight:
			_finish_attack_cast(&"cast_end")
		else:
			_finish_attack_cast(&"cast_cancel", "Lost line of sight")
		if has_sight:
			_fire_volley()
	elif _profile["shape"] == "lane":
		_attack_phase = AttackPhase.DASH
		_dash_travel = 0.0
	else:
		if _trace_markers != null:
			_start_area_trace()
			return true
		_follow_up_delay = ability.roll_follow_up_delay(_attack_rng)
		_finish_attack_cast(&"cast_end")
		_resolve_area_attack()
		_queue_follow_up()
	if _attack_warning:
		_attack_warning.hide()
	return true

func _commit_attack_cost(ability: AbilityDefinition) -> bool:
	if _ability_runtime.try_commit(ability, mana, _spend_mana):
		return true
	_finish_attack_cast(&"cast_cancel", "Ability unavailable")
	return false

func _strike_progress() -> float:
	return clampf(_strike_time / STRIKE_CLIP_SECONDS, 0.0, 1.0) if _strike_time >= 0.0 else -1.0

func _start_area_trace() -> void:
	_attack_phase = AttackPhase.AREA_TRACE
	_area_contacted = false
	_area_hit = false

func _advance_area_trace() -> bool:
	var clip_time := _trace_markers.at_elapsed(_strike_time, STRIKE_CLIP_SECONDS)
	if clip_time < _trace_markers.trace_start:
		return false
	if _attack_cast_open:
		var ability := _cast_definition()
		if not _commit_attack_cost(ability):
			return true
		_follow_up_delay = ability.roll_follow_up_delay(_attack_rng)
		if _attack_warning:
			_attack_warning.hide()
		_finish_attack_cast(&"cast_end")
	if not _area_contacted:
		_area_contacted = _area_attack_contains_player() and _has_sight()
		if _area_contacted:
			_area_hit = _damage_player()
	if clip_time < _trace_markers.trace_end:
		return false
	_draw_area_trace(_area_hit)
	return not _queue_follow_up()

func _queue_follow_up() -> bool:
	if _follow_up_delay < 0.0:
		return false
	_attack_phase = AttackPhase.FOLLOW_UP
	_attack_remaining = maxf(0.0, _follow_up_delay - _strike_time)
	_follow_up_delay = -1.0
	return true

func _advance_dash(delta: float) -> bool:
	var range_limit := float(_profile["reach"]) * _attack_scale()
	var advance := minf(range_limit - _dash_travel, float(_profile["dash_speed"]) * delta)
	var previous := global_position
	var collision := move_and_collide(_windup_toward * advance)
	_dash_travel += _windup_toward.dot(_flat(global_position - previous))
	var offset := _flat(_target.global_position - _attack_origin)
	var forward := offset.dot(_windup_toward)
	var side := absf(offset.dot(_windup_toward.cross(Vector3.UP)))
	var reach := minf(range_limit, _dash_travel + 0.68)
	if collision != null and collision.get_collider() == _target:
		# The bodies can touch before their centers enter the proximity check.
		reach = minf(range_limit, maxf(reach, forward))
	var half_width := float(_profile["width"]) * _attack_scale()
	var contacts := forward >= -0.10 and forward <= reach and side <= half_width and _has_sight()
	if contacts and _floor_warning_locked:
		contacts = Telegraph.contains(_warning_footprint, _attack_origin, _windup_toward, _player.global_position)
	if not contacts and collision == null and _dash_travel < range_limit - 0.01 and advance >= 0.001:
		return false
	_finish_attack_cast(&"cast_end")
	var hit := contacts and _damage_player()
	if _ability_trace.is_valid():
		_ability_trace.call({
			"shape": "lane", "origin": _attack_origin + Vector3.UP * ABILITY_TRACE_HEIGHT - _windup_toward * 0.10,
			"direction": _windup_toward, "reach": reach + 0.10, "width": half_width, "hit": hit,
		})
	return true


func _resolve_area_attack() -> void:
	var landed := _area_attack_contains_player() and _has_sight() and _damage_player()
	_draw_area_trace(landed)

func _area_attack_contains_player() -> bool:
	if _floor_warning_locked:
		var origin := _floor_warning_origin()
		return (absf(_player.global_position.y - origin.y) < 0.96
			and Telegraph.contains(_warning_footprint, origin, _windup_toward, _player.global_position))
	var toward := _flat(_player.global_position - _attack_origin)
	var reach := float(_profile["reach"]) * _attack_scale()
	if _profile["shape"] == "disc":
		return (toward - _disc_center_offset()).length_squared() <= reach * reach
	var arc := cos(deg_to_rad(float(_profile["arc"])))
	return toward.length_squared() <= reach * reach and (toward.length_squared() < 0.01
		or toward.normalized().dot(_windup_toward) >= arc)

func _disc_center_offset() -> Vector3:
	return _windup_toward * float(_profile["offset"]) * _attack_scale()

func _draw_area_trace(hit: bool) -> void:
	if _ability_trace.is_valid():
		var shape: String = _profile["shape"]
		var center := _disc_center_offset() if shape == "disc" else Vector3.ZERO
		_ability_trace.call({
			"shape": shape, "origin": _attack_origin + center + Vector3.UP * ABILITY_TRACE_HEIGHT,
			"direction": _windup_toward, "reach": float(_profile["reach"]) * _attack_scale(),
			"angle": float(_profile.get("arc", 0.0)), "inner_radius": float(_profile.get("inner_radius", 0.0)) * _attack_scale(),
			"hit": hit,
		})

func _damage_player() -> bool:
	if _player.has_method("receive_enemy_hit"):
		var status: String = ATTACK_STATUSES[_selected_element.y]
		var hit_ability := _attack_ability
		var ability := _cast_definition()
		if ability != null and ability.knockback_speed > 0.0:
			var direction := _flat(_player.global_position - global_position)
			match _profile.get("shape", ""):
				"lane": direction = _windup_toward
				"disc": direction = _flat(_player.global_position - _floor_warning_origin())
			if direction.is_zero_approx():
				direction = _windup_toward
			hit_ability = hit_ability.merged({"push_direction": direction})
		if _player.receive_enemy_hit(_attack_damage(), _selected_damage_type, status, self, hit_ability) == true:
			on_projectile_hit()
			return true
	return false

func _attack_damage() -> float:
	var damage := EnemyStats.hit_damage(_base_damage, float(_profile["damage"]))
	var enrage := _active_enrage()
	return damage * (1.0 + _hatch_growth() * 0.80) * (1.31 if _enraged() else 1.0) \
		* (enrage.damage_factor() if enrage else 1.0)

func _active_enrage() -> EnrageEffectDefinition:
	var state: Variant = _statuses.get("enrage")
	return state["effect"] as EnrageEffectDefinition if state != null else null

func _attack_speed_factor() -> float:
	var enrage := _active_enrage()
	return enrage.attack_speed_factor() if enrage else 1.0

func _start_recovery() -> void:
	_attack_phase = AttackPhase.RECOVERY
	_release_attack_claim()
	_decision_time = 0.0
	var recovery: float = _cobweb_profile["recovery"] if _casting_cobweb else _profile["recovery"]
	_recovery = recovery
	if _windup_total > 0.0:
		_recovery = recovery * _recovery_multiplier + _rest_offset
		if _enraged():
			_recovery *= 0.89
	if not _casting_cobweb:
		_attack_serial += 1
		_choose_profile()

func _reset_attack() -> void:
	_attack_phase = AttackPhase.READY
	_attack_ability = {}
	_casting_cobweb = false
	_floor_warning_locked = false
	_attack_remaining = 0.0
	_trace_markers = null
	_follow_up_delay = -1.0
	_planned_velocity = Vector3.ZERO
	if _attack_warning:
		_attack_warning.hide()
	if _cobweb_windup:
		_cobweb_windup.hide()

func _choose_profile() -> void:
	if _patterns.is_empty():
		return
	var profile_count := 1 if enemy_level < int(_spec.get("additional_moves_level", 3)) else _patterns.size()
	_move_id = _patterns[_attack_serial % profile_count]
	var ready_attacks: Array[String] = []
	for offset in profile_count:
		var move: String = _patterns[(_attack_serial + offset) % profile_count]
		if _attack_is_ready(move):
			ready_attacks.append(move)
	if not ready_attacks.is_empty():
		var selected := select_attack(ready_attacks)
		_move_id = selected if selected in ready_attacks else ready_attacks[0]
	_profile = _attack_profiles[_move_id]

## Override in an enemy AI script to choose from its ready moves in rotation order.
func select_attack(ready_attacks: Array[String]) -> String:
	return ready_attacks[0]

func _attack_is_ready(move: String) -> bool:
	return _ability_runtime.can_start(_abilities_by_id.get(move), mana)

func _combat_ability(move: String) -> Dictionary:
	var ability_definition: AbilityDefinition = _abilities_by_id.get(move)
	if ability_definition == null:
		match move:
			"cobweb": ability_definition = _cobweb_ability
			"cocoon": ability_definition = _cocoon_ability
			"thornback_guard": ability_definition = _guard_ability
	var ability: Dictionary
	if _ability_details.is_valid():
		var move_or_definition: Variant = move
		if ability_definition != null:
			move_or_definition = ability_definition
		ability = _ability_details.call(archetype_id, move_or_definition)
	elif ability_definition != null:
		ability = ability_definition.combat_details()
	else:
		ability = {"name": move.capitalize(), "description": ""}
	if ability_definition != null:
		ability["id"] = ability_definition.id
		ability["definition"] = ability_definition
	ability["actor"] = display_name
	ability["source_level"] = enemy_level
	ability["stun_power"] = stun_power
	return ability

## While stunned, observe the outcome of the currently active damaging cast.
func on_next_damaging_cast_interrupted(callback: Callable) -> void:
	var ability := _attack_ability.get("definition") as AbilityDefinition
	if _attack_cast_open and is_stunned() and ability != null and ability.damage_multiplier > 0.0:
		_on_cast_interrupted = callback


func _finish_attack_cast(kind: StringName, detail := "") -> void:
	if not _attack_cast_open:
		return
	_attack_cast_open = false
	_emit_cast(kind, _attack_ability, "Player", detail)
	var interrupted := _on_cast_interrupted
	_on_cast_interrupted = Callable()
	if kind == &"cast_cancel" and detail == "Stunned" and interrupted.is_valid():
		interrupted.call(self)

func _emit_cast(kind: StringName, ability: Dictionary, target: String, detail := "") -> void:
	combat_event.emit({"kind": kind, "side": &"enemy", "actor": display_name, "target": target,
		"ability_id": ability.get("id", &""), "ability": ability["name"],
		"description": ability["description"], "detail": detail})

func _attack_scale() -> float:
	return 1.0 + (_size_multiplier - 1.0) * 0.65

func _profile_warns_on_floor() -> bool:
	return _profile.get("floor_warning", "") == "always"

func _show_ground_warning(profile: Dictionary, origin: Vector3, direction := Vector3.FORWARD) -> void:
	if not _attack_warning:
		_attack_warning = Telegraph.make_node()
		add_child(_attack_warning)
	Telegraph.present(_attack_warning, profile, origin, direction)

func _floor_warning_origin() -> Vector3:
	return _attack_origin + _disc_center_offset() if _profile["shape"] == "disc" else _attack_origin

func _set_warning_progress(fraction: float) -> void:
	Telegraph.set_progress(_attack_warning, fraction)

func _predict_target() -> Vector3:
	var target := _player.global_position + Vector3.UP * 1.05
	if _casting_cobweb or not _is_projectile_attack() or not _player is CharacterBody3D:
		return target
	var arrow_speed := float(_profile["speed"]) * _projectile_speed_multiplier
	var player_motion := _player_ground_velocity().limit_length(6.0)
	var seconds_per_tick := 1.0 / float(Engine.physics_ticks_per_second)
	var release_delay := minf(PROJECTILE_AIM_LOCK_SECONDS, _attack_remaining / _attack_speed_factor()) + seconds_per_tick
	var offset := _flat(target - global_position) + player_motion * release_delay
	# Solve |offset + velocity * travel| = arrow_speed * travel on the ground plane.
	var speed_difference := arrow_speed * arrow_speed - player_motion.length_squared()
	var travel := offset.length() / arrow_speed
	if speed_difference > 0.0:
		var along := offset.dot(player_motion)
		travel = (along + sqrt(along * along + speed_difference * offset.length_squared())) / speed_difference
	var prediction := (player_motion * (release_delay + travel * _projectile_lead_factor)).limit_length(_projectile_lead_limit)
	return target + prediction

func _player_ground_velocity() -> Vector3:
	return _flat(_player.get_real_velocity()) if _player is CharacterBody3D else Vector3.ZERO

func _fire_cobweb() -> void:
	_cobweb_windup.hide()
	var start := global_position + Vector3.UP * _body_height * 0.61 + _windup_toward * 0.28
	var web := CobwebProjectile.instantiate() as Node3D
	get_parent().add_child(web)
	web.launch(start, _aim_position, float(_cobweb_profile["speed"]), self, _player, float(_cobweb_profile["reach"]),
		_attack_ability, Cobweb.DEFAULT_ROOT_SECONDS, _ability_trace)

func _fire_volley() -> void:
	var start := global_position + Vector3.UP * _body_height * 0.61 + _windup_toward * 0.28
	var direction := start.direction_to(_aim_position)
	var spread := float(_profile.get("spread", 0.0))
	_spawn_projectile(start, direction)
	if spread > 0.0:
		for side in [-1.0, 1.0]:
			_spawn_projectile(start, direction.rotated(Vector3.UP, deg_to_rad(spread * side)), 0.74)

func _spawn_projectile(start: Vector3, direction: Vector3, damage_scalar := 1.0) -> void:
	var shot := ProjectilePool.take(get_parent())
	var attack_type := _selected_damage_type
	var status: String = ATTACK_STATUSES[_selected_element.y]
	var speed := float(_profile["speed"]) * _projectile_speed_multiplier
	shot.launch(start, start + direction, speed, _attack_damage() * damage_scalar, attack_type, status,
		self, _player, ELEMENT_COLORS[attack_type], float(_profile["reach"]) * 1.28, _attack_ability, _ability_trace)

func _record_encounter() -> void:
	if not _encountered:
		_encountered = true
		encountered.emit(self)

func _engage() -> void:
	if _engaged:
		return
	_engaged = true
	_contact_point = _player.global_position if is_instance_valid(_player) else global_position
	_target = _encounter.select_target(self, _target, _melee_ring, not _ranged) if is_instance_valid(_encounter) else null
	_planned_velocity = Vector3.ZERO
	if _pack_group.is_empty():
		return
	for member in get_tree().get_nodes_in_group(_pack_group):
		if member != self and not member._engaged:
			member._engaged = true
			member._contact_point = _contact_point
			member._planned_velocity = Vector3.ZERO
			member._recovery = maxf(member._recovery, member._rest_offset + 0.13)

func _steer_locomotion(to_player: Vector3, delta: float) -> Vector3:
	var moving := _planned_velocity.length_squared() > 0.002
	var face_player := not moving and _engaged and _sight
	var heading := to_player if face_player else _planned_velocity
	if heading.length_squared() <= 0.002:
		return _planned_velocity
	var goal_yaw := atan2(-heading.x, -heading.z)
	var yaw := rotate_toward(global_rotation.y, goal_yaw, deg_to_rad(turn_speed) * delta)
	global_rotation.y = yaw
	if face_player:
		return _planned_velocity
	# Plant the feet on sharp pivots, then build speed as the gait lines up with the path.
	var alignment := cos(angle_difference(yaw, goal_yaw))
	return _planned_velocity * smoothstep(0.707, 0.966, alignment)

func _turn(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.002:
		# The parent can be rotated. The committed direction is global.
		var angle := atan2(-direction.x, -direction.z)
		global_rotation.y = lerp_angle(global_rotation.y, angle, minf(delta * 11.0, 1.0))

func _has_sight() -> bool:
	var eye := global_position + Vector3.UP * _body_height * 0.67
	var target := _player.global_position + Vector3.UP * 1.11
	_world_ray.from = eye
	_world_ray.to = target
	return get_world_3d().direct_space_state.intersect_ray(_world_ray).is_empty()

func _select_affixes(rng: RandomNumberGenerator, selected_affixes: Array[String]) -> void:
	affixes.clear()
	_attack_elements.clear()
	var limit := Affixes.selection_limit(rarity)
	for affix in selected_affixes:
		if affixes.size() == limit:
			break
		if Affixes.AFFIX_NAMES.has(affix) and not affixes.has(affix):
			affixes.append(affix)
	if affixes.is_empty() and limit > 0:
		var choices: Array = Affixes.AFFIX_NAMES.keys()
		var amount := rng.randi_range(1, limit) if rarity == "rare" else limit
		for i in range(amount):
			var idx := rng.randi_range(0, choices.size() - 1)
			affixes.append(choices[idx])
			choices.remove_at(idx)
	_attack_elements.append(Vector2i(-1, 0))
	if affixes.has("frozen"):
		_attack_elements.push_front(Vector2i(2, 2))
	if affixes.has("incendiary"):
		_attack_elements.push_front(Vector2i(1, 5))
	if affixes.has("venomous"):
		_attack_elements.push_front(Vector2i(4, 4))

func _update_statuses(delta: float) -> void:
	if affixes.has("renewing") and health < max_health:
		_last_hurt = maxf(0.0, _last_hurt - delta)
		if _last_hurt <= 0.0:
			health = minf(max_health, health + max_health * 0.035 * delta)
			_update_health_bar()
	if _statuses.is_empty():
		return
	for key in _statuses.keys():
		var state: Dictionary = _statuses[key]
		var remaining := float(state["duration"])
		var elapsed := minf(remaining, delta)
		state["duration"] = remaining - elapsed
		var expired: bool = state["duration"] <= 0.000001
		var effect: EffectDefinition = state["effect"]
		if not effect.damage_type.is_empty():
			state["tick_elapsed"] = float(state["tick_elapsed"]) + elapsed
			state["pending_damage"] = float(state.get("pending_damage", 0.0)) + float(state["potency"]) * elapsed
			if expired or float(state["tick_elapsed"]) + 0.000001 >= effect.tick_interval:
				var source_ref: WeakRef = state.get("source")
				var source: Node3D = source_ref.get_ref() if source_ref else null
				var damage := float(state["pending_damage"])
				var point := aim_point()
				var player_source := is_instance_valid(source) and source == _player
				state["tick_elapsed"] = 0.0
				state["pending_damage"] = 0.0
				if effect is BleedEffectDefinition:
					damage = effect.mitigate_tick(damage, physical_dot_reduction)
				else:
					damage = _mitigate_damage(damage, effect.damage_type)
				var resolved := DamageResolution.tick(damage, state)
				var dealt := _lose_life(resolved, source)
				if dealt > 0.0 and player_source:
					CombatFloaters.damage(self, point, resolved, false, true)
					var detail := "%s · Damage over time" % effect.damage_type.capitalize()
					if not is_equal_approx(dealt, float(resolved)):
						detail += " · %s Life lost" % ("%.2f" % dealt).rstrip("0").rstrip(".")
					combat_event.emit({
						"kind": &"damage", "side": &"player", "actor": "Player", "target": display_name,
						"ability_id": effect.id, "ability": effect.display_name,
						"description": effect.tooltip_description(), "amount": resolved, "detail": detail,
					})
				if _dead or _statuses.is_empty():
					break
		if expired:
			CombatVisuals.end_status(self, state, _status_visual_offset())
			if effect is BleedEffectDefinition and _bleed_icon != null:
				_bleed_icon.hide()
			_statuses.erase(key)

func _enraged() -> bool:
	return affixes.has("enraged") and health <= max_health * 0.45

func _movement_speed() -> float:
	return _base_speed * (1.0 + _hatch_growth() * 0.55) * (1.18 if _enraged() else 1.0)

func _hatch_growth() -> float:
	# Each hatch adds strength, with diminishing gains over a long fight.
	var count := float(_hatches)
	return count / (count + 2.0)

func _moth_max_health() -> float:
	return _moth_life * (1.0 + _hatch_growth() * 0.85)

func _begin_cocoon() -> void:
	_finish_attack_cast(&"cast_cancel", "Transformed into a cocoon")
	_brain.reset()
	_bind_behavior()
	_release_attack_claim()
	_encounter.release_agent(self)
	_reset_attack()
	_target = null
	_has_move_goal = false
	velocity = Vector3.ZERO
	_impulse = Vector3.ZERO
	_clear_statuses()
	_cocoon_remaining = float(_cocoon_profile["hatch_seconds"])
	max_health = _moth_max_health() * float(_cocoon_profile["health_fraction"])
	health = max_health
	_show_cocoon()
	_emit_cast(&"cast_start", _combat_ability("cocoon"), "", "Hatching")
	metamorphosis_changed.emit()

func _show_cocoon() -> void:
	if not _cocoon_visual:
		_cocoon_visual = MothCocoon.instantiate() as MothCocoonVisual
		_cocoon_visual.name = "MothCocoon"
		add_child(_cocoon_visual)
	_cocoon_visual.show()
	_cocoon_visual.update_hatch(_cocoon_remaining, _cocoon_profile["hatch_seconds"])
	var shell_shape := CapsuleShape3D.new()
	shell_shape.radius = COCOON_RADIUS
	shell_shape.height = COCOON_HEIGHT
	_set_body_shape(shell_shape)
	_model.hide()
	_title.hide()
	_bar.position.y = COCOON_LIFE_BAR_HEIGHT
	_update_health_bar()

func _tick_cocoon(delta: float) -> void:
	_cocoon_remaining = maxf(0.0, _cocoon_remaining - delta)
	if _cocoon_remaining <= 0.000001:
		_hatch_moth()
		return
	_cocoon_visual.update_hatch(_cocoon_remaining, _cocoon_profile["hatch_seconds"])

func _hatch_moth() -> void:
	_cocoon_remaining = 0.0
	_hatches += 1
	max_health = _moth_max_health()
	health = max_health
	_clear_statuses()
	_attack_serial = 0
	_choose_profile()
	_strike_time = -1.0
	_recovery = 0.0
	_decision_time = 0.0
	_route_timer = 0.0
	_cocoon_visual.hide()
	_set_body_shape(_living_shape)
	_model.show()
	_bar.position.y = _body_height + 0.20
	_title.position.y = _bar.position.y + INDICATOR_GAP * _bar.scale.x
	_update_health_bar()
	_emit_cast(&"cast_end", _combat_ability("cocoon"), "", "Hatched")
	metamorphosis_changed.emit()

func _set_body_shape(shape: CapsuleShape3D) -> void:
	_hitbox.set_deferred("shape", shape)
	var hitbox_position := _living_hitbox_position if shape == _living_shape else Vector3.UP * shape.height * 0.5
	_hitbox.set_deferred("position", hitbox_position)

## Notify the run owner when authored behavior changes persistent enemy state.
func _notify_behavior_changed() -> void:
	behavior_changed.emit()

func _make_indicators() -> void:
	var indicator := EnemyIndicator.instantiate() as Node3D
	_bar = indicator.get_node("Health") as MeshInstance3D
	_title = indicator.get_node("Title") as Label3D
	_bar.position.y += _body_height + 0.20
	_title.position.y += _bar.position.y
	if rarity != "normal":
		_title.modulate = RARITY_COLORS[rarity]
	_title.hide()
	add_child(indicator)
	_bar.set_instance_shader_parameter("bar_color", RARITY_COLORS[rarity])
	_update_health_bar()
	refresh_level_label()


func refresh_level_label() -> void:
	if not is_instance_valid(_title):
		return
	var player_level := 1
	if is_instance_valid(_player) and _player.has_method("combat_ability_level"):
		player_level = int(_player.combat_ability_level())
	var danger := "☠ " if Progression.outgoing_multiplier(player_level, enemy_level) <= 0.05 else ""
	var title := "%s · %sLv %d" % [display_name, danger, enemy_level]
	var labels := PackedStringArray()
	if rarity != "magic" or display_name == archetype_name:
		for affix in affixes:
			labels.append(Affixes.AFFIX_NAMES[affix])
	_title.text = title if labels.is_empty() else "%s\n%s" % [title, " · ".join(labels)]


func _update_health_bar() -> void:
	if _bar:
		_bar.set_instance_shader_parameter("health_fraction", health / max_health)

func _die(source: Node3D, direction := Vector3.ZERO, weapon_contact: Dictionary = {},
		overkill := 0.0, body_resistance := 1.0) -> void:
	var corpse: Node3D = _model
	_finish_attack_cast(&"cast_cancel", "Defeated")
	if is_cocoon():
		_emit_cast(&"cast_cancel", _combat_ability("cocoon"), "", "Cocoon destroyed")
		_cocoon_visual.hide_hatch()
		corpse = _cocoon_visual
	if is_thornback_reflecting():
		_end_thornback_guard(true)
	_clear_statuses()
	_dead = true
	_brain.reset()
	if is_instance_valid(_encounter):
		_encounter.release_agent(self)
	_reset_attack()
	remove_from_group("enemies")
	if not _pack_group.is_empty():
		remove_from_group(_pack_group)
	set_physics_process(false)
	set_process(false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	var momentum := _flat(velocity).limit_length(1.5)
	var push := _flat(global_position - source.global_position) if is_instance_valid(source) else -global_basis.z
	if WeaponRoles.is_blunt_contact(weapon_contact):
		momentum += WeaponRoles.blunt_death_momentum(weapon_contact, direction, overkill, body_resistance)
	elif not push.is_zero_approx():
		momentum += push.normalized() * 1.25
	velocity = Vector3.ZERO
	_title.hide()
	_bar.hide()
	died.emit(self)
	# The impact queues a native Engore cut first. Build the ragdoll from the
	# resulting mesh while keeping its independent detached limb in the world.
	_begin_death_ragdoll.call_deferred(get_path_to(corpse), momentum)
	var cleanup := Timer.new()
	cleanup.name = "CorpseLifetime"
	cleanup.one_shot = true
	cleanup.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(cleanup)
	cleanup.timeout.connect(queue_free)
	cleanup.start(CombatLifetimeRules.corpse_lifetime_seconds)
	if affixes.has("volatile"):
		_show_ground_warning(VOLATILE_WARNING, global_position)
		_emit_cast(&"cast_start", _combat_ability("volatile"), "Player")
		var explosion := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		var warning_seconds := TelegraphRules.warning_seconds(VOLATILE_WINDUP, VOLATILE_RADIUS, _player)
		explosion.tween_method(_set_warning_progress, 0.0, 1.0, warning_seconds)
		explosion.tween_callback(_burst)

func _begin_death_ragdoll(corpse_path: NodePath, momentum: Vector3) -> void:
	EnemyRagdoll.start(get_node_or_null(corpse_path) as Node3D, momentum)


func _burst() -> void:
	_attack_warning.hide()
	_attack_warning.queue_free()
	_attack_warning = null
	var ability := _combat_ability("volatile")
	ability["unblockable"] = true
	_emit_cast(&"cast_end", ability, "Player")
	if not is_instance_valid(_player) or not _player.has_method("receive_enemy_hit"):
		return
	var to_player := _flat(_player.global_position - global_position)
	var hit := false
	if to_player.length_squared() < VOLATILE_RADIUS * VOLATILE_RADIUS and _has_sight():
		hit = _player.receive_enemy_hit(_base_damage * 0.88, "fire", "burning", self, ability) == true
	if _ability_trace.is_valid():
		_ability_trace.call({
			"shape": "disc", "origin": global_position + Vector3.UP * ABILITY_TRACE_HEIGHT,
			"reach": VOLATILE_RADIUS, "hit": hit,
		})

func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)
