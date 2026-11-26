extends Control
## Inventory, merchant catalogue, and smithing at the workbench.

signal closed
signal attributes_changed
signal item_drop_requested(source: String, id: StringName)

const Items := preload("res://systems/items.gd")
const Inventory := preload("res://systems/inventory.gd")
const Progression := preload("res://systems/character_progression.gd")
const Grid := preload("res://ui/inventory_grid.gd")
const Appearance := preload("res://ui/inventory_appearance.gd")
const EquipmentSlot := preload("res://ui/inventory_equipment_slot.gd")
const RECIPE_SCENE := preload("res://ui/inventory_recipe_button.tscn")
const STAT_ROW_SCENE := preload("res://ui/inventory_stat_row.tscn")
const Carry := preload("res://ui/inventory_carry.gd")
const ItemTooltip := preload("res://ui/item_tooltip.gd")
const Art := preload("res://ui/item_art.gd")
const MenuFrame := preload("res://ui/menu_frame.gd")
const Supplies := preload("res://systems/pack_supplies.gd")
const CardItems := preload("res://systems/card_items.gd")
const CardDeck := preload("res://systems/card_deck.gd")

const PAPER := MenuFrame.TEXT
const GOLD := Color("#d4ae77")
const QUIET := MenuFrame.DIM
const ERROR_COLOR := Color("#df9a80")
const EDITOR_STYLE_REFRESH_SECONDS := 0.75

const PRIMARY_ATTRIBUTES := {
	&"strength": ["Strength", "Strength attacks"],
	&"dexterity": ["Dexterity", "Dexterity attacks"],
	&"intelligence": ["Intelligence", "Intelligence spells"],
}
const OVERVIEW_STATS := {
	"Life": "max_health", "Mana": "max_mana", "Stamina": "max_stamina", "Armour": "armor", "Ward": "ward",
}
const STAT_GROUPS := {
	"Attack": ["attack_speed", "crit_chance", "crit_multiplier", "fire_damage", "cold_damage",
		"lightning_damage", "poison_damage", "stun_power", "bleed_chance", "bleed_damage", "damage_over_time"],
	"Defence": ["dodge_chance", "fire_resist", "cold_resist", "lightning_resist", "poison_resist",
		"physical_dot_reduction"],
	"Recovery": ["life_regen", "mana_regen", "life_leech", "life_on_kill", "mana_on_kill", "cooldown_recovery"],
	"Exploration": ["move_speed", "loot_rarity", "gold_find"],
}

var _inventory: Inventory
var _card_deck: CardDeck
var _progression: Progression
var _allow_attribute_reset := false
var _mode := ""
var _selected: StringName = &""
var _bag_grid: Grid
var _stash_tabs: Array[Button] = []
var _stash_tab := 0
var _slots: Dictionary = {}
var _grid_minima: Dictionary[Grid, Vector2] = {}
var _attribute_values: Dictionary[StringName, Label] = {}
var _attribute_buttons: Dictionary[StringName, Button] = {}
var _recipes: Dictionary = {}
var _style_disk_hash := ""
var _style_refresh_time := 0.0

@onready var _frame: PanelContainer = %Frame
@onready var _title: Label = %Title
@onready var _gold: Label = %Gold
@onready var _shortcuts: HBoxContainer = %Shortcuts
@onready var _feedback: Label = %Feedback
@onready var _pack_grid: Grid = %PackGrid
@onready var _smith_pack_grid: Grid = %SmithPackGrid
@onready var _vendor_grid: Grid = %VendorGrid
@onready var _stash_grid: Grid = %StashGrid
@onready var _stash_scroll: ScrollContainer = _stash_grid.get_parent()
@onready var _stash_ledger: LineEdit = %Search
@onready var _stash_rarity: OptionButton = %Rarity
@onready var _stash_type: OptionButton = %Type
@onready var _stats: VBoxContainer = %Stats
@onready var _stat_overview: GridContainer = %Overview
@onready var _progression_panel: PanelContainer = %Progression
@onready var _character_level: Label = %Level
@onready var _experience_label: Label = %XP
@onready var _experience_bar: ProgressBar = %ExperienceBar
@onready var _attribute_points: Label = %Available
@onready var _attribute_reset: Button = %Reset
@onready var _smith_target: Label = %SmithName
@onready var _smith_item_art: TextureRect = %SmithArt
@onready var _smith_item_well: PanelContainer = %SmithTarget
@onready var _materials: Label = %Materials
@onready var _smith_list: VBoxContainer = %RecipeList
@onready var _carry: Carry = %Carry
@onready var _item_tooltip: ItemTooltip = %Tooltip

var _tooltip_id: StringName = &""
var _tooltip_slot := ""
var _tooltip_at_vendor := false
var _tooltip_compare := false
var _pointer := Vector2.ZERO


func bind(inventory: Inventory) -> void:
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)
	_inventory = inventory
	if _inventory != null:
		_inventory.changed.connect(_refresh)
	if _carry != null:
		_carry.bind(_inventory)
	if is_inside_tree() and is_open():
		_rebuild()


func bind_card_deck(deck: CardDeck) -> void:
	_card_deck = deck
	if _carry != null:
		_carry.bind_card_deck(deck)


func bind_progression(progression: Progression, allow_reset := false) -> void:
	_progression = progression
	_allow_attribute_reset = allow_reset
	refresh_progression()


func refresh_progression() -> void:
	if _mode != "inventory":
		return
	_dismiss_item_tooltip()
	_update_progression()
	_update_stats()


func _ready() -> void:
	(%Close as Button).pressed.connect(close)
	_carry.bind(_inventory)
	_carry.bind_card_deck(_card_deck)
	_carry.feedback.connect(_show_feedback)
	_carry.outside_drop_requested.connect(item_drop_requested.emit)
	_pack_grid.cursor_swapped.connect(_carry.adopt_native_swap.bind(_pack_grid))
	for grid: Grid in [_pack_grid, _smith_pack_grid, _vendor_grid, _stash_grid]:
		grid.action_feedback.connect(_show_feedback)
		var scroller := grid.get_parent() as ScrollContainer
		_grid_minima[grid] = scroller.custom_minimum_size
		scroller.get_v_scroll_bar().value_changed.connect(_grid_scrolled)
	_smith_pack_grid.item_selected.connect(_select_item.bind("bag"))
	for child: Node in (%EquipmentBoard as Control).get_children():
		if child is EquipmentSlot:
			_slots[child.slot] = child
			child.action_feedback.connect(_show_feedback)
	_setup_stash_controls()
	_setup_attributes()
	for recipe: Dictionary in Items.recipes():
		var id: String = recipe.id
		var button := RECIPE_SCENE.instantiate() as Button
		button.pressed.connect(_craft.bind(id))
		_smith_list.add_child(button)
		_recipes[id] = button
	hide()
	set_process(false)


func _grid_scrolled(_position: float) -> void:
	_carry._refresh_pointer()


func open(mode: String = "inventory") -> void:
	if _inventory == null:
		return
	if mode not in ["inventory", "vendor", "smith", "stash"]:
		return
	if not is_node_ready():
		return
	if OS.has_feature("editor"):
		_refresh_appearance_from_disk()
	_mode = mode
	_selected = &""
	_pointer = get_viewport().get_mouse_position()
	_feedback.text = ""
	_rebuild()
	show()
	set_process(true)


func close() -> void:
	if not is_open():
		return
	_carry.cancel()
	if _carry.is_holding():
		return
	_dismiss_item_tooltip()
	_mode = ""
	hide()
	set_process(false)
	closed.emit()


func is_open() -> bool:
	return not _mode.is_empty()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouse:
		_pointer = event.position
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_I and _stash_ledger != null and _stash_ledger.has_focus():
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_I:
		if _carry.cancel():
			_dismiss_item_tooltip()
		elif get_viewport().gui_is_dragging():
			get_viewport().gui_cancel_drag()
		else:
			close()
		get_viewport().set_input_as_handled()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not is_open() or not data is Dictionary or not data.get("inventory_item", false):
		return false
	var frame_position := _frame.get_global_transform_with_canvas().affine_inverse() * (
		get_global_transform_with_canvas() * at_position)
	return data.get("source", "") in ["bag", "equipment"] \
		and not Rect2(Vector2.ZERO, _frame.size).has_point(frame_position)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_drop_requested.emit(data["source"], data["id"])


func _refresh_appearance_from_disk() -> void:
	_style_refresh_time = EDITOR_STYLE_REFRESH_SECONDS
	var current_hash := FileAccess.get_sha256(Appearance.SOURCE)
	if current_hash.is_empty() or current_hash == _style_disk_hash:
		return
	var refreshed := ResourceLoader.load(Appearance.SOURCE, "", ResourceLoader.CACHE_MODE_REPLACE)
	if refreshed == Appearance.LIVE:
		_style_disk_hash = current_hash
		Appearance.LIVE.emit_changed()


func _process(delta: float) -> void:
	if is_visible_in_tree() and OS.has_feature("editor"):
		_style_refresh_time -= delta
		if _style_refresh_time <= 0.0:
			_refresh_appearance_from_disk()
	if not is_visible_in_tree() or _carry.is_holding() or _carry.is_splitting() or get_viewport().gui_is_dragging():
		_dismiss_item_tooltip()
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var id: StringName = &""
	var slot := ""
	var at_vendor := false
	if hovered is Grid:
		var at_grid := hovered.get_global_transform_with_canvas().affine_inverse() * _pointer
		id = hovered.item_at(at_grid)
		at_vendor = hovered == _vendor_grid
	elif hovered is EquipmentSlot:
		id = hovered.anchored_item_id()
		slot = hovered.slot
	elif _smith_item_well != null and hovered == _smith_item_well:
		id = _selected
	if id.is_empty():
		_dismiss_item_tooltip()
		return
	var cursor := _pointer
	var comparing := Input.is_key_pressed(KEY_SHIFT)
	if id == _tooltip_id and slot == _tooltip_slot and at_vendor == _tooltip_at_vendor \
			and comparing == _tooltip_compare:
		_item_tooltip.follow(cursor)
		return
	var item := _inventory.get_item(id)
	if item.is_empty():
		_dismiss_item_tooltip()
		return
	_tooltip_id = id
	_tooltip_slot = slot
	_tooltip_at_vendor = at_vendor
	_tooltip_compare = comparing
	var price := Inventory.buy_price(item) if at_vendor else -1
	var comparisons: Array[Dictionary] = []
	if comparing:
		comparisons = _inventory.comparison_items(item, slot, _mode == "vendor")
	_item_tooltip.present(item, comparisons, cursor, price)


func _dismiss_item_tooltip() -> void:
	_tooltip_id = &""
	if _item_tooltip.visible:
		_item_tooltip.dismiss()


func _rebuild() -> void:
	_carry.cancel()
	_dismiss_item_tooltip()
	(%Catalogue as Control).visible = _mode == "vendor"
	(%Storage as Control).visible = _mode == "stash"
	(%Smith as Control).visible = _mode == "smith"
	(%Loadout as Control).visible = _mode != "smith"
	(%SmithPack as Control).visible = _mode == "smith"
	(%Character as Control).visible = _mode == "inventory"
	_bag_grid = _smith_pack_grid if _mode == "smith" else _pack_grid
	_bag_grid.allow_quick_actions = _mode == "inventory"
	_bind_grid(_bag_grid)
	var counter: Grid
	match _mode:
		"vendor":
			_title.text = "Merchant"
			_set_shortcuts([["Click", "Carry"], ["Ctrl+click", "Buy or sell"], ["Shift", "Compare"], ["Alt", "Affixes"]])
			counter = _vendor_grid
			_bind_grid(counter)
		"smith":
			_title.text = "Blacksmith"
			_set_shortcuts([["Click", "Select gear and recipe"], ["Shift", "Compare"], ["Alt", "Affixes"]])
		"stash":
			_title.text = "Stash"
			_set_shortcuts([["Click", "Carry"], ["Ctrl+click", "Transfer"], ["Shift", "Compare"], ["Alt", "Affixes"]])
			counter = _stash_grid
			_stash_tabs[_stash_tab].set_pressed_no_signal(true)
			_stash_ledger.clear()
			_stash_rarity.select(0)
			_stash_type.select(0)
			_stash_scroll.scroll_vertical = 0
			_set_stash_grid()
			_refresh_stash_filter()
		_:
			_title.text = "Inventory"
			_set_shortcuts([["Click", "Carry"], ["Right-click", "Equip or remove"], ["Shift", "Compare"], ["Alt", "Affixes"]])
	if _mode != "smith":
		for slot: EquipmentSlot in _slots.values():
			slot.inventory = _inventory
	_carry.set_targets(_mode, _bag_grid, counter, [] if _mode == "smith" else _slots.values(), _frame)
	_refresh()


func _set_shortcuts(shortcuts: Array) -> void:
	for index in _shortcuts.get_child_count():
		var pair := _shortcuts.get_child(index) as HBoxContainer
		pair.visible = index < shortcuts.size()
		if pair.visible:
			(pair.get_node("Key/Text") as Label).text = shortcuts[index][0]
			(pair.get_node("Meaning") as Label).text = shortcuts[index][1]


func _bind_grid(grid: Grid) -> void:
	grid.inventory = _inventory
	var dimensions := _inventory.get_grid(grid.endpoint).get_grid_size()
	grid.set_grid_size(dimensions, grid.cell_size)
	var scroller := grid.get_parent() as ScrollContainer
	var needs_scroll := dimensions.y > grid.authored_cells.y
	var desired := Vector2(grid.authored_cells * grid.cell_size)
	if needs_scroll:
		desired.x += scroller.get_v_scroll_bar().get_combined_minimum_size().x
	scroller.custom_minimum_size = desired.max(_grid_minima[grid])
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if needs_scroll else ScrollContainer.SCROLL_MODE_DISABLED


func _setup_stash_controls() -> void:
	_stash_grid.allow_quick_actions = false
	for child: Button in (%Tabs as HBoxContainer).get_children():
		child.pressed.connect(_select_stash_tab.bind(_stash_tabs.size()))
		_stash_tabs.append(child)
	_stash_ledger.text_changed.connect(func(_text: String) -> void: _refresh_stash_filter())
	for filter: OptionButton in [_stash_rarity, _stash_type]:
		var caption: String = filter.text
		filter.clear()
		_add_filter_item(filter, caption, "")
		filter.item_selected.connect(func(_choice: int) -> void: _refresh_stash_filter())
	for rarity in ["normal", "magic", "rare", "legendary"]:
		_add_filter_item(_stash_rarity, rarity.capitalize(), rarity)
	for key: String in Items.BaseData.TYPES:
		_add_filter_item(_stash_type, Items.BaseData.TYPES[key].name, key)
	_add_filter_item(_stash_type, "Crafting Materials", "material")
	_add_filter_item(_stash_type, "Scribe's Seals", Supplies.UNVEILING_SCROLL)
	_add_filter_item(_stash_type, "Cards", CardItems.KIND)


static func _add_filter_item(menu: OptionButton, caption: String, key: String) -> void:
	menu.add_item(caption)
	menu.set_item_metadata(menu.item_count - 1, key)


func _select_stash_tab(index: int) -> void:
	if index == _stash_tab:
		return
	_stash_tab = index
	_set_stash_grid()
	_stash_scroll.scroll_vertical = 0
	_dismiss_item_tooltip()
	_refresh_stash_filter()
	_carry._refresh_pointer()


func _set_stash_grid() -> void:
	_stash_grid.endpoint = Inventory.Stash.OWNERS[_stash_tab]
	_bind_grid(_stash_grid)


func _refresh_stash_filter() -> void:
	if _mode != "stash":
		return
	var query := _stash_ledger.text.strip_edges().to_lower()
	var rarity := String(_stash_rarity.get_selected_metadata())
	var type := String(_stash_type.get_selected_metadata())
	var active := not query.is_empty() or not rarity.is_empty() or not type.is_empty()
	_stash_grid.set_search_filter(_matching_stash_item.bind(query.split(" ", false), rarity, type) if active else Callable())


static func _matching_stash_item(item: Dictionary, terms: PackedStringArray, rarity: String, item_type: String) -> bool:
	var is_card := CardItems.is_card(item)
	var unidentified: bool = item.get("unidentified", false)
	if not rarity.is_empty() and ((is_card and unidentified) or item.get("rarity", "normal") != rarity):
		return false
	var type: String = item.get("supply_kind", item.get("type", ""))
	if not item_type.is_empty() and type != item_type:
		return false
	if terms.is_empty():
		return true
	var details := ""
	if not unidentified:
		details = String(item.get("description", "")) if is_card else Items.tooltip(item, true)
	var search := ("%s %s %s %s" % [Items.visible_name(item), item.get("base_name", ""),
		type.replace("_", " "), details]).to_lower()
	for term: String in terms:
		if not search.contains(term):
			return false
	return true


func _setup_attributes() -> void:
	var attributes := %Attributes as HBoxContainer
	var attribute_bonuses := {
		&"strength": "+%.2f Maximum Stamina" % Progression.BALANCE.stamina_per_strength,
		&"dexterity": "+%.2f percentage points of Critical Chance for Dexterity attacks" % Progression.BALANCE.critical_chance_per_dexterity,
		&"intelligence": "+%.2f Maximum Mana" % Progression.BALANCE.mana_per_intelligence,
	}
	for attribute: StringName in PRIMARY_ATTRIBUTES:
		var information: Array = PRIMARY_ATTRIBUTES[attribute]
		var controls := attributes.get_node("%s/Controls" % information[0]) as HBoxContainer
		_attribute_values[attribute] = controls.get_node("Value") as Label
		var allocate := controls.get_node("Allocate") as Button
		allocate.tooltip_text = "Per point\n+%.2f%% base damage for %s\n%s" % [
			Progression.BALANCE.damage_per_point * 100.0, information[1], attribute_bonuses[attribute],
		]
		allocate.pressed.connect(_allocate_attribute.bind(attribute))
		_attribute_buttons[attribute] = allocate
	_attribute_reset.pressed.connect(_reset_attributes)


func _update_progression() -> void:
	_progression_panel.visible = _progression != null
	if _progression == null:
		return
	_character_level.text = "Level %d" % _progression.level
	var needed := _progression.xp_for_next_level()
	_experience_label.text = "%d / %d XP" % [_progression.xp, needed] if needed > 0 else "Max level"
	if _allow_attribute_reset:
		_experience_label.text = "Training"
	_experience_bar.visible = not _allow_attribute_reset
	_experience_bar.max_value = maxi(1, needed)
	_experience_bar.value = _progression.xp if needed > 0 else 1
	var points := _progression.points_available()
	_attribute_points.text = "%d attribute point%s available" % [points, "" if points == 1 else "s"]
	_attribute_points.add_theme_color_override("font_color", GOLD if points > 0 else QUIET)
	var has_allocated := false
	for attribute: StringName in PRIMARY_ATTRIBUTES:
		var amount := _progression.attribute(attribute)
		_attribute_values[attribute].text = str(amount)
		_attribute_buttons[attribute].disabled = points == 0
		has_allocated = has_allocated or amount > 0
	_attribute_reset.visible = _allow_attribute_reset
	_attribute_reset.disabled = not has_allocated


func _allocate_attribute(attribute: StringName) -> void:
	if _progression != null and _progression.allocate(attribute):
		refresh_progression()
		attributes_changed.emit()


func _reset_attributes() -> void:
	if _progression == null or not _allow_attribute_reset or _attribute_reset.disabled:
		return
	_progression.reset_attributes()
	refresh_progression()
	attributes_changed.emit()


func _refresh() -> void:
	if _inventory == null or not is_open() or not is_node_ready():
		return
	_gold.text = str(_inventory.gold)
	_bag_grid.selected = _selected if _mode == "smith" else &""
	_bag_grid.queue_redraw()
	if _mode == "vendor":
		_vendor_grid.queue_redraw()
	if _mode == "stash":
		_stash_grid.queue_redraw()
	_dismiss_item_tooltip()
	if _mode == "smith":
		_update_smith()
	else:
		for tile: EquipmentSlot in _slots.values():
			tile.refresh()
	if _mode == "inventory":
		_update_progression()
		_update_stats()


func _select_item(id: StringName, endpoint: String) -> void:
	if endpoint != "bag" or _mode != "smith":
		return
	var item := _inventory.get_item(id)
	_selected = &"" if item.has("supply_kind") or item.get("unidentified", false) else id
	_feedback.text = ""
	_refresh()


func _update_stats() -> void:
	for section: VBoxContainer in _stats.get_children():
		var rows := section.get_node("Rows")
		for child: Node in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
	var totals := Items.player_stats(_inventory.equipment, _progression)
	var min_damage := float(totals.get("damage_min", 0))
	var max_damage := float(totals.get("damage_max", 0))
	(_stat_overview.get_node("Damage/Body/Value") as Label).text = Items.physical_damage_range(min_damage, max_damage)
	var shown := {"damage_min": true, "damage_max": true}
	for name: String in OVERVIEW_STATS:
		var stat: String = OVERVIEW_STATS[name]
		(_stat_overview.get_node("%s/Body/Value" % name) as Label).text = Items.stat_value(stat, totals[stat])
		shown[stat] = true
	for group: String in STAT_GROUPS:
		var rows := _stats.get_node("%s/Rows" % group) as VBoxContainer
		for stat: String in STAT_GROUPS[group]:
			if totals.has(stat):
				_stat_row(rows, stat, totals[stat])
				shown[stat] = true
	var other := _stats.get_node("Other/Rows") as VBoxContainer
	for stat: String in totals:
		if not shown.has(stat):
			_stat_row(other, stat, totals[stat])


func _stat_row(parent: VBoxContainer, stat: String, amount: float) -> void:
	var row := STAT_ROW_SCENE.instantiate() as HBoxContainer
	(row.get_node("Caption") as Label).text = Items.stat_label(stat)
	var value := row.get_node("Value") as Label
	value.text = Items.stat_value(stat, amount)
	value.add_theme_color_override("font_color", QUIET if is_zero_approx(amount) else PAPER)
	parent.add_child(row)


func _update_smith() -> void:
	var item := _inventory.get_item(_selected)
	_smith_target.text = "No gear selected" if item.is_empty() else Items.visible_name(item)
	_smith_target.add_theme_color_override("font_color", Items.item_color(item.get("rarity", "normal")))
	_smith_item_art.texture = Art.texture_for_item(item)
	var parts := PackedStringArray()
	for id: String in _inventory.materials:
		parts.append("%s ×%d" % [Items.material_name(id), _inventory.materials[id]])
	parts.sort()
	_materials.text = "Materials • " + ("None gathered" if parts.is_empty() else "  ·  ".join(parts))
	for recipe: Dictionary in Items.recipes():
		var button: Button = _recipes[recipe["id"]]
		var requirements := PackedStringArray()
		for id: String in recipe["materials"]:
			requirements.append("%d %s" % [recipe["materials"][id], Items.material_name(id)])
		button.text = "%s   ·   %s" % [recipe["name"], ", ".join(requirements)]
		button.tooltip_text = _recipe_tooltip(item, recipe, requirements)
		button.disabled = item.is_empty() or not Items.can_craft(item, recipe["id"], _inventory.materials)


func _recipe_tooltip(item: Dictionary, recipe: Dictionary, requirements: PackedStringArray) -> String:
	var text := String(recipe.get("description", "")) + "\n" + "\n".join(requirements)
	if item.is_empty() or item.get("unidentified", false):
		return text
	var result := Items.craft(item, recipe["id"])
	if result.is_empty():
		return text + "\n\nThis item cannot hold the affix."
	var original: Dictionary = item.get("stats", {})
	var revised: Dictionary = result.get("stats", {})
	var bonuses := PackedStringArray()
	for stat: String in revised:
		var bonus := float(revised[stat]) - float(original.get(stat, 0.0))
		if not is_zero_approx(bonus):
			bonuses.append("%s %s" % [Items.stat_value(stat, bonus), Items.stat_label(stat)])
	if not bonuses.is_empty():
		text += "\n\n" + "\n".join(bonuses)
	return text


func _craft(recipe_id: String) -> void:
	var denial := _inventory.craft_item(_selected, recipe_id)
	var forged := _inventory.get_item(_selected)
	var message := "Forged %s." % forged.get("name", "the item") if denial.is_empty() else denial
	_show_feedback(message, denial.is_empty())


func _show_feedback(message: String, success: bool) -> void:
	_feedback.text = message
	_feedback.add_theme_color_override("font_color", GOLD if success else ERROR_COLOR)
