extends RefCounted

const RECORDS := preload("res://data/items/gear_records.tres")

static var TYPES: Dictionary:
	get:
		return RECORDS.types

# Thin grips and tall shields use the footprint of their individual base.
static var BASE_SIZES: Dictionary:
	get:
		return RECORDS.base_footprints

# Item level, attack stat multiplier, defensive stat multiplier.
# The original base and implicit values carry the first ten depths.
static var ITEM_POWER_BY_LEVEL: Array[Vector3]:
	get:
		return RECORDS.power_by_level


static func power_at_item_level(level: int) -> Vector2:
	var lower: Vector3 = ITEM_POWER_BY_LEVEL[0]
	if level <= lower.x:
		return Vector2(lower.y, lower.z)
	for index in range(1, ITEM_POWER_BY_LEVEL.size()):
		var upper: Vector3 = ITEM_POWER_BY_LEVEL[index]
		if level <= upper.x:
			var progress := inverse_lerp(lower.x, upper.x, float(level))
			return Vector2(lower.y, lower.z).lerp(Vector2(upper.y, upper.z), progress)
		lower = upper
	return Vector2(lower.y, lower.z)


static func footprint(base_id: String, type_id: String) -> Vector2i:
	var type: Dictionary = TYPES.get(type_id, {})
	return BASE_SIZES.get(base_id, type.get("size", Vector2i.ZERO))

# Weapon and off-hand implicits remain when random or crafted affixes change.
static var BASES: Array[Dictionary]:
	get:
		return RECORDS.bases
