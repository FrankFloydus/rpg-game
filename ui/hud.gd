extends Control

signal level_selected(level: int)
signal blood_oath_selected(id: String)
signal recap_requested
signal statistics_requested
signal achievements_requested
signal leave_requested
signal resume_requested
signal quit_requested
signal settings_requested
signal settings_back_requested
signal bestiary_requested
signal combat_log_requested
signal cards_requested
signal fullscreen_changed(enabled: bool)

const DungeonMap := preload("res://ui/dungeon_map.gd")
const MenuFrame := preload("res://ui/menu_frame.gd")
const EffectBadge := preload("res://ui/status_effect_badge.gd")
const EFFECT_BADGE_SCENE := preload("res://ui/status_effect_badge.tscn")
const MENU_BUTTON := preload("res://ui/hud_menu_button.tscn")
const SUMMARY_ROW := preload("res://ui/hud_menu_summary_row.tscn")
const LIFETIME_SECTION := preload("res://ui/hud_menu_lifetime_section.tscn")
const ACHIEVEMENT_ENTRY := preload("res://ui/hud_menu_achievement_entry.tscn")
const CardFace := preload("res://ui/card_face.gd")
const UNKNOWN_EFFECT_ICON := preload("res://assets/rework/icons/curse.tres")

## Header height when the training room has no dungeon objective or floor caption.
@export var training_header_height := 48.0
## Minimum height of a Blood Altar offer, including its title and cost/reward line.
@export var altar_offer_height := 66.0

@onready var _world_content: Control = $WorldContent
@onready var _header: Panel = $WorldContent/Header
@onready var _full_header_height := _header.size.y
@onready var _zone: Label = $WorldContent/Header/Zone
@onready var _objective: Label = $WorldContent/Header/Objective
@onready var _room_name: Label = $WorldContent/Header/RoomName
@onready var _prompt: Label = $WorldContent/Prompt
@onready var _notice: Label = $WorldContent/Notice
@onready var _discovery_toast: PanelContainer = $WorldContent/DiscoveryToast
@onready var _discovery_text: Label = $WorldContent/DiscoveryToast/DiscoveryText
@onready var _life: ProgressBar = $WorldContent/Vitals/Life
@onready var _mana: ProgressBar = $WorldContent/Vitals/Mana
@onready var _stamina: ProgressBar = $WorldContent/Vitals/Stamina
@onready var _status_row: HFlowContainer = $WorldContent/Vitals/ActiveEffects
@onready var _bleed_badge: EffectBadge = $WorldContent/Vitals/ActiveEffects/BleedBadge
@onready var _ward: Label = $WorldContent/Vitals/Ward
@onready var _life_text: Label = $WorldContent/Vitals/LifeValue
@onready var _mana_text: Label = $WorldContent/Vitals/ManaValue
@onready var _stamina_text: Label = $WorldContent/Vitals/StaminaValue
@onready var _gold: Label = $WorldContent/Gold
@onready var _controls: Label = $WorldContent/Controls
@onready var _overlay: ColorRect = $Overlay
@onready var _menu_heading: Label = $Overlay/Center/Frame/Contents/Heading
@onready var _menu_description: Label = $Overlay/Center/Frame/Contents/Description
@onready var _menus: VBoxContainer = $Overlay/Center/Frame/Contents/Menus
@onready var _pause: VBoxContainer = _menus.get_node("Pause")
@onready var _settings: VBoxContainer = _menus.get_node("Settings")
@onready var _depths: VBoxContainer = _menus.get_node("Depths")
@onready var _seal_vault: VBoxContainer = _menus.get_node("SealVault")
@onready var _blood_altar: VBoxContainer = _menus.get_node("BloodAltar")
@onready var _recap: VBoxContainer = _menus.get_node("Recap")
@onready var _lifetime: VBoxContainer = _menus.get_node("Lifetime")
@onready var _achievements: VBoxContainer = _menus.get_node("Achievements")
@onready var _save_error: VBoxContainer = _menus.get_node("SaveError")
@onready var _fullscreen: CheckButton = _settings.get_node("Fullscreen")
@onready var _lifetime_scroll: ScrollContainer = _lifetime.get_node("Scroll")
@onready var _lifetime_scroll_height := _lifetime_scroll.custom_minimum_size.y
@onready var _achievement_scroll: ScrollContainer = _achievements.get_node("Scroll")
@onready var _achievement_scroll_height := _achievement_scroll.custom_minimum_size.y
@onready var _achievement_toast: PanelContainer = $AchievementUnlock
@onready var _achievement_y := _achievement_toast.position.y
@onready var _pointer: Control = $WorldContent/Pointer
@onready var _guard_gauge: Panel = $WorldContent/Pointer/GuardGauge
@onready var _guard_meter: ProgressBar = $WorldContent/Pointer/GuardGauge/Meter
@onready var _guard_mark: Polygon2D = $WorldContent/Pointer/GuardGauge/Shield
@onready var _guard_break_mark: Line2D = $WorldContent/Pointer/GuardGauge/BreakMark
@onready var _charge_gauge: ProgressBar = $WorldContent/Pointer/ChargeGauge
@onready var _map: DungeonMap = $WorldContent/Map

var _discovery_queue: Array[String] = []
var _discovery_time := 0.0
var _active_menu: VBoxContainer
var _recap_available := false
var _character_tools := false
var _achievement_queue: Array[Dictionary] = []
var _achievement_visible := false
var _shown_stamina := Vector2i(-1, -1)
var _guard_ready := true
var _notice_time := 0.0
var _card_hand_open := false
var _cards_action := "Deck"
var _effect_source: CharacterBody3D
var _effect_badges: Dictionary[StringName, EffectBadge] = {}
var _card_status_textures: Dictionary[int, Texture2D] = {}
var _show_expedition_buffs := false


func _ready() -> void:
	_bleed_badge.icon.name = &"BleedStatusIcon"
	_bleed_badge.countdown.name = &"BleedStatusCountdown"
	_effect_badges[&"bleed"] = _bleed_badge
	_active_menu = _pause
	_connect_menu_actions()
	$EffectRefresh.timeout.connect(_refresh_active_effects)
	_map.visibility_changed.connect(_update_notice_visibility)


func bind_effect_source(player: CharacterBody3D) -> void:
	if _effect_source == player:
		return
	if is_instance_valid(_effect_source):
		_effect_source.active_statuses_changed.disconnect(_refresh_active_effects)
		_effect_source.card_effects.display_changed.disconnect(_refresh_active_effects)
	_effect_source = player
	if is_instance_valid(player):
		player.active_statuses_changed.connect(_refresh_active_effects)
		player.card_effects.display_changed.connect(_refresh_active_effects)
	_refresh_active_effects()


func _process(delta: float) -> void:
	if _pointer.visible and _discovery_time > 0.0:
		_discovery_time -= delta
		_discovery_toast.modulate.a = clampf(_discovery_time * 4.0, 0.0, 1.0)
		if _discovery_time <= 0.0:
			_show_next_discovery()
	if _notice_time > 0.0:
		_notice_time -= delta
		_notice.modulate.a = clampf(_notice_time * 1.4, 0.0, 1.0)


func set_zone(in_dungeon: bool, floor_number: int, remaining: int, highest: int, cleared: bool,
		depth_name: String, room_name: String, floor_index: int = 0, floor_count: int = 1,
		unspent_cards := 0) -> void:
	_set_expedition_buff_visibility(in_dungeon)
	_header.size.y = _full_header_height
	_zone.text = "%s · Depth %02d" % [depth_name, floor_number] if in_dungeon else "Cinderhold Refuge"
	var location := room_name
	if floor_count > 1:
		var floor_caption := "Floor %d/%d" % [floor_index + 1, floor_count]
		location = floor_caption if room_name.is_empty() else "%s · %s" % [floor_caption, room_name]
	_room_name.text = location
	_room_name.visible = in_dungeon and not location.is_empty()
	_gold.visible = in_dungeon
	if in_dungeon:
		_cards_action = "Cards"
		_objective.text = "Depth cleared · Collect your rewards" if cleared else "%d enemies remaining" % remaining
		_controls.text = "E  Interact     Q  Cards (%d)     T  Portal     Tab  Map     I  Pack     Esc  Pause" % unspent_cards
	else:
		_cards_action = "Deck"
		_objective.text = "Deepest gate unlocked · %02d" % highest
		_controls.text = "E  Interact     Q  Deck     I  Pack     Esc  Pause"
		if _map.visible:
			_map.hide()


func set_vitals(life: float, max_life: float, mana: float, max_mana: float, ward: float, gold: int) -> void:
	_life.max_value = max_life
	_life.value = life
	_mana.max_value = max_mana
	_mana.value = mana
	_life_text.text = "%d / %d" % [ceili(life), ceili(max_life)]
	_mana_text.text = "%d / %d" % [ceili(mana), ceili(max_mana)]
	_ward.text = "+%d Ward" % ceili(ward) if ward > 0.0 else ""
	_gold.text = "%d gold" % gold


func _set_expedition_buff_visibility(show_cards: bool) -> void:
	if _show_expedition_buffs != show_cards:
		_show_expedition_buffs = show_cards
		_refresh_active_effects()


func _refresh_active_effects() -> void:
	var rows: Array[Dictionary] = []
	if is_instance_valid(_effect_source):
		if _show_expedition_buffs:
			rows = _effect_source.card_effects.active_statuses()
		rows.append_array(_effect_source.active_statuses())
	var seen: Dictionary[StringName, bool] = {}
	for index in rows.size():
		var status: Dictionary = rows[index]
		var id: StringName = status.id
		var badge := _effect_badges.get(id) as EffectBadge
		if badge == null:
			badge = _add_effect_badge(id)
		badge.present(status, _effect_icon(status))
		if badge.get_index() != index:
			_status_row.move_child(badge, index)
		seen[id] = true
	for id: StringName in _effect_badges.keys():
		if seen.has(id):
			continue
		var badge := _effect_badges[id]
		badge.clear_status()
		if id != &"bleed":
			_effect_badges.erase(id)
			_status_row.remove_child(badge)
			badge.queue_free()
	_status_row.visible = not rows.is_empty()


func _add_effect_badge(id: StringName) -> EffectBadge:
	var badge := EFFECT_BADGE_SCENE.instantiate() as EffectBadge
	badge.name = String(id).to_pascal_case() + "Badge"
	_status_row.add_child(badge)
	_effect_badges[id] = badge
	return badge


func _effect_icon(status: Dictionary) -> Texture2D:
	var index := int(status.get("card_art", -1))
	if index >= 0:
		if not _card_status_textures.has(index):
			_card_status_textures[index] = CardFace.art_texture(index)
		return _card_status_textures[index]
	var icon := status.get("icon") as Texture2D
	return icon if icon != null else UNKNOWN_EFFECT_ICON


func set_stamina(current: float, maximum: float, guard_held: bool, blocking: bool, charge_fraction := 0.0) -> void:
	_stamina.max_value = maximum
	_stamina.value = current
	var counters := Vector2i(floori(current + 0.0001), roundi(maximum))
	if counters != _shown_stamina:
		_shown_stamina = counters
		_stamina_text.text = "%d / %d" % [counters.x, counters.y]
	_guard_gauge.visible = guard_held
	if guard_held:
		_guard_meter.max_value = maximum
		_guard_meter.value = current
		if blocking != _guard_ready:
			_guard_ready = blocking
			_guard_mark.visible = blocking
			_guard_break_mark.visible = not blocking
			_guard_gauge.self_modulate = Color.WHITE if blocking else Color("#dc9a7f")
			_guard_gauge.accessibility_name = "Block stamina" if blocking else "Guard depleted"
	_charge_gauge.visible = not guard_held and charge_fraction > 0.0
	if _charge_gauge.visible:
		_charge_gauge.value = charge_fraction


func set_training_zone(unspent_cards: int) -> void:
	_set_expedition_buff_visibility(true)
	_header.size.y = training_header_height
	_zone.text = "Training Ground"
	_room_name.hide()
	_gold.hide()
	_objective.text = ""
	_cards_action = "Training Deck"
	_controls.text = "F1  Training Menu     E  Interact     Q  Cards (%d)     I  Pack     Esc  Pause" % unspent_cards
	_map.hide()


func set_prompt(message: String, tint := MenuFrame.TEXT) -> void:
	_prompt.text = message
	_prompt.add_theme_color_override("font_color", tint)


func set_world_visible(enabled: bool) -> void:
	_world_content.visible = enabled


func set_gameplay(enabled: bool) -> void:
	_pointer.visible = enabled
	_prompt.visible = enabled
	if not enabled:
		_map.hide()


func set_card_hand_open(opened: bool) -> void:
	_card_hand_open = opened
	_update_notice_visibility()


func _update_notice_visibility() -> void:
	_notice.visible = not (_card_hand_open or _map.visible)


func notify(message: String) -> void:
	if not message.is_empty():
		_notice.text = message
		_notice.modulate.a = 1.0
		_notice_time = 3.6


func notify_discovery(enemy_name: String) -> void:
	_discovery_queue.append(enemy_name)
	if _discovery_time <= 0.0:
		_show_next_discovery()


func _show_next_discovery() -> void:
	if _discovery_queue.is_empty():
		_discovery_toast.hide()
		return
	_discovery_text.text = "%s added to bestiary" % _discovery_queue.pop_front()
	_discovery_time = 2.8
	_discovery_toast.modulate.a = 1.0
	_discovery_toast.show()


func is_menu_open() -> bool:
	return _overlay.visible


func _connect_menu_actions() -> void:
	(_pause.get_node("Resume") as Button).pressed.connect(close_menu)
	(_pause.get_node("Cards") as Button).pressed.connect(cards_requested.emit)
	(_pause.get_node("CombatLog") as Button).pressed.connect(combat_log_requested.emit)
	(_pause.get_node("Recap") as Button).pressed.connect(recap_requested.emit)
	(_pause.get_node("Achievements") as Button).pressed.connect(achievements_requested.emit)
	(_pause.get_node("Settings") as Button).pressed.connect(settings_requested.emit)
	(_pause.get_node("Quit") as Button).pressed.connect(quit_requested.emit)
	(_seal_vault.get_node("Confirm") as Button).pressed.connect(leave_requested.emit)
	(_settings.get_node("Bestiary") as Button).pressed.connect(bestiary_requested.emit)
	(_settings.get_node("Lifetime") as Button).pressed.connect(statistics_requested.emit)
	_fullscreen.toggled.connect(fullscreen_changed.emit)
	for menu: VBoxContainer in [_depths, _seal_vault, _blood_altar]:
		(menu.get_node("Back") as Button).pressed.connect(close_menu)
	for menu: VBoxContainer in [_settings, _recap, _lifetime, _achievements, _save_error]:
		(menu.get_node("Back") as Button).pressed.connect(back_from_menu)


func back_from_menu() -> void:
	if _active_menu == _settings:
		settings_back_requested.emit()
	elif _active_menu == _lifetime:
		settings_requested.emit()
	elif _active_menu in [_save_error, _recap, _achievements]:
		open_pause()
	else:
		close_menu()


func hide_menu() -> void:
	if is_instance_valid(_active_menu):
		_active_menu.hide()
		_active_menu = null
	_overlay.hide()


func close_menu() -> void:
	hide_menu()
	resume_requested.emit()


func open_depths(highest: int) -> void:
	var scroll := _depths.get_node("Scroll") as ScrollContainer
	var levels := scroll.get_node("Rows") as VBoxContainer
	_clear_rows(levels)
	for depth in range(highest, 0, -1):
		var choice := MENU_BUTTON.instantiate() as Button
		choice.text = "Enter Depth %02d" % depth
		if depth == highest:
			choice.theme_type_variation = &"PrimaryButton"
		choice.pressed.connect(level_selected.emit.bind(depth))
		levels.add_child(choice)
	scroll.scroll_vertical = 0
	_open_menu(_depths, "The Gate Below", "Choose a depth. Slay every enemy on that depth to unseal the next.")


func open_close(cleared: bool) -> void:
	var body := "The vault is clear. Close the gate when you have collected everything you want to keep."
	if not cleared:
		body = "Closing the gate abandons this attempt. You keep equipment, materials, and gold you already picked up."
	_open_menu(_seal_vault, "Seal the Vault", body + " Unused treasure keys and loot left inside are lost.")


func open_blood_altar(offers: Array[Dictionary]) -> void:
	var rows := _blood_altar.get_node("Offers") as VBoxContainer
	_clear_rows(rows)
	for offer in offers:
		var choice := MENU_BUTTON.instantiate() as Button
		choice.text = "%s\n%s · %s" % [offer.name, offer.curse, offer.reward]
		choice.custom_minimum_size.y = maxf(choice.custom_minimum_size.y, altar_offer_height)
		choice.pressed.connect(blood_oath_selected.emit.bind(String(offer.id)))
		rows.add_child(choice)
	_open_menu(_blood_altar, "Blood Altar", "Choose one bargain for this expedition.")


func open_pause() -> void:
	(_pause.get_node("Cards") as Button).text = _cards_action
	(_pause.get_node("Recap") as Button).visible = _recap_available
	(_pause.get_node("Achievements") as Button).visible = _character_tools
	_open_menu(_pause, "Paused", "")
	(_pause.get_node("Resume") as Button).grab_focus()


func set_recap_available(available: bool) -> void:
	_recap_available = available


func set_character_tools(available: bool) -> void:
	_character_tools = available


func open_expedition_recap(area: String, depth: int, cleared: bool, rows: Array) -> void:
	var contents := _recap.get_node("Rows") as VBoxContainer
	_clear_rows(contents)
	for values: Array in rows:
		var row := SUMMARY_ROW.instantiate() as HBoxContainer
		_fill_summary(row, values[0], values[1])
		contents.add_child(row)
	_open_menu(_recap, "Expedition Recap", "%s · Depth %02d · %s" % [area, depth, "Cleared" if cleared else "In progress"])


func open_settings(fullscreen: bool, embedded: bool, character_tools := false) -> void:
	_fullscreen.set_pressed_no_signal(fullscreen)
	_fullscreen.disabled = embedded
	(_settings.get_node("EmbeddedHelp") as Label).visible = embedded
	(_settings.get_node("Lifetime") as Button).visible = character_tools
	_open_menu(_settings, "Settings", "")


func open_save_error() -> void:
	_open_menu(_save_error, "Save failed", "The checkpoint could not be written.")


func open_lifetime_statistics(character_name: String, categories: Dictionary) -> void:
	var contents := _lifetime_scroll.get_node("Rows") as VBoxContainer
	_clear_rows(contents)
	for category: String in categories:
		var section := LIFETIME_SECTION.instantiate() as VBoxContainer
		(section.get_node("Heading") as Label).text = category
		var rows: Array = categories[category]
		(section.get_node("Empty") as Label).visible = rows.is_empty()
		var list := section.get_node("Rows") as VBoxContainer
		list.visible = not rows.is_empty()
		for values: Array in rows:
			var row := SUMMARY_ROW.instantiate() as HBoxContainer
			_fill_summary(row, values[0], values[1])
			list.add_child(row)
		contents.add_child(section)
	_lifetime_scroll.custom_minimum_size.y = minf(_lifetime_scroll_height, get_viewport_rect().size.y * 0.52)
	_lifetime_scroll.scroll_vertical = 0
	_open_menu(_lifetime, "Lifetime Statistics", character_name)


func open_achievements(entries: Array[Dictionary], points: int) -> void:
	var contents := _achievement_scroll.get_node("Rows") as VBoxContainer
	_clear_rows(contents)
	for entry in entries:
		var title: String = "✓ " + entry.name if entry.unlocked else entry.name
		var score := "%d pts" % int(entry.points) if entry.unlocked else "%d / %d" % [entry.progress, entry.threshold]
		var row := ACHIEVEMENT_ENTRY.instantiate() as VBoxContainer
		_fill_summary(row.get_node("Summary"), title, score, bool(entry.unlocked))
		(row.get_node("Description") as Label).text = entry.description
		contents.add_child(row)
	_achievement_scroll.custom_minimum_size.y = minf(_achievement_scroll_height, get_viewport_rect().size.y * 0.52)
	_achievement_scroll.scroll_vertical = 0
	_open_menu(_achievements, "Achievements", "%d achievement points earned" % points)


func present_achievement(entry: Dictionary) -> void:
	_achievement_queue.append(entry)
	if not _achievement_visible:
		_next_achievement()


func _next_achievement() -> void:
	_achievement_visible = not _achievement_queue.is_empty()
	if not _achievement_visible:
		_achievement_toast.hide()
		return
	var entry: Dictionary = _achievement_queue.pop_front()
	(_achievement_toast.get_node("Contents/Badge/Points") as Label).text = "+%d" % int(entry.points)
	(_achievement_toast.get_node("Contents/Labels/Title") as Label).text = entry.name
	(_achievement_toast.get_node("Contents/Labels/Description") as Label).text = entry.description
	_achievement_toast.modulate.a = 0.0
	_achievement_toast.show()
	# Let the description wrap at the actual width before sizing the slide-in.
	await get_tree().process_frame
	_achievement_toast.size.y = _achievement_toast.get_combined_minimum_size().y
	_achievement_toast.position.y = -_achievement_toast.size.y
	_achievement_toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_achievement_toast, "position:y", _achievement_y, 0.37) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(3.6)
	tween.tween_property(_achievement_toast, "modulate:a", 0.0, 0.28)
	tween.tween_callback(_next_achievement)


func _open_menu(menu: VBoxContainer, title: String, body: String) -> void:
	if is_instance_valid(_active_menu):
		_active_menu.hide()
	_active_menu = menu
	_menu_heading.text = title
	_menu_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if menu == _pause else HORIZONTAL_ALIGNMENT_LEFT
	_menu_description.text = body
	_menu_description.visible = not body.is_empty()
	menu.show()
	_overlay.show()


func _clear_rows(rows: VBoxContainer) -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()


func _fill_summary(row: Node, title: String, value: String, earned := false) -> void:
	var caption := row.get_node("Caption") as Label
	caption.text = title
	if earned:
		caption.add_theme_color_override(&"font_color", MenuFrame.TEXT)
	(row.get_node("Value") as Label).text = value


func toggle_map() -> void:
	_map.visible = not _map.visible
	_map.queue_redraw()


func is_map_visible() -> bool:
	return _map.visible


func set_map(fog: RefCounted, targets: Array[Vector2i], caption: String,
		trail: Array[Vector2i], stairs: Dictionary, player: Node3D, dungeon_floor: Node3D, cell_size: float) -> void:
	_map.update_projection(fog, targets, caption, trail, stairs, player, dungeon_floor, cell_size)


func map_has_route() -> bool:
	return _map.has_route()
