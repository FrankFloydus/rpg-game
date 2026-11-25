extends RefCounted
## Defines single-cell crafting materials and expedition keys stored in the backpack.

const Affixes := preload("res://data/items/affixes.gd")
const CardItems := preload("res://systems/card_items.gd")

const MATERIAL := "material"
const TREASURE_KEY := "treasure_key"
const ROUTE_KEY := "route_key"
const UNVEILING_SCROLL := "unveiling_scroll"
const STACK_LIMIT := 50


static func is_supply(item: Dictionary) -> bool:
	return item.has("supply_kind")


static func is_treasure_key(item: Dictionary) -> bool:
	return item.get("supply_kind") == TREASURE_KEY


static func is_expedition_key(item: Dictionary) -> bool:
	return item.get("supply_kind") in [TREASURE_KEY, ROUTE_KEY]


static func can_stack(item: Dictionary) -> bool:
	return item.get("supply_kind") in [MATERIAL, UNVEILING_SCROLL]


static func stack_limit(item: Dictionary) -> int:
	return STACK_LIMIT if can_stack(item) else 1


static func quantity(item: Dictionary) -> int:
	return int(item.get("quantity", 1)) if can_stack(item) else 1


static func same_stack(first: Dictionary, second: Dictionary) -> bool:
	return can_stack(first) and first.get("supply_kind") == second.get("supply_kind") \
		and first.get("supply_id") == second.get("supply_id")


static func material(material_id: String) -> Dictionary:
	var definition: Dictionary = Affixes.MATERIALS.get(material_id, {})
	if definition.is_empty():
		return {}
	return _record(MATERIAL, material_id, definition["name"], int(definition["level"]))


static func treasure_key() -> Dictionary:
	return _record(TREASURE_KEY, TREASURE_KEY, "Treasure Key", 1)


static func route_key(lock_id: String, key_name: String) -> Dictionary:
	if lock_id.is_empty() or key_name.is_empty():
		return {}
	var item := _record(ROUTE_KEY, lock_id, key_name, 1)
	item["type"] = TREASURE_KEY
	return item


static func unveiling_scroll() -> Dictionary:
	var item := _record(UNVEILING_SCROLL, UNVEILING_SCROLL, "Scribe's Seal", 1)
	item["price"] = 6
	return item


static func restore_item(item: Dictionary) -> Dictionary:
	if CardItems.is_card(item):
		return CardItems.restore_item(item)
	var id := str(item.get("id", ""))
	if id.is_empty():
		return {}
	var restored: Dictionary
	match item.get("supply_kind"):
		MATERIAL: restored = material(str(item.get("supply_id", "")))
		TREASURE_KEY: restored = treasure_key()
		ROUTE_KEY: restored = route_key(str(item.get("supply_id", "")), str(item.get("name", "")))
		UNVEILING_SCROLL: restored = unveiling_scroll()
	if not restored.is_empty():
		var count: Variant = item.get("quantity", 1)
		if not (count is int or count is float) or count < 1 or count > stack_limit(restored) or count != int(count):
			return {}
		if can_stack(restored):
			restored["quantity"] = int(count)
		restored["id"] = id
	return restored


static func _record(kind: String, supply_id: String, item_name: String, level: int) -> Dictionary:
	return {
		"supply_kind": kind, "supply_id": supply_id,
		"type": supply_id, "name": item_name, "item_level": level,
		"rarity": "normal", "width": 1, "height": 1, "gold_value": 1,
	}
