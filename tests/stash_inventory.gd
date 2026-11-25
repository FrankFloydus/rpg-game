extends SceneTree
## Native placement, atomic transfers, and JSON save round trips for character storage.

const Inventory := preload("res://systems/inventory.gd")
const Items := preload("res://systems/items.gd")
const Supplies := preload("res://systems/pack_supplies.gd")

var _checks := 0
var _failures := 0
var _transactions := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inventory := Inventory.new()
	_check(Inventory.Stash.OWNERS.size() == 5 and Inventory.Stash.OWNERS.all(func(owner: String) -> bool:
		return inventory.get_grid(owner).get_grid_size() == Vector2i(12, 12)
	), "Each of the five tabs uses a native 12 × 12 storage grid")
	_check(inventory.get_grid("stash:5") == null and inventory.get_grid("stash:000") == null,
		"Unauthored tab names do not alias an existing grid")
	var staff := Items.training_weapon_item("yew_crook", "stash_staff")
	_check(inventory.add_item(staff) and inventory.add_item(Items.starter_weapon()), "Starter gear fits in the pack")
	inventory.changed.connect(func() -> void: _transactions += 1)
	var staff_id := &"stash_staff"
	var sword_id := &"starter_oath_blade"
	_check(not inventory.drop_stash_item("bag", staff_id, "stash:0", Vector2i(2, 5), true).is_empty()
		and not inventory.get_grid("bag").get_placement(staff_id).is_empty() and _transactions == 0,
		"Manual rotation is rejected before moving an item")
	_check(inventory.drop_stash_item("bag", staff_id, "stash:0", Vector2i(2, 5)).is_empty()
		and inventory.get_grid("bag").get_placement(staff_id).is_empty() and _transactions == 1,
		"Depositing an upright multi-cell weapon commits exactly one inventory change")
	var staff_origin := inventory.get_grid("stash:0").get_placement(staff_id)
	_check(staff_origin.origin == Vector2i(2, 5) and not staff_origin.rotated and staff_origin.footprint == Vector2i(1, 4)
		and inventory.get_item(staff_id).base_id == staff.base_id,
		"Deposits preserve the existing item record, orientation, and footprint")
	_check(not inventory.drop_stash_item("bag", sword_id, "stash:0", Vector2i(2, 4)).is_empty()
		and not inventory.get_grid("bag").get_placement(sword_id).is_empty() and _transactions == 1,
		"A partial overlap rejects the whole transfer without mutating source or destination")
	_check(inventory.quick_stash_transfer("stash:0", staff_id, "stash:3").is_empty()
		and inventory.get_grid("stash:0").get_placement(staff_id).is_empty()
		and not inventory.get_grid("stash:3").get_placement(staff_id).rotated,
		"Quick transfer between tabs finds a canonical upright footprint")
	_check(inventory.add_material("bone_shard") and inventory.add_treasure_keys()
		and inventory.add_item(_identified(Supplies.route_key("gate-1", "Gate Key"), "route-1")),
		"Material, route-key and treasure-key records use ordinary pack cells")
	var material := _supply_id(inventory, Supplies.MATERIAL)
	var treasure_key := _supply_id(inventory, Supplies.TREASURE_KEY)
	_check(inventory.quick_stash_transfer("bag", material, "stash:1").is_empty()
		and inventory.materials.get("bone_shard", 0) == 0,
		"Crafting supplies can be stashed and leave the pack's usable supply count")
	_check(not inventory.quick_stash_transfer("bag", treasure_key, "stash:1").is_empty()
		and not inventory.drop_stash_item("bag", &"route-1", "stash:1", Vector2i(5, 7)).is_empty()
		and inventory.treasure_key_count() == 1,
		"Expedition keys cannot outlive the run through stash storage")
	var state := inventory.save_data()
	var from_disk: Dictionary = JSON.parse_string(JSON.stringify(state))
	var loaded := Inventory.new()
	_check(loaded.restore_data(from_disk)
		and not loaded.get_grid("stash:3").get_placement(staff_id).rotated
		and loaded.get_grid("stash:1").get_placement(material).origin == Vector2i.ZERO,
		"A JSON save preserves items, tabs, orientations and coordinates")
	_check(loaded.quick_stash_transfer("stash:3", staff_id, "bag").is_empty()
		and loaded.quick_stash_transfer("stash:1", material, "bag").is_empty()
		and loaded.materials.get("bone_shard", 0) == 1,
		"Loaded deposits can be recovered and become usable immediately")
	var corrupted := from_disk.duplicate(true)
	corrupted.stash_tabs[4].append(corrupted.stash_tabs[3][0].duplicate(true))
	_check(not loaded.restore_data(corrupted) and not loaded.get_grid("bag").get_placement(staff_id).is_empty(),
		"A repeated ID across tabs rejects the staged load without losing live gear")
	var legacy := state.duplicate(true)
	legacy.erase("stash_tabs")
	_check(loaded.restore_data(legacy) and Inventory.Stash.OWNERS.all(func(owner: String) -> bool:
		return loaded.get_grid(owner).get_placements().is_empty()
	), "An older character receives five empty tabs and preserves the existing pack")
	_check(Inventory.new().get_grid("stash:3").get_placements().is_empty(),
		"A new character does not inherit another character's stash")
	_test_legacy_storage(state, staff_id)
	_test_carried_deposit()
	print("Stash inventory: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _identified(item: Dictionary, id: String) -> Dictionary:
	item["id"] = id
	return item


func _test_legacy_storage(state: Dictionary, staff_id: StringName) -> void:
	var legacy := state.duplicate(true)
	legacy.stash_tabs[3][0]["rotated"] = true
	var loaded := Inventory.new()
	_check(loaded.restore_data(legacy) and not loaded.get_grid("stash:3").get_placement(staff_id).rotated,
		"A previously rotated deposit survives conversion to its canonical upright footprint")
	var dense := Inventory.new().save_data()
	dense["stash_tab_rows"] = [13, 12, 12, 12, 12]
	for index in 145:
		var item := _identified(Supplies.material("bone_shard"), "recovery_%d" % index)
		dense.stash_tabs[0].append({"item": item, "x": index % 12, "y": floori(float(index) / 12.0), "rotated": false})
	_check(loaded.restore_data(dense) and loaded.get_grid("stash:0").get_placements().size() == 145
		and loaded.get_grid("stash:0").get_grid_size().y == 13 and loaded.save_data().stash_tab_rows[0] == 13,
		"A valid legacy overflow row round-trips without truncating permanent loot")


func _test_carried_deposit() -> void:
	var inventory := Inventory.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 54839
	var base := {}
	for record: Dictionary in Items.BaseData.BASES:
		if record.id == "iron_band":
			base = record
			break
	var ring := _identified(Items.roll_item(1, "normal", rng, 0.0, base), "stash_cursor_ring")
	var ring_id := StringName(ring.id)
	inventory.add_item(ring)
	inventory.add_item(Items.starter_weapon())
	var place := inventory.place_backpack_cursor(&"starter_oath_blade", Vector2i.ZERO, false)
	_check(place.denial.is_empty() and not inventory.backpack_cursor_placement(ring_id).is_empty(),
		"A backpack swap can put a displaced item on the cursor")
	_check(inventory.drop_stash_item("bag", ring_id, "stash:4", Vector2i(11, 11)).is_empty()
		and inventory.backpack_cursor_placement(ring_id).is_empty()
		and inventory.get_grid("stash:4").get_placement(ring_id).origin == Vector2i(11, 11),
		"Depositing a carried item settles the swap and uses the full stash grid")
	var saved := Inventory.new()
	_check(saved.restore_data(inventory.save_data())
		and saved.get_grid("bag").get_placement(ring_id).is_empty()
		and not saved.get_grid("stash:4").get_placement(ring_id).is_empty(),
		"Settled cursor deposits serialize exactly once")


func _supply_id(inventory: Inventory, kind: String) -> StringName:
	for placement: Dictionary in inventory.get_grid("bag").get_placements():
		if inventory.get_item(placement.id).get("supply_kind") == kind:
			return placement.id
	return &""


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
