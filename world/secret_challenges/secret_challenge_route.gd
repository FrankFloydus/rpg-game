@tool
class_name SecretChallengeRoute
extends Resource
## Authored route behind a secret passage. Both forms share the same hidden door.

const Socket := preload("res://world/secret_challenges/secret_challenge_socket.gd")
const MISSING_CELL := Vector2i(-1, -1)

## Stable route identifier stored in seeded layouts.
@export var id: StringName
## Display name used to identify the route in the World editor.
@export var display_name := ""
## First expedition depth at which this route can be selected.
@export_range(1, 30, 1) var min_depth := 2
## Relative selection weight among eligible routes that fit.
@export_range(0.01, 10.0, 0.01) var weight := 1.0
## Enter at S on the west edge. R is the coffer, . is floor, # is empty, and digits are sockets.
@export var rows: PackedStringArray
## Optional second set of tiles, with its own authored extension, turn or shortened ending.
@export var alternate_rows: PackedStringArray
## Floor fixtures that can appear where their digit is present.
@export var hazard_sockets: Array[Socket]


func ingress(alternate := false) -> Vector2i:
	return _find("S", alternate)


func reward(alternate := false) -> Vector2i:
	return _find("R", alternate)


func floor_cells(alternate := false) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var active_rows := _layout(alternate)
	for row in active_rows.size():
		for column in active_rows[row].length():
			if active_rows[row][column] != "#":
				cells.append(Vector2i(column, row))
	return cells


func sockets(alternate := false) -> Dictionary[Vector2i, Socket]:
	var fixtures: Dictionary[Vector2i, Socket] = {}
	for socket in hazard_sockets:
		if socket == null:
			continue
		var cell := _find(socket.glyph, alternate)
		if cell != MISSING_CELL:
			fixtures[cell] = socket
	return fixtures


func _find(glyph: String, alternate: bool) -> Vector2i:
	var active_rows := _layout(alternate)
	for row in active_rows.size():
		var column := active_rows[row].find(glyph)
		if column >= 0:
			return Vector2i(column, row)
	return MISSING_CELL


func _layout(alternate: bool) -> PackedStringArray:
	return alternate_rows if alternate and not alternate_rows.is_empty() else rows
