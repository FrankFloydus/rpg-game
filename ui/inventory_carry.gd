extends Control
## Click-to-carry keeps ownership with the source until a checked drop commits.

signal feedback(message: String, success: bool)
signal holding_changed(active: bool)
signal outside_drop_requested(source: String, id: StringName)

const Inventory := preload("res://systems/inventory.gd")
const Grid := preload("res://ui/inventory_grid.gd")
const Appearance := preload("res://ui/inventory_appearance.gd")
const Items := preload("res://systems/items.gd")
const Supplies := preload("res://systems/pack_supplies.gd")
const CardItems := preload("res://systems/card_items.gd")
const CardDeck := preload("res://systems/card_deck.gd")
const InventorySounds := preload("res://ui/inventory_sounds.gd")

var _inventory: Inventory
var _card_deck: CardDeck
var _mode := ""
var _panel: Control
var _targets: Array[Control] = []
var _press_target: Control
var _pressed_outside := false
var _pending: Dictionary = {}
var _carried: Dictionary = {}
var _source: Control
var _tile: Grid.DragTile
var _consume_release := false
var _outline := Rect2()
var _swap_outline := Rect2()
var _outline_valid := false
var _mouse := Vector2.ZERO
var _split_grid: Grid
var _split_source: Dictionary = {}


@onready var _split_layer: Control = %SplitLayer
@onready var _split_caption: Label = %Caption
@onready var _split_amount: SpinBox = %Amount


func _ready() -> void:
	Appearance.LIVE.changed.connect(queue_redraw)
	resized.connect(_refresh_pointer)
	_split_amount.get_line_edit().text_submitted.connect(func(_value: String) -> void: _confirm_split())
	(%Cancel as Button).pressed.connect(_close_split)
	(%Split as Button).pressed.connect(_confirm_split)


func bind(inventory: Inventory) -> void:
	cancel()
	if _inventory != null and _inventory.changed.is_connected(_inventory_changed):
		_inventory.changed.disconnect(_inventory_changed)
	_inventory = inventory
	if _inventory != null:
		_inventory.changed.connect(_inventory_changed)


func bind_card_deck(deck: CardDeck) -> void:
	_card_deck = deck


func set_targets(mode: String, bag: Grid, vendor: Grid, slots: Array, panel: Control) -> void:
	cancel()
	_consume_release = false
	_mode = mode
	_panel = panel
	_targets.clear()
	if bag != null:
		_targets.append(bag)
	if vendor != null:
		_targets.append(vendor)
	for slot: Control in slots:
		_targets.append(slot)


func is_holding() -> bool:
	return not _carried.is_empty()


func is_splitting() -> bool:
	return not _split_source.is_empty()


func cancel() -> bool:
	_clear_pending()
	if is_splitting():
		_close_split()
		return true
	if is_holding() and not _inventory.cancel_backpack_cursor():
		feedback.emit("Make room for the item on your cursor.", false)
		return true
	return _clear_carry()


func _inventory_changed() -> void:
	if not is_inside_tree():
		return
	_refresh_pointer()
	var native_data: Variant = get_viewport().gui_get_drag_data()
	_refresh_slot_fit(native_data if _carried.is_empty() and native_data is Dictionary else _carried)


func _refresh_pointer() -> void:
	if is_holding():
		_update_preview(_mouse)
	elif get_viewport().gui_is_dragging():
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("inventory_item") == true:
			_update_drop_outline(edge_drop_target(_mouse, data), _mouse, data)


func _input(event: InputEvent) -> void:
	if _inventory == null or not is_visible_in_tree() or _mode == "smith":
		return
	if is_splitting():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		_refresh_pointer()
		return
	if not event is InputEventMouseButton:
		return
	_mouse = event.position
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if cancel() or _begin_bulk_transfer(event) or _begin_identification(event.position) \
					or _learn_card(event.position):
				get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed and _consume_release:
		_consume_release = false
		if is_holding():
			var release_target := _carry_target_at(event.position)
			if is_instance_valid(_press_target) and _press_target == release_target:
				_drop_on(_press_target, event.position)
			elif _pressed_outside and release_target == null and _outside_panel(event.position):
				_drop_outside()
		_clear_pending()
		get_viewport().set_input_as_handled()
		return
	if get_viewport().gui_is_dragging():
		_clear_pending()
		return
	var target := _carry_target_at(event.position) if is_holding() else _target_at(event.position)
	if event.pressed:
		_press_target = target
		_pressed_outside = target == null and _outside_panel(event.position)
		if is_holding() and (target != null or _pressed_outside):
			_consume_release = true
			get_viewport().set_input_as_handled()
			return
		if target == null:
			_clear_pending()
			return
		if event.ctrl_pressed and _mode in ["vendor", "stash"] and target is Grid:
			if _mode == "stash":
				_quick_stash(target, _local(target, event.position))
			else:
				_quick_trade(target, _local(target, event.position))
			_consume_release = true
			_clear_pending()
			get_viewport().set_input_as_handled()
			return
		if event.shift_pressed and target is Grid and _begin_split(target, event.position):
			_clear_pending()
			get_viewport().set_input_as_handled()
			return
		_pending = _data_at(target, event.position)
		return
	if target != null and target == _press_target and not _pending.is_empty():
		var released := _data_at(target, event.position)
		if released.get("id") == _pending["id"]:
			_pick_up(target, _pending, event.position)
	_clear_pending()


func _draw() -> void:
	if _outline.has_area():
		Appearance.paint_drop(self, _outline, Appearance.LIVE, _outline_valid)
	if _swap_outline.has_area():
		Appearance.paint_swap(self, _swap_outline, Appearance.LIVE)


func _begin_identification(at: Vector2) -> bool:
	var target := _target_at(at) as Grid
	if target == null or target.endpoint != "bag":
		return false
	var data := target.carry_data_at(_local(target, at))
	if data.is_empty() or _inventory.get_item(data.id).get("supply_kind") != Supplies.UNVEILING_SCROLL:
		return false
	data["identify"] = true
	_pick_up(target, data, at)
	feedback.emit("Click an unidentified item.", true)
	return true


func _learn_card(at: Vector2) -> bool:
	var target := _target_at(at) as Grid
	if target == null or target.endpoint != "bag":
		return false
	var id := target.item_at(_local(target, at))
	var card := _inventory.get_item(id)
	if not CardItems.is_card(card):
		return false
	var denial := _inventory.learn_card(id, _card_deck)
	feedback.emit("Learned %s." % Items.visible_name(card) if denial.is_empty() else denial, denial.is_empty())
	return true


func _begin_split(grid: Grid, at: Vector2) -> bool:
	if grid.endpoint == "vendor":
		return false
	var data := grid.carry_data_at(_local(grid, at))
	if data.is_empty():
		return false
	var item := _inventory.get_item(data.id)
	var units := Supplies.quantity(item)
	if not Supplies.can_stack(item) or units < 2:
		return false
	_split_grid = grid
	_split_source = data
	_split_caption.text = "%s · %d in stack" % [Items.visible_name(item), units]
	_split_amount.max_value = float(units - 1)
	_split_amount.value = 1.0
	_split_layer.show()
	var field := _split_amount.get_line_edit()
	field.grab_focus()
	field.select_all()
	return true


func _confirm_split() -> void:
	if not is_splitting():
		return
	_split_amount.apply()
	var data := _split_source
	data["split_units"] = int(_split_amount.value)
	var grid := _split_grid
	_close_split()
	_pick_up(grid, data, _mouse)


func _close_split() -> void:
	_split_source = {}
	_split_grid = null
	_split_layer.hide()


func _data_at(target: Control, viewport_position: Vector2) -> Dictionary:
	if target is Grid:
		return target.carry_data_at(_local(target, viewport_position))
	var slot: String = target.get("slot")
	var id := _inventory.equipped_id(slot)
	if id.is_empty() or _inventory.equipped_anchor(id) != slot:
		return {}
	var item := _inventory.get_item(id)
	var extent := Vector2i(int(item.get("width", 1)), int(item.get("height", 1)))
	return {"inventory_item": true, "id": id, "source": "equipment", "size": extent}


func _pick_up(target: Control, data: Dictionary, viewport_position: Vector2, play_grab := true) -> void:
	var was_holding := is_holding()
	if was_holding:
		_mark_source(&"")
	_carried = data
	var item := _inventory.get_item(data["id"])
	if not is_instance_valid(_tile):
		_tile = Grid.DragTile.new()
		_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tile)
	_tile.item = item
	if data.has("split_units"):
		_tile.item = item.duplicate()
		_tile.item["quantity"] = data.split_units
	var cell_size := _cell_size()
	_tile.size = Vector2(data["size"]) * cell_size
	_tile.queue_redraw()
	_source = target
	_mark_source(&"" if data.has("split_units") else data["id"])
	_update_preview(viewport_position)
	_refresh_slot_fit(_carried)
	if not was_holding:
		if play_grab:
			InventorySounds.grab(self)
		holding_changed.emit(true)


func _clear_pending() -> void:
	_pending = {}
	_press_target = null
	_pressed_outside = false


func _clear_carry() -> bool:
	if not is_holding():
		return false
	_carried = {}
	_outline = Rect2()
	_swap_outline = Rect2()
	_mark_source(&"")
	_source = null
	if is_instance_valid(_tile):
		_tile.hide()
		_tile.queue_free()
	_tile = null
	_refresh_slot_fit({})
	queue_redraw()
	holding_changed.emit(false)
	return true


func _mark_source(id: StringName) -> void:
	if not is_instance_valid(_source):
		return
	if _source is Grid:
		_source.carried_id = id
		_source.queue_redraw()
	else:
		_source.set_carried(not id.is_empty())


func _refresh_slot_fit(data: Dictionary) -> void:
	var has_equipment_candidate: bool = not data.is_empty() and not data.get("identify", false) and not data.has("split_units")
	for target: Control in _targets:
		if not is_instance_valid(target) or target is Grid:
			continue
		target.set_carry_fit(has_equipment_candidate and target.place_from_cursor(data).is_empty())


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN and _inventory != null:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("inventory_item") == true:
			_refresh_slot_fit(data)
			if is_visible_in_tree():
				mouse_filter = Control.MOUSE_FILTER_STOP
				InventorySounds.grab(self)
	elif what == NOTIFICATION_DRAG_END:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_refresh_slot_fit(_carried)
		if not is_holding():
			_update_drop_outline(null, _mouse, {})


## This control handles native drops in the gutter, where ordinary GUI hit testing misses the grid.
func _has_point(at_position: Vector2) -> bool:
	var data: Variant = get_viewport().gui_get_drag_data()
	return data is Dictionary and edge_drop_target(get_global_transform_with_canvas() * at_position, data) != null


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var viewport_position := get_global_transform_with_canvas() * at_position
	var grid := edge_drop_target(viewport_position, data)
	return grid != null and grid.preview_grid_drop(_local(grid, viewport_position), data).is_empty()


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var viewport_position := get_global_transform_with_canvas() * at_position
	var grid := edge_drop_target(viewport_position, data)
	if grid != null:
		grid._drop_data(_local(grid, viewport_position), data)


func _update_preview(viewport_position: Vector2) -> void:
	_tile.position = _local(self, viewport_position) - _tile.size * 0.5
	_update_drop_outline(_carry_target_at(viewport_position) as Grid, viewport_position, _carried)


func _update_drop_outline(target: Grid, viewport_position: Vector2, data: Dictionary) -> void:
	var outline := Rect2()
	var swap := Rect2()
	var valid := false
	if target != null:
		var local_position := _local(target, viewport_position)
		var cells := target.drop_cells(local_position, data["size"])
		if data.get("identify", false):
			valid = target.endpoint == "bag" and _inventory.preview_identify(data.id, target.item_at(local_position)).is_empty()
			var placement := _inventory.get_grid(target.endpoint).get_placement(target.item_at(local_position))
			if not placement.is_empty():
				cells = Rect2i(placement.origin, placement.footprint)
		elif data.has("split_units"):
			valid = _split_drop(target, local_position, false).is_empty()
		else:
			var plan := target.preview_grid_cursor_drop(cells, data)
			valid = plan.denial.is_empty()
			if valid:
				swap = _outline_rect(target, target.swap_cells(cells, plan.displaced))
		outline = _outline_rect(target, cells)
	if _outline != outline or _swap_outline != swap or _outline_valid != valid:
		_outline = outline
		_swap_outline = swap
		_outline_valid = valid
		queue_redraw()


func _outline_rect(target: Grid, cells: Rect2i) -> Rect2:
	if not cells.has_area():
		return Rect2()
	var pixels := Rect2(Vector2(cells.position * target.cell_size), Vector2(cells.size * target.cell_size))
	var viewport_rect := (target.get_global_transform_with_canvas() * pixels).intersection(_target_rect(target))
	return get_global_transform_with_canvas().affine_inverse() * viewport_rect


func _drop_on(target: Control, view_position: Vector2) -> void:
	var at_position := _local(target, view_position)
	var denial := ""
	var id: StringName = _carried["id"]
	if _carried.get("identify", false):
		_apply_identification(target, at_position, id)
		return
	var item := _inventory.get_item(id)
	if _carried.has("split_units"):
		denial = _split_drop(target, at_position, true)
		if denial.is_empty():
			InventorySounds.place(self, item)
			_clear_carry()
		else:
			feedback.emit(denial, false)
		return
	var source: String = _carried["source"]
	var item_name := Items.visible_name(item)
	var message := ""
	if target is Grid:
		var origin: Vector2i = target.drop_cells(at_position, _carried["size"]).position
		if source == "bag" and target.endpoint == "bag":
			var result := _inventory.place_backpack_cursor(id, origin)
			denial = result.denial
			if denial.is_empty() and not result.displaced.is_empty():
				InventorySounds.place(self, item)
				_hold_displaced(target, result.displaced, view_position)
				return
		else:
			denial = _inventory.drop_item(source, id, target.endpoint, origin)
		if source == "vendor":
			message = "Purchased %s for %d gold." % [item_name, Inventory.buy_price(item)]
		elif target.endpoint == "vendor":
			message = "Sold %s for %d gold." % [item_name, Inventory.sell_price(item)]
		elif source == "equipment":
			message = "Returned %s to your pack." % item_name
		elif _mode == "stash" and source != target.endpoint:
			message = "Stored %s." % item_name if target.endpoint != "bag" else "Withdrew %s." % item_name
	else:
		denial = target.place_from_cursor(_carried, true)
		if source == "bag":
			message = "Equipped %s." % item_name
	if denial.is_empty():
		InventorySounds.place(self, item)
		_clear_carry()
	feedback.emit(message if denial.is_empty() else denial, denial.is_empty())


func _apply_identification(target: Control, at: Vector2, id: StringName) -> void:
	if not target is Grid or target.endpoint != "bag":
		feedback.emit("Choose an unidentified item in your pack.", false)
		return
	var target_id: StringName = target.item_at(at)
	var denial := _inventory.identify_item(id, target_id)
	if not denial.is_empty():
		feedback.emit(denial, false)
		return
	_clear_carry()
	feedback.emit("Identified %s." % Items.visible_name(_inventory.get_item(target_id)), true)


func _split_drop(target: Control, at: Vector2, commit: bool) -> String:
	if not target is Grid or target.endpoint == "vendor":
		return "Place the split stack in your pack or stash."
	var source: String = _carried.source
	var id: StringName = _carried.id
	var count: int = _carried.split_units
	var origin: Vector2i = target.cell_at(at)
	if commit:
		return _inventory.drop_split(source, id, count, target.endpoint, origin)
	return _inventory.preview_split(source, id, count, target.endpoint, origin)


func adopt_native_swap(placement: Dictionary, view_position: Vector2, target: Grid) -> void:
	_hold_displaced(target, placement, view_position, false)


func _hold_displaced(target: Grid, placement: Dictionary, view_position: Vector2, play_grab := true) -> void:
	_pick_up(target, {
		"inventory_item": true, "id": placement.id, "source": "bag",
		"size": Grid._extent(placement),
	}, view_position, play_grab)


func _outside_panel(viewport_position: Vector2) -> bool:
	return is_instance_valid(_panel) and not Rect2(Vector2.ZERO, _panel.size).has_point(_local(_panel, viewport_position))


func _drop_outside() -> void:
	if _carried.has("split_units"):
		feedback.emit("Place the split stack in your pack or stash.", false)
		return
	if _carried.get("identify", false):
		feedback.emit("Choose an unidentified item in your pack.", false)
		return
	var source: String = _carried["source"]
	var id: StringName = _carried["id"]
	if not _inventory.cancel_backpack_cursor():
		feedback.emit("Make room for the item on your cursor.", false)
		return
	_clear_carry()
	if source in ["bag", "equipment"]:
		outside_drop_requested.emit(source, id)


func _quick_trade(grid: Grid, at_position: Vector2) -> void:
	var id := grid.item_at(at_position)
	if id.is_empty():
		return
	var item := _inventory.get_item(id)
	var item_name := Items.visible_name(item)
	var buying := grid.endpoint == "vendor"
	var denial := _inventory.quick_purchase(id) if buying else _inventory.quick_sell(id)
	if denial.is_empty():
		InventorySounds.place(self, item)
	var terms := "Purchased %s for %d gold." if buying else "Sold %s for %d gold."
	var price := Inventory.buy_price(item) if buying else Inventory.sell_price(item)
	feedback.emit(terms % [item_name, price] if denial.is_empty() else denial, denial.is_empty())


func _begin_bulk_transfer(event: InputEventMouseButton) -> bool:
	if _mode != "stash" or not event.ctrl_pressed:
		return false
	var grid := _target_at(event.position) as Grid
	if grid == null:
		return false
	var local := _local(grid, event.position)
	var id := grid.item_at(local)
	if id.is_empty() or not Supplies.can_stack(_inventory.get_item(id)):
		return false
	_quick_stash(grid, local, true)
	return true


func _quick_stash(grid: Grid, at_position: Vector2, bulk := false) -> void:
	var id := grid.item_at(at_position)
	if id.is_empty():
		return
	var destination := "bag"
	if grid.endpoint == "bag":
		for target: Control in _targets:
			if target is Grid and Inventory.Stash.is_owner(target.endpoint):
				destination = target.endpoint
				break
	var item := _inventory.get_item(id)
	var denial := _inventory.bulk_stash_transfer(grid.endpoint, id, destination) if bulk \
		else _inventory.quick_stash_transfer(grid.endpoint, id, destination)
	if denial.is_empty():
		InventorySounds.place(self, item)
	var terms := "Withdrew %s." if destination == "bag" else "Stored %s."
	feedback.emit(terms % Items.visible_name(item) if denial.is_empty() else denial, denial.is_empty())


func _target_at(viewport_position: Vector2) -> Control:
	for target: Control in _targets:
		if not is_instance_valid(target) or not target.is_visible_in_tree():
			continue
		if _target_rect(target).has_point(viewport_position):
			return target
	return null


func _carry_target_at(viewport_position: Vector2) -> Control:
	var direct := _target_at(viewport_position)
	return direct if direct != null else _overlapping_grid(viewport_position, _carried)


func edge_drop_target(viewport_position: Vector2, data: Dictionary) -> Grid:
	return _overlapping_grid(viewport_position, data) if _target_at(viewport_position) == null else null


func _overlapping_grid(viewport_position: Vector2, data: Dictionary) -> Grid:
	if _mode == "smith" or data.get("inventory_item") != true or data.get("identify", false) or data.has("split_units"):
		return null
	var hovered := get_viewport().gui_get_hovered_control()
	if (hovered is BaseButton or hovered is LineEdit or hovered is ScrollBar) and _screen_rect(hovered).has_point(viewport_position):
		return null
	var nearest: Grid
	var nearest_distance := INF
	for target: Control in _targets:
		var grid := target as Grid
		if not is_instance_valid(grid) or grid.endpoint == "vendor" or not grid.is_visible_in_tree():
			continue
		var visible_area := _target_rect(grid)
		if not visible_area.has_area() or _screen_rect(grid).has_point(viewport_position):
			continue
		var footprint := Vector2(data["size"]) * grid.cell_size
		var tile := grid.get_global_transform_with_canvas() * Rect2(_local(grid, viewport_position) - footprint * 0.5, footprint)
		if not tile.intersects(visible_area):
			continue
		var distance := viewport_position.distance_squared_to(viewport_position.clamp(visible_area.position, visible_area.end))
		if distance < nearest_distance:
			nearest = grid
			nearest_distance = distance
	return nearest


static func _target_rect(target: Control) -> Rect2:
	var bounds := _screen_rect(target)
	var scroll := target.get_parent() as ScrollContainer
	return bounds.intersection(_screen_rect(scroll)) if scroll != null else bounds


static func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _cell_size() -> int:
	for target: Control in _targets:
		if is_instance_valid(target) and target is Grid:
			return target.cell_size
	return 45


static func _local(target: Control, viewport_position: Vector2) -> Vector2:
	return target.get_global_transform_with_canvas().affine_inverse() * viewport_position
