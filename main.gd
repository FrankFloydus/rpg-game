extends Node3D

const TrainingGround = preload("res://world/training_ground.tscn")
const TrainingRecoveryWell = preload("res://world/props/training_recovery_well.gd")
const TrainingAbilityTrace = preload("res://combat/effects/training_ability_trace.gd")
const TrainingWeaponTrace = preload("res://combat/effects/training_weapon_trace.gd")
const Enemy = preload("res://combat/enemies/enemy.gd")
const EnemyCatalog = preload("res://combat/enemies/enemy_catalog.gd")
const EncounterPressure = preload("res://ai/encounter_pressure.gd")
const Prop = preload("res://world/world_prop.gd")
const Items = preload("res://systems/items.gd")
const Inventory = preload("res://systems/inventory.gd")
const Progression = preload("res://systems/character_progression.gd")
const WindowPreferences = preload("res://systems/window_preferences.gd")
const DESTROY_ITEM_DIALOG := preload("res://ui/destroy_item_dialog.tscn")
const BestiaryData = preload("res://data/bestiary.gd")
const SaveStore = preload("res://systems/save_store.gd")
const CharacterSlots = preload("res://systems/character_slots.gd")
const CardCatalog = preload("res://data/card_catalog.gd")
const CardDeck = preload("res://systems/card_deck.gd")
const CardCast = preload("res://combat/cards/card_cast.gd")
const CARD_WORLD_SPEED := 0.075
const Supplies := preload("res://systems/pack_supplies.gd")
const CharacterStatistics := preload("res://systems/character_statistics.gd")
const AudioService := preload("res://systems/game_audio.gd")
const GameServices := preload("res://systems/game_services.gd")

enum SessionMode { TITLE, CHARACTER, PRACTICE }

const COMBAT_LOG_LIMIT := 1000
const TRAINING_SPAWN_CLEARANCE := 2.0

const WALK_KEYS := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
	"sprint": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_E,
	"inventory": KEY_I, "pause": KEY_ESCAPE, "training_roster": KEY_F1, "cards": KEY_Q}

@export_group("Player Abilities")
## Ability used by a quick left-mouse tap. Leave empty for the equipped weapon's light attack.
@export var primary_ability: AbilityDefinition
## Ability released automatically when the left-mouse hold finishes charging.
## Leave empty for the equipped weapon's charged attack.
@export var charged_ability: AbilityDefinition

var player: CharacterBody3D
var hub: Node3D
var training_ground: Node3D
var inventory: Inventory
var lifetime := CharacterStatistics.new()
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
var unlocked := 1
var completions := 0
var save_enabled := true
var save_directory := SaveStore.SAVE_DIRECTORY
var preferences_path := WindowPreferences.PREFERENCES_PATH

var _rng := RandomNumberGenerator.new()
var _world: Node3D
var _modal := false
var _changing := false
var _interact_pending := false
var _updating := true
var _death_pending := false
var _hud_clock := 0.0
var _last_target: Node3D
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
	_set_combat_location(false)
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
	training_roster.melee_contact_preset_changed.connect(_set_training_melee_contact_preset)
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
	hud.statistics_requested.connect(_open_lifetime_statistics)
	hud.achievements_requested.connect(_open_achievements)
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
	if start_in_training:
		_enter_training_ground()
	else:
		player.place_at(hub.spawn_position)
		audio.set_zone(&"hub")
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
	if event.is_action_pressed("interact"):
		_interact_pending = true


func _logical_menu_key_pressed(event: InputEvent, key: Key) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != key:
		return false
	# Some Windows input providers give logical shortcuts an absent or Pause scancode.
	return event.physical_keycode == 0 or event.physical_keycode == KEY_PAUSE


func _physics_process(delta: float) -> void:
	if not is_instance_valid(hud):
		return
	if not _carried_drop.is_empty():
		_drop_carried_item()
	if _modal or _changing or _death_pending:
		return
	if not _pending_training_weapon.is_empty():
		_drop_training_weapon()
	hud.set_stamina(player.stamina, player.max_stamina(), player.guard_is_held(),
		player.is_blocking(), player.attack_charge_fraction())
	if is_instance_valid(training_ground):
		_combat_clock += delta
		player.card_effects.advance(delta)
		if not _queued_card.is_empty():
			var card_id := _queued_card
			_queued_card = ""
			if not player.is_stunned():
				_training_used_cards[card_id] = true
				var card: Dictionary = CardCatalog.CARDS[card_id]
				CardCast.play(card_id, card, player, _training_actors)
				var sound := card.get("play_sound") as HearthSoundCue
				if sound == null:
					audio.cue(CardCatalog.default_use_sound(card))
				else:
					audio.play_sound(sound)
				hud.notify(card.name)
	if _card_hand_open:
		player._tick_ailments(delta)
		return
	_hud_clock -= delta
	if _hud_clock <= 0.0 or _interact_pending:
		_hud_clock = 0.085
		_update_hud()
		_update_interactions()
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
		_set_world_target(_pick_prop(origin, direction,
			_training_props.get_children() + training_ground.recovery_wells))
		if is_instance_valid(_last_target):
			hud.set_prompt("E   " + _last_target.text, _last_target.tint)
		else:
			hud.set_prompt("")
		return
	_set_world_target(null)
	_last_hub_target = hub.active_interaction(origin, direction, 4.0)
	var label: String = {"vendor": "Trade with the Merchant", "blacksmith": "Speak to the Blacksmith",
		"training_portal": "Enter Training Ground",
		"stash": "Open Stash"}.get(_last_hub_target, "")
	hud.set_prompt("E   " + label if not label.is_empty() else "")


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
		elif _last_target is TrainingRecoveryWell:
			if _last_target.restores_mana:
				player.mana = player.stats.max_mana
			else:
				player.heal(player.stats.max_health)
			hud.notify(_last_target.resource_label() + " refilled")
			_update_hud()
		elif is_instance_valid(_last_target):
			_pickup(_last_target)
		return
	match _last_hub_target:
		"vendor":
			_open_inventory("vendor")
		"blacksmith":
			_open_inventory("smith")
		"stash":
			_open_inventory("stash")
		"training_portal":
			_enter_training_ground()


func _suspend() -> void:
	_close_card_hand(false)
	_modal = true
	_interact_pending = false
	player.gameplay_enabled = false
	player.velocity = Vector3.ZERO
	_set_world_target(null)
	hud.set_gameplay(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_encounters_enabled(false)


func _resume() -> void:
	_modal = false
	player.gameplay_enabled = true
	hud.set_gameplay(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_encounters_enabled(true)


func _set_encounters_enabled(enabled: bool) -> void:
	var mode := Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_training_actors):
		_training_actors.process_mode = mode


func _enter_training_ground() -> void:
	if _changing or is_instance_valid(training_ground):
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
	training_roster.reset_melee_contact_preset()
	_set_combat_location(true, true)
	player.place_at(training_ground.spawn_position, training_ground.spawn_yaw)
	player.restore_full()
	audio.set_zone(&"training")
	audio.cue("portal")
	hud.set_prompt("")
	_update_hud()
	_changing = false


func _leave_training_ground() -> void:
	if _session_mode == SessionMode.PRACTICE:
		_set_combat_location(false)
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
	_set_combat_location(false)
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
	_training_pressure = EncounterPressure.new()
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


func _set_training_melee_contact_preset(stops_on_static_world: bool, uses_refuge_sweep: bool) -> void:
	if is_instance_valid(training_ground):
		_set_combat_location(true, stops_on_static_world, uses_refuge_sweep)


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


func _close_inventory_menu() -> void:
	_resume()


func _can_edit_cards() -> bool:
	return (_session_mode != SessionMode.TITLE and not is_instance_valid(training_ground)
		and is_instance_valid(hub) and hub.is_inside_tree())


func _request_inventory_disposal(source: String, id: StringName) -> void:
	var inventory_owner := _active_inventory()
	var item := inventory_owner.get_item(id)
	if item.is_empty() or source not in ["equipment", "bag"]:
		return
	if is_instance_valid(training_ground):
		if _carried_drop.is_empty():
			_carried_drop = {"owner": inventory_owner, "source": source, "id": id}
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
	if inventory_owner != _active_inventory() or not is_instance_valid(training_ground):
		return
	var direction: Vector3 = -player.global_basis.z
	var point: Vector3 = training_ground.weapon_drop_point(player.global_position, direction, _training_props.get_children())
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
	var prop := _make_prop(data, _training_props.to_local(point), _training_props)
	prop.animate_drop()
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
	return _training_card_deck.equipped if _training_card_deck != null else []


func _remaining_cards() -> Array[String]:
	var remaining: Array[String] = []
	for id: String in _active_card_loadout():
		if not id.is_empty() and not _training_used_cards.has(id) and CardCatalog.CARDS.has(id):
			remaining.append(id)
	return remaining


func _open_card_screen() -> void:
	if _session_mode == SessionMode.TITLE or player.is_stunned():
		return
	if _training_card_deck == null:
		_suspend()
		_card_editor_open = true
		card_screen.show_loadout(card_deck.owned, card_deck.equipped)
		return
	if not _queued_card.is_empty():
		return
	var cards := _remaining_cards()
	if cards.is_empty():
		var equipped := _active_card_loadout().any(func(id: String) -> bool: return not id.is_empty())
		hud.notify("All training cards are spent until the arena resets" if equipped else "Equip cards in F1 → Cards")
		return
	_card_original_speed = Engine.time_scale
	Engine.time_scale *= CARD_WORLD_SPEED
	_card_hand_open = true
	_interact_pending = false
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


func _legate_rarity(index: int, rng: RandomNumberGenerator) -> String:
	if index == 0:
		return "rare"
	return "magic" if rng.randf() < 0.42 else "normal"


func _set_combat_location(enabled: bool, stops_on_static_world := false, uses_refuge_sweep := false) -> void:
	player.melee_stops_on_static_world = stops_on_static_world
	player.melee_uses_refuge_sweep = uses_refuge_sweep
	player.combat_enabled = enabled


func _make_prop(data: Dictionary, point: Vector3, container: Node3D) -> Node3D:
	var prop := Prop.new()
	prop.position = point
	prop.setup(data)
	container.add_child(prop)
	return prop


func _restock() -> void:
	var offers := Items.roll_vendor(maxi(1, unlocked - 1), _rng, 7)
	for index in 3:
		var seal := Supplies.unveiling_scroll()
		seal.id = "seal_%d_%d" % [_rng.randi(), index]
		offers.append(seal)
	inventory.set_vendor_items(offers)


func _pickup(prop: Node3D) -> void:
	if prop.is_queued_for_deletion():
		return
	var data: Dictionary = prop.payload
	var inventory_owner := _active_inventory()
	var added := true
	var picked_item: Dictionary
	if data.get("item") is Dictionary:
		picked_item = data.item
		added = inventory_owner.add_item(picked_item)
	elif data.category == "material":
		picked_item = Supplies.material(String(data.id))
		added = inventory_owner.add_material(String(data.id), int(data.get("quantity", 1)))
	else:
		return
	if not added:
		_feedback("Inventory is full", "error")
		return
	hud.notify("+ " + prop.text)
	audio.place_item(picked_item)
	prop.queue_free()
	_last_target = null
	_update_hud()


func _update_hud() -> void:
	hud.set_character_tools(_session_mode == SessionMode.CHARACTER)
	if is_instance_valid(training_ground):
		hud.set_training_zone(_remaining_cards().size())
	else:
		hud.set_hub_zone()
	hud.set_vitals(player.life, player.stats.max_health, player.mana, player.stats.max_mana, player.ward)


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
	lifetime.death("")
	player.restore_full()
	_death_pending = false
	audio.cue("death")
	hud.notify("You fell · Returned to Cinderhold")
	_update_hud()


func _on_inventory_changed() -> void:
	if _updating:
		return
	if not _modal:
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


func _refresh_enemy_levels() -> void:
	for actor in get_tree().get_nodes_in_group("enemies"):
		if actor is Enemy:
			actor.refresh_level_label()


func _save_now() -> Error:
	if not save_enabled or _updating or _session_mode != SessionMode.CHARACTER:
		return OK
	var practice := is_instance_valid(training_ground)
	var vitals := _training_campaign_vitals if practice else Vector3(player.life, player.mana, player.ward)
	var stamina: float = _training_campaign_stamina if practice else player.stamina
	var state := {"character_name": _character_name, "inventory": inventory.save_data(),
		"unlocked": unlocked, "completions": completions, "rng_state": str(_rng.state),
		"life": vitals.x, "mana": vitals.y, "ward": vitals.z, "stamina": stamina,
		"bestiary": bestiary_discoveries.keys(), "card_deck": card_deck.snapshot(),
		"progression": progression.snapshot(), "lifetime": lifetime.snapshot()}
	return SaveStore.write_game(state, CharacterSlots.directory_for(save_directory, _character_slot))


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
	inventory.clear_expedition_keys()


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
	var entry := event.duplicate()
	entry["time"] = _combat_clock
	if _combat_events.size() >= COMBAT_LOG_LIMIT:
		_combat_events.pop_front()
	_combat_events.append(entry)


func _open_combat_log() -> void:
	player.flush_combat_log()
	hud.hide_menu()
	combat_log.present(_combat_events)


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
	if is_instance_valid(hub) and hub.get_parent() == null:
		hub.free()
