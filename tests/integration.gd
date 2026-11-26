extends SceneTree

const Game = preload("res://main.tscn")
const SaveStore = preload("res://systems/save_store.gd")
const CharacterSlots = preload("res://systems/character_slots.gd")
const Items = preload("res://systems/items.gd")
const Inventory = preload("res://systems/inventory.gd")
const BaseItems = preload("res://data/items/bases.gd")

var _errors := 0
var _checks := 0
var _game: Node3D
var _save_path := "user://test_runs/hearth_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_saved_gear_balance()
	_mount_game(false)
	_check(_game.title_screen.is_open() and _game._modal,
		"Boot shows the title screen with gameplay paused")
	_check(_game.title_screen._buttons.size() == CharacterSlots.SLOT_COUNT and _game.title_screen._characters.is_empty(),
		"An empty roster offers ten character slots")
	_game._save_now()
	await _ticks(30)
	_check(CharacterSlots.list_slots(_save_path).is_empty(), "The title screen does not create a checkpoint")
	_game.title_screen.settings_requested.emit()
	_check(_game._modal and is_instance_valid(_menu_button("Fullscreen")),
		"Title Settings opens while gameplay stays paused")
	await _tap(KEY_ESCAPE)
	_check(_game.title_screen.is_open() and _game._modal,
		"Escape from title Settings returns to the title")
	_game._create_character(0, "Crypt Tester")
	await _ticks(8)
	_check(not _game.title_screen.is_open() and not _game._modal, "New closes the title and starts gameplay")
	_check(_game.hub.is_inside_tree() and not _game.player.combat_enabled, "Fresh character spawns in the hub")
	_check(_game.player.weapon_type == "sword_1h", "Starter sword is equipped")
	var starting_gold: int = _game.inventory.gold
	_check(_game.bestiary_discoveries.is_empty(), "A fresh character starts with an undiscovered bestiary")
	await _tap(KEY_ESCAPE)
	var settings := _menu_button("Settings")
	_check(is_instance_valid(settings), "Pause menu offers Settings")
	if is_instance_valid(settings):
		settings.pressed.emit()
		var fullscreen := _menu_button("Fullscreen") as CheckButton
		_check(is_instance_valid(fullscreen) and not fullscreen.button_pressed, "Fullscreen starts unchecked")
		if is_instance_valid(fullscreen):
			fullscreen.button_pressed = true
			_check(_game._fullscreen, "Fullscreen checkbox updates the game preference")
		var library := _menu_button("Bestiary")
		_check(is_instance_valid(library), "Settings offers the Bestiary")
		if is_instance_valid(library):
			library.pressed.emit()
			_check(_game.bestiary.is_open() and _game._modal, "The Bestiary opens from Settings while gameplay stays paused")
			await _tap(KEY_ESCAPE)
			_check(not _game.bestiary.is_open() and is_instance_valid(_menu_button("Fullscreen")),
				"Escape from the Bestiary grid returns to Settings")

		await _tap(KEY_ESCAPE)
		_check(is_instance_valid(_menu_button("Resume")) and _game._modal,
			"Escape from Settings returns to the paused menu")
		await _tap(KEY_ESCAPE)
		_check(not _game._modal, "Escape from Pause resumes play")
	_check(_game.inventory.get_grid("vendor").get_placements().size() == 10, "Initial vendor catalogue has ten offers")
	var before: Vector3 = _game.player.global_position
	Input.action_press("forward")
	await _ticks(18)
	Input.action_release("forward")
	_check(_game.player.global_position.z < before.z - 0.4, "Forward input moves the player")
	_check(CharacterSlots.load_slot(_save_path, 0).is_empty(), "Playing a new character does not autosave")
	_check(not _game.hub.STATIONS.has("altar") and not _game.hub.STATIONS.has("close_dungeon")
		and not _game.hub.STATIONS.has("open_world") and _game.hub.STATIONS.has("training_portal"),
		"The Refuge still offers Training and has no retired world routes")

	_game.inventory.grant_gold(62)
	_game.progression.restore({"level": 2, "xp": 3, "attributes": {"strength": 1}})
	_game.card_deck.unlock("winter_bell")
	_game.card_deck.equip(0, "winter_bell")
	_game.bestiary_discoveries[0] = true
	_game.lifetime.add("gold_collected", 62)
	_game.unlocked = 3
	_game.completions = 2
	_check(_game.inventory.add_treasure_keys(2), "The old save fixture carries two expedition keys")
	_check(_game._save_now() == OK, "An explicit save checkpoints the current character")
	var legacy_checkpoint := CharacterSlots.load_slot(_save_path, 0)
	legacy_checkpoint["run"] = {"level": 2, "seed": "7395045", "generation_version": 11,
		"floor_index": 1, "floor_states": {"1": {"mob_states": {}, "opened": {"old_coffer": true}}}}
	legacy_checkpoint["in_dungeon"] = true
	legacy_checkpoint["lifetime"]["awards"] = ["vaultbreaker"]
	legacy_checkpoint["open_world_quests"] = {"claimed": ["keep_the_road"], "wilds_defeated": ["GaleWatch/Sentry"]}
	legacy_checkpoint["open_world_climate"] = {"elapsed_seconds": 1800.0}
	var directory := CharacterSlots.directory_for(_save_path, 0)
	_check(SaveStore.write_game(legacy_checkpoint, directory) == OK, "Write a character with a legacy expedition and Open World history")
	legacy_checkpoint = CharacterSlots.load_slot(_save_path, 0)
	var legacy_files := DirAccess.get_files_at(directory)

	_game.free()
	await _ticks(2)
	_mount_game(false)
	_check(_game.title_screen.is_open() and _game.title_screen._characters.has(0),
		"The character roster lists the saved slot")
	_game._save_now()
	await _ticks(30)
	_check(DirAccess.get_files_at(directory) == legacy_files and
		CharacterSlots.load_slot(_save_path, 0) == legacy_checkpoint, "The title leaves an existing checkpoint untouched")
	_game._create_character(1, "Second Tester")
	await _ticks(8)
	_check(_game.hub.is_inside_tree() and _game.bestiary_discoveries.is_empty(),
		"New starts a fresh character with an existing checkpoint present")
	_check(_game.inventory.gold == starting_gold, "New starts with the starter purse")
	_check(_game._fullscreen, "Global settings apply to a New character")
	_game.inventory.grant_gold(57)
	_game._save_now()
	await _ticks(30)
	_check(DirAccess.get_files_at(directory) == legacy_files and
		CharacterSlots.load_slot(_save_path, 0) == legacy_checkpoint and not CharacterSlots.load_slot(_save_path, 1).is_empty(),
		"Saving a second character leaves the first character's checkpoint untouched")

	_game.free()
	await _ticks(2)
	_mount_game()
	await _ticks(9)
	_check(not _game.title_screen.is_open() and not _game._modal, "Continue closes the title and starts gameplay")
	_check(_game.hub.is_inside_tree() and not _game.player.combat_enabled,
		"Continuing a character with an old in-progress expedition starts in the Refuge")
	_check(_game.inventory.gold == int(legacy_checkpoint.inventory.gold)
		and _game.inventory.treasure_key_count() == 0 and _game.player.weapon_type == "sword_1h",
		"Legacy restore preserves gold and gear and clears expedition keys")
	_check(_game.progression.level == 2 and _game.progression.xp == 3
		and _game.progression.attribute(&"strength") == 1 and _game.card_deck.equipped[0] == "winter_bell",
		"Legacy restore preserves level, XP, attributes, and equipped cards")
	_check(_game.bestiary_discoveries.has(0) and _game.unlocked == 3 and _game.completions == 2,
		"Legacy restore preserves Bestiary and completion history")
	var restored_statistics: Dictionary = _game.lifetime.snapshot()
	_check(int(restored_statistics.totals.get("gold_collected", 0)) == 62,
		"Legacy restore preserves lifetime gold collected")
	_check("vaultbreaker" in restored_statistics.awards and _game.lifetime.points() == 15
		and _game.lifetime.achievements().is_empty() and not _game.lifetime.groups().has("Exploration"),
		"Retired dungeon awards keep their earned points without displaying retired goals")
	_check(_game._save_now() == OK, "A continued legacy character still saves successfully")
	var migrated := CharacterSlots.load_slot(_save_path, 0)
	_check(not migrated.is_empty() and not migrated.has("run") and not migrated.has("in_dungeon")
		and not migrated.has("open_world_quests") and not migrated.has("open_world_climate"),
		"The next checkpoint drops the retired world payloads")
	_game.free()
	await _ticks(4)
	for slot in [0, 1]:
		var slot_directory := CharacterSlots.directory_for(_save_path, slot)
		for filename in DirAccess.get_files_at(slot_directory):
			DirAccess.remove_absolute(slot_directory.path_join(filename))
		DirAccess.remove_absolute(slot_directory)
	for filename in DirAccess.get_files_at(_save_path):
		DirAccess.remove_absolute(_save_path.path_join(filename))
	DirAccess.remove_absolute(_save_path)
	print("Hearth Below integration: %d checks, %d failures" % [_checks, _errors])
	quit(1 if _errors > 0 else 0)


func _check_saved_gear_balance() -> void:
	var shop_item := {"price": 42, "gold_value": 11}
	_check(Inventory.sell_price(shop_item) == 3 and Inventory.buy_price(shop_item) == 42,
		"Merchant resale pays less while preserving listed purchase prices")
	var legacy := Items.starter_weapon()
	legacy.erase("balance_version")
	legacy["id"] = "legacy_sword"
	legacy["rarity"] = "magic"
	legacy["name"] = "Searing Oath Blade"
	legacy["price"] = 35
	legacy["base_stats"] = {"damage_min": 4, "damage_max": 8}
	legacy["prefixes"] = [{"id": "searing", "tier": 4, "name": "Searing", "stats": {"fire_damage": 5}}]
	var inventory := Inventory.new()
	var accepted := inventory.restore_data({"gold": 18, "equipment": [{"item": legacy, "slot": "main_hand"}]})
	_check(accepted, "An earlier equipment snapshot loads with the new balance")
	if not accepted:
		return
	var restored: Dictionary = inventory.equipment["main_hand"]
	_check(restored.id == legacy.id and restored.name == legacy.name and restored.price == 35 and inventory.gold == 18
		and restored.prefixes[0].tier == 4, "Rebalancing saved gear preserves the item, tier, name, and prices")
	_check(is_equal_approx(float(restored.stats.damage_min), 1.0)
		and is_equal_approx(float(restored.stats.damage_max), 3.0)
		and restored.stats.fire_damage == 1,
		"Saved gear adopts the current base and keeps its positive Fire bonus as a whole number")
	_check(Items.restore_item(restored) == restored and not legacy.has("balance_version"),
		"Reopening rebalanced gear keeps the same numbers")
	var old_rapier := Items.training_weapon_item("funeral_rapier", "old_depth_25_rapier")
	old_rapier["item_level"] = 25
	old_rapier["balance_version"] = 2
	old_rapier["prefixes"] = [{"id": "rimed", "tier": 1, "name": "Rimed", "stats": {"cold_damage": 2.4}}]
	old_rapier["price"] = 125
	var upgraded := Items.restore_item(old_rapier)
	_check(upgraded.id == old_rapier.id and upgraded.price == old_rapier.price
		and upgraded.prefixes[0].id == old_rapier.prefixes[0].id
		and upgraded.prefixes[0].tier == old_rapier.prefixes[0].tier and upgraded.stats.cold_damage == 2
		and upgraded.stats.damage_min == 14 and upgraded.stats.damage_max == 24
		and Items.restore_item(upgraded) == upgraded, "High-level saved gear gains item power once without rerolling")
	var scaled_rapier := old_rapier.duplicate(true)
	scaled_rapier["balance_version"] = 3
	scaled_rapier["base_stats"] = {"damage_min": 14.4, "damage_max": 24.0, "lightning_damage": 2.4}
	scaled_rapier["implicit"]["fire_damage"] = 0.7
	scaled_rapier["legendary_stats"] = {"poison_damage": 0.4, "mana_regen": 0.2}
	var rounded := Items.restore_item(scaled_rapier)
	_check(rounded.stats.damage_min == 14 and rounded.stats.damage_max == 24
		and rounded.stats.fire_damage == 1 and rounded.stats.cold_damage == 2
		and rounded.stats.lightning_damage == 2 and rounded.stats.poison_damage == 1
		and is_equal_approx(rounded.stats.mana_regen, 0.2)
		and Items.restore_item(rounded) == rounded,
		"Already-scaled saves round every flat damage type once without rebasing or changing regeneration")
	var armor_base: Dictionary = BaseItems.BASES.filter(func(base: Dictionary) -> bool:
		return base.id == "black_lamellar").front()
	var rng := RandomNumberGenerator.new()
	rng.seed = 851
	var saved_armor := Items.roll_item(30, "normal", rng, 0, armor_base)
	saved_armor.balance_version = 5
	saved_armor.base_stats.armor = 24.0
	saved_armor.base_stats.max_health = 8.0
	var affixes: Array = saved_armor.prefixes.duplicate(true)
	var current_armor := Items.restore_item(saved_armor)
	_check(current_armor.base_stats.armor == 26.0 and current_armor.base_stats.max_health == 9.0
		and current_armor.id == saved_armor.id and current_armor.prefixes == affixes
		and saved_armor.base_stats.armor == 24.0 and Items.restore_item(current_armor) == current_armor,
		"Saved defensive bases gain the revised item level power once and keep their affix rolls")
	var crafted := Items.craft(Items.starter_weapon(), "ash_quench")
	var legendary := Items.training_weapon_preview("bell_of_the_lost", 25)
	_check(crafted.stats.fire_damage == 1 and crafted.prefixes[0].stats.fire_damage == 1
		and legendary.stats.fire_damage == 2 and legendary.legendary_stats.lightning_damage == 3,
		"Crafting and Legendary previews produce whole-number Fire and Lightning modifiers")
	var random := RandomNumberGenerator.new()
	random.seed = 25
	var top_stock := true
	for index in range(24):
		var offer: Dictionary = Items.roll_vendor(25, random, 1)[0]
		var base := Items.training_weapon_item(offer.base_id, "test_base")
		top_stock = top_stock and offer.slot in ["main_hand", "one_hand"] and offer.item_level == 25 and base.item_level >= 8
	_check(top_stock, "A high-level vendor roll reserves a raised item-level offer from its best weapon bases")


func _menu_button(caption: String) -> Button:
	for button: Button in _game.hud.find_children("*", "Button", true, false):
		if button.text == caption:
			return button
	return null


func _mount_game(start_session := true) -> void:
	_game = Game.instantiate()
	_game.save_directory = _save_path
	_game.preferences_path = _save_path.path_join("settings.cfg")
	root.add_child(_game)
	if not start_session:
		return
	_game._select_character(0)


func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(3)
	event = InputEventKey.new()
	event.physical_keycode = key
	Input.parse_input_event(event)
	await _ticks(3)


func _ticks(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS  " + description)
	else:
		_errors += 1
		push_error("FAIL  " + description)
