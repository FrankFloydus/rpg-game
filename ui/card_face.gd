extends Button

const Catalog = preload("res://data/card_catalog.gd")
const Services := preload("res://systems/game_services.gd")
const STARTER_ART := preload("res://assets/cards/starter_illustrations.png")
const DISCOVERY_ART := preload("res://assets/cards/relic_illustrations.png")
const OATHBOUND_ART := preload("res://assets/cards/oathbound_three.png")

@onready var _heading: Label = $Heading
@onready var _illustration: TextureRect = $Illustration
@onready var _rarity: Label = $Rarity
@onready var _description: Label = $Description


func play_hover_sound() -> void:
	var audio := Services.audio_for(self)
	if audio != null:
		audio.cue(Catalog.HOVER_SOUND)


func present(card: Dictionary, heading_font: Font = null) -> void:
	pivot_offset = Vector2(size.x * 0.5, size.y * 0.92)
	accessibility_name = card.name
	accessibility_description = card.description
	tooltip_text = card.description
	_heading.text = card.name
	if heading_font != null:
		_heading.add_theme_font_override("font", heading_font)
	_illustration.texture = art_texture(int(card.art))
	_rarity.text = String(card.rarity).capitalize()
	_rarity.add_theme_color_override("font_color", Catalog.color(card))
	_description.text = card.description


static func art_texture(index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	if index == 10:
		atlas.atlas = OATHBOUND_ART
		var guard_inset := OATHBOUND_ART.get_size() * 0.018
		atlas.region = Rect2(guard_inset, OATHBOUND_ART.get_size() - guard_inset * 2.0)
		atlas.filter_clip = true
		return atlas
	var common := index < 6
	var columns := 3 if common else 2
	var local := index if common else index - 6
	var source := STARTER_ART if common else DISCOVERY_ART
	var size_per := source.get_size() / Vector2(columns, 2)
	atlas.atlas = source
	var origin := size_per * Vector2(posmod(local, columns), int(float(local) / columns))
	atlas.region = Rect2(origin + Vector2.ONE * 2.0, size_per - Vector2.ONE * 4.0)
	atlas.filter_clip = true
	return atlas
