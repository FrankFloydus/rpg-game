extends RefCounted
## Owns item records, gold, materials, and the game policies for the native spatial inventory.

signal changed
signal transaction_committed(cue: String)
signal economy_event(kind: StringName, amount: int)

const Items := preload("res://systems/items.gd")
const Supplies := preload("res://systems/pack_supplies.gd")
const CardItems := preload("res://systems/card_items.gd")
const CardDeck := preload("res://systems/card_deck.gd")
const Stash := preload("res://systems/stash_inventory.gd")
const Equipment := preload("res://addons/godot-spatial-inventory/inventory_equipment.gd")
const BackpackCursor := preload("res://systems/backpack_cursor.gd")
const SLOTS := ["helm", "chest", "gloves", "boots", "left_ring", "right_ring", "amulet", "main_hand", "off_hand", "belt"]
const SLOT_NAMES := {
	"helm": "Helm", "chest": "Chest", "gloves": "Gloves", "boots": "Boots",
	"left_ring": "Left Ring", "right_ring": "Right Ring", "amulet": "Amulet",
	"main_hand": "Main Hand", "off_hand": "Off Hand", "belt": "Belt",
}
const BAG_SIZE := Vector2i(12, 6)
const VENDOR_SIZE := Vector2i(10, 7)
const LEGACY_BAG_SIZE := Vector2i(10, 7)
const ONE_HAND_WEAPONS := [&"sword_1h", &"axe_1h", &"mace_1h", &"dagger_1h"]
const MAX_MIGRATED_ROWS := 64
const NO_FIT := Vector2i(-1, -1)

var gold := 0
var materials: Dictionary:
	get:
		var counts := {}
		for placement: Dictionary in _bag.get_placements():
			var item := get_item(placement["id"])
			if item.get("supply_kind") == Supplies.MATERIAL:
				var material_id: String = item["supply_id"]
				counts[material_id] = int(counts.get(material_id, 0)) + Supplies.quantity(item)
		return counts
var equipment: Dictionary:
	get:
		var equipped: Dictionary = {}
		for placement: Dictionary in _gear.get_equipped_items():
			equipped[String(placement["slot"])] = get_item(placement["id"])
		return equipped

var _bag := SpatialInventory.new()
var _vendor := SpatialInventory.new()
var _expedition_vendor: SpatialInventory
var _stash := Stash.new()
var _gear := Equipment.new()
var _backpack_cursor := BackpackCursor.new()
var _items: Dictionary = {}


func _init() -> void:
	_bag.configure(BAG_SIZE)
	_vendor.configure(VENDOR_SIZE)
	_gear.configure(_bag, SLOTS)
	_gear.slot_requirements = _required_slots


func get_grid(owner: String) -> SpatialInventory:
	match owner:
		"bag": return _bag
		"vendor": return _expedition_vendor if _expedition_vendor != null else _vendor
	return _stash.get_grid(owner)


func get_item(id: StringName) -> Dictionary:
	return _items.get(id, {})


func equipped_id(slot: String) -> StringName:
	return _gear.get_slot_item(StringName(slot))


func equipped_anchor(id: StringName) -> String:
	return String(_gear.get_equipped(id).get("slot", ""))


func equipped_rotated(id: StringName) -> bool:
	return bool(_gear.get_equipped(id).get("rotated", false))


func grant_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	changed.emit()


func add_material(material_id: String, quantity: int = 1) -> bool:
	return _add_supplies(Supplies.material(material_id), quantity)


func add_treasure_keys(quantity: int = 1) -> bool:
	return _add_supplies(Supplies.treasure_key(), quantity)


func treasure_key_count() -> int:
	return _treasure_key_ids().size()


func consume_treasure_key() -> bool:
	var keys := _treasure_key_ids()
	if keys.is_empty() or not _remove_supplies(keys.slice(0, 1)):
		return false
	changed.emit()
	return true


func clear_treasure_keys() -> void:
	var keys := _treasure_key_ids()
	if not keys.is_empty() and _remove_supplies(keys):
		changed.emit()


func consume_route_key(lock_id: String) -> bool:
	for placement: Dictionary in _bag.get_placements():
		var id: StringName = placement.id
		var item := get_item(id)
		if item.get("supply_kind") == Supplies.ROUTE_KEY and item.supply_id == lock_id:
			if not _remove_supplies([id]):
				return false
			changed.emit()
			return true
	return false


func clear_expedition_keys() -> void:
	var keys: Array[StringName] = []
	for placement: Dictionary in _bag.get_placements():
		var id: StringName = placement.id
		if Supplies.is_expedition_key(get_item(id)):
			keys.append(id)
	if not keys.is_empty() and _remove_supplies(keys):
		changed.emit()


func _add_supplies(template: Dictionary, quantity: int) -> bool:
	if not _place_supply_units(_bag, template, quantity):
		return false
	changed.emit()
	return true


func _place_supply_units(grid: SpatialInventory, template: Dictionary, quantity: int,
		source: SpatialInventory = null) -> bool:
	var size := grid.get_grid_size()
	var limit := Supplies.stack_limit(template)
	if template.is_empty() or quantity <= 0 or quantity > size.x * size.y * limit:
		return false
	var id := StringName(template.get("id", ""))
	var changes: Array[Dictionary] = []
	var balance := 0
	if source != null:
		var before := source.get_placement(id)
		balance = Supplies.quantity(template) - quantity
		if before.is_empty() or source == grid or balance < 0:
			return false
		changes.append(_placement_change(source, id, before, before if balance > 0 else {}))
	elif not id.is_empty() and _items.has(id):
		return false
	var records := {}
	var remaining := quantity
	if limit > 1:
		for placement: Dictionary in grid.get_placements():
			var candidate := get_item(placement.id)
			if not Supplies.same_stack(template, candidate):
				continue
			var existing := Supplies.quantity(candidate)
			var allocation := mini(remaining, limit - existing)
			if allocation > 0:
				var filled := candidate.duplicate()
				filled["quantity"] = existing + allocation
				records[placement.id] = filled
				changes.append(_placement_change(grid, placement.id, placement, placement))
				remaining -= allocation
				if remaining == 0:
					break
	var start := Vector2i.ZERO
	var pending_id := &"" if balance > 0 else id
	while remaining > 0:
		var cell := grid.find_first_fit(Vector2i.ONE, false, start)
		if cell == NO_FIT:
			return false
		start = Vector2i((cell.x + 1) % size.x, cell.y + int(cell.x == size.x - 1))
		var allocated := mini(remaining, limit)
		var new_id := pending_id if not pending_id.is_empty() else _next_supply_id()
		pending_id = &""
		if new_id.is_empty() or records.has(new_id):
			return false
		var item := template.duplicate()
		item["id"] = String(new_id)
		if limit > 1:
			item["quantity"] = allocated
		records[new_id] = item
		changes.append(_placement_change(grid, new_id, {}, _supply_placement(new_id, cell)))
		remaining -= allocated
	if source != null:
		if balance == 0:
			if not records.has(id):
				records[id] = {}
		else:
			var remainder := template.duplicate()
			remainder["quantity"] = balance
			records[id] = remainder
	return _commit_grid_records(changes, records)


func _next_supply_id() -> StringName:
	var nonce := Crypto.new().generate_random_bytes(12).hex_encode()
	var id := StringName("supply_" + nonce)
	return &"" if nonce.is_empty() or _items.has(id) else id


static func _placement_change(grid: SpatialInventory, id: StringName, before: Dictionary,
		after: Dictionary) -> Dictionary:
	return {"inventory": grid, "id": id, "before": before, "after": after}


func _commit_grid_records(changes: Array[Dictionary], records: Dictionary) -> bool:
	# Native placement observers run synchronously and must see the corresponding item payloads.
	var previous := {}
	for id: StringName in records:
		previous[id] = get_item(id)
		var record: Dictionary = records[id]
		if record.is_empty():
			_items.erase(id)
		else:
			_items[id] = record
	if SpatialInventory.apply_placement_changes(changes) == OK:
		return true
	for id: StringName in previous:
		var record: Dictionary = previous[id]
		if record.is_empty():
			_items.erase(id)
		else:
			_items[id] = record
	return false


static func _supply_placement(id: StringName, cell: Vector2i) -> Dictionary:
	return {"id": id, "origin": cell, "footprint": Vector2i.ONE, "rotated": false}


func _treasure_key_ids() -> Array[StringName]:
	var keys: Array[StringName] = []
	for placement: Dictionary in _bag.get_placements():
		var id: StringName = placement["id"]
		if Supplies.is_treasure_key(get_item(id)):
			keys.append(id)
	return keys


func _recipe_units(requirements: Dictionary) -> Dictionary[StringName, int]:
	var remaining := requirements.duplicate()
	var units: Dictionary[StringName, int] = {}
	for placement: Dictionary in _bag.get_placements():
		var id: StringName = placement["id"]
		var item := get_item(id)
		if item.get("supply_kind") != Supplies.MATERIAL:
			continue
		var material_id: String = item["supply_id"]
		var quantity := int(remaining.get(material_id, 0))
		if quantity <= 0:
			continue
		var consumed := mini(quantity, Supplies.quantity(item))
		units[id] = consumed
		if consumed == quantity:
			remaining.erase(material_id)
			if remaining.is_empty():
				return units
		else:
			remaining[material_id] = quantity - consumed
	return {}


func _consume_supply_quantities(units: Dictionary[StringName, int], forged: Dictionary = {}) -> bool:
	var changes: Array[Dictionary] = []
	var records := {}
	if not forged.is_empty():
		var forged_id := StringName(forged.get("id", ""))
		var target := _bag.get_placement(forged_id)
		if target.is_empty():
			return false
		changes.append(_placement_change(_bag, forged_id, target, target))
		records[forged_id] = forged
	for id: StringName in units:
		var item := get_item(id)
		var before := _bag.get_placement(id)
		var consumed: int = units[id]
		var balance := Supplies.quantity(item) - consumed
		if before.is_empty() or not Supplies.is_supply(item) or consumed <= 0 or balance < 0:
			return false
		if balance == 0:
			changes.append(_placement_change(_bag, id, before, {}))
			records[id] = {}
		else:
			changes.append(_placement_change(_bag, id, before, before))
			var smaller := item.duplicate()
			smaller["quantity"] = balance
			records[id] = smaller
	return _commit_grid_records(changes, records)


func _remove_supplies(ids: Array[StringName]) -> bool:
	var quantities: Dictionary[StringName, int] = {}
	for id: StringName in ids:
		if quantities.has(id):
			return false
		quantities[id] = Supplies.quantity(get_item(id))
	return _consume_supply_quantities(quantities)


func add_item(item: Dictionary) -> bool:
	if Supplies.can_stack(item):
		var validated := Supplies.restore_item(item)
		return not validated.is_empty() and _add_supplies(validated, Supplies.quantity(validated))
	if not _insert(_bag, item):
		return false
	changed.emit()
	return true


## Transfer a player-owned item to the world or discard it after confirmation.
func take_item(source: String, id: StringName) -> Dictionary:
	var item := get_item(id)
	if item.is_empty():
		return {}
	var removed := false
	match source:
		"bag": removed = _bag.remove(id) == OK
		"equipment": removed = _gear.remove(id) == OK
	if not removed:
		return {}
	_items.erase(id)
	changed.emit()
	return item


func equip_starter(item: Dictionary) -> bool:
	if equipped_id("main_hand") != &"" or not _insert(_bag, item):
		return false
	var id := StringName(item["id"])
	var denial := equip_item(id, "main_hand")
	if denial.is_empty():
		return true
	_bag.remove(id)
	_items.erase(id)
	return false


func set_vendor_items(items: Array) -> int:
	for placement: Dictionary in _vendor.get_placements():
		_items.erase(placement["id"])
	_vendor = SpatialInventory.new()
	_vendor.configure(VENDOR_SIZE)
	var stocked := _fill_vendor(_vendor, items)
	changed.emit()
	return stocked


func _fill_vendor(grid: SpatialInventory, items: Array, isolated := false) -> int:
	# Larger pieces first fit more reliably. Catalogue contents stay fixed until restock.
	var stock := items.duplicate()
	stock.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var a := _canonical_footprint(first)
		var b := _canonical_footprint(second)
		return a.x * a.y > b.x * b.y)
	var stocked := 0
	for item: Dictionary in stock:
		var offered := item
		if isolated and _items.has(StringName(item.get("id", ""))):
			offered = item.duplicate(true)
			var suffix := 1
			while _items.has(StringName("%s_expedition_%d" % [item.id, suffix])):
				suffix += 1
			offered["id"] = "%s_expedition_%d" % [item.id, suffix]
		if _insert(grid, offered):
			stocked += 1
	return stocked


## Opens a temporary merchant beside the player's existing hub catalogue.
func open_vendor_catalog(state: Dictionary) -> bool:
	if _expedition_vendor != null:
		return false
	var offers := SpatialInventory.new()
	offers.configure(VENDOR_SIZE)
	var original_items := _items
	_items = original_items.duplicate()
	if state.has("stock"):
		var stock: Variant = state["stock"]
		if not stock is Array or not stock.all(func(item: Variant) -> bool: return item is Dictionary):
			_items = original_items
			return false
		_fill_vendor(offers, stock, true)
	elif not _read_grid(offers, state.get("rows", []), VENDOR_SIZE, VENDOR_SIZE, state.get("height", VENDOR_SIZE.y)):
		_items = original_items
		return false
	_expedition_vendor = offers
	changed.emit()
	return true


func vendor_catalog_snapshot() -> Dictionary:
	if _expedition_vendor == null:
		return {}
	return {"rows": _save_grid(_expedition_vendor), "height": _expedition_vendor.get_grid_size().y}


func close_vendor_catalog() -> Dictionary:
	var snapshot := vendor_catalog_snapshot()
	if snapshot.is_empty():
		return snapshot
	for placement: Dictionary in _expedition_vendor.get_placements():
		_items.erase(placement.id)
	_expedition_vendor = null
	changed.emit()
	return snapshot


func preview_drop(source: String, id: StringName, destination: String, origin: Vector2i, rotated := false) -> String:
	if rotated:
		return "Items keep their original orientation."
	if Stash.is_owner(source) or Stash.is_owner(destination):
		return preview_stash_drop(source, id, destination, origin, rotated)
	var item := get_item(id)
	if item.is_empty():
		return "That item has moved."
	if source == "equipment":
		if destination != "bag" or equipped_anchor(id).is_empty():
			return "Drop equipped gear in your pack."
		var result := _gear.preview_unequip(StringName(equipped_anchor(id)), origin, rotated)
		return String(result.get("reason", "")) if result["error"] != OK else ""
	var source_grid := get_grid(source)
	var detached := backpack_cursor_placement(id) if source == "bag" else {}
	if source_grid == null or (detached.is_empty() and source_grid.get_placement(id).is_empty()):
		return "That item has moved."
	if destination == "vendor":
		if Supplies.is_expedition_key(item):
			return "Expedition keys cannot be traded."
		return "" if source == "bag" else "The merchant arranges her stock."
	if destination != "bag":
		return "Choose a backpack cell."
	if source == "vendor" and gold < buy_price(item):
		return "You need %d more gold." % (buy_price(item) - gold)
	var match_id := _stack_at(id, _bag, origin)
	if not match_id.is_empty():
		return _stack_denial(match_id, Supplies.quantity(item))
	if source == "bag":
		var error := source_grid.check_move(id, origin, rotated) if detached.is_empty() else _bag.check_placement(detached.footprint, origin, rotated)
		if error != OK:
			return "That item will not fit there."
	elif source_grid.check_transfer(id, _bag, origin, rotated) != OK:
		return "That item will not fit there."
	return ""


func drop_item(source: String, id: StringName, destination: String, origin: Vector2i, rotated := false) -> String:
	if Stash.is_owner(source) or Stash.is_owner(destination):
		return drop_stash_item(source, id, destination, origin, rotated)
	var denial := preview_drop(source, id, destination, origin, rotated)
	if not denial.is_empty():
		return denial
	var item := get_item(id)
	var trade_gold := 0
	var units := Supplies.quantity(item)
	var match_id := _stack_at(id, _bag, origin) if destination == "bag" else &""
	if source == "equipment":
		var result := _gear.unequip(StringName(equipped_anchor(id)), origin, rotated)
		if result["error"] != OK:
			return String(result.get("reason", "Could not return that item."))
	elif destination == "vendor":
		var price := sell_price(item)
		gold += price
		if backpack_cursor_placement(id).is_empty() and _bag.remove(id) != OK:
			gold -= price
			return "That item has moved."
		if not backpack_cursor_placement(id).is_empty():
			_backpack_cursor.settle()
		_items.erase(id)
		trade_gold = price
	elif source == "vendor":
		var price := buy_price(item)
		var vendor := get_grid("vendor")
		var moved := vendor.try_transfer(id, _bag, origin, rotated) == OK if match_id.is_empty() \
			else _merge_whole_stack(vendor, id, _bag, match_id)
		if not moved:
			return "That item will not fit there."
		gold -= price
		trade_gold = -price
	elif not match_id.is_empty():
		if not _merge_whole_stack(_bag, id, _bag, match_id):
			return "That item will not fit there."
	elif not backpack_cursor_placement(id).is_empty():
		if _bag.try_place(id, backpack_cursor_placement(id).footprint, origin, rotated) != OK:
			return "That item will not fit there."
		_backpack_cursor.settle()
	elif _bag.try_move(id, origin, rotated) != OK:
		return "That item will not fit there."
	changed.emit()
	_record_trade(trade_gold, units)
	return ""


func _record_trade(trade_gold: int, units: int) -> void:
	if trade_gold < 0:
		economy_event.emit(&"gold_spent", -trade_gold)
		economy_event.emit(&"items_bought", units)
		transaction_committed.emit("trade")
	elif trade_gold > 0:
		economy_event.emit(&"gold_earned_trade", trade_gold)
		economy_event.emit(&"items_sold", units)
		transaction_committed.emit("trade")


func preview_backpack_cursor_drop(id: StringName, origin: Vector2i, rotated := false) -> String:
	var match_id := _stack_at(id, _bag, origin)
	if not rotated and not match_id.is_empty():
		return _stack_denial(match_id, Supplies.quantity(get_item(id)))
	return _backpack_cursor.preview(_bag, id, origin, rotated).denial


func place_backpack_cursor(id: StringName, origin: Vector2i, rotated := false) -> Dictionary:
	var match_id := _stack_at(id, _bag, origin)
	if not rotated and not match_id.is_empty():
		var denial := _stack_denial(match_id, Supplies.quantity(get_item(id)))
		if denial.is_empty() and not _merge_whole_stack(_bag, id, _bag, match_id):
			denial = "That item has moved."
		if denial.is_empty():
			changed.emit()
		return {"denial": denial, "displaced": {}}
	var result := _backpack_cursor.place(_bag, id, origin, rotated)
	if result.denial.is_empty():
		changed.emit()
	return result


func backpack_cursor_placement(id: StringName) -> Dictionary:
	return _backpack_cursor.detached if _backpack_cursor.detached.get("id", &"") == id else {}


func cancel_backpack_cursor() -> bool:
	if _backpack_cursor.detached.is_empty():
		return true
	if not _backpack_cursor.cancel(_bag):
		return false
	changed.emit()
	return true


func preview_identify(scroll_id: StringName, target_id: StringName) -> String:
	var scroll := get_item(scroll_id)
	if scroll.get("supply_kind") != Supplies.UNVEILING_SCROLL or _bag.get_placement(scroll_id).is_empty():
		return "That Scribe's Seal has moved."
	var target := get_item(target_id)
	var can_reveal: bool = CardItems.is_card(target) or target.get("rarity") == "rare"
	if not can_reveal or not target.get("unidentified", false) or _bag.get_placement(target_id).is_empty():
		return "Choose an unidentified item in your pack."
	return ""


func identify_item(scroll_id: StringName, target_id: StringName) -> String:
	var denial := preview_identify(scroll_id, target_id)
	if not denial.is_empty():
		return denial
	var scroll := get_item(scroll_id)
	var hidden := get_item(target_id)
	var revealed := CardItems.make(String(hidden.card_id), String(target_id), false) if CardItems.is_card(hidden) \
		else hidden.duplicate()
	if revealed.is_empty():
		return "That item could not be identified."
	if not CardItems.is_card(revealed):
		revealed.erase("unidentified")
	var scroll_placement := _bag.get_placement(scroll_id)
	var remaining := Supplies.quantity(scroll) - 1
	var target := _bag.get_placement(target_id)
	var rows: Array[Dictionary] = [
		_placement_change(_bag, scroll_id, scroll_placement, scroll_placement if remaining > 0 else {}),
		_placement_change(_bag, target_id, target, target),
	]
	var reduced := {}
	if remaining > 0:
		reduced = scroll.duplicate()
		reduced["quantity"] = remaining
	if not _commit_grid_records(rows, {scroll_id: reduced, target_id: revealed}):
		return "Those items changed before the Seal could be used."
	changed.emit()
	return ""


func learn_card(id: StringName, deck: CardDeck) -> String:
	var card := get_item(id)
	var placement := _bag.get_placement(id)
	if placement.is_empty() or not CardItems.is_card(card):
		return "Move the card to your pack first."
	if card.get("unidentified", false):
		return "Identify this card with a Scribe's Seal first."
	if deck == null:
		return "Your card collection is unavailable."
	var card_id: String = card["card_id"]
	if deck.owned.has(card_id):
		return "You already know this card."
	var rows: Array[Dictionary] = [_placement_change(_bag, id, placement, {})]
	if not deck.unlock_when(card_id, _commit_grid_records.bind(rows, {id: {}})):
		return "That card could not be learned."
	changed.emit()
	return ""


func carried_card_ids() -> Array[String]:
	var result: Array[String] = []
	for item: Dictionary in _items.values():
		if CardItems.is_card(item) and not result.has(item["card_id"]):
			result.append(item["card_id"])
	return result


func preview_equip(id: StringName, slot: String) -> String:
	var result := _gear.preview_equip(id, StringName(slot), backpack_cursor_placement(id))
	return String(result.get("reason", "")) if result["error"] != OK else ""


func equip_item(id: StringName, slot: String) -> String:
	var detached := backpack_cursor_placement(id)
	var result := _gear.equip(id, StringName(slot), {}, detached)
	if result["error"] != OK:
		return String(result.get("reason", "Could not equip that item."))
	if not detached.is_empty():
		_backpack_cursor.settle()
	changed.emit()
	return ""


func quick_equip(id: StringName) -> String:
	return equip_item(id, _default_slot(get_item(id)))


func comparison_items(item: Dictionary, preferred_slot: String = "", include_merchant := false) -> Array[Dictionary]:
	var comparisons: Array[Dictionary] = []
	if item.is_empty() or Supplies.is_supply(item) or item.get("unidentified", false):
		return comparisons
	if not preferred_slot.is_empty():
		# Compare a worn item with the other worn ring/weapon and the next compatible item in view.
		var slot_type := _item_slot(item)
		if slot_type == "ring" or slot_type == "one_hand":
			for slot: String in _slots_for(item):
				var other := get_item(equipped_id(slot))
				if not other.is_empty() and other.get("id") != item.get("id") and _item_slot(other) == slot_type:
					comparisons.append(other)
		var current_vendor := get_grid("vendor")
		for endpoint: SpatialInventory in [_bag, current_vendor]:
			if endpoint == current_vendor and not include_merchant:
				break
			for placement: Dictionary in endpoint.get_placements():
				var candidate := get_item(placement["id"])
				if not candidate.get("unidentified", false) and preferred_slot in _slots_for(candidate):
					comparisons.append(candidate)
					return comparisons
		return comparisons
	var seen: Array[StringName] = []
	for slot: String in _slots_for(item):
		var id := equipped_id(slot)
		if not id.is_empty() and equipped_anchor(id) == slot and id not in seen \
				and id != StringName(item.get("id", "")):
			seen.append(id)
			comparisons.append(get_item(id))
	return comparisons


func _default_slot(item: Dictionary, preferred_slot: String = "") -> String:
	var slots := _slots_for(item)
	if preferred_slot in slots:
		return preferred_slot
	for slot: String in slots:
		if equipped_id(slot).is_empty():
			return slot
	return slots.front() if not slots.is_empty() else ""


func quick_unequip(slot: String) -> String:
	var id := equipped_id(slot)
	if id.is_empty():
		return ""
	var result := _gear.unequip(StringName(equipped_anchor(id)))
	if result["error"] != OK:
		return String(result.get("reason", "There is no room in your pack."))
	changed.emit()
	return ""


func quick_purchase(id: StringName) -> String:
	var item := get_item(id)
	var vendor := get_grid("vendor")
	var placement := vendor.get_placement(id)
	if item.is_empty() or placement.is_empty():
		return "That item has moved."
	if gold < buy_price(item):
		return "You need %d more gold." % (buy_price(item) - gold)
	if Supplies.can_stack(item):
		var price := buy_price(item)
		var units := Supplies.quantity(item)
		if not _place_supply_units(_bag, item, units, vendor):
			return "There is no room in your pack."
		gold -= price
		changed.emit()
		_record_trade(-price, units)
		return ""
	var footprint := _footprint(item)
	var origin := _bag.find_first_fit(footprint)
	if origin == NO_FIT:
		return "There is no room in your pack."
	return drop_item("vendor", id, "bag", origin)


func quick_sell(id: StringName) -> String:
	return drop_item("bag", id, "vendor", Vector2i.ZERO)


func preview_stash_drop(source: String, id: StringName, destination: String,
		origin: Vector2i, rotated := false) -> String:
	if rotated:
		return "Items keep their original orientation."
	if not _is_stash_transfer(source, destination):
		return "Choose your pack or a stash tab."
	var item := get_item(id)
	var source_grid := get_grid(source)
	var target_grid := get_grid(destination)
	var detached := backpack_cursor_placement(id) if source == "bag" else {}
	if item.is_empty() or (source_grid.get_placement(id).is_empty() and detached.is_empty()):
		return "That item has moved."
	if Stash.is_owner(destination) and not can_stash_item(item):
		return "Expedition keys stay in your pack."
	var match_id := _stack_at(id, target_grid, origin)
	if not match_id.is_empty():
		return _stack_denial(match_id, Supplies.quantity(item))
	if not detached.is_empty():
		return "" if target_grid.check_placement(detached.footprint, origin, rotated) == OK else "That item will not fit there."
	var result := source_grid.check_move(id, origin, rotated) if source_grid == target_grid \
		else source_grid.check_transfer(id, target_grid, origin, rotated)
	return "That item will not fit there." if result != OK else ""


func drop_stash_item(source: String, id: StringName, destination: String,
		origin: Vector2i, rotated := false) -> String:
	var denial := preview_stash_drop(source, id, destination, origin, rotated)
	if not denial.is_empty():
		return denial
	var source_grid := get_grid(source)
	var target_grid := get_grid(destination)
	var match_id := _stack_at(id, target_grid, origin)
	if not match_id.is_empty():
		if not _merge_whole_stack(source_grid, id, target_grid, match_id):
			return "That item has moved."
		changed.emit()
		return ""
	var detached := backpack_cursor_placement(id) if source == "bag" else {}
	if not detached.is_empty():
		if target_grid.try_place(id, detached.footprint, origin, rotated) != OK:
			return "That item will not fit there."
		_backpack_cursor.settle()
		changed.emit()
		return ""
	var result := source_grid.try_move(id, origin, rotated) if source_grid == target_grid \
		else source_grid.try_transfer(id, target_grid, origin, rotated)
	if result != OK:
		return "That item will not fit there."
	changed.emit()
	return ""


func quick_stash_transfer(source: String, id: StringName, destination: String) -> String:
	if source == destination or not _is_stash_transfer(source, destination):
		return "Choose another stash tab or your pack."
	var source_grid := get_grid(source)
	var target_grid := get_grid(destination)
	var placement := source_grid.get_placement(id)
	if placement.is_empty():
		return "That item has moved."
	if Stash.is_owner(destination) and not can_stash_item(get_item(id)):
		return "Expedition keys stay in your pack."
	var item := get_item(id)
	if Supplies.can_stack(item):
		if not _place_supply_units(target_grid, item, Supplies.quantity(item), source_grid):
			return _transfer_capacity_denial(destination)
		changed.emit()
		return ""
	var footprint: Vector2i = placement.footprint
	var origin := target_grid.find_first_fit(footprint)
	if origin == NO_FIT:
		return _transfer_capacity_denial(destination)
	return drop_stash_item(source, id, destination, origin)


func bulk_stash_transfer(source: String, id: StringName, destination: String) -> String:
	var item := get_item(id)
	if not Supplies.can_stack(item):
		return quick_stash_transfer(source, id, destination)
	if source == destination or not _is_stash_transfer(source, destination):
		return "Choose another stash tab or your pack."
	var source_grid := get_grid(source)
	var target_grid := get_grid(destination)
	if source_grid.get_placement(id).is_empty():
		return "That item has moved."
	var moved := false
	for placement: Dictionary in source_grid.get_placements():
		var candidate := get_item(placement.id)
		if Supplies.same_stack(item, candidate):
			var units := mini(Supplies.quantity(candidate), _supply_room(target_grid, candidate))
			if units > 0:
				moved = _place_supply_units(target_grid, candidate, units, source_grid) or moved
	if moved:
		changed.emit()
		return ""
	return _transfer_capacity_denial(destination)


func _supply_room(grid: SpatialInventory, item: Dictionary) -> int:
	var size := grid.get_grid_size()
	var free_cells := size.x * size.y
	var open_units := 0
	for placement: Dictionary in grid.get_placements():
		var footprint: Vector2i = placement.footprint
		free_cells -= footprint.x * footprint.y
		var candidate := get_item(placement.id)
		if Supplies.same_stack(item, candidate):
			open_units += Supplies.STACK_LIMIT - Supplies.quantity(candidate)
	return open_units + free_cells * Supplies.STACK_LIMIT


func preview_split(source: String, id: StringName, units: int, destination: String, origin: Vector2i) -> String:
	if not _is_stash_transfer(source, destination) and (source != "bag" or destination != "bag"):
		return "Choose a cell in your pack or stash."
	var source_grid := get_grid(source)
	var item := get_item(id)
	if not Supplies.can_stack(item) or source_grid.get_placement(id).is_empty():
		return "That stack has moved."
	if units < 1 or units >= Supplies.quantity(item):
		return "Choose a quantity smaller than the source stack."
	if not _backpack_cursor.detached.is_empty():
		return "Place the item already on your cursor first."
	var target_grid := get_grid(destination)
	var occupant := target_grid.get_item_at(origin)
	if not occupant.is_empty():
		if occupant == id or not Supplies.same_stack(item, get_item(occupant)):
			return "Choose an empty cell or a matching stack."
		return _stack_denial(occupant, units)
	return "" if target_grid.check_placement(Vector2i.ONE, origin, false) == OK else "That item will not fit there."


func drop_split(source: String, id: StringName, units: int, destination: String, origin: Vector2i) -> String:
	var denial := preview_split(source, id, units, destination, origin)
	if not denial.is_empty():
		return denial
	var from_grid := get_grid(source)
	var to_grid := get_grid(destination)
	var original := from_grid.get_placement(id)
	var occupant := to_grid.get_item_at(origin)
	var remainder := get_item(id).duplicate()
	remainder["quantity"] = Supplies.quantity(remainder) - units
	var split := get_item(occupant).duplicate() if not occupant.is_empty() else remainder.duplicate()
	var rows: Array[Dictionary] = [_placement_change(from_grid, id, original, original)]
	if occupant.is_empty():
		occupant = _next_supply_id()
		if occupant.is_empty():
			return "Could not create a new stack."
		split["id"] = String(occupant)
		split["quantity"] = units
		rows.append(_placement_change(to_grid, occupant, {}, _supply_placement(occupant, origin)))
	else:
		var target := to_grid.get_placement(occupant)
		split["quantity"] = Supplies.quantity(split) + units
		rows.append(_placement_change(to_grid, occupant, target, target))
	if not _commit_grid_records(rows, {id: remainder, occupant: split}):
		return "Those stacks changed before the split could finish."
	changed.emit()
	return ""


func _stack_at(id: StringName, grid: SpatialInventory, origin: Vector2i) -> StringName:
	var other := grid.get_item_at(origin)
	if other == id or other.is_empty():
		return &""
	return other if Supplies.same_stack(get_item(id), get_item(other)) else &""


func _stack_denial(target_id: StringName, units: int) -> String:
	if Supplies.quantity(get_item(target_id)) + units > Supplies.STACK_LIMIT:
		return "That stack holds at most %d. Split off a smaller amount." % Supplies.STACK_LIMIT
	return ""


func _merge_whole_stack(source: SpatialInventory, id: StringName, destination: SpatialInventory,
		target: StringName) -> bool:
	var before := source.get_placement(id)
	var target_place := destination.get_placement(target)
	var detached := source == _bag and not backpack_cursor_placement(id).is_empty()
	var units := Supplies.quantity(get_item(id))
	if target_place.is_empty() or (before.is_empty() and not detached) or not _stack_denial(target, units).is_empty():
		return false
	var rows: Array[Dictionary] = [_placement_change(destination, target, target_place, target_place)]
	if not detached:
		rows.append(_placement_change(source, id, before, {}))
	var combined := get_item(target).duplicate()
	combined["quantity"] = Supplies.quantity(combined) + units
	if not _commit_grid_records(rows, {target: combined, id: {}}):
		return false
	if detached:
		_backpack_cursor.settle()
	return true


static func _transfer_capacity_denial(owner: String) -> String:
	return "There is no room in that stash tab." if Stash.is_owner(owner) else "There is no room in your pack."


static func can_stash_item(item: Dictionary) -> bool:
	return not item.is_empty() and not Supplies.is_expedition_key(item)


static func _is_stash_transfer(source: String, destination: String) -> bool:
	var stash_source := Stash.is_owner(source)
	var stash_destination := Stash.is_owner(destination)
	return (stash_source and (stash_destination or destination == "bag")) or (source == "bag" and stash_destination)


func craft_item(id: StringName, recipe_id: String) -> String:
	if _bag.get_placement(id).is_empty():
		return "Choose an item from your pack."
	var item := get_item(id)
	if Supplies.is_supply(item):
		return "Choose equipment to forge."
	if item.get("unidentified", false):
		return "Identify this item before forging it."
	if not Items.can_craft(item, recipe_id, materials):
		return "This combination cannot be forged with the materials and item you have."
	var forged := Items.craft(item, recipe_id)
	if forged.is_empty():
		return "The forging failed."
	for recipe: Dictionary in Items.recipes():
		if String(recipe["id"]) != recipe_id:
			continue
		var units := _recipe_units(recipe["materials"])
		if (units.is_empty() and not recipe["materials"].is_empty()) or not _consume_supply_quantities(units, forged):
			return "The crafting materials have moved."
		changed.emit()
		economy_event.emit(&"items_crafted", 1)
		transaction_committed.emit("craft")
		return ""
	return "That recipe is unavailable."


func save_data() -> Dictionary:
	var saved_bag := _backpack_cursor.safe_layout(_bag)
	if saved_bag == null:
		saved_bag = _recover_saved_cursor()
	var equipped: Array[Dictionary] = []
	for placement: Dictionary in _gear.get_equipped_items():
		equipped.append({
			"item": get_item(placement["id"]).duplicate(true),
			"slot": String(placement["slot"]),
			"rotated": placement["rotated"],
		})
	var data := {
		"gold": gold,
		"bag": _save_grid(saved_bag),
		"bag_columns": BAG_SIZE.x,
		"vendor": _save_grid(_vendor),
		"equipment": equipped,
	}
	var stash_tabs: Array = []
	var stash_heights: Array[int] = []
	var has_recovery_rows := false
	for owner: String in Stash.OWNERS:
		var tab := _stash.get_grid(owner)
		stash_tabs.append(_save_grid(tab))
		var height := tab.get_grid_size().y
		stash_heights.append(height)
		has_recovery_rows = has_recovery_rows or height != Stash.TAB_SIZE.y
	data["stash_tabs"] = stash_tabs
	if has_recovery_rows:
		data["stash_tab_rows"] = stash_heights
	if saved_bag.get_grid_size().y != BAG_SIZE.y:
		data["bag_rows"] = saved_bag.get_grid_size().y
	if _vendor.get_grid_size().y != VENDOR_SIZE.y:
		data["vendor_rows"] = _vendor.get_grid_size().y
	return data


func _recover_saved_cursor() -> SpatialInventory:
	var placements := _bag.get_placements()
	var detached := _backpack_cursor.detached
	var size := _bag.get_grid_size()
	var recovered := SpatialInventory.new()
	var fit := _bag.find_first_fit(detached.footprint)
	if fit == NO_FIT:
		fit = Vector2i(0, size.y)
		var footprint: Vector2i = detached.footprint
		size.y += footprint.y
	recovered.configure(size)
	for placement: Dictionary in placements:
		recovered.try_place(placement.id, placement.footprint, placement.origin)
	recovered.try_place(detached.id, detached.footprint, fit)
	return recovered


func restore_data(data: Dictionary) -> bool:
	var staged = get_script().new()
	if not staged._read_data(data):
		return false
	gold = staged.gold
	_bag = staged._bag
	_backpack_cursor.settle()
	_vendor = staged._vendor
	_expedition_vendor = null
	_stash = staged._stash
	_gear = staged._gear
	_items = staged._items
	_gear.slot_requirements = _required_slots
	changed.emit()
	return true


static func buy_price(item: Dictionary) -> int:
	return maxi(1, int(item.get("price", int(item.get("gold_value", 1)) * 3))) * Supplies.quantity(item)


static func sell_price(item: Dictionary) -> int:
	if Supplies.is_expedition_key(item):
		return 0
	return maxi(1, floori(float(item.get("gold_value", 1)) / 3.0)) * Supplies.quantity(item)


static func restore_item(item: Dictionary) -> Dictionary:
	return Supplies.restore_item(item) if Supplies.is_supply(item) else Items.restore_item(item)


static func _footprint(item: Dictionary) -> Vector2i:
	return Vector2i(int(item.get("width", 1)), int(item.get("height", 1)))


func _insert(grid: SpatialInventory, item: Dictionary) -> bool:
	if Supplies.is_supply(item):
		if grid != _bag and item.get("supply_kind") != Supplies.UNVEILING_SCROLL:
			return false
		item = Supplies.restore_item(item)
	var id := StringName(str(item.get("id", "")))
	if id.is_empty() or _items.has(id):
		return false
	var footprint := _canonical_footprint(item)
	var origin := grid.find_first_fit(footprint)
	if origin == NO_FIT:
		return false
	var stored := item.duplicate(true)
	stored["slot"] = _item_slot(stored)
	_set_footprint(stored, footprint)
	var placement := {"id": id, "origin": origin, "footprint": footprint, "rotated": false}
	return _commit_grid_records([_placement_change(grid, id, {}, placement)], {id: stored})


func _required_slots(id: StringName, requested: StringName) -> Variant:
	var item := get_item(id)
	if Supplies.is_supply(item):
		return "Supplies stay in your pack."
	if item.get("unidentified", false):
		return "Identify this item before equipping it."
	var target := _item_slot(item)
	if String(requested) not in _slots_for(item):
		var slot_name: String = SLOT_NAMES.get(target, "either hand" if target == "one_hand" else "a ring slot")
		return "This item fits %s." % slot_name
	var blocked := _off_hand_denial(String(requested), get_item(equipped_id("main_hand")))
	if not blocked.is_empty():
		return blocked
	return _occupied_slots(item, String(requested))


static func _item_slot(item: Dictionary) -> String:
	if Supplies.is_supply(item):
		return ""
	if StringName(item.get("type", "")) in ONE_HAND_WEAPONS:
		return "one_hand"
	return String(item.get("slot", ""))


static func _slots_for(item: Dictionary) -> Array[String]:
	match _item_slot(item):
		"ring": return ["left_ring", "right_ring"]
		"one_hand": return ["main_hand", "off_hand"]
		"": return []
		var slot: return [slot]


static func _off_hand_denial(slot: String, main: Dictionary) -> String:
	if slot == "off_hand" and bool(main.get("two_handed", false)):
		return "Equip a one-handed weapon first."
	return ""


static func _occupied_slots(item: Dictionary, slot: String) -> Array[StringName]:
	if slot == "main_hand" and bool(item.get("two_handed", false)):
		return [&"main_hand", &"off_hand"]
	return [StringName(slot)]


func _save_grid(grid: SpatialInventory) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement: Dictionary in grid.get_placements():
		var origin: Vector2i = placement["origin"]
		result.append({
			"item": get_item(placement["id"]).duplicate(true),
			"x": origin.x, "y": origin.y, "rotated": placement["rotated"],
		})
	return result


func _read_data(data: Dictionary) -> bool:
	gold = maxi(0, int(data.get("gold", 0)))
	var bag_width: Variant = data.get("bag_columns", LEGACY_BAG_SIZE.x)
	if bag_width != BAG_SIZE.x and bag_width != LEGACY_BAG_SIZE.x:
		return false
	var original_bag := BAG_SIZE if int(bag_width) == BAG_SIZE.x else LEGACY_BAG_SIZE
	if not _read_grid(_bag, data.get("bag", []), BAG_SIZE, original_bag, data.get("bag_rows", original_bag.y)):
		return false
	if not _read_grid(_vendor, data.get("vendor", []), VENDOR_SIZE, VENDOR_SIZE, data.get("vendor_rows", VENDOR_SIZE.y)):
		return false
	var stash_tabs: Variant = data.get("stash_tabs", null)
	if stash_tabs != null:
		if not stash_tabs is Array or stash_tabs.size() != Stash.OWNERS.size():
			return false
		var stash_heights: Variant = data.get("stash_tab_rows", [])
		if not stash_heights is Array or (not stash_heights.is_empty() and stash_heights.size() != Stash.OWNERS.size()):
			return false
		for index in Stash.OWNERS.size():
			var grid := _stash.get_grid(Stash.OWNERS[index])
			var height: Variant = Stash.TAB_SIZE.y if stash_heights.is_empty() else stash_heights[index]
			if not _read_grid(grid, stash_tabs[index], Stash.TAB_SIZE, Stash.TAB_SIZE, height):
				return false
	var saved_equipment: Variant = data.get("equipment", [])
	if not saved_equipment is Array:
		return false
	var placements: Array[Dictionary] = []
	for raw: Variant in saved_equipment:
		if not raw is Dictionary or not raw.get("item") is Dictionary:
			return false
		var item: Dictionary = raw["item"]
		if Supplies.is_supply(item):
			return false
		var id := StringName(str(item.get("id", "")))
		var slot := StringName(str(raw.get("slot", "")))
		if id.is_empty() or _items.has(id) or not String(slot) in SLOTS:
			return false
		var restored := Items.restore_item(item)
		restored["slot"] = _item_slot(restored)
		var footprint := _canonical_footprint(restored)
		_set_footprint(restored, footprint)
		_items[id] = restored
		var slots: Variant = _required_slots(id, slot)
		if not slots is Array:
			return false
		placements.append({
			"id": id, "footprint": footprint, "rotated": false,
			"slot": slot, "slots": slots,
		})
	return _gear.import_snapshot({"version": 1, "items": placements}) == OK


func _read_grid(grid: SpatialInventory, rows: Variant, standard_size: Vector2i, previous_size: Vector2i,
		saved_height: Variant) -> bool:
	if not rows is Array or (not saved_height is int and not saved_height is float):
		return false
	var height := int(saved_height)
	if height != saved_height or height < previous_size.y or height > MAX_MIGRATED_ROWS:
		return false
	var saved_size := Vector2i(previous_size.x, height)
	var needs_reflow := saved_size != standard_size
	if needs_reflow and grid.configure(saved_size) != OK:
		return false
	for row: Variant in rows:
		if not row is Dictionary or not row.get("item") is Dictionary:
			return false
		var item: Dictionary = row["item"]
		if Supplies.is_supply(item) and grid != _bag:
			if _stash.has_grid(grid):
				if not can_stash_item(item):
					return false
			elif item.get("supply_kind") != Supplies.UNVEILING_SCROLL:
				return false
		var id := StringName(str(item.get("id", "")))
		var origin := Vector2i(int(row.get("x", -1)), int(row.get("y", -1)))
		if id.is_empty() or _items.has(id):
			return false
		var restored := restore_item(item)
		if restored.is_empty():
			return false
		var footprint := Vector2i.ONE if Supplies.is_supply(restored) else _footprint(item)
		var old_rotation := bool(row.get("rotated", false))
		if grid.try_place(id, footprint, origin, old_rotation) != OK:
			return false
		restored["slot"] = _item_slot(restored)
		_items[id] = restored
		needs_reflow = needs_reflow or old_rotation or footprint != _canonical_footprint(restored)
	return not needs_reflow or _migrate_grid_footprints(grid, standard_size)


func _migrate_grid_footprints(grid: SpatialInventory, standard_size: Vector2i) -> bool:
	var placements := grid.get_placements()
	var migrated := _reflow_grid(standard_size, placements, true)
	if migrated == null:
		migrated = _reflow_grid(standard_size, placements, false)
	if migrated == null:
		# Keep every saved item at its current base size even when legacy items used fewer cells.
		var cell_count := 0
		for placement: Dictionary in placements:
			var footprint := _canonical_footprint(_items[placement["id"]])
			cell_count += footprint.x * footprint.y
		var minimum_height := maxi(standard_size.y + 1, ceili(float(cell_count) / standard_size.x))
		var previous_size := grid.get_grid_size()
		for height in range(minimum_height, MAX_MIGRATED_ROWS + 1):
			var grid_size := Vector2i(standard_size.x, height)
			if grid_size == previous_size:
				migrated = _reflow_grid(grid_size, placements, true)
			if migrated == null:
				migrated = _reflow_grid(grid_size, placements, false)
			if migrated != null:
				break
	if migrated == null or grid.import_snapshot(migrated.export_snapshot()) != OK:
		return false
	for placement: Dictionary in migrated.get_placements():
		_set_footprint(_items[placement["id"]], placement["footprint"])
	return true


func _reflow_grid(grid_size: Vector2i, placements: Array, preserve_origins: bool) -> SpatialInventory:
	var staged := SpatialInventory.new()
	staged.configure(grid_size)
	var remaining: Array[Dictionary] = []
	for placement: Dictionary in placements:
		var id: StringName = placement["id"]
		var footprint := _canonical_footprint(_items[id])
		if not preserve_origins or staged.try_place(id, footprint, placement["origin"]) != OK:
			remaining.append(placement)
	return staged if _fit_migrated_items(staged, remaining) else null


func _fit_migrated_items(grid: SpatialInventory, placements: Array) -> bool:
	var sorted := placements.duplicate()
	sorted.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var a := _canonical_footprint(_items[first["id"]])
		var b := _canonical_footprint(_items[second["id"]])
		return a.x * a.y > b.x * b.y)
	for placement: Dictionary in sorted:
		var id: StringName = placement["id"]
		var footprint := _canonical_footprint(_items[id])
		var origin := grid.find_first_fit(footprint)
		if origin == NO_FIT or grid.try_place(id, footprint, origin) != OK:
			return false
	return true


static func _canonical_footprint(item: Dictionary) -> Vector2i:
	if Supplies.is_supply(item):
		return Vector2i.ONE
	var footprint := Items.canonical_footprint(item)
	return _footprint(item) if footprint == Vector2i.ZERO else footprint


static func _set_footprint(item: Dictionary, footprint: Vector2i) -> void:
	item["width"] = footprint.x
	item["height"] = footprint.y
