extends RefCounted
## Owns the one displaced backpack item on the cursor and the expected placement changes for cancellation.

const NO_FIT := Vector2i(-1, -1)

var detached: Dictionary = {}
var _journal: Dictionary[StringName, Dictionary] = {}


func preview(grid: SpatialInventory, id: StringName, origin: Vector2i, rotated: bool) -> Dictionary:
	if rotated:
		return {"denial": "Items keep their original orientation."}
	var before := grid.get_placement(id)
	var source := detached if not detached.is_empty() and detached.id == id else before
	if source.is_empty() or (not detached.is_empty() and detached.id != id):
		return {"denial": "That item has moved."}
	var footprint: Vector2i = source.footprint
	var area := Rect2i(origin, footprint)
	if not Rect2i(Vector2i.ZERO, grid.get_grid_size()).encloses(area):
		return {"denial": "That item will not fit there."}
	var displaced := &""
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var occupant := grid.get_item_at(Vector2i(x, y))
			if occupant.is_empty() or occupant == id:
				continue
			if not displaced.is_empty() and displaced != occupant:
				return {"denial": "That item overlaps more than one item."}
			displaced = occupant
	var destination := {"id": id, "origin": origin, "footprint": footprint, "rotated": false}
	var rows := [_row(grid, id, before, destination)]
	if not displaced.is_empty():
		rows.append(_row(grid, displaced, grid.get_placement(displaced), {}))
	return {"denial": "", "rows": rows, "displaced": displaced}


func place(grid: SpatialInventory, id: StringName, origin: Vector2i, rotated: bool) -> Dictionary:
	var plan := preview(grid, id, origin, rotated)
	if not plan.denial.is_empty():
		return plan
	var rows: Array = plan.rows
	if SpatialInventory.apply_placement_changes(rows) != OK:
		return {"denial": "The backpack changed before the move could finish."}
	if rows.size() == 1:
		settle()
	else:
		for row: Dictionary in rows:
			var item_id: StringName = row.id
			var history: Dictionary = _journal.get_or_add(item_id, {"original": row.before})
			history["current"] = row.after
		detached = rows[1].before
	return {"denial": "", "displaced": detached}


func cancel(grid: SpatialInventory) -> bool:
	if detached.is_empty():
		return true
	if SpatialInventory.apply_placement_changes(_rollback_rows(grid)) != OK:
		var position := grid.find_first_fit(detached.footprint)
		if position == NO_FIT or grid.try_place(detached.id, detached.footprint, position) != OK:
			return false
	settle()
	return true


func settle() -> void:
	detached = {}
	_journal.clear()


func safe_layout(grid: SpatialInventory) -> SpatialInventory:
	if detached.is_empty():
		return grid
	var checkpoint := SpatialInventory.new()
	if checkpoint.import_snapshot(grid.export_snapshot()) != OK:
		return null
	return checkpoint if SpatialInventory.apply_placement_changes(_rollback_rows(checkpoint)) == OK else null


func _rollback_rows(grid: SpatialInventory) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: StringName in _journal:
		var history := _journal[id]
		rows.append(_row(grid, id, history.current, history.original))
	return rows


static func _row(grid: SpatialInventory, id: StringName, before: Dictionary, after: Dictionary) -> Dictionary:
	return {"inventory": grid, "id": id, "before": before, "after": after}
