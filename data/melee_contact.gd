@tool
extends Resource
## Authored enemy sweep volumes and separate damage and stagger budgets for weapon attacks.

const WEAPONS := [&"unarmed", &"dagger_1h", &"sword_1h", &"mace_1h", &"axe_1h", &"sword_2h", &"mace_2h", &"axe_2h"]
const SWEEP_KEYS := [&"reach_target", &"reach_assist", &"width", &"height", &"length_scale"]
const CLEAVE_KEYS := [&"damage", &"stagger"]

## Each family specifies its light and heavy volume dimensions in meters and its independent mass budgets.
@export_storage var families: Dictionary[String, Dictionary] = {}

@export_group("Contact cone")
## Maximum left or right bearing for melee contacts from the player's gameplay aim.
@export_range(0.0, 89.0, 0.001, "degrees") var horizontal_half_angle := 57.775
## Maximum elevation above or below gameplay aim, measured from horizontal distance to the contact.
@export_range(0.0, 89.0, 0.01, "degrees") var vertical_half_angle := 60.0

@export_group("Downcut precision")
## Maximum distance to consider a preferred target for a two-handed mace downcut.
@export_range(0.1, 12.0, 0.01, "suffix:m") var precision_reach := 2.85
## Minimum alignment between aim and the preferred target, expressed as the cosine of the angle.
@export_range(0.0, 1.0, 0.001) var precision_dot := 0.90

@export_group("Refuge sweep")
## Length multiplier for the broad damage volume in the refuge. The physical head uses its own size.
@export_range(0.05, 2.0, 0.01, "suffix:x") var inn_reach_scale := 0.65
## Width multiplier for the broad damage volume in the refuge.
@export_range(0.05, 2.0, 0.01, "suffix:x") var inn_width_scale := 0.25

@export_group("Cleave mass and power")
## Effective attack power where a family uses its authored damage and stagger budgets unchanged.
@export_range(0.01, 10.0, 0.01) var power_reference := 1.0
## Exponent applied to the attack-power ratio when scaling the mass budgets. Zero uses fixed budgets.
@export_range(0.0, 2.0, 0.01) var power_exponent := 0.50
## Relative mass paid by a strike that meets armor.
@export_range(0.0, 8.0, 0.01, "suffix:x") var armor_mass_scale := 1.35
## Relative base mass paid by a strike that meets a guard, before the flat guard cost.
@export_range(0.0, 8.0, 0.01, "suffix:x") var guard_mass_scale := 1.0
## Extra mass added when a guard blocks the attack.
@export_range(0.0, 20.0, 0.01) var guard_mass_bonus := 3.0
## Relative mass of a foe already staggered by another contact or attack.
@export_range(0.0, 2.0, 0.01, "suffix:x") var staggered_mass_scale := 0.75


func sweep_profile(weapon: String, heavy: bool) -> Dictionary:
	var attack := _attack(weapon, heavy)
	return {"reach_target": attack.reach_target, "reach_assist": attack.reach_assist,
		"width": attack.width, "height": attack.height, "length_scale": attack.length_scale}


func cleave_profile(weapon: String, heavy: bool) -> Dictionary:
	var attack := _attack(weapon, heavy)
	return {"damage": attack.damage, "stagger": attack.stagger, "slides_armor": attack.slides_armor,
		"power_reference": power_reference, "power_exponent": power_exponent,
		"armor_mass_scale": armor_mass_scale, "guard_mass_scale": guard_mass_scale,
		"guard_mass_bonus": guard_mass_bonus, "staggered_mass_scale": staggered_mass_scale}


func _attack(weapon: String, heavy: bool) -> Dictionary:
	var family: Dictionary = families.get(weapon, families.get("unarmed", {}))
	return family.get("heavy" if heavy else "light", {})


func validation_error() -> String:
	for weapon: StringName in WEAPONS:
		if not families.has(String(weapon)):
			return "Melee contact needs a profile for %s." % String(weapon).capitalize()
		var family: Dictionary = families[String(weapon)]
		if String(family.get("name", "")).strip_edges().is_empty():
			return "%s needs a display name." % String(weapon).capitalize()
		for weight: String in ["light", "heavy"]:
			var attack: Variant = family.get(weight)
			if not attack is Dictionary or not attack.get("slides_armor") is bool:
				return "%s needs a complete %s contact profile." % [family.name, weight]
			for key: StringName in SWEEP_KEYS + CLEAVE_KEYS:
				var value: Variant = attack.get(String(key))
				var allows_zero := key in [&"reach_assist", &"damage", &"stagger"]
				if not _valid_number(value, allows_zero):
					return "%s %s has an invalid %s." % [family.name, weight, String(key).replace("_", " ")]
	return ""


static func _valid_number(value: Variant, allows_zero: bool) -> bool:
	if not (value is float or value is int):
		return false
	return is_finite(float(value)) and (value >= 0.0 if allows_zero else value > 0.0)
