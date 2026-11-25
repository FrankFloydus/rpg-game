extends RefCounted
## Carries permanent unlocks and the selected three-slot expedition loadout.

const Catalog = preload("res://data/card_catalog.gd")

var owned: Array[String] = Catalog.STARTERS.duplicate()
var equipped: Array[String] = Catalog.STARTERS.duplicate()


func unlock(id: String) -> bool:
	if not Catalog.CARDS.has(id) or owned.has(id):
		return false
	owned.append(id)
	return true


func unlock_when(id: String, consume: Callable) -> bool:
	if not consume.is_valid() or not unlock(id):
		return false
	if bool(consume.call()):
		return true
	owned.erase(id)
	return false


func equip(slot: int, id: String) -> bool:
	if slot < 0 or slot >= Catalog.SLOTS or (not id.is_empty() and not owned.has(id)):
		return false
	var previous := equipped.find(id) if not id.is_empty() else -1
	if previous >= 0:
		equipped[previous] = equipped[slot]
	equipped[slot] = id
	return true


func snapshot() -> Dictionary:
	return {"owned": owned.duplicate(), "equipped": equipped.duplicate()}


func restore(saved: Dictionary) -> void:
	owned = Catalog.STARTERS.duplicate()
	for id in saved.get("owned", []):
		if id is String:
			unlock(id)
	equipped = normalize_loadout(saved.get("equipped", Catalog.STARTERS), owned)


static func normalize_loadout(loadout: Variant, available: Array[String]) -> Array[String]:
	var result: Array[String] = ["", "", ""]
	var used := {}
	if not loadout is Array:
		return Catalog.STARTERS.duplicate()
	for slot in mini(loadout.size(), Catalog.SLOTS):
		var id: Variant = loadout[slot]
		if id is String and available.has(id) and not used.has(id):
			result[slot] = id
			used[id] = true
	return result
