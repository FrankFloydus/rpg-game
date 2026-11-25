extends RefCounted
## Adds one-cell-wide blind branches to established galleries.

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const BENDS: Array[Vector2i] = [Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 1), Vector2i(3, 2)]
const STRAIGHTS: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
const ARRIVAL_CLEARANCE_SQUARED := 64.0
const MAX_PASSAGES := 8
const MAX_TREASURE_PASSAGES := 5


static func carve(map_cells: Dictionary, corridors: Array[Dictionary], rooms: Array[Dictionary],
		depth: int, rng: RandomNumberGenerator, limits := Rect2i(), reserved: Dictionary = {}) -> Array[Dictionary]:
	var branches: Array[Dictionary] = []
	if rooms.is_empty():
		return branches

	var arrival_center: Vector2i = rooms[0].center
	var anchor_groups: Array[Array] = []
	for corridor in corridors:
		var endpoints: Vector2i = corridor.rooms
		if endpoints.x == 0 or endpoints.y == 0:
			continue
		var anchors: Array[Vector2i] = []
		for tile: Vector2i in corridor.tiles:
			var stays_clear_of_arrival := tile.distance_squared_to(arrival_center) >= ARRIVAL_CLEARANCE_SQUARED
			if stays_clear_of_arrival and not anchors.has(tile) and not reserved.has(tile) and _is_gallery_anchor(map_cells, tile):
				anchors.append(tile)
		if not anchors.is_empty():
			_shuffle(anchors, rng)
			anchor_groups.append(anchors)
	_shuffle(anchor_groups, rng)

	var budget := mini(MAX_PASSAGES, 3 + floori(float(maxi(0, depth - 1)) / 3.0))
	var treasure_count := 0
	var used_anchors := {}
	# Give each gallery one opportunity before trying a second branch on the same route.
	# Short straight ends are a fallback when the bend will not fit.
	for sweep in 2:
		for anchors: Array in anchor_groups:
			var branch := _find_branch(anchors, map_cells, used_anchors, rng, sweep == 1, limits)
			if branch.is_empty():
				continue
			var treasure := treasure_count < 2 or (
				treasure_count < MAX_TREASURE_PASSAGES and rng.randf() < 0.68)
			branch["treasure"] = treasure
			treasure_count += int(treasure)
			used_anchors[branch.anchor] = true
			for tile: Vector2i in branch.cells:
				map_cells[tile] = -1
			branches.append(branch)
			if branches.size() == budget:
				return branches
	return branches


static func _is_gallery_anchor(map_cells: Dictionary, tile: Vector2i) -> bool:
	if map_cells.get(tile) != -1:
		return false
	var gallery_neighbors := 0
	for direction in DIRECTIONS:
		var neighbor: int = map_cells.get(tile + direction, -2)
		if neighbor >= 0:
			return false
		gallery_neighbors += int(neighbor == -1)
	return gallery_neighbors == 2


static func _find_branch(anchors: Array, map_cells: Dictionary, used_anchors: Dictionary,
		rng: RandomNumberGenerator, allow_straight: bool, limits: Rect2i) -> Dictionary:
	for anchor: Vector2i in anchors:
		if used_anchors.has(anchor) or not _is_gallery_anchor(map_cells, anchor):
			continue
		var headings := DIRECTIONS.duplicate()
		_shuffle(headings, rng)
		for heading: Vector2i in headings:
			if map_cells.has(anchor + heading):
				continue
			var path := _try_heading(anchor, heading, map_cells, rng, allow_straight, limits)
			if not path.is_empty():
				return {"anchor": anchor, "tip": path.back(), "cells": path}
	return {}


static func _try_heading(anchor: Vector2i, heading: Vector2i, map_cells: Dictionary,
		rng: RandomNumberGenerator, allow_straight: bool, limits: Rect2i) -> Array[Vector2i]:
	var run_lengths := BENDS.duplicate()
	_shuffle(run_lengths, rng)
	if allow_straight:
		var straight_lengths := STRAIGHTS.duplicate()
		_shuffle(straight_lengths, rng)
		run_lengths.append_array(straight_lengths)
	var across := Vector2i(-heading.y, heading.x)
	if rng.randf() < 0.5:
		across = -across
	for lengths: Vector2i in run_lengths:
		var path := _make_path(anchor, heading, across, lengths)
		if _is_clear(anchor, path, map_cells, limits):
			return path
		if lengths.y > 0:
			path = _make_path(anchor, heading, -across, lengths)
			if _is_clear(anchor, path, map_cells, limits):
				return path
	return []


static func _make_path(anchor: Vector2i, heading: Vector2i, across: Vector2i,
		lengths: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for step in range(1, lengths.x + 1):
		cells.append(anchor + heading * step)
	var corner := anchor + heading * lengths.x
	for step in range(1, lengths.y + 1):
		cells.append(corner + across * step)
	return cells


static func _is_clear(anchor: Vector2i, cells: Array[Vector2i], map_cells: Dictionary, limits: Rect2i) -> bool:
	for index in cells.size():
		var tile := cells[index]
		if map_cells.has(tile) or (limits.has_area() and not limits.has_point(tile)):
			return false
		for direction in DIRECTIONS:
			var neighbor := tile + direction
			# The branch may touch the established layout only at its mouth.
			if map_cells.has(neighbor) and (index != 0 or neighbor != anchor):
				return false
	return true


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var original: Variant = items[index]
		items[index] = items[other]
		items[other] = original

