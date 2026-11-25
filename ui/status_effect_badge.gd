extends Panel
## Displays one active effect using the icon and lifetime supplied by combat.

## Frame style for effects that help the player.
@export var beneficial_style: StyleBox
## Frame style for effects that hinder the player.
@export var harmful_style: StyleBox

@onready var icon: TextureRect = $Icon
@onready var countdown: Label = $Countdown
@onready var _charges: Label = $Charges


func present(status: Dictionary, texture: Texture2D) -> void:
	var beneficial := bool(status.get("beneficial", false))
	var style := beneficial_style if beneficial else harmful_style
	if get_theme_stylebox(&"panel") != style:
		add_theme_stylebox_override(&"panel", style)
	if icon.texture != texture:
		icon.texture = texture
	var remaining := float(status.get("remaining", INF))
	var time_text := str(ceili(remaining - 0.000001)) if is_finite(remaining) else ""
	if countdown.text != time_text:
		countdown.text = time_text
		countdown.visible = not time_text.is_empty()
	var count := int(status.get("charges", -1))
	var charge_text := "%d×" % count if count > 0 else ""
	if _charges.text != charge_text:
		_charges.text = charge_text
		_charges.visible = not charge_text.is_empty()
	var title := String(status.get("name", status.id))
	if accessibility_name != title:
		accessibility_name = title
		var description := String(status.get("description", ""))
		tooltip_text = title + ("\n" + description if not description.is_empty() else "")
	show()


func clear_status() -> void:
	hide()
	countdown.text = ""
	countdown.hide()
	_charges.text = ""
	_charges.hide()
