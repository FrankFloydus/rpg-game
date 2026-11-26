@tool
extends Control
## Paints item footprints and routes Godot drag events through the checked game model.

signal item_selected(id: StringName)
signal action_feedback(message: String, success: bool)
signal cursor_swapped(placement: Dictionary, viewport_position: Vector2)

const Items := preload("res://systems/items.gd")
const Inventory := preload("res://systems/inventory.gd")
const Art := preload("res://ui/item_art.gd")
const Supplies := preload("res://systems/pack_supplies.gd")
const InventorySounds := preload("res://ui/inventory_sounds.gd")
const MenuFrame := preload("res://ui/menu_frame.gd")
const Appearance := preload("res://ui/inventory_appearance.gd")

var inventory: Inventory
@export var endpoint := "bag"
@export_range(12, 84) var cell_size := 38:
	set(value):
		cell_size = value
		if Engine.is_editor_hint() and is_node_ready():
			_update_editor_size()
## The empty grid shown in the editor. At runtime the inventory supplies its exact dimensions.
@export var authored_cells := Vector2i(12, 6):
	set(value):
		authored_cells = value
		if Engine.is_editor_hint() and is_node_ready():
			_update_editor_size()
var selected: StringName = &""
var carried_id: StringName = &""
var allow_quick_actions := true
var _hover := Vector2i(-1, -1)
var _target := Rect2i()
var _swap_target := Rect2i()
var _target_ok := false
var _search_filter: Callable


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_size()
		return
	Appearance.LIVE.changed.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_exited.connect(_clear_preview)
	resized.connect(queue_redraw)


func _update_editor_size() -> void:
	custom_minimum_size = Vector2(authored_cells * cell_size)
	queue_redraw()


func set_grid_size(cells: Vector2i, pixels: int) -> void:
	cell_size = pixels
	custom_minimum_size = Vector2(cells * cell_size)
	queue_redraw()


func set_search_filter(filter: Callable) -> void:
	_search_filter = filter
	queue_redraw()


func _draw() -> void:
	var grid: SpatialInventory = inventory.get_grid(endpoint) if inventory != null else null
	var bounds := grid.get_grid_size() if grid != null else authored_cells
	var surface := Rect2(Vector2.ZERO, Vector2(bounds * cell_size))
	draw_rect(surface, MenuFrame.WELL)
	for y: int in bounds.y:
		for x: int in bounds.x:
			var cell := Vector2i(x, y)
			if grid != null and not grid.get_item_at(cell).is_empty():
				continue
			var frame := Rect2(Vector2(cell * cell_size), Vector2.ONE * cell_size).grow(-0.5)
			if cell == _hover:
				draw_rect(frame, MenuFrame.HOVER)
			draw_rect(frame, MenuFrame.BORDER if cell == _hover else MenuFrame.LINE, false, 1.0)
	if grid == null:
		return
	for placement: Dictionary in grid.get_placements():
		var id: StringName = placement["id"]
		var item := inventory.get_item(id)
		var extent := _extent(placement)
		var box := Rect2(Vector2(placement["origin"]) * cell_size, Vector2(extent) * cell_size).grow(-1)
		var price := Inventory.buy_price(item) if endpoint == "vendor" else 0
		var hovered := Rect2i(placement["origin"], extent).has_point(_hover)
		paint_tile(self, box, item, price, id == selected or hovered)
		if _search_filter.is_valid():
			if _search_filter.call(item):
				draw_rect(box.grow(-1), Color("#d4a65d"), false, 1.6)
			else:
				draw_rect(box, Color("#0f0d0cbd"))
		if id == carried_id:
			draw_rect(box, Color("#14100dd0"))
	if not _target.has_area():
		return
	var origin := Vector2(_target.position * cell_size)
	var target_extent := Vector2(_target.size * cell_size)
	Appearance.paint_drop(self, Rect2(origin, target_extent), Appearance.LIVE, _target_ok)
	if _swap_target.has_area():
		Appearance.paint_swap(self, Rect2(Vector2(_swap_target.position * cell_size),
			Vector2(_swap_target.size * cell_size)), Appearance.LIVE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var next := cell_at(event.position)
		if _hover != next:
			_hover = next
			queue_redraw()
	if not event is InputEventMouseButton or not event.pressed or inventory == null:
		return
	var id := inventory.get_grid(endpoint).get_item_at(cell_at(event.position))
	if event.button_index == MOUSE_BUTTON_LEFT:
		item_selected.emit(id)
	if not allow_quick_actions or id.is_empty() or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := inventory.get_item(id)
	var denial := inventory.quick_purchase(id) if endpoint == "vendor" else inventory.quick_equip(id)
	if denial.is_empty():
		InventorySounds.place(self, item)
	var success_text := "Purchased %s." if endpoint == "vendor" else "Equipped %s."
	action_feedback.emit(success_text % Items.visible_name(item) if denial.is_empty() else denial, denial.is_empty())
	accept_event()


func item_at(at_position: Vector2) -> StringName:
	if inventory == null:
		return &""
	return inventory.get_grid(endpoint).get_item_at(cell_at(at_position))


func carry_data_at(at_position: Vector2) -> Dictionary:
	var id := item_at(at_position)
	if id.is_empty():
		return {}
	var placement := inventory.get_grid(endpoint).get_placement(id)
	return {
		"inventory_item": true, "id": id, "source": endpoint,
		"size": _extent(placement),
	}


func _get_drag_data(at_position: Vector2) -> Variant:
	var data := carry_data_at(at_position)
	if data.is_empty():
		return null
	set_drag_preview(make_drag_preview(inventory.get_item(data["id"]), data["size"], cell_size))
	return data


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if inventory == null or not data is Dictionary or data.get("inventory_item") != true:
		return false
	var area := drop_cells(at_position, data["size"])
	_target = area.intersection(Rect2i(Vector2i.ZERO, inventory.get_grid(endpoint).get_grid_size()))
	var plan := preview_grid_cursor_drop(area, data)
	_target_ok = plan.denial.is_empty()
	_swap_target = swap_cells(area, plan.displaced) if _target_ok else Rect2i()
	queue_redraw()
	return _target_ok


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var id: StringName = data["id"]
	var item := inventory.get_item(id)
	var buying: bool = data["source"] == "vendor"
	var selling := endpoint == "vendor"
	var price := Inventory.buy_price(item) if buying else Inventory.sell_price(item)
	var origin := drop_cells(at_position, data["size"]).position
	var denial: String
	if _can_swap_from(data):
		var result := inventory.place_backpack_cursor(id, origin)
		denial = result.denial
		if denial.is_empty() and not result.displaced.is_empty():
			cursor_swapped.emit(result.displaced, get_global_transform_with_canvas() * at_position)
	else:
		denial = inventory.drop_item(data["source"], id, endpoint, origin)
	if denial.is_empty():
		InventorySounds.place(self, item)
	if not denial.is_empty():
		action_feedback.emit(denial, false)
	elif buying or selling:
		var action := "Purchased" if buying else "Sold"
		action_feedback.emit("%s %s for %d gold." % [action, Items.visible_name(item), price], true)
	elif data["source"] == "equipment":
		action_feedback.emit("Returned %s to your pack." % Items.visible_name(item), true)
	elif data["source"] != endpoint and (Inventory.Stash.is_owner(endpoint) or Inventory.Stash.is_owner(data["source"])):
		var action := "Withdrew" if endpoint == "bag" else "Stored"
		action_feedback.emit("%s %s." % [action, Items.visible_name(item)], true)
	_clear_preview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_preview()


func cell_at(at_position: Vector2) -> Vector2i:
	return Vector2i((at_position / float(cell_size)).floor())


## Select the nearest position for the item's center, then keep its full footprint inside the grid.
func drop_cells(at_position: Vector2, footprint: Vector2i) -> Rect2i:
	if endpoint == "vendor":
		return Rect2i(cell_at(at_position), Vector2i.ONE)
	var origin := cell_at(at_position - Vector2(footprint - Vector2i.ONE) * cell_size * 0.5)
	var last_origin := inventory.get_grid(endpoint).get_grid_size() - footprint
	if last_origin.x >= 0 and last_origin.y >= 0:
		origin = origin.clamp(Vector2i.ZERO, last_origin)
	return Rect2i(origin, footprint)


func preview_grid_drop(at_position: Vector2, data: Dictionary) -> String:
	return preview_grid_cursor_drop(drop_cells(at_position, data["size"]), data).denial


func preview_grid_cursor_drop(area: Rect2i, data: Dictionary) -> Dictionary:
	if _can_swap_from(data):
		return inventory.backpack_cursor_preview(data["id"], area.position)
	return {"denial": inventory.preview_drop(data["source"], data["id"], endpoint, area.position), "displaced": &""}


func swap_cells(area: Rect2i, displaced: StringName) -> Rect2i:
	if displaced.is_empty():
		return Rect2i()
	var placement := inventory.get_grid(endpoint).get_placement(displaced)
	return Rect2i() if placement.is_empty() else area.intersection(Rect2i(placement.origin, placement.footprint))


func _can_swap_from(data: Dictionary) -> bool:
	return endpoint == "bag" and data["source"] == "bag" and cursor_swapped.has_connections()


static func make_drag_preview(item: Dictionary, footprint: Vector2i, pixels: int) -> Control:
	var preview := Control.new()
	var tile := DragTile.new()
	tile.item = item
	tile.size = Vector2(footprint * pixels)
	tile.position = -tile.size * 0.5
	preview.add_child(tile)
	return preview


func _clear_preview() -> void:
	_hover = Vector2i(-1, -1)
	_target = Rect2i()
	_swap_target = Rect2i()
	queue_redraw()


static func _extent(placement: Dictionary) -> Vector2i:
	return placement["footprint"]


static func item_art_bounds(tile: Rect2, price := 0) -> Rect2:
	var art := tile.grow(-3.0)
	if price > 0:
		art.size.y -= 15.0
	return art


static func paint_tile(canvas: Control, box: Rect2, item: Dictionary, price := 0, highlighted := false) -> void:
	Appearance.paint_placed(canvas, box, Appearance.LIVE, item.get("unidentified", false), highlighted)
	paint_item_art(canvas, item_art_bounds(box, price), item)
	_paint_quantity(canvas, box, item, price)
	if price > 0:
		_paint_price(canvas, box, price)


static func paint_item_art(canvas: Control, box: Rect2, item: Dictionary) -> void:
	if item.is_empty():
		return
	var icon := Art.texture_for_item(item)
	if icon != null:
		var extent := icon.get_size()
		var fit := minf(box.size.x / extent.x, box.size.y / extent.y)
		var draw_size := extent * fit
		canvas.draw_texture_rect(icon, Rect2(box.get_center() - draw_size * 0.5, draw_size), false)
	else:
		_paint_symbol(canvas, box, String(item.get("type", "")))


static func _paint_quantity(canvas: Control, box: Rect2, item: Dictionary, price: int, floating := false) -> void:
	var quantity := Supplies.quantity(item)
	if quantity <= 1:
		return
	var font := canvas.get_theme_font(&"font", &"GearValue")
	var count := str(quantity)
	var width := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var baseline := Vector2(box.end.x - width - 5, box.end.y - (19 if price > 0 else 4))
	if floating:
		canvas.draw_string_outline(font, baseline, count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color("#100c08"))
	else:
		canvas.draw_rect(Rect2(baseline - Vector2(3, 12), Vector2(width + 6, 15)), Color("#100c08d9"))
	canvas.draw_string(font, baseline, count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#f8e4b6"))


static func _paint_price(canvas: Control, box: Rect2, price: int) -> void:
	var font := canvas.get_theme_font(&"font", &"GearValue")
	var cost := str(price)
	var width := font.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var plate := Rect2(Vector2(box.position.x + 1.0, box.end.y - 16.0), Vector2(box.size.x - 2.0, 15.0))
	canvas.draw_rect(plate, Color("#21180f"))
	canvas.draw_line(plate.position, Vector2(plate.end.x, plate.position.y), Color("#6c5236"), 1.0)
	canvas.draw_string(font, Vector2(box.get_center().x - width * 0.5 - 5, box.end.y - 4), cost,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ecd4a5"))
	var coin_center := Vector2(box.get_center().x + width * 0.5 + 2, box.end.y - 8)
	canvas.draw_circle(coin_center, 3.2, Color("#8b6b3f"), true, -1.0, true)
	canvas.draw_circle(coin_center - Vector2(0.3, 0.3), 2.0, Color("#d7b17a"), true, -1.0, true)


static func _paint_symbol(canvas: Control, box: Rect2, type: String) -> void:
	var edge := Color("#211915")
	var steel := Color("#a9a19a")
	var shine := Color("#e2d5b5")
	var shadow := Color("#68605c")
	var gem := Color("#a39780")
	var bronze := Color("#936a3e")
	var gold := Color("#d5a76f")
	var leather := Color("#5e4030")
	var symbol := type.get_slice("_", 0)
	var tall := symbol in ["sword", "axe", "mace", "staff", "dagger"]
	var icon_size := minf(box.size.x, box.size.y) * 0.97
	if tall:
		icon_size = minf(maxf(icon_size, box.size.y * 0.65), box.size.x * 1.65)
	var scaling := Vector2.ONE * maxf(8.0, icon_size) / 48.0
	canvas.draw_set_transform(box.get_center(), 0.0, scaling)
	match symbol:
		"sword", "dagger":
			_poly(canvas, [-4, 12, -1, -17, 5, -23, 6, -14, 1, 12], steel, edge)
			_line(canvas, Vector2(0, 7), Vector2(4, -16), shine, 1.4)
			_line(canvas, Vector2(-9, 9), Vector2(8, 11), gold, 3)
			_line(canvas, Vector2(-1, 12), Vector2(-2, 20), leather, 4)
			canvas.draw_circle(Vector2(-2, 21), 2.5, bronze)
		"axe":
			_line(canvas, Vector2(-3, 22), Vector2(4, -18), leather, 4)
			_poly(canvas, [2, -11, -11, -15, -15, -20, -10, -22, 1, -18, 10, -20, 15, -15, 11, -7], steel, edge)
			_line(canvas, Vector2(13, -15), Vector2(10, -8), shine, 2)
			_line(canvas, Vector2(-3, 17), Vector2(-2, 12), bronze, 5)
		"mace":
			_line(canvas, Vector2(-4, 20), Vector2(3, -15), leather, 5)
			_poly(canvas, [-9, -14, -5, -20, 0, -19, 4, -24, 8, -18, 13, -17, 10, -12, 12, -6, 6, -6, 2, -3, -1, -8, -7, -8], shadow, edge)
			_poly(canvas, [-6, -15, 5, -20, 10, -16, 6, -11, -2, -10], steel)
			_line(canvas, Vector2(-4, 18), Vector2(-2, 11), bronze, 5)
		"staff":
			_line(canvas, Vector2(-6, 22), Vector2(3, -16), leather, 5)
			_line(canvas, Vector2(-5, 21), Vector2(4, -15), bronze, 2)
			canvas.draw_arc(Vector2(5, -13), 8, -0.1, TAU - 0.5, 24, gold, 2.5, true)
			_poly(canvas, [4, -21, 9, -15, 5, -9, 0, -15], gem, shine)
		"shield":
			_poly(canvas, [-16, -15, -10, -19, 10, -19, 16, -15, 13, 4, 7, 14, 0, 19, -7, 14, -13, 4], bronze, edge)
			_poly(canvas, [-12, -13, 0, -16, 12, -13, 9, 3, 0, 15, -9, 3], shadow, gold)
			_poly(canvas, [0, -14, 10, -12, 8, 3, 0, 13], steel)
			_poly(canvas, [0, -8, 6, -2, 0, 6, -6, -2], bronze, gold)
		"helm":
			_poly(canvas, [-16, 11, -16, -8, -11, -15, 0, -19, 11, -15, 16, -8, 16, 11, 10, 16, -10, 16], steel, edge)
			_poly(canvas, [-12, 2, -3, 5, 3, 5, 12, 2, 11, 8, 4, 8, 0, 15, -4, 8, -11, 8], edge)
			_line(canvas, Vector2(0, -17), Vector2(0, 4), shine, 2)
			_line(canvas, Vector2(-16, -2), Vector2(16, -2), shadow, 2)
		"chest":
			_poly(canvas, [-7, -18, -15, -15, -20, -8, -13, -3, -10, -6, -10, 14, 0, 19, 10, 14, 10, -6, 13, -3, 20, -8, 15, -15, 7, -18, 4, -12, -4, -12], steel, edge)
			_poly(canvas, [0, -10, 9, -12, 8, 12, 0, 16], shadow)
			for y: int in [3, 8, 13]:
				_line(canvas, Vector2(-8, y - 2), Vector2(7, y), bronze, 2)
			_line(canvas, Vector2(-10, -11), Vector2(-5, -8), shine, 2)
		"gloves":
			_poly(canvas, [-15, 15, -17, 1, -20, -6, -17, -8, -13, -4, -13, -16, -10, -17, -7, -8, -4, -16, -1, -14, -1, -5, -4, 15], shadow, edge)
			_poly(canvas, [5, 15, 2, -4, 2, -14, 5, -16, 8, -8, 11, -17, 14, -16, 15, -6, 18, -8, 21, -6, 18, 1, 16, 15], steel, edge)
			_line(canvas, Vector2(-14, 10), Vector2(-4, 10), bronze, 3)
			_line(canvas, Vector2(6, 10), Vector2(16, 10), gold, 3)
		"boots":
			_poly(canvas, [-14, -16, -4, -16, -4, 12, -10, 15, -21, 15, -21, 10, -16, 7], shadow, edge)
			_poly(canvas, [4, -17, 15, -17, 16, 6, 21, 9, 21, 15, 9, 16, 4, 13], steel, edge)
			_line(canvas, Vector2(-13, -10), Vector2(-4, -10), bronze, 3)
			_line(canvas, Vector2(5, -11), Vector2(15, -11), gold, 3)
		"ring":
			canvas.draw_arc(Vector2(0, 3), 12, 0, TAU, 36, edge, 6, true)
			canvas.draw_arc(Vector2(0, 3), 12, 0, TAU, 36, gold, 3.5, true)
			_poly(canvas, [-6, -10, 0, -17, 6, -10, 0, -4], gem.darkened(0.18), shine)
		"amulet":
			canvas.draw_arc(Vector2(0, -8), 12, -0.8, PI + 0.8, 32, gold, 2, true)
			_poly(canvas, [0, -1, 8, 8, 0, 18, -8, 8], bronze, edge)
			_poly(canvas, [0, 2, 4, 8, 0, 13, -4, 8], gem, shine)
		"belt":
			_poly(canvas, [-22, -7, 18, -7, 23, -3, 23, 7, -22, 7], leather, edge)
			canvas.draw_rect(Rect2(-6, -8, 13, 16), bronze, false, 2.5)
			_line(canvas, Vector2(-5, 0), Vector2(2, 0), gold, 1.5)
		"treasure":
			canvas.draw_arc(Vector2(-12, -3), 7, 0, TAU, 20, gold, 3, true)
			_line(canvas, Vector2(-6, -1), Vector2(16, 12), gold, 3)
			_line(canvas, Vector2(10, 8), Vector2(14, 1), bronze, 3)
		"orb":
			canvas.draw_arc(Vector2(0, 6), 14, -0.32, PI + 0.32, 24, bronze, 2.8, true)
			canvas.draw_circle(Vector2(0, -1), 11, gem.darkened(0.50), true, -1.0, true)
			canvas.draw_circle(Vector2(-2, -3), 5, gem.darkened(0.16), true, -1.0, true)
			canvas.draw_circle(Vector2(-4, -5), 2.5, shine, true, -1.0, true)
		"focus":
			_poly(canvas, [0, -17, 10, -12, 12, 8, 0, 18, -12, 8, -10, -12], bronze, edge)
			_poly(canvas, [0, -11, 7, -6, 6, 5, 0, 12, -6, 5, -7, -6], gem.darkened(0.25), shine)
			_line(canvas, Vector2(-11, 2), Vector2(11, 2), gold, 2)
		_:
			_poly(canvas, [0, -14, 11, 0, 0, 14, -11, 0], steel, edge)
	canvas.draw_set_transform(Vector2.ZERO)


static func _poly(canvas: Control, coordinates: Array, tint: Color, edge: Color = Color.TRANSPARENT) -> void:
	var points := PackedVector2Array()
	for index: int in range(0, coordinates.size(), 2):
		points.append(Vector2(coordinates[index], coordinates[index + 1]))
	canvas.draw_colored_polygon(points, tint)
	if edge.a > 0:
		points.append(points[0])
		canvas.draw_polyline(points, edge, 1.8, true)


static func _line(canvas: Control, start: Vector2, end: Vector2, tint: Color, width: float) -> void:
	canvas.draw_line(start, end, tint, width, true)


class DragTile extends Control:
	var item: Dictionary

	func _draw() -> void:
		var script := load("res://ui/inventory_grid.gd")
		var box := Rect2(Vector2.ZERO, size).grow(-1.0)
		script.paint_item_art(self, script.item_art_bounds(box), item)
		script._paint_quantity(self, box, item, 0, true)
