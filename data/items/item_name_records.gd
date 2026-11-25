extends Resource

## First words for rare titles. Weapon, armour and accessory bases use separate pools.
@export var rare_prefixes: Dictionary[String, PackedStringArray] = {}
## Second words for rare titles, keyed by item family. The roll has no link to item affixes.
@export var rare_suffixes: Dictionary[String, PackedStringArray] = {}


func roll_rare_name(type: String, rng: RandomNumberGenerator) -> String:
	var family := type.trim_suffix("_1h").trim_suffix("_2h")
	var category := "weapon"
	if family in ["amulet", "belt", "focus", "orb", "ring"]:
		category = "accessory"
	elif family in ["boots", "chest", "gloves", "helm", "shield"]:
		category = "armour"
	var first: PackedStringArray = rare_prefixes.get(category, PackedStringArray())
	var second: PackedStringArray = rare_suffixes.get(family, rare_suffixes.get(category, PackedStringArray()))
	if first.is_empty():
		first = PackedStringArray(["Hollow"])
	if second.is_empty():
		second = PackedStringArray(["Relic"])
	return "%s %s" % [first[rng.randi_range(0, first.size() - 1)], second[rng.randi_range(0, second.size() - 1)]]
