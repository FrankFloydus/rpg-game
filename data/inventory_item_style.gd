@tool
extends Resource
## Appearance shared by the pack, stash, merchant, and equipment slots.

@export_group("Placed Items")
## Fill behind an identified item. Alpha controls how strongly it tints the black slot.
@export var identified_fill := Color("#282b3c"):
	set(value):
		if identified_fill != value:
			identified_fill = value
			emit_changed()
## Fill behind an unidentified item. Alpha controls how strongly it tints the black slot.
@export var unidentified_fill := Color("#513239"):
	set(value):
		if unidentified_fill != value:
			unidentified_fill = value
			emit_changed()
## Fill and opacity for an identified item when hover highlighting is enabled.
@export var identified_hover_fill := Color("#373c53"):
	set(value):
		if identified_hover_fill != value:
			identified_hover_fill = value
			emit_changed()
## Fill and opacity for an unidentified item when hover highlighting is enabled.
@export var unidentified_hover_fill := Color("#653d48"):
	set(value):
		if unidentified_hover_fill != value:
			unidentified_hover_fill = value
			emit_changed()
## Change an item's background when hovered or selected.
@export var highlight_items := true:
	set(value):
		if highlight_items != value:
			highlight_items = value
			emit_changed()
## Thin outline used across item rarities. Set alpha to zero to remove it.
@export var outline_color := Color("#141318"):
	set(value):
		if outline_color != value:
			outline_color = value
			emit_changed()
## Transparency of the dark leather grain over a placed item.
@export_range(0.0, 1.0, 0.01) var grain_opacity := 0.0:
	set(value):
		if grain_opacity != value:
			grain_opacity = value
			emit_changed()

@export_group("Placement Preview")
## Color used when an item can be placed in the indicated footprint.
@export_color_no_alpha var valid_drop_color := Color("#779e65"):
	set(value):
		if valid_drop_color != value:
			valid_drop_color = value
			emit_changed()
## Color used when the indicated footprint cannot accept an item.
@export_color_no_alpha var invalid_drop_color := Color("#ba7263"):
	set(value):
		if invalid_drop_color != value:
			invalid_drop_color = value
			emit_changed()
## Fill opacity inside the placement outline.
@export_range(0.0, 1.0, 0.01) var drop_fill_opacity := 0.29:
	set(value):
		if drop_fill_opacity != value:
			drop_fill_opacity = value
			emit_changed()
## Opacity of the highlight on compatible equipment slots. Zero hides it.
@export_range(0.0, 1.0, 0.01) var equipment_highlight_opacity := 0.90:
	set(value):
		if equipment_highlight_opacity != value:
			equipment_highlight_opacity = value
			emit_changed()


func placed_fill(unidentified: bool, highlighted: bool) -> Color:
	if highlighted and highlight_items:
		return unidentified_hover_fill if unidentified else identified_hover_fill
	return unidentified_fill if unidentified else identified_fill
