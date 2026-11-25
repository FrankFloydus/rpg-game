extends HBoxContainer
## Shared collection and slot editor for the deck menu and Training Ground.

signal slot_changed(slot: int, id: String)

const Catalog := preload("res://data/card_catalog.gd")
const Face := preload("res://ui/card_face.gd")
const CardTemplate := preload("res://ui/card_face_compact.tscn")
const MenuFrame := preload("res://ui/menu_frame.gd")
@export var serif: Font
@export var slot_width := 0.0

@onready var _collection: ScrollContainer = $Collection/Scroll
@onready var _grid: GridContainer = $Collection/Scroll/CardCollection
@onready var _note: Label = $Equipped/Scroll/Deck/Note
@onready var _empty: Button = $Equipped/Scroll/Deck/EmptySelectedSlot

var _slots: Array[Button] = []
var _slot_images: Array[TextureRect] = []
var _slot_labels: Array[Label] = []
var _available: Array[String] = []
var _equipped: Array[String] = []
var _selected_slot := 0
var _editable := false


func _ready() -> void:
	if slot_width > 0.0:
		$Equipped.custom_minimum_size.x = slot_width
	_collection.resized.connect(_layout_cards)
	for child in $Equipped/Scroll/Deck/Slots.get_children():
		var button := child as Button
		button.pressed.connect(_select_slot.bind(_slots.size()))
		_slots.append(button)
		_slot_images.append(button.get_node("Contents/Portrait"))
		var caption := button.get_node("Contents/Caption") as Label
		if serif != null:
			caption.add_theme_font_override("font", serif)
		_slot_labels.append(caption)
	_empty.pressed.connect(func() -> void: slot_changed.emit(_selected_slot, ""))


func present(available: Array[String], equipped: Array[String], reset_selection := false,
		read_only_note := "") -> void:
	if reset_selection:
		_selected_slot = 0
		_collection.scroll_vertical = 0
	var editable := read_only_note.is_empty()
	if available != _available or editable != _editable:
		_available = available.duplicate()
		_editable = editable
		_rebuild_collection()
	_equipped = equipped.duplicate()
	_note.text = "Select a slot, then choose a card." if _editable else read_only_note
	_refresh_slots()
	_layout_cards()


func focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	if not _editable:
		return controls
	controls.append_array(_slots)
	if not _empty.disabled:
		controls.append(_empty)
	for choice: Button in _grid.get_children():
		controls.append(choice)
	return controls


func _layout_cards() -> void:
	var rail := _collection.get_v_scroll_bar().get_combined_minimum_size().x
	var width := _collection.size.x - rail
	var gap := _grid.get_theme_constant("h_separation")
	if _grid.get_child_count() > 0:
		var sample := _grid.get_child(0) as Control
		_grid.columns = clampi(floori((width + gap) / (sample.get_combined_minimum_size().x + gap)), 1, 5)


func _rebuild_collection() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for id in _available:
		var face := CardTemplate.instantiate() as Face
		face.name = "DeckCard_" + id
		_grid.add_child(face)
		face.present(Catalog.CARDS[id], serif)
		face.mouse_entered.connect(face.play_hover_sound)
		face.focus_entered.connect(func() -> void:
			if not face.is_hovered():
				face.play_hover_sound())
		if _editable:
			face.pressed.connect(func() -> void: slot_changed.emit(_selected_slot, id))
		else:
			face.disabled = true
			face.mouse_default_cursor_shape = Control.CURSOR_ARROW


func _select_slot(slot: int) -> void:
	_selected_slot = slot
	_refresh_slots()


func _refresh_slots() -> void:
	for slot in Catalog.SLOTS:
		var id := _equipped[slot]
		var card: Dictionary = Catalog.CARDS.get(id, {})
		var has_card := not card.is_empty()
		var selected := _editable and slot == _selected_slot
		var quick := _slots[slot]
		quick.disabled = not _editable
		quick.set_pressed_no_signal(selected)
		quick.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _editable else Control.CURSOR_ARROW
		quick.accessibility_name = ("Select slot %d" if _editable else "Equipped slot %d") % (slot + 1)
		var caption := _slot_labels[slot]
		caption.text = String(card.name) if has_card else "Empty slot"
		caption.add_theme_color_override("font_color", Catalog.color(card) if has_card else MenuFrame.MUTED)
		_slot_images[slot].visible = has_card
		_slot_images[slot].texture = Face.art_texture(card.art) if has_card else null
	_empty.visible = _editable
	_empty.disabled = _equipped[_selected_slot].is_empty()
