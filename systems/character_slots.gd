extends RefCounted
## Per-character catalogue backed by the existing atomic checkpoint store.

const SaveStore := preload("res://systems/save_store.gd")
const SLOT_COUNT := 10
const MAX_NAME_LENGTH := 24


static func directory_for(root: String, slot: int) -> String:
	assert(slot >= 0 and slot < SLOT_COUNT, "Character slot out of bounds.")
	return root.path_join("character_%02d" % (slot + 1))


static func load_slot(root: String, slot: int) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT:
		return {}
	return SaveStore.load_game(directory_for(root, slot))


static func list_slots(root: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in SLOT_COUNT:
		var saved := load_slot(root, slot)
		if not saved.is_empty():
			var progress: Dictionary = saved.get("progression", {})
			result.append({"slot": slot, "name": String(saved.get("character_name", "Wanderer")),
				"level": maxi(1, int(progress.get("level", 1)))})
	return result


static func valid_name(value: String) -> bool:
	var display := value.strip_edges()
	if display.is_empty() or display.length() > MAX_NAME_LENGTH:
		return false
	for index in display.length():
		if display.unicode_at(index) < 32 or display.unicode_at(index) == 127:
			return false
	return true
