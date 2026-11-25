@tool
extends Button
## Presents the saved character or creation action for one roster slot.

const MenuFrame := preload("res://ui/menu_frame.gd")

## One-based number of this slot in the character roster.
@export var slot_number := 1:
	set(value):
		slot_number = value
		if is_node_ready():
			_number.text = "%02d" % slot_number

@onready var _number: Label = $Face/Number
@onready var _caption: Label = $Face/Text/Caption
@onready var _detail: Label = $Face/Text/Detail
@onready var _empty_caption := _caption.text


func _ready() -> void:
	_number.text = "%02d" % slot_number


func present(character: Dictionary) -> void:
	var occupied := not character.is_empty()
	_caption.text = String(character.get("name", _empty_caption))
	_detail.text = "Level %d" % int(character.get("level", 1)) if occupied else ""
	_detail.visible = occupied
	theme_type_variation = &"" if occupied else &"QuietButton"
	_caption.add_theme_color_override(&"font_color", MenuFrame.TEXT if occupied else MenuFrame.MUTED)
	accessibility_name = "Slot %d, %s%s" % [slot_number, _caption.text,
		", " + _detail.text if occupied else ""]
	tooltip_text = "%s · %s" % [_caption.text, _detail.text] if occupied else ""
