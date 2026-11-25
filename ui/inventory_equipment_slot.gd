@tool
extends Control
## One editable equipment well with checked equip and carry interactions.

const Inventory := preload("res://systems/inventory.gd")
const Grid := preload("res://ui/inventory_grid.gd")
const Art := preload("res://ui/item_art.gd")
const MenuFrame := preload("res://ui/menu_frame.gd")
const InventorySounds := preload("res://ui/inventory_sounds.gd")
const Appearance := preload("res://ui/inventory_appearance.gd")

signal action_feedback(message: String, success: bool)

const EMPTY_EDGE := MenuFrame.LINE
const EMPTY_FILL := MenuFrame.WELL
const BLOCKED_EDGE := MenuFrame.LINE
const BLOCKED_FILL := MenuFrame.BASE
const EMPTY_INK := MenuFrame.MUTED
const BLOCKED_INK := MenuFrame.DIM
const LOCK_TEXTURE := preload("res://assets/rework/ui/wrought_iron_lock.png")
const SLOT_ICONS := {
	"left_ring": "ring", "right_ring": "ring", "helm": "helm",
	"main_hand": "sword_1h", "off_hand": "shield", "chest": "chest",
	"gloves": "gloves", "boots": "boots", "amulet": "amulet", "belt": "belt",
}


var inventory: Inventory
@export_enum("main_hand","off_hand","helm","chest","left_ring","right_ring","amulet","gloves","boots","belt") var slot := "main_hand"
@export_range(12, 84) var cell_size := 38
var _over := false
var _item: Dictionary = {}
var _blocked := false
var _carried := false
var _carry_fit := false

func _ready() -> void:
	if Engine.is_editor_hint():
		resized.connect(queue_redraw)
		return
	Appearance.LIVE.changed.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_over = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_over = false
		queue_redraw())
	refresh()

func refresh() -> void:
	if inventory == null:
		return
	var id := inventory.equipped_id(slot)
	_blocked = not id.is_empty() and inventory.equipped_anchor(id) != slot
	_item = inventory.get_item(id) if not id.is_empty() and not _blocked else {}
	var state := "Two-handed" if _blocked else String(_item.get("name", "Empty"))
	accessibility_name = "%s, %s" % [Inventory.SLOT_NAMES[slot], state]
	tooltip_text = accessibility_name if _item.is_empty() else ""
	mouse_default_cursor_shape = Control.CURSOR_ARROW if _item.is_empty() else Control.CURSOR_POINTING_HAND
	queue_redraw()

func set_carried(active: bool) -> void:
	_carried = active
	refresh()

func set_carry_fit(compatible: bool) -> void:
	if _carry_fit != compatible:
		_carry_fit = compatible
		queue_redraw()

func anchored_item_id() -> StringName:
	if inventory == null:
		return &""
	var id := inventory.equipped_id(slot)
	return id if not id.is_empty() and inventory.equipped_anchor(id) == slot else &""

func place_from_cursor(data: Dictionary, commit := false) -> String:
	var id: StringName = data.get("id", &"")
	if inventory == null or data.get("inventory_item") != true or id.is_empty():
		return "Choose an item to equip."
	match data.get("source"):
		"bag":
			return inventory.equip_item(id, slot) if commit else inventory.preview_equip(id, slot)
		"equipment":
			# The source still owns the carried item. Putting it back needs no inventory write.
			if id == anchored_item_id():
				return ""
	return "Move this item to your pack first."

func item_art_rect() -> Rect2:
	if _item.is_empty():
		return Rect2()
	var item_size := Vector2(_item["width"], _item["height"]) * cell_size
	var tile := Rect2((size - item_size) * 0.5, item_size).grow(-1.0)
	return Grid.item_art_bounds(tile)

func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size).grow(-0.5)
	var art := area.grow(-2.0)
	if Engine.is_editor_hint():
		draw_rect(area, EMPTY_FILL)
		draw_rect(area, EMPTY_EDGE, false, 1.0)
		_draw_state_label("Empty", art, EMPTY_INK)
		return
	var filled := not _item.is_empty()
	if filled:
		Appearance.paint_placed(self, area, Appearance.LIVE, _item.get("unidentified", false), _over and not _carried)
	else:
		var edge := BLOCKED_EDGE if _blocked else EMPTY_EDGE
		var fill := BLOCKED_FILL if _blocked else EMPTY_FILL
		if _over:
			edge = edge.lightened(0.24)
			fill = fill.lightened(0.055)
		draw_rect(area, fill)
		draw_rect(area, edge, false, 1.0)
	var show_fit := _carry_fit and Appearance.paint_equipment_fit(self, art, Appearance.LIVE)
	if filled and not _carried:
		Grid.paint_item_art(self, item_art_rect(), _item)
		var status := Vector2(size.x - 10, 10)
		draw_polyline(PackedVector2Array([status + Vector2(-4, 0), status + Vector2(-1, 3),
			status + Vector2(4, -3)]), MenuFrame.MUTED, 1.5, true)
	elif _blocked:
		_draw_blocked(art)
	elif not filled:
		_draw_empty(art, show_fit)

func _draw_empty(art: Rect2, show_fit: bool) -> void:
	if not show_fit:
		draw_rect(art, Color(MenuFrame.BASE, 0.40))
	var texture := Art.texture_for(SLOT_ICONS[slot])
	if texture != null:
		var box := art.grow(-4.0)
		box.size.y -= 12.0
		var scale_factor := minf(box.size.x / texture.get_width(), box.size.y / texture.get_height()) * 0.88
		var extent := texture.get_size() * scale_factor
		draw_texture_rect(texture, Rect2(box.get_center() - extent * 0.5, extent), false,
			Color(0.90, 0.88, 0.85, 0.46))
	_draw_state_label("Empty", art, EMPTY_INK)

func _draw_state_label(caption: String, area: Rect2, ink: Color) -> void:
	var font := get_theme_font(&"font", &"GearValue")
	var font_size := 11 if size.x <= cell_size else 12
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(area.get_center().x - width * 0.5, area.end.y - 3.0), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)

func _draw_blocked(art: Rect2) -> void:
	draw_rect(art, Color("#10111270"))
	var extent := LOCK_TEXTURE.get_size() * (minf(art.size.x, 55.0) / LOCK_TEXTURE.get_width())
	draw_texture_rect(LOCK_TEXTURE, Rect2(art.get_center() - extent * 0.5, extent), false)
	_draw_state_label("Two-handed", art, BLOCKED_INK)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var id := anchored_item_id()
	if id.is_empty():
		return
	var item := inventory.get_item(id)
	var denial := inventory.quick_unequip(slot)
	if denial.is_empty():
		InventorySounds.place(self, item)
	action_feedback.emit("Returned %s to your pack." % item.get("name", "gear") if denial.is_empty() else denial,
		denial.is_empty())
	accept_event()

func _get_drag_data(_at_position: Vector2) -> Variant:
	var id := anchored_item_id()
	if id.is_empty():
		return null
	var item := inventory.get_item(id)
	var footprint := Vector2i(int(item.get("width", 1)), int(item.get("height", 1)))
	set_drag_preview(Grid.make_drag_preview(item, footprint, cell_size))
	return {"inventory_item": true, "id": id, "source": "equipment", "size": footprint}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and place_from_cursor(data).is_empty()

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var id: StringName = data["id"]
	var item := inventory.get_item(id)
	var denial := place_from_cursor(data, true)
	if denial.is_empty():
		InventorySounds.place(self, item)
	var message := "Equipped %s." % item.get("name", "gear") if data.get("source") == "bag" else ""
	action_feedback.emit(message if denial.is_empty() else denial, denial.is_empty())
