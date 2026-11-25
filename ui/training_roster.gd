extends Control
## Lets the player choose enemies, equipment, and cards for the Training Ground.

signal spawn_requested(archetype_id: int)
signal weapon_requested(choice_id: String)
signal close_requested
signal ability_traces_changed(enabled: bool)
signal player_weapon_traces_changed(enabled: bool)
signal player_level_changed(level: int)

const Catalog := preload("res://combat/enemies/enemy_catalog.gd")
const Affixes := preload("res://combat/effects/enemy_affixes.gd")
const BestiaryData := preload("res://data/bestiary.gd")
const CardDeck := preload("res://systems/card_deck.gd")
const CardLoadout := preload("res://ui/card_loadout.gd")
const ItemArt := preload("res://ui/item_art.gd")
const Items := preload("res://systems/items.gd")
const Progression := preload("res://systems/character_progression.gd")
const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const ENEMY_CARD := preload("res://ui/training_enemy_card.tscn")
const WEAPON_CARD := preload("res://ui/training_weapon_card.tscn")
const AFFIX_BUTTON := preload("res://ui/training_affix_button.tscn")
const RARITIES := ["normal", "magic", "rare"]
const DEFAULT_ENEMY_LEVEL := 1
const DEFAULT_WEAPON_ITEM_LEVEL := 1
const ENEMY_TAB := 0
const WEAPONRY_TAB := 1
const CARDS_TAB := 2

## Largest centered roster panel before the layout adapts to a smaller viewport.
@export var panel_size_limit := Vector2(968.0, 748.0)
## Minimum space around the centered panel on each viewport edge.
@export var viewport_inset := 20.0

@onready var _panel: PanelContainer = %Panel
@onready var _tabs: TabContainer = %TrainingTabs
@onready var _scroll: ScrollContainer = %EnemyScroll
@onready var _grid: GridContainer = %EnemyGrid
@onready var _weapon_scroll: ScrollContainer = %WeaponScroll
@onready var _weapon_grid: GridContainer = %WeaponGrid
@onready var _enemy_columns_limit := _grid.columns
@onready var _weapon_columns_limit := _weapon_grid.columns
@onready var _card_loadout: CardLoadout = %Cards
@onready var _close_button: Button = %Close
@onready var _enemy_level: SpinBox = %EnemyLevel
@onready var _player_level: SpinBox = %PlayerLevel
@onready var _weapon_item_level: SpinBox = %WeaponItemLevel
@onready var _ability_traces: CheckButton = %ShowAbilityTraces
@onready var _player_weapon_traces: CheckButton = %ShowPlayerWeaponTraces
@onready var _affix_panel: VBoxContainer = %AffixPanel
@onready var _affix_summary: Label = %AffixSummary

var _training_deck: CardDeck
var _player_level_value := 1
var _cards: Array[Button] = []
var _weapon_cards: Array[Button] = []
var _weapon_choices: Array[Dictionary] = []
var _rarity := "normal"
var _affixes: Array[String] = []
var _rarity_buttons: Dictionary[String, Button] = {}
var _affix_buttons: Dictionary[String, Button] = {}
var _populated := false


func _ready() -> void:
	_close_button.pressed.connect(close_requested.emit)
	_ability_traces.toggled.connect(ability_traces_changed.emit)
	_player_weapon_traces.toggled.connect(player_weapon_traces_changed.emit)
	_tabs.tab_changed.connect(_on_tab_changed)
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	_card_loadout.slot_changed.connect(_equip_training_card)
	_player_level.max_value = Progression.MAX_LEVEL
	set_player_level(_player_level_value)
	for input: SpinBox in [_enemy_level, _player_level, _weapon_item_level]:
		var edit := input.get_line_edit()
		edit.select_all_on_focus = true
		edit.accessibility_name = input.accessibility_name
	_player_level.value_changed.connect(_on_player_level_changed)
	_weapon_item_level.value_changed.connect(_refresh_weapon_previews)
	for rarity: String in RARITIES:
		var choice := %RarityRow.get_node("Rarity" + rarity.capitalize()) as Button
		choice.pressed.connect(_select_rarity.bind(rarity))
		_rarity_buttons[rarity] = choice
	_panel.minimum_size_changed.connect(_reflow)
	resized.connect(_reflow)
	hide()


func present() -> void:
	if not _populated:
		_populate_catalogues()
	_refresh_training_deck()
	show()
	_reflow()
	if _tabs.current_tab == ENEMY_TAB:
		_scroll.scroll_vertical = 0
	_focus_content()


func set_weapon_choices(choices: Array[Dictionary]) -> void:
	if choices == _weapon_choices:
		return
	_weapon_choices = choices.duplicate(true)
	if _populated:
		_rebuild_weapon_cards()
		_reflow()
		if visible and _tabs.current_tab == WEAPONRY_TAB:
			_focus_content()


func bind_card_deck(deck: CardDeck) -> void:
	_training_deck = deck
	_refresh_training_deck(true)


func close() -> void:
	hide()


func is_open() -> bool:
	return visible


func selected_rarity() -> String:
	return _rarity


func selected_level() -> int:
	if _enemy_level == null:
		return DEFAULT_ENEMY_LEVEL
	_enemy_level.apply()
	return int(_enemy_level.value)


func selected_player_level() -> int:
	if _player_level != null:
		_player_level.apply()
	return _player_level_value


func set_player_level(level: int) -> void:
	_player_level_value = clampi(level, 1, Progression.MAX_LEVEL)
	if _player_level != null:
		_player_level.set_value_no_signal(_player_level_value)
		_player_level.get_line_edit().text = str(_player_level_value)


func selected_weapon_item_level() -> int:
	if _weapon_item_level == null:
		return DEFAULT_WEAPON_ITEM_LEVEL
	_weapon_item_level.apply()
	return int(_weapon_item_level.value)


func selected_affixes() -> Array[String]:
	return _affixes.duplicate()


func ability_traces_enabled() -> bool:
	return _ability_traces != null and _ability_traces.button_pressed


func player_weapon_traces_enabled() -> bool:
	return _player_weapon_traces != null and _player_weapon_traces.button_pressed


func _populate_catalogues() -> void:
	for id in Catalog.ARCHETYPES.size():
		var caption: String = Catalog.ARCHETYPES[id]["name"]
		var card := ENEMY_CARD.instantiate() as Button
		card.name = "Enemy%d" % id
		card.accessibility_name = "Spawn %s" % caption
		var portrait := card.get_node("PortraitWell/Portrait") as TextureRect
		portrait.texture = BestiaryData.portrait_texture(id)
		var label := card.get_node("Caption") as Label
		label.text = caption
		card.pressed.connect(spawn_requested.emit.bind(id))
		_grid.add_child(card)
		_cards.append(card)
	for affix: String in Affixes.AFFIX_NAMES:
		var choice := AFFIX_BUTTON.instantiate() as Button
		choice.name = "Affix_" + affix
		choice.text = Affixes.AFFIX_NAMES[affix]
		choice.tooltip_text = BestiaryData.combat_ability(-1, affix)["description"]
		choice.pressed.connect(_toggle_affix.bind(affix))
		%AffixChoices.add_child(choice)
		_affix_buttons[affix] = choice
	_refresh_spawn_options()
	_rebuild_weapon_cards()
	_populated = true


func _on_tab_changed(index: int) -> void:
	if index == CARDS_TAB:
		_refresh_training_deck()
	_reflow()


func _focus_content() -> void:
	if _tabs.current_tab == CARDS_TAB:
		var controls := _card_loadout.focus_controls()
		(controls[0] if not controls.is_empty() else _tabs.get_tab_bar()).grab_focus()
	elif _tabs.current_tab == WEAPONRY_TAB:
		if _weapon_cards.is_empty():
			_tabs.get_tab_bar().grab_focus()
		else:
			var row_height := _weapon_cards[0].get_combined_minimum_size().y \
				+ _weapon_grid.get_theme_constant("v_separation")
			var row := floori(_weapon_scroll.scroll_vertical / row_height)
			var index := mini(row * _weapon_grid.columns, _weapon_cards.size() - 1)
			_weapon_cards[index].grab_focus()
	else:
		_cards[0].grab_focus()


func _refresh_training_deck(reset_selection := false) -> void:
	if _populated and _training_deck != null:
		_card_loadout.present(_training_deck.owned, _training_deck.equipped, reset_selection)


func _equip_training_card(slot: int, id: String) -> void:
	if not visible or _tabs.current_tab != CARDS_TAB or _training_deck == null:
		return
	if _training_deck.equip(slot, id):
		_refresh_training_deck()
		_reflow()


func _rebuild_weapon_cards() -> void:
	for card: Button in _weapon_cards:
		_weapon_grid.remove_child(card)
		card.queue_free()
	_weapon_cards.clear()
	for choice: Dictionary in _weapon_choices:
		var id := String(choice["id"])
		var caption := String(choice["name"])
		var type := String(choice.get("type", ""))
		var category := String(choice.get("type_label", type.capitalize()))
		var family := WeaponRoles.family(type)
		if not family.is_empty():
			category += " · " + String(family).capitalize()
		var rarity := String(choice.get("rarity", "normal"))
		var card := WEAPON_CARD.instantiate() as Button
		card.name = "Weapon_" + id.validate_node_name()
		card.set_meta(&"choice_id", id)
		card.accessibility_name = "Spawn %s" % caption
		card.set_meta(&"caption", caption)
		card.set_meta(&"category", category)
		card.pressed.connect(weapon_requested.emit.bind(id))
		var icon := card.get_node("Contents/Icon") as TextureRect
		icon.texture = choice.get("icon") as Texture2D
		if icon.texture == null:
			icon.texture = ItemArt.texture_for_base(String(choice.get("base_id", "")), type)
		var title := card.get_node("Contents/Labels/Title") as Label
		title.text = caption
		if rarity != "normal":
			title.add_theme_color_override("font_color", Items.item_color(rarity))
		var kind := card.get_node("Contents/Labels/Category") as Label
		kind.text = category
		kind.visible = not category.is_empty()
		_weapon_grid.add_child(card)
		_weapon_cards.append(card)
	_refresh_weapon_previews(_weapon_item_level.value)


func _refresh_weapon_previews(level: float) -> void:
	for card: Button in _weapon_cards:
		var preview := Items.training_weapon_preview(String(card.get_meta(&"choice_id")), int(level))
		if preview.is_empty():
			continue
		var base_lines := Items.stat_lines(preview.get("base_stats", {}))
		var implicit_lines := Items.stat_lines(preview.get("implicit", {}))
		var base_label := card.get_node("Contents/Labels/BaseStats") as Label
		base_label.text = " · ".join(base_lines)
		base_label.visible = not base_lines.is_empty()
		var implicit_label := card.get_node("Contents/Labels/ImplicitStats") as Label
		implicit_label.text = "Implicit · " + " · ".join(implicit_lines)
		implicit_label.visible = not implicit_lines.is_empty()
		var tooltip := PackedStringArray([String(card.get_meta(&"caption")),
			"%s · Item level %d" % [card.get_meta(&"category"), preview.item_level]])
		tooltip.append_array(base_lines)
		if implicit_label.visible:
			tooltip.append(implicit_label.text)
		card.tooltip_text = "\n".join(tooltip)


func _on_player_level_changed(level: float) -> void:
	_player_level_value = int(level)
	player_level_changed.emit(_player_level_value)


func _select_rarity(rarity: String) -> void:
	_rarity = rarity
	_affixes.resize(mini(_affixes.size(), Affixes.selection_limit(rarity)))
	_refresh_spawn_options()
	_reflow()


func _toggle_affix(affix: String) -> void:
	if _affixes.has(affix):
		_affixes.erase(affix)
	elif _affixes.size() < Affixes.selection_limit(_rarity):
		_affixes.append(affix)
	_refresh_spawn_options()
	_reflow()


func _refresh_spawn_options() -> void:
	var limit := Affixes.selection_limit(_rarity)
	for rarity: String in RARITIES:
		_rarity_buttons[rarity].set_pressed_no_signal(rarity == _rarity)
	_affix_panel.visible = limit > 0
	_affix_summary.text = "Affixes · Random roll" if _affixes.is_empty() \
		else "Affixes · %d of %d selected" % [_affixes.size(), limit]
	for affix: String in _affix_buttons:
		var choice := _affix_buttons[affix]
		var selected := _affixes.has(affix)
		choice.set_pressed_no_signal(selected)
		choice.disabled = not selected and _affixes.size() >= limit


func _reflow() -> void:
	if not _populated:
		return
	var desired := (size - Vector2.ONE * (viewport_inset * 2.0)).clamp(Vector2.ONE, panel_size_limit)
	var panel_style := _panel.get_theme_stylebox("panel")
	var content_width := desired.x - panel_style.get_minimum_size().x
	_fit_columns(_grid, _scroll, _cards, content_width, _enemy_columns_limit)
	_fit_columns(_weapon_grid, _weapon_scroll, _weapon_cards, content_width, _weapon_columns_limit)
	_panel.size = desired
	_panel.position = ((size - _panel.size) * 0.5).round()
	var tab_bar := _tabs.get_tab_bar()
	var focus_order: Array[Control] = [_close_button, tab_bar]
	if _tabs.current_tab == ENEMY_TAB:
		focus_order.append(_enemy_level.get_line_edit())
		focus_order.append(_player_level.get_line_edit())
		for rarity: String in RARITIES:
			focus_order.append(_rarity_buttons[rarity])
		focus_order.append(_ability_traces)
		if _affix_panel.visible:
			for choice: Button in _affix_buttons.values():
				if not choice.disabled:
					focus_order.append(choice)
		focus_order.append_array(_cards)
		_wire_card_focus(_cards, _grid.columns, _rarity_buttons[_rarity])
	elif _tabs.current_tab == WEAPONRY_TAB:
		var item_level_edit := _weapon_item_level.get_line_edit()
		focus_order.append(item_level_edit)
		focus_order.append(_player_weapon_traces)
		focus_order.append_array(_weapon_cards)
		_wire_card_focus(_weapon_cards, _weapon_grid.columns, item_level_edit)
	else:
		var card_controls := _card_loadout.focus_controls()
		focus_order.append_array(card_controls)
		var first_card_control := card_controls[0] if not card_controls.is_empty() else tab_bar
		_close_button.focus_neighbor_bottom = _close_button.get_path_to(first_card_control)
	tab_bar.focus_neighbor_bottom = tab_bar.get_path_to(focus_order[2] if focus_order.size() > 2 else tab_bar)
	for index in focus_order.size():
		var control := focus_order[index]
		control.focus_previous = control.get_path_to(focus_order[posmod(index - 1, focus_order.size())])
		control.focus_next = control.get_path_to(focus_order[(index + 1) % focus_order.size()])


static func _fit_columns(grid: GridContainer, scroll: ScrollContainer, cards: Array[Button],
		content_width: float, limit: int) -> void:
	if cards.is_empty():
		return
	var available := content_width - scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var card_width := cards[0].get_combined_minimum_size().x
	var gap := grid.get_theme_constant("h_separation")
	grid.columns = clampi(floori((available + gap) / (card_width + gap)), 1, limit)


func _wire_card_focus(cards: Array[Button], columns: int, above_first: Control) -> void:
	for index in cards.size():
		var card := cards[index]
		var left := index - 1 if index % columns > 0 else index
		var right := index + 1 if index % columns < columns - 1 and index + 1 < cards.size() else index
		card.focus_neighbor_left = card.get_path_to(cards[left])
		card.focus_neighbor_right = card.get_path_to(cards[right])
		var above := cards[index - columns] if index >= columns else above_first
		var below := cards[index + columns] if index + columns < cards.size() else card
		card.focus_neighbor_top = card.get_path_to(above)
		card.focus_neighbor_bottom = card.get_path_to(below)
	var first_row_edge := cards[mini(columns, cards.size()) - 1] if not cards.is_empty() else above_first
	_close_button.focus_neighbor_bottom = _close_button.get_path_to(first_row_edge)
