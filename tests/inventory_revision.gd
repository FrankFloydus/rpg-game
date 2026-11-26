extends SceneTree

const Inventory := preload("res://systems/inventory.gd")
const Items := preload("res://systems/items.gd")
const Board := preload("res://ui/inventory_ui.gd")
const BOARD_SCENE := preload("res://ui/inventory_ui.tscn")
const Supplies := preload("res://systems/pack_supplies.gd")
const Grid := preload("res://ui/inventory_grid.gd")
const CardItems := preload("res://systems/card_items.gd")
const CardDeck := preload("res://systems/card_deck.gd")
const Art := preload("res://ui/item_art.gd")
var _inventory := Inventory.new()
var _panel: Board
var _failures := 0
var _checks := 0
var _drops: Array[Array] = []


class InventoryCueProbe extends "res://systems/game_audio.gd":
	var requested: Array[StringName] = []

	func _play(event: StringName, _pitch: float, _extra_gain: float) -> bool:
		requested.append(event)
		return true

	func take_events() -> Array[StringName]:
		var events := requested.duplicate()
		requested.clear()
		return events


func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var candidate := _weapon("delvers_edge", "Delver's Edge", 5)
	var worn := _weapon("sanctum_edge", "Sanctum Edge", 3)
	worn.base_stats["move_speed"] = 7
	worn.stats["move_speed"] = 7
	candidate.base_stats["crit_multiplier"] = 5
	candidate.stats["crit_multiplier"] = 5
	_check(_inventory.get_grid("bag").get_grid_size() == Vector2i(12, 6), "Fresh pack is twelve by six")
	_check(_inventory.equip_starter(worn) and _inventory.add_item(candidate), "Worn and pack records exist")
	_inventory.set_vendor_items([_weapon("dealer_edge", "Merchant's Edge", 2)])
	var legacy := Inventory.new()
	var ring := {"id": "legacy_ring", "name": "Old ring", "rarity": "normal", "type": "ring",
		"width": 1, "height": 1, "slot": "ring", "item_level": 1, "stats": {}}
	_check(legacy.restore_data({"bag": [{"item": ring, "x": 9, "y": 6}]}), "Legacy bottom-right item restores")
	_check(legacy.get_grid("bag").get_grid_size() == Vector2i(12, 6)
		and not legacy.get_item(&"legacy_ring").is_empty(), "Legacy grid repacks without losing its item")
	_check(legacy.restore_data(legacy.save_data()), "Migrated save round-trips")
	_check(_inventory.preview_equip(&"delvers_edge", "off_hand").is_empty(), "One-handed item equips in either hand")

	_panel = BOARD_SCENE.instantiate()
	_panel.bind(_inventory)
	_panel.item_drop_requested.connect(func(source: String, id: StringName) -> void: _drops.append([source, id]))
	root.add_child(_panel)
	_panel.open()
	await _frames()
	var pack := _panel._bag_grid
	var main: Control = _panel._slots["main_hand"]
	var ring_slot: Control = _panel._slots["left_ring"]
	var belt: Control = _panel._slots["belt"]
	var expected_art := Grid.item_art_bounds(Rect2(Vector2.ZERO, pack.cell_size * Vector2(worn.width, worn.height)).grow(-1.0))
	_check(main.size.is_equal_approx(pack.cell_size * Vector2(2, 4)) and main.item_art_rect().size == expected_art.size
		and ring_slot.size.is_equal_approx(pack.cell_size * Vector2.ONE),
		"The weapon well stays two by four while its sword artwork uses the same footprint as the pack")
	_check(belt.size.is_equal_approx(pack.cell_size * Vector2(2, 1)), "Belt has its exact two-cell footprint")
	_check(main.global_position.y < pack.global_position.y, "Equipment sits above the shared pack")
	_hover(pack.get_global_rect().position + Vector2.ONE * 10.0)
	await _frames()
	_check(_panel._item_tooltip._panes.get_child_count() == 1, "Normal hover shows one pane")
	_shift(true)
	await _frames()
	var tooltip := _panel._item_tooltip
	_check(tooltip._panes.get_child_count() == 2, "Shift held over bag shows full comparison pane")
	var delta_lines: Array[String] = []
	for line in tooltip.find_children("*", "RichTextLabel", true, false):
		delta_lines.append(line.get_parsed_text())
	_check(delta_lines == ["3 Maximum Stamina (-2)"], "Only shared stamina has inline signed delta: " + str(delta_lines))
	_shift(false)
	await _frames()
	_check(tooltip._panes.get_child_count() == 1, "Releasing Shift removes comparison without moving mouse")
	_hover(main.get_global_rect().get_center())
	_shift(true)
	await _frames()
	_check(tooltip._panes.get_child_count() == 2, "Shift held over equipped gear compares a pack counterpart")
	_shift(false)
	_hover(pack.get_global_rect().position + Vector2.ONE * 10.0)
	_click(pack.get_global_rect().position + Vector2.ONE * 10.0)
	await _frames()
	_check(_panel._carry.is_holding(), "Click picks up player gear")
	_click(Vector2(15, 15))
	await _frames()
	_check(_drops == [["bag", &"delvers_edge"]] and not _panel._carry.is_holding()
		and not _inventory.get_item(&"delvers_edge").is_empty(), "Outside drop dispatches once and keeps model ownership")
	_hover(Vector2(15, 15))
	await _frames()

	_panel.open("vendor")
	await _frames()
	var dealer := _panel._vendor_grid
	_hover(dealer.get_global_rect().position + Vector2.ONE * 10.0)
	_shift(true)
	await _frames()
	_check(tooltip._panes.get_child_count() == 2 and tooltip._buy_price >= 0,
		"Merchant Shift comparison preserves hovered price and shows equipped gear")
	_shift(false)
	_click(dealer.get_global_rect().position + Vector2.ONE * 10.0)
	_click(Vector2(15, 15))
	await _frames()
	_check(_drops.size() == 1 and not _inventory.get_item(&"dealer_edge").is_empty(),
		"Carried merchant stock stays owned by merchant outside the panel")
	var gear := _inventory.take_item("equipment", &"sanctum_edge")
	_check(gear.get("id") == "sanctum_edge" and _inventory.equipped_id("main_hand").is_empty(),
		"Confirmed equipment transfer clears the worn slot directly")
	_check(_inventory.take_item("vendor", &"dealer_edge").is_empty(), "Player cannot take merchant stock directly")
	_check(_inventory.add_material("bone_shard") and _inventory.add_treasure_keys(), "Supplies occupy pack cells")
	_panel.open()
	await _frames()
	for placement: Dictionary in _inventory.get_grid("bag").get_placements():
		var supply := _inventory.get_item(placement["id"])
		if supply.get("supply_kind") != "material":
			continue
		var supply_at := Vector2(placement["origin"]) * _panel._bag_grid.cell_size + Vector2.ONE * 10.0
		_hover(_panel._bag_grid.get_global_rect().position + supply_at)
		_shift(true)
		await _frames()
		_check(tooltip._panes.get_child_count() == 1 and tooltip._comparisons.is_empty(),
			"Crafting supplies show one tooltip and no gear comparison")
		_shift(false)
		break
	_panel.free()
	await process_frame
	await _check_hand_wells()
	await _check_centered_placement()
	await _check_cursor_swaps()
	await _check_stash_controls()
	_check_orientation_migration()
	await _check_identification()
	await _check_stack_controls()
	_check_native_record_transactions()
	await _check_physical_card_controls()
	await _check_inventory_sounds()
	print("Hearth Below inventory revision: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _weapon(id: String, label: String, stamina: int) -> Dictionary:
	var result := Items.training_weapon_item("oath_blade", id)
	result["name"] = label
	result.base_stats["max_stamina"] = stamina
	result.stats["max_stamina"] = stamina
	return result


func _check_hand_wells() -> void:
	var stock := Inventory.new()
	stock.equip_starter(_weapon("narrow_blade", "Narrow Blade", 0))
	var buckler := Items.training_weapon_item("riveted_buckler", "small_buckler")
	var mace := Items.training_weapon_item("quarry_maul", "large_mace")
	stock.add_item(buckler)
	stock.add_item(mace)
	_panel = BOARD_SCENE.instantiate()
	_panel.bind(stock)
	root.add_child(_panel)
	_panel.open()
	await _frames()
	var main: Control = _panel._slots["main_hand"]
	var off: Control = _panel._slots["off_hand"]
	var pack := _panel._bag_grid
	var bag := stock.get_grid("bag")
	var main_rect := main.get_global_rect()
	var off_rect := off.get_global_rect()
	_check(main.size == Vector2(2, 4) * pack.cell_size and off.size == main.size
		and off.accessibility_name.ends_with("Empty") and not off.item_art_rect().has_area(),
		"Empty offhand and occupied main hand start with matching fixed wells and distinct states")
	_click(_grid_point(pack, bag.get_placement(&"small_buckler").origin))
	_check(off._carry_fit and not main._carry_fit, "Only the offhand well highlights for the carried shield")
	_click(off_rect.position + Vector2(12, 130))
	var shield_art := Grid.item_art_bounds(Rect2(Vector2.ZERO, Vector2(2, 2) * pack.cell_size).grow(-1.0))
	_check(off.anchored_item_id() == &"small_buckler" and off.get_global_rect() == off_rect
		and off.item_art_rect().size == shield_art.size, "Clicking near the bottom of the fixed frame equips a true two-by-two shield")
	var equipped := stock.save_data()
	_click(main_rect.get_center())
	var carried_size: Vector2i = _panel._carry._carried.get("size", Vector2i.ZERO)
	_check(carried_size == Vector2i(1, 3), "Picking up a sword from its fixed frame keeps the true backpack footprint")
	_hover(off_rect.get_center())
	_check(main._carry_fit and not off._carry_fit and not _panel._carry._outline.has_area(),
		"Only the carried sword's original slot highlights, even while hovering an incompatible slot")
	_click(main_rect.get_center())
	_check(not _panel._carry.is_holding() and not main._carried and not main._carry_fit and stock.save_data() == equipped,
		"Left-clicking the source slot puts the sword back without changing the inventory")
	_panel._carry.cancel()
	_click(off_rect.get_center())
	_check(off._carry_fit and not main._carry_fit, "The carried shield can return to its exact offhand slot")
	_click(off_rect.get_center())
	_check(not _panel._carry.is_holding() and not off._carried and stock.save_data() == equipped,
		"Left-clicking the shield's source restores the visible slotted shield")
	_panel._carry.cancel()
	_check(stock.equip_item(&"large_mace", "main_hand").is_empty(), "The two-handed fixture selects the normal equipment path")
	await _frames()
	_check(main.get_global_rect() == main_rect and off.get_global_rect() == off_rect and off._blocked
		and off.accessibility_name.ends_with("Two-handed") and not off.item_art_rect().has_area(),
		"A two-handed weapon preserves both frame bounds and labels the locked offhand")
	_click(main_rect.get_center())
	_click(off_rect.get_center())
	_check(main._carry_fit and not off._carry_fit and _panel._carry.is_holding() and off._blocked,
		"The secondary slot of a carried two-hander rejects the drop")
	_click(main_rect.get_center())
	_check(not _panel._carry.is_holding() and off._blocked and main.anchored_item_id() == &"large_mace",
		"The two-hander returns to its main-hand anchor with both slots intact")
	_panel._carry.cancel()
	_click(main_rect.get_center(), false, MOUSE_BUTTON_RIGHT)
	_check(main.get_global_rect() == main_rect and off.get_global_rect() == off_rect and not off._blocked
		and main.accessibility_name.ends_with("Empty") and off.accessibility_name.ends_with("Empty"),
		"Right-click unequip returns both hand wells to labeled empty state without resizing")
	_panel.free()
	await process_frame


func _check_centered_placement() -> void:
	var stock := Inventory.new()
	stock.equip_starter(_weapon("edge_worn", "Worn Blade", 0))
	var id := &"edge_maul"
	stock.add_item(Items.training_weapon_item("quarry_maul", String(id)))
	var bag := stock.get_grid("bag")
	var original := bag.get_placement(id)
	var footprint: Vector2i = original.footprint
	var last_origin := bag.get_grid_size() - footprint
	for index in 2:
		var blocker := StringName("edge_blocker_%d" % index)
		stock.add_item({"id": blocker, "base_id": "iron_band", "type": "ring", "slot": "ring",
			"name": "Iron Band", "rarity": "normal", "item_level": 1})
		bag.try_move(blocker, last_origin + Vector2i(index, 0), false)
	_panel = BOARD_SCENE.instantiate()
	_panel.bind(stock)
	root.add_child(_panel)
	_panel.open()
	await _frames()
	var pack := _panel._bag_grid
	var carry := _panel._carry
	var main: Control = _panel._slots["main_hand"]
	var off: Control = _panel._slots["off_hand"]
	var start := _grid_point(pack, original.origin)
	_click(start)
	_check(footprint == Vector2i(2, 4) and carry._tile.get_global_rect().get_center().is_equal_approx(start),
		"Lifting a 2×4 maul by its upper-left cell centers its whole icon on the cursor")
	_check(main._carry_fit and not off._carry_fit,
		"An occupied main-hand well highlights for the held two-handed weapon")
	var last_point := _drop_point(pack, last_origin, footprint)
	var below_pack := Vector2(last_point.x, pack.get_global_rect().end.y + 8.0)
	var expected := Rect2(pack.global_position + Vector2(last_origin * pack.cell_size), Vector2(footprint * pack.cell_size))
	_hover(below_pack)
	var outline: Rect2 = carry.get_global_transform_with_canvas() * carry._outline
	_check(outline == expected and not carry._outline_valid,
		"The overlapping item previews its full clamped footprint below the pack, including invalid contents")
	_click(below_pack)
	_check(carry.is_holding() and bag.get_placement(id) == original,
		"Blocked edge placement keeps ownership and never searches a neighboring footprint")
	for index in 2:
		bag.try_move(StringName("edge_blocker_%d" % index), Vector2i(5 + index, 0), false)
	_hover(below_pack)
	_check(carry._outline_valid, "Clearing the blockers makes the same overlapping footprint valid")
	_click(below_pack)
	_check(not carry.is_holding() and bag.get_placement(id).origin == last_origin,
		"Clicking just below the grid commits the visible in-bounds footprint")
	var right_edge := Vector2(pack.get_global_rect().end.x + 6.0, pack.global_position.y + pack.cell_size * 2.0)
	var expected_native_origin := Vector2i(last_origin.x, 0)
	var drag_started := await _drag(_grid_point(pack, last_origin), right_edge, func() -> void:
		_check(main._carry_fit and not off._carry_fit, "Native drag highlights the same valid weapon well"))
	_check(drag_started and root.gui_is_drag_successful()
		and bag.get_placement(id).origin == expected_native_origin,
		"Native drag from an item's corner commits the centered footprint just beyond the right edge (%s, %s)" %
			[root.gui_is_drag_successful(), bag.get_placement(id).origin])
	_check(not main._carry_fit and not carry._outline.has_area(), "Drag completion clears both placement previews")
	_panel.free()
	await process_frame


func _check_cursor_swaps() -> void:
	var stock := Inventory.new()
	stock.add_item(_weapon("long", "Long Blade", 0))
	for id in ["ring_a", "ring_b"]:
		stock.add_item({"id": id, "base_id": "iron_band", "type": "ring", "slot": "ring",
			"name": "Iron Band", "rarity": "normal", "item_level": 1})
	var bag := stock.get_grid("bag")
	bag.try_move(&"long", Vector2i(0, 0), false)
	bag.try_move(&"ring_a", Vector2i(3, 1), false)
	bag.try_move(&"ring_b", Vector2i(3, 2), false)
	var initial_long := bag.get_placement(&"long")
	var initial_ring := bag.get_placement(&"ring_a")
	_panel = BOARD_SCENE.instantiate()
	_panel.bind(stock)
	root.add_child(_panel)
	_panel.open()
	await _frames()
	var pack := _panel._bag_grid
	var base := pack.global_position + Vector2.ONE * pack.cell_size * 0.5
	_click(base)
	_check(_panel._carry.is_holding() and _panel._slots["main_hand"]._carry_fit
		and _panel._slots["off_hand"]._carry_fit and not _panel._slots["helm"]._carry_fit,
		"The carried one-hander highlights both compatible hands and leaves other slots alone")
	_hover(_drop_point(pack, Vector2i(3, 1), initial_long.footprint))
	_check(not _panel._carry._outline_valid and not _panel._carry._swap_outline.has_area(),
		"Two overlapping items show a rejected drop without a swap highlight")
	_click(_drop_point(pack, Vector2i(3, 1), initial_long.footprint))
	_check(_panel._carry._carried.get("id") == &"long" and bag.get_placement(&"long") == initial_long,
		"A footprint covering more than one item preserves the installed and carried records")
	var swap_point := _drop_point(pack, Vector2i(3, 2), initial_long.footprint)
	_hover(swap_point)
	_check(_panel._carry._outline_valid and _panel._carry._swap_outline.size == Vector2.ONE * pack.cell_size
		and _panel._carry._outline.size.y == 3 * pack.cell_size,
		"Only the single occupied intersection takes the swap overlay")
	_click(swap_point)
	_check(_panel._carry._carried.get("id") == &"ring_b" and bag.get_placement(&"ring_b").is_empty()
		and bag.get_placement(&"long").origin == Vector2i(3, 2) and _panel._slots["left_ring"]._carry_fit,
		"A valid click places the weapon and puts the displaced ring on the cursor")
	var loaded := Inventory.new()
	_check(loaded.restore_data(stock.save_data()) and not loaded.get_item(&"ring_b").is_empty()
		and loaded.get_grid("bag").get_placement(&"long") == initial_long,
		"A checkpoint taken during a swap preserves the cursor item and the safe layout")
	_click(base + Vector2(3, 1) * pack.cell_size)
	_check(_panel._carry._carried.get("id") == &"ring_a" and bag.get_placement(&"ring_b").origin == Vector2i(3, 1),
		"The displaced ring can itself swap with another item on the next click")
	_panel._carry.cancel()
	_check(not _panel._carry.is_holding() and bag.get_placement(&"long") == initial_long
		and bag.get_placement(&"ring_a") == initial_ring and not _panel._slots["left_ring"]._carry_fit,
		"Cancellation atomically restores the chain and clears equipment highlights")
	var dragged := await _drag(base, swap_point)
	_check(dragged and _panel._carry._carried.get("id") == &"ring_b"
		and bag.get_placement(&"long").origin == Vector2i(3, 2) and bag.get_placement(&"ring_b").is_empty(),
		"Dragging onto one occupied backpack item hands that item to click carry")
	_panel._carry.cancel()
	_check(not _panel._carry.is_holding() and bag.get_placement(&"long") == initial_long,
		"Cancel rolls back a swap started by native drag")
	_click(base)
	_click(_drop_point(pack, Vector2i(3, 2), initial_long.footprint))
	_click(_panel._slots["left_ring"].get_global_rect().get_center())
	_check(stock.equipped_id("left_ring") == &"ring_b" and not _panel._carry.is_holding(),
		"A displaced item can be equipped directly from the cursor")
	_panel.free()
	await process_frame


func _check_stash_controls() -> void:
	var stock := Inventory.new()
	stock.add_item(_weapon("stored_blade", "Oath Blade", 5))
	stock.grant_gold(25)
	_panel = BOARD_SCENE.instantiate()
	_panel.bind(stock)
	root.add_child(_panel)
	_panel.open("stash")
	await _frames()
	var pack := _panel._bag_grid
	var stash := _panel._stash_grid
	var pack_corner := pack.global_position + Vector2.ONE * pack.cell_size * 0.5
	var stash_corner := stash.global_position + Vector2.ONE * stash.cell_size * 0.5
	var bag := stock.get_grid("bag")
	var id := &"stored_blade"
	var footprint: Vector2i = bag.get_placement(id).footprint
	_check(_panel._stash_tabs.size() == 5 and stash.endpoint == "stash:0"
		and stock.get_grid(stash.endpoint).get_grid_size() == Vector2i(12, 12),
		"The Stash presents five independent 12×12 tabs")
	_click(pack_corner, true)
	_check(bag.get_placement(id).is_empty() and not stock.get_grid("stash:0").get_placement(id).is_empty(),
		"Ctrl-click transfers pack gear into the current stash tab")
	_click(stash_corner, true)
	_check(not bag.get_placement(id).is_empty() and stock.get_grid("stash:0").get_placement(id).is_empty()
		and stock.gold == 25, "Ctrl-click transfers stash gear into the pack without changing gold")
	_click(pack_corner)
	_click(_panel._stash_tabs[3].get_global_rect().get_center())
	_click(_drop_point(stash, Vector2i(4, 2), footprint))
	var location := stock.get_grid("stash:3").get_placement(id)
	_check(location.get("origin") == Vector2i(4, 2) and not _panel._carry.is_holding()
		and stock.get_grid("stash:0").get_placement(id).is_empty(),
		"Click carry survives a tab switch and drops at the exact cell without moving the old tab")
	var search := _panel._stash_ledger
	search.text = "oath maximum stamina"
	search.text_changed.emit(search.text)
	_check(stash._search_filter.call(stock.get_item(id)) == true and location == stock.get_grid("stash:3").get_placement(id),
		"Name and stat search highlights the item in its original footprint")
	_panel._stash_rarity.select(1)
	_panel._stash_rarity.item_selected.emit(1)
	_check(stash._search_filter.call(stock.get_item(id)) == true, "Matching rarity keeps the item highlighted")
	_panel._stash_rarity.select(3)
	_panel._stash_rarity.item_selected.emit(3)
	_check(stash._search_filter.call(stock.get_item(id)) == false,
		"The rarity filter dims a non-matching item without removing it")
	_click(stash_corner + Vector2(4, 2) * stash.cell_size)
	_click(_drop_point(pack, Vector2i(5, 1), footprint))
	_check(bag.get_placement(id).get("origin") == Vector2i(5, 1)
		and stock.get_grid("stash:3").get_placement(id).is_empty(),
		"The same click carry withdraws from the Stash into an exact pack cell")
	var in_pack := pack_corner + Vector2(5, 1) * pack.cell_size
	var in_stash := _drop_point(stash, Vector2i(1, 1), footprint)
	var dragged := await _drag(in_pack, in_stash)
	_check(dragged and stock.get_grid("stash:3").get_placement(id).get("origin") == Vector2i(1, 1)
		and bag.get_placement(id).is_empty(), "Native drag transfers pack gear into stash (%s, %s, %s)" %
			[dragged, root.gui_is_drag_successful(), stock.get_grid("stash:3").get_placement(id)])
	var returned := await _drag(in_stash, pack_corner)
	_check(returned and bag.get_placement(id).get("origin") == Vector2i.ZERO
		and stock.get_grid("stash:3").get_placement(id).is_empty(), "Native drag transfers stash gear into pack")
	_panel.free()
	await process_frame


func _check_orientation_migration() -> void:
	var old_rows: Array[Dictionary] = []
	for index in 9:
		old_rows.append({"item": {
			"id": "iron_%d" % index, "type": "mace_2h", "slot": "main_hand",
			"name": "Long Maul", "width": 2, "height": 4, "rarity": "normal", "item_level": 1,
		}, "x": index % 3 * 4, "y": floori(index / 3.0) * 2, "rotated": true})
	var stock := Inventory.new()
	_check(stock.restore_data({"bag_columns": 12, "bag": old_rows}),
		"An old pack full of rotated gear restores in canonical orientation")
	var bag := stock.get_grid("bag")
	_check(bag.get_placements().size() == 9 and bag.get_grid_size().y > Inventory.BAG_SIZE.y
		and bag.get_placements().all(func(row: Dictionary) -> bool: return not row.rotated),
		"An impossible 12×6 arrangement uses recovery rows without losing or rotating items")
	var saved := Inventory.new()
	_check(saved.restore_data(stock.save_data()) and saved.get_grid("bag").get_placements().size() == 9,
		"Recovery rows round-trip")
	var before := bag.get_placement(&"iron_0")
	_check(not stock.drop_item("bag", &"iron_0", "bag", Vector2i.ZERO, true).is_empty()
		and not stock.place_backpack_cursor(&"iron_0", Vector2i.ZERO, true).denial.is_empty()
		and not stock.drop_item("bag", &"iron_0", "stash:0", Vector2i.ZERO, true).is_empty()
		and bag.get_placement(&"iron_0") == before,
		"Gameplay APIs reject rotations in pack moves, cursor swaps and stash transfers")


func _check_identification() -> void:
	var stock := Inventory.new()
	var concealed := _weapon("masked_gear", "Gilded Masked Blade", 13)
	concealed["rarity"] = "rare"
	concealed["unidentified"] = true
	var follow_up := concealed.duplicate(true)
	follow_up["id"] = "masked_spare"
	stock.add_item(concealed)
	stock.add_item(follow_up)
	stock.equip_starter(_weapon("known", "Known Blade", 3))
	var scroll := Supplies.unveiling_scroll()
	scroll["id"] = "vendor_seals"
	scroll["quantity"] = 2
	stock.grant_gold(40)
	stock.set_vendor_items([scroll])
	var vendor := stock.get_grid("vendor")
	var seal_offer: StringName = vendor.get_item_at(Vector2i.ZERO)
	var price := Inventory.buy_price(stock.get_item(seal_offer))
	_check(price == 12 and stock.quick_purchase(seal_offer).is_empty() and stock.gold == 28,
		"Vendor sells the selected Seal stack at the price of its two units")
	var saved := Inventory.new()
	_check(saved.restore_data(stock.save_data()), "Seals and still-concealed rare gear survive a save")
	stock = saved
	var bag := stock.get_grid("bag")
	var seal: StringName
	for placement: Dictionary in bag.get_placements():
		var item := stock.get_item(placement.id)
		if item.get("supply_kind") == Supplies.UNVEILING_SCROLL:
			seal = placement.id
			break
	var hidden := stock.get_item(&"masked_gear")
	_check(Supplies.quantity(stock.get_item(seal)) == 2 and hidden.get("unidentified", false)
		and hidden.stats.max_stamina == 13 and stock.comparison_items(hidden).is_empty()
		and not stock.quick_equip(&"masked_gear").is_empty(), "Concealed stats stay stored while comparison and equip are denied")
	_check(Board._matching_stash_item(hidden, PackedStringArray(["oath", "blade"]), "rare", "sword_1h")
		and not Board._matching_stash_item(hidden, PackedStringArray(["gilded"]), "", "")
		and not Board._matching_stash_item(hidden, PackedStringArray(["stamina"]), "", ""),
		"Stash search matches visible base and rarity without revealing hidden name or stats")
	_panel = BOARD_SCENE.instantiate()
	_panel.bind(stock)
	root.add_child(_panel)
	_panel.open()
	await _frames()
	var gear_placement := bag.get_placement(&"masked_gear")
	var gear_at := _grid_point(_panel._bag_grid, gear_placement.origin)
	var seal_at := _grid_point(_panel._bag_grid, bag.get_placement(seal).origin)
	_hover(gear_at)
	_modifier(KEY_SHIFT, true)
	_modifier(KEY_ALT, true)
	await _frames()
	var tooltip := _panel._item_tooltip
	var lines := _tooltip_lines()
	_check(tooltip._panes.get_child_count() == 1 and "Oath Blade" in lines and "Unidentified" in lines
		and not "Gilded Masked Blade" in lines and not "+13 Maximum Stamina" in lines
		and tooltip._panes.find_children("*", "RichTextLabel", true, false).is_empty(),
		"Alt and Shift keep unidentified tooltip limited to its base and instructions")
	_modifier(KEY_SHIFT, false)
	_modifier(KEY_ALT, false)
	_hover(seal_at)
	await _frames()
	_check("Stack 2 / 50" in _tooltip_lines(), "Seal tooltip displays its current count and maximum")
	_click(seal_at, false, MOUSE_BUTTON_RIGHT)
	_check(_panel._carry._carried.get("identify", false), "Right-clicking a pack Seal arms the identification cursor")
	_click(_grid_point(_panel._bag_grid, Vector2i(11, 5)))
	_click(Vector2(10, 10))
	_check(_panel._carry.is_holding() and Supplies.quantity(stock.get_item(seal)) == 2,
		"Empty pack and outside clicks leave identification armed and consume no Seal")
	_press_key(KEY_ESCAPE)
	_check(not _panel._carry.is_holding() and _panel.is_open() and Supplies.quantity(stock.get_item(seal)) == 2,
		"Escape cancels only the identification cursor")
	_click(seal_at, false, MOUSE_BUTTON_RIGHT)
	_click(gear_at)
	_check(not _panel._carry.is_holding() and Supplies.quantity(stock.get_item(seal)) == 1
		and bag.get_placement(&"masked_gear") == gear_placement and stock.get_item(&"masked_gear").stats == hidden.stats
		and Items.visible_name(stock.get_item(&"masked_gear")) == "Gilded Masked Blade",
		"A valid click preserves the item footprint and its affix roll while consuming exactly one Seal")
	_click(seal_at, false, MOUSE_BUTTON_RIGHT)
	_click(_grid_point(_panel._bag_grid, bag.get_placement(&"masked_spare").origin))
	_check(stock.get_item(seal).is_empty() and bag.get_placement(seal).is_empty()
		and stock.quick_equip(&"masked_gear").is_empty(), "Last Seal removes its cell and identified gear can equip")
	_panel.free()
	await process_frame


func _check_stack_controls() -> void:
	var stock := Inventory.new()
	stock.add_material("bone_shard", 54)
	_panel = BOARD_SCENE.instantiate()
	_panel.bind(stock)
	root.add_child(_panel)
	_panel.open("stash")
	await _frames()
	var pack := _panel._bag_grid
	var stash := _panel._stash_grid
	var bag := stock.get_grid("bag")
	var store := stock.get_grid("stash:0")
	var stack := bag.get_item_at(Vector2i.ZERO)
	var pack_at := _grid_point(pack, Vector2i.ZERO)
	var stash_cell := Vector2i(3, 4)
	var stash_at := _grid_point(stash, stash_cell)
	_click(pack_at, false, MOUSE_BUTTON_LEFT, true)
	_check(_panel._carry.is_splitting() and _panel._carry._split_amount.max_value == 49.0
		and Supplies.quantity(stock.get_item(stack)) == 50, "Shift-left-click opens a bounded split dialog without changing the stack")
	_press_key(KEY_ESCAPE)
	_check(not _panel._carry.is_splitting() and _panel.is_open(), "Escape closes the split dialog without closing Stash")
	_click(pack_at, false, MOUSE_BUTTON_LEFT, true)
	_panel._carry._split_amount.get_line_edit().text = "7"
	_press_key(KEY_ENTER)
	_check(_panel._carry._carried.get("split_units") == 7 and Supplies.quantity(stock.get_item(stack)) == 50,
		"Enter confirms the typed split count and leaves ownership unchanged while carried")
	_click(pack_at)
	_check(_panel._carry.is_holding() and Supplies.quantity(stock.get_item(stack)) == 50,
		"Clicking the source stack itself cannot commit a split")
	_click(stash_at)
	var deposited := store.get_item_at(stash_cell)
	_check(not _panel._carry.is_holding() and Supplies.quantity(stock.get_item(deposited)) == 7
		and Supplies.quantity(stock.get_item(stack)) == 43, "Split places exactly seven units in the chosen stash cell")
	_click(pack_at, true)
	_check(Supplies.quantity(stock.get_item(deposited)) == 50 and stock.materials.get("bone_shard") == 4,
		"Ctrl-left-click moves and merges only the clicked stack into Stash")
	var last_pack: Vector2i = bag.get_placements()[0].origin
	_click(_grid_point(pack, last_pack), true, MOUSE_BUTTON_RIGHT)
	_check(store.get_placements().size() == 2 and bag.get_placements().is_empty(),
		"Ctrl-right-click deposits all matching stacks within stash capacity")
	_click(stash_at, true, MOUSE_BUTTON_RIGHT)
	_check(store.get_placements().is_empty() and stock.materials.get("bone_shard") == 54,
		"Ctrl-right-click withdraws all matching stacks and preserves the total")
	_panel.free()
	await process_frame


func _check_native_record_transactions() -> void:
	var stock := Inventory.new()
	var bag := stock.get_grid("bag")
	var store := stock.get_grid("stash:0")
	var observed_pack: Array[int] = []
	var observe_pack := func() -> void:
		observed_pack.append(stock.materials.get("bone_shard", 0))
	bag.changed.connect(observe_pack)
	_check(stock.add_material("bone_shard", 51) and observed_pack == [51],
		"A native insertion observer sees the item records for every just-placed stack")
	var source_id := bag.get_item_at(Vector2i.ZERO)
	var observed_split: Array[Vector2i] = []
	var observe_split := func() -> void:
		var stored_id := store.get_item_at(Vector2i.ZERO)
		observed_split.append(Vector2i(Supplies.quantity(stock.get_item(source_id)),
			Supplies.quantity(stock.get_item(stored_id))))
	store.changed.connect(observe_split)
	_check(stock.drop_split("bag", source_id, 7, "stash:0", Vector2i.ZERO).is_empty()
		and observed_split == [Vector2i(43, 7)], "A native cross-grid observer sees both new quantities after one commit")
	var original := stock.get_item(source_id).duplicate(true)
	var staged := original.duplicate(true)
	staged["quantity"] = 1
	var collision := Supplies.material("bone_shard")
	collision["id"] = "transaction_probe"
	var rows: Array[Dictionary] = [Inventory._placement_change(bag, &"transaction_probe", {},
		Inventory._supply_placement(&"transaction_probe", Vector2i.ZERO))]
	_check(not stock._commit_grid_records(rows, {source_id: staged, &"transaction_probe": collision})
		and stock.get_item(source_id) == original and stock.get_item(&"transaction_probe").is_empty(),
		"Native collision restores staged records and leaves source payload untouched")
	bag.changed.disconnect(observe_pack)
	store.changed.disconnect(observe_split)


func _check_physical_card_controls() -> void:
	const CARD_ID := "oathbound_three"
	const INSTANCE := &"test_unlearned_card"
	const SEAL := &"test_card_seal_stack"
	const DUPLICATE := &"test_card_duplicate"
	var unopened := CardItems.make(CARD_ID, String(INSTANCE))
	var catalog_card: Dictionary = CardDeck.Catalog.CARDS[CARD_ID]
	var full_pack := Inventory.new()
	_check(full_pack.add_treasure_keys(Inventory.BAG_SIZE.x * Inventory.BAG_SIZE.y)
		and not full_pack.add_item(unopened) and full_pack.get_item(INSTANCE).is_empty(),
		"A full pack rejects a physical card without adding a record")
	var stock := Inventory.new()
	var seals := Supplies.unveiling_scroll()
	seals["id"] = String(SEAL)
	seals["quantity"] = 2
	_check(stock.add_item(unopened) and stock.add_item(seals), "Physical card and two Seals occupy separate pack cells")
	var raw := stock.save_data()
	_check(stock.restore_data(raw), "A masked physical card and Seal stack survive a checkpoint")
	var card := stock.get_item(INSTANCE)
	_check(card.get("unidentified", false) and not card.has("description") and not card.has("art")
		and Items.visible_name(card) == CardItems.UNIDENTIFIED_NAME
		and Art.texture_for_item(card) == CardItems.BACK_ART
		and not Board._matching_stash_item(card, PackedStringArray(["oathbound"]), "", "")
		and not Board._matching_stash_item(card, PackedStringArray(), String(catalog_card.rarity), ""),
		"Masked card search and art reveal no title, catalogue rarity or mechanics")
	var deck := CardDeck.new()
	var bag := stock.get_grid("bag")
	var original := bag.get_placement(INSTANCE)
	_panel = BOARD_SCENE.instantiate()
	_panel.bind(stock)
	_panel.bind_card_deck(deck)
	root.add_child(_panel)
	_panel.open()
	await _frames()
	var grid := _panel._bag_grid
	var item_at := _grid_point(grid, original.origin)
	var seal_at := _grid_point(grid, bag.get_placement(SEAL).origin)
	_hover(item_at)
	await _frames()
	var concealed_lines := _tooltip_lines()
	_check(CardItems.UNIDENTIFIED_NAME in concealed_lines and not catalog_card.name in concealed_lines
		and not catalog_card.description in concealed_lines, "Unidentified hover shows generic title and instructions")
	_click(item_at, false, MOUSE_BUTTON_RIGHT)
	_check(not deck.owned.has(CARD_ID) and bag.get_placement(INSTANCE) == original
		and "Seal" in _panel._feedback.text, "Native right-click prompts identification and leaves the physical card alone")
	_click(seal_at, false, MOUSE_BUTTON_RIGHT)
	_click(item_at)
	var revealed := stock.get_item(INSTANCE)
	_check(not revealed.get("unidentified", true) and Items.visible_name(revealed) == catalog_card.name
		and Supplies.quantity(stock.get_item(SEAL)) == 1 and bag.get_placement(INSTANCE) == original
		and Art.texture_for_item(revealed) != CardItems.BACK_ART and not deck.owned.has(CARD_ID),
		"One Seal reveals the catalogue art and description without learning or moving the card")
	_hover(item_at)
	await _frames()
	_check(catalog_card.name in _tooltip_lines() and catalog_card.description in _tooltip_lines(),
		"The revealed hover immediately shows the card's actual effect")
	var reloaded := Inventory.new()
	_check(reloaded.restore_data(stock.save_data()) and not reloaded.get_item(INSTANCE).get("unidentified", true)
		and reloaded.get_item(INSTANCE).description == catalog_card.description,
		"Revealed card state and its exact catalogue identity survive a checkpoint")
	_check(stock.drop_stash_item("bag", INSTANCE, "stash:0", Vector2i.ZERO).is_empty()
		and stock.carried_card_ids() == [CARD_ID] and not stock.learn_card(INSTANCE, deck).is_empty()
		and stock.quick_stash_transfer("stash:0", INSTANCE, "bag").is_empty(),
		"Cards can be stored and returned, and learning only commits from the pack")
	item_at = _grid_point(grid, bag.get_placement(INSTANCE).origin)
	_click(item_at, false, MOUSE_BUTTON_RIGHT)
	_check(deck.owned.has(CARD_ID) and stock.get_item(INSTANCE).is_empty()
		and bag.get_placement(INSTANCE).is_empty() and stock.carried_card_ids().is_empty(),
		"Native right-click learns into the bound collection and consumes the physical card")
	var resumed_deck := CardDeck.new()
	resumed_deck.restore(deck.snapshot())
	stock.add_item(CardItems.make(CARD_ID, String(DUPLICATE), false))
	var duplicate_placement := bag.get_placement(DUPLICATE)
	_click(_grid_point(grid, duplicate_placement.origin), false, MOUSE_BUTTON_RIGHT)
	_check(resumed_deck.owned.has(CARD_ID) and deck.owned.count(CARD_ID) == 1
		and bag.get_placement(DUPLICATE) == duplicate_placement and "already know" in _panel._feedback.text
		and not stock.quick_equip(DUPLICATE).is_empty(),
		"Learned cards persist in the deck, duplicate right-click retains the item, and cards cannot equip")
	var rollback_deck := CardDeck.new()
	_check(not rollback_deck.unlock_when(CARD_ID, func() -> bool: return false)
		and not rollback_deck.owned.has(CARD_ID), "A failed consumption rolls back the attempted collection unlock")
	_panel.free()
	await process_frame


func _grid_point(grid: Control, cell: Vector2i) -> Vector2:
	return grid.global_position + (Vector2(cell) + Vector2.ONE * 0.5) * grid.cell_size


func _drop_point(grid: Control, origin: Vector2i, footprint: Vector2i) -> Vector2:
	return grid.global_position + (Vector2(origin) + Vector2(footprint) * 0.5) * grid.cell_size


func _check_inventory_sounds() -> void:
	var probe := InventoryCueProbe.new()
	root.add_child(probe)
	var services := root.get_node("Services")
	services.register_audio(probe)
	var stock := Inventory.new()
	var bag := stock.get_grid("bag")
	stock.add_item(_weapon("audio_blade", "Practice Blade", 0))
	stock.add_item({"id": "audio_ring", "base_id": "iron_band", "type": "ring", "slot": "ring",
		"name": "Iron Band", "rarity": "normal", "item_level": 1})
	for index in 2:
		var id := StringName("audio_blocker_%d" % index)
		stock.add_item({"id": id, "base_id": "iron_band", "type": "ring", "slot": "ring",
			"name": "Iron Band", "rarity": "normal", "item_level": 1})
		bag.try_move(id, Vector2i(11, 3 + index), false)
	bag.try_move(&"audio_ring", Vector2i(4, 1), false)
	_panel = BOARD_SCENE.instantiate()
	_panel.bind(stock)
	root.add_child(_panel)
	_panel.open()
	await _frames()
	var pack := _panel._bag_grid
	var sword_cell := _grid_point(pack, bag.get_placement(&"audio_blade").origin)
	var footprint: Vector2i = bag.get_placement(&"audio_blade").footprint
	_click(_grid_point(pack, Vector2i(10, 5)))
	_check(probe.take_events().is_empty(), "An empty grid click stays silent")
	_click(sword_cell)
	_check(probe.take_events() == [&"item_grab"], "Click-to-carry requests one generic grab cue")
	_click(_grid_point(pack, Vector2i(11, 5)))
	_check(_panel._carry.is_holding() and probe.take_events().is_empty(), "A rejected placement stays silent")
	_click(_drop_point(pack, Vector2i(4, 1), footprint))
	_check(_panel._carry._carried.id == &"audio_ring" and probe.take_events() == [&"item_place_sword_1h"],
		"A backpack swap plays only the incoming sword's place cue")
	var left_ring: Control = _panel._slots["left_ring"]
	_click(left_ring.get_global_rect().get_center())
	_check(stock.equipped_id("left_ring") == &"audio_ring" and probe.take_events() == [&"item_place_ring"],
		"Equipping a displaced cursor item plays its own place cue")
	_click(left_ring.get_global_rect().get_center(), false, MOUSE_BUTTON_RIGHT)
	_check(stock.equipped_id("left_ring").is_empty() and probe.take_events() == [&"item_place_ring"],
		"Right-click unequip requests one place cue")
	_click(_grid_point(pack, bag.get_placement(&"audio_ring").origin), false, MOUSE_BUTTON_RIGHT)
	_check(stock.equipped_id("left_ring") == &"audio_ring" and probe.take_events() == [&"item_place_ring"],
		"Right-click equip requests one place cue")
	var ring_position := left_ring.get_global_rect().get_center()
	var equipment_revision := stock._gear.revision
	_click(ring_position)
	_click(ring_position)
	_check(not _panel._carry.is_holding() and stock._gear.revision == equipment_revision
		and probe.take_events() == [&"item_grab", &"item_place_ring"],
		"A click return plays one grab and place cue without writing equipment")
	_panel._carry.cancel()
	var ring_dragged := await _drag(ring_position, ring_position)
	_check(ring_dragged and root.gui_is_drag_successful() and stock._gear.revision == equipment_revision
		and probe.take_events() == [&"item_grab", &"item_place_ring"],
		"A native drag can land back in the source slot with the same cues and no equipment write")
	probe.take_events()
	_click(_grid_point(pack, bag.get_placement(&"audio_blade").origin))
	_press_key(KEY_ESCAPE)
	_check(not _panel._carry.is_holding() and probe.take_events() == [&"item_grab"],
		"Cancelling the cursor adds no place cue")
	_panel.open("stash")
	await _frames()
	pack = _panel._bag_grid
	var stash := _panel._stash_grid
	sword_cell = _grid_point(pack, bag.get_placement(&"audio_blade").origin)
	var stash_cell := _grid_point(stash, Vector2i.ZERO)
	var dragged := await _drag(sword_cell, stash_cell)
	_check(dragged and probe.take_events() == [&"item_grab", &"item_place_sword_1h"],
		"A native pack-to-stash drag requests one grab and one place cue")
	_click(stash_cell, true)
	_check(probe.take_events() == [&"item_place_sword_1h"], "Ctrl-withdrawal requests only the place cue")
	stock.set_vendor_items([_weapon("audio_offer", "Merchant Blade", 0)])
	_panel.open("vendor")
	await _frames()
	var vendor := _panel._vendor_grid
	var offer := _grid_point(vendor, stock.get_grid("vendor").get_placement(&"audio_offer").origin)
	_click(offer, true)
	_check(probe.take_events().is_empty(), "An unaffordable merchant purchase stays silent")
	stock.grant_gold(1000)
	_click(offer, true)
	_check(not bag.get_placement(&"audio_offer").is_empty() and probe.take_events() == [&"item_place_sword_1h"],
		"A successful Ctrl-purchase requests exactly one item cue")
	pack = _panel._bag_grid
	_click(_grid_point(pack, bag.get_placement(&"audio_offer").origin), true)
	_check(stock.get_item(&"audio_offer").is_empty() and probe.take_events() == [&"item_place_sword_1h"],
		"A successful Ctrl-sale requests exactly one item cue")
	_panel.free()
	services.unregister_audio(probe)
	probe.free()
	await process_frame


func _tooltip_lines() -> Array[String]:
	var lines: Array[String] = []
	for label: Label in _panel._item_tooltip._panes.find_children("*", "Label", true, false):
		lines.append(label.text)
	return lines


func _drag(start: Vector2, destination: Vector2, on_start: Callable = Callable()) -> bool:
	_hover(start)
	var press := InputEventMouseButton.new()
	press.position = start
	press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var travel := InputEventMouseMotion.new()
	travel.relative = Vector2(16.0, 0.0)
	travel.position = start + travel.relative
	travel.global_position = travel.position
	travel.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(travel, true)
	await _frames()
	var active := root.gui_is_dragging()
	if active and on_start.is_valid():
		on_start.call()
	var destination_motion := InputEventMouseMotion.new()
	destination_motion.position = destination
	destination_motion.global_position = destination
	destination_motion.relative = destination - travel.position
	destination_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	var native := DisplayServer.get_name() != "headless"
	var restore_pointer := DisplayServer.mouse_get_position() if native else Vector2i.ZERO
	# The root Viewport validates engine drag/drop at the current display pointer.
	if native:
		root.warp_mouse(destination)
	else:
		Input.parse_input_event(destination_motion)
		Input.flush_buffered_events()
	root.push_input(destination_motion, true)
	press = press.duplicate()
	press.position = destination
	press.global_position = destination
	press.pressed = false
	root.push_input(press, true)
	if native:
		Input.warp_mouse(restore_pointer)
	await _frames()
	return active

func _hover(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func _click(at: Vector2, control := false, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = button
		event.pressed = pressed
		event.ctrl_pressed = control
		event.shift_pressed = shift
		root.push_input(event, true)

func _shift(pressed: bool) -> void:
	_modifier(KEY_SHIFT, pressed)

func _modifier(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _press_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		root.push_input(event, true)

func _frames() -> void:
	for index in 4:
		await process_frame

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS " + description)
	else:
		_failures += 1
		push_error("FAIL " + description)



