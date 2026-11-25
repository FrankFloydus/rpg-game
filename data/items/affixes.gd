extends RefCounted

const RECORDS := preload("res://data/items/affix_records.tres")

static var LEVELS: Array[int]:
	get:
		return RECORDS.tier_levels
static var TIER_MULTIPLIERS: Array[float]:
	get:
		return RECORDS.tier_multipliers


# A single explicit affix can grant multiple related stats and occupies one slot.
static var PREFIXES: Array[Dictionary]:
	get:
		return RECORDS.prefixes

static var SUFFIXES: Array[Dictionary]:
	get:
		return RECORDS.suffixes

static var MATERIALS: Dictionary = _ordered_materials()

static var RECIPES: Array[Dictionary]:
	get:
		return RECORDS.recipes


static func _ordered_materials() -> Dictionary:
	# ResourceSaver sorts dictionary keys. Keep the original order for seeded drops.
	var ordered := {}
	for id: String in RECORDS.material_order:
		if RECORDS.materials.has(id):
			ordered[id] = RECORDS.materials[id]
	ordered.merge(RECORDS.materials)
	return ordered
