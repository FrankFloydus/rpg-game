extends RefCounted
## Owns the cleave budget for one committed swing.

# Charged mace impact carries deeper into a group than its damage does.
const MACE_HEAVY_DAMAGE := [1.0, 0.15 / 0.275, 0.075 / 0.275, 0.05 / 0.275]
const MACE_HEAVY_STAGGER := [1.0, 0.225 / 0.30, 0.20 / 0.30, 0.125 / 0.30]

var damage_budget: float
var stagger_budget: float
var spent_mass := 0.0
var target_count := 0
var stopped := false

var _slides_armor: bool
var _armor_mass_scale: float
var _guard_mass_scale: float
var _guard_mass_bonus: float
var _staggered_mass_scale: float
var _mace_heavy: bool
var _seen_actors: Dictionary[int, bool] = {}


func _init(weapon_type: String, heavy: bool, power := 1.0, profile: Dictionary = {}) -> void:
	_mace_heavy = weapon_type == "mace_2h" and heavy
	var two_handed := weapon_type.ends_with("2h")
	var default_budget := (4.0 if two_handed else 3.0) if heavy else (3.0 if two_handed else 1.0)
	var reference := maxf(0.01, float(profile.get("power_reference", 1.0)))
	var exponent := maxf(0.0, float(profile.get("power_exponent", 0.5)))
	var scale := pow(maxf(0.01, power) / reference, exponent)
	damage_budget = maxf(0.0, float(profile.get("damage", default_budget))) * scale
	stagger_budget = maxf(0.0, float(profile.get("stagger", default_budget))) * scale
	_slides_armor = bool(profile.get("slides_armor", heavy))
	_armor_mass_scale = maxf(0.0, float(profile.get("armor_mass_scale", 1.35)))
	_guard_mass_scale = maxf(0.0, float(profile.get("guard_mass_scale", 1.0)))
	_guard_mass_bonus = maxf(0.0, float(profile.get("guard_mass_bonus", 3.0)))
	_staggered_mass_scale = maxf(0.0, float(profile.get("staggered_mass_scale", 0.75)))


func resolve_actor(target: Node3D, contact: Dictionary = {}) -> Dictionary:
	if stopped or not is_instance_valid(target) or target.is_queued_for_deletion() or target.health <= 0.0:
		return {}
	var id := target.get_instance_id()
	if _seen_actors.has(id):
		return {}
	_seen_actors[id] = true
	var material: StringName = target.melee_contact_material()
	var blocked := material == &"guard"
	var armored := material == &"armor"
	var prior_mass := spent_mass
	var can_damage := damage_budget > 0.0 and prior_mass <= damage_budget
	var can_stagger := stagger_budget > 0.0 and prior_mass <= stagger_budget
	if not can_damage and not can_stagger:
		return {}
	spent_mass += _actor_mass(target, material)
	target_count += 1
	var limit := maxf(damage_budget, stagger_budget)
	var stop_kind := &""
	if blocked:
		spent_mass += _guard_mass_bonus
		if target.is_cocoon() or spent_mass >= limit:
			stop_kind = &"guard"
	elif armored and not _slides_armor and not bool(contact.get("ignore_armor", false)):
		stop_kind = &"armor"
	elif spent_mass >= limit or float(target_count) >= limit:
		stop_kind = &"mass"
	stopped = stop_kind != &""
	var outcome := {"can_damage": can_damage, "can_stagger": can_stagger,
		"material": material, "blocked": blocked, "stops_weapon": stopped, "stop_kind": stop_kind,
		"target_index": target_count, "prior_mass": prior_mass, "mass_spent": spent_mass}
	if _mace_heavy:
		var order := mini(target_count - 1, MACE_HEAVY_DAMAGE.size() - 1)
		outcome.damage_falloff = MACE_HEAVY_DAMAGE[order]
		outcome.stagger_falloff = MACE_HEAVY_STAGGER[order]
	return outcome


func can_fit_saved_actor(target: Node3D) -> bool:
	var material: StringName = target.melee_contact_material()
	return spent_mass + _actor_mass(target, material) <= maxf(damage_budget, stagger_budget)


func _actor_mass(target: Node3D, material: StringName) -> float:
	var mass := maxf(0.0, float(target.melee_contact_mass()))
	if target.is_stunned():
		mass *= _staggered_mass_scale
	match material:
		&"armor": mass *= _armor_mass_scale
		&"guard": mass *= _guard_mass_scale
	return mass


func resolve_prop(cost: float, stops_on_hit: bool) -> Dictionary:
	if stopped:
		return {}
	spent_mass += maxf(0.0, cost)
	stopped = stops_on_hit
	return {"stops_weapon": stopped, "stop_kind": &"breakable" if stopped else &"", "mass_spent": spent_mass}
