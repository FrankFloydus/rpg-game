extends RefCounted
## The pack, equipped slots, and item details share painted versions of their model portraits.

const ICONS := "res://assets/items/icons/"
const PAINTED_ICONS := "res://assets/items/painted_icons/"
const BASE_ICONS := "res://assets/items/base_icons/"
const LEATHER := "res://assets/grounded/interface_leather.png"
const CardItems := preload("res://systems/card_items.gd")
const CardFace := preload("res://ui/card_face.gd")

static var _leather: Texture2D
static var _icons: Dictionary[String, Texture2D] = {}
static var _card_icons: Dictionary[int, Texture2D] = {}


static func texture_for_item(item: Dictionary) -> Texture2D:
	if not CardItems.is_card(item):
		return texture_for_base(String(item.get("base_id", "")), String(item.get("type", "")))
	if item.get("unidentified", false) or not item.has("art"):
		return CardItems.BACK_ART
	var index: int = item.art
	if not _card_icons.has(index):
		_card_icons[index] = CardFace.art_texture(index)
	return _card_icons[index]


static func texture_for(type: String) -> Texture2D:
	var filename := type + ".png"
	var painting := _icon_at(PAINTED_ICONS.path_join(filename))
	return painting if painting != null else _icon_at(ICONS.path_join(filename))


static func texture_for_base(base_id: String, type: String) -> Texture2D:
	if not base_id.is_empty():
		var portrait := _icon_at(BASE_ICONS.path_join(base_id + ".png"))
		if portrait != null:
			return portrait
	return texture_for(type)


static func _icon_at(path: String) -> Texture2D:
	if _icons.has(path):
		return _icons[path]
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	var icon := ResourceLoader.load(path, "Texture2D") as Texture2D
	_icons[path] = icon
	return icon


static func leather() -> Texture2D:
	if _leather == null and ResourceLoader.exists(LEATHER, "Texture2D"):
		_leather = ResourceLoader.load(LEATHER, "Texture2D") as Texture2D
	return _leather

