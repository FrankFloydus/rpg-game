class_name SpatialInventoryEquipment
extends RefCounted
## Checked equipment operations for a host-owned backpack and item store.

signal changed

const FIRST_FIT := Vector2i(-1, -1)
const MAX_SLOTS := 64
const SNAPSHOT_VERSION := 1

## Receives (id, requested_slot). Return the occupied slots or a denial string.
var slot_requirements: Callable
## Optional read-only policy for equipping and returning an item. Return an empty String to allow it.
var move_policy: Callable

var revision: int:
	get:
		return _revision

var backpack: SpatialInventory:
	get:
		return _backpack

var _backpack: SpatialInventory
var _slot_ids: Array[StringName] = []
var _slot_positions: Dictionary = {}
var _occupants: Dictionary = {}
var _items: Dictionary = {}
var _revision := 0
var _busy := false


func configure(source: SpatialInventory, slot_ids: Array) -> Error:
	if _busy:
		return ERR_BUSY
	if source == null or source.get_grid_size() == Vector2i.ZERO or slot_ids.is_empty() or slot_ids.size() > MAX_SLOTS:
		return ERR_INVALID_PARAMETER
	var names: Array[StringName] = []
	var positions: Dictionary = {}
	for raw: Variant in slot_ids:
		if not _is_name(raw):
			return ERR_INVALID_PARAMETER
		var slot := StringName(raw)
		if positions.has(slot):
			return ERR_INVALID_PARAMETER
		positions[slot] = names.size()
		names.append(slot)
	if _backpack == source and _slot_ids == names:
		return OK
	if not _items.is_empty():
		return ERR_BUSY
	_backpack = source
	_slot_ids = names
	_slot_positions = positions
	_busy = true
	_revision += 1
	changed.emit()
	_busy = false
	return OK


func get_slot_ids() -> Array[StringName]:
	return _slot_ids.duplicate()


func get_slot_item(slot: StringName) -> StringName:
	return _occupants.get(slot, &"")


func get_equipped(id: StringName) -> Dictionary:
	return _items.get(id, {}).duplicate(true)


func get_equipped_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for slot: StringName in _slot_ids:
		var id := get_slot_item(slot)
		if not id.is_empty() and _items[id]["slot"] == slot:
			items.append(get_equipped(id))
	return items


func preview_equip(id: StringName, slot: StringName, detached: Dictionary = {}) -> Dictionary:
	return _run(&"equip", id, slot, FIRST_FIT, null, false, {}, detached)


func equip(id: StringName, slot: StringName, expected: Dictionary = {}, detached: Dictionary = {}) -> Dictionary:
	return _run(&"equip", id, slot, FIRST_FIT, null, true, expected, detached)


func preview_unequip(slot: StringName, origin: Vector2i = FIRST_FIT, rotated: Variant = null) -> Dictionary:
	return _run(&"unequip", get_slot_item(slot), slot, origin, rotated, false, {})


func unequip(slot: StringName, origin: Vector2i = FIRST_FIT, rotated: Variant = null,
		expected: Dictionary = {}) -> Dictionary:
	return _run(&"unequip", get_slot_item(slot), slot, origin, rotated, true, expected)


## Release ownership to the host, including any secondary slots occupied by the same item.
func remove(id: StringName) -> Error:
	if _busy:
		return ERR_BUSY
	if not _items.has(id):
		return ERR_DOES_NOT_EXIST
	_busy = true
	var item: Dictionary = _items[id]
	if not _check_move_policy(&"remove", item, item, {}, false).is_empty():
		_busy = false
		return ERR_UNAUTHORIZED
	_remove_equipped(id)
	_revision += 1
	changed.emit()
	_busy = false
	return OK


## The host saves this model alongside its backpack placements and item records.
func export_snapshot() -> Dictionary:
	return {"version": SNAPSHOT_VERSION, "items": get_equipped_items()}


## Restore ownership into an empty endpoint after the host loads its backpack and item records.
func import_snapshot(snapshot: Dictionary) -> Error:
	if _busy or not _items.is_empty():
		return ERR_BUSY
	if _backpack == null or _backpack.get_grid_size() == Vector2i.ZERO:
		return ERR_UNCONFIGURED
	if (not snapshot.get("version") is int or snapshot["version"] != SNAPSHOT_VERSION
			or not snapshot.get("items") is Array or snapshot["items"].size() > _slot_ids.size()):
		return ERR_INVALID_DATA
	_busy = true
	var error := _restore_items(snapshot["items"])
	_busy = false
	return error


func _run(action: StringName, id: StringName, slot: StringName, origin: Vector2i,
		rotated: Variant, commit: bool, expected: Dictionary, detached: Dictionary = {}) -> Dictionary:
	var result := _result(action, id, slot)
	if _busy:
		return _fail(result, ERR_BUSY, "An equipment action is already running.")
	if _backpack == null or _backpack.get_grid_size() == Vector2i.ZERO:
		return _fail(result, ERR_UNCONFIGURED, "Configure equipment and its backpack first.")
	if not _slot_positions.has(slot) or (rotated != null and not rotated is bool):
		return _fail(result, ERR_INVALID_PARAMETER, "Choose a configured equipment slot and a valid rotation.")
	if id.is_empty():
		return _fail(result, ERR_DOES_NOT_EXIST, "Choose an item to move.")
	_busy = true
	var incoming := _plan_equip(result, detached) if action == &"equip" else _plan_unequip(result, origin, rotated)
	if _backpack.get_placement_revision() != result["backpack_revision"]:
		_fail(result, ERR_BUSY, "The backpack changed during equipment validation.")
	if commit and result["error"] == OK:
		if expected.is_empty() or _matches_preview(expected, result):
			_commit(result, incoming)
		else:
			_fail(result, ERR_BUSY, "The equipment preview changed. Review the new placement and try again.")
	_busy = false
	return result


func _plan_equip(result: Dictionary, detached: Dictionary) -> Dictionary:
	var id: StringName = result["id"]
	var source := _backpack.get_placement(id)
	if not detached.is_empty():
		if not source.is_empty() or detached.get("id") != id:
			_fail(result, ERR_BUSY, "The item changed ownership.")
			return {}
		source = detached
	if source.is_empty():
		_fail(result, ERR_DOES_NOT_EXIST, "The item is outside the backpack.")
		return {}
	if _items.has(id):
		_fail(result, ERR_ALREADY_EXISTS, "The equipment endpoint already owns this item.")
		return {}
	var slot: StringName = result["slot"]
	var requirements := _get_requirements(id, slot)
	if requirements["error"] != OK:
		_fail(result, requirements["error"], requirements["reason"])
		return {}
	var slots: Array[StringName] = requirements["slots"]
	var incoming := _item(id, source["footprint"], source["rotated"], slot, slots)
	var denial := _check_move_policy(&"equip", incoming, source, incoming, false)
	if not denial.is_empty():
		_fail(result, ERR_UNAUTHORIZED, denial)
		return {}

	var displaced: Array[StringName] = []
	var seen: Dictionary = {}
	for occupied_slot: StringName in slots:
		var occupant := get_slot_item(occupied_slot)
		if not occupant.is_empty() and not seen.has(occupant):
			seen[occupant] = true
			displaced.append(occupant)
	if displaced.size() > 1:
		displaced.sort_custom(_displacement_order)
	result["slots"] = slots.duplicate()
	result["displaced"] = displaced
	var changes: Array[Dictionary] = [_row(id, source if detached.is_empty() else {}, {})]
	var reserved: Array[Rect2i] = []
	for occupant: StringName in displaced:
		if not _backpack.get_placement(occupant).is_empty():
			_fail(result, ERR_ALREADY_EXISTS, "A displaced item already exists in the backpack.")
			return {}
		var equipped: Dictionary = _items[occupant]
		var origin := _find_return(equipped, source, reserved) if detached.is_empty() else _find_unreserved(equipped, _extent(equipped), reserved)
		if origin == FIRST_FIT:
			_fail(result, ERR_CANT_CREATE, "The backpack has no room for all displaced equipment.")
			return {}
		var placement := _placement(equipped, origin, equipped["rotated"])
		denial = _check_move_policy(&"unequip", equipped, equipped, placement, true)
		if not denial.is_empty():
			_fail(result, ERR_UNAUTHORIZED, denial)
			return {}
		reserved.append(Rect2i(origin, _extent(equipped)))
		changes.append(_row(occupant, {}, placement))
	result["changes"] = changes
	return incoming


func _plan_unequip(result: Dictionary, origin: Vector2i, rotated: Variant) -> Dictionary:
	var id: StringName = result["id"]
	if not _backpack.get_placement(id).is_empty():
		_fail(result, ERR_ALREADY_EXISTS, "The backpack already owns this equipped item.")
		return {}
	var equipped: Dictionary = _items[id]
	var rotation: bool = equipped["rotated"] if rotated == null else rotated
	var footprint: Vector2i = equipped["footprint"]
	if origin == FIRST_FIT:
		origin = _backpack.find_first_fit(footprint, rotation)
		if origin == FIRST_FIT:
			_fail(result, ERR_CANT_CREATE, "The backpack has no room for this equipment.")
			return {}
	else:
		var error := _backpack.check_placement(footprint, origin, rotation)
		if error != OK:
			_fail(result, error, "The equipped item does not fit at that backpack cell.")
			return {}
	var placement := _placement(equipped, origin, rotation)
	var denial := _check_move_policy(&"unequip", equipped, equipped, placement, false)
	if not denial.is_empty():
		_fail(result, ERR_UNAUTHORIZED, denial)
		return {}
	result["changes"] = [_row(id, {}, placement)] as Array[Dictionary]
	result["slots"] = equipped["slots"].duplicate()
	return {}


func _commit(result: Dictionary, incoming: Dictionary) -> void:
	var old_items := _items
	var old_occupants := _occupants
	_items = old_items.duplicate()
	_occupants = old_occupants.duplicate()
	if incoming.is_empty():
		_remove_equipped(result["id"])
	else:
		for id: StringName in result["displaced"]:
			_remove_equipped(id)
		_items[incoming["id"]] = incoming
		for slot: StringName in incoming["slots"]:
			_occupants[slot] = incoming["id"]
	_revision += 1
	# Native backpack listeners see the equipment state belonging to the same transaction.
	var error := SpatialInventory.apply_placement_changes(result["changes"])
	if error != OK:
		_items = old_items
		_occupants = old_occupants
		_revision -= 1
		_fail(result, error, "The backpack changed before equipment could commit.")
		return
	result["committed"] = true
	changed.emit()


func _remove_equipped(id: StringName) -> void:
	for slot: StringName in _items[id]["slots"]:
		_occupants.erase(slot)
	_items.erase(id)


func _restore_items(items: Array) -> Error:
	var backpack_revision := _backpack.get_placement_revision()
	var restored: Dictionary = {}
	var occupants: Dictionary = {}
	for value: Variant in items:
		if not value is Dictionary:
			return ERR_INVALID_DATA
		var record: Dictionary = value
		var footprint: Variant = record.get("footprint")
		if (not _is_name(record.get("id")) or not _is_name(record.get("slot"))
				or not footprint is Vector2i or footprint.x <= 0 or footprint.y <= 0
				or not record.get("rotated") is bool or not record.get("slots") is Array):
			return ERR_INVALID_DATA
		var id := StringName(record["id"])
		var slot := StringName(record["slot"])
		if restored.has(id) or not _backpack.get_placement(id).is_empty():
			return ERR_ALREADY_EXISTS
		var slots := _normalized_slots(record["slots"], slot)
		if slots.is_empty():
			return ERR_INVALID_DATA
		var requirements := _get_requirements(id, slot)
		if requirements["error"] != OK:
			return requirements["error"]
		if requirements["slots"] != slots:
			return ERR_INVALID_DATA
		for occupied: StringName in slots:
			if occupants.has(occupied):
				return ERR_ALREADY_EXISTS
			occupants[occupied] = id
		restored[id] = _item(id, footprint, record["rotated"], slot, slots)
	if _backpack.get_placement_revision() != backpack_revision:
		return ERR_BUSY
	if not restored.is_empty():
		_items = restored
		_occupants = occupants
		_revision += 1
		changed.emit()
	return OK


func _find_return(item: Dictionary, source: Dictionary, reserved: Array[Rect2i]) -> Vector2i:
	var preferred: Vector2i = source["origin"]
	var extent := _extent(item)
	var grid_size := _backpack.get_grid_size()
	if extent.x > grid_size.x or extent.y > grid_size.y:
		return FIRST_FIT
	if (_reserved_end_x(Rect2i(preferred, extent), reserved) == preferred.x
			and _backpack.get_swap_target(item["footprint"], preferred, item["rotated"]) == source["id"]):
		return preferred
	var native_fit := _find_unreserved(item, extent, reserved)
	# Search the additional origins made possible by vacating the incoming item. Keep ordinary scans native.
	var source_end := preferred + _extent(source)
	var first := (preferred - extent + Vector2i.ONE).max(Vector2i.ZERO)
	var last := (source_end - Vector2i.ONE).min(grid_size - extent)
	for y in range(first.y, last.y + 1):
		if native_fit != FIRST_FIT and y > native_fit.y:
			break
		var end_x := mini(last.x, native_fit.x - 1) if y == native_fit.y else last.x
		var x := first.x
		while x <= end_x:
			var origin := Vector2i(x, y)
			var skip_x := _reserved_end_x(Rect2i(origin, extent), reserved)
			if skip_x == x and _backpack.get_swap_target(item["footprint"], origin, item["rotated"]) == source["id"]:
				return origin
			x = maxi(x + 1, skip_x)
	return native_fit


func _find_unreserved(item: Dictionary, extent: Vector2i, reserved: Array[Rect2i]) -> Vector2i:
	var start := Vector2i.ZERO
	while true:
		var fit := _backpack.find_first_fit(item["footprint"], item["rotated"], start)
		if fit == FIRST_FIT:
			return fit
		var skip_x := _reserved_end_x(Rect2i(fit, extent), reserved)
		if skip_x == fit.x:
			return fit
		start = Vector2i(skip_x, fit.y)
	return FIRST_FIT


static func _reserved_end_x(candidate: Rect2i, reserved: Array[Rect2i]) -> int:
	var end_x := candidate.position.x
	for other: Rect2i in reserved:
		if candidate.intersects(other):
			end_x = maxi(end_x, other.end.x)
	return end_x


func _displacement_order(first_id: StringName, second_id: StringName) -> bool:
	var first: Dictionary = _items[first_id]
	var second: Dictionary = _items[second_id]
	var first_footprint: Vector2i = first["footprint"]
	var second_footprint: Vector2i = second["footprint"]
	var first_area := first_footprint.x * first_footprint.y
	var second_area := second_footprint.x * second_footprint.y
	if first_area != second_area:
		return first_area > second_area
	return int(_slot_positions[first["slot"]]) < int(_slot_positions[second["slot"]])


func _get_requirements(id: StringName, slot: StringName) -> Dictionary:
	var value: Variant = [slot]
	if not slot_requirements.is_null():
		if not slot_requirements.is_valid():
			return {"error": ERR_UNAUTHORIZED, "reason": "The equipment rules are unavailable."}
		value = slot_requirements.call(id, slot)
	if value is String or value is StringName:
		var reason := String(value)
		return {"error": ERR_UNAUTHORIZED, "reason": reason if not reason.is_empty() else "This item cannot use the slot."}
	if not value is Array:
		return {"error": ERR_INVALID_DATA, "reason": "Equipment rules must return named slots or a denial reason."}
	var slots := _normalized_slots(value, slot)
	if slots.is_empty():
		return {"error": ERR_INVALID_DATA, "reason": "Equipment rules must include the chosen slot and unique configured slots."}
	return {"error": OK, "slots": slots}


func _normalized_slots(raw: Array, requested: StringName) -> Array[StringName]:
	var slots: Array[StringName] = []
	if raw.is_empty() or raw.size() > _slot_ids.size():
		return slots
	var seen: Dictionary = {}
	for value: Variant in raw:
		if not _is_name(value):
			return []
		var slot := StringName(value)
		if not _slot_positions.has(slot) or seen.has(slot):
			return []
		seen[slot] = true
	if not seen.has(requested):
		return []
	for slot: StringName in _slot_ids:
		if seen.has(slot):
			slots.append(slot)
	return slots


func _check_move_policy(action: StringName, item: Dictionary, source: Dictionary,
		destination: Dictionary, displaced: bool) -> String:
	if move_policy.is_null():
		return ""
	if not move_policy.is_valid():
		return "The equipment movement policy is unavailable."
	var context := {
		"action": action, "id": item["id"], "slot": item["slot"], "slots": item["slots"].duplicate(),
		"backpack": _backpack, "placement": source.duplicate(true),
		"destination_placement": destination.duplicate(true), "displaced": displaced,
	}
	var value: Variant = move_policy.call(context)
	return String(value) if value is String or value is StringName else "Equipment movement policy must return a String."


func _result(action: StringName, id: StringName, slot: StringName) -> Dictionary:
	return {
		"error": OK, "reason": "", "action": action, "id": id, "slot": slot, "committed": false,
		"slots": [] as Array[StringName], "displaced": [] as Array[StringName], "changes": [] as Array[Dictionary],
		"equipment_revision": _revision, "backpack_revision": _backpack.get_placement_revision() if _backpack != null else -1,
	}


static func _fail(result: Dictionary, error: Error, reason: String) -> Dictionary:
	result["error"] = error
	result["reason"] = reason
	result["changes"] = [] as Array[Dictionary]
	return result


static func _matches_preview(expected: Dictionary, current: Dictionary) -> bool:
	for key: String in ["error", "action", "id", "slot", "slots", "displaced", "changes",
			"equipment_revision", "backpack_revision", "committed"]:
		if not expected.has(key) or expected[key] != current[key]:
			return false
	return true


static func _is_name(value: Variant) -> bool:
	return (value is String or value is StringName) and not String(value).is_empty()


static func _extent(item: Dictionary) -> Vector2i:
	var footprint: Vector2i = item["footprint"]
	return Vector2i(footprint.y, footprint.x) if item["rotated"] else footprint


static func _item(id: StringName, footprint: Vector2i, rotated: bool, slot: StringName,
		slots: Array[StringName]) -> Dictionary:
	return {"id": id, "footprint": footprint, "rotated": rotated, "slot": slot, "slots": slots}


static func _placement(item: Dictionary, origin: Vector2i, rotated: bool) -> Dictionary:
	return {"id": item["id"], "footprint": item["footprint"], "origin": origin, "rotated": rotated}


func _row(id: StringName, before: Dictionary, after: Dictionary) -> Dictionary:
	return {"inventory": _backpack, "id": id, "before": before, "after": after}
