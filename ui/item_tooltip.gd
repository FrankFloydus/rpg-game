extends Control
## Immediate, non-interactive item details and loadout comparison at the pointer.

const Items := preload("res://systems/items.gd")
const Art := preload("res://ui/item_art.gd")
const MenuFrame := preload("res://ui/menu_frame.gd")
const Supplies := preload("res://systems/pack_supplies.gd")
const CardItems := preload("res://systems/card_items.gd")
const PANE_SCENE := preload("res://ui/item_tooltip_pane.tscn")

const PANEL_WIDTH := 328.0
const CURSOR_GAP := 19.0
const SCREEN_MARGIN := 8.0
const PAPER := MenuFrame.TEXT
const MUTED := MenuFrame.MUTED
const GOLD := Color("#d4ae77")
const BONUS := Color("#aed2a3")
const PENALTY := Color("#ee9c87")

var _item: Dictionary = {}
var _comparisons: Array[Dictionary] = []
var _cursor := Vector2.ZERO
var _buy_price := -1
var _advanced := false

@onready var _panes: HBoxContainer = $Panes


func _ready() -> void:
	_panes.minimum_size_changed.connect(_position_panes)
	get_viewport().size_changed.connect(_viewport_resized)
	visibility_changed.connect(_visibility_changed)
	hide()
	set_process(false)


func present(item: Dictionary, comparisons: Array[Dictionary], cursor: Vector2, buy_price: int = -1) -> void:
	if item.is_empty():
		dismiss()
		return
	_item = item
	_comparisons = []
	if not item.get("unidentified", false):
		for compared in comparisons:
			if not compared.get("unidentified", false):
				_comparisons.append(compared)
	_cursor = cursor
	_buy_price = buy_price
	_advanced = Input.is_key_pressed(KEY_ALT)
	_rebuild()
	show()
	set_process(is_visible_in_tree())
	_position_panes()


func follow(cursor: Vector2) -> void:
	if cursor.is_equal_approx(_cursor):
		return
	_cursor = cursor
	if is_visible_in_tree():
		_position_panes()


func dismiss() -> void:
	_item = {}
	_comparisons = []
	hide()
	set_process(false)


func _visibility_changed() -> void:
	set_process(is_visible_in_tree() and not _item.is_empty())


func _viewport_resized() -> void:
	if is_visible_in_tree():
		_rebuild()
		_position_panes()


func _process(_delta: float) -> void:
	var advanced := Input.is_key_pressed(KEY_ALT)
	if advanced != _advanced:
		_advanced = advanced
		_rebuild()
		_position_panes()


func _rebuild() -> void:
	for child: Node in _panes.get_children():
		_panes.remove_child(child)
		child.queue_free()
	var width := get_viewport().get_visible_rect().size.x - 2.0 * SCREEN_MARGIN
	var count := 1 + _comparisons.size()
	var tooltip_width := minf(PANEL_WIDTH, (width - (count - 1) * 7.0) / count)
	_build_item(_add_pane(tooltip_width, _trim(_item)), _item, {}, _buy_price)
	for compared: Dictionary in _comparisons:
		var deltas := Items.item_comparison_deltas(_item, compared)
		_build_item(_add_pane(tooltip_width, _trim(compared)), compared, deltas, -1)


static func _trim(item: Dictionary) -> Color:
	var rarity := String(item.get("rarity", "normal"))
	return GOLD if rarity == "normal" else Items.item_color(rarity)


func _build_item(pane: PanelContainer, item: Dictionary, deltas: Dictionary, buy_price: int) -> void:
	var body: VBoxContainer = pane.get_node("Body")
	var icon_frame: PanelContainer = body.get_node("Header/IconFrame")
	var icon: TextureRect = icon_frame.get_node("Icon")
	icon.texture = Art.texture_for_item(item)
	icon_frame.visible = icon.texture != null
	var title: Label = body.get_node("Header/Heading/Title")
	title.text = Items.visible_name(item)
	title.add_theme_color_override("font_color", Items.item_color(item["rarity"]).lightened(0.14))
	var subtitle: Label = body.get_node("Header/Heading/Subtitle")
	var rows: VBoxContainer = body.get_node("Rows")
	var price: VBoxContainer = body.get_node("Price")
	price.visible = buy_price >= 0
	var price_value: Label = price.get_node("Pair/Value")
	price_value.text = "%d gold" % buy_price if price.visible else ""
	price_value.add_theme_color_override("font_color", GOLD)
	var supply := String(item.get("supply_kind", ""))
	if CardItems.is_card(item):
		_build_card_details(rows, subtitle, item)
		return
	if not supply.is_empty():
		if supply == Supplies.UNVEILING_SCROLL:
			subtitle.text = "Identification scroll"
			rows.add_child(_divider())
			rows.add_child(_label("Right-click this Seal, then click an unidentified item in your pack.", 14, PAPER))
		else:
			subtitle.text = "Dungeon key" if supply in [Supplies.TREASURE_KEY, Supplies.ROUTE_KEY] else "Crafting material"
		if Supplies.can_stack(item):
			rows.add_child(_label("Stack %d / %d" % [Supplies.quantity(item), Supplies.STACK_LIMIT], 14, PAPER))
		return
	subtitle.text = Items.item_subtitle(item)
	if item.get("unidentified", false):
		rows.add_child(_divider())
		rows.add_child(_label("Unidentified", 15, GOLD))
		rows.add_child(_label("Reveal its affixes with a Scribe's Seal.", 14, PAPER))
		return
	var previous_kind := ""
	for section in Items.tooltip_sections(item, _advanced):
		var kind: String = section["kind"]
		if previous_kind != kind:
			rows.add_child(_divider())
		previous_kind = kind
		var caption: String = section["caption"]
		if not caption.is_empty():
			rows.add_child(_label(caption, 13, GOLD))
		var lines: PackedStringArray = section["lines"]
		var keys: PackedStringArray = section.get("stats", PackedStringArray())
		for index: int in lines.size():
			var stat := keys[index] if index < keys.size() else ""
			rows.add_child(_stat_line(lines[index], stat, deltas))



func _build_card_details(rows: VBoxContainer, subtitle: Label, item: Dictionary) -> void:
	var unidentified: bool = item.get("unidentified", false)
	subtitle.text = "Expedition card" if unidentified else "%s expedition card" % String(item["rarity"]).capitalize()
	rows.add_child(_divider())
	if unidentified:
		rows.add_child(_label("Reveal it with a Scribe's Seal.", 14, PAPER))
	else:
		rows.add_child(_label(String(item.get("description", "")), 15, PAPER))
		rows.add_child(_label("Right-click from your pack to learn.", 14, MUTED))


func _stat_line(line: String, stat: String, deltas: Dictionary) -> Control:
	var stats := [stat]
	if stat == "damage_range":
		stats = ["damage_min", "damage_max"]
	var shared: Array[String] = []
	for key: String in stats:
		if deltas.has(key):
			shared.append(key)
	if shared.is_empty():
		return _label(line, 15, PAPER)
	var row := RichTextLabel.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_theme_font_size_override("normal_font_size", 15)
	row.add_theme_color_override("default_color", PAPER)
	row.add_text(line + " (")
	for index: int in shared.size():
		var key: String = shared[index]
		var delta: float = deltas[key]
		deltas.erase(key)
		if index > 0:
			row.add_text(" / ")
		row.push_color(BONUS if delta > 0.0 else PENALTY)
		row.add_text(("+" if delta > 0.0 else "-") + Items.stat_value(key, absf(delta)))
		row.pop()
	row.add_text(")")
	return row


func _add_pane(width: float, trim: Color) -> PanelContainer:
	var pane: PanelContainer = PANE_SCENE.instantiate()
	pane.custom_minimum_size.x = width
	pane.add_theme_stylebox_override(&"panel", MenuFrame.well(13.0, 11.0, MenuFrame.WELL, MenuFrame.LINE.lerp(trim, 0.24)))
	_panes.add_child(pane)
	return pane


func _position_panes() -> void:
	if not is_visible_in_tree():
		return
	var rect := get_viewport().get_visible_rect().grow(-SCREEN_MARGIN)
	var extent := _panes.get_combined_minimum_size()
	_panes.size = extent
	var right := _cursor.x + CURSOR_GAP
	var left := _cursor.x - extent.x - CURSOR_GAP
	var bottom := _cursor.y + CURSOR_GAP
	var top := _cursor.y - extent.y - CURSOR_GAP
	var position_viewport := Vector2(right, bottom)
	if right + extent.x > rect.end.x:
		position_viewport.x = left if left >= rect.position.x else _cursor.x - extent.x * 0.5
	if bottom + extent.y > rect.end.y:
		position_viewport.y = top
	position_viewport.x = clampf(position_viewport.x, rect.position.x, maxf(rect.position.x, rect.end.x - extent.x))
	position_viewport.y = clampf(position_viewport.y, rect.position.y, maxf(rect.position.y, rect.end.y - extent.y))
	_panes.position = get_global_transform_with_canvas().affine_inverse() * position_viewport


func _divider() -> HSeparator:
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

