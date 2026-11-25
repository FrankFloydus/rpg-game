extends SceneTree
## Verifies exact backpack quantities, crafting transactions, and belt persistence.

const Inventory := preload("res://systems/inventory.gd")
const Items := preload("res://systems/items.gd")
const Bases := preload("res://data/items/bases.gd")
const Supplies := preload("res://systems/pack_supplies.gd")

var _checks := 0
var _failures := 0
var _changes := 0


func _initialize() -> void:
	_test_units_and_capacity()
	_test_stack_transactions()
	_test_crafting()
	_test_belts()
	print("Backpack supplies: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_units_and_capacity() -> void:
	var inventory := Inventory.new()
	inventory.changed.connect(func() -> void: _changes += 1)
	_check(inventory.add_material("bone_shard", 2) and inventory.add_treasure_keys(2), "Supplies can be packed")
	var supplies := inventory.get_grid("bag").get_placements()
	_check(supplies.size() == 3 and _changes == 2, "Two shards share one cell while two keys use individual cells")
	var ids := {}
	for placement: Dictionary in supplies:
		ids[placement.id] = true
		_check(placement.footprint == Vector2i.ONE, "Each supply has a single-cell footprint")
	_check(ids.size() == 3 and inventory.materials == {"bone_shard": 2} and inventory.treasure_key_count() == 2,
		"Every instance has a unique ID and material counts only include crafting parts")
	var counts := inventory.materials
	counts.clear()
	_check(inventory.materials == {"bone_shard": 2}, "Changing a reported count cannot edit the pack")
	var key_id := _find_id(inventory, "treasure_key")
	_check(not inventory.equip_item(key_id, "belt").is_empty() and not inventory.quick_sell(key_id).is_empty()
		and inventory.gold == 0, "Keys cannot equip or be traded")
	_check(inventory.comparison_items(inventory.get_item(key_id), "helm", true).is_empty(), "Supplies offer no gear comparisons")
	var saved := inventory.save_data()
	var invalid_save := saved.duplicate(true)
	invalid_save.vendor.append({"item": inventory.get_item(key_id), "x": 0, "y": 0})
	_check(not inventory.restore_data(invalid_save) and inventory.treasure_key_count() == 2,
		"A malformed vendor record cannot import a key or corrupt the active pack")
	_check(not saved.has("materials"), "Save data has one authoritative record per supply")
	var restored := Inventory.new()
	_check(restored.restore_data(JSON.parse_string(JSON.stringify(saved))) and restored.treasure_key_count() == 2
		and restored.materials == {"bone_shard": 2}, "Keys, IDs and crafting units roundtrip through JSON")
	for placement: Dictionary in supplies:
		_check(restored.get_grid("bag").get_placement(placement.id) == placement,
			"Save keeps each unit's cell and orientation")
	var unit := restored.take_item("bag", key_id)
	_check(not unit.is_empty() and restored.treasure_key_count() == 1 and restored.add_item(unit)
		and restored.treasure_key_count() == 2, "Dropping and returning an individual key preserves its instance")
	_check(restored.consume_treasure_key() and restored.treasure_key_count() == 1, "A lock consumes one key")
	restored.clear_treasure_keys()
	_check(restored.treasure_key_count() == 0 and not restored.consume_treasure_key()
		and restored.materials == {"bone_shard": 2}, "Sealing clears only keys")
	_check(restored.add_treasure_keys(70) and not restored.add_material("carrion_eye", 51)
		and restored.materials == {"bone_shard": 2}, "A pickup that exceeds available cells inserts nothing")
	_check(restored.add_material("carrion_eye", 2) and not restored.add_treasure_keys()
		and restored.get_grid("bag").get_placements().size() == 72, "The last free cell accepts exactly one item")
	_check(not restored.add_material("unknown_part") and not restored.add_treasure_keys(0), "Invalid supply requests are rejected")


func _test_crafting() -> void:
	var inventory := Inventory.new()
	var weapon := Items.starter_weapon()
	var id := StringName(weapon.id)
	_check(inventory.add_item(weapon) and inventory.add_material("bone_shard", 3), "Craft inputs enter ordinary backpack")
	_check(not inventory.craft_item(id, "carrion_hone").is_empty() and inventory.materials == {"bone_shard": 3},
		"Missing recipe part leaves gear and ingredients intact")
	_check(inventory.add_material("carrion_eye") and inventory.add_treasure_keys(67), "The recipe can be tested in a full pack")
	var before := inventory.get_grid("bag").get_placement(id)
	_check(inventory.get_grid("bag").get_placements().size() == 70
		and inventory.get_grid("bag").find_first_fit(Vector2i.ONE) == Vector2i(-1, -1),
		"Ingredients and weapon fill the same grid")
	var material_id := _find_id(inventory, "bone_shard")
	_check(not inventory.craft_item(material_id, "carrion_hone").is_empty()
		and not Items.can_craft(inventory.get_item(material_id), "carrion_hone", inventory.materials),
		"Supplies are ingredients only")
	_check(inventory.craft_item(id, "carrion_hone").is_empty() and inventory.materials == {"bone_shard": 1}
		and inventory.treasure_key_count() == 67 and inventory.get_item(id).prefixes[0].id == "honed"
		and inventory.get_grid("bag").get_placement(id) == before,
		"Crafting consumes exactly two shards and one eye without moving gear or touching keys")
	_check(inventory.quick_sell(_find_id(inventory, "bone_shard")).is_empty() and inventory.materials.is_empty()
		and inventory.gold == 1, "Selling a material also updates the available recipe quantity")


func _test_belts() -> void:
	var inventory := Inventory.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 142007
	var belt_bases := 0
	for base: Dictionary in Bases.BASES:
		if base.type != "belt":
			continue
		belt_bases += 1
		var belt := Items.roll_item(int(base.level), "normal", rng, 0.0, base)
		_check(Items.canonical_footprint(belt) == Vector2i(2, 1) and not belt.implicit.is_empty(),
			"Each rolled belt base has a horizontal footprint and an implicit")
		if base.id == "cord_belt":
			belt = Items._roll_gear(base, 1, "normal", rng)
			_check(inventory.add_item(belt) and inventory.quick_equip(StringName(belt.id)).is_empty()
				and Items.player_stats(inventory.equipment).max_health >= 25.0, "A level-one belt equips and grants its life implicit")
	_check(belt_bases == 3, "Three progression tiers use normal loot generation")
	var vendor_belts := 0
	for round in range(8):
		for item: Dictionary in Items.roll_vendor(7, rng):
			if item.type == "belt":
				vendor_belts += 1
	_check(vendor_belts > 0, "Merchant gear generation can roll the belt slot")
	var id := inventory.equipped_id("belt")
	var restored := Inventory.new()
	_check(restored.restore_data(JSON.parse_string(JSON.stringify(inventory.save_data())))
		and restored.equipped_id("belt") == id and not id.is_empty(), "A character save persists equipped belts")
	_check(restored.quick_unequip("belt").is_empty() and restored.add_material("bone_shard", 2)
		and restored.add_material("grave_moss"), "The belt and recipe ingredients fit in the pack")
	_check(restored.craft_item(id, "bone_temper").is_empty(), "An armour recipe works on a belt")


func _test_stack_transactions() -> void:
	var inventory := Inventory.new()
	var bag := inventory.get_grid("bag")
	_check(inventory.add_material("bone_shard", 101) and _quantities(inventory, "bag", "bone_shard") == [1, 50, 50],
		"More than 100 material units form 50, 50 and 1 stacks")
	_check(inventory.add_treasure_keys(69) and inventory.add_material("bone_shard", 47)
		and not inventory.add_material("bone_shard", 3) and inventory.materials.bone_shard == 148,
		"A full pack can fill a partial stack and rejects a larger pickup without consuming any units")
	_check(inventory.add_material("bone_shard", 2) and inventory.materials.bone_shard == 150,
		"The last two units fit a partial stack without a free cell")
	var material := _find_id(inventory, "bone_shard")
	var source := bag.get_placement(material)
	var destination := Vector2i(3, 4)
	_check(inventory.preview_split("bag", material, 19, "stash:0", destination).is_empty()
		and Supplies.quantity(inventory.get_item(material)) == 50,
		"Picking a split quantity holds the preview without mutating the source")
	_check(inventory.drop_split("bag", material, 19, "stash:0", destination).is_empty()
		and inventory.materials.bone_shard == 131 and bag.get_placement(material) == source
		and _quantities(inventory, "stash:0", "bone_shard") == [19],
		"Splitting commits exact amounts to exact cells across grids")
	_check(inventory.drop_split("bag", material, 7, "stash:0", destination).is_empty()
		and _quantities(inventory, "stash:0", "bone_shard") == [26],
		"A split can merge into an existing compatible stack")
	_check(inventory.bulk_stash_transfer("bag", material, "stash:0").is_empty()
		and inventory.materials.is_empty() and _quantities(inventory, "stash:0", "bone_shard") == [50, 50, 50],
		"Bulk transfers preserve all units and fill existing compatible stacks first")
	var saved := inventory.save_data()
	var loaded := Inventory.new()
	_check(loaded.restore_data(JSON.parse_string(JSON.stringify(saved)))
		and _quantities(loaded, "stash:0", "bone_shard") == [50, 50, 50]
		and loaded.treasure_key_count() == 69, "Save round trips keep every quantity and do not combine expedition keys")
	var corrupted := saved.duplicate(true)
	corrupted.stash_tabs[0][0].item.quantity = 51
	_check(not loaded.restore_data(corrupted) and _quantities(loaded, "stash:0", "bone_shard") == [50, 50, 50],
		"An out-of-range saved stack is rejected without damaging active inventory")
	var scroll := Supplies.unveiling_scroll()
	scroll["id"] = "merchant_seals"
	scroll["quantity"] = 4
	loaded.set_vendor_items([scroll])
	loaded.grant_gold(24)
	_check(loaded.quick_purchase(&"merchant_seals").is_empty() and loaded.gold == 0
		and _quantities(loaded, "bag", Supplies.UNVEILING_SCROLL) == [4],
		"Buying four Seals charges the unit price four times")
	var held := _find_id(loaded, Supplies.UNVEILING_SCROLL)
	var seal_cell: Vector2i = loaded.get_grid("bag").get_placement(held).origin
	var spare := Vector2i(11, 5)
	if not loaded.get_grid("bag").get_item_at(spare).is_empty():
		spare = loaded.get_grid("bag").find_first_fit(Vector2i.ONE)
	_check(loaded.drop_split("bag", held, 2, "bag", spare).is_empty()
		and _quantities(loaded, "bag", Supplies.UNVEILING_SCROLL) == [2, 2],
		"Seals split into two player-owned stacks")
	var split := loaded.get_grid("bag").get_item_at(spare)
	_check(loaded.place_backpack_cursor(split, seal_cell).denial.is_empty()
		and _quantities(loaded, "bag", Supplies.UNVEILING_SCROLL) == [4],
		"Click placement onto a compatible Seal stack combines the records")
	_check(loaded.quick_sell(held).is_empty() and loaded.gold == 4
		and _quantities(loaded, "bag", Supplies.UNVEILING_SCROLL).is_empty(),
		"Selling a stack pays per unit without retaining scrolls")
	var crowded := Inventory.new()
	crowded.add_material("bone_shard", 95)
	var full_stack := crowded.get_grid("bag").get_item_at(Vector2i.ZERO)
	crowded.quick_stash_transfer("bag", full_stack, "stash:0")
	crowded.add_treasure_keys(71)
	_check(crowded.bulk_stash_transfer("stash:0", full_stack, "bag").is_empty()
		and _quantities(crowded, "bag", "bone_shard") == [50]
		and _quantities(crowded, "stash:0", "bone_shard") == [45],
		"Bulk transfer fills the last five units and leaves overflow at its source")


func _quantities(inventory: Inventory, owner: String, id: String) -> Array[int]:
	var result: Array[int] = []
	for placement: Dictionary in inventory.get_grid(owner).get_placements():
		var item := inventory.get_item(placement.id)
		if item.get("supply_id") == id:
			result.append(Supplies.quantity(item))
	result.sort()
	return result


func _find_id(inventory: Inventory, supply_id: String) -> StringName:
	for placement: Dictionary in inventory.get_grid("bag").get_placements():
		if inventory.get_item(placement.id).get("supply_id") == supply_id:
			return placement.id
	return &""


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + description)
