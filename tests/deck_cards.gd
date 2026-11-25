extends SceneTree

const Game = preload("res://main.tscn")
const Catalog = preload("res://data/card_catalog.gd")
const CardItems := preload("res://systems/card_items.gd")
const CharacterSlots = preload("res://systems/character_slots.gd")
const Effects = preload("res://combat/cards/card_effects.gd")
const Inventory := preload("res://systems/inventory.gd")
const Supplies := preload("res://systems/pack_supplies.gd")

var _game: Node3D
var _checks := 0
var _failures := 0
var _legacy_bag_card_id := &""
var _save_path := "user://test_runs/cards_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_mount()
	_game.title_screen.character_created.emit(0, "Card Deck Fixture")
	await _ticks(2)
	_check(Catalog.CARDS.size() == 11 and Catalog.CARDS.has("oathbound_three"),
		"The collection includes the ten original cards and Oathbound Three")
	_check(_game.card_deck.equipped == Catalog.STARTERS, "Every new player gets the three starters")
	await _tap(KEY_Q, KEY_PAUSE)
	_check(_game._card_editor_open and _game._modal and is_equal_approx(Engine.time_scale, 1.0),
		"Logical Q with an unreliable Windows scancode opens the hub collection")
	_game.card_deck.unlock("winter_bell")
	_game.card_screen.slot_changed.emit(1, "winter_bell")
	_check(_game.card_deck.equipped[1] == "winter_bell", "Collection selection replaces the chosen slot")
	_game.card_screen.slot_changed.emit(1, "cinder_circle")
	await _tap(KEY_ESCAPE, KEY_PAUSE)
	_check(not _game.card_screen.visible and _game.player.gameplay_enabled, "Escape closes the editor")
	await _tap(KEY_ESCAPE)
	await _activate_pause_action("Deck")
	_check(_game.card_screen.visible and not _game.hud.is_menu_open(),
		"Pause offers the same deck editor as Q")
	await _tap(KEY_Q)
	_check(_game.player.gameplay_enabled and not _game._modal, "Closing the pause-opened deck restores gameplay")
	_game._rng.seed = 7395045
	_game._select_depth(1)
	await _ticks(3)
	_check(_game._remaining_cards() == Catalog.STARTERS, "An expedition captures the current loadout")
	var notice: Label = _game.hud.get_node("WorldContent/Notice")
	_check(notice.visible and not notice.text.is_empty(), "The expedition objective notice is visible before cards open")
	_game.player.life = 5.0
	var mana: float = _game.player.mana
	var clock: float = _game._combat_clock
	await _tap(KEY_ESCAPE)
	await _activate_pause_action("Cards")
	_check(_game._card_hand_open and is_equal_approx(Engine.time_scale, 0.075),
		"Cards in Pause opens the 7.5 percent speed hand and releases the pause")
	_check(not notice.visible, "Opening the combat hand suppresses the objective notice behind the fan")
	_check(not _game._modal and _game._actors.process_mode == Node.PROCESS_MODE_INHERIT
		and not _game.player.gameplay_enabled and _game._combat_clock > clock,
		"Combat keeps simulating slowly while normal player controls are gated")
	_game.card_screen._hand[0].pressed.emit()
	await _ticks(2)
	_check(_game.player.life > 13.0 and is_equal_approx(_game.player.mana, mana),
		"Red Mercy heals and spends no mana")
	_check(not _game._card_hand_open and is_equal_approx(Engine.time_scale, 1.0)
		and _game.player.gameplay_enabled and _game.run.used_cards.has("red_mercy"),
		"Playing a card closes the hand and spends it once")
	_check(notice.visible and not notice.text.is_empty(), "Closing the combat hand restores HUD notices")
	await _tap(KEY_Q)
	_check(_game.card_screen._hand.size() == 2, "The used card is absent on reopen")
	await _tap(KEY_ESCAPE)
	_check(not _game.card_screen.visible and not _game._modal, "Escape dismisses the hand without pausing")
	_game._actors.process_mode = Node.PROCESS_MODE_DISABLED
	var nearby: Node3D = _game._enemies.values()[0]
	nearby.global_position = _game.player.global_position + Vector3.RIGHT * 1.8
	nearby.health = 100.0
	await _ticks(2)
	await _tap(KEY_Q)
	_game.card_screen._hand[0].pressed.emit()
	await _ticks(2)
	_check(nearby.health < 100.0 and _game.run.used_cards.has("cinder_circle"),
		"Cinder Circle hits a nearby enemy through the expedition combat pipeline")
	await _tap(KEY_Q)
	_game.card_screen._hand[0].pressed.emit()
	await _ticks(2)
	_check(is_equal_approx(_game.player.card_effects.attack_multiplier(), 1.35),
		"Iron Oath arms its landed-attack modifier")
	_check(_game._remaining_cards().is_empty(), "All three cards stay spent")
	await _tap(KEY_Q)
	_check(not _game.card_screen.visible and _game.player.gameplay_enabled
		and _game.hud.get_node("WorldContent/Notice").text == "All expedition cards are spent",
		"Q explains an exhausted hand without suspending controls")
	var next_floor: Node3D = _game._dungeon_floors[1].geometry
	_game.player.place_at(next_floor.to_global(next_floor.spawn_position))
	_game._track_dungeon_floor()
	await _ticks(3)
	_check(_game._dungeon_floor_index() == 1 and _game._remaining_cards().is_empty(),
		"Changing floors does not refresh the hand")
	_game._enter_hub()
	await _tap(KEY_Q)
	_check(_game.card_screen.visible and not _game.in_dungeon and _read_only_deck(),
		"Q shows the read-only deck in the refuge with an expedition open")
	_game.card_screen.slot_changed.emit(1, "winter_bell")
	_check(_game.card_deck.equipped[1] == "cinder_circle", "The parked expedition rejects loadout edits")
	await _tap(KEY_ESCAPE)
	_check(_game.player.gameplay_enabled and is_equal_approx(Engine.time_scale, 1.0),
		"Closing the read-only deck restores controls in the refuge")
	_game._enter_dungeon(true)
	_check(_game._remaining_cards().is_empty(), "Returning through the hub cannot refresh cards")
	await _check_drop()
	await _check_training_cards()
	_game.save_enabled = true
	_check(_game._save_now() == OK, "Card deck and run save to a checkpoint")
	_game.free()
	_mount()
	_game.save_enabled = true
	_game.title_screen.character_selected.emit(0)
	await _ticks(3)
	_check(_game.card_deck.owned.has("winter_bell") and _game.card_deck.owned.has("pilgrim_reserve")
		and _game._remaining_cards().is_empty() and not _game.in_dungeon
		and _game._dungeon_floor_index() == 0,
		"Selecting the character restores collection and spent cards from the refuge")
	var legacy_card: Dictionary = _game.inventory.get_item(_legacy_bag_card_id)
	_check(CardItems.is_card(legacy_card) and legacy_card.get("unidentified", false)
		and not _game.card_deck.owned.has("hollow_thunder"),
		"Character save preserves the recovered hidden card in the pack without learning it")
	_game._close_dungeon()
	_game._select_depth(1)
	await _ticks(2)
	_check(_game._remaining_cards() == Catalog.STARTERS, "A fresh expedition refreshes the chosen cards")
	await _tap(KEY_Q)
	_game.free()
	_check(is_equal_approx(Engine.time_scale, 1.0), "Leaving the scene restores world time")
	_check_buffs()
	_cleanup()
	print("Hearth Below expedition cards: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _mount() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	_game.save_directory = _save_path
	root.add_child(_game)


func _activate_pause_action(action: String) -> void:
	for candidate: Button in _game.hud.find_children("*", "Button", true, false):
		if candidate.text == action and candidate.is_visible_in_tree():
			candidate.grab_focus()
			await _tap(KEY_ENTER)
			return
	_check(false, "Pause exposes %s" % action)


func _read_only_deck() -> bool:
	var card_count := 0
	for face: Button in _game.card_screen.find_children("*", "Button", true, false):
		if face.accessibility_name in ["Red Mercy", "Cinder Circle", "Iron Oath"]:
			if not face.disabled:
				return false
			card_count += 1
	return card_count == 3


func _check_drop() -> void:
	var point: Vector3 = _game.dungeon.to_global(_game.dungeon.spawn_position)
	var before: int = _game.run.loot.size()
	for index in 400:
		_game._drop_card_reward(str(index), "normal", point, 0)
	_check(_game.run.loot.size() == before, "Normal monsters cannot drop cards")
	for index in 400:
		_game._drop_card_reward(str(index), "rare", point, 0)
	var cards: Array[Node3D] = []
	for prop: Node3D in _game._loot.values():
		if prop.payload.get("category") == "card":
			cards.append(prop)
	if not _check(cards.size() == 1, "A rare kill drops a single available physical card"):
		return
	var prop := cards[0]
	var physical_card: Dictionary = prop.payload.item
	var id := StringName(physical_card.id)
	var ground_id: String = prop.payload.id_on_ground
	var illustration := prop.find_child("Illustration", true, false) as MeshInstance3D
	var face := illustration.material_override as StandardMaterial3D if illustration != null else null
	_check(prop.text == CardItems.UNIDENTIFIED_NAME and not prop._legendary
		and physical_card.get("unidentified", false) and not physical_card.has("art")
		and face != null and face.albedo_texture == CardItems.BACK_ART,
		"A fresh world card shows the generic back and label without rarity or title")
	var inventory: Inventory = _game.inventory
	var empty_cells := Inventory.BAG_SIZE.x * Inventory.BAG_SIZE.y
	for placement: Dictionary in inventory.get_grid("bag").get_placements():
		var footprint: Vector2i = placement.footprint
		empty_cells -= footprint.x * footprint.y
	var before_fill := inventory.save_data()
	if _check(inventory.add_treasure_keys(empty_cells), "The pack fixture fills every remaining cell"):
		_game._pickup(prop)
		_check(_game.run.loot.has(ground_id) and inventory.get_item(id).is_empty(),
			"A full pack leaves the same physical card on the ground")
		_check(inventory.restore_data(before_fill), "Restoring the fixture pack frees room for the drop")
	_game._pickup(prop)
	_check(not _game.run.loot.has(ground_id) and CardItems.is_card(inventory.get_item(id))
		and not _game.card_deck.owned.has("pilgrim_reserve"),
		"Pickup moves the card to the backpack as a hidden item")
	var after_pickup: int = _game.run.loot.size()
	for index in 100:
		_game._drop_card_reward(str(index + 400), "rare", point, 1)
	_check(_game.run.loot.size() == after_pickup, "Carrying an unknown card suppresses reoffering that card")
	_check(not inventory.learn_card(id, _game.card_deck).is_empty(),
		"An unidentified card cannot be learned")
	var seal := Supplies.unveiling_scroll()
	seal["id"] = "deck_fixture_scribe_seal"
	_check(inventory.add_item(seal) and inventory.identify_item(&"deck_fixture_scribe_seal", id).is_empty()
		and inventory.get_item(id).name == Catalog.CARDS.pilgrim_reserve.name
		and not _game.card_deck.owned.has("pilgrim_reserve"),
		"One Scribe's Seal reveals the physical card while it remains in the pack")
	await _right_click_pack_card(id)
	_check(_game.card_deck.owned.has("pilgrim_reserve") and inventory.get_item(id).is_empty(),
		"Right-clicking the identified card learns it and consumes the inventory item")
	var legacy_ground_id := str(_game.run.next_loot)
	_game._store_loot({"category": "card", "card_id": "hollow_thunder"}, point, _game._dungeon_floor_index())
	var legacy: Node3D = _game._loot[legacy_ground_id]
	_check(legacy.text == CardItems.UNIDENTIFIED_NAME and not legacy._legendary,
		"A pre-existing Legendary ground record has the same anonymous label and no beam")
	_legacy_bag_card_id = StringName(_game._physical_reward_card(
		"hollow_thunder", _game._dungeon_floor_index(), legacy_ground_id).id)
	_game._pickup(legacy)
	_check(inventory.get_item(_legacy_bag_card_id).get("unidentified", false)
		and not _game.card_deck.owned.has("hollow_thunder"),
		"Picking up an old ground record creates a hidden card without unlocking it")


func _right_click_pack_card(id: StringName) -> void:
	_game._open_inventory("inventory")
	await _ticks(2)
	var grid: Control = _game.inventory_ui._bag_grid
	var placement: Dictionary = _game.inventory.get_grid("bag").get_placement(id)
	if not placement.is_empty():
		var center := (Vector2(placement.origin) + Vector2.ONE * 0.5) * float(grid.cell_size)
		var screen_point := grid.get_global_transform_with_canvas() * center
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.position = screen_point
			click.global_position = screen_point
			click.button_index = MOUSE_BUTTON_RIGHT
			click.pressed = pressed
			root.push_input(click, true)
			await _ticks(1)
	await _tap(KEY_ESCAPE)


func _check_training_cards() -> void:
	var campaign_deck: Dictionary = _game.card_deck.snapshot()
	var campaign_spent: Dictionary = _game.run.used_cards.duplicate()
	var campaign_buffs: Dictionary = _game.player.card_effects.snapshot()
	_game._enter_hub()
	_game._enter_training_ground()
	await _ticks(2)
	_check(_game._remaining_cards() == Catalog.STARTERS and
		is_equal_approx(_game.player.card_effects.attack_multiplier(), 1.0),
		"Training starts with fresh cards and suspends the parked expedition's buffs")

	await _tap(KEY_ESCAPE)
	await _activate_pause_action("Training Deck")
	var choices := 0
	for face: Button in _game.card_screen.find_children("*", "Button", true, false):
		if not face.accessibility_description.is_empty() and not face.disabled:
			choices += 1
	_check(_game._card_editor_open and choices == Catalog.CARDS.size(),
		"Pause opens an editable training loadout with all ten cards")
	_game.card_screen.slot_changed.emit(1, "hollow_thunder")
	_game.card_screen.slot_changed.emit(2, "lantern_ward")
	_check(_game._remaining_cards() == ["red_mercy", "hollow_thunder", "lantern_ward"] and
		_game.card_deck.snapshot() == campaign_deck,
		"Training loadout edits are separate from campaign unlocks and equipment")
	await _tap(KEY_ESCAPE)

	await _tap(KEY_F1)
	_game.training_roster.spawn_requested.emit(0)
	await _ticks(2)
	var enemy: CharacterBody3D
	for actor: Node in _game._training_actors.get_children():
		if actor is CharacterBody3D and actor.is_in_group("enemies"):
			enemy = actor
			break
	if not _check(is_instance_valid(enemy), "The training roster supplies a real arena target"):
		_game._leave_training_ground()
		_game._enter_dungeon(true)
		return
	enemy.set_physics_process(false)
	enemy.global_position = _game.player.global_position + Vector3.RIGHT * 1.8
	enemy.health = 100.0
	_game.player.life = 5.0

	await _tap(KEY_Q)
	_check(_game._card_hand_open and _game.card_screen._hand.size() == 3 and
		_game._training_actors.can_process() and is_equal_approx(Engine.time_scale, 0.075),
		"Q opens a slow-time fan of three cards with arena combat still running")
	if _game._card_hand_open:
		_game.card_screen._hand[0].pressed.emit()
	await _ticks(2)
	_check(_game.player.life > 13.0 and _game._remaining_cards().size() == 2,
		"Playing Red Mercy in training heals and spends the card")

	await _tap(KEY_Q)
	if _game._card_hand_open:
		_game.card_screen._hand[0].pressed.emit()
	await _ticks(2)
	_check(enemy.health < 100.0 and enemy.is_stunned() and _game._remaining_cards() == ["lantern_ward"],
		"Playing Hollow Thunder damages and stuns the matched-level arena target, leaving one card")

	await _tap(KEY_Q)
	if _game._card_hand_open:
		_game.card_screen._hand[0].pressed.emit()
	await _ticks(2)
	_check(is_equal_approx(_game.player.card_effects.incoming_multiplier(), 0.55) and
		_game._remaining_cards().is_empty(),
		"The training hand stays spent and protection applies in combat")
	await _tap(KEY_Q)
	_check(not _game._card_hand_open and _game.player.gameplay_enabled,
		"Opening an exhausted training hand keeps the player in control")

	_game.save_enabled = true
	var saved_ok: bool = _game._save_now() == OK
	_game.save_enabled = false
	var saved := CharacterSlots.load_slot(_save_path, 0)
	var saved_buffs := Effects.new()
	saved_buffs.restore(saved.get("run", {}).get("card_buffs", {}))
	_check(saved_ok and saved.get("card_deck", {}) == campaign_deck and
		saved.get("run", {}).get("used_cards", {}) == campaign_spent and saved_buffs.snapshot() == campaign_buffs,
		"A save during training records only campaign cards, spends, and buffs")

	_game._reset_training_combat()
	_check(_game._remaining_cards() == ["red_mercy", "hollow_thunder", "lantern_ward"] and
		is_equal_approx(_game.player.card_effects.incoming_multiplier(), 1.0),
		"Resetting the arena refreshes the training deck and clears its buffs")
	await _tap(KEY_Q)
	_check(_game._card_hand_open, "The refreshed training hand opens for the next arena fight")
	_game._reset_training_combat()
	_check(not _game._card_hand_open and _game.player.gameplay_enabled and is_equal_approx(Engine.time_scale, 1.0),
		"Resetting an open training hand restores world time and controls")
	_game._leave_training_ground()
	_game._enter_dungeon(true)
	_check(_game._remaining_cards().is_empty() and _game.card_deck.snapshot() == campaign_deck and
		_game.player.card_effects.snapshot() == campaign_buffs,
		"Returning to the expedition restores its original deck, spent cards, and buff timers")


func _check_buffs() -> void:
	var effects := Effects.new()
	effects.apply_buffs(Catalog.CARDS.iron_oath)
	effects.apply_buffs(Catalog.CARDS.sable_benediction)
	_check(is_equal_approx(effects.attack_multiplier(), 1.65), "Distinct attack buffs stack additively")
	for count in 3:
		effects.weapon_landed()
	_check(is_equal_approx(effects.attack_multiplier(), 1.30), "Each landed weapon action consumes one Oath use")
	effects.apply_buffs(Catalog.CARDS.lantern_ward)
	_check(is_equal_approx(effects.incoming_multiplier(), 0.55), "Lantern Ward reduces incoming damage")
	effects.advance(12.1)
	_check(is_equal_approx(effects.attack_multiplier(), 1.0)
		and is_equal_approx(effects.incoming_multiplier(), 1.0), "Timed buffs wear off in world time")


func _tap(key: int, reported_physical := -1) -> void:
	var physical_key := key if reported_physical < 0 else reported_physical
	var press := InputEventKey.new()
	press.physical_keycode = physical_key
	press.keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await _ticks(2)
	var release := InputEventKey.new()
	release.physical_keycode = physical_key
	release.keycode = key
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await _ticks(1)


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _cleanup() -> void:
	var slot := CharacterSlots.directory_for(_save_path, 0)
	for filename in DirAccess.get_files_at(slot):
		DirAccess.remove_absolute(slot.path_join(filename))
	DirAccess.remove_absolute(slot)
	DirAccess.remove_absolute(_save_path)


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	return condition
