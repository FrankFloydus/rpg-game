extends SceneTree
## Exercises the actual hidden merchant, trade grid and named-character save path.

const Game := preload("res://main.tscn")
const Dungeon := preload("res://world/dungeon.gd")
const CharacterSlots := preload("res://systems/character_slots.gd")
const SaveStore := preload("res://systems/save_store.gd")
const Items := preload("res://systems/items.gd")
const Inventory := preload("res://systems/inventory.gd")

var _save_directory := "user://test_runs/lantern_broker_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
var _game: Node
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_mount()
	_game._create_character(0, "Lantern Broker Fixture")
	var save := CharacterSlots.load_slot(_save_directory, 0)
	var seed_value := 7395045
	if not await _mount_expedition(save, seed_value):
		_finish()
		return
	var broker := await _meet_broker()
	if not _check(is_instance_valid(broker), "The live interaction picks the revealed merchant"):
		_finish()
		return
	var opening: Dictionary = _game.inventory.vendor_catalog_snapshot()
	var hub_stock: Array = _game.inventory.save_data().vendor
	var offer := _first_rare(opening.rows)
	if not _check(not offer.is_empty(), "Broker offers ordinary rare stock through the existing vendor grid"):
		_finish()
		return
	_check(opening.rows.all(func(row: Dictionary) -> bool:
		return row.item.rarity == "legendary" or (row.item.item_level >= 46 and row.item.item_level <= 50 \
			and row.item.get("unidentified", false) and Items.visible_name(row.item) == row.item.base_name)),
		"Fresh rare offers are unidentified and roll in the five-level band")
	var offer_id := StringName(offer.id)
	_game.inventory.grant_gold(100000)
	var gold: int = _game.inventory.gold
	_check(_game.inventory.quick_purchase(offer_id).is_empty()
		and _game.inventory.gold == gold - Inventory.buy_price(offer),
		"The standard quick-buy moves a broker offer and charges exactly its displayed price")
	var remaining: Dictionary = _game.inventory.vendor_catalog_snapshot()
	_check(remaining.rows.size() == opening.rows.size() - 1
		and _game.inventory.save_data().vendor == hub_stock, "Buying depletes only the hidden catalogue")
	_game.inventory_ui.close()
	_game._last_target = broker
	_game._interact()
	_check(_game.inventory.vendor_catalog_snapshot() == remaining, "Reopening preserves the depleted catalogue")
	gold = _game.inventory.gold
	_check(_game.inventory.quick_sell(offer_id).is_empty() and _game.inventory.gold == gold + Inventory.sell_price(offer),
		"The same vendor accepts items sold from the pack")
	_check(_game._save_now() == OK, "A save captures broker depletion while the panel is open")
	_game.free()
	_mount()
	_game._select_character(0)
	_check(not _game.in_dungeon and _game.inventory.save_data().vendor == hub_stock,
		"Reload starts in Cinderhold with the original merchant stock")
	_game._enter_dungeon(true)
	await _ticks(5)
	broker = _game._dungeon_floors[0].broker
	if _check(is_instance_valid(broker) and broker.pick_available(), "Reload remembers the revealed broker"):
		_game._last_target = broker
		_game._interact()
		var restored: Dictionary = _game.inventory.vendor_catalog_snapshot()
		# Checkpoint JSON represents saved numbers as floats even though live placements store integers.
		var saved_value: Variant = JSON.parse_string(JSON.stringify(remaining, "", true, true))
		var restored_value: Variant = JSON.parse_string(JSON.stringify(restored, "", true, true))
		_check(saved_value == restored_value, "Reload preserves the exact prices, rolls and depleted offer")
	var new_seed := seed_value + 1760273
	if await _mount_expedition(save, new_seed):
		broker = await _meet_broker()
		if _check(is_instance_valid(broker), "The second hidden merchant opens through the same interaction"):
			var distinct: Dictionary = _game.inventory.vendor_catalog_snapshot()
			_check(_names(opening.rows) != _names(distinct.rows), "A different broker appearance rolls different visible bases and prices")
	_finish()


func _mount() -> void:
	_game = Game.instantiate()
	_game.save_directory = _save_directory
	_game.preferences_path = _save_directory.path_join("window.cfg")
	root.add_child(_game)


func _mount_expedition(original: Dictionary, seed_value: int) -> bool:
	var save := original.duplicate(true)
	save.unlocked = 51
	save.run = {
		"level": 50, "seed": str(seed_value), "generation_version": Dungeon.GENERATION_VERSION,
		"rarity_version": _game.RARITY_PROFILE_VERSION, "cleared": false,
		"floor_index": 0, "floor_count": 3, "floor_rise": 1,
		"features": {"masks": [Dungeon.FEATURE_SECRET_MERCHANT, 0, 0], "legate": false},
	}
	if not _check(SaveStore.write_game(save, CharacterSlots.directory_for(_save_directory, 0)) == OK,
			"A named fixture owns the seeded expedition"):
		return false
	_game.free()
	_mount()
	_game._select_character(0)
	for floor in _game._dungeon_floors.values():
		for enemy in floor.enemies.values():
			enemy.set_physics_process(false)
	_game._enter_dungeon(true)
	await _ticks(5)
	return _check(_game.in_dungeon and _game._dungeon_floor_index() == 0, "The real hub portal enters this expedition")


func _meet_broker() -> Node3D:
	var floor: Variant = _game._dungeon_floors[0]
	var broker: Node3D = floor.broker
	if not _check(is_instance_valid(broker) and not broker.pick_available(), "Broker starts inaccessible behind the secret"):
		return null
	var slab: Node3D
	for prop: Node3D in floor.props.get_children():
		if prop.payload.kind == "secret_passage" and prop.payload.id == broker.passage_id:
			slab = prop
			break
	if not _check(is_instance_valid(slab), "The merchant is bound to an actual secret slab"):
		return null
	_game._last_target = slab
	_game._interact()
	await _ticks(45)
	var target: Vector3 = broker.global_position + broker.interaction_point
	var aim := target + broker.global_basis.z.normalized() * 1.15
	var aimed: Node3D = _game._pick_prop(aim, (target - aim).normalized(), floor.props.get_children())
	if aimed != broker:
		return null
	_game._last_target = aimed
	_game._interact()
	return aimed if _game.inventory_ui.is_open() else null


func _first_rare(rows: Array) -> Dictionary:
	for row: Dictionary in rows:
		if row.item.rarity == "rare":
			return row.item
	return {}


func _names(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> Array: return [Items.visible_name(row.item), row.item.price])


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL " + description)
	return condition


func _finish() -> void:
	if is_instance_valid(_game):
		_game.free()
	print("Secret Broker trade: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
