extends RefCounted
## Five independent storage endpoints using the same native grid as the pack.

const TAB_SIZE := Vector2i(12, 12)
const OWNERS := ["stash:0", "stash:1", "stash:2", "stash:3", "stash:4"]

var _tabs: Dictionary[String, SpatialInventory] = {}


func _init() -> void:
	for owner: String in OWNERS:
		var grid := SpatialInventory.new()
		grid.configure(TAB_SIZE)
		_tabs[owner] = grid


static func is_owner(owner: String) -> bool:
	return owner in OWNERS


func get_grid(owner: String) -> SpatialInventory:
	return _tabs.get(owner)


func has_grid(grid: SpatialInventory) -> bool:
	return grid in _tabs.values()
