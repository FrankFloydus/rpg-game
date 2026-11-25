extends RefCounted
## Shared melee weapon families, attribute defaults and strike roles.

const ImpactFeedback := preload("res://data/impact_feedback.tres")
const WeaponBalance := preload("res://data/player_weapon_balance.tres")
const EDGED := &"edged"
const BLUNT := &"blunt"
const CUT := &"cut"
const THRUST := &"thrust"
const STRENGTH := &"strength"
const DEXTERITY := &"dexterity"
const INTELLIGENCE := &"intelligence"
const FINESSE_BASES := ["oath_blade", "chapel_sabre", "funeral_rapier"]
const ONE_HANDED_WEAPONS := ["sword_1h", "mace_1h", "axe_1h", "dagger_1h"]
const MAIN_HAND := &"main_hand"
const OFF_HAND := &"off_hand"
const BOTH_HANDS := &"both_hands"

# Multipliers apply to the authored clock, preserving every hit and buffer marker.
# Light greatswords recover before heavy, head-weighted two-handers.
const COMMITMENT_TIMING := {
	"axe_1h": Vector2(0.94, 0.97),
	"sword_2h": Vector2(0.94, 1.0),
	"axe_2h": Vector2(1.02, 1.03),
	"mace_2h": Vector2(1.06, 1.08),
}

const STUN_BUILDUP := {
	"unarmed": Vector2(10.0, 22.0),
	"dagger_1h": Vector2(8.0, 17.0),
	"sword_1h": Vector2(14.0, 30.0),
	"axe_1h": Vector2(14.0, 30.0),
	"sword_2h": Vector2(18.0, 42.0),
	"axe_2h": Vector2(18.0, 42.0),
	"mace_1h": Vector2(22.0, 50.0),
	"mace_2h": Vector2(28.0, 65.0),
}

# These three-stage chains share left-to-right, right-to-left, and overhead releases.
const DIRECTIONAL_CHARGE_MOVE_FACTORS := {
	"axe_1h": 0.53,
	"axe_2h": 0.40,
	"sword_2h": 0.40,
	"mace_2h": 0.25,
}

const THRUST_ALIGNMENT := 0.82


static func can_dual_wield(main: String, offhand: String) -> bool:
	return main in ONE_HANDED_WEAPONS and offhand in ONE_HANDED_WEAPONS


static func commitment_timing(weapon_type: String, heavy: bool) -> float:
	var values: Vector2 = COMMITMENT_TIMING.get(weapon_type, Vector2.ONE)
	return values.y if heavy else values.x


static func family(weapon_type: String) -> StringName:
	match weapon_type:
		"sword_1h", "sword_2h", "axe_1h", "axe_2h", "dagger_1h":
			return EDGED
		"mace_1h", "mace_2h", "unarmed":
			return BLUNT
	return &""


static func scaling_attribute(weapon_type: String, base_id: String) -> StringName:
	if weapon_type == "staff":
		return INTELLIGENCE
	if weapon_type == "dagger_1h" or base_id in FINESSE_BASES:
		return DEXTERITY
	return STRENGTH if family(weapon_type) != &"" else &""


static func stun_buildup(weapon_type: String, heavy: bool) -> float:
	var values: Vector2 = STUN_BUILDUP.get(weapon_type, Vector2.ZERO)
	return values.y if heavy else values.x


static func charged_damage_factor(weapon_type: String) -> float:
	return WeaponBalance.two_handed_charge if weapon_type.ends_with("2h") else 1.0


static func secondary_damage_factor(weapon_type: String) -> float:
	if weapon_type == "staff":
		return WeaponBalance.staff_fork_damage
	return WeaponBalance.two_handed_cleave if weapon_type.ends_with("2h") else 0.68


static func contact(weapon_type: String, base_id: String, heavy: bool, strike: Dictionary) -> Dictionary:
	var weapon_family := family(weapon_type)
	if weapon_family == &"":
		return {}
	var stroke := weapon_family
	if weapon_family == EDGED:
		stroke = THRUST if _is_thrust(base_id, strike) else CUT
	return {"family": weapon_family, "stroke": stroke, "heavy": heavy, "weapon_type": weapon_type,
		"two_handed": weapon_type.ends_with("2h")}


static func is_blunt_contact(weapon_contact: Dictionary) -> bool:
	return weapon_contact.get("family", &"") == BLUNT


static func can_sever(weapon_contact: Dictionary) -> bool:
	return weapon_contact.get("family", &"") == EDGED and weapon_contact.get("stroke", &"") == CUT


static func blunt_death_momentum(weapon_contact: Dictionary, direction: Vector3,
		overkill := 0.0, body_resistance := 1.0) -> Vector3:
	if not is_blunt_contact(weapon_contact) or not direction.is_finite():
		return Vector3.ZERO
	var speed := ImpactFeedback.blunt_speed(overkill, body_resistance,
		bool(weapon_contact.get("two_handed", false)))
	return direction.normalized() * speed


static func _is_thrust(base_id: String, strike: Dictionary) -> bool:
	var direction: Vector3 = strike.get("direction", Vector3.ZERO)
	var blade_axis: Vector3 = strike.get("blade_axis", Vector3.ZERO)
	var minimum_alignment := 0.72 if base_id == "funeral_rapier" else THRUST_ALIGNMENT
	return direction.normalized().dot(blade_axis.normalized()) >= minimum_alignment
