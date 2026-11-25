extends Control
## Presents character selection and creation. The game owns campaign saves and scene transitions.

signal character_selected(slot: int)
signal character_created(slot: int, character_name: String)
signal training_requested
signal settings_requested
signal quit_requested

const CharacterSlots := preload("res://systems/character_slots.gd")
const CharacterSlot := preload("res://ui/title_character_slot.gd")

@onready var _roster: VBoxContainer = $Center/MenuFrame/Menu/Roster
@onready var _slots: GridContainer = _roster.get_node("Slots")
@onready var _creation: VBoxContainer = $Center/MenuFrame/Menu/CreateCharacter
@onready var _creation_slot_label: Label = _creation.get_node("Heading")
@onready var _name_input: LineEdit = _creation.get_node("Name")
@onready var _create: Button = _creation.get_node("Actions/Create")
@onready var _cancel: Button = _creation.get_node("Actions/Back")
@onready var _error: Label = $Center/MenuFrame/Menu/Error
@onready var _training: Button = $Center/MenuFrame/Menu/Actions/Training
@onready var _settings: Button = $Center/MenuFrame/Menu/Actions/Settings
@onready var _quit: Button = $Center/MenuFrame/Menu/Actions/Quit

var _characters: Dictionary[int, Dictionary] = {}
var _buttons: Array[CharacterSlot] = []
var _creation_slot := -1


func _ready() -> void:
	for slot in CharacterSlots.SLOT_COUNT:
		var button := _slots.get_node("Character%02d" % (slot + 1)) as CharacterSlot
		button.pressed.connect(_choose_slot.bind(slot))
		_buttons.append(button)
	_set_roster_navigation()
	_name_input.max_length = CharacterSlots.MAX_NAME_LENGTH
	_name_input.text_changed.connect(_update_creation)
	_name_input.text_submitted.connect(func(_submitted: String) -> void: _submit_creation())
	_cancel.pressed.connect(_back_to_roster)
	_create.pressed.connect(_submit_creation)
	_training.pressed.connect(training_requested.emit)
	_settings.pressed.connect(settings_requested.emit)
	_quit.pressed.connect(quit_requested.emit)
	hide()


func present(characters: Array[Dictionary]) -> void:
	_characters.clear()
	for character: Dictionary in characters:
		var slot := int(character.get("slot", -1))
		if slot >= 0 and slot < CharacterSlots.SLOT_COUNT:
			_characters[slot] = character
	for slot in CharacterSlots.SLOT_COUNT:
		_buttons[slot].present(_characters.get(slot, {}))
	show()
	_back_to_roster()
	for slot in CharacterSlots.SLOT_COUNT:
		if _characters.has(slot):
			_buttons[slot].grab_focus()
			return
	_buttons.front().grab_focus()


func close() -> void:
	hide()


func is_open() -> bool:
	return visible


func show_roster_error(message: String) -> void:
	_error.text = message
	_error.visible = not message.is_empty()


func _input(event: InputEvent) -> void:
	if is_open() and _creation_slot >= 0 and event is InputEventKey and event.pressed \
			and not event.echo and event.keycode == KEY_ESCAPE:
		_back_to_roster()
		get_viewport().set_input_as_handled()


func _set_roster_navigation() -> void:
	var columns := _slots.columns
	for index: int in _buttons.size():
		var button := _buttons[index]
		var column := index % columns
		if column < columns - 1 and index + 1 < _buttons.size():
			button.focus_neighbor_right = button.get_path_to(_buttons[index + 1])
		if column > 0:
			button.focus_neighbor_left = button.get_path_to(_buttons[index - 1])
		if index >= columns:
			button.focus_neighbor_top = button.get_path_to(_buttons[index - columns])
		var below := index + columns
		button.focus_neighbor_bottom = button.get_path_to(_buttons[below] if below < _buttons.size() else _training)
	var final_row := _buttons.size() - 1 - (_buttons.size() - 1) % columns
	_training.focus_neighbor_top = _training.get_path_to(_buttons[final_row])
	_settings.focus_neighbor_top = _settings.get_path_to(_buttons.back())


func _choose_slot(slot: int) -> void:
	show_roster_error("")
	if _characters.has(slot):
		character_selected.emit(slot)
		return
	_creation_slot = slot
	_creation_slot_label.text = "New Character · Slot %02d" % (slot + 1)
	_name_input.clear()
	_update_creation("")
	_roster.hide()
	_creation.show()
	_name_input.grab_focus()


func _update_creation(value: String) -> void:
	_create.disabled = not CharacterSlots.valid_name(value)
	if not _error.text.is_empty():
		show_roster_error("")


func _submit_creation() -> void:
	var character_name := _name_input.text.strip_edges()
	if _creation_slot < 0 or not CharacterSlots.valid_name(character_name):
		return
	character_created.emit(_creation_slot, character_name)


func _back_to_roster() -> void:
	var selected := maxi(0, _creation_slot)
	_creation_slot = -1
	_creation.hide()
	_roster.show()
	show_roster_error("")
	_buttons[selected].grab_focus()

