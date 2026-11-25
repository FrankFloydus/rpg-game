extends RefCounted

const AFFIX_NAMES := {
	"armored": "Armored",
	"draining": "Life Draining",
	"enraged": "Enraged",
	"frozen": "Frostbound",
	"incendiary": "Incendiary",
	"quick": "Quick",
	"ravaging": "Ravaging",
	"renewing": "Renewing",
	"venomous": "Venomous",
	"volatile": "Volatile",
	"vital": "Vital"
}


static func selection_limit(rarity: String) -> int:
	match rarity:
		"magic": return 1
		"rare": return 3
	return 0
