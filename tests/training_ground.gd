extends SceneTree
## Exercises the Training Ground through the production main scene and input bindings.

const Game = preload("res://main.tscn")
const Catalog = preload("res://combat/enemies/enemy_catalog.gd")
const CardCatalog := preload("res://data/card_catalog.gd")
const Enemy = preload("res://combat/enemies/enemy.gd")
const Gear := preload("res://data/items/bases.gd")
const HeldModels := preload("res://data/items/held_item_models.gd")
const ItemArt := preload("res://ui/item_art.gd")
const Items = preload("res://systems/items.gd")
const SaveStore = preload("res://systems/save_store.gd")
const CharacterSlots = preload("res://systems/character_slots.gd")
const Arena = preload("res://world/training_ground.gd")
const SEED := 7395045

var _game: Node3D
var _checks := 0
var _failures := 0
var _save_path := "user://test_runs/training_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := {"character_name": "Existing Tester", "inventory": {"gold": 917}, "unlocked": 7}
	var slot := CharacterSlots.directory_for(_save_path, 0)
	_check(SaveStore.write_game(fixture, slot) == OK, "The title-entry fixture writes an existing checkpoint")
	var checkpoint := CharacterSlots.load_slot(_save_path, 0)
	var checkpoint_files := DirAccess.get_files_at(slot)
	_check_weapon_base_assets()
	_mount_game()
	if await _exercise_title_entry(checkpoint, checkpoint_files):
		_game.free()
		await _ticks(2)
		_mount_game()
		_game._create_character(1, "Training Tester")
		await _exercise_arena()
	_game.free()
	await _ticks(2)
	if DirAccess.dir_exists_absolute(_save_path):
		for index in [0, 1]:
			var directory := CharacterSlots.directory_for(_save_path, index)
			if not DirAccess.dir_exists_absolute(directory):
				continue
			for filename in DirAccess.get_files_at(directory):
				DirAccess.remove_absolute(directory.path_join(filename))
			DirAccess.remove_absolute(directory)
		for filename in DirAccess.get_files_at(_save_path):
			DirAccess.remove_absolute(_save_path.path_join(filename))
		DirAccess.remove_absolute(_save_path)
	print("Hearth Below Training Ground: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_weapon_base_assets() -> void:
	for base: Dictionary in Gear.BASES:
		var type := String(base.type)
		if Gear.TYPES[type].slot not in ["main_hand", "one_hand", "off_hand"]:
			continue
		var id := String(base.id)
		var model := HeldModels.scene_for(id, type)
		var portrait := ItemArt.texture_for_base(id, type)
		_check(model != null and model.resource_path.get_file() == id + ".glb"
			and portrait != null and portrait.resource_path.get_file() == id + ".png",
			"%s resolves its own authored model and portrait" % base.name)


func _mount_game() -> void:
	_game = Game.instantiate()
	_game.save_directory = _save_path
	_game.preferences_path = _save_path.path_join("settings.cfg")
	root.add_child(_game)


func _exercise_title_entry(checkpoint: Dictionary, checkpoint_files: PackedStringArray) -> bool:
	var entry: Button
	for button: Button in _game.title_screen.find_children("*", "Button", true, false):
		if button.text == "Training Ground":
			entry = button
			break
	if not _check(is_instance_valid(entry) and entry.is_visible_in_tree() and not entry.disabled,
			"The title screen offers Training Ground with an existing checkpoint"):
		return false
	entry.grab_focus()
	await _tap(KEY_ENTER)
	var arena: Node3D = _game.training_ground
	if not _check(is_instance_valid(arena) and arena.is_inside_tree() and _on_arrival(arena)
			and not _game.title_screen.is_open() and not _game.hub.is_inside_tree(),
			"The title button starts at the arena entrance"):
		return false
	_check(_game.player.gameplay_enabled and _game.player.combat_enabled
			and _game.player.weapon_type == "sword_1h" and _game.inventory.gold == 30
			and _game.unlocked == 1 and _game.run.is_empty(),
		"Direct entry starts a fresh character with the starter sword and live combat")
	if await _open_roster():
		_check(_game.training_roster.selected_level() == 1, "The title-entry roster defaults to Enemy Level 1")
		var profile_level := _game.training_roster.find_child("PlayerLevel", true, false) as SpinBox
		_game.training_roster.set_player_level(9)
		_check(profile_level.get_line_edit().text == "9" and _game.training_roster.selected_player_level() == 9
			and _game.player.combat_ability_level() == 1, "Quiet Player Level assignment syncs its numeric text")
		profile_level.get_line_edit().text = "25"
		_check(_game.training_roster.selected_player_level() == 25 and _game.player.combat_ability_level() == 25
			and _game.training_roster.selected_level() == 1 and _game.training_roster.selected_weapon_item_level() == 1,
			"Training changes Player Level independently from Enemy and Item Level")
		profile_level.value = 1
		await _tap(KEY_F1)
	await _exercise_training_weaponry()
	await _exercise_player_weapon_traces()
	return _check(_game._save_now() == OK and CharacterSlots.load_slot(_save_path, 0) == checkpoint
		and DirAccess.get_files_at(CharacterSlots.directory_for(_save_path, 0)) == checkpoint_files,
		"Visiting training from the title leaves the existing checkpoint untouched")


func _exercise_training_weaponry() -> void:
	var inventory_before: Dictionary = _game.inventory.save_data()
	var saved_characters := CharacterSlots.list_slots(_save_path)
	if not await _open_roster():
		return
	var tabs := _game.training_roster.find_child("TrainingTabs", true, false) as TabContainer
	if not _check(tabs != null and tabs.get_tab_count() == 3 and tabs.get_tab_title(0) == "Enemy"
			and tabs.get_tab_title(1) == "Weaponry" and tabs.get_tab_title(2) == "Cards",
			"F1 offers Enemy, Weaponry, and Cards in that order"):
		return
	tabs.current_tab = 1
	var grid := _game.training_roster.find_child("WeaponGrid", true, false) as GridContainer
	var authored_weapons := Items.training_weapon_choices()
	if not _check(grid != null and grid.is_visible_in_tree() and grid.get_child_count() == authored_weapons.size(),
			"Weaponry lists all authored main-hand, off-hand, and Legendary items"):
		return
	var listed := {}
	for button: Button in grid.get_children():
		var choice_id := String(button.get_meta("choice_id"))
		var item := Items.training_weapon_item(choice_id, "test_" + choice_id)
		listed[choice_id] = item
	_check(listed.size() == authored_weapons.size() and listed.values().all(func(item: Dictionary) -> bool: return not item.is_empty()),
		"Every Weaponry choice builds a distinct authored item")

	var rapier := grid.get_node("Weapon_funeral_rapier") as Button
	var rapier_base := rapier.get_node("Contents/Labels/BaseStats") as Label
	var rapier_implicit := rapier.get_node("Contents/Labels/ImplicitStats") as Label
	_check(rapier_base.text == "6–10 Physical Damage" and rapier_implicit.text.contains("7% Critical Chance")
		and rapier.tooltip_text.contains("Edged"), "Weaponry shows base damage, implicits, and weapon family")
	var item_level := _game.training_roster.find_child("WeaponItemLevel", true, false) as SpinBox
	item_level.get_line_edit().text = "25"
	var preview_rng := RandomNumberGenerator.new()
	var rare_seed := 0
	for candidate in 200:
		preview_rng.seed = candidate
		var preview := Items.training_weapon_item("funeral_rapier", "fixture", 25, preview_rng, float(_game.player.stats.loot_rarity))
		if preview.get("unidentified", false):
			rare_seed = candidate
			break
	_game._training_rng.seed = rare_seed
	var rolled_drop := await _spawn_weapon_choice(grid, "funeral_rapier")
	if not _check(rolled_drop != null, "Selecting a regular base spawns a real rolled weapon"):
		return
	var rolled: Dictionary = rolled_drop.payload.item
	_check(rolled.base_id == "funeral_rapier" and rolled.item_level == 25 and rolled.rarity in ["magic", "rare"]
		and rolled.prefixes.size() + rolled.suffixes.size() > 0
		and rolled.base_stats.damage_min == 14 and rolled.base_stats.damage_max == 24,
		"The selected base, typed item level, and dungeon affixes reach the actual pickup")
	_check(rapier_base.text == "14–24 Physical Damage" and rapier_implicit.text.contains("7% Critical Chance"),
		"Changing Item Level updates the base preview without adding rolled affixes to the card")
	var practice_seal := false
	for prop: Node3D in _game._training_props.get_children():
		var supply: Dictionary = prop.payload.get("item", {})
		practice_seal = practice_seal or supply.get("supply_kind") == "unveiling_scroll"
	_check(rolled.get("unidentified", false) and practice_seal,
		"A practice rare drops fully pre-rolled alongside a Scribe's Seal for testing")
	if not await _open_roster():
		return
	item_level.value = 1

	var player: CharacterBody3D = _game.player
	var practice: RefCounted = _game._training_inventory
	var starter: StringName = practice.equipped_id("main_hand")
	var first: Node3D = await _spawn_weapon_choice(grid, "pyre_of_the_unburied")
	if not _check(first != null, "Clicking a Legendary in Weaponry spawns a real ground pickup"):
		return
	var axe := StringName(first.payload.item.id)
	_check(player.weapon_type == "sword_1h" and practice.get_item(axe).is_empty(),
		"Clicking Weaponry leaves the item on the ground and keeps the current weapon equipped")
	if not await _open_roster():
		return
	var next: Node3D = await _spawn_weapon_choice(grid, "pyre_of_the_unburied")
	_check(next != null and next != first and next.payload.item.id != first.payload.item.id
		and next.global_position.distance_to(first.global_position) > 0.75,
		"Spawning one weapon twice creates separate pickups with separate item IDs")
	await _pick_up_practice_item(first)
	_check(practice.get_item(axe).get("legendary_id") == "pyre_of_the_unburied"
		and player.weapon_type == "sword_1h" and _game.inventory.get_item(axe).is_empty(),
		"E moves the pickup into the practice pack for manual equipping")
	await _tap(KEY_I)
	if not _check(_game.inventory_ui.is_open() and _game.inventory_ui._inventory == practice,
			"I opens the normal inventory with the practice pack bound"):
		return
	_quick_equip_practice_item(axe)
	_check(player.weapon_type == "axe_2h" and player._weapon._type == "axe_2h" and player.effects.has("ashwake")
		and practice.equipped_id("off_hand") == axe and player.stats == Items.player_stats(practice.equipment),
		"Right-clicking the pickup equips its real first-person model, stats and Legendary effect")
	await _tap(KEY_I)

	if not await _open_roster():
		return
	var shield_drop: Node3D = await _spawn_weapon_choice(grid, "the_pale_door")
	if not _check(shield_drop != null, "Weaponry also spawns Legendary off-hand pickups"):
		return
	var shield := StringName(shield_drop.payload.item.id)
	await _pick_up_practice_item(shield_drop)
	await _tap(KEY_I)
	_quick_equip_practice_item(shield)
	_check(practice.equipped_id("off_hand") == axe and not player._shield_equipped,
		"Inventory still enforces the two-handed equipment rule")
	_quick_equip_practice_item(starter)
	_quick_equip_practice_item(shield)
	_check(practice.equipped_id("off_hand") == shield and player._shield_equipped
		and player._weapon._secondary == "shield" and player.effects.has("frostguard"),
		"After equipping a one-handed weapon, the Legendary shield equips and enables its effect")
	await _tap(KEY_I)
	_check(_game.inventory.save_data() == inventory_before and CharacterSlots.list_slots(_save_path) == saved_characters,
		"Practice gear leaves campaign gear and saved characters untouched")
	if await _open_roster():
		tabs.current_tab = 0
		await _tap(KEY_F1)


func _spawn_weapon_choice(grid: GridContainer, choice_id: String) -> Node3D:
	var button := grid.get_node_or_null("Weapon_" + choice_id) as Button
	if button == null or not button.is_visible_in_tree():
		return null
	var count: int = _game._training_props.get_child_count()
	button.pressed.emit()
	await _ticks(3)
	if _game.training_roster.is_open() or _game._training_props.get_child_count() <= count:
		return null
	return _game._training_props.get_child(count) as Node3D


func _exercise_player_weapon_traces() -> void:
	if not await _open_roster():
		return
	var tabs := _game.training_roster.find_child("TrainingTabs", true, false) as TabContainer
	tabs.current_tab = 1
	var toggle := _game.training_roster.find_child("ShowPlayerWeaponTraces", true, false) as CheckButton
	if not _check(toggle != null and toggle.is_visible_in_tree() and not toggle.button_pressed,
			"Weaponry exposes disabled-by-default player weapon trace previews"):
		await _tap(KEY_F1)
		return
	toggle.button_pressed = true
	await _tap(KEY_F1)
	var trace: MultiMeshInstance3D = _game._training_weapon_trace
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await _ticks(2)
	click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(click)
	for frame in 60:
		if trace._count > 0:
			break
		await _ticks(1)
	await _ticks(2)
	_check(trace._count > 0 and trace.multimesh.visible_instance_count > 0,
		"A real input renders the actual sampled melee box transforms")
	if trace._count > 0:
		var remaining: float = trace._expires[trace._head] - trace._time
		_check(remaining > 1.85 and remaining <= 2.01, "The earliest weapon trace starts with a two-second lifetime")
	await _ticks(162)
	_check(trace._count == 0 and trace.multimesh.visible_instance_count == 0,
		"Timed traces clear all boxes after the swing")
	toggle.button_pressed = false


func _pick_up_practice_item(prop: Node3D) -> void:
	_aim(_game.player.global_position, prop.global_position + prop.interaction_point)
	await _tap(KEY_E)


func _quick_equip_practice_item(id: StringName) -> void:
	var grid: Control = _game.inventory_ui._bag_grid
	var placement: Dictionary = grid.inventory.get_grid("bag").get_placement(id)
	if placement.is_empty():
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = (Vector2(placement["origin"]) + Vector2.ONE * 0.5) * grid.cell_size
	grid._gui_input(click)


func _exercise_training_cards(campaign_deck: Dictionary) -> void:
	if not await _open_roster():
		return
	var tabs := _game.training_roster.find_child("TrainingTabs", true, false) as TabContainer
	var tab_bar := tabs.get_tab_bar()
	await _click_menu(tab_bar.get_global_transform_with_canvas() * tab_bar.get_tab_rect(2).get_center())
	var collection := _game.training_roster.find_child("CardCollection", true, false) as GridContainer
	if not _check(tabs.current_tab == 2 and collection != null and collection.is_visible_in_tree()
			and collection.get_child_count() == CardCatalog.CARDS.size(),
			"Clicking Cards opens the embedded collection with every authored card"):
		return
	var slot := _game.training_roster.find_child("DeckSlot2", true, false) as Button
	await _click_menu(slot.get_global_rect().get_center())
	var choice := collection.get_node("DeckCard_hollow_thunder") as Button
	choice.grab_focus()
	await _ticks(3)
	await _tap(KEY_ENTER)
	_check(_game._training_card_deck.equipped[1] == "hollow_thunder" and _game.training_roster.is_open()
		and not _game.player.gameplay_enabled and _game.card_deck.snapshot() == campaign_deck,
		"Mouse slot selection and keyboard card selection edit only the paused practice loadout")
	var empty := _game.training_roster.find_child("EmptySelectedSlot", true, false) as Button
	await _click_menu(empty.get_global_rect().get_center())
	_check(_game._training_card_deck.equipped[1].is_empty(), "The Cards tab can clear the selected slot")
	choice.grab_focus()
	await _tap(KEY_ENTER)
	await _tap(KEY_Q)
	_check(_game.training_roster.is_open() and not _game._card_hand_open and is_equal_approx(Engine.time_scale, 1.0),
		"Q leaves the modal Cards tab in control until the roster closes")
	await _tap(KEY_F1)
	await _tap(KEY_Q)
	_check(_game._card_hand_open and _game._remaining_cards() == ["red_mercy", "hollow_thunder", "iron_oath"],
		"Closing F1 and pressing Q opens the arena hand with the edited slot")
	await _tap(KEY_ESCAPE)
	if not await _open_roster():
		return
	_check(tabs.current_tab == 2 and _game._training_card_deck.equipped[1] == "hollow_thunder"
		and root.gui_get_focus_owner() == _game.training_roster.find_child("DeckSlot1", true, false),
		"Reopening F1 retains the card edit and focuses a visible equipped slot")
	await _click_menu(tab_bar.get_global_transform_with_canvas() * tab_bar.get_tab_rect(0).get_center())
	await _tap(KEY_ESCAPE)
	_check(tabs.current_tab == 0 and not _game.training_roster.is_open() and _game.player.gameplay_enabled,
		"Returning to Enemy and closing the roster restores gameplay")


func _exercise_arena() -> void:
	await _tap(KEY_F1)
	_check(not _game.training_roster.is_open() and _game.player.gameplay_enabled, "F1 leaves hub gameplay unchanged")
	if not await _park_expedition():
		return
	var expedition: Node3D = _game.dungeon
	var expedition_seed := int(_game.run.seed)
	var keys: int = _game.inventory.treasure_key_count()
	var gold := int(_game.inventory.gold)
	var discovery_count: int = _game.bestiary_discoveries.size()
	var survivors: int = _game._enemies.size()
	var first_enemy: CharacterBody3D = _game._enemies.values()[0]
	var parked_position := first_enemy.position
	_check(first_enemy.enemy_level == 1, "The expedition spawner assigns Enemy Level 1 to its first-depth enemies")
	var unlocked := int(_game.unlocked)
	var completions := int(_game.completions)
	var campaign_deck: Dictionary = _game.card_deck.snapshot()
	var hub_gate: Vector3 = _game.hub.interaction_position("training_portal")
	_aim(_game.hub.training_arrival_position(), hub_gate)
	await _ticks(4)
	var campaign_life := float(_game.player.stats.max_health) * 0.60
	_game.player.life = campaign_life
	await _tap(KEY_E)
	if not _check(is_instance_valid(_game.training_ground) and _game.training_ground.is_inside_tree(),
			"Aiming at Training Ground and pressing E enters the arena"):
		return
	var arena: Node3D = _game.training_ground
	_check(_game.player.combat_enabled and _on_arrival(arena), "Arrival places the player at the arena entrance with live combat enabled")
	_check(not expedition.is_inside_tree() and _game.dungeon == expedition,
		"The parked expedition remains detached during training")
	_check(_training_enemies().is_empty(), "The arena initially contains no enemies")
	if not _check(await _wait_for_navigation(arena), "The arena publishes a native navigation map"):
		return
	_check_pillar_cover(arena)
	await _exercise_swimming_pool(arena)
	await _exercise_training_cards(campaign_deck)
	await _check_bestiary_access(true)
	var scene_assets := _check_enemy_scenes()

	if not await _open_roster():
		return
	var grid := _game.training_roster.find_child("EnemyGrid", true, false) as GridContainer
	if not _check(is_instance_valid(grid) and grid.get_child_count() == Catalog.ARCHETYPES.size(),
			"F1 lists one selection for every enemy archetype"):
		return
	var all_selectable := true
	for id in range(Catalog.ARCHETYPES.size()):
		var card := grid.get_node_or_null("Enemy%d" % id) as Button
		all_selectable = all_selectable and card != null and not card.disabled
	_check(all_selectable, "Enemy cards are selectable without campaign discoveries")
	var trace_toggle := _game.training_roster.find_child("ShowAbilityTraces", true, false) as CheckButton
	_check(trace_toggle != null and trace_toggle.is_visible_in_tree() and not trace_toggle.button_pressed,
		"The F1 roster offers Ability Traces and leaves them off by default")

	await _tap(KEY_F1)
	_check(not _game.training_roster.is_open() and _game.player.gameplay_enabled, "F1 toggles the roster closed and resumes play")
	if not await _open_roster():
		return
	await _tap(KEY_ESCAPE)
	_check(not _game.training_roster.is_open() and not _game.hud.is_menu_open() and _game.player.gameplay_enabled,
		"Escape closes the roster and returns to play")

	if not await _choose_enemy(grid, 0):
		return
	var enemies := _training_enemies()
	if not _check(enemies.size() == 1 and int(enemies[0].archetype_id) == 0,
			"The Grave Thrall card spawns its matching enemy and resumes gameplay"):
		return
	var thrall := enemies[0]
	_check(thrall.enemy_level == 1 and thrall.rarity == "normal" and thrall.affixes.is_empty(),
		"The default Training Ground spawn is Level 1 Normal without affixes")
	var normal_stats := Vector3(thrall.max_health, thrall._base_damage, thrall._base_speed)
	var normal_scale: float = thrall._model.scale.x
	_check(await _observe_native_movement(thrall),
		"The spawned Grave Thrall advances through its native behavior runner")
	if not is_instance_valid(_game.training_ground) or _training_enemies().is_empty():
		_check(false, "Grave Thrall survives the movement probe")
		return
	if trace_toggle != null:
		await _check_ability_traces(thrall, trace_toggle)
	var last_id := Catalog.ARCHETYPES.size() - 1
	if not await _open_roster() or not _select_enemy_level(2) or not await _activate_enemy_card(grid, last_id):
		return
	enemies = _training_enemies()
	if not _check(enemies.size() == 2 and thrall in enemies and int(enemies.back().archetype_id) == last_id,
			"The last card spawns a Dread Knight alongside the Grave Thrall"):
		return
	_check(int(Catalog.ARCHETYPES[last_id].level) > 2 and enemies.back().enemy_level == 2 and thrall.enemy_level == 1,
		"The selected Level 2 ignores dungeon eligibility and leaves the existing Level 1 Thrall unchanged")
	_check(enemies[0].global_position.distance_squared_to(enemies[1].global_position) > 1.0,
		"Concurrent spawns use separate positions")
	for enemy in enemies:
		var runner := enemy.get_node_or_null("Brain") as AIBehaviorRunner
		_check(runner != null and runner.tree != null and runner.tree.validate().is_empty() and runner.tree.resource_path.begins_with("res://"),
			"%s uses a valid native behavior tree resource" % enemy.display_name)
		var expected: Dictionary = scene_assets.get(int(enemy.archetype_id), {})
		var attached_ai := enemy.get_script() as GDScript
		_check(not expected.is_empty() and enemy.scene_file_path == expected.scene and attached_ai != null
			and attached_ai.resource_path == expected.ai, "%s spawns from its own combat scene and AI script" % enemy.display_name)

	thrall.take_damage(100000.0, "physical", _game.player)
	_check(int(_game.inventory.gold) == gold and _game.bestiary_discoveries.size() == discovery_count,
		"Training combat does not award gold or populate the campaign Bestiary")
	_check(_game.inventory.treasure_key_count() == keys and int(_game.run.seed) == expedition_seed and not _game.run.cleared
			and int(_game.unlocked) == unlocked and int(_game.completions) == completions and _game._enemies.size() == survivors,
		"Training combat leaves the parked expedition and campaign progress unchanged")

	_game.player.life = float(_game.player.stats.max_health) * 0.30
	_check(_game._save_now() == OK, "Saving while in the arena writes a checkpoint")
	var checkpoint := CharacterSlots.load_slot(_save_path, 1)
	_check(not checkpoint.is_empty() and not checkpoint.has("in_dungeon")
			and int(checkpoint.run.seed) == expedition_seed and absf(float(checkpoint.get("life", 0.0)) - campaign_life) < 0.5,
		"The checkpoint retains the hub return and pre-training Life")
	_check(checkpoint.get("bestiary", []).size() == discovery_count, "The checkpoint only stores campaign discoveries")
	_check(checkpoint.get("card_deck", {}) == campaign_deck,
		"Saving while the practice deck is edited stores only the campaign loadout")

	_game.player.receive_enemy_hit(100000.0, "physical")
	await _ticks(10)
	if not _check(is_instance_valid(_game.training_ground) and _game.training_ground.is_inside_tree()
			and _training_enemies().is_empty() and _on_arrival(_game.training_ground),
			"Defeat resets the arena at the entrance without ending the parked expedition"):
		return
	_check(is_equal_approx(_game.player.life, float(_game.player.stats.max_health)),
		"A training defeat restores the player to full Life in the arena")
	await _check_affixed_spawns(grid, normal_stats, normal_scale)

	var return_portal: Node3D = _game._training_portal
	_aim(_game.training_ground.spawn_position, return_portal.global_position + return_portal.interaction_point)
	await _tap(KEY_E)
	if not _check(not is_instance_valid(_game.training_ground) and _game.hub.is_inside_tree() and not _game.player.combat_enabled,
			"Aiming at the arena return portal and pressing E returns to the hub"):
		return
	_check(_training_enemies().is_empty() and absf(_game.player.life - campaign_life) < 0.5,
		"Leaving the arena clears its actors and restores pre-training Life")
	_check(_game.player._water_volume == null and not _game.player._water_tint.visible,
		"Returning to the hub clears the Training Ground water volume and view")
	_check(_game._training_inventory == null and _game._training_props == null
		and _game.player.weapon_type == "sword_1h" and _game.inventory_ui._inventory == _game.inventory,
		"Leaving discards the practice pack and restores the campaign inventory and held weapon")
	_check(_game._training_card_deck == null and _game.card_deck.snapshot() == campaign_deck,
		"Leaving discards the loadout edited in F1 and restores the campaign deck")
	_check(not is_instance_valid(_game._training_trace_visuals),
		"Leaving the Training Ground removes its trace overlay")
	_check(_game.dungeon == expedition and not expedition.is_inside_tree() and first_enemy.position == parked_position,
		"The parked dungeon retains its actors and their positions")
	await _check_bestiary_access(false)

	var expedition_gate: Vector3 = _game.hub.interaction_position("altar")
	_aim(Vector3(expedition_gate.x, 0.06, expedition_gate.z + 2.0), expedition_gate)
	await _tap(KEY_E)
	_check(_game.in_dungeon and _game.dungeon == expedition and int(_game.run.seed) == expedition_seed,
		"The main altar resumes the same expedition after training")


func _check_enemy_scenes() -> Dictionary[int, Dictionary]:
	var assets: Dictionary[int, Dictionary] = {}
	var directories := {}
	var scripts := {}
	var authored_visuals := 0
	var registered_bipeds := 0
	var inspectable_bipeds := 0
	for id in range(Catalog.ARCHETYPES.size()):
		var actor := Catalog.instantiate(id)
		if actor == null:
			continue
		var scene_path := actor.scene_file_path
		var ai := actor.get_script() as GDScript
		var model := actor.get_node_or_null("Model")
		var collision := actor.get_node_or_null("BodyCollision") as CollisionShape3D
		var animation := actor.get_node_or_null("Model/Rig/AnimationPlayer") as AnimationPlayer
		var skeletons := model.find_children("*", "Skeleton3D") if model != null else []
		if model != null and not model.find_children("*", "MeshInstance3D").is_empty() \
				and not skeletons.is_empty() \
				and collision != null and collision.shape is CapsuleShape3D \
				and animation != null and animation.has_animation(&"Idle") and animation.has_animation(&"Walk") \
				and animation.has_animation(&"Windup") and animation.has_animation(&"Strike"):
			authored_visuals += 1
			var skeleton := skeletons[0] as Skeleton3D
			var spine := skeleton.find_bone(&"Spine")
			var left := skeleton.find_bone(&"ArmLeft1")
			var right := skeleton.find_bone(&"ArmRight1")
			var head := skeleton.find_bone(&"Head")
			if min(spine, left, right, head) >= 0:
				inspectable_bipeds += 1
				if skeleton.get_bone_parent(left) == spine and skeleton.get_bone_parent(right) == spine \
						and skeleton.get_bone_parent(head) == spine:
					registered_bipeds += 1
		if not scene_path.is_empty() and ResourceLoader.exists(scene_path, "PackedScene") and ai != null:
			var directory := scene_path.get_base_dir()
			var definition: Dictionary = actor.definition()
			if ai.resource_path.get_base_dir() == directory and int(definition.get("id", -1)) == id \
					and definition.get("name") == Catalog.ARCHETYPES[id].name:
				assets[id] = {"scene": scene_path, "ai": ai.resource_path}
				directories[directory] = true
				scripts[ai.resource_path] = true
		actor.free()
	var roster_count := Catalog.ARCHETYPES.size()
	_check(assets.size() == roster_count and directories.size() == roster_count and scripts.size() == roster_count,
		"All %d archetypes instantiate their own packed scene and matching AI script" % roster_count)
	_check(authored_visuals == assets.size(), "Every enemy scene owns skinned meshes, a skeleton, collision, and four animation clips")
	_check(inspectable_bipeds >= 15 and registered_bipeds == inspectable_bipeds,
		"Biped head and shoulder joints remain registered to the chest as it moves")
	return assets


func _check_bestiary_access(in_training: bool) -> void:
	await _tap(KEY_ESCAPE)
	_game.hud.settings_requested.emit()
	_game.hud.bestiary_requested.emit()
	var bestiary: Control = _game.bestiary
	var expected_access: bool = bestiary.is_open() and bestiary._cards.size() == Catalog.ARCHETYPES.size()
	for id in bestiary._cards.size():
		var available: bool = in_training or _game.bestiary_discoveries.has(id)
		var selectable: bool = not bestiary._cards[id].disabled
		expected_access = expected_access and selectable == available
	_check(expected_access, "Every Bestiary entry is selectable in training" if in_training else "The hub Bestiary uses campaign discoveries again")
	if in_training and expected_access:
		var last_id := Catalog.ARCHETYPES.size() - 1
		bestiary._cards[last_id].pressed.emit()
		_check(bestiary._active_id == last_id, "The Training Ground Bestiary opens the selected detail page")
		await _tap(KEY_ESCAPE)
	await _tap(KEY_ESCAPE)
	await _tap(KEY_ESCAPE)
	await _tap(KEY_ESCAPE)


func _park_expedition() -> bool:
	_game._rng.seed = SEED
	_game._select_depth(1)
	await _ticks(8)
	if not _check(_game.in_dungeon, "The training test enters a real expedition"):
		return false
	await _tap(KEY_F1)
	_check(not _game.training_roster.is_open() and _game.player.gameplay_enabled,
		"F1 leaves expedition gameplay unchanged")
	_game.inventory.add_treasure_keys(2)
	await _tap(KEY_T)
	var portal: Node3D = _game._portal_prop
	if not _check(is_instance_valid(portal), "T opens the expedition return portal"):
		return false
	_aim(_game.dungeon.spawn_position, portal.global_position + portal.interaction_point)
	await _tap(KEY_E)
	return _check(not _game.in_dungeon and _game.hub.is_inside_tree() and not _game.dungeon.is_inside_tree(),
		"Using the expedition portal parks that world and returns to the hub")


func _open_roster() -> bool:
	await _tap(KEY_F1)
	return _check(_game.training_roster.is_open() and not _game.player.gameplay_enabled
			and not _game._training_actors.can_process(),
		"F1 in the Training Ground opens the roster and suspends combat")


func _choose_enemy(grid: GridContainer, id: int) -> bool:
	if not await _open_roster():
		return false
	return await _activate_enemy_card(grid, id)


func _activate_enemy_card(grid: GridContainer, id: int) -> bool:
	var card := grid.get_node_or_null("Enemy%d" % id) as Button
	if not _check(card != null, "The selected card exists for %s" % Catalog.ARCHETYPES[id].name):
		return false
	card.grab_focus()
	await _tap(KEY_ENTER)
	return _check(not _game.training_roster.is_open() and _game.player.gameplay_enabled,
		"Spawning from the roster closes it and resumes combat")


func _check_affixed_spawns(grid: GridContainer, normal: Vector3, normal_scale: float) -> void:
	var magic := await _spawn_affixed_thrall(grid, "magic", ["vital"])
	if magic != null:
		_check(is_equal_approx(float(magic.max_health), normal.x * 1.46 * 1.42),
			"Magic rarity and the selected Vital affix multiply max life")
	var rare := await _spawn_affixed_thrall(grid, "rare", ["vital", "ravaging", "quick"])
	if rare != null:
		_check(is_equal_approx(float(rare.max_health), normal.x * 2.27 * 1.42)
			and is_equal_approx(float(rare._base_damage), normal.y * 1.62 * 1.27)
			and is_equal_approx(float(rare._base_speed), normal.z * 1.17),
			"Rare rarity and the three chosen affixes affect life, damage, and movement")
	if magic != null and rare != null:
		var magic_bar: Color = magic._bar.get_instance_shader_parameter("bar_color")
		var rare_bar: Color = rare._bar.get_instance_shader_parameter("bar_color")
		_check(magic._model.scale.x > normal_scale and rare._model.scale.x > magic._model.scale.x
			and magic_bar.b > magic_bar.r and rare_bar.r > rare_bar.b
			and "Vital" in magic._title.text and "Ravaging" in rare._title.text and "Quick" in rare._title.text,
			"Affixed spawns show their rarity scale, bar color, and selected affix names")
	if rare != null:
		await _check_high_level_spawn(grid, rare)
	if _game.training_roster.is_open():
		await _tap(KEY_ESCAPE)


func _check_high_level_spawn(grid: GridContainer, level_one: CharacterBody3D) -> void:
	var arena_encounter: AIEncounter3D = _game._training_encounter
	var arena_rules := arena_encounter.get_attack_rules()
	var arena_peak: float = _game._training_pressure._director.peak_pressure
	var level_30 := await _spawn_affixed_thrall(grid, "rare", ["vital", "ravaging", "quick"], 30)
	if level_30 == null:
		return
	var summary: Dictionary = level_30.combat_tuning_summary()
	_check(summary.level == 30 and level_one.enemy_level == 1 and level_30.max_health > level_one.max_health
		and level_30._attack_damage() > level_one._attack_damage(),
		"The Level 30 selection scales the new enemy without changing the earlier Level 1 spawn")
	var other_encounter := Enemy.create_ai_encounter(20, _game.player, false)
	var deep_rules := other_encounter.get_attack_rules()
	_check(_game._training_encounter == arena_encounter and arena_encounter.get_attack_rules() == deep_rules
		and arena_encounter.get_attack_rules() != arena_rules and level_one._encounter == arena_encounter
		and is_equal_approx(_game._training_pressure._director.peak_pressure, 30.0),
		"The new high-level enemy raises the arena to deep encounter pressure without replacing the coordinator")
	var other_actor := Catalog.instantiate(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var affixes: Array[String] = ["vital", "ravaging", "quick"]
	other_actor.setup(null, 30, "rare", rng, Callable(), Callable(), affixes)
	other_actor.configure_ai(other_encounter)
	var other_summary: Dictionary = other_actor.combat_tuning_summary()
	_check(other_summary.level == summary.level
		and is_equal_approx(other_summary.life, summary.life)
		and is_equal_approx(other_summary.move_speed, summary.move_speed)
		and is_equal_approx(other_summary.attack_damage, summary.attack_damage)
		and is_equal_approx(other_actor._attack_damage(), level_30._attack_damage()),
		"A different encounter resolves identical Level 30 Life, movement, and damage with the same rarity and affixes")
	other_actor.free()
	other_encounter.free()
	arena_encounter.try_begin_attack(_game.player, &"hearth_melee", 0.1)
	var pressure := arena_encounter.get_attack_pressure(_game.player, &"hearth_melee")
	level_30.take_damage(100000.0, "physical", _game.player)
	_check(_game._training_encounter == arena_encounter and arena_encounter.get_attack_rules() == arena_rules
		and is_equal_approx(_game._training_pressure._director.peak_pressure, arena_peak)
		and is_equal_approx(arena_encounter.get_attack_pressure(_game.player, &"hearth_melee"), pressure)
		and arena_encounter.is_target_valid(_game.player) and level_one.is_in_group("enemies"),
		"Defeating the highest-level enemy restores the live low-level pressure without clearing the attack meter")


func _select_enemy_level(enemy_level: int) -> bool:
	var selector := _game.training_roster.find_child("EnemyLevel", true, false) as SpinBox
	if not _check(selector != null and selector.is_visible_in_tree() and selector.editable,
			"The F1 roster offers an editable Enemy Level selector"):
		return false
	selector.get_line_edit().text = str(enemy_level)
	return _check(_game.training_roster.selected_level() == enemy_level, "The roster accepts Enemy Level %d" % enemy_level)


func _spawn_affixed_thrall(grid: GridContainer, rarity: String, affixes: Array[String], enemy_level := 1) -> CharacterBody3D:
	if not await _open_roster() or not _select_enemy_level(enemy_level) or not await _press_roster_button("Rarity" + rarity.capitalize()):
		return null
	var roster: Control = _game.training_roster
	for previous: String in roster.selected_affixes():
		if previous not in affixes and not await _press_roster_button("Affix_" + previous):
			return null
	for affix in affixes:
		if affix not in roster.selected_affixes() and not await _press_roster_button("Affix_" + affix):
			return null
	var selected: Array[String] = roster.selected_affixes().duplicate()
	var expected := affixes.duplicate()
	selected.sort()
	expected.sort()
	_check(roster.selected_rarity() == rarity and selected == expected,
		"The F1 controls retain the selected %s rarity and affixes" % rarity.capitalize())
	var count_before := _training_enemies().size()
	if not await _activate_enemy_card(grid, 0):
		return null
	var enemies := _training_enemies()
	if not _check(enemies.size() == count_before + 1, "Selecting the card spawns another Thrall"):
		return null
	var thrall: CharacterBody3D = enemies.back()
	var actual: Array[String] = thrall.affixes.duplicate()
	actual.sort()
	_check(thrall.archetype_id == 0 and thrall.rarity == rarity and actual == expected,
		"The live %s Thrall carries the exact selected affixes" % rarity.capitalize())
	return thrall


func _press_roster_button(button_name: String) -> bool:
	var button := _game.training_roster.find_child(button_name, true, false) as Button
	if not _check(button != null and button.is_visible_in_tree() and not button.disabled,
			"The %s control is selectable" % button_name):
		return false
	button.grab_focus()
	await _tap(KEY_ENTER)
	return true


func _observe_native_movement(enemy: CharacterBody3D) -> bool:
	var runner := enemy.get_node_or_null("Brain") as AIBehaviorRunner
	if runner == null:
		return false
	var before := enemy.position
	for frame in range(110):
		await _ticks(1)
		if not is_instance_valid(enemy):
			return false
		if runner.get_active_node_ids().has(20) and enemy.position.distance_squared_to(before) > 0.25:
			return true
	return false


func _check_ability_traces(thrall: CharacterBody3D, toggle: CheckButton) -> void:
	thrall.global_position = Vector3(0.0, 0.08, 1.35)
	thrall.velocity = Vector3.ZERO
	_aim(Vector3(0.0, 0.08, 3.0), thrall.aim_point())
	var casts := _completed_cuts()
	_check(await _wait_for_cut(casts) and _visible_trace_count() == 0,
		"A real Graveknife Cut draws no trace while the option is off")
	if not await _open_roster():
		return
	toggle.grab_focus()
	await _tap(KEY_ENTER)
	_check(toggle.button_pressed, "The roster toggle enables enemy ability tracing")
	var trace_group: Node3D = _game._training_trace_visuals
	var trace_lifetimes := {}
	var measure_trace := func(visual: Node) -> void:
		var trace_id := visual.get_instance_id()
		var birth_frame := Engine.get_physics_frames()
		var record_exit := func() -> void:
			trace_lifetimes[trace_id] = Engine.get_physics_frames() - birth_frame
		visual.tree_exited.connect(record_exit, CONNECT_ONE_SHOT)
	trace_group.child_entered_tree.connect(measure_trace)
	await _tap(KEY_F1)

	var trace := await _wait_for_trace()
	trace_group.child_entered_tree.disconnect(measure_trace)
	if _check(is_instance_valid(trace), "An already-spawned Grave Thrall draws the next resolved cut"):
		var trace_id := trace.get_instance_id()
		for frame in range(140):
			if trace_lifetimes.has(trace_id):
				break
			await _ticks(1)
		var live_frames := int(trace_lifetimes.get(trace_id, -1))
		var duration_ticks := roundi(2.0 * Engine.physics_ticks_per_second)
		_check(not is_instance_valid(trace) and absi(live_frames - duration_ticks) <= 2,
			"Each trace expires after two seconds of active play (%d physics ticks)" % live_frames)

	trace = await _wait_for_trace()
	if not await _open_roster():
		return
	if _check(is_instance_valid(trace), "Another resolved cut draws another trace"):
		await _ticks(roundi(2.0 * Engine.physics_ticks_per_second) + 5)
		_check(is_instance_valid(trace), "Trace lifetime pauses while the F1 roster is open")
	toggle.grab_focus()
	await _tap(KEY_ENTER)
	_check(not toggle.button_pressed and _visible_trace_count() == 0,
		"Turning tracing off clears the current overlays")
	await _tap(KEY_F1)
	casts = _completed_cuts()
	_check(await _wait_for_cut(casts) and _visible_trace_count() == 0,
		"Further attacks by that Thrall leave tracing off")


func _completed_cuts() -> int:
	var count := 0
	for event: Dictionary in _game._combat_events:
		if event.kind == &"cast_end" and event.actor == "Grave Thrall" and event.ability_id == &"graveknife_cut":
			count += 1
	return count


func _wait_for_cut(previous: int) -> bool:
	for frame in range(240):
		if _completed_cuts() > previous:
			return true
		await _ticks(1)
	return false


func _wait_for_trace() -> Node:
	for frame in range(240):
		if _visible_trace_count() > 0:
			return _game._training_trace_visuals.get_child(-1)
		await _ticks(1)
	return null


func _visible_trace_count() -> int:
	var overlay: Node3D = _game._training_trace_visuals
	return overlay.get_child_count() if is_instance_valid(overlay) else 0


func _exercise_swimming_pool(arena: Node3D) -> void:
	var player: CharacterBody3D = _game.player
	var water: Node3D = arena.water_volume
	_check(player._water_volume == water, "Entering training registers the authored swimming pool")
	var surface := water.global_position
	var route: PackedVector3Array = arena.navigation_route(player.global_position, surface)
	_check(route.is_empty(), "The dry training navigation mesh excludes the pool")
	var saved_position := player.global_position
	var saved_heading := player.rotation.y
	var saved_pitch: float = player.view_pitch()
	var approach := Vector3(surface.x - 3.8, 0.04, surface.z + 0.2)
	player.place_at(approach, -PI * 0.5)
	await _ticks(5)
	var waded := false
	Input.action_press("forward")
	for _frame in range(150):
		await _ticks(1)
		var feet := player.global_position
		var torso_wet: bool = water.contains(feet + Vector3.UP * 0.76)
		waded = waded or (water.contains(feet + Vector3.UP * 0.12) and not torso_wet)
		if player._water_tint.visible:
			break
	Input.action_release("forward")
	_check(waded and player._water_tint.visible and player.global_position.y < surface.y - 1.56,
		"Walking down from the dry court progresses through wading, swimming, and underwater view")
	var depth := player.global_position.y
	Input.action_press("jump")
	await _ticks(16)
	Input.action_release("jump")
	_check(player.global_position.y > depth + 0.25, "Space swims upward from below the surface")
	player.place_at(player.global_position, PI * 0.5)
	Input.action_press("forward")
	await _ticks(130)
	Input.action_release("forward")
	_check(player.is_on_floor() and absf(player.global_position.y) < 0.05 and not player._water_tint.visible,
		"Swimming back up the ramp returns to the dry court and clears the underwater effect")
	player.place_at(saved_position, saved_heading, saved_pitch)
	await _ticks(2)


func _check_pillar_cover(arena: Node3D) -> void:
	var space := arena.get_world_3d().direct_space_state
	var clear := PhysicsRayQueryParameters3D.create(Vector3(0.0, 1.0, -5.5), Vector3(0.0, 1.0, 5.5), 1)
	_check(Arena.PILLAR_CENTERS.size() == 2 and space.intersect_ray(clear).is_empty(),
		"The two-pillar layout leaves an open center lane")
	for center: float in Arena.PILLAR_CENTERS:
		var start := Vector3(center, 0.0, -5.5)
		var finish := Vector3(center, 0.0, 5.5)
		var sight := PhysicsRayQueryParameters3D.create(start + Vector3.UP, finish + Vector3.UP, 1)
		var route: PackedVector3Array = arena.navigation_route(start, finish)
		var circles_pillar := route.size() >= 3 and route[-1].distance_to(finish) < 0.25
		var pillar := Vector2(center, 0.0)
		for index in range(1, route.size()):
			var previous := Vector2(route[index - 1].x, route[index - 1].z)
			var point := Vector2(route[index].x, route[index].z)
			var closest := Geometry2D.get_closest_point_to_segment(pillar, previous, point)
			if closest.distance_to(pillar) < Arena.PILLAR_RADIUS:
				circles_pillar = false
		_check(not space.intersect_ray(sight).is_empty() and circles_pillar,
			"The %s pillar blocks sight while leaving a complete native route around it" % ("left" if center < 0.0 else "right"))


func _training_enemies() -> Array[CharacterBody3D]:
	var actors: Array[CharacterBody3D] = []
	if not is_instance_valid(_game._training_actors):
		return actors
	for actor: Node in _game._training_actors.get_children():
		if actor is CharacterBody3D and actor.is_in_group("enemies"):
			actors.append(actor)
	return actors


func _on_arrival(arena: Node3D) -> bool:
	return _game.player.position.distance_squared_to(arena.spawn_position) < 0.35


func _wait_for_navigation(arena: Node3D) -> bool:
	for frame in range(180):
		if arena.navigation_map().is_valid():
			return true
		await _ticks(1)
	return false


func _aim(point: Vector3, target: Vector3) -> void:
	var direction := (target - point - Vector3.UP * 1.56).normalized()
	_game.player.place_at(point, atan2(-direction.x, -direction.z), asin(direction.y))


func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(3)
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	Input.parse_input_event(event)
	await _ticks(3)


func _click_menu(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await _ticks(3)


func _ticks(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + description)
	else:
		_failures += 1
		push_error("FAIL  " + description)
	return condition
