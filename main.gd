extends Node3D

const Dungeon = preload("res://world/dungeon.gd")
const DungeonScene = preload("res://world/dungeon.tscn")
const TrainingGround = preload("res://world/training_ground.tscn")
const TrainingAbilityTrace = preload("res://combat/effects/training_ability_trace.gd")
const TrainingWeaponTrace = preload("res://combat/effects/training_weapon_trace.gd")
const HAZARD_SCENES := {
	"spike_plate": preload("res://world/hazards/spike_plate.tscn"),
	"ember_vent": preload("res://world/hazards/ember_vent.tscn"),
	"miasma_vent": preload("res://world/hazards/miasma_vent.tscn"),
}
const Enemy = preload("res://combat/enemies/enemy.gd")
const EnemyCatalog = preload("res://combat/enemies/enemy_catalog.gd")
const ExpeditionPressure = preload("res://ai/expedition_pressure.gd")
const Prop = preload("res://world/world_prop.gd")
const SecretPassage = preload("res://world/props/secret_passage.tscn")
const Items = preload("res://systems/items.gd")
const Inventory = preload("res://systems/inventory.gd")
const Progression = preload("res://systems/character_progression.gd")
const WindowPreferences = preload("res://systems/window_preferences.gd")
const DESTROY_ITEM_DIALOG := preload("res://ui/destroy_item_dialog.tscn")
const BestiaryData = preload("res://data/bestiary.gd")
const SaveStore = preload("res://systems/save_store.gd")
const CharacterSlots = preload("res://systems/character_slots.gd")
const ExpeditionRules = preload("res://data/expedition_rules.tres")
const LootPlacement = preload("res://world/loot_placement.gd")
const CardCatalog = preload("res://data/card_catalog.gd")
const CardItems = preload("res://systems/card_items.gd")
const CardDeck = preload("res://systems/card_deck.gd")
const CardCast = preload("res://combat/cards/card_cast.gd")
const DungeonMapFog := preload("res://ui/dungeon_map_fog.gd")
const CARD_WORLD_SPEED := 0.075
const DepthDifficulty := preload("res://data/depth_difficulty.tres")
const RouteGate := preload("res://world/props/route_gate.tscn")
const Supplies := preload("res://systems/pack_supplies.gd")
const CharacterStatistics := preload("res://systems/character_statistics.gd")
const AudioService := preload("res://systems/game_audio.gd")
const GameServices := preload("res://systems/game_services.gd")
const CasterLegendaryEffects := preload("res://combat/effects/caster_legendary_effects.gd")
const ExpeditionFeatures := preload("res://world/expedition_features.gd")
const DungeonEnemyConvergence := preload("res://world/dungeon_enemy_convergence.gd")
const DungeonWallClues := preload("res://world/dungeon_wall_clues.gd")
const DungeonTilesets := preload("res://world/dungeon_tilesets.gd")
const BloodAltarRules := preload("res://data/blood_altar_rules.tres")
const BloodAltar := preload("res://world/props/blood_altar.tscn")
const BrokerScene := preload("res://world/props/secret_merchant.tscn")
const LavaFloor := preload("res://world/props/lava_floor.tscn")
const BasinWater := preload("res://world/modules/basin_water.tscn")
const GroundCast := preload("res://combat/effects/ground_cast.gd")

enum SessionMode { TITLE, CHARACTER, PRACTICE }

const GOLD_PICKUP_RADIUS := 2.0
const ENEMY_GOLD_PER_LEVEL := 0.15
const COFFER_GOLD_PER_DEPTH := 0.55
const BREAKABLE_GOLD_PER_DEPTH := 0.21
const BREAKABLE_REWARD_CHANCE := 0.23
const BREAKABLE_REWARD_PER_DEPTH := 0.008
const BREAKABLE_MATERIAL_SHARE := 0.24
const ENEMY_GOLD_BY_RARITY := {"normal": 0.0, "magic": 1.0, "rare": 3.0}
const ENEMY_GEAR_LEVEL_BONUS := {"normal": 0, "magic": 1, "rare": 2}
const RARITY_PROFILE_VERSION := 2
const FLOOR_ELITE_SHARE_LIMIT := 0.45
const COMBAT_LOG_LIMIT := 1000
const TRAINING_SPAWN_CLEARANCE := 2.0
const LEGATE_ID := 25
const LEGATE_COMBAT_DELAY := 5.0
const LEGATE_CHANCE_PER_POLL := 0.22
const FLOOR_SEED_STRIDE := 2654435761
const FLOOR_STATE_DEFAULTS := {
	"defeated": {}, "opened": {}, "loot": {}, "mob_states": {}, "explored": [], "map_fog": [], "map_landmarks": [],
	"portal": [], "portal_yaw": 0.0, "secrets_opened": {}, "broken_props": {}, "ambush_triggered": {},
	"mason_clues": {},
	"opened_route_gates": {}, "collected_route_keys": {},
	"extra_enemies": {}, "revived": {},
	"broker_catalog": {},
}
const RECAP_DEFAULTS := {"dealt": 0, "taken": 0, "kills": 0, "elite_kills": 0, "gold": 0, "time": 0.0}
const DEPTH_NAMES := {
	&"iron_crypt": "Iron Crypt",
	&"drowned_vault": "Drowned Vault",
	&"ashen_catacomb": "Ashen Catacomb",
	&"blighted_ossuary": "Blighted Ossuary",
}

const WALK_KEYS := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
	"sprint": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_E, "portal": KEY_T,
	"inventory": KEY_I, "map": KEY_TAB, "pause": KEY_ESCAPE, "training_roster": KEY_F1, "cards": KEY_Q}

class DungeonFloor:
	var geometry: Node3D
	var actors: Node3D
	var props: Node3D
	var enemies: Dictionary = {}
	var room_enemies: Dictionary = {}
	var hazards: Array[Node3D] = []
	var loot: Dictionary = {}
	var chests: Dictionary = {}
	var concealed: Dictionary[Vector2i, bool] = {}
	var portal: Node3D
	var pack_encounters: Dictionary[int, AIEncounter3D] = {}
	var dormant_rooms: Dictionary[int, Array] = {}
	var blood_altar: Node3D
	var broker: Node3D
	var water: Node3D
	var corpses: Dictionary = {}
	var enemy_origins: Dictionary = {}


@export_group("Player Abilities")
## Ability used by a quick left-mouse tap. Leave empty for the equipped weapon's light attack.
@export var primary_ability: AbilityDefinition
## Ability released automatically when the left-mouse hold finishes charging.
## Leave empty for the equipped weapon's charged attack.
@export var charged_ability: AbilityDefinition

var player: CharacterBody3D
var hub: Node3D
var dungeon: Node3D
var training_ground: Node3D
var inventory: Inventory
var lifetime := CharacterStatistics.new()
var _last_damage_actor := ""
var hud: Control
var inventory_ui: Control
var bestiary: Control
var combat_log: Control
var training_roster: Control
var title_screen: Control
var card_screen: Control
var card_deck := CardDeck.new()
var progression := Progression.new()
var bestiary_discoveries: Dictionary[int, bool] = {}
var audio: AudioService
var in_dungeon := false
var unlocked := 1
var completions := 0
var run: Dictionary = {}
var save_enabled := true
var save_directory := SaveStore.SAVE_DIRECTORY
var preferences_path := WindowPreferences.PREFERENCES_PATH

var _actors: Node3D
var _expedition_pressure: Node
var _props: Node3D
var _enemies: Dictionary = {}
var _remaining_by_room: Dictionary = {}
var _hazards: Array[Node3D] = []
var _loot: Dictionary = {}
var _chests: Dictionary = {}
var _explored: Dictionary = {}
var _map_fog := DungeonMapFog.new()
var _concealed_tiles: Dictionary[Vector2i, bool] = {}
var _portal_prop: Node3D
var _rng := RandomNumberGenerator.new()
var _world: Node3D
var _dungeon_root: Node3D
var _dungeon_floors: Dictionary[int, DungeonFloor] = {}
var _altar_armed := false
var _modal := false
var _confirm_close := false
var _changing := false
var _interact_pending := false
var _portal_pending := false
var _updating := true
var _death_pending := false
var _hud_clock := 0.0
var _last_target: Node3D
var _broker_floor := -1
var _legate_wait := LEGATE_COMBAT_DELAY
var _convergence_wait := 0.0
var _convergence_floor := -1
var _last_hub_target := ""
var _cached_equipment: Dictionary = {}
var _session_mode := SessionMode.TITLE
var _character_slot := -1
var _character_name := ""
var _fullscreen := false
var _windowed_mode := Window.MODE_WINDOWED
var _training_actors: Node3D
var _training_props: Node3D
var _training_trace_visuals: Node3D
var _training_weapon_trace: TrainingWeaponTrace
var _training_portal: Node3D
var _training_encounter: AIEncounter3D
var _training_encounter_rating := 1
var _training_pressure: Node
var _training_rng := RandomNumberGenerator.new()
var _training_campaign_vitals := Vector3.ZERO
var _training_campaign_stamina := 0.0
var _training_inventory: Inventory
var _training_progression: Progression
var _pending_training_weapon: Dictionary = {}
var _training_weapon_serial := 0
var _training_spawn_cursor := 0
var _combat_clock := 0.0
var _combat_events: Array[Dictionary] = []
var _card_hand_open := false
var _card_editor_open := false
var _card_original_speed := 1.0
var _queued_card := ""
var _training_card_deck: CardDeck
var _training_used_cards: Dictionary = {}
var _training_campaign_card_buffs: Dictionary = {}
var _carried_drop: Dictionary = {}


func _enter_tree() -> void:
	var services := GameServices.from_context(self)
	audio = get_node_or_null("GameAudio") as AudioService
	if services != null and audio != null:
		services.register_audio(audio)


func _ready() -> void:
	_install_inputs()
	_rng.randomize()
	_training_rng.randomize()
	get_tree().set_auto_accept_quit(false)
	_world = $ActiveWorld
	hub = $ActiveWorld/Hub
	player = $Player
	player.light_ability_override = primary_ability
	player.heavy_ability_override = charged_ability
	player.feedback.connect(_feedback)
	player.died.connect(_schedule_death)
	player.struck.connect(_struck)
	player.combat_event.connect(_record_combat_event)
	hud = $Interface/HUD
	hud.bind_effect_source(player)
	inventory_ui = $Interface/Inventory
	card_screen = $Interface/Cards
	card_screen.card_played.connect(_choose_card)
	card_screen.slot_changed.connect(_equip_card)
	card_screen.close_requested.connect(_close_card_screen)
	bestiary = $Interface/Bestiary
	bestiary.back_requested.connect(_close_bestiary)
	combat_log = $Interface/CombatLog
	combat_log.back_requested.connect(_close_combat_log)
	training_roster = $Interface/TrainingRoster
	training_roster.spawn_requested.connect(_spawn_training_enemy)
	training_roster.weapon_requested.connect(_request_training_weapon)
	training_roster.player_level_changed.connect(_set_training_player_level)
	training_roster.set_weapon_choices(Items.training_weapon_choices())
	training_roster.close_requested.connect(_close_training_roster)
	training_roster.ability_traces_changed.connect(_set_training_ability_traces)
	training_roster.player_weapon_traces_changed.connect(_set_training_weapon_traces)
	title_screen = $Interface/Title
	title_screen.character_selected.connect(_select_character)
	title_screen.character_created.connect(_create_character)
	title_screen.training_requested.connect(_start_training_from_title)
	title_screen.settings_requested.connect(_open_settings)
	title_screen.quit_requested.connect(_quit_without_save)
	inventory = Inventory.new()
	inventory.changed.connect(_on_inventory_changed)
	inventory.economy_event.connect(_record_economy)
	lifetime.achievement_unlocked.connect(hud.present_achievement)
	inventory.transaction_committed.connect(_on_inventory_transaction)
	inventory_ui.bind(inventory)
	inventory_ui.bind_card_deck(card_deck)
	inventory_ui.bind_progression(progression)
	inventory_ui.attributes_changed.connect(_on_attributes_changed)
	inventory_ui.closed.connect(_close_inventory_menu)
	inventory_ui.item_drop_requested.connect(_request_inventory_disposal)
	hud.level_selected.connect(_select_depth)
	hud.blood_oath_selected.connect(_accept_blood_oath)
	hud.recap_requested.connect(_open_expedition_recap)
	hud.statistics_requested.connect(_open_lifetime_statistics)
	hud.achievements_requested.connect(_open_achievements)
	hud.leave_requested.connect(_close_dungeon)
	hud.resume_requested.connect(_resume)
	hud.quit_requested.connect(_save_and_quit)
	hud.settings_requested.connect(_open_settings)
	hud.settings_back_requested.connect(_close_settings)
	hud.bestiary_requested.connect(_open_bestiary)
	hud.combat_log_requested.connect(_open_combat_log)
	hud.cards_requested.connect(_open_cards_from_pause)
	hud.fullscreen_changed.connect(_set_fullscreen)
	var fullscreen_default := get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	if save_enabled:
		var legacy_fullscreen: Variant = SaveStore.load_game(save_directory).get("fullscreen", fullscreen_default)
		if legacy_fullscreen is bool:
			fullscreen_default = legacy_fullscreen
		fullscreen_default = WindowPreferences.load_fullscreen(preferences_path, fullscreen_default)
	_apply_fullscreen(fullscreen_default)
	player.place_at(Vector3(-2.5, hub.spawn_position.y, 10.0), 0.108, -0.01)
	hud.set_world_visible(false)
	_suspend()
	_show_title()


func _show_title() -> void:
	hud.hide_menu()
	var characters: Array[Dictionary] = []
	if save_enabled:
		characters = CharacterSlots.list_slots(save_directory)
	title_screen.present(characters)


func _select_character(slot: int) -> void:
	if _session_mode != SessionMode.TITLE or not save_enabled:
		return
	var saved := CharacterSlots.load_slot(save_directory, slot)
	if saved.is_empty():
		return
	_character_slot = slot
	_character_name = String(saved.get("character_name", "Wanderer"))
	_begin_campaign(SessionMode.CHARACTER, saved)


func _create_character(slot: int, character_name: String) -> void:
	if (_session_mode != SessionMode.TITLE or slot < 0 or slot >= CharacterSlots.SLOT_COUNT
			or not CharacterSlots.valid_name(character_name)):
		return
	if save_enabled and not CharacterSlots.load_slot(save_directory, slot).is_empty():
		return
	_character_slot = slot
	_character_name = character_name.strip_edges()
	_begin_campaign(SessionMode.CHARACTER, {})


func _start_training_from_title() -> void:
	if _session_mode == SessionMode.TITLE:
		_begin_campaign(SessionMode.PRACTICE, {}, true)


func _begin_campaign(mode: SessionMode, saved: Dictionary, start_in_training := false) -> void:
	_session_mode = mode
	lifetime.restore(saved.get("lifetime", {}))
	title_screen.close()
	hud.hide_menu()
	hud.set_world_visible(true)
	if saved.is_empty():
		inventory.grant_gold(30)
		inventory.equip_starter(Items.starter_weapon())
		_restock()
	else:
		_restore(saved)
	player.set_character_progression(progression)
	_refresh_enemy_levels()
	inventory_ui.refresh_progression()
	player.update_equipment(inventory.equipment)
	_cached_equipment = inventory.equipment.duplicate(true)
	player.restore_full()
	if saved.has("life"):
		player.life = clampf(float(saved.life), 1.0, player.stats.max_health)
		player.mana = clampf(float(saved.get("mana", player.stats.max_mana)), 0.0, player.stats.max_mana)
		player.ward = clampf(float(saved.get("ward", player.stats.ward)), 0.0, player.stats.ward)
		player.restore_stamina(float(saved.get("stamina", player.max_stamina())))
	if not run.is_empty():
		player.card_effects.restore(run.get("card_buffs", {}))
	if start_in_training:
		_enter_training_ground()
	elif not in_dungeon:
		player.place_at(hub.spawn_position)
		audio.set_zone("hub")
	hub.set_dungeon_state(not run.is_empty(), bool(run.get("cleared", false)))
	_updating = false
	_resume()
	_update_hud()


func _install_inputs() -> void:
	for action in WALK_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var event := InputEventKey.new()
			event.physical_keycode = WALK_KEYS[action]
			InputMap.action_add_event(action, event)


func _input(event: InputEvent) -> void:
	if not _card_hand_open and not _card_editor_open:
		return
	if (event.is_action_pressed("cards") or _logical_menu_key_pressed(event, KEY_Q)
			or event.is_action_pressed("pause") or _logical_menu_key_pressed(event, KEY_ESCAPE)):
		_close_card_screen()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _card_hand_open or _card_editor_open:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cards") or _logical_menu_key_pressed(event, KEY_Q):
		if not _modal and not _changing and not _death_pending:
			_open_card_screen()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		player.look(event)
		return
	if event.is_action_pressed("pause") or _logical_menu_key_pressed(event, KEY_ESCAPE):
		if combat_log.is_open():
			_close_combat_log()
		elif training_roster.is_open():
			_close_training_roster()
		elif bestiary.is_open():
			bestiary.back()
		elif inventory_ui.is_open():
			inventory_ui.close()
		elif hud.is_menu_open():
			hud.back_from_menu()
		elif _session_mode != SessionMode.TITLE:
			_suspend()
			hud.open_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("training_roster") and is_instance_valid(training_ground):
		if training_roster.is_open():
			_close_training_roster()
		elif not _modal and not _changing and not _death_pending:
			_suspend()
			training_roster.present()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory"):
		if inventory_ui.is_open():
			inventory_ui.close()
		elif not _modal:
			_open_inventory("inventory")
		get_viewport().set_input_as_handled()
		return
	if _modal or _changing:
		return
	if event.is_action_pressed("interact") or (
		not in_dungeon and _last_hub_target == "close_dungeon" and event.is_action_pressed("attack")):
		_interact_pending = true
	if event.is_action_pressed("portal") and in_dungeon:
		_portal_pending = true
	if event.is_action_pressed("map") and in_dungeon:
		hud.toggle_map()
		_update_map()
		get_viewport().set_input_as_handled()


func _logical_menu_key_pressed(event: InputEvent, key: Key) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != key:
		return false
	# Some Windows input providers give logical shortcuts an absent or Pause scancode.
	return event.physical_keycode == 0 or event.physical_keycode == KEY_PAUSE


func _physics_process(delta: float) -> void:
	if not is_instance_valid(hud):
		return
	_check_dungeon_deadline()
	if not _carried_drop.is_empty():
		_drop_carried_item()
	if _modal or _changing or _death_pending:
		return
	if in_dungeon:
		_track_dungeon_floor()
		_trigger_entered_ambush()
		_tick_legate_incursion(delta)
		_tick_enemy_convergence(delta)
		run.recap.time = float(run.recap.time) + delta
	if not _pending_training_weapon.is_empty():
		_drop_training_weapon()
	hud.set_stamina(player.stamina, player.max_stamina(), player.guard_is_held(),
		player.is_blocking(), player.attack_charge_fraction())
	if in_dungeon or is_instance_valid(training_ground):
		_combat_clock += delta
		player.card_effects.advance(delta)
		if not _queued_card.is_empty():
			var card_id := _queued_card
			_queued_card = ""
			if not player.is_stunned():
				var used: Dictionary = run.used_cards if in_dungeon else _training_used_cards
				used[card_id] = true
				if in_dungeon:
					lifetime.add("cards_cast")
				var card: Dictionary = CardCatalog.CARDS[card_id]
				CardCast.play(card_id, card, player, _active_combat_actors())
				var sound := card.get("play_sound") as HearthSoundCue
				if sound == null:
					audio.cue(CardCatalog.default_use_sound(card))
				else:
					audio.play_sound(sound)
				hud.notify(card.name)
	if _card_hand_open:
		player._tick_ailments(delta)
		return
	if _portal_pending:
		_portal_pending = false
		if not player.is_stunned():
			_create_portal()
	_hud_clock -= delta
	if _hud_clock <= 0.0 or _interact_pending:
		_hud_clock = 0.085
		if in_dungeon:
			_collect_nearby_gold()
		_update_hud()
		_update_interactions()
		if in_dungeon:
			_update_map()
	if _interact_pending:
		_interact_pending = false
		if not player.is_stunned():
			_interact()


func _update_interactions() -> void:
	var aim: Transform3D = player.get_aim_transform()
	var origin := aim.origin
	var direction := -aim.basis.z
	_last_hub_target = ""
	if is_instance_valid(training_ground):
		_set_world_target(_pick_prop(origin, direction, _training_props.get_children()))
		if is_instance_valid(_last_target):
			hud.set_prompt("E   " + _last_target.text, _last_target.tint)
		else:
			hud.set_prompt("")
		return
	if in_dungeon:
		_set_world_target(_pick_prop(origin, direction, _props.get_children()))
		var special_target: bool = (is_instance_valid(_last_target)
			and _last_target.payload.kind in ["route_gate", "blood_altar", "secret_merchant"])
		hud.set_prompt("E   " + _last_target.text if special_target else "")
		return
	_set_world_target(null)
	var overlaps: bool = hub.altar_overlaps(player.global_position)
	if not overlaps:
		_altar_armed = true
	elif _altar_armed and run.is_empty():
		_altar_armed = false
		_suspend()
		hud.open_depths(unlocked)
		return
	_last_hub_target = hub.active_interaction(origin, direction, 4.0)
	if _last_hub_target == "close_dungeon" and run.is_empty():
		_last_hub_target = ""
	var label: String = {"vendor": "Trade with the Merchant", "blacksmith": "Speak to the Blacksmith",
		"altar": "Choose a Dungeon Depth",
		"close_dungeon": "Seal the Vault", "training_portal": "Enter Training Ground",
		"stash": "Open Stash"}.get(_last_hub_target, "")
	if _last_hub_target == "altar" and not run.is_empty():
		label = "Return to the Undervault"
	var binding := "E / Click   " if _last_hub_target == "close_dungeon" else "E   "
	hud.set_prompt(binding + label if not label.is_empty() else "")


func _set_world_target(target: Node3D) -> void:
	if _last_target == target:
		return
	if is_instance_valid(_last_target) and _last_target.has_method("set_targeted"):
		_last_target.set_targeted(false)
	_last_target = target
	if is_instance_valid(target) and target.has_method("set_targeted"):
		target.set_targeted(true)


func _pick_prop(origin: Vector3, direction: Vector3, props: Array[Node]) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for candidate in props:
		if candidate.is_queued_for_deletion() or not candidate.pick_available():
			continue
		var anchors: PackedVector3Array = (candidate.loot_aim_points() if candidate.has_method("loot_aim_points")
			else PackedVector3Array([candidate.interaction_point]))
		for anchor in anchors:
			var point: Vector3 = candidate.global_position + anchor
			var offset := point - origin
			var depth := direction.dot(offset)
			if depth < 0.25 or depth > 4.8:
				continue
			var distance := (offset - direction * depth).length()
			if distance > candidate.margin:
				continue
			var score := distance + depth * 0.045
			if score >= best_score:
				continue
			var ray := PhysicsRayQueryParameters3D.create(origin, point, 1)
			if candidate is StaticBody3D:
				ray.exclude = [candidate.get_rid()]
			if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			best = candidate
			best_score = score
	return best


func _interact() -> void:
	if _modal:
		return
	if is_instance_valid(training_ground):
		if _last_target == _training_portal:
			_leave_training_ground()
		elif is_instance_valid(_last_target):
			_pickup(_last_target)
		return
	if in_dungeon:
		if not is_instance_valid(_last_target):
			return
		match _last_target.payload.kind:
			"portal":
				_enter_hub()
			"loot":
				_pickup(_last_target)
			"chest":
				_open_chest(_last_target)
			"secret_passage":
				_open_secret_passage(_last_target)
			"route_gate":
				_unlock_route_gate(_last_target)
			"blood_altar":
				_suspend()
				hud.open_blood_altar(BloodAltarRules.choices())
			"secret_merchant":
				_open_secret_broker()
		return
	match _last_hub_target:
		"vendor":
			_open_inventory("vendor")
		"blacksmith":
			_open_inventory("smith")
		"stash":
			_open_inventory("stash")
		"altar":
			if run.is_empty():
				_altar_armed = false
				_suspend()
				hud.open_depths(unlocked)
			else:
				_enter_dungeon(true)
		"close_dungeon":
			_suspend()
			_confirm_close = true
			hud.open_close(bool(run.cleared))
		"training_portal":
			_enter_training_ground()


func _suspend() -> void:
	_close_card_hand(false)
	_modal = true
	_interact_pending = false
	_portal_pending = false
	player.gameplay_enabled = false
	player.velocity = Vector3.ZERO
	_set_world_target(null)
	hud.set_gameplay(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_encounters_enabled(false)


func _resume() -> void:
	_modal = false
	_confirm_close = false
	player.gameplay_enabled = true
	hud.set_gameplay(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_encounters_enabled(true)


func _active_combat_actors() -> Node3D:
	return _training_actors if is_instance_valid(training_ground) else _dungeon_root


func _set_encounters_enabled(enabled: bool) -> void:
	var mode := Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_training_actors):
		_training_actors.process_mode = mode
	for dungeon_floor: DungeonFloor in _dungeon_floors.values():
		dungeon_floor.actors.process_mode = mode


func _enter_training_ground() -> void:
	if _changing or in_dungeon or is_instance_valid(training_ground):
		return
	_changing = true
	_training_inventory = Inventory.new()
	if not _training_inventory.restore_data({"equipment": inventory.save_data().equipment}):
		_training_inventory = null
		_changing = false
		_feedback("Could not prepare the practice inventory", "error")
		return
	_training_inventory.changed.connect(_on_inventory_changed)
	_training_campaign_vitals = Vector3(player.life, player.mana, player.ward)
	_training_campaign_stamina = player.stamina
	_training_progression = Progression.new()
	_training_progression.restore(progression.snapshot())
	player.set_character_progression(_training_progression)
	training_roster.set_player_level(_training_progression.level)
	inventory_ui.bind(_training_inventory)
	inventory_ui.bind_progression(_training_progression, true)
	var equipment := _training_inventory.equipment
	player.update_equipment(equipment)
	_cached_equipment = equipment.duplicate(true)
	_training_weapon_serial = 0
	_world.remove_child(hub)
	training_ground = TrainingGround.instantiate()
	training_ground.name = "TrainingGround"
	_world.add_child(training_ground)
	player.set_water_volume(training_ground.water_volume)
	_training_props = Node3D.new()
	_training_props.name = "TrainingProps"
	training_ground.add_child(_training_props)
	_training_portal = Prop.new()
	_training_portal.name = "ReturnPortal"
	_training_portal.position = training_ground.return_portal_position
	_training_portal.rotation.y = PI
	_training_portal.setup({"kind": "portal", "show_world_label": true})
	_training_props.add_child(_training_portal)
	_begin_training_cards()
	_reset_training_combat()
	player.combat_enabled = true
	player.place_at(training_ground.spawn_position, training_ground.spawn_yaw)
	player.restore_full()
	_altar_armed = false
	audio.set_zone("dungeon")
	audio.cue("portal")
	hud.set_prompt("")
	_update_hud()
	_changing = false


func _leave_training_ground() -> void:
	if _session_mode == SessionMode.PRACTICE:
		_changing = true
		get_tree().reload_current_scene()
		return
	_changing = true
	_end_training_cards()
	player.set_water_volume(null)
	_world.remove_child(training_ground)
	training_ground.queue_free()
	training_ground = null
	_training_actors = null
	_training_props = null
	_training_trace_visuals = null
	_training_weapon_trace = null
	player.set("weapon_trace", Callable())
	_training_portal = null
	_training_encounter = null
	_training_pressure = null
	_last_target = null
	_world.add_child(hub)
	player.combat_enabled = false
	_pending_training_weapon.clear()
	inventory_ui.bind(inventory)
	inventory_ui.bind_progression(progression)
	_training_inventory = null
	_training_progression = null
	player.set_character_progression(progression)
	var equipment: Dictionary = inventory.equipment
	player.update_equipment(equipment)
	_cached_equipment = equipment.duplicate(true)
	var arrival: Vector3 = hub.training_arrival_position()
	player.place_at(arrival, atan2(arrival.x, arrival.z))
	player.restore_full()
	player.life = clampf(_training_campaign_vitals.x, 1.0, player.stats.max_health)
	player.mana = clampf(_training_campaign_vitals.y, 0.0, player.stats.max_mana)
	player.ward = clampf(_training_campaign_vitals.z, 0.0, player.stats.ward)
	player.restore_stamina(_training_campaign_stamina)
	audio.set_zone("hub")
	audio.cue("portal")
	hud.set_prompt("")
	_update_hud()
	_changing = false


func _reset_training_combat() -> void:
	_reset_training_cards()
	if is_instance_valid(_training_actors):
		training_ground.remove_child(_training_actors)
		_training_actors.queue_free()
	_training_actors = Node3D.new()
	_training_actors.name = "TrainingActors"
	training_ground.add_child(_training_actors)
	_training_trace_visuals = Node3D.new()
	_training_trace_visuals.name = "AbilityTraces"
	_training_actors.add_child(_training_trace_visuals)
	_training_weapon_trace = TrainingWeaponTrace.new()
	_training_weapon_trace.name = "PlayerWeaponTraces"
	_training_actors.add_child(_training_weapon_trace)
	_set_training_weapon_traces(training_roster.player_weapon_traces_enabled())
	_training_spawn_cursor = 0
	_training_encounter_rating = 1
	_training_encounter = Enemy.create_ai_encounter(_training_encounter_rating, player)
	_training_encounter.name = "TrainingEncounter"
	_training_actors.add_child(_training_encounter)
	_training_pressure = ExpeditionPressure.new()
	_training_pressure.name = "TrainingPressure"
	_training_pressure.configure(player, _training_encounter_rating)
	_training_actors.add_child(_training_pressure)


func _close_training_roster() -> void:
	if training_roster.is_open():
		training_roster.close()
		_resume()


func _set_training_player_level(level: int) -> void:
	if _training_progression == null or _training_progression.level == level:
		return
	_training_progression = Progression.for_training(level)
	player.set_character_progression(_training_progression)
	inventory_ui.bind_progression(_training_progression, true)
	player.restore_full()
	_refresh_enemy_levels()
	_update_hud()


func _request_training_weapon(choice_id: String) -> void:
	if not training_roster.is_open() or not is_instance_valid(_training_props):
		return
	var item := Items.training_weapon_item(choice_id, "training_weapon_%d" % _training_weapon_serial,
		training_roster.selected_weapon_item_level(), _training_rng, float(player.stats.loot_rarity))
	if item.is_empty():
		return
	_pending_training_weapon = item
	_close_training_roster()


func _drop_training_weapon() -> void:
	var item := _pending_training_weapon
	_pending_training_weapon = {}
	var point: Vector3 = training_ground.weapon_drop_point(player.global_position,
		-player.global_basis.z, _training_props.get_children())
	if not point.is_finite():
		_feedback("No clear spot for a practice weapon", "error")
		return
	_training_weapon_serial += 1
	var prop := _make_prop({"kind": "loot", "category": "item", "item": item, "label_height": 0.48},
		_training_props.to_local(point), _training_props)
	prop.animate_drop()
	if item.get("unidentified", false):
		var seal_point: Vector3 = training_ground.weapon_drop_point(player.global_position,
			-player.global_basis.z, _training_props.get_children())
		var seal := Supplies.unveiling_scroll()
		seal.id = "practice_seal_%d" % _training_weapon_serial
		if seal_point.is_finite():
			var supply := _make_prop({"kind": "loot", "category": "item", "item": seal, "label_height": 0.38},
				_training_props.to_local(seal_point), _training_props)
			supply.animate_drop()
		else:
			_training_inventory.add_item(seal)


func _set_training_ability_traces(enabled: bool) -> void:
	if not is_instance_valid(_training_actors):
		return
	var trace := Callable(self, "_draw_training_ability_trace") if enabled else Callable()
	for actor: Node in _training_actors.get_children():
		if actor is Enemy:
			actor.set_ability_trace(trace)
	if not enabled:
		for visual: Node in _training_trace_visuals.get_children():
			_training_trace_visuals.remove_child(visual)
			visual.queue_free()


func _draw_training_ability_trace(data: Dictionary) -> void:
	if is_instance_valid(_training_trace_visuals) and training_roster.ability_traces_enabled():
		TrainingAbilityTrace.draw(_training_trace_visuals, data)


func _set_training_weapon_traces(enabled: bool) -> void:
	var visual := _training_weapon_trace
	if not is_instance_valid(visual):
		return
	player.set("weapon_trace", visual.draw_box if enabled else Callable())
	if not enabled:
		visual.clear()


func _spawn_training_enemy(archetype_id: int) -> void:
	if not training_roster.is_open() or not is_instance_valid(training_ground):
		return
	if archetype_id < 0 or archetype_id >= EnemyCatalog.ARCHETYPES.size():
		return
	var enemy_level: int = training_roster.selected_level()
	var rarity: String = training_roster.selected_rarity()
	var selected_affixes: Array[String] = training_roster.selected_affixes()
	_close_training_roster()
	var point := _training_spawn_point()
	if not point.is_finite():
		hud.notify("No clear spawn point")
		return
	var enemy := EnemyCatalog.instantiate(archetype_id)
	_prepare_training_enemy(enemy, enemy_level, rarity, selected_affixes, point)
	_refresh_training_encounter_rating()
	var tuning: Dictionary = enemy.combat_tuning_summary()
	hud.notify("%s · Level %d · %.1f Life · %.1f Attack Damage · %.2f m/s" % [
		enemy.display_name, tuning.level, tuning.life, tuning.attack_damage, tuning.move_speed,
	])


func _prepare_training_enemy(enemy: CharacterBody3D, enemy_level: int, rarity: String,
		selected_affixes: Array[String], point: Vector3) -> void:
	enemy.setup(player, enemy_level, rarity, _training_rng, Callable(training_ground, "navigation_route"),
		BestiaryData.combat_ability, selected_affixes)
	enemy.configure_encounter(0, false, 16.0)
	enemy.configure_ai(_training_encounter, _training_pressure)
	if training_roster.ability_traces_enabled():
		enemy.set_ability_trace(_draw_training_ability_trace)
	enemy.died.connect(_training_enemy_died)
	enemy.combat_event.connect(_record_combat_event)
	if enemy.has_signal("summon_requested"):
		enemy.summon_requested.connect(_training_legate_summoned)
	if enemy.has_method("configure_revival"):
		enemy.configure_revival(_find_training_corpse, _revive_training_corpse)
	enemy.position = point
	_training_actors.add_child(enemy)


func _training_legate_summoned(caster: Node3D) -> void:
	var level := int(caster.enemy_level)
	for index in 3:
		var point := _training_spawn_point()
		if not point.is_finite():
			point = caster.position + Vector3(0, 0, -1.15).rotated(Vector3.UP, TAU * index / 3.0)
		var recruit := EnemyCatalog.instantiate(EnemyCatalog.pick_archetype(level, _training_rng))
		var chosen_affixes: Array[String] = []
		_prepare_training_enemy(recruit, level, _legate_rarity(index, _training_rng), chosen_affixes, point)
	_refresh_training_encounter_rating()


func _find_training_corpse(caster: Node3D, radius: float) -> Node3D:
	var nearest: Node3D
	var distance := radius * radius
	for actor in _training_actors.get_children():
		if not actor is Enemy or not actor.can_be_raised() or actor.has_meta("raised_from_corpse"):
			continue
		var weight: float = actor.global_position.distance_squared_to(caster.global_position)
		if weight < distance and caster.can_reach_corpse(actor):
			distance = weight
			nearest = actor
	return nearest


func _revive_training_corpse(_caster: Node3D, corpse: Node3D) -> bool:
	if not is_instance_valid(corpse) or not corpse.can_be_raised() or corpse.has_meta("raised_from_corpse"):
		return false
	var enemy := EnemyCatalog.instantiate(int(corpse.archetype_id))
	enemy.set_meta("raised_from_corpse", true)
	_prepare_training_enemy(enemy, int(corpse.enemy_level), String(corpse.rarity), corpse.affixes, corpse.position)
	corpse.queue_free()
	return true


func _training_spawn_point() -> Vector3:
	var points: PackedVector3Array = training_ground.enemy_spawn_points
	var occupied: Array[Vector3] = [player.global_position]
	for actor in _training_actors.get_children():
		if actor is CharacterBody3D and actor.is_in_group("enemies"):
			occupied.append(actor.global_position)
	for offset in range(points.size()):
		var index := (_training_spawn_cursor + offset) % points.size()
		var point := points[index]
		var available := true
		for actor_position in occupied:
			if point.distance_squared_to(actor_position) < TRAINING_SPAWN_CLEARANCE * TRAINING_SPAWN_CLEARANCE:
				available = false
				break
		if available:
			_training_spawn_cursor = (index + 1) % points.size()
			return point
	return Vector3.INF


func _training_enemy_died(enemy: CharacterBody3D) -> void:
	_refresh_training_encounter_rating()
	player.on_kill()
	player.present_nearby_enemy_death(enemy)
	if player.global_position.distance_squared_to(enemy.global_position) <= 144.0:
		_record_combat_pressure(2.5)
	audio.cue("kill")


func _refresh_training_encounter_rating() -> void:
	var rating := 1
	for actor in _training_actors.get_children():
		if actor is Enemy and actor.is_in_group("enemies"):
			rating = maxi(rating, actor.enemy_level)
	if rating == _training_encounter_rating:
		return
	_training_encounter_rating = rating
	Enemy.apply_encounter_attack_rating(_training_encounter, rating)
	_training_pressure.set_encounter_rating(rating)


func _open_inventory(mode: String) -> void:
	_suspend()
	inventory_ui.open(mode)


func _open_secret_broker() -> void:
	var index := _dungeon_floor_index()
	var state := _floor_state(index)
	var catalog: Dictionary = state.broker_catalog
	if catalog.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([run.seed, index, "Lantern Broker"])
		catalog = {"stock": Items.roll_secret_vendor(maxi(int(run.level), unlocked - 1), rng)}
	if not inventory.open_vendor_catalog(catalog):
		return
	_broker_floor = index
	_open_inventory("vendor")


func _close_inventory_menu() -> void:
	if _broker_floor >= 0:
		var catalog := inventory.close_vendor_catalog()
		if not run.is_empty():
			_floor_state(_broker_floor).broker_catalog = catalog
		_broker_floor = -1
	_resume()


func _can_edit_cards() -> bool:
	return (_session_mode != SessionMode.TITLE and not in_dungeon and not is_instance_valid(training_ground)
		and run.is_empty() and is_instance_valid(hub) and hub.is_inside_tree())


func _request_inventory_disposal(source: String, id: StringName) -> void:
	var inventory_owner := _active_inventory()
	var item := inventory_owner.get_item(id)
	if item.is_empty() or source not in ["equipment", "bag"]:
		return
	if in_dungeon or is_instance_valid(training_ground):
		if _carried_drop.is_empty():
			_carried_drop = {"owner": inventory_owner, "source": source, "id": id}
		return
	if item.get("supply_kind") == Supplies.ROUTE_KEY:
		_feedback("Keep this key for the expedition's gate", "error")
		return
	var confirmation := DESTROY_ITEM_DIALOG.instantiate() as ConfirmationDialog
	confirmation.dialog_text = "Destroy %s? This permanently removes the item." % Items.visible_name(item)
	confirmation.confirmed.connect(func() -> void:
		if not inventory_owner.take_item(source, id).is_empty():
			audio.cue("loot")
		confirmation.queue_free())
	confirmation.canceled.connect(confirmation.queue_free)
	inventory_ui.add_child(confirmation)
	confirmation.popup_centered.call_deferred()


func _drop_carried_item() -> void:
	var request := _carried_drop
	_carried_drop = {}
	var inventory_owner: Inventory = request.owner
	if inventory_owner != _active_inventory():
		return
	var direction: Vector3 = -player.global_basis.z
	var practice := is_instance_valid(training_ground)
	var floor_index := _dungeon_floor_index()
	var point := Vector3.INF
	if practice:
		point = training_ground.weapon_drop_point(player.global_position, direction, _training_props.get_children())
	elif in_dungeon:
		point = _loot_drop_point(_dungeon_floors[floor_index], player.global_position, 0, direction)
	if not point.is_finite():
		_feedback("There is no clear space to drop that item", "error")
		return
	var item := inventory_owner.take_item(request.source, request.id)
	if item.is_empty():
		return
	var data := {"kind": "loot", "category": "item", "item": item, "dropped_by_player": true}
	match item.get("supply_kind", ""):
		"material":
			data.category = "material"
			data.id = item.supply_id
			data.quantity = maxi(1, int(item.get("quantity", 1)))
		"treasure_key":
			data.category = "key"
	if practice:
		var prop := _make_prop(data, _training_props.to_local(point), _training_props)
		prop.animate_drop()
	else:
		_store_loot(data, point, floor_index)
	audio.place_item(item)


func _begin_training_cards() -> void:
	_training_campaign_card_buffs = player.card_effects.snapshot()
	_training_card_deck = CardDeck.new()
	for id: String in CardCatalog.CARDS:
		_training_card_deck.unlock(id)
	_training_card_deck.equipped.assign(card_deck.equipped)
	inventory_ui.bind_card_deck(_training_card_deck)
	training_roster.bind_card_deck(_training_card_deck)


func _reset_training_cards(buffs: Dictionary = {}) -> void:
	_training_used_cards.clear()
	_queued_card = ""
	if _card_hand_open:
		_close_card_hand(false)
		if not _modal:
			_resume()
	player.card_effects.restore(buffs)


func _end_training_cards() -> void:
	_reset_training_cards(_training_campaign_card_buffs)
	_training_campaign_card_buffs.clear()
	training_roster.bind_card_deck(null)
	_training_card_deck = null
	inventory_ui.bind_card_deck(card_deck)


func _active_card_loadout() -> Array:
	if _training_card_deck != null:
		return _training_card_deck.equipped
	return run.get("card_loadout", [])


func _remaining_cards() -> Array[String]:
	var remaining: Array[String] = []
	var used: Dictionary = _training_used_cards if _training_card_deck != null else run.get("used_cards", {})
	for id: String in _active_card_loadout():
		if not id.is_empty() and not used.has(id) and CardCatalog.CARDS.has(id):
			remaining.append(id)
	return remaining


func _open_card_screen() -> void:
	if _session_mode == SessionMode.TITLE or player.is_stunned():
		return
	var in_training := _training_card_deck != null
	if not in_dungeon and not in_training:
		_suspend()
		_card_editor_open = true
		var reason := "Use Close Dungeon to edit your deck." if not run.is_empty() else ""
		card_screen.show_loadout(card_deck.owned, card_deck.equipped, true, reason)
		return
	if not _queued_card.is_empty():
		return
	var cards := _remaining_cards()
	if cards.is_empty():
		var equipped := _active_card_loadout().any(func(id: String) -> bool: return not id.is_empty())
		if in_training:
			hud.notify("All training cards are spent until the arena resets" if equipped
				else "Equip cards in F1 → Cards")
		else:
			hud.notify("All expedition cards are spent" if equipped else "No cards equipped for this expedition")
		return
	_card_original_speed = Engine.time_scale
	Engine.time_scale *= CARD_WORLD_SPEED
	_card_hand_open = true
	_interact_pending = false
	_portal_pending = false
	player.gameplay_enabled = false
	player.velocity = Vector3.ZERO
	hud.set_gameplay(false)
	hud.set_card_hand_open(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	card_screen.show_hand(cards)


func _open_cards_from_pause() -> void:
	hud.hide_menu()
	if _training_card_deck != null:
		_card_editor_open = true
		card_screen.show_loadout(_training_card_deck.owned, _training_card_deck.equipped, true, "", "Training Deck")
		return
	_resume()
	_open_card_screen()


func _close_card_screen() -> void:
	if _card_editor_open:
		_card_editor_open = false
		card_screen.dismiss()
		_resume()
	else:
		_close_card_hand(true)


func _close_card_hand(restore_controls: bool) -> void:
	if not _card_hand_open:
		return
	Engine.time_scale = _card_original_speed
	_card_hand_open = false
	hud.set_card_hand_open(false)
	if is_instance_valid(card_screen):
		card_screen.dismiss()
	if restore_controls and not _modal and not _death_pending:
		player.gameplay_enabled = true
		hud.set_gameplay(true)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _equip_card(slot: int, id: String) -> void:
	if not _card_editor_open:
		return
	if _training_card_deck != null:
		if _training_card_deck.equip(slot, id):
			card_screen.show_loadout(_training_card_deck.owned, _training_card_deck.equipped, false, "", "Training Deck")
	elif _can_edit_cards() and card_deck.equip(slot, id):
		card_screen.show_loadout(card_deck.owned, card_deck.equipped)


func _choose_card(id: String) -> void:
	if not _card_hand_open or _death_pending or player.is_stunned() or not _queued_card.is_empty():
		return
	if not _remaining_cards().has(id):
		return
	_queued_card = id
	_close_card_hand(true)


func _select_depth(level: int) -> void:
	if _session_mode == SessionMode.TITLE or is_instance_valid(training_ground) or not run.is_empty() or level < 1 or level > unlocked:
		return
	var seed_value := int(_rng.randi())
	_legate_wait = LEGATE_COMBAT_DELAY
	run = {"level": level, "seed": str(seed_value), "generation_version": Dungeon.GENERATION_VERSION,
		"rarity_version": RARITY_PROFILE_VERSION,
		"cleared": false,
		"floor_index": 0, "floor_count": 3 if level >= ExpeditionRules.third_floor_depth else 2,
		"floor_rise": 1 if _rng.randf() < ExpeditionRules.ascending_chance else -1,
		"floor_states": {}, "cleared_floors": {}, "next_loot": 0,
		"return_point": [], "return_yaw": 0.0, "return_pitch": 0.0, "key_drops": 0}
	run.merge(FLOOR_STATE_DEFAULTS.duplicate(true))
	run["features"] = ExpeditionFeatures.make_plan(level, seed_value, _dungeon_floor_count())
	run["tileset"] = String(DungeonTilesets.choose(seed_value))
	run["card_loadout"] = card_deck.equipped.duplicate()
	run["used_cards"] = {}
	run["recap"] = RECAP_DEFAULTS.duplicate()
	lifetime.add("depths_entered")
	_last_damage_actor = ""
	player.card_effects.restore({})
	_explored.clear()
	_map_fog.restore([])
	hud.close_menu()
	_build_dungeon()
	_enter_dungeon(false)
	hud.notify("Slay every enemy to unseal the next depth")


func _build_dungeon() -> void:
	_dungeon_root = Node3D.new()
	_dungeon_root.name = "Undervault"
	_dungeon_floors.clear()
	_convergence_floor = -1
	_expedition_pressure = ExpeditionPressure.new()
	_expedition_pressure.name = "ExpeditionPressure"
	_expedition_pressure.configure(player, int(run.level))
	_dungeon_root.add_child(_expedition_pressure)

	var floor_count := _dungeon_floor_count()
	var room_limit := Dungeon.MAX_ROOMS
	if floor_count > 1:
		var room_budget := mini(24, 6 + int(run.level) * 2)
		room_limit = maxi(6, ceili(float(room_budget) / float(floor_count)))
	var indices := range(floor_count) if _has_connected_floors() else [_dungeon_floor_index()]
	var previous_geometry: Node3D = null
	for floor_index: int in indices:
		var dungeon_floor := DungeonFloor.new()
		dungeon_floor.geometry = DungeonScene.instantiate()
		dungeon_floor.geometry.name = "Floor_%d" % (floor_index + 1)
		dungeon_floor.geometry.tileset_id = StringName(run.get("tileset", DungeonTilesets.DEFAULT))
		var floor_seed := int(run.seed) + floor_index * FLOOR_SEED_STRIDE
		var masks: Array = run.get("features", {}).get("masks", [])
		var mask := int(masks[floor_index]) if floor_index < masks.size() else -1
		dungeon_floor.geometry.build(int(run.level), floor_seed, int(run.get("generation_version", 1)),
			floor_index, floor_count, room_limit, int(run.get("floor_rise", -1)), mask)
		_dungeon_root.add_child(dungeon_floor.geometry)
		if previous_geometry != null:
			Dungeon.join_floors(previous_geometry, dungeon_floor.geometry)
		previous_geometry = dungeon_floor.geometry
		_dungeon_floors[floor_index] = dungeon_floor
		_populate_dungeon_floor(dungeon_floor, floor_index, floor_seed)
	_restore_convergence_routes()
	_use_dungeon_floor(_dungeon_floor_index())


func _populate_dungeon_floor(dungeon_floor: DungeonFloor, floor_index: int, floor_seed: int) -> void:
	var geometry := dungeon_floor.geometry
	var state := _floor_state(floor_index)
	if not _has_connected_floors():
		for direction: int in geometry.stairs:
			var stairs: Node3D = geometry.stairs[direction]
			stairs.passed.connect(_stair_threshold_entered.bind(direction))
	geometry.breakable_destroyed.connect(_dungeon_breakable_destroyed.bind(floor_index))
	geometry.restore_breakables(state.broken_props)
	dungeon_floor.actors = Node3D.new()
	dungeon_floor.actors.name = "EnemiesAndProjectiles"
	geometry.add_child(dungeon_floor.actors)
	dungeon_floor.props = Node3D.new()
	dungeon_floor.props.name = "Interactables"
	geometry.add_child(dungeon_floor.props)

	var roster_rng := RandomNumberGenerator.new()
	roster_rng.seed = floor_seed + 30289
	var use_pack_rarity := int(run.get("rarity_version", 1)) >= RARITY_PROFILE_VERSION
	var enemy_level := int(run.level)
	var roster := _roll_encounter_roster(geometry.encounters, enemy_level, roster_rng, use_pack_rarity)
	for index in range(roster.size()):
		var entry: Dictionary = geometry.encounters[index]
		var id := str(index)
		if state.defeated.has(id):
			continue
		var room := int(entry.get("room", -1))
		var trigger := String(entry.get("spawn_trigger", ""))
		var wave_index := int(entry.get("wave", 0))
		var current_wave := int(state.ambush_triggered.get(str(room), -1))
		if room >= 0 and not trigger.is_empty() and wave_index > current_wave:
			var wave: Array = dungeon_floor.dormant_rooms.get_or_add(room, [])
			wave.append({"id": id, "entry": entry, "roll": roster[index], "trigger": trigger})
		else:
			_spawn_dungeon_enemy(dungeon_floor, floor_index, id, entry, roster[index], state)
	for entry: Dictionary in geometry.chests:
		var id := str(entry.id)
		var data := {"kind": "chest", "id": id, "locked": bool(entry.locked),
			"opened": state.opened.has(id), "room": int(entry.get("room", -1)),
			"guarded": bool(entry.get("guarded", false)), "side_cache": bool(entry.get("side_cache", false)),
			"secret_cache": bool(entry.get("secret_cache", false)), "spawn_trigger": String(entry.get("spawn_trigger", "")),
			"trial_waves": int(entry.get("trial_waves", 0)), "challenge_type": String(entry.get("challenge_type", ""))}
		var pose: Transform3D = geometry.coffer_pose(int(entry.id))
		dungeon_floor.chests[id] = _make_prop(data, pose.origin, dungeon_floor.props)
		dungeon_floor.chests[id].transform = pose
	for id: String in state.extra_enemies:
		if not state.defeated.has(id):
			var record: Dictionary = state.extra_enemies[id]
			var entry: Dictionary = record.entry.duplicate()
			entry.position = _vector(entry.position, geometry.spawn_position)
			_spawn_dungeon_enemy(dungeon_floor, floor_index, id, entry, record.roll, state)
	for entry: Dictionary in geometry.hazard_points:
		var challenge := bool(entry.get("challenge", false))
		if bool(run.cleared) and not challenge:
			continue
		var kind := String(entry.kind)
		var scene: PackedScene = HAZARD_SCENES.get(kind, HAZARD_SCENES["spike_plate"])
		var hazard := scene.instantiate() as Node3D
		var phase := float(entry.get("phase", fmod(float(dungeon_floor.hazards.size()) * 0.37, 1.2)))
		hazard.configure(kind, enemy_level, player, phase, entry)
		hazard.position = entry.position
		if challenge:
			hazard.set_meta("challenge_secret", String(entry.secret_id))
			hazard.set_active(state.secrets_opened.has(String(entry.secret_id)))
		dungeon_floor.actors.add_child(hazard)
		dungeon_floor.hazards.append(hazard)
	if not geometry.lava_floor.is_empty():
		var lava := LavaFloor.instantiate()
		lava.position = geometry.lava_floor.position
		lava.configure(player, geometry.lava_floor.extent)
		dungeon_floor.actors.add_child(lava)
		lava.set_active(not bool(run.cleared))
		dungeon_floor.hazards.append(lava)
	if not geometry.submerged_basin.is_empty():
		dungeon_floor.water = BasinWater.instantiate()
		dungeon_floor.water.position = geometry.submerged_basin.position
		dungeon_floor.water.configure(geometry.submerged_basin.extent)
		geometry.add_child(dungeon_floor.water)
	for id in state.loot:
		var stored: Dictionary = state.loot[id]
		if stored.get("item") is Dictionary:
			stored["item"] = Inventory.restore_item(stored["item"])
		dungeon_floor.loot[id] = _make_prop(stored, _vector(stored.point, geometry.spawn_position), dungeon_floor.props)
	if state.portal.size() >= 3:
		var saved_point := _vector(state.portal, geometry.spawn_position)
		var point: Vector3 = geometry.return_portal_clearance(saved_point)
		dungeon_floor.portal = _make_prop({"kind": "portal"}, point, dungeon_floor.props)
		state.portal = _coords(point)
		dungeon_floor.portal.rotation.y = float(state.get("portal_yaw", 0.0))
	_place_secret_passages(dungeon_floor, state)
	_place_route_gates(dungeon_floor, state)
	if geometry.secret_merchant_position.is_finite():
		dungeon_floor.broker = BrokerScene.instantiate()
		dungeon_floor.broker.position = geometry.secret_merchant_position
		dungeon_floor.broker.rotation.y = geometry.secret_merchant_yaw
		dungeon_floor.broker.configure(geometry.secret_merchant_passage, state.secrets_opened.has(geometry.secret_merchant_passage))
		dungeon_floor.props.add_child(dungeon_floor.broker)
	if geometry.blood_altar_position.is_finite():
		dungeon_floor.blood_altar = BloodAltar.instantiate()
		dungeon_floor.blood_altar.position = geometry.blood_altar_position
		dungeon_floor.blood_altar.configure(not String(run.get("blood_oath", "")).is_empty())
		dungeon_floor.props.add_child(dungeon_floor.blood_altar)



func _spawn_dungeon_enemy(dungeon_floor: DungeonFloor, floor_index: int, id: String,
		entry: Dictionary, roll: Dictionary, state: Dictionary) -> void:
	var geometry := dungeon_floor.geometry
	var enemy_level := int(run.level)
	var pack := int(entry.get("pack", -1))
	var rarity: String = roll.rarity
	var mob_rng := RandomNumberGenerator.new()
	mob_rng.seed = int(roll.seed)
	var enemy := EnemyCatalog.instantiate(int(entry.archetype))
	var chosen_affixes: Array[String] = []
	chosen_affixes.assign(roll.get("affixes", []))
	enemy.setup(player, enemy_level, rarity, mob_rng, Callable(geometry, "navigation_route"),
		BestiaryData.combat_ability, chosen_affixes, DepthDifficulty.for_depth(int(run.level)))
	var oath := _blood_oath()
	if enemy.archetype_id != LEGATE_ID:
		enemy.apply_expedition_oath(float(oath.get("life", 1.0)), float(oath.get("damage", 1.0)))
	var room := int(entry.get("room", -1))
	var corridor := room < 0
	var patrol := PackedVector3Array()
	for point: Vector3 in entry.get("patrol_points", PackedVector3Array()):
		patrol.append(geometry.transform * point)
	enemy.configure_encounter(pack, bool(entry.get("ambush", false)),
		float(entry.get("alert_radius", 12.0)), patrol,
		Enemy.expedition_sight_range(enemy_level, corridor))
	if not dungeon_floor.pack_encounters.has(pack):
		var encounter: AIEncounter3D = Enemy.create_ai_encounter(enemy_level, player)
		encounter.name = "PackEncounter_%d" % pack
		dungeon_floor.actors.add_child(encounter)
		dungeon_floor.pack_encounters[pack] = encounter
	enemy.configure_ai(dungeon_floor.pack_encounters[pack], _expedition_pressure)
	var last: Dictionary = state.mob_states.get(id, {})
	enemy.position = _vector(last.get("point", []), entry.position)
	var metamorphosis: Variant = last.get("metamorphosis")
	if metamorphosis is Dictionary:
		enemy.restore_metamorphosis(metamorphosis)
	if last.has("life"):
		enemy.restore_saved_life(float(last.life), float(last.get("max_life", 0.0)))
	if room >= 0:
		dungeon_floor.room_enemies[room] = int(dungeon_floor.room_enemies.get(room, 0)) + 1
	enemy.encountered.connect(_discover_enemy)
	enemy.combat_event.connect(_record_combat_event)
	enemy.died.connect(_enemy_died.bind(id, room, floor_index))
	if enemy.has_signal("summon_requested"):
		enemy.summon_requested.connect(_legate_summoned.bind(floor_index))
	if enemy.has_method("configure_revival"):
		enemy.configure_revival(_find_dungeon_corpse.bind(floor_index), _revive_dungeon_corpse.bind(floor_index))
	dungeon_floor.actors.add_child(enemy)
	var behavior: Variant = last.get("behavior", {})
	enemy.restore_checkpoint_behavior(behavior if behavior is Dictionary else {})
	dungeon_floor.enemies[id] = enemy
	dungeon_floor.enemy_origins[id] = {"entry": entry, "roll": roll}


func _trigger_entered_ambush() -> void:
	var dungeon_floor := _dungeon_floors[_dungeon_floor_index()]
	if dungeon_floor.dormant_rooms.is_empty():
		return
	var room := int(dungeon.map_cells.get(dungeon.tile_at(player.global_position), -1))
	_activate_ambush(room, "threshold")


func _tick_legate_incursion(delta: float) -> void:
	if run.get("legate_used", false) or not run.get("features", {}).get("legate", false) or run.cleared:
		return
	var combat := false
	for enemy: Node3D in _enemies.values():
		if enemy.is_fighting_player() and enemy.global_position.distance_squared_to(player.global_position) <= 100.0:
			combat = true
			break
	if not combat:
		_legate_wait = LEGATE_COMBAT_DELAY
		return
	_legate_wait -= delta
	if _legate_wait > 0.0:
		return
	_legate_wait = 2.5
	if _rng.randf() >= LEGATE_CHANCE_PER_POLL:
		return
	var floor_index := _dungeon_floor_index()
	var dungeon_floor := _dungeon_floors[floor_index]
	var sites := _incursion_positions(dungeon_floor, player.global_position, 3)
	if sites.size() < 3 or player.global_position.distance_squared_to(sites[2]) > 120.0:
		return
	_add_incursion_enemy(dungeon_floor, floor_index, "legate", LEGATE_ID, "normal", sites[2])
	run["legate_used"] = true
	hud.notify("A Grave Legate has answered the battle")


func _incursion_positions(dungeon_floor: DungeonFloor, around: Vector3, count: int) -> Array[Vector3]:
	var geometry := dungeon_floor.geometry
	var cells: Array = geometry.map_cells.keys()
	var origin: Vector2i = geometry.tile_at(around)
	cells.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		return first.distance_squared_to(origin) < second.distance_squared_to(origin))
	var spots: Array[Vector3] = []
	var taken: Array[Vector3] = [player.global_position]
	for enemy: Node3D in dungeon_floor.enemies.values():
		taken.append(enemy.global_position)
	var space := get_viewport().get_world_3d().direct_space_state
	for tile: Vector2i in cells:
		if tile.distance_squared_to(origin) > 12:
			break
		var candidate: Vector3 = geometry.to_global(geometry.tile_position(tile))
		if taken.any(func(point: Vector3) -> bool: return point.distance_squared_to(candidate) < 2.25):
			continue
		if not geometry.ground_is_open(candidate):
			continue
		var line := PhysicsRayQueryParameters3D.create(around + Vector3.UP * 0.82, candidate + Vector3.UP * 0.82, 1)
		if not space.intersect_ray(line).is_empty():
			continue
		spots.append(candidate)
		if spots.size() >= count:
			return spots
	return spots


func _add_incursion_enemy(dungeon_floor: DungeonFloor, floor_index: int, id: String, archetype: int,
		rarity: String, point: Vector3) -> void:
	var entry := {"archetype": archetype, "position": dungeon_floor.geometry.to_local(point), "room": -1,
		"pack": -100, "alert_radius": 16.0}
	var roll := {"seed": int(_rng.randi()), "rarity": rarity}
	var stored := entry.duplicate()
	stored.position = _coords(entry.position)
	var state := _floor_state(floor_index)
	state.extra_enemies[id] = {"entry": stored, "roll": roll}
	_spawn_dungeon_enemy(dungeon_floor, floor_index, id, entry, roll, state)


func _legate_rarity(index: int, rng: RandomNumberGenerator) -> String:
	if index == 0:
		return "rare"
	return "magic" if rng.randf() < 0.42 else "normal"


func _legate_summoned(caster: Node3D, floor_index: int) -> void:
	floor_index = _floor_at(caster.global_position, floor_index)
	var dungeon_floor := _dungeon_floors[floor_index]
	var sites := _incursion_positions(dungeon_floor, caster.global_position, 3)
	for index in 3:
		var point := (sites[index] if index < sites.size() else caster.global_position
			+ Vector3(0.0, 0.0, 0.30).rotated(Vector3.UP, TAU * float(index) / 3.0))
		var archetype := EnemyCatalog.pick_archetype(int(run.level), _rng)
		_add_incursion_enemy(dungeon_floor, floor_index, "levy_%d" % index, archetype, _legate_rarity(index, _rng), point)
	hud.notify("The Grave Legate has called its levy")


func _find_dungeon_corpse(caster: Node3D, radius: float, floor_index: int) -> Node3D:
	var physical_floor := _floor_at(caster.global_position, floor_index)
	var nearest: Node3D
	var distance := radius * radius
	for index: int in _dungeon_floors:
		var dungeon_floor := _dungeon_floors[index]
		for id in dungeon_floor.corpses.keys():
			var corpse: Node3D = dungeon_floor.corpses[id]
			if not is_instance_valid(corpse):
				dungeon_floor.corpses.erase(id)
				continue
			var weight := caster.global_position.distance_squared_to(corpse.global_position)
			if weight < distance and _floor_at(corpse.global_position, index) == physical_floor \
					and corpse.can_be_raised() and caster.can_reach_corpse(corpse):
				distance = weight
				nearest = corpse
	return nearest


func _revive_dungeon_corpse(_caster: Node3D, corpse: Node3D, _floor_index: int) -> bool:
	if not is_instance_valid(corpse) or not corpse.can_be_raised():
		return false
	var dungeon_floor: DungeonFloor
	var id: Variant = null
	var floor_index := -1
	for index: int in _dungeon_floors:
		dungeon_floor = _dungeon_floors[index]
		id = dungeon_floor.corpses.find_key(corpse)
		if id != null:
			floor_index = index
			break
	if floor_index < 0:
		return false
	var state := _floor_state(floor_index)
	if state.revived.has(id):
		return false
	var origin: Dictionary = dungeon_floor.enemy_origins[id]
	var entry: Dictionary = origin.entry.duplicate()
	entry.position = dungeon_floor.geometry.to_local(corpse.global_position)
	var roll: Dictionary = origin.roll.duplicate()
	roll["affixes"] = Array(corpse.affixes)
	state.defeated.erase(id)
	state.revived[id] = true
	dungeon_floor.corpses.erase(id)
	var physical_floor := _floor_at(corpse.global_position, floor_index)
	corpse.queue_free()
	_spawn_dungeon_enemy(dungeon_floor, floor_index, String(id), entry, roll, state)
	var raised: Node3D = dungeon_floor.enemies[id]
	if physical_floor != floor_index:
		raised.set_convergence_route(physical_floor, Callable(_dungeon_floors[physical_floor].geometry, "navigation_route"))
	raised.restore_saved_life(raised.max_health * 0.54, raised.max_health)
	return true


func _activate_ambush(room: int, trigger: String, floor_index := -1) -> bool:
	if floor_index < 0:
		floor_index = _dungeon_floor_index()
	var dungeon_floor := _dungeon_floors[floor_index]
	var remaining: Array = dungeon_floor.dormant_rooms.get(room, [])
	if remaining.is_empty() or remaining[0].trigger != trigger:
		return false
	var state := _floor_state(floor_index)
	var wave_index := int(state.ambush_triggered.get(str(room), -1)) + 1
	var future_waves: Array = []
	var spawned := false
	for record: Dictionary in remaining:
		if int(record.entry.get("wave", 0)) != wave_index:
			future_waves.append(record)
			continue
		var entry: Dictionary = record.entry.duplicate()
		var point: Vector3 = dungeon_floor.geometry.to_global(entry.position)
		if player.global_position.distance_squared_to(point) < 1.44:
			var tile: Vector2i = dungeon_floor.geometry.tile_at(point)
			for neighbor: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := tile + neighbor
				var local: Vector3 = dungeon_floor.geometry.tile_position(next)
				var candidate: Vector3 = dungeon_floor.geometry.to_global(local)
				if (int(dungeon_floor.geometry.map_cells.get(next, -1)) == room
						and dungeon_floor.geometry.ground_is_open(candidate) and player.global_position.distance_squared_to(candidate) >= 1.44):
					local.y = entry.position.y
					entry.position = local
					break
		_spawn_dungeon_enemy(dungeon_floor, floor_index, record.id, entry, record.roll, state)
		spawned = true
	if not spawned:
		return false
	state.ambush_triggered[str(room)] = wave_index
	if future_waves.is_empty():
		dungeon_floor.dormant_rooms.erase(room)
	else:
		dungeon_floor.dormant_rooms[room] = future_waves
	var trial := _trial_coffer(dungeon_floor, room)
	if trial != null:
		hud.notify("Trial Coffer · Wave %d of %d" % [wave_index + 1, int(trial.payload.trial_waves)])
	_update_hud()
	return true


func _has_connected_floors() -> bool:
	return int(run.get("generation_version", 1)) >= Dungeon.CONNECTED_FLOOR_VERSION


func _floor_state(index: int) -> Dictionary:
	if index == _dungeon_floor_index():
		return run
	var parked: Dictionary = run.floor_states
	var id := str(index)
	if not parked.has(id):
		parked[id] = FLOOR_STATE_DEFAULTS.duplicate(true)
	return parked[id]


func _use_dungeon_floor(index: int) -> void:
	var dungeon_floor := _dungeon_floors[index]
	dungeon = dungeon_floor.geometry
	_actors = dungeon_floor.actors
	_props = dungeon_floor.props
	_enemies = dungeon_floor.enemies
	_remaining_by_room = dungeon_floor.room_enemies
	_hazards = dungeon_floor.hazards
	_loot = dungeon_floor.loot
	_chests = dungeon_floor.chests
	_concealed_tiles = dungeon_floor.concealed
	_portal_prop = dungeon_floor.portal
	if in_dungeon:
		player.set_water_volume(dungeon_floor.water)


func _track_dungeon_floor() -> void:
	var current := _dungeon_floor_index()
	var index := _floor_at(player.global_position, current)
	if index == current:
		return
	_store_floor_exploration()
	_select_floor_state(index)
	_use_dungeon_floor(index)
	_set_world_target(null)
	_update_hud()
	_update_map()


func _floor_at(point: Vector3, preferred: int) -> int:
	if not _has_connected_floors() or _dungeon_floors[preferred].geometry.floor_contains(point):
		return preferred
	for index: int in _dungeon_floors:
		if _dungeon_floors[index].geometry.floor_contains(point):
			return index
	return preferred


func _select_floor_state(index: int) -> void:
	var parked: Dictionary = run.floor_states
	var outgoing := {}
	for key in FLOOR_STATE_DEFAULTS:
		outgoing[key] = run.get(key, FLOOR_STATE_DEFAULTS[key])
	parked[str(_dungeon_floor_index())] = outgoing
	var incoming: Dictionary = parked.get(str(index), {})
	parked.erase(str(index))
	var pristine := FLOOR_STATE_DEFAULTS.duplicate(true)
	for key in pristine:
		run[key] = incoming.get(key, pristine[key])
	run.floor_index = index
	_restore_floor_exploration()


func _dungeon_floor_count() -> int:
	return clampi(int(run.get("floor_count", 1)), 1, 3) if int(run.get("generation_version", 1)) >= 4 else 1


func _dungeon_floor_index() -> int:
	return clampi(int(run.get("floor_index", 0)), 0, _dungeon_floor_count() - 1)


func _stair_threshold_entered(body: Node3D, direction: int) -> void:
	if body == player and in_dungeon and not _changing and not _modal and not _death_pending:
		_change_dungeon_floor.call_deferred(direction)


func _change_dungeon_floor(direction: int) -> void:
	if not in_dungeon or _changing or _modal or _death_pending or _has_connected_floors():
		return
	var floor_index := _dungeon_floor_index()
	var next_floor := floor_index + direction
	var departing: Node3D = dungeon.stairs.get(direction)
	if not is_instance_valid(departing) or next_floor < 0 or next_floor >= _dungeon_floor_count():
		return
	_close_card_hand(true)
	_changing = true
	_interact_pending = false
	_portal_pending = false
	_last_target = null
	var lateral_offset := departing.to_local(player.global_position).x
	var pitch: float = player.view_pitch()
	_remember_active_floor()
	_select_floor_state(next_floor)
	_world.remove_child(_dungeon_root)
	_dungeon_root.free()
	_build_dungeon()
	_world.add_child(_dungeon_root)
	var arriving: Node3D = dungeon.stairs.get(-direction)
	if is_instance_valid(arriving):
		player.place_at(arriving.arrival_point(lateral_offset), arriving.rotation.y + PI, pitch)
	else:
		player.place_at(dungeon.spawn_position, dungeon.spawn_yaw, pitch)
	hud.set_prompt("")
	_update_hud()
	_update_map()
	_changing = false


func _place_secret_passages(dungeon_floor: DungeonFloor, state: Dictionary) -> void:
	var opened: Dictionary = state.get("secrets_opened", {})
	for entry: Dictionary in dungeon_floor.geometry.secret_passages:
		var passage := SecretPassage.instantiate() as Node3D
		passage.position = entry.position
		passage.rotation.y = float(entry.yaw)
		var id := String(entry.id)
		var is_open := bool(opened.get(id, false))
		passage.configure(id, is_open, entry.wall_tint, dungeon_floor.geometry.wall_texture(),
			dungeon_floor.geometry.wall_repeats_per_metre())
		dungeon_floor.props.add_child(passage)
		if not is_open:
			for tile: Vector2i in entry.hidden_tiles:
				dungeon_floor.concealed[tile] = true


func _place_route_gates(dungeon_floor: DungeonFloor, state: Dictionary) -> void:
	var opened: Dictionary = state.opened_route_gates
	var collected: Dictionary = state.collected_route_keys
	for entry: Dictionary in dungeon_floor.geometry.route_gates:
		var id := String(entry.id)
		var gate := RouteGate.instantiate() as StaticBody3D
		gate.position = entry.position
		gate.rotation.y = float(entry.yaw)
		gate.configure(id, entry.key_name, opened.has(id))
		dungeon_floor.props.add_child(gate)
		if opened.has(id) or collected.has(id):
			continue
		var ground_id := "key_" + id
		var item := Supplies.route_key(id, entry.key_name)
		item["id"] = ground_id
		var record := {"kind": "loot", "category": "item", "item": item, "id_on_ground": ground_id,
			"route_key_source": id}
		dungeon_floor.loot[ground_id] = _make_prop(record, entry.key_position, dungeon_floor.props)


func _unlock_route_gate(gate: Node3D) -> void:
	var id := String(gate.payload.id)
	if not gate.pick_available():
		return
	if not inventory.consume_route_key(id):
		_feedback("You need the " + String(gate.payload.key_name), "error")
		return
	run.opened_route_gates[id] = true
	lifetime.add("gates_opened")
	gate.open()
	audio.cue("loot")
	_update_hud()


func _blood_oath() -> Dictionary:
	var id := String(run.get("blood_oath", ""))
	return {} if id.is_empty() else BloodAltarRules.choice(id)


func _accept_blood_oath(id: String) -> void:
	if not in_dungeon or not String(run.get("blood_oath", "")).is_empty():
		return
	var dungeon_floor := _dungeon_floors[_dungeon_floor_index()]
	var oath := BloodAltarRules.choice(id)
	if oath.is_empty() or not is_instance_valid(dungeon_floor.blood_altar) or not dungeon_floor.blood_altar.pick_available():
		return
	var key_count := int(oath.get("keys", 0))
	if key_count > 0 and not inventory.add_treasure_keys(key_count):
		hud.notify("Make room in your pack for the treasure key")
		return
	run["blood_oath"] = id
	dungeon_floor.blood_altar.spend()
	for current: DungeonFloor in _dungeon_floors.values():
		for enemy: Node3D in current.enemies.values():
			if enemy.archetype_id != LEGATE_ID:
				enemy.apply_expedition_oath(float(oath.get("life", 1.0)), float(oath.get("damage", 1.0)))
	hud.close_menu()
	hud.notify(oath.name)
	audio.cue("portal")


func _open_secret_passage(passage: Node3D) -> void:
	if not passage.open():
		return
	var id := String(passage.payload.id)
	var opened: Dictionary = run.get("secrets_opened", {})
	opened[id] = true
	run["secrets_opened"] = opened
	lifetime.add("secrets_opened")
	var broker: Node3D = _dungeon_floors[_dungeon_floor_index()].broker
	if is_instance_valid(broker) and broker.passage_id == id:
		broker.discover()
	for hazard: Node3D in _hazards:
		if hazard.get_meta("challenge_secret", "") == id:
			hazard.set_active(true)
	for entry: Dictionary in dungeon.secret_passages:
		if String(entry.id) == id:
			for tile: Vector2i in entry.hidden_tiles:
				_concealed_tiles.erase(tile)
			break
	_update_map()


func _dungeon_breakable_destroyed(id: String, point: Vector3, floor_index := -1) -> void:
	if not in_dungeon or run.is_empty():
		return
	var index := floor_index if floor_index >= 0 else _dungeon_floor_index()
	var state := _floor_state(index)
	var broken: Dictionary = state.broken_props
	if broken.has(id):
		return
	broken[id] = true
	lifetime.add("breakables")
	if player.effects.has("masons_listener"):
		var dungeon_floor: DungeonFloor = _dungeon_floors[index]
		var wall := DungeonWallClues.nearest(dungeon_floor.geometry, dungeon_floor.props, point, state.mason_clues)
		if wall != null and wall.play_mason_clue():
			state.mason_clues[wall.payload.id] = true
	var salvage := RandomNumberGenerator.new()
	salvage.seed = hash([run.seed, index, id, "breakable_salvage"])
	var depth := int(run.level)
	var bonus := float(clampi(depth - 1, 0, 11))
	if salvage.randf() < BREAKABLE_REWARD_CHANCE + bonus * BREAKABLE_REWARD_PER_DEPTH:
		if salvage.randf() < BREAKABLE_MATERIAL_SHARE:
			var material := Items.material_drop(depth, salvage)
			if not material.is_empty():
				_drop({"category": "material", "id": material}, point, 0, Vector3.ZERO, index)
		else:
			var gold_bonus := bonus * BREAKABLE_GOLD_PER_DEPTH
			var gold := _roll_gold(1.0 + gold_bonus, 2.0 + gold_bonus, salvage)
			_drop({"category": "gold", "amount": gold}, point, 0, Vector3.ZERO, index)


func _roll_encounter_roster(entries: Array[Dictionary], level: int, rng: RandomNumberGenerator,
		use_pack_rarity: bool) -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	var rare_packs: Dictionary[int, bool] = {}
	var magic_slots: Array[int] = []
	var rare_slots: Array[int] = []
	# Roll the entire floor so defeated slots keep their share of the original rarity budget.
	for entry in entries:
		var rarity := _monster_rarity(level, rng, use_pack_rarity)
		var geometry_seed := int(rng.randi())
		if entry.get("swarm", false):
			rarity = "normal"
		var pack := int(entry.get("pack", -1))
		if use_pack_rarity and rarity == "rare" and pack >= 0:
			if rare_packs.has(pack):
				rarity = "magic"
			else:
				rare_packs[pack] = true
		if rarity == "magic":
			magic_slots.append(roster.size())
		elif rarity == "rare":
			rare_slots.append(roster.size())
		roster.append({"rarity": rarity, "seed": geometry_seed})
	if use_pack_rarity:
		var elite_limit := floori(float(roster.size()) * FLOOR_ELITE_SHARE_LIMIT)
		var excess := magic_slots.size() + rare_slots.size() - elite_limit
		for _index in range(maxi(0, excess)):
			var slots := magic_slots if not magic_slots.is_empty() else rare_slots
			var slot_index := rng.randi_range(0, slots.size() - 1)
			roster[slots[slot_index]].rarity = "normal"
			slots[slot_index] = slots.back()
			slots.pop_back()
	return roster


func _monster_rarity(level: int, rng: RandomNumberGenerator, use_pack_rarity: bool) -> String:
	var chance := rng.randf()
	var level_steps := float(level - 1)
	var rare := minf(0.12, 0.035 + level_steps * 0.007) if use_pack_rarity else minf(0.23, 0.035 + level_steps * 0.016)
	var magic := minf(0.34, 0.16 + level_steps * 0.014) if use_pack_rarity else minf(0.48, 0.16 + level_steps * 0.023)
	if chance < rare:
		return "rare"
	if chance < rare + magic:
		return "magic"
	return "normal"


func _enter_dungeon(returning: bool) -> void:
	if _changing or run.is_empty() or in_dungeon or is_instance_valid(training_ground):
		return
	_changing = true
	_interact_pending = false
	_portal_pending = false
	_world.remove_child(hub)
	_world.add_child(_dungeon_root)
	run.erase("retained_until")
	in_dungeon = true
	_convergence_floor = -1
	player.set_water_volume(_dungeon_floors[_dungeon_floor_index()].water)
	player.combat_enabled = true
	_validate_saved_loot()
	var point: Vector3 = dungeon.to_global(dungeon.spawn_position)
	var heading: float = dungeon.spawn_yaw + dungeon.global_rotation.y
	var pitch := 0.0
	if returning and not run.return_point.is_empty():
		point = _vector(run.return_point, point)
		heading = float(run.return_yaw)
		pitch = float(run.return_pitch)
	player.place_at(point, heading, pitch)
	audio.set_zone("dungeon")
	audio.cue("portal")
	_update_hud()
	_changing = false


func _enter_hub(preserve_position := true) -> void:
	if _changing or not in_dungeon:
		return
	_changing = true
	if preserve_position:
		_remember_active_floor()
		run.return_point = _coords(player.global_position)
		run.return_yaw = player.rotation.y
		run.return_pitch = player.view_pitch()
	_world.remove_child(_dungeon_root)
	_world.add_child(hub)
	in_dungeon = false
	player.set_water_volume(null)
	player.combat_enabled = false
	hub.set_dungeon_state(true, bool(run.cleared))
	player.place_at(hub.spawn_position)
	_altar_armed = false
	if bool(run.cleared) and preserve_position and not run.has("close_deadline"):
		run.close_deadline = Time.get_unix_time_from_system() + ExpeditionRules.cleared_grace_seconds
		hud.notify("The vault seals in %d seconds" % ceili(ExpeditionRules.cleared_grace_seconds))
	audio.set_zone("hub")
	audio.cue("portal")
	_update_hud()
	_changing = false


func _instance_deadline() -> float:
	return float(run.get("close_deadline", run.get("retained_until", 0.0)))


func _check_dungeon_deadline() -> void:
	var deadline := _instance_deadline()
	if deadline > 0.0 and Time.get_unix_time_from_system() >= deadline and not _changing:
		_close_dungeon(true)


func _close_dungeon(automatic := false) -> void:
	if run.is_empty() or (is_instance_valid(training_ground) and not automatic):
		return
	if is_instance_valid(training_ground):
		_training_campaign_card_buffs.clear()
	else:
		_close_card_hand(true)
		_queued_card = ""
		player.card_effects.restore({})
	if in_dungeon:
		_enter_hub(false)
	if is_instance_valid(_dungeon_root):
		_dungeon_root.free()
	_dungeon_root = null
	_dungeon_floors.clear()
	dungeon = null
	_actors = null
	_expedition_pressure = null
	_props = null
	_portal_prop = null
	_enemies.clear()
	_remaining_by_room.clear()
	_hazards.clear()
	_chests.clear()
	_loot.clear()
	_explored.clear()
	_map_fog.restore([])
	_concealed_tiles.clear()
	inventory.clear_expedition_keys()
	run.clear()
	hub.set_dungeon_state(false, false)
	_altar_armed = false
	if (not automatic or _confirm_close) and hud.is_menu_open():
		hud.close_menu()
	_update_hud()
	hud.notify("The vault has been sealed")


func _create_portal() -> void:
	if not in_dungeon:
		return
	var world_state := player.get_world_3d().direct_space_state
	var direction: Vector3 = -player.global_basis.z
	var point: Vector3 = player.global_position + direction * 2.45
	var start: Vector3 = player.global_position + Vector3.UP * 0.6
	var wall := world_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, point + Vector3.UP * 0.6, 1))
	if not wall.is_empty():
		point = wall.position - direction * 0.43
	var clear_distance := direction.dot(point - player.global_position)
	if not dungeon.ground_is_open(point) and clear_distance > 0.8:
		for fraction in [0.75, 0.55, 0.35]:
			var closer: Vector3 = player.global_position + direction * (clear_distance * fraction)
			if dungeon.ground_is_open(closer):
				point = closer
				break
	point = dungeon.to_global(dungeon.return_portal_clearance(dungeon.to_local(point)))
	var ground := world_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 0.72, point - Vector3.UP * 1.1, 1))
	if not ground.is_empty():
		point.y = ground.position.y + 0.035
	else:
		point.y = player.global_position.y + 0.035
	for dungeon_floor: DungeonFloor in _dungeon_floors.values():
		if is_instance_valid(dungeon_floor.portal):
			dungeon_floor.portal.queue_free()
			dungeon_floor.portal = null
	for parked: Dictionary in run.get("floor_states", {}).values():
		parked["portal"] = []
		parked["portal_yaw"] = 0.0
	var local_point: Vector3 = dungeon.to_local(point)
	_portal_prop = _make_prop({"kind": "portal"}, local_point)
	_dungeon_floors[_dungeon_floor_index()].portal = _portal_prop
	var local_yaw: float = player.rotation.y - dungeon.global_rotation.y
	_portal_prop.rotation.y = local_yaw
	run.portal = _coords(local_point)
	run.portal_yaw = local_yaw
	audio.cue("portal")


func _make_prop(data: Dictionary, point: Vector3, container: Node3D = null) -> Node3D:
	var prop := Prop.new()
	prop.position = point
	prop.setup(data)
	var parent := container if container != null else _props
	parent.add_child(prop)
	return prop


func _discover_enemy(enemy: CharacterBody3D) -> void:
	var id: int = enemy.archetype_id
	if bestiary_discoveries.has(id):
		return
	bestiary_discoveries[id] = true
	hud.notify_discovery(enemy.archetype_name)


func _enemy_died(enemy: Node3D, id: String, room: int, floor_index := -1) -> void:
	var index := floor_index if floor_index >= 0 else _dungeon_floor_index()
	var dungeon_floor: DungeonFloor = _dungeon_floors.get(index)
	if dungeon_floor == null or not dungeon_floor.enemies.has(id) or run.is_empty():
		return
	var state := _floor_state(index)
	dungeon_floor.enemies.erase(id)
	if room >= 0:
		dungeon_floor.room_enemies[room] = int(dungeon_floor.room_enemies[room]) - 1
	state.defeated[id] = true
	state.mob_states.erase(id)
	if not state.revived.has(id) and enemy.can_be_raised():
		dungeon_floor.corpses[id] = enemy
	if id != "legate" or enemy.health <= 0.0:
		run.recap.kills = int(run.recap.kills) + 1
		lifetime.kill(enemy.archetype_name, enemy.rarity)
		if enemy.rarity != "normal":
			run.recap.elite_kills = int(run.recap.elite_kills) + 1
	if id == "legate" or state.revived.has(id):
		_check_clear_after_enemy(dungeon_floor, room, index, state)
		return
	player.on_kill()
	player.present_nearby_enemy_death(enemy)
	CasterLegendaryEffects.on_rare_kill(player, enemy, _active_combat_actors(), run)
	if player.global_position.distance_squared_to(enemy.global_position) <= 144.0:
		_record_combat_pressure(2.5)
	audio.cue("kill")
	var point := enemy.global_position + Vector3.UP * 0.035
	var depth := int(run.level)
	var source := String(enemy.rarity)
	var previous_level := progression.level
	if progression.award_kill(int(enemy.enemy_level), source) > 0:
		_update_progression(previous_level)
	var reward_index := 0
	var rarity_bonus := float(player.stats.loot_rarity)
	var gear_bonus := float(_blood_oath().get("gear", 1.0))
	if _rng.randf() < minf(1.0, Items.enemy_drop_chance(depth, source, "gear") * gear_bonus):
		# Deep drops reward elite encounters without advancing early legendary eligibility.
		var item_level := depth + int(ENEMY_GEAR_LEVEL_BONUS.get(source, 0)) if depth > 10 else depth
		_drop({"category": "item", "item": Items.roll_item(item_level, source, _rng, rarity_bonus)}, point, reward_index, Vector3.ZERO, index)
		reward_index += 1
	var gold := _roll_enemy_gold(int(enemy.enemy_level), source)
	_drop({"category": "gold", "amount": gold}, point, reward_index, Vector3.ZERO, index)
	reward_index += 1
	if _rng.randf() < Items.enemy_drop_chance(depth, source, "material"):
		var material := String(enemy.part_key)
		if material.is_empty():
			material = Items.material_drop(depth, _rng)
		if not material.is_empty():
			_drop({"category": "material", "id": material}, point, reward_index, Vector3.ZERO, index)
		reward_index += 1
	if _rng.randf() < Items.enemy_drop_chance(depth, source, "key") or (dungeon_floor.enemies.size() <= 1 and int(run.key_drops) == 0):
		run.key_drops += 1
		_drop({"category": "key"}, point, reward_index, Vector3.ZERO, index)
		reward_index += 1
	_drop_card_reward(id, source, point, reward_index, index)
	_check_clear_after_enemy(dungeon_floor, room, index, state)


func _check_clear_after_enemy(dungeon_floor: DungeonFloor, room: int, index: int, state: Dictionary) -> void:
	if room >= 0 and int(dungeon_floor.room_enemies.get(room, 0)) == 0:
		var trial := _trial_coffer(dungeon_floor, room)
		if (trial != null and state.ambush_triggered.has(str(room))
				and not trial.payload.opened and not _activate_ambush(room, "coffer", index)):
			hud.notify("The trial coffer is unsealed")
	if dungeon_floor.enemies.is_empty():
		_mark_cleared(index)
	_update_hud()


func _drop_card_reward(enemy_id: String, monster_rarity: String, point: Vector3, index: int, floor_index := -1) -> void:
	if not CardCatalog.DROP_CHANCES.has(monster_rarity):
		return
	var unavailable := {}
	for card_id in card_deck.owned:
		unavailable[card_id] = true
	for card_id in inventory.carried_card_ids():
		unavailable[card_id] = true
	var loot_tables: Array[Dictionary] = [run.loot]
	for floor_state: Dictionary in run.get("floor_states", {}).values():
		loot_tables.append(floor_state.get("loot", {}))
	for loot_table in loot_tables:
		for drop: Dictionary in loot_table.values():
			var item: Variant = drop.get("item")
			if item is Dictionary and CardItems.is_card(item):
				unavailable[String(item.card_id)] = true
			elif drop.get("category", "") == "card" and drop.has("card_id"):
				unavailable[String(drop.card_id)] = true
	var card_rng := RandomNumberGenerator.new()
	var reward_floor := floor_index if floor_index >= 0 else _dungeon_floor_index()
	card_rng.seed = hash([run.seed, reward_floor, enemy_id, "card"])
	var card_id := CardCatalog.roll_drop(int(run.level), monster_rarity, unavailable, card_rng)
	if not card_id.is_empty():
		var item := _physical_reward_card(card_id, reward_floor, str(run.next_loot))
		_drop({"category": "card", "item": item}, point, index, Vector3.ZERO, reward_floor)


func _physical_reward_card(card_id: String, reward_floor: int, ground_id: String) -> Dictionary:
	var item_id := "card_%s_%d_%s_%d" % [str(run.get("seed", 0)), reward_floor, ground_id, card_id.hash()]
	return CardItems.make(card_id, item_id)


func _mark_cleared(floor_index := -1) -> void:
	if bool(run.cleared):
		return
	var cleared_floors: Dictionary = run.get("cleared_floors", {})
	var index := floor_index if floor_index >= 0 else _dungeon_floor_index()
	cleared_floors[str(index)] = true
	run["cleared_floors"] = cleared_floors
	for required_floor in _dungeon_floor_count():
		if not cleared_floors.get(str(required_floor), false):
			hud.notify("Floor cleared · Search the remaining floors")
			return
	if _has_connected_floors() and _remaining_dungeon_enemies() > 0:
		return
	run.cleared = true
	lifetime.add("depths_cleared")
	for dungeon_floor: DungeonFloor in _dungeon_floors.values():
		for hazard: Node3D in dungeon_floor.hazards:
			if not hazard.has_meta("challenge_secret"):
				hazard.set_active(false)
	var depth := int(run.level)
	var previous_level := progression.level
	if progression.award_clear(depth) > 0:
		_update_progression(previous_level)
	unlocked = maxi(unlocked, depth + 1)
	completions += 1
	_restock()
	audio.cue("complete")
	hud.notify("Depth cleared · Merchant restocked · Deepest gate %02d" % unlocked)
	hub.set_dungeon_state(true, true)


func _restock() -> void:
	var offers := Items.roll_vendor(maxi(1, unlocked - 1), _rng, 7)
	for index in 3:
		var seal := Supplies.unveiling_scroll()
		seal.id = "seal_%d_%d" % [_rng.randi(), index]
		offers.append(seal)
	inventory.set_vendor_items(offers)


func _roll_enemy_gold(enemy_level: int, rarity: String) -> int:
	var bonus := float(maxi(1, enemy_level) - 1) * ENEMY_GOLD_PER_LEVEL
	bonus += float(ENEMY_GOLD_BY_RARITY.get(rarity, 0.0))
	return _roll_gold(1.0 + bonus, 2.0 + bonus, _rng)


func _roll_coffer_gold(depth: int, protected_reward: bool) -> int:
	var bonus := float(maxi(1, depth) - 1) * COFFER_GOLD_PER_DEPTH
	if protected_reward:
		bonus += 3.0
	var gold := _roll_gold(4.0 + bonus, 6.0 + bonus, _rng)
	return gold * 2 if player.effects.has("deep_pockets") else gold


func _roll_gold(minimum: float, maximum: float, rng: RandomNumberGenerator) -> int:
	# Round after applying Gold Find so it can raise the odds of an extra coin on small piles.
	var multiplier := 1.0 + float(player.stats.gold_find) * 0.01
	var oath_bonus := float(_blood_oath().get("gold", 1.0))
	return maxi(1, roundi(rng.randf_range(minimum, maximum) * multiplier * oath_bonus))


func _drop(data: Dictionary, base: Vector3, index: int, facing := Vector3.ZERO, floor_index := -1) -> void:
	var physical_floor := _floor_at(base, floor_index if floor_index >= 0 else _dungeon_floor_index())
	var contents: DungeonFloor = _dungeon_floors[physical_floor]
	var point := _loot_drop_point(contents, base, index, facing)
	if point.is_finite():
		_store_loot(data, point, physical_floor)
		match data.category:
			"gold":
				lifetime.add("gold_dropped", int(data.amount))
			"item":
				lifetime.add("items_dropped")


func _loot_drop_point(dungeon_floor: DungeonFloor, base: Vector3, index: int, facing: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	return LootPlacement.find(dungeon_floor.geometry, space, base, index, facing, dungeon_floor.loot.values())


func _store_loot(data: Dictionary, point: Vector3, floor_index: int) -> void:
	var id := str(run.next_loot)
	run.next_loot += 1
	var dungeon_floor := _dungeon_floors[floor_index]
	var local_point: Vector3 = dungeon_floor.geometry.to_local(point)
	data.id_on_ground = id
	data.kind = "loot"
	data.point = _coords(local_point)
	_floor_state(floor_index).loot[id] = data
	dungeon_floor.loot[id] = _make_prop(data, local_point, dungeon_floor.props)
	dungeon_floor.loot[id].animate_drop()


func _validate_saved_loot() -> void:
	for dungeon_floor: DungeonFloor in _dungeon_floors.values():
		for prop: Node3D in dungeon_floor.loot.values():
			var point := LootPlacement.find(dungeon_floor.geometry, null, prop.global_position, 0)
			if point.is_finite() and not point.is_equal_approx(prop.global_position):
				prop.global_position = point
				prop.payload.point = _coords(prop.position)


func _collect_nearby_gold() -> void:
	var reach_squared := GOLD_PICKUP_RADIUS * GOLD_PICKUP_RADIUS
	var position_at_feet: Vector3 = player.global_position
	var ray_height := Vector3.UP * 0.36
	var space := player.get_world_3d().direct_space_state
	var collected := 0
	for coin: Node3D in _loot.values():
		var data: Dictionary = coin.payload
		if data.category != "gold":
			continue
		var coin_point := coin.global_position
		var distance_squared := position_at_feet.distance_squared_to(coin_point)
		if distance_squared > reach_squared:
			continue
		if distance_squared > 0.0001:
			var ray := PhysicsRayQueryParameters3D.create(
				position_at_feet + ray_height, coin_point + ray_height, 1)
			if not space.intersect_ray(ray).is_empty():
				continue
		collected += int(data.amount)
		_remove_loot(coin)
	if collected > 0:
		inventory.grant_gold(collected)
		run.recap.gold = int(run.recap.gold) + collected
		lifetime.add("gold_collected", collected)
		audio.cue("loot")


func _pickup(prop: Node3D) -> void:
	var data: Dictionary = prop.payload
	var inventory_owner := _active_inventory()
	var added := true
	var picked_item: Dictionary
	if data.get("item") is Dictionary:
		picked_item = data.item
		added = inventory_owner.add_item(picked_item)
	else:
		match data.category:
			"material":
				picked_item = Supplies.material(String(data.id))
				added = inventory_owner.add_material(String(data.id), int(data.get("quantity", 1)))
			"key":
				picked_item = Supplies.treasure_key()
				added = inventory_owner.add_treasure_keys()
			"card":
				# Older active expeditions stored only the chosen card and their ground record ID.
				picked_item = _physical_reward_card(String(data.get("card_id", "")), _dungeon_floor_index(),
					String(data.get("id_on_ground", "")))
				if picked_item.is_empty():
					return
				added = inventory_owner.add_item(picked_item)
			_:
				return
	if not added:
		_feedback("Inventory is full", "error")
		return
	if data.has("route_key_source"):
		run.collected_route_keys[String(data.route_key_source)] = true
	if in_dungeon and not data.get("dropped_by_player", false):
		match data.category:
			"material": lifetime.add("materials_looted")
			"card": lifetime.add("cards_looted")
			"item":
				if not Supplies.is_supply(data.item):
					lifetime.add("items_looted")
	hud.notify("+ " + prop.text)
	audio.place_item(picked_item)
	if _training_inventory != null:
		prop.queue_free()
	else:
		_remove_loot(prop)
	_last_target = null
	_update_hud()


func _remove_loot(prop: Node3D) -> void:
	var id: String = prop.payload.id_on_ground
	run.loot.erase(id)
	_loot.erase(id)
	prop.queue_free()


func _coffer_guards(data: Dictionary) -> int:
	if data.get("guarded", false) or data.get("spawn_trigger", "") == "coffer":
		return int(_remaining_by_room.get(int(data.get("room", -1)), 0))
	return 0


func _trial_coffer(dungeon_floor: DungeonFloor, room: int) -> Node3D:
	for prop: Node3D in dungeon_floor.chests.values():
		if int(prop.payload.trial_waves) > 1 and int(prop.payload.room) == room:
			return prop
	return null


func _open_chest(prop: Node3D) -> void:
	var data: Dictionary = prop.payload
	if bool(data.get("opened", false)):
		return
	if (data.get("spawn_trigger", "") == "coffer" and not run.ambush_triggered.has(str(data.room))
			and _activate_ambush(int(data.room), "coffer")):
		return
	if _coffer_guards(data) > 0:
		_feedback("Defeat the reliquary guards first", "error")
		return
	var returned_key := false
	if bool(data.locked):
		returned_key = (int(data.trial_waves) < 2 and player.effects.has("tollkeepers_mercy")
			and not bool(run.get("tollkeepers_mercy_used", false)))
		# The refunded unit remains in its original pack cell or stack.
		var paid := inventory.treasure_key_count() > 0 if returned_key else inventory.consume_treasure_key()
		if not paid:
			_feedback("You need a treasure key", "error")
			return
	run.opened[String(data.id)] = true
	if returned_key:
		run["tollkeepers_mercy_used"] = true
	lifetime.add("coffers_opened")
	if int(data.trial_waves) > 1:
		lifetime.add("trials_claimed")
	prop.opened()
	var facing := player.global_position - prop.global_position
	facing.y = 0.0
	var point := prop.global_position + Vector3.UP * 0.035
	var depth := int(run.level)
	var protected_reward := bool(data.locked) or bool(data.get("guarded", false))
	var hidden_cache := bool(data.get("secret_cache", false))
	var plain_cache := bool(data.get("side_cache", false)) and not hidden_cache
	var quality := "locked_chest" if protected_reward else "chest"
	if hidden_cache:
		quality = "secret_cache"
	elif plain_cache:
		quality = "side_cache"
	var loot_bonus := float(player.stats.loot_rarity)
	var gear := not plain_cache or _rng.randf() < Items.SIDE_CACHE_GEAR_CHANCE
	if gear:
		_drop({"category": "item", "item": Items.roll_item(depth, quality, _rng, loot_bonus)}, point, 0, facing)
	var gold := _roll_coffer_gold(depth, protected_reward)
	_drop({"category": "gold", "amount": gold}, point, 1, facing)
	if protected_reward and depth >= Items.PROTECTED_COFFER_BONUS_DEPTH and _rng.randf() < Items.PROTECTED_COFFER_BONUS_GEAR_CHANCE:
		_drop({"category": "item", "item": Items.roll_item(depth, quality, _rng, loot_bonus)}, point, 2, facing)
	if protected_reward or hidden_cache or not gear:
		var material := Items.material_drop(depth, _rng)
		if not material.is_empty():
			_drop({"category": "material", "id": material}, point, 3, facing)
	audio.cue("chest")
	var opened_notice := "Reliquary unsealed" if data.get("guarded", false) else "Coffer opened"
	hud.notify(opened_notice + " · Treasure Key returned" if returned_key else opened_notice)
	_update_hud()


func _depth_name() -> String:
	if int(run.get("generation_version", 1)) == 1:
		return "The Undervault"
	return DEPTH_NAMES.get(dungeon.depth_theme, "The Undervault")


func _update_hud() -> void:
	hud.set_recap_available(not run.is_empty() and not is_instance_valid(training_ground))
	hud.set_character_tools(_session_mode == SessionMode.CHARACTER)
	var depth_name := _depth_name() if in_dungeon else ""
	if is_instance_valid(training_ground):
		hud.set_training_zone(_remaining_cards().size())
	else:
		hud.set_zone(in_dungeon, int(run.get("level", 0)), _remaining_dungeon_enemies(), unlocked,
			bool(run.get("cleared", false)), depth_name, "", _dungeon_floor_index(),
			_dungeon_floor_count(), _remaining_cards().size() if in_dungeon else 0)
	hud.set_vitals(player.life, player.stats.max_health, player.mana, player.stats.max_mana, player.ward, inventory.gold)


func _update_map() -> void:
	var center: Vector2i = dungeon.tile_at(player.global_position)
	var exact := dungeon.to_local(player.global_position)
	var tile_position := Vector2(exact.x, exact.z) / Dungeon.CELL_SIZE
	_map_fog.observe(dungeon.map_cells, _concealed_tiles, tile_position)
	_map_fog.observe_landmarks(_map_landmark_candidates(), dungeon.map_cells, _concealed_tiles, tile_position)
	var visible_cells := preload("res://ui/dungeon_map_visibility.gd").survey(
		dungeon.map_cells, _concealed_tiles, tile_position)
	_explored.merge(visible_cells)
	for tile: Vector2i in _concealed_tiles:
		_explored.erase(tile)
	if not hud.is_map_visible():
		return
	var marks: Array[Vector2i] = []
	var local_enemies := _enemies_on_floor(_dungeon_floor_index())
	var final_enemies := local_enemies.size() <= 3 or _remaining_dungeon_enemies() <= ExpeditionRules.straggler_count
	for enemy: Enemy in local_enemies:
		var target: Vector2i = dungeon.tile_at(enemy.global_position)
		if not _concealed_tiles.has(target) and (final_enemies or _explored.has(target)):
			marks.append(target)
	var trail: Array[Vector2i] = []
	if not marks.is_empty() and final_enemies:
		trail = _route_to_remaining_enemy(center, local_enemies)
	var stair_marks := {}
	for direction: int in dungeon.stair_tiles:
		var tile: Vector2i = dungeon.stair_tiles[direction]
		if _explored.has(tile):
			stair_marks[tile] = dungeon.stair_slope(direction)
	var caption := _depth_name()
	if _dungeon_floor_count() > 1:
		caption += " · Floor %d/%d" % [_dungeon_floor_index() + 1, _dungeon_floor_count()]
	hud.set_map(_map_fog, marks, caption, trail, stair_marks, player, dungeon, Dungeon.CELL_SIZE)


func _map_landmark_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for prop: Node3D in _props.get_children():
		var marker_type := ""
		var data: Dictionary = prop.payload
		match data.kind:
			"chest":
				if bool(data.opened):
					continue
				if int(data.trial_waves) > 1:
					marker_type = "trial_coffer"
				elif bool(data.locked) or not String(data.challenge_type).is_empty():
					marker_type = "locked_coffer"
			"route_gate", "blood_altar":
				if prop.pick_available():
					marker_type = data.kind
		if marker_type.is_empty():
			continue
		var position_on_floor: Vector3 = dungeon.to_local(prop.global_position)
		candidates.append({"id": "%s_%s" % [marker_type, data.get("id", "altar")],
			"kind": marker_type, "at": Vector2(position_on_floor.x, position_on_floor.z) / Dungeon.CELL_SIZE})
	return candidates


func _route_to_remaining_enemy(center: Vector2i, enemies: Array[Enemy]) -> Array[Vector2i]:
	var nearest: Array[Vector2i] = []
	var shortest := INF
	for enemy: Enemy in enemies:
		if _concealed_tiles.has(dungeon.tile_at(enemy.global_position)):
			continue
		var route: PackedVector3Array = dungeon.route(player.global_position, enemy.global_position)
		if route.is_empty():
			continue
		var points: Array[Vector2i] = [center]
		var length := 0.0
		var previous: Vector3 = player.global_position
		for point in route:
			length += previous.distance_to(point)
			previous = point
			var tile: Vector2i = dungeon.tile_at(point)
			if tile != points.back():
				points.append(tile)
		if length < shortest:
			shortest = length
			nearest = points
	return nearest


func _feedback(message: String, event: String) -> void:
	if not message.is_empty():
		hud.notify(message)
	if event == "swing" or event == "swing_weapon":
		audio.swing(player.weapon_audio_type(), player.weapon_audio_heft())
	elif not event.is_empty():
		audio.cue(event)
	if event == "player_hit":
		_record_combat_pressure(8.0)
	elif event == "block":
		_record_combat_pressure(2.0)


func _record_combat_pressure(amount: float) -> void:
	if is_instance_valid(_training_pressure):
		_training_pressure.record_pressure(amount)
	elif in_dungeon and is_instance_valid(_expedition_pressure):
		_expedition_pressure.record_pressure(amount)


func _struck(_enemy: Node3D, amount: float, _critical: bool) -> void:
	if amount > 0.0:
		audio.cue(&"hit", player.weapon_audio_heft())


func _schedule_death() -> void:
	if not _death_pending:
		_death_pending = true
		call_deferred("_handle_death")


func _handle_death() -> void:
	if is_instance_valid(training_ground):
		_reset_training_combat()
		player.place_at(training_ground.spawn_position, training_ground.spawn_yaw)
		player.restore_full()
		_death_pending = false
		audio.cue("death")
		hud.set_prompt("")
		hud.notify("Training Ground reset")
		_update_hud()
		return
	lifetime.death(_last_damage_actor)
	_close_dungeon()
	player.restore_full()
	_death_pending = false
	audio.cue("death")
	hud.notify("You fell · Run ended · Carried loot kept")
	_update_hud()


func _on_inventory_changed() -> void:
	if _updating:
		return
	if not _modal and not in_dungeon:
		_update_hud()
	var equipment := _active_inventory().equipment
	if equipment != _cached_equipment:
		player.update_equipment(equipment)
		_cached_equipment = equipment.duplicate(true)
		if _modal and not inventory_ui.is_open():
			audio.cue("equip")


func _on_inventory_transaction(event: StringName) -> void:
	if event != &"trade" or not inventory_ui.is_open():
		audio.cue(event)


func _record_economy(kind: StringName, amount: int) -> void:
	if _session_mode == SessionMode.CHARACTER and not is_instance_valid(training_ground):
		lifetime.add(String(kind), amount)


func _on_attributes_changed() -> void:
	player.refresh_character_progression()
	_update_hud()


func _update_progression(previous_level: int) -> void:
	inventory_ui.refresh_progression()
	if progression.level > previous_level:
		player.refresh_character_progression(true)
		_refresh_enemy_levels()
		hud.notify("Level %d · %d unspent attribute points" % [progression.level, progression.points_available()])


func _refresh_enemy_levels() -> void:
	for actor in get_tree().get_nodes_in_group("enemies"):
		if actor is Enemy:
			actor.refresh_level_label()


func _coords(point: Vector3) -> Array:
	return [point.x, point.y, point.z]


func _vector(values: Array, fallback: Vector3) -> Vector3:
	if values.size() != 3:
		return fallback
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _save_now() -> Error:
	if not save_enabled or _updating or _session_mode != SessionMode.CHARACTER:
		return OK
	if not run.is_empty() and in_dungeon:
		_remember_active_floor()
		if _broker_floor >= 0:
			_floor_state(_broker_floor).broker_catalog = inventory.vendor_catalog_snapshot()
	var retained_run := run.duplicate(true)
	if not retained_run.is_empty():
		var now := Time.get_unix_time_from_system()
		var deadline := _instance_deadline()
		if deadline > 0.0 and now >= deadline:
			retained_run.clear()
		else:
			retained_run["return_point"] = []
			retained_run["return_yaw"] = 0.0
			retained_run["return_pitch"] = 0.0
			retained_run["card_buffs"] = (_training_campaign_card_buffs.duplicate() if _training_card_deck != null
				else player.card_effects.snapshot())
			if deadline <= 0.0:
				if bool(retained_run.cleared):
					retained_run["close_deadline"] = now + ExpeditionRules.cleared_grace_seconds
				else:
					retained_run["retained_until"] = now + ExpeditionRules.logout_grace_seconds
	var practice := is_instance_valid(training_ground)
	var vitals := _training_campaign_vitals if practice else Vector3(player.life, player.mana, player.ward)
	var stamina: float = _training_campaign_stamina if practice else player.stamina
	var state := {"character_name": _character_name, "inventory": inventory.save_data(), "run": retained_run,
		"unlocked": unlocked, "completions": completions, "rng_state": str(_rng.state),
		"life": vitals.x, "mana": vitals.y, "ward": vitals.z, "stamina": stamina,
		"bestiary": bestiary_discoveries.keys(), "card_deck": card_deck.snapshot(),
		"progression": progression.snapshot(), "lifetime": lifetime.snapshot()}
	return SaveStore.write_game(state, CharacterSlots.directory_for(save_directory, _character_slot))


func _remember_active_floor() -> void:
	_store_floor_exploration()
	for index: int in _dungeon_floors:
		var dungeon_floor := _dungeon_floors[index]
		var mobs := {}
		for id in dungeon_floor.enemies:
			var enemy: Enemy = dungeon_floor.enemies[id]
			var state := {"point": _coords(enemy.position), "life": enemy.health, "max_life": enemy.max_health}
			if enemy.convergence_floor >= 0:
				state["convergence_floor"] = enemy.convergence_floor
			var metamorphosis: Dictionary = enemy.save_metamorphosis()
			if not metamorphosis.is_empty():
				state["metamorphosis"] = metamorphosis
			var behavior: Dictionary = enemy.save_checkpoint_behavior()
			if not behavior.is_empty():
				state["behavior"] = behavior
			mobs[id] = state
		_floor_state(index).mob_states = mobs


func _store_floor_exploration() -> void:
	run.explored = []
	for point: Vector2i in _explored:
		run.explored.append([point.x, point.y])
	run.map_fog = _map_fog.snapshot()
	run.map_landmarks = _map_fog.landmark_snapshot()


func _restore_floor_exploration() -> void:
	_explored.clear()
	_map_fog.restore(run.get("map_fog", []))
	_map_fog.restore_landmarks(run.get("map_landmarks", []))
	for point in run.get("explored", []):
		if point is Array and point.size() == 2:
			_explored[Vector2i(int(point[0]), int(point[1]))] = true


func _read_bestiary(saved: Dictionary) -> Dictionary[int, bool]:
	var known: Dictionary[int, bool] = {}
	var discoveries: Variant = saved.get("bestiary", [])
	if discoveries is Array:
		for value: Variant in discoveries:
			if value is int or value is float:
				var id := int(value)
				if id >= 0 and id < BestiaryData.entry_count() and float(value) == float(id):
					known[id] = true
	return known


func _restore(saved: Dictionary) -> void:
	bestiary_discoveries = _read_bestiary(saved)
	unlocked = maxi(1, int(saved.get("unlocked", 1)))
	completions = maxi(0, int(saved.get("completions", 0)))
	var progression_data: Variant = saved.get("progression", {})
	progression.restore(progression_data if progression_data is Dictionary else {}, unlocked - 1)
	if saved.has("rng_state") and String(saved.rng_state).is_valid_int():
		_rng.state = int(saved.rng_state)
	inventory.restore_data(saved.get("inventory", {}))
	card_deck.restore(saved.get("card_deck", {}))
	run = saved.get("run", {}).duplicate(true)
	if run.is_empty():
		inventory.clear_expedition_keys()
		return
	var deadline := _instance_deadline()
	if deadline > 0.0 and Time.get_unix_time_from_system() >= deadline:
		run.clear()
		inventory.clear_expedition_keys()
		return
	run.merge(FLOOR_STATE_DEFAULTS.duplicate(true))
	run.merge({"floor_states": {}, "cleared_floors": {}, "key_drops": 0, "next_loot": 0})
	if not run.get("recap") is Dictionary:
		run["recap"] = {}
	run.recap.merge(RECAP_DEFAULTS)
	for parked: Dictionary in run.floor_states.values():
		parked.merge(FLOOR_STATE_DEFAULTS.duplicate(true))
	run["card_loadout"] = CardDeck.normalize_loadout(run.get("card_loadout", card_deck.equipped), card_deck.owned)
	if not run.get("used_cards") is Dictionary:
		run["used_cards"] = {}
	run["return_point"] = []
	run["return_yaw"] = 0.0
	run["return_pitch"] = 0.0
	if _dungeon_floor_index() > 0:
		_select_floor_state(0)
	else:
		_restore_floor_exploration()
	_build_dungeon()


func _open_settings() -> void:
	title_screen.close()
	var embedded := Engine.is_embedded_in_editor()
	hud.open_settings(_fullscreen and not embedded, embedded, _session_mode == SessionMode.CHARACTER)


func _open_lifetime_statistics() -> void:
	player.flush_combat_log()
	hud.open_lifetime_statistics(_character_name, lifetime.groups())


func _open_achievements() -> void:
	player.flush_combat_log()
	hud.open_achievements(lifetime.achievements(), lifetime.points())


func _active_inventory() -> Inventory:
	return _training_inventory if _training_inventory != null else inventory


func _close_settings() -> void:
	if _session_mode == SessionMode.TITLE:
		_show_title()
	else:
		hud.open_pause()


func _open_bestiary() -> void:
	hud.hide_menu()
	bestiary.present(bestiary_discoveries, is_instance_valid(training_ground))


func _close_bestiary() -> void:
	bestiary.close()
	_open_settings()


func _record_combat_event(event: Dictionary) -> void:
	if _session_mode == SessionMode.TITLE:
		return
	if in_dungeon and event.kind == &"damage" and run.has("recap"):
		var amount := maxi(0, int(event.get("amount", 0)))
		if event.target == "Player":
			run.recap.taken = int(run.recap.taken) + amount
			lifetime.add("damage_taken", amount)
			_last_damage_actor = String(event.get("actor", ""))
		elif event.side == &"player":
			run.recap.dealt = int(run.recap.dealt) + amount
			lifetime.add("damage_dealt", amount)
	var entry := event.duplicate()
	entry["time"] = _combat_clock
	if _combat_events.size() >= COMBAT_LOG_LIMIT:
		_combat_events.pop_front()
	_combat_events.append(entry)


func _open_combat_log() -> void:
	player.flush_combat_log()
	hud.hide_menu()
	combat_log.present(_combat_events)


func _open_expedition_recap() -> void:
	if run.is_empty() or is_instance_valid(training_ground):
		return
	player.flush_combat_log()
	var chest_count := 0
	var chests_opened := 0
	var secret_count := 0
	var secrets_opened := 0
	var gates_opened := 0
	var gate_count := 0
	for index: int in _dungeon_floors:
		var dungeon_floor := _dungeon_floors[index]
		var state := _floor_state(index)
		chest_count += dungeon_floor.geometry.chests.size()
		chests_opened += state.opened.size()
		secret_count += dungeon_floor.geometry.secret_passages.size()
		secrets_opened += state.secrets_opened.size()
		gate_count += dungeon_floor.geometry.route_gates.size()
		gates_opened += state.opened_route_gates.size()
	var recap: Dictionary = run.recap
	var time := int(recap.time)
	var rows := [
		["Damage dealt", str(recap.dealt)], ["Damage taken", str(recap.taken)],
		["Enemies slain", str(recap.kills)], ["Magic and rare enemies slain", str(recap.elite_kills)],
		["Coffers opened", "%d / %d" % [chests_opened, chest_count]],
		["Secret passages opened", "%d / %d" % [secrets_opened, secret_count]],
		["Gold collected", str(recap.gold)], ["Cards played", str(run.used_cards.size())],
		["Time inside", "%d:%02d" % [floori(float(time) / 60.0), time % 60]],
	]
	if gate_count > 0:
		rows.insert(6, ["Route gates opened", "%d / %d" % [gates_opened, gate_count]])
	hud.open_expedition_recap(_depth_name(), int(run.level), bool(run.cleared), rows)


func _close_combat_log() -> void:
	combat_log.close()
	hud.open_pause()


func _set_fullscreen(enabled: bool) -> void:
	_apply_fullscreen(enabled)
	if save_enabled and WindowPreferences.save_fullscreen(preferences_path, enabled) != OK:
		hud.notify("Could not save the fullscreen setting")


func _apply_fullscreen(enabled: bool) -> void:
	_fullscreen = enabled
	var window := get_window()
	var currently_fullscreen := window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	if not Engine.is_embedded_in_editor() and DisplayServer.get_name() != "headless" and currently_fullscreen != enabled:
		if enabled:
			_windowed_mode = Window.MODE_MAXIMIZED if window.mode == Window.MODE_MAXIMIZED else Window.MODE_WINDOWED
			window.mode = Window.MODE_FULLSCREEN
		else:
			window.mode = _windowed_mode


func _save_and_quit() -> void:
	if _save_now() != OK:
		_suspend()
		hud.open_save_error()
		return
	_close_card_hand(false)
	if get_tree().reload_current_scene() != OK:
		hud.notify("Could not return to character selection")


func _quit_without_save() -> void:
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _save_now() == OK:
			_quit_without_save()
		else:
			_suspend()
			hud.open_save_error()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and _session_mode != SessionMode.TITLE and not _modal:
		_suspend()
		hud.open_pause()


func _exit_tree() -> void:
	var services := GameServices.from_context(self)
	if services != null and is_instance_valid(audio):
		services.unregister_audio(audio)
	_close_card_hand(false)
	if is_instance_valid(_dungeon_root) and _dungeon_root.get_parent() == null:
		_dungeon_root.free()
	if is_instance_valid(hub) and hub.get_parent() == null:
		hub.free()


func _remaining_dungeon_enemies() -> int:
	var count := 0
	for dungeon_floor: DungeonFloor in _dungeon_floors.values():
		count += dungeon_floor.enemies.size()
	return count


func _enemies_on_floor(index: int) -> Array[Enemy]:
	var present: Array[Enemy] = []
	for origin_index: int in _dungeon_floors:
		var origin: DungeonFloor = _dungeon_floors[origin_index]
		for enemy: Enemy in origin.enemies.values():
			if _floor_at(enemy.global_position, origin_index) == index:
				present.append(enemy)
	return present


func _restore_convergence_routes() -> void:
	# Floor-owned enemies retain their original local transform and death signal binding.
	for origin_index: int in _dungeon_floors:
		var origin: DungeonFloor = _dungeon_floors[origin_index]
		var states: Dictionary = _floor_state(origin_index).mob_states
		for id: String in origin.enemies:
			var record: Dictionary = states.get(id, {})
			var destination := int(record.get("convergence_floor", -1))
			if not _dungeon_floors.has(destination):
				continue
			var enemy: Enemy = origin.enemies[id]
			var geometry: Dungeon = _dungeon_floors[destination].geometry
			enemy.set_convergence_route(destination, geometry.navigation_route)


func _tick_enemy_convergence(delta: float) -> void:
	var index := _dungeon_floor_index()
	var count := _remaining_dungeon_enemies()
	if count == 0 or count > ExpeditionRules.straggler_count or run.cleared \
			or _dungeon_floors.size() < _dungeon_floor_count() \
			or not DungeonEnemyConvergence.player_has_footing(dungeon, player):
		_convergence_floor = -1
		return
	if _convergence_floor != index:
		_convergence_floor = index
		_convergence_wait = ExpeditionRules.straggler_delay_seconds
	_convergence_wait -= delta
	if _convergence_wait > 0.0:
		return
	_convergence_wait = ExpeditionRules.straggler_delay_seconds
	var dungeon_floor: DungeonFloor = _dungeon_floors[index]
	var distant: Array[Enemy] = []
	var reserved: Array[Vector3] = []
	for origin_index: int in _dungeon_floors:
		var origin: DungeonFloor = _dungeon_floors[origin_index]
		for enemy: Enemy in origin.enemies.values():
			if _floor_at(enemy.global_position, origin_index) == index \
					and DungeonEnemyConvergence.can_stay(dungeon, player, enemy):
				reserved.append(enemy.global_position)
			else:
				distant.append(enemy)
	if distant.is_empty():
		return
	for coffer: Node3D in dungeon_floor.chests.values():
		reserved.append(coffer.global_position)
	for hazard: Node3D in dungeon_floor.hazards:
		reserved.append(hazard.global_position)
	for prop: Node3D in [dungeon_floor.portal, dungeon_floor.blood_altar]:
		if is_instance_valid(prop):
			reserved.append(prop.global_position)
	var points := DungeonEnemyConvergence.candidate_points(dungeon, player, dungeon_floor.concealed, reserved)
	var placed: Array[Vector3] = []
	for enemy: Enemy in distant:
		var point := DungeonEnemyConvergence.take_site(enemy, points, placed)
		if point.is_finite():
			enemy.relocate_for_convergence(point, index, dungeon.navigation_route)
	if not placed.is_empty():
		hud.notify("The remaining enemies draw near")
		_update_map()
