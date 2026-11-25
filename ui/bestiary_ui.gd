extends Control
## A field guide for creatures the player has encountered.

signal back_requested

const Bestiary := preload("res://data/bestiary.gd")
const MenuFrame := preload("res://ui/menu_frame.gd")
const PortraitCard := preload("res://ui/bestiary_portrait_card.gd")
const EntryGlyph := preload("res://ui/bestiary_entry_glyph.gd")
const PORTRAIT_CARD := preload("res://ui/bestiary_portrait_card.tscn")
const ABILITY_GROUP := preload("res://ui/bestiary_ability_group.tscn")
const ABILITY_CHIP := preload("res://ui/bestiary_ability_chip.tscn")
const GOLD := MenuFrame.TEXT
const PAPER := MenuFrame.TEXT
const MUTED := MenuFrame.MUTED
const DIM := MenuFrame.DIM
const ARCANE := Color("#bc9cdc")

@export var maximum_window_size := Vector2(1170.0, 776.0)
@export var minimum_card_width := 188.0
@export var stacked_detail_width := 805.0

var _discovered: Dictionary = {}
var _show_all := false
var _active_id := -1
var _grid_scroll := 0
var _restore_grid_pending := false
var _cards: Array[PortraitCard] = []
var _description_owner: Button

@onready var _window: PanelContainer = %Window
@onready var _count: Label = %Count
@onready var _back_button: Button = %Back
@onready var _scroll: ScrollContainer = %Scroll
@onready var _inset: MarginContainer = $Window/Layout/Scroll/Inset
@onready var _grid: GridContainer = %Entries
@onready var _detail: BoxContainer = %Detail
@onready var _portrait_column: VBoxContainer = %PortraitColumn
@onready var _big_portrait: PortraitCard = %Portrait
@onready var _creature_name: Label = %CreatureName
@onready var _classification: Label = %Classification
@onready var _lore: Label = %Lore
@onready var _ability_groups: VBoxContainer = %AbilityGroups
@onready var _description: PanelContainer = %Description
@onready var _description_title: Label = %DescriptionTitle
@onready var _description_text: Label = %DescriptionText
@onready var _description_icon: TextureRect = %DescriptionIcon


func _ready() -> void:
	_back_button.pressed.connect(back)
	var scrollbar := _scroll.get_v_scroll_bar()
	scrollbar.changed.connect(_restore_grid_position)
	scrollbar.value_changed.connect(_dismiss_on_scroll)
	_description.minimum_size_changed.connect(_position_description)
	resized.connect(_reflow)
	hide()


func present(discovered: Dictionary, show_all := false) -> void:
	_discovered = discovered.duplicate()
	_show_all = show_all
	_grid_scroll = 0
	_active_id = -1
	_build_grid()
	show()
	_reflow()
	_show_grid()


func close() -> void:
	_hide_description()
	hide()


func is_open() -> bool:
	return visible


func back() -> void:
	if not is_open():
		return
	if _active_id >= 0:
		_show_grid()
	else:
		close()
		back_requested.emit()


func _build_grid() -> void:
	_clear_children(_grid)
	_cards.clear()
	for id in Bestiary.entry_count():
		var known := _is_known(id)
		var card := PORTRAIT_CARD.instantiate() as PortraitCard
		card.disabled = not known
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if known else Control.CURSOR_ARROW
		var caption := "Unidentified"
		if known:
			caption = String(Bestiary.entry(id).get("name", "Unidentified"))
			card.portrait = Bestiary.portrait_texture(id)
			card.pressed.connect(_show_entry.bind(id))
		card.accessibility_name = caption
		var label := card.get_node("Caption") as Label
		label.text = caption
		if not known:
			label.add_theme_color_override("font_color", MenuFrame.DIM)
		_grid.add_child(card)
		_cards.append(card)


func _show_grid() -> void:
	_hide_description()
	_active_id = -1
	_back_button.text = "Back to Settings"
	var known := 0
	for card in _cards:
		if not card.disabled:
			known += 1
	_count.text = "%d entries available" % known if _show_all else "%d of %d discovered" % [known, Bestiary.entry_count()]
	_count.visible = _window.size.x >= 670.0
	_detail.hide()
	_grid.show()
	_resize_grid()
	_restore_grid_pending = _grid_scroll > 0
	if _restore_grid_pending:
		_restore_grid_position.call_deferred()
	else:
		_scroll.scroll_vertical = 0


func _restore_grid_position() -> void:
	if not _restore_grid_pending or _active_id >= 0:
		return
	# Wait for the larger grid to replace the detail page in the scroll range.
	var scroll_height := _grid.get_combined_minimum_size().y
	var bar := _scroll.get_v_scroll_bar()
	if scroll_height > _scroll.size.y and bar.max_value < scroll_height:
		return
	_restore_grid_pending = false
	_scroll.scroll_vertical = _grid_scroll


func _show_entry(id: int) -> void:
	if id < 0 or id >= Bestiary.entry_count() or not _is_known(id):
		return
	if _active_id < 0:
		_grid_scroll = _scroll.scroll_vertical
	_hide_description()
	_restore_grid_pending = false
	_active_id = id
	_back_button.text = "Back to Bestiary"
	_count.hide()
	_grid.hide()
	var entry := Bestiary.entry(id)
	_creature_name.text = String(entry.get("name", ""))
	_big_portrait.portrait = Bestiary.portrait_texture(id)
	_big_portrait.accessibility_name = "%s portrait" % _creature_name.text
	var distance := "Ranged" if bool(entry.get("ranged", false)) else "Melee"
	var element := String(entry.get("attack_type", "physical")).capitalize()
	var depth := int(entry.get("min_depth", 1))
	_classification.text = "%s   ·   %s   ·   Found from Depth %d" % [distance, element, depth]
	_lore.text = String(entry.get("lore", ""))
	_clear_children(_ability_groups)
	_add_group("Moves", entry.get("abilities", []), MenuFrame.TEXT)
	_add_group("Innate effects", entry.get("traits", []), MenuFrame.TEXT)
	_add_group("Possible magic and rare affixes", entry.get("buffs", []), ARCANE)
	_resize_portrait()
	_detail.show()
	_scroll.set_deferred("scroll_vertical", 0)


func _add_group(heading: String, entries: Array, tint: Color) -> void:
	if entries.is_empty():
		return
	var group := ABILITY_GROUP.instantiate() as VBoxContainer
	(group.get_node("Title") as Label).text = heading
	var flow := group.get_node("Chips") as HFlowContainer
	_ability_groups.add_child(group)
	for detail: Dictionary in entries:
		var chip := ABILITY_CHIP.instantiate() as Button
		var caption := String(detail.get("name", ""))
		chip.accessibility_name = caption
		chip.accessibility_description = String(detail.get("tooltip", ""))
		var icon := chip.get_node("Layout/Glyph") as EntryGlyph
		icon.key = String(detail.get("icon", ""))
		icon.texture = detail.get("texture") as Texture2D
		icon.tint = Color("#ea7466") if icon.key == "briar_guard" else tint
		var name_label := chip.get_node("Layout/Name") as Label
		name_label.text = caption
		chip.custom_minimum_size.x = ceili(name_label.get_minimum_size().x) + 59
		chip.mouse_entered.connect(_show_description.bind(chip, detail))
		chip.mouse_exited.connect(_clear_description_owner.bind(chip))
		chip.focus_entered.connect(_show_description.bind(chip, detail))
		chip.focus_exited.connect(_clear_description_owner.bind(chip))
		chip.pressed.connect(_show_description.bind(chip, detail))
		flow.add_child(chip)


func _show_description(anchor_button: Button, entry: Dictionary) -> void:
	_description_owner = anchor_button
	_description_icon.texture = entry.get("texture") as Texture2D
	_description_icon.visible = _description_icon.texture != null
	_description_title.text = String(entry.get("name", ""))
	_description_text.text = String(entry.get("tooltip", ""))
	_description.reset_size()
	_description.show()
	_position_description()
	_position_description.call_deferred()


func _position_description() -> void:
	if not _description.visible or not is_instance_valid(_description_owner):
		return
	var source := _description_owner.get_global_rect()
	var point := get_global_transform().affine_inverse() * Vector2(source.position.x, source.end.y + 8.0)
	var box_size := _description.get_combined_minimum_size()
	if point.y + box_size.y + 10.0 > size.y:
		point.y -= source.size.y + box_size.y + 16.0
	point.x = clampf(point.x, 10.0, maxf(10.0, size.x - box_size.x - 10.0))
	point.y = clampf(point.y, 10.0, maxf(10.0, size.y - box_size.y - 10.0))
	_description.position = point


func _hide_description() -> void:
	_description_owner = null
	_description.hide()


func _clear_description_owner(anchor_button: Button) -> void:
	if anchor_button == _description_owner:
		_hide_description()


func _dismiss_on_scroll(_value: float) -> void:
	_hide_description()


static func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _is_known(id: int) -> bool:
	return _show_all or bool(_discovered.get(id, false))


func _reflow() -> void:
	if not is_instance_valid(_window):
		return
	var desired := (size - Vector2(62.0, 64.0)).clamp(Vector2(410.0, 350.0), maximum_window_size)
	_window.position = ((size - desired) * 0.5).round()
	_window.size = desired
	_count.visible = _active_id < 0 and desired.x >= 670.0
	if _active_id < 0:
		_resize_grid()
	else:
		_resize_portrait()
	_position_description()


func _resize_grid() -> void:
	var panel_style := _window.get_theme_stylebox("panel")
	var frame_width := panel_style.get_minimum_size().x
	var inset_width := _inset.get_theme_constant("margin_left") + _inset.get_theme_constant("margin_right")
	var scrollbar_width := _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var width := _window.size.x - frame_width - inset_width - scrollbar_width - 14.0
	var gap := _grid.get_theme_constant("h_separation")
	_grid.columns = clampi(floori((width + gap) / (minimum_card_width + gap)), 2, 5)
	var cell := floorf((width - gap * (_grid.columns - 1)) / _grid.columns)
	for card in _cards:
		card.custom_minimum_size = Vector2(cell, cell + 31.0)


func _resize_portrait() -> void:
	var stacked := _window.size.x < stacked_detail_width
	_detail.vertical = stacked
	_portrait_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if stacked else Control.SIZE_FILL
	var side := clampf(_window.size.x - 76.0, 228.0, 370.0) if stacked else clampf(_window.size.x * 0.35, 242.0, 394.0)
	_big_portrait.custom_minimum_size = Vector2(side, side)


static func _rule() -> HSeparator:
	var rule := HSeparator.new()
	var style := StyleBoxLine.new()
	style.color = MenuFrame.LINE
	style.thickness = 1
	rule.add_theme_stylebox_override("separator", style)
	return rule


static func _box(fill: Color, edge: Color, border: int, horizontal: float,
		vertical: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(border)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style
