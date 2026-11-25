extends Node3D

signal breakable_destroyed(id: String, reward_position: Vector3)

const EnemyCatalog = preload("res://combat/enemies/enemy_catalog.gd")
const ExpeditionRules := preload("res://data/expedition_rules.tres")
const DungeonLayout = preload("res://world/dungeon_layout.gd")
const DungeonNavMesh = preload("res://world/dungeon_navmesh.gd")
const DungeonTilesets := preload("res://world/dungeon_tilesets.gd")
const CofferPlacement = preload("res://world/coffer_placement.gd")
const SidePassages = preload("res://world/dungeon_side_passages.gd")
const SecretMerchantRules := preload("res://data/secret_merchant_rules.tres")
const SecretChallenges := preload("res://world/dungeon_secret_challenges.gd")
const RouteGates = preload("res://world/dungeon_route_gates.gd")
const ChallengeChambers = preload("res://world/dungeon_challenge_chambers.gd")
const EdgeDressing = preload("res://world/dungeon_edge_dressing.gd")
const Setpieces = preload("res://world/dungeon_setpieces.gd")
const CryptCell = preload("res://world/modules/crypt_cell.tscn")
const BloodFloorShader := preload("res://world/modules/blood_floor.gdshader")
const BloodFloorProjection := preload("res://world/modules/blood_floor_projection.tscn")
const StairFlight = preload("res://world/modules/crypt_stair_flight.gd")
const StairFlightScene = preload("res://world/modules/crypt_stair_flight.tscn")
const WORN_LINEN := preload("res://assets/grounded/worn_linen.png")
const FORGED_STEEL := preload("res://assets/rework/materials/forged_steel.tres")
const WEATHERED_BRONZE := preload("res://assets/rework/materials/weathered_bronze.tres")
const ROOM_FIXTURES := {
	&"Doorway": preload("res://world/modules/crypt_doorway.tscn"),
	&"StonePortal": preload("res://world/modules/crypt_stone_portal.tscn"),
	&"Sentinel": preload("res://world/modules/crypt_sentinel.tscn"),
	&"Brazier": preload("res://world/modules/crypt_brazier.tscn"),
	&"Sconce": preload("res://world/modules/crypt_sconce.tscn"),
}
const COVER_SCENES := [
	preload("res://world/modules/cover_pillar.tscn"),
	preload("res://world/modules/cover_sarcophagus.tscn"),
	preload("res://world/modules/cover_altar.tscn"),
]

const CONNECTED_FLOOR_VERSION := 5
const GENERATION_VERSION := 10
const AMBUSH_GENERATION_VERSION := 6
const GATE_GENERATION_VERSION := 7
const TRIAL_COFFER_GENERATION_VERSION := 8
const EXPANDED_ROSTER_VERSION := 9
const AUTHORED_SECRET_VERSION := 10
const FEATURE_THRESHOLD_AMBUSH := 1
const FEATURE_COFFER_AMBUSH := 2
const FEATURE_ROUTE_GATE := 4
const FEATURE_TRIAL_COFFER := 8
const FEATURE_BLOOD_ALTAR := 16
const FEATURE_PLATFORM_CHAMBER := 32
const FEATURE_LAVA_CHAMBER := 64
const FEATURE_SUBMERGED_CHAMBER := 128
const FEATURE_SECRET_MERCHANT := 256
const GRAVE_THRALL_ARCHETYPE := 0
const OSSUARY_ARCHER_ARCHETYPE := 1
const CRYPT_SCURRER_ARCHETYPE := 27

const CELL_SIZE := 3.4
const CEILING_HEIGHT := 4.15
const PLATFORM_CEILING_HEIGHT := 6.76
const ROOM_STRIDE := 9
const CHUNK_SIZE := 5
const MAX_ROOMS := 19
const NORTH := Vector2i(0, -1)
const DIRECTIONS: Array[Vector2i] = [NORTH, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

const IRON := &"iron"
const UPPER_STONE := &"upper_stone"
const BRONZE := &"bronze"
const CLOTH := &"cloth"
const CLOTH_TRIM := &"cloth_trim"

var spawn_position := Vector3.ZERO
var spawn_yaw := 0.0
var map_cells: Dictionary = {}
var room_bounds: Array[Rect2i] = []
var rooms: Array[Dictionary] = []
var room_names: Dictionary = {}
var topology: StringName = &"legacy"
var depth_theme: StringName = &"iron_crypt"
## Set by the expedition once, before building any of its floors.
var tileset_id: StringName = DungeonTilesets.DEFAULT
var hazard_points: Array[Dictionary] = []
var encounters: Array[Dictionary] = []
var chests: Array[Dictionary] = []
var coffer_tiles: Dictionary[Vector2i, bool] = {}
var side_passages: Array[Dictionary] = []
var secret_passages: Array[Dictionary] = []
var secret_merchant_position := Vector3.INF
var secret_merchant_yaw := 0.0
var secret_merchant_passage := ""
var route_gates: Array[Dictionary] = []
var blood_altar_position := Vector3.INF
var lava_floor: Dictionary = {}
var submerged_basin: Dictionary = {}
var challenge_chamber: Dictionary = {}
var stairs: Dictionary[int, Node3D] = {}
var stair_tiles: Dictionary[int, Vector2i] = {}
var stair_approach_tiles: Dictionary[Vector2i, bool] = {}

var _generation_version := 1
var _room_limit := MAX_ROOMS
var _population_scale := 1.0
var _feature_mask := -1
var _stair_edges: Dictionary[Vector2i, Vector2i] = {}
var _stair_overruns: Dictionary[Vector2i, bool] = {}
var _floor_cutouts: Array[Rect2] = []
var _palette: Dictionary
var _cover_tiles: Dictionary = {}
var _coffer_poses: Dictionary[int, Transform3D] = {}
var _room_centers: Array[Vector2i] = []
var _links: Array[Vector2i] = []
var _thresholds: Dictionary = {}
var _routed_ports: Array[Vector4i] = []
var _passage_frames: Dictionary = {}
var _batches: Dictionary = {}
var _colliders: Dictionary = {}
var _floor_body: StaticBody3D
var _floor_geometry := Geometry.new()
var _floor_material: ShaderMaterial
var _materials: Dictionary = {}
var _module_meshes: Dictionary = {}
var _module_collisions: Dictionary = {}
var _module_materials: Dictionary = {}
var _module_effects: Dictionary = {}
var _navigation := AStarGrid2D.new()
var _navigation_region: NavigationRegion3D
var _native_query := NavigationPathQueryParameters3D.new()
var _native_result := NavigationPathQueryResult3D.new()
var _navigation_context := RID()
var _navigation_iteration := 0
var _navigation_blockers: Array[CollisionShape3D] = []
var _breakable_props: Dictionary[String, Node3D] = {}
var _rng := RandomNumberGenerator.new()
var _arrival_gate := NORTH
var _torches: Array[OmniLight3D] = []
var _torch_energies := PackedFloat32Array()
var _torch_elapsed := 0.0
var _torch_sample := 0.0


class Geometry:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()

	func append_mesh(source: Array, placement: Transform3D, tint: Color) -> void:
		var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL] if source[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var source_tangents: PackedFloat32Array = source[Mesh.ARRAY_TANGENT] if source[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var source_uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV] if source[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var source_colors: PackedColorArray = source[Mesh.ARRAY_COLOR] if source[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX] if source[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var normal_basis := placement.basis.inverse().transposed()
		var mirrored := placement.basis.determinant() < 0.0
		for corner in (points.size() if indices.is_empty() else indices.size()):
			var ordered_corner := corner
			if mirrored and corner % 3 != 0:
				ordered_corner += 1 if corner % 3 == 1 else -1
			var index := ordered_corner if indices.is_empty() else indices[ordered_corner]
			vertices.append(placement * points[index])
			var normal := source_normals[index] if index < source_normals.size() else Vector3.UP
			normals.append((normal_basis * normal).normalized())
			var offset := index * 4
			var tangent := Vector3.RIGHT
			var handedness := 1.0
			if offset + 3 < source_tangents.size():
				tangent = Vector3(source_tangents[offset], source_tangents[offset + 1], source_tangents[offset + 2])
				handedness = source_tangents[offset + 3]
			tangent = (placement.basis * tangent).normalized()
			tangents.append(tangent.x)
			tangents.append(tangent.y)
			tangents.append(tangent.z)
			tangents.append(-handedness if mirrored else handedness)
			uvs.append(source_uvs[index] if index < source_uvs.size() else Vector2.ZERO)
			colors.append(source_colors[index] * tint if index < source_colors.size() else tint)

	func quad(
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
		uv_size := Vector2.ONE, tint := Color.WHITE
	) -> void:
		var points := [a, b, c, d]
		var texcoords := [Vector2.ZERO, Vector2(uv_size.x, 0.0), uv_size, Vector2(0.0, uv_size.y)]
		var tangent := (b - a).normalized()
		var handedness := -1.0 if normal.cross(tangent).dot(d - a) < 0.0 else 1.0
		var order := [0, 1, 2, 0, 2, 3]
		if (b - a).cross(c - a).dot(normal) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for index: int in order:
			vertices.append(points[index])
			normals.append(normal)
			tangents.append(tangent.x)
			tangents.append(tangent.y)
			tangents.append(tangent.z)
			tangents.append(handedness)
			uvs.append(texcoords[index])
			colors.append(tint)

	func box(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
		var x := basis.x * size.x * 0.5
		var y := basis.y * size.y * 0.5
		var z := basis.z * size.z * 0.5
		quad(center - x - y + z, center + x - y + z, center + x + y + z, center - x + y + z, basis.z)
		quad(center + x - y - z, center - x - y - z, center - x + y - z, center + x + y - z, -basis.z)
		quad(center + x - y + z, center + x - y - z, center + x + y - z, center + x + y + z, basis.x)
		quad(center - x - y - z, center - x - y + z, center - x + y + z, center - x + y - z, -basis.x)
		quad(center - x + y + z, center + x + y + z, center + x + y - z, center - x + y - z, basis.y)
		quad(center - x - y - z, center + x - y - z, center + x - y + z, center - x - y + z, -basis.y)

	func taper(
		center: Vector3, lower: Vector2, upper: Vector2, height: float, basis: Basis,
		tint := Color.WHITE
	) -> void:
		for edge in range(8):
			var start := TAU * float(edge) / 8.0
			var end := TAU * float(edge + 1) / 8.0
			var first := Vector2(cos(start), sin(start))
			var last := Vector2(cos(end), sin(end))
			var a := center + basis * Vector3(first.x * lower.x, 0.0, first.y * lower.y)
			var b := center + basis * Vector3(last.x * lower.x, 0.0, last.y * lower.y)
			var c := center + basis * Vector3(last.x * upper.x, height, last.y * upper.y)
			var d := center + basis * Vector3(first.x * upper.x, height, first.y * upper.y)
			var normal := (d - a).cross(b - a).normalized()
			quad(a, b, c, d, normal, Vector2.ONE, tint)
			if edge % 2 == 0:
				var cap := center + basis.y * height
				var third_angle := TAU * float(edge + 2) / 8.0
				var third := cap + basis * Vector3(cos(third_angle) * upper.x, 0.0, sin(third_angle) * upper.y)
				quad(cap, d, c, third, basis.y, Vector2.ONE, tint)

	func arrays() -> Array:
		var result := []
		result.resize(Mesh.ARRAY_MAX)
		result[Mesh.ARRAY_VERTEX] = vertices
		result[Mesh.ARRAY_NORMAL] = normals
		result[Mesh.ARRAY_TANGENT] = tangents
		result[Mesh.ARRAY_TEX_UV] = uvs
		result[Mesh.ARRAY_COLOR] = colors
		return result


func build(level: int, run_seed: int, generation_version: int = GENERATION_VERSION,
		floor_index := 0, floor_count := 1, room_limit := MAX_ROOMS, floor_rise := -1, features := -1) -> void:
	assert(map_cells.is_empty(), "Build a fresh dungeon node for each run.")
	_generation_version = clampi(generation_version, 1, GENERATION_VERSION)
	_feature_mask = features if _generation_version >= TRIAL_COFFER_GENERATION_VERSION else -1
	_room_limit = clampi(room_limit, 6, MAX_ROOMS)
	if _generation_version >= 4 and floor_count > 1:
		_population_scale = 0.79 if floor_count == 2 else 0.70
	_rng.seed = run_seed
	var depth := maxi(1, level)
	if _generation_version == 1:
		_layout_legacy(depth)
	else:
		_layout_expedition(depth, run_seed, floor_index, floor_count, floor_rise)
	if _generation_version == 4 and floor_count > 1:
		_plan_stairs(floor_index, floor_count)
	_palette = _lighting_palette()
	_build_navigation()
	_build_materials()
	_load_geometry_modules()
	if _generation_version < 5 or floor_index == 0:
		_build_environment()
	else:
		var environment := get_node_or_null("UndercroftAir")
		if environment != null:
			environment.free()
	_build_shell()
	if _generation_version == 1:
		_populate_legacy(depth)
	_seat_coffers(run_seed)
	if _generation_version == 1:
		_build_legacy_chambers()
	else:
		_build_expedition_chambers(run_seed, depth, floor_index)
	ChallengeChambers.room_floor_geometry(self, challenge_chamber)
	_flush_meshes()
	_module_meshes.clear()
	_module_collisions.clear()
	_module_materials.clear()
	_module_effects.clear()
	var navigation_blocked := _cover_tiles
	if not submerged_basin.is_empty():
		navigation_blocked = _cover_tiles.duplicate()
		navigation_blocked[challenge_chamber.tile] = true
	_navigation_region = DungeonNavMesh.build(self, map_cells, navigation_blocked, CELL_SIZE, _navigation_blockers)
	_navigation_blockers.clear()
	add_child(_navigation_region)
	_native_query.navigation_layers = navigation_layers()
	_native_query.metadata_flags = 0
	_native_query.simplify_path = true
	_native_query.simplify_epsilon = 0.06
	# The default 4,096-polygon search can return a partial path across deep layouts.
	_native_query.path_search_max_polygons = 32768


func _process(delta: float) -> void:
	_torch_elapsed += delta
	_torch_sample += delta
	if _torch_sample < 0.075:
		return
	_torch_sample = 0.0
	for index in range(_torches.size()):
		var phase := _torch_elapsed + float(index) * 2.061
		_torches[index].light_energy = _torch_energies[index] * (0.91 + 0.07 * sin(phase * 8.0) + 0.04 * sin(phase * 19.0))


func tile_at(point: Vector3) -> Vector2i:
	var local := to_local(point) if is_inside_tree() else point
	return Vector2i(roundi(local.x / CELL_SIZE), roundi(local.z / CELL_SIZE))


func tile_position(tile: Vector2i) -> Vector3:
	return Vector3(tile.x * CELL_SIZE, 0.0, tile.y * CELL_SIZE)


func wall_texture() -> Texture2D:
	return DungeonTilesets.albedo(tileset_id, &"wall")


func wall_repeats_per_metre() -> float:
	return DungeonTilesets.repeats_per_metre(tileset_id, &"wall")


func ground_is_open(point: Vector3) -> bool:
	var tile := tile_at(point)
	if map_cells.has(tile):
		return not _cover_tiles.has(tile)
	return _generation_version >= 5 and not stairs.is_empty() and is_inside_tree() and floor_contains(point)


func floor_contains(point: Vector3) -> bool:
	var local := to_local(point)
	var tile := tile_at(point)
	var room := int(map_cells.get(tile, -2))
	var bottom := -ChallengeChambers.BATH_DEPTH - 0.15 if _is_basin_tile(tile) else -0.4
	var ceiling := PLATFORM_CEILING_HEIGHT if _is_tall_room(room) else CEILING_HEIGHT
	if room > -2 and local.y >= bottom and local.y < ceiling:
		return true
	for flight: Node3D in stairs.values():
		var stair_local := flight.transform.affine_inverse() * local
		if absf(stair_local.x) < CELL_SIZE * 0.5 and stair_local.z <= 0.0 \
				and stair_local.z >= -StairFlight.LENGTH and absf(stair_local.y) < CEILING_HEIGHT:
			return true
	return false


func stair_slope(direction: int) -> int:
	var flight: Node3D = stairs[direction]
	return -1 if flight.landing_endpoint().y > flight.position.y else 1


## Fits each continuous floor to its preceding one. The two open half-flights meet at a landing.
## Both nodes use transforms relative to the same expedition root.
static func join_floors(previous: Node3D, next: Node3D) -> void:
	var outgoing: Node3D = previous.stairs[1]
	var incoming: Node3D = next.stairs[-1]
	var outward := previous.transform.basis * -outgoing.basis.z
	var inward := incoming.basis.z
	var alignment := Basis(Vector3.UP, atan2(outward.x, outward.z) - atan2(inward.x, inward.z))
	var shared_landing: Vector3 = previous.transform * outgoing.landing_endpoint()
	var next_landing: Vector3 = incoming.landing_endpoint()
	next.transform = Transform3D(alignment, shared_landing - alignment * next_landing)
	var link := NavigationLink3D.new()
	link.name = "InterfloorStairNavigation"
	link.start_position = previous.tile_position(previous.stair_tiles[1])
	link.end_position = previous.transform.affine_inverse() * (next.transform * next.tile_position(next.stair_tiles[-1]))
	link.navigation_layers = DungeonNavMesh.NAVIGATION_LAYER
	previous.add_child(link)


func navigation_map() -> RID:
	if not is_inside_tree() or _navigation_region == null:
		return RID()
	var context := _navigation_region.get_navigation_map()
	if not context.is_valid():
		return RID()
	var iteration := NavigationServer3D.map_get_iteration_id(context)
	if iteration == 0:
		return RID()
	if _navigation_context != context or _navigation_iteration != iteration:
		# A region can already be registered while its polygons are still synchronizing.
		if NavigationServer3D.map_get_closest_point_owner(context, to_global(spawn_position)) != _navigation_region.get_rid():
			return RID()
		_navigation_context = context
		_navigation_iteration = iteration
	return _navigation_context


func navigation_layers() -> int:
	return DungeonNavMesh.NAVIGATION_LAYER


func navigation_route(start: Vector3, target: Vector3) -> PackedVector3Array:
	var context := navigation_map()
	if not context.is_valid():
		return PackedVector3Array()
	var destination := NavigationServer3D.map_get_closest_point(context, target)
	if destination.distance_to(target) > CELL_SIZE * 0.5:
		return PackedVector3Array()
	_native_query.map = context
	_native_query.start_position = start
	_native_query.target_position = destination
	NavigationServer3D.query_path(_native_query, _native_result)
	var path := _native_result.get_path()
	if path.is_empty() or path[-1].distance_to(destination) > 0.3:
		return PackedVector3Array()
	return path


func route(start: Vector3, target: Vector3) -> PackedVector3Array:
	var first := _route_tile(start)
	var last := _route_tile(target)
	var points := PackedVector3Array()
	if not map_cells.has(first) or not map_cells.has(last):
		return points
	var path := _navigation.get_id_path(first, last)
	if path.is_empty():
		return points
	if _cover_tiles.has(tile_at(start)):
		var center := tile_position(first)
		points.append(to_global(center) if is_inside_tree() else center)
	for index in range(1, path.size() - 1):
		if path[index] - path[index - 1] != path[index + 1] - path[index]:
			var center := tile_position(path[index])
			points.append(to_global(center) if is_inside_tree() else center)
	if path.size() > 1 or _cover_tiles.has(tile_at(target)):
		# Reach the safe center of the destination tile before crossing it diagonally.
		var center := tile_position(last)
		points.append(to_global(center) if is_inside_tree() else center)
	points.append(target)
	return points


func _route_tile(point: Vector3) -> Vector2i:
	var tile := tile_at(point)
	if not _cover_tiles.has(tile):
		return tile
	var closest := tile
	var best := INF
	var local := to_local(point) if is_inside_tree() else point
	for step in DIRECTIONS:
		var neighbor := tile + step
		var distance := tile_position(neighbor).distance_squared_to(local)
		if distance < best and map_cells.has(neighbor) and not _cover_tiles.has(neighbor):
			closest = neighbor
			best = distance
	return closest


func _layout_expedition(depth: int, seed_value: int, floor_index: int, floor_count: int, floor_rise: int) -> void:
	if depth >= 9:
		depth_theme = &"blighted_ossuary"
	elif depth >= 6:
		depth_theme = &"ashen_catacomb"
	elif depth >= 3:
		depth_theme = &"drowned_vault"
	var layout := DungeonLayout.new()
	layout.generate(depth, seed_value, _room_limit, _generation_version)
	topology = layout.topology
	rooms = layout.rooms
	map_cells = layout.map_cells
	_arrival_gate = layout.gate
	if _generation_version == 4:
		side_passages = SidePassages.carve(map_cells, layout.corridors, rooms, depth, layout.rng)
		_plan_secret_passages(depth, layout.rng)
	for corridor in layout.corridors:
		_routed_ports.append_array(corridor.get("ports", []))
	for room in rooms:
		room_bounds.append(room.bounds)
		_room_centers.append(room.center)
		for tile: Vector2i in room.doors:
			_thresholds[tile] = true
	spawn_position = tile_position(_room_centers[0])
	spawn_yaw = atan2(-float(_arrival_gate.x), -float(_arrival_gate.y))
	var branch_bounds := Rect2i()
	if _generation_version >= 5:
		if floor_count > 1:
			_plan_continuous_stairs(floor_index, floor_count, floor_rise)
		if floor_count > 1:
			branch_bounds = Rect2i(map_cells.keys()[0], Vector2i.ONE)
			for tile: Vector2i in map_cells:
				branch_bounds = branch_bounds.expand(tile).expand(tile + Vector2i.ONE)
			# Only constrain the stair axis. Branches may grow into unoccupied masonry to either side.
			if _arrival_gate.x != 0:
				branch_bounds = branch_bounds.grow_individual(0, 10, 0, 10)
			else:
				branch_bounds = branch_bounds.grow_individual(10, 0, 10, 0)
		side_passages = SidePassages.carve(map_cells, layout.corridors, rooms, depth, layout.rng,
			branch_bounds, stair_approach_tiles)
		_plan_secret_passages(depth, layout.rng, branch_bounds)
	_plan_challenge_chamber(seed_value)
	_plan_secret_merchant(depth, seed_value)
	if _generation_version >= AUTHORED_SECRET_VERSION:
		SecretChallenges.try_place(self, depth, seed_value, branch_bounds)
	_populate_expedition(depth, seed_value, layout.corridors, floor_index)


func _plan_challenge_chamber(seed_value: int) -> void:
	if _generation_version < EXPANDED_ROSTER_VERSION:
		return
	var kind := ""
	if _feature_enabled(FEATURE_PLATFORM_CHAMBER, false):
		kind = ChallengeChambers.PLATFORM
	elif _feature_enabled(FEATURE_LAVA_CHAMBER, false):
		kind = ChallengeChambers.LAVA
	elif _feature_enabled(FEATURE_SUBMERGED_CHAMBER, false):
		kind = ChallengeChambers.SUBMERGED
	if kind.is_empty():
		return
	challenge_chamber = ChallengeChambers.choose(self, kind, seed_value)
	if challenge_chamber.is_empty():
		return
	var center: Vector3 = challenge_chamber.position
	if kind == ChallengeChambers.LAVA:
		lava_floor = {"position": center, "extent": challenge_chamber.lava_extent}
	elif kind == ChallengeChambers.SUBMERGED:
		var bath: Rect2 = challenge_chamber.bath_rect
		_floor_cutouts.append(bath)
		submerged_basin = {"position": center + Vector3.UP * ChallengeChambers.WATER_SURFACE,
			"extent": Vector3(bath.size.x, ChallengeChambers.BATH_DEPTH + ChallengeChambers.WATER_SURFACE, bath.size.y)}


func _is_basin_tile(tile: Vector2i) -> bool:
	return not submerged_basin.is_empty() and challenge_chamber.tile == tile


func _is_tall_room(room: int) -> bool:
	return challenge_chamber.get("kind") == ChallengeChambers.PLATFORM and challenge_chamber.room == room


func _plan_secret_passages(depth: int, rng: RandomNumberGenerator, limits := Rect2i()) -> void:
	var candidates: Array[Dictionary] = []
	for branch_index in side_passages.size():
		var passage: Dictionary = side_passages[branch_index]
		if not passage.treasure:
			continue
		var tiles: Array[Vector2i] = passage.cells
		for index in range(1, tiles.size()):
			var approach := tiles[index - 1]
			var first := tiles[index]
			var forward := first - approach
			var across := Vector2i(-forward.y, forward.x)
			if map_cells.has(first + across) or map_cells.has(first - across):
				continue
			var tangent := Vector3(forward.x, 0.0, forward.y)
			candidates.append({
				"position": tile_position(approach) + tangent * (CELL_SIZE * 0.5),
				"yaw": atan2(-tangent.x, -tangent.z),
				"hidden_tiles": tiles.slice(index), "wall_tint": _lighting_palette().wall,
			})
			if _generation_version >= 5:
				candidates[-1]["branch"] = branch_index
				candidates[-1]["entry"] = index
			break
	var limit := mini(candidates.size(), 2 if depth >= 6 and candidates.size() > 2 else 1)
	for index in limit:
		var secret: Dictionary = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		secret["id"] = "hidden_%d" % index
		if _generation_version >= 5:
			var passage: Dictionary = side_passages[secret.branch]
			var annex := _secret_annex(passage.cells, int(secret.entry), limits)
			# Preserve shorter cache pockets so the number of rewards is itself a surprise.
			if annex != Vector4i.ZERO and (index == 0 or rng.randf() < 0.70):
				var annex_tile := Vector2i(annex.x, annex.y)
				passage["annex"] = annex
				map_cells[annex_tile] = -1
				secret.hidden_tiles.append(annex_tile)
		secret_passages.append(secret)


func _secret_annex(path: Array[Vector2i], entry: int, limits: Rect2i) -> Vector4i:
	# A second pocket branches past the concealed wall and keeps both chests at wall ends.
	for index in range(path.size() - 2, entry - 1, -1):
		var landing := path[index]
		var forward := path[index + 1] - landing
		var across := Vector2i(-forward.y, forward.x)
		for direction: Vector2i in [across, -across]:
			var tile := landing + direction
			if map_cells.has(tile) or (limits.has_area() and not limits.has_point(tile)):
				continue
			var clear := true
			for side in DIRECTIONS:
				if tile + side != landing and map_cells.has(tile + side):
					clear = false
			if clear:
				return Vector4i(tile.x, tile.y, direction.x, direction.y)
	return Vector4i.ZERO


func _plan_secret_merchant(depth: int, seed_value: int) -> void:
	if _generation_version < EXPANDED_ROSTER_VERSION or depth < SecretMerchantRules.minimum_depth \
			or not _feature_enabled(FEATURE_SECRET_MERCHANT, false):
		return
	var chosen: Dictionary = {}
	var best := -INF
	for secret: Dictionary in secret_passages:
		var candidate_branch: Dictionary = side_passages[secret.branch]
		var candidate_path: Array[Vector2i] = candidate_branch.cells
		var final_tile: Vector2i = candidate_branch.tip
		if final_tile not in secret.hidden_tiles or stair_approach_tiles.has(final_tile):
			continue
		if not challenge_chamber.is_empty() and final_tile == challenge_chamber.tile:
			continue
		var concealed_length := candidate_path.size() - int(secret.entry)
		var score := float(concealed_length) + float(posmod(hash([seed_value, final_tile]), 1000)) / 1000.0
		if score > best:
			best = score
			chosen = secret
	if chosen.is_empty():
		return
	var branch: Dictionary = side_passages[chosen.branch]
	var path: Array[Vector2i] = branch.cells
	var tip := path[-1]
	var inward := tip - path[-2]
	var heading := Vector3(inward.x, 0.0, inward.y)
	secret_merchant_position = tile_position(tip) + heading * 0.72
	secret_merchant_yaw = atan2(-heading.x, -heading.z)
	secret_merchant_passage = String(chosen.id)
	branch["merchant"] = true


func _populate_expedition(depth: int, seed_value: int, corridors: Array[Dictionary], floor_index: int) -> void:
	_rng.seed = seed_value + 81771
	var bonus_cache_tiles: Array[Vector2i] = []
	var hazard_budget := mini(7, 2 + floori((depth - 2) * 0.5)) if depth >= 2 else 0
	var ordinary_chest_count := 2 + mini(2, floori(depth / 4.0))
	var challenge_room := int(challenge_chamber.get("room", -1))
	var spare_rooms: Array[int] = []
	for room in rooms:
		var id: int = room.id
		if id > 1 and id != challenge_room and room.role != &"vault":
			spare_rooms.append(id)
	var ordinary_chests := {}
	for index in range(mini(ordinary_chest_count, spare_rooms.size())):
		var id: int = spare_rooms.pop_at(_rng.randi_range(0, spare_rooms.size() - 1))
		ordinary_chests[id] = index == 0

	var occupied := stair_approach_tiles.duplicate() if _generation_version >= 5 else {}
	for secret in secret_passages:
		for tile: Vector2i in secret.hidden_tiles:
			occupied[tile] = true
	for passage in side_passages:
		if not passage.treasure:
			continue
		var tip: Vector2i = passage.tip
		var previous: Vector2i = passage.cells[-2]
		var forward := Vector3(tip.x - previous.x, 0.0, tip.y - previous.y)
		if not passage.get("merchant", false):
			chests.append({"id": chests.size(), "position": tile_position(tip) + forward * 0.80,
				"yaw": atan2(-forward.x, -forward.z), "room": -1,
				"locked": false, "guarded": false, "side_cache": true, "secret_cache": occupied.has(tip)})
			if passage.get("bonus_coffer", false):
				bonus_cache_tiles.append(tip)
		occupied[tip] = true
		var locked_annex: bool = (passage.has("annex") or passage.get("replaced_annex", false)) \
			and depth >= 3 and _rng.randf() < 0.44
		if passage.has("annex"):
			var annex: Vector4i = passage.annex
			var alcove := Vector2i(annex.x, annex.y)
			chests.append({"id": chests.size(), "position": tile_position(alcove), "room": -1,
				"locked": locked_annex, "guarded": false,
				"side_cache": true, "secret_cache": true, "wall_edge": Vector2i(annex.z, annex.w)})
			occupied[alcove] = true
	if _generation_version >= 5:
		_place_exploration_hazards(depth, corridors, occupied)
	var hazard_rooms: Array[int] = []
	for room in rooms:
		var id: int = room.id
		if id == 0:
			continue
		if id == challenge_room:
			chests.append({"id": chests.size(), "room": id, "position": challenge_chamber.reward,
				"fixed_yaw": challenge_chamber.yaw, "locked": false, "guarded": false,
				"challenge_type": challenge_chamber.kind})
			continue
		if room.role == &"vault" or ordinary_chests.has(id):
			var needs_key := bool(ordinary_chests.get(id, false))
			if room.role == &"vault" and depth >= 9:
				needs_key = _rng.randf() < 0.23
			_place_expedition_chest(room, occupied, needs_key)
		_reserve_room_cover(room, occupied, depth)
		if id > 1 and room.role not in [&"vault", &"quiet"]:
			hazard_rooms.append(id)

	var hazard_count := 0
	while hazard_count < hazard_budget and not hazard_rooms.is_empty():
		var id: int = hazard_rooms.pop_at(_rng.randi_range(0, hazard_rooms.size() - 1))
		var room: Dictionary = rooms[id]
		var slots := _interior_slots(room, occupied)
		if slots.is_empty() and _generation_version >= 4:
			for tile: Vector2i in room.tiles:
				if not occupied.has(tile) and not _thresholds.has(tile):
					slots.append(tile)
		if slots.is_empty():
			continue
		var tile: Vector2i = slots[_rng.randi_range(0, slots.size() - 1)]
		var kinds := _hazard_types()
		var kind := kinds[(hazard_count + _rng.randi_range(0, 1)) % kinds.size()]
		hazard_points.append({"position": tile_position(tile), "room": id, "kind": kind})
		occupied[tile] = true
		hazard_count += 1

	var opening_floor := depth == 1 and floor_index == 0
	var distance := _room_distances(corridors) if _generation_version >= AMBUSH_GENERATION_VERSION else {}
	var dormant := _select_ambush_rooms(distance) if _generation_version >= AMBUSH_GENERATION_VERSION else {}
	var trial_coffer := _select_trial_coffer(depth, seed_value, distance)
	var swarm_room := _select_swarm_room(depth, seed_value, distance, dormant)
	for room in rooms:
		if room.id != 0 and room.id != challenge_room and room.role != &"quiet":
			var trial := trial_coffer if trial_coffer.get("room", -1) == room.id else {}
			_place_room_pack(room, occupied, depth, opening_floor, int(distance.get(room.id, 1)),
				dormant.get(room.id, ""), trial, room.id == swarm_room)
	_place_corridor_packs(corridors, occupied, depth, opening_floor)
	for chest: Dictionary in chests:
		if dormant.get(chest.room, "") == "coffer" and not chest.locked and not chest.guarded:
			if encounters.any(func(entry: Dictionary) -> bool: return entry.room == chest.room and entry.has("spawn_trigger")):
				chest["spawn_trigger"] = "coffer"
	for tile: Vector2i in bonus_cache_tiles:
		chests.append({"id": chests.size(), "position": tile_position(tile), "room": -1,
			"locked": false, "guarded": false, "side_cache": true, "secret_cache": true, "paired_cache": true})


func _select_trial_coffer(depth: int, seed_value: int, distance: Dictionary) -> Dictionary:
	if _generation_version < TRIAL_COFFER_GENERATION_VERSION or depth < ExpeditionRules.trial_coffer_min_depth:
		return {}
	var chance := float(posmod(hash([seed_value, depth, 7513]), 10000)) / 10000.0
	if not _feature_enabled(FEATURE_TRIAL_COFFER, chance < ExpeditionRules.trial_coffer_chance):
		return {}
	for chest: Dictionary in chests:
		if chest.guarded and not chest.locked and int(distance.get(chest.room, 0)) >= 2:
			return chest
	return {}


func _select_swarm_room(depth: int, seed_value: int, distance: Dictionary, dormant: Dictionary) -> int:
	if (_generation_version < EXPANDED_ROSTER_VERSION or depth < 3
			or EnemyCatalog.ARCHETYPES.size() <= CRYPT_SCURRER_ARCHETYPE
			or posmod(hash([seed_value, depth, 8357]), 100) >= 42):
		return -1
	var available: Array[int] = []
	for room: Dictionary in rooms:
		var id: int = room.id
		if (int(distance.get(id, 0)) < 2 or dormant.has(id) or id == int(challenge_chamber.get("room", -1))
				or room.role in [&"arrival", &"quiet", &"vault", &"arena"]):
			continue
		if not stair_approach_tiles.keys().any(func(tile: Vector2i) -> bool: return tile in room.tiles):
			available.append(id)
	return available[posmod(hash([seed_value, 253]), available.size())] if not available.is_empty() else -1


func _room_distances(corridors: Array[Dictionary]) -> Dictionary:
	var neighbors := {}
	for corridor: Dictionary in corridors:
		var connection: Vector2i = corridor.rooms
		if connection.x == connection.y:
			continue
		if not neighbors.has(connection.x):
			neighbors[connection.x] = []
		if not neighbors.has(connection.y):
			neighbors[connection.y] = []
		neighbors[connection.x].append(connection.y)
		neighbors[connection.y].append(connection.x)
	var distance := {0: 0}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var room: int = queue.pop_front()
		for neighbor: int in neighbors.get(room, []):
			if not distance.has(neighbor):
				distance[neighbor] = int(distance[room]) + 1
				queue.append(neighbor)
	return distance


func _select_ambush_rooms(distance: Dictionary) -> Dictionary:
	var triggers := {}
	var coffers: Array[int] = []
	for chest: Dictionary in chests:
		var id: int = chest.room
		if int(distance.get(id, 0)) >= 2 and not chest.locked and not chest.guarded and rooms[id].role != &"quiet":
			coffers.append(id)
	if not coffers.is_empty() and _feature_enabled(FEATURE_COFFER_AMBUSH, _rng.randf() < ExpeditionRules.coffer_ambush_chance):
		triggers[coffers[_rng.randi_range(0, coffers.size() - 1)]] = "coffer"
	var threshold: Array[int] = []
	for room: Dictionary in rooms:
		var id: int = room.id
		if int(distance.get(id, 0)) >= 2 and id != int(challenge_chamber.get("room", -1)) \
				and not triggers.has(id) and room.role not in [&"quiet", &"vault"]:
			threshold.append(id)
	if not threshold.is_empty() and _feature_enabled(FEATURE_THRESHOLD_AMBUSH, _rng.randf() < ExpeditionRules.threshold_ambush_chance):
		triggers[threshold[_rng.randi_range(0, threshold.size() - 1)]] = "threshold"
	return triggers


func _feature_enabled(flag: int, default_enabled: bool) -> bool:
	return default_enabled if _feature_mask < 0 else (_feature_mask & flag) != 0


func _place_exploration_hazards(depth: int, corridors: Array[Dictionary], occupied: Dictionary) -> void:
	var kinds := _hazard_types()
	for secret in secret_passages:
		if _generation_version >= AUTHORED_SECRET_VERSION:
			hazard_points.append_array(secret.get("challenge_hazards", []))
		var passage: Dictionary = side_passages[secret.branch]
		var hidden: Array[Vector2i] = passage.cells.slice(int(secret.entry), -1)
		# Trap recipes use their own rolls. Keep the ordinary encounter sequence tied to the base map seed.
		var hazard_sites := int(secret.get("legacy_hazard_sites", hidden.size()))
		if hazard_sites <= 0:
			continue
		# A blind cache can be free, but a proper annex always has a hazard on its approach.
		if passage.has("annex") or passage.get("replaced_annex", false) or _rng.randf() < 0.55:
			var keep_legacy := _generation_version < AUTHORED_SECRET_VERSION and not bool(passage.get("merchant", false))
			var kind: String = kinds[_rng.randi_range(0, kinds.size() - 1)]
			if keep_legacy:
				hazard_points.append({"position": tile_position(hidden[0]), "room": -1, "kind": kind, "secret": true})
			if depth >= 6 and hazard_sites >= 3:
				kind = kinds[_rng.randi_range(0, kinds.size() - 1)]
				if keep_legacy:
					hazard_points.append({"position": tile_position(hidden[2]), "room": -1, "kind": kind, "secret": true})
	if depth < 2:
		return
	var sections: Array[Array] = []
	for corridor in corridors:
		if corridor.rooms.x == 0 or corridor.rooms.y == 0:
			continue
		var slots: Array[Vector2i] = []
		for tile: Vector2i in corridor.tiles:
			if occupied.has(tile) or tile in slots or tile.distance_squared_to(_room_centers[0]) < 100.0:
				continue
			var open_ends := 0
			var near_room := false
			for side in DIRECTIONS:
				var neighbor := int(map_cells.get(tile + side, -2))
				open_ends += int(neighbor == -1)
				near_room = near_room or neighbor >= 0
			if not near_room and open_ends == 2:
				slots.append(tile)
		if slots.size() >= 2:
			sections.append(slots)
	for ignored in mini(sections.size(), 2 if depth >= 5 else 1):
		var section: Array = sections.pop_at(_rng.randi_range(0, sections.size() - 1))
		var index := _rng.randi_range(0, section.size() - 2)
		for tile: Vector2i in [section[index], section[index + 1]]:
			if occupied.has(tile):
				continue
			hazard_points.append({"position": tile_position(tile), "room": -1,
				"kind": kinds[_rng.randi_range(0, kinds.size() - 1)], "gallery": true})
			occupied[tile] = true


func _place_expedition_chest(room: Dictionary, occupied: Dictionary, needs_key: bool) -> void:
	var spots: Array[Vector2i] = []
	for tile: Vector2i in room.tiles:
		if tile not in room.interior and not _thresholds.has(tile) and (_generation_version < 5 or not occupied.has(tile)):
			spots.append(tile)
	if spots.is_empty():
		return
	var tile: Vector2i = spots[_rng.randi_range(0, spots.size() - 1)]
	if _generation_version >= 4 and room.role == &"vault":
		var greatest_separation := -1.0
		for candidate in spots:
			var separation := INF
			for door: Vector2i in room.doors:
				separation = minf(separation, candidate.distance_squared_to(door))
			if separation > greatest_separation:
				tile = candidate
				greatest_separation = separation
	occupied[tile] = true
	var id: int = room.id
	var guarded: bool = room.role == &"vault"
	chests.append({
		"id": chests.size(), "position": tile_position(tile), "room": id,
		"locked": needs_key, "guarded": guarded,
	})


func _reserve_room_cover(room: Dictionary, occupied: Dictionary, depth: int) -> void:
	var minimum_interior := 5 if _generation_version >= 4 else 9
	if room.role == &"arrival" or room.interior.size() < minimum_interior:
		return
	var count := 1 if room.role == &"arena" or (room.tiles.size() >= 32 and _rng.randf() < 0.6) else 0
	if room.interior.size() >= 23 and depth >= 3:
		count += 1
	var slots := _interior_slots(room, occupied)
	# Keep a complete ring of open tiles around every reserved route cell.
	var corners := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for index in range(slots.size() - 1, -1, -1):
		for corner: Vector2i in corners:
			if int(map_cells.get(slots[index] + corner, -2)) != int(room.id):
				slots.remove_at(index)
				break
	for index in range(count):
		if slots.is_empty():
			break
		var tile: Vector2i = slots.pop_at(_rng.randi_range(0, slots.size() - 1))
		room.cover.append(tile)
		_cover_tiles[tile] = _rng.randi_range(0, 2)
		occupied[tile] = true
		for offset: Vector2i in corners:
			slots.erase(tile + offset)
		for offset in DIRECTIONS:
			slots.erase(tile + offset)


func _interior_slots(room: Dictionary, occupied: Dictionary) -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	for tile: Vector2i in room.interior:
		if occupied.has(tile) or tile == room.center:
			continue
		var near_door := false
		for door: Vector2i in room.doors:
			if tile.distance_squared_to(door) <= 2:
				near_door = true
				break
		if not near_door:
			slots.append(tile)
	return slots


func _hazard_types() -> Array[String]:
	match depth_theme:
		&"drowned_vault":
			return ["spike_plate", "miasma_vent", "spike_plate"]
		&"ashen_catacomb":
			return ["ember_vent", "spike_plate", "ember_vent"]
		&"blighted_ossuary":
			return ["miasma_vent", "spike_plate", "miasma_vent"]
		_:
			return ["spike_plate", "ember_vent"]


func _place_room_pack(room: Dictionary, occupied: Dictionary, depth: int, opening_floor: bool,
		distance: int, trigger: String, trial: Dictionary, swarm: bool) -> void:
	var id: int = room.id
	var core: Array[Vector2i] = []
	var rim: Array[Vector2i] = []
	for tile: Vector2i in room.tiles:
		if occupied.has(tile) or _thresholds.has(tile):
			continue
		if tile in room.interior:
			core.append(tile)
		else:
			rim.append(tile)
	var starting_area: int = room.tiles.size()
	var count := roundi(sqrt(float(starting_area)) * 0.79) + mini(2, floori((depth - 1) / 3.0))
	count += _rng.randi_range(-1, 1)
	var stronghold: bool = room.role == &"arena" or room.role == &"vault"
	if stronghold:
		count += 1
	if id == 1 and room.role != &"arena":
		count = mini(4, count)
	var ambush := id >= 2 and (_rng.randf() < minf(0.76, 0.24 + depth * 0.048) or stronghold)
	var first_member := encounters.size()
	var pack_size := clampi(roundi(count * _population_scale), 2, 9)
	if _generation_version >= AMBUSH_GENERATION_VERSION:
		pack_size = _paced_pack_size(pack_size, depth, opening_floor, distance, stronghold)
	var wave_count := 3 if depth >= 9 else 2
	var wave_size := mini(5, 3 + floori(maxi(0, depth - 4) / 4.0))
	var trial_active := not trial.is_empty() and core.size() + rim.size() >= wave_count * wave_size
	if trial_active:
		pack_size = wave_count * wave_size
		trigger = "coffer"
		trial["trial_waves"] = wave_count
		trial["spawn_trigger"] = trigger
	var swarm_active := swarm and core.size() + rim.size() >= 4
	if swarm_active:
		var bonus := mini(2, floori((depth - 3) / 4.0))
		pack_size = mini(core.size() + rim.size(), _rng.randi_range(4 + bonus, 6 + bonus))
	var pack_archetype := _pick_archetype(depth) if _generation_version >= AMBUSH_GENERATION_VERSION else -1
	for member in pack_size:
		var candidates := core if not core.is_empty() and (rim.is_empty() or member < 2 or _rng.randf() < 0.74) else rim
		if candidates.is_empty():
			break
		var tile: Vector2i = candidates.pop_at(_rng.randi_range(0, candidates.size() - 1))
		occupied[tile] = true
		var spread := 0.33 if tile in room.interior else 0.14
		_spawn_entry(tile, depth, id, id, ambush, minf(10.8, 6.2 + depth * 0.45), spread)
		if _generation_version >= AMBUSH_GENERATION_VERSION:
			if swarm_active:
				encounters[-1]["archetype"] = CRYPT_SCURRER_ARCHETYPE
				encounters[-1]["swarm"] = true
			elif opening_floor and distance == 1:
				encounters[-1]["archetype"] = GRAVE_THRALL_ARCHETYPE if member == 0 else OSSUARY_ARCHER_ARCHETYPE
			elif member == 0 or member < pack_size - 1 or _rng.randf() < 0.44:
				encounters[-1]["archetype"] = pack_archetype
			if not trigger.is_empty():
				encounters[-1]["spawn_trigger"] = trigger
				encounters[-1]["ambush"] = true
			if trial_active:
				var wave := floori(float(member) / wave_size)
				encounters[-1]["wave"] = wave
				encounters[-1]["pack"] = 1000 + id * 3 + wave
	if _generation_version == 3 and depth == 1 and id == 1 and encounters.size() - first_member >= 2:
		_assign_opening_pack(room, first_member)


func _paced_pack_size(size: int, depth: int, opening_floor: bool, distance: int, stronghold: bool) -> int:
	if opening_floor:
		if distance == 1:
			var opening: Vector2i = ExpeditionRules.opening_chamber_size
			return _rng.randi_range(maxi(1, opening.x), maxi(maxi(1, opening.x), opening.y))
		var cap: int = ExpeditionRules.opening_floor_pack_cap + int(stronghold and distance >= 3)
		return mini(size, cap)
	if depth <= 3:
		var cap := mini(5, 3 + int(distance >= 3) + int(stronghold and depth >= 2))
		return mini(size, cap)
	return size


func _assign_opening_pack(room: Dictionary, first_member: int) -> void:
	var entrance: Vector2i = room.doors.front()
	for door: Vector2i in room.doors:
		if door.distance_squared_to(_room_centers[0]) < entrance.distance_squared_to(_room_centers[0]):
			entrance = door
	var entrance_position := tile_position(entrance)
	var front := first_member
	var back := first_member
	var nearest_distance := INF
	var furthest_distance := -INF
	for member in range(first_member, encounters.size()):
		var distance := entrance_position.distance_squared_to(encounters[member].position)
		if distance < nearest_distance:
			front = member
			nearest_distance = distance
		if distance >= furthest_distance:
			back = member
			furthest_distance = distance
	# Reuse the sampled slots and leave the RNG stream unchanged for later packs.
	encounters[front]["archetype"] = GRAVE_THRALL_ARCHETYPE
	encounters[back]["archetype"] = OSSUARY_ARCHER_ARCHETYPE


func _place_corridor_packs(corridors: Array[Dictionary], occupied: Dictionary, depth: int, opening_floor: bool) -> void:
	var remaining := ceili(float(rooms.size()) * _population_scale / 3.0)
	var sparse := _generation_version >= AMBUSH_GENERATION_VERSION and opening_floor
	if sparse:
		remaining = mini(1, remaining)
	var options: Array[Dictionary] = []
	for corridor in corridors:
		if corridor.rooms.x == 0 or corridor.rooms.y == 0:
			continue
		var spots: Array[Vector2i] = []
		for tile: Vector2i in corridor.tiles:
			if occupied.has(tile) or tile in spots or tile.distance_squared_to(_room_centers[0]) < 81:
				continue
			var near_room := false
			var neighbors := 0
			for step in DIRECTIONS:
				var neighbor := int(map_cells.get(tile + step, -2))
				near_room = near_room or neighbor >= 0
				neighbors += 1 if neighbor == -1 else 0
			if not near_room and neighbors >= 2:
				spots.append(tile)
		if not spots.is_empty():
			options.append({"id": corridor.id, "spots": spots})
	var patrols := 0
	var patrolling: Dictionary = {}
	while remaining > 0 and not options.is_empty():
		var entry: Dictionary = options.pop_at(_rng.randi_range(0, options.size() - 1))
		if _rng.randf() >= minf(0.66, 0.40 + depth * 0.022) and (patrols > 0 or not options.is_empty()):
			continue
		var spots: Array[Vector2i] = entry.spots
		var ambush := _rng.randf() < 0.49
		var pack := MAX_ROOMS + int(entry.id)
		var tile: Vector2i = spots.pop_at(_rng.randi_range(0, spots.size() - 1))
		if occupied.has(tile):
			continue
		var index := encounters.size()
		_spawn_entry(tile, depth, -1, pack, ambush, minf(7.8, 5.2 + depth * 0.29))
		occupied[tile] = true
		if not ambush:
			patrolling[index] = tile
		if not sparse and _rng.randf() < minf(0.54, 0.26 + depth * 0.037):
			for partner in spots:
				if not occupied.has(partner) and partner.distance_squared_to(tile) >= 4:
					_spawn_entry(partner, depth, -1, pack, ambush, 6.0)
					occupied[partner] = true
					break
		patrols += 1
		remaining -= 1
	for index: int in patrolling:
		var patrol := _corridor_patrol(patrolling[index], occupied)
		if patrol.size() >= 2:
			encounters[index]["patrol_points"] = patrol


func _corridor_patrol(start: Vector2i, occupied: Dictionary) -> PackedVector3Array:
	var tiles: Array[Vector2i] = [start]
	var points := PackedVector3Array([tile_position(start)])
	for leg in range(2):
		var from: Vector2i = tiles.back()
		var candidates: Array[Vector2i] = []
		for step in DIRECTIONS:
			var tile: Vector2i = from + step
			if int(map_cells.get(tile, -2)) != -1 or occupied.has(tile) or tile in tiles:
				continue
			var near_room := false
			for adjacent in DIRECTIONS:
				if int(map_cells.get(tile + adjacent, -2)) >= 0:
					near_room = true
					break
			if not near_room:
				candidates.append(tile)
		if candidates.is_empty():
			break
		var next: Vector2i = candidates[_rng.randi_range(0, candidates.size() - 1)]
		tiles.append(next)
		points.append(tile_position(next))
	return points


func _spawn_entry(tile: Vector2i, depth: int, room: int, pack: int, ambush: bool, reach: float, spread := 0.27) -> void:
	var offset := Vector3(_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))
	encounters.append({
		"position": tile_position(tile) + offset, "archetype": _pick_archetype(depth),
		"pack": pack, "room": room, "ambush": ambush, "alert_radius": reach,
		"location": "room" if room >= 0 else "corridor",
	})


func _pick_archetype(depth: int) -> int:
	return EnemyCatalog.pick_archetype(depth, _rng, 20 if _generation_version < EXPANDED_ROSTER_VERSION else -1)


# Legacy checkpoints address enemies and chests by index. Preserve layout and RNG order.
func _layout_legacy(level: int) -> void:
	var chamber_count := mini(MAX_ROOMS, 5 + 2 * (level - 1))
	var coarse_rooms: Array[Vector2i] = [Vector2i.ZERO]
	var occupied := {Vector2i.ZERO: 0}
	for room in range(1, chamber_count):
		var frontier: Array[Vector2i] = []
		# Keep a single gate in the arrival chamber, and give the first junction two branches.
		var first_source := 0 if room == 1 else 1
		var source_limit := 2 if room in [2, 3] else room
		for source in range(first_source, source_limit):
			for direction_index in range(DIRECTIONS.size()):
				var candidate := coarse_rooms[source] + DIRECTIONS[direction_index]
				if not occupied.has(candidate):
					frontier.append(Vector2i(source, direction_index))
		var edge := frontier[_rng.randi_range(0, frontier.size() - 1)]
		var coarse_tile := coarse_rooms[edge.x] + DIRECTIONS[edge.y]
		coarse_rooms.append(coarse_tile)
		occupied[coarse_tile] = room
		_links.append(Vector2i(edge.x, room))

	var shortcuts: Array[Vector2i] = []
	for room in range(1, chamber_count):
		for offset in [Vector2i.RIGHT, Vector2i.DOWN]:
			var adjacent: Vector2i = coarse_rooms[room] + offset
			var neighbor := int(occupied.get(adjacent, 0))
			if neighbor > 0 and not _links.has(Vector2i(room, neighbor)) and not _links.has(Vector2i(neighbor, room)):
				shortcuts.append(Vector2i(room, neighbor))
	for ignored in range(mini(shortcuts.size(), floori(chamber_count / 6.0))):
		var index := _rng.randi_range(0, shortcuts.size() - 1)
		_links.append(shortcuts.pop_at(index))

	for room in range(chamber_count):
		var center := coarse_rooms[room] * ROOM_STRIDE
		if room > 0:
			center += Vector2i(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1))
		var size := Vector2i(5, 5)
		if room > 0:
			size = Vector2i(_rng.randi_range(3, 5), _rng.randi_range(3, 5))
			if room % 4 == 2:
				size.x = 6
		_room_centers.append(center)
		var bounds := Rect2i(center - Vector2i(Vector2(size) * 0.5), size)
		room_bounds.append(bounds)
		for z in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				map_cells[Vector2i(x, z)] = room

	for edge in _links:
		var first := _room_centers[edge.x]
		var last := _room_centers[edge.y]
		if coarse_rooms[edge.x].x != coarse_rooms[edge.y].x:
			var bend := int((first.x + last.x) * 0.5)
			_carve_line(first, Vector2i(bend, first.y))
			_carve_line(Vector2i(bend, first.y), Vector2i(bend, last.y))
			_carve_line(Vector2i(bend, last.y), last)
		else:
			var bend := int((first.y + last.y) * 0.5)
			_carve_line(first, Vector2i(first.x, bend))
			_carve_line(Vector2i(first.x, bend), Vector2i(last.x, bend))
			_carve_line(Vector2i(last.x, bend), last)
	spawn_position = tile_position(_room_centers[0])
	_arrival_gate = coarse_rooms[1] - coarse_rooms[0]
	spawn_yaw = atan2(-float(_arrival_gate.x), -float(_arrival_gate.y))


func _carve_line(first: Vector2i, last: Vector2i) -> void:
	var current := first
	var step := (last - first).sign()
	while true:
		if not map_cells.has(current):
			map_cells[current] = -1
		if current == last:
			return
		current += step


func _build_navigation() -> void:
	var limits := Rect2i(Vector2i.ZERO, Vector2i.ONE)
	for tile: Vector2i in map_cells:
		limits = limits.expand(tile).expand(tile + Vector2i.ONE)
	_navigation.region = limits
	_navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_navigation.update()
	for z in range(limits.position.y, limits.end.y):
		for x in range(limits.position.x, limits.end.x):
			var tile := Vector2i(x, z)
			if not map_cells.has(tile) or _cover_tiles.has(tile) or _is_basin_tile(tile):
				_navigation.set_point_solid(tile)


func _build_materials() -> void:
	_materials[IRON] = FORGED_STEEL
	_materials[BRONZE] = WEATHERED_BRONZE
	_materials[CLOTH] = _textured_material(Color("974a47"), WORN_LINEN)
	_materials[CLOTH_TRIM] = _textured_material(Color("c8aa73"), WORN_LINEN)
	if challenge_chamber.get("kind") == ChallengeChambers.PLATFORM:
		var stone := StandardMaterial3D.new()
		DungeonTilesets.apply_masonry(stone, tileset_id, &"wall")
		_materials[UPPER_STONE] = stone


func _textured_material(tint: Color, texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = texture
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material


func _lighting_palette() -> Dictionary:
	return DungeonTilesets.lighting(tileset_id)


func _build_environment() -> void:
	var authored := get_node_or_null("UndercroftAir") as WorldEnvironment
	if authored != null and authored.environment != null:
		authored.environment = authored.environment.duplicate()
		_apply_dungeon_atmosphere(authored.environment)
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 0.8
	environment.ssao_intensity = 1.45
	environment.fog_enabled = true
	environment.fog_sky_affect = 0.0
	_apply_dungeon_atmosphere(environment)
	var world := WorldEnvironment.new()
	world.name = "UndercroftAir"
	world.environment = environment
	add_child(world)


func _apply_dungeon_atmosphere(environment: Environment) -> void:
	var fog_color: Color = _palette.fog
	environment.background_color = fog_color.darkened(0.35)
	environment.ambient_light_color = _palette.ambient
	environment.ambient_light_energy = float(_palette.ambient_energy)
	environment.fog_light_color = fog_color
	environment.fog_density = 0.024
	environment.glow_enabled = true
	environment.glow_intensity = 0.25
	environment.glow_bloom = 0.055
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.87


func _load_geometry_modules() -> void:
	var cell := get_node_or_null("CellTemplate") as Node3D
	if cell == null:
		cell = CryptCell.instantiate()
	_cache_module(cell.get_node("Floor"), &"Floor", Transform3D.IDENTITY)
	_cache_module(cell.get_node("Ceiling"), &"Ceiling", Transform3D.IDENTITY)
	var wall := cell.get_node("Wall") as Node3D
	var masonry := wall.get_node("MasonryKit") as Node3D
	var pilaster := masonry.get_node("Pilaster") as Node3D
	_cache_module(pilaster, &"Pilaster", wall.transform * masonry.transform)
	pilaster.free()
	_cache_module(wall, &"Wall", Transform3D.IDENTITY)
	cell.free()
	for index in COVER_SCENES.size():
		var cover: Node3D = COVER_SCENES[index].instantiate()
		_cache_module(cover, StringName("Cover%d" % index), Transform3D.IDENTITY)
		cover.free()
	for key: StringName in ROOM_FIXTURES:
		var resource: PackedScene = ROOM_FIXTURES[key]
		var fixture: Node3D = resource.instantiate()
		_cache_module(fixture, key, Transform3D.IDENTITY)
		fixture.free()


func _cache_module(node: Node3D, module: StringName, parent_pose: Transform3D) -> void:
	var pose := parent_pose * node.transform
	if node is OmniLight3D or node is GPUParticles3D or node is CPUParticles3D or node.is_in_group(&"dungeon_module_effect"):
		var piece := PackedScene.new()
		if piece.pack(node) == OK:
			if not _module_effects.has(module):
				_module_effects[module] = []
			_module_effects[module].append({"pose": pose, "scene": piece})
		return
	if node is MeshInstance3D and node.mesh != null and node.visible:
		for surface in node.mesh.get_surface_count():
			var source: Material = node.material_override
			if source == null:
				source = node.get_surface_override_material(surface)
			if source == null:
				source = node.mesh.surface_get_material(surface)
			var material := _module_material(source)
			if not _module_meshes.has(module):
				_module_meshes[module] = []
			_module_meshes[module].append({"pose": pose, "material": material, "source": node.mesh.surface_get_arrays(surface)})
	elif node is CollisionShape3D and node.shape != null and not node.disabled:
		if not _module_collisions.has(module):
			_module_collisions[module] = []
		_module_collisions[module].append({"pose": pose, "shape": node.shape})
	for child in node.get_children():
		if child is Node3D:
			_cache_module(child, module, pose)


func _module_material(source: Material) -> StringName:
	if not _module_materials.has(source):
		var material: Material = source.duplicate() if source != null else StandardMaterial3D.new()
		if material is StandardMaterial3D:
			var surface := DungeonTilesets.masonry_surface(material.albedo_texture) if source != null else &"wall"
			if surface != &"":
				DungeonTilesets.apply_masonry(material, tileset_id, surface)
		elif material is ShaderMaterial and material.shader == BloodFloorShader:
			var stone_tint: Color = material.get_shader_parameter("stone_tint")
			material.set_shader_parameter("stone_tint", stone_tint * _palette.floor)
			material.set_shader_parameter("stone_albedo", DungeonTilesets.albedo(tileset_id, &"floor"))
			material.set_shader_parameter("world_texture_scale", DungeonTilesets.repeats_per_metre(tileset_id, &"floor"))
		var key := StringName("Module%d" % _module_materials.size())
		_materials[key] = material
		_module_materials[source] = key
	return _module_materials[source]


func _place_module(tile: Vector2i, module: StringName, pose: Transform3D, tint := Color.WHITE,
		light_tint := Color.WHITE, light_strength := 1.0) -> void:
	for part: Dictionary in _module_meshes.get(module, []):
		var material: Material = _materials[part.material]
		if module == &"Floor" and material is ShaderMaterial and material.shader == BloodFloorShader:
			_floor_geometry.append_mesh(part.source, pose * part.pose, tint)
			_floor_material = material
		else:
			_surface(tile, part.material).append_mesh(part.source, pose * part.pose, tint)
	for fixture: Dictionary in _module_collisions.get(module, []):
		var collision := CollisionShape3D.new()
		collision.transform = pose * fixture.pose
		collision.shape = fixture.shape
		_collision_body(tile).add_child(collision)
		if module == &"StonePortal":
			_navigation_blockers.append(collision)
	for effect: Dictionary in _module_effects.get(module, []):
		var instance: Node3D = effect.scene.instantiate()
		instance.transform = pose * effect.pose
		if instance is OmniLight3D:
			instance.light_color *= light_tint
			instance.light_energy *= light_strength
			_torches.append(instance)
			_torch_energies.append(instance.light_energy)
		add_child(instance)


func _plan_stairs(floor_index: int, floor_count: int) -> void:
	var ascending: Array[Dictionary] = rooms.duplicate()
	if floor_index > 0:
		_find_stair_site(-1, floor_index, ascending, -_arrival_gate)
	if floor_index + 1 < floor_count:
		var descending: Array[Dictionary] = rooms.slice(1)
		var arrival := _room_centers[0]
		descending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var center_a: Vector2i = a.center
			var center_b: Vector2i = b.center
			return center_a.distance_squared_to(arrival) > center_b.distance_squared_to(arrival))
		_find_stair_site(1, floor_index + 2, descending, Vector2i.ZERO)


func _plan_continuous_stairs(floor_index: int, floor_count: int, floor_rise: int) -> void:
	if floor_index > 0:
		_place_continuous_stair(-_arrival_gate, -1, floor_rise)
	if floor_index + 1 < floor_count:
		_place_continuous_stair(_arrival_gate, 1, floor_rise)


func _place_continuous_stair(outward: Vector2i, progression: int, floor_rise: int) -> void:
	var extreme := -2147483648
	var selected := Vector2i.ZERO
	var score := -INF
	for tile: Vector2i in map_cells:
		var projection := tile.x * outward.x + tile.y * outward.y
		if projection < extreme:
			continue
		var has_approach := map_cells.has(tile - outward)
		var room := int(map_cells[tile])
		var rating := 10.0 if has_approach else 0.0
		if room >= 0 and rooms[room].role != &"vault":
			rating += 2.0
		if not _thresholds.has(tile):
			rating += 1.0
		rating += float(posmod(hash([tile, _rng.seed, progression]), 400)) * 0.001
		if projection > extreme or rating > score:
			selected = tile
			extreme = projection
			score = rating
	if not map_cells.has(selected - outward) or selected == _room_centers[0]:
		selected += outward
		map_cells[selected] = -1
	var physical_direction := -signi(floor_rise) * progression
	if physical_direction == 0:
		physical_direction = progression
	_place_stair_flight(selected, outward, progression, 0, physical_direction)


func _find_stair_site(direction: int, destination: int, candidates: Array[Dictionary],
		preferred: Vector2i) -> void:
	var approaches: Array[Vector2i] = DIRECTIONS.duplicate()
	var occupied: Dictionary[Vector2i, bool] = {}
	for entries in [chests, hazard_points, encounters]:
		for entry: Dictionary in entries:
			occupied[tile_at(entry.position)] = true
	if preferred in approaches:
		approaches.erase(preferred)
		approaches.push_front(preferred)
	for room: Dictionary in candidates:
		if room.role == &"vault":
			continue
		for outward in approaches:
			for tile: Vector2i in room.tiles:
				var approach := tile - outward
				if _thresholds.has(tile) or stair_approach_tiles.has(tile) or _cover_tiles.has(tile) or occupied.has(tile):
					continue
				if int(map_cells.get(approach, -2)) != int(room.id) or _cover_tiles.has(approach) or occupied.has(approach):
					continue
				var first := tile + outward
				var second := first + outward
				if map_cells.has(first) or map_cells.has(second) or _stair_overruns.has(first) or _stair_overruns.has(second):
					continue
				_place_stair_flight(tile, outward, direction, destination)
				return
	push_error("Dungeon floor has no clear stair approach for direction %d" % direction)


func _place_stair_flight(tile: Vector2i, outward: Vector2i, direction: int, destination: int,
		physical_direction := 0) -> void:
	var flight := StairFlightScene.instantiate() as Node3D
	var continuous := physical_direction != 0
	var slope := physical_direction if continuous else direction
	flight.name = "DescendingStair" if slope > 0 else "AscendingStair"
	var normal := Vector3(outward.x, 0.0, outward.y)
	flight.position = tile_position(tile) + normal * (CELL_SIZE * 0.5 - 0.015)
	flight.rotation.y = atan2(-normal.x, -normal.z)
	flight.configure(slope, destination, continuous)
	_apply_stair_tileset(flight)
	var reflective_fill: Color = _lighting_palette().get("threshold_fill", Color.TRANSPARENT)
	if reflective_fill.a > 0.0:
		_light(flight.transform * Vector3(0.0, 0.54 - float(slope) * 0.67, -2.46),
			reflective_fill, 4.7, 0.69)
	add_child(flight)
	stairs[direction] = flight
	stair_tiles[direction] = tile
	stair_approach_tiles[tile] = true
	stair_approach_tiles[tile - outward] = true
	_thresholds[tile] = true
	_stair_edges[tile] = outward
	_stair_overruns[tile + outward] = true
	_stair_overruns[tile + outward * 2] = true
	var room := int(map_cells[tile])
	if room >= 0:
		var doors: Array[Vector2i] = rooms[room].doors
		if tile not in doors:
			doors.append(tile)
	if slope > 0:
		var start := Vector2(flight.position.x, flight.position.z)
		var end := start + Vector2(outward) * StairFlight.LENGTH
		var half_width := Vector2(absi(outward.y), absi(outward.x)) * CELL_SIZE * 0.5
		_floor_cutouts.append(Rect2(start.min(end) - half_width, (start - end).abs() + half_width * 2.0))


func _apply_stair_tileset(flight: Node3D) -> void:
	for instance: MeshInstance3D in flight.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		if instance.material_override != null:
			instance.material_override = _stair_tileset_material(instance.material_override)
			continue
		for surface in instance.mesh.get_surface_count():
			var source := instance.get_active_material(surface)
			var material := _stair_tileset_material(source)
			if material != source:
				instance.set_surface_override_material(surface, material)


func _stair_tileset_material(source: Material) -> Material:
	var surface := source as StandardMaterial3D
	if surface == null:
		return source
	var stone_surface := DungeonTilesets.masonry_surface(surface.albedo_texture)
	if stone_surface == &"":
		return source
	var material := surface.duplicate() as StandardMaterial3D
	DungeonTilesets.apply_masonry(material, tileset_id, stone_surface)
	return material


func _build_floor_collision() -> void:
	_floor_body = StaticBody3D.new()
	_floor_body.name = "DungeonFloor"
	_floor_body.collision_layer = 1
	_floor_body.collision_mask = 0
	add_child(_floor_body)
	var outer_bounds := _navigation.region
	var floor_regions: Array[Rect2] = [Rect2(Vector2(outer_bounds.position) * CELL_SIZE - Vector2.ONE * CELL_SIZE * 0.5,
		Vector2(outer_bounds.size) * CELL_SIZE)]
	for cut in _floor_cutouts:
		var remaining: Array[Rect2] = []
		for region in floor_regions:
			var overlap := region.intersection(cut)
			if not overlap.has_area():
				remaining.append(region)
				continue
			remaining.append_array([
				Rect2(region.position, Vector2(overlap.position.x - region.position.x, region.size.y)),
				Rect2(Vector2(overlap.end.x, region.position.y), Vector2(region.end.x - overlap.end.x, region.size.y)),
				Rect2(Vector2(overlap.position.x, region.position.y), Vector2(overlap.size.x, overlap.position.y - region.position.y)),
				Rect2(Vector2(overlap.position.x, overlap.end.y), Vector2(overlap.size.x, region.end.y - overlap.end.y)),
			])
		floor_regions = remaining
	for region in floor_regions:
		if not region.has_area():
			continue
		var center := region.get_center()
		_collision_box(_floor_body, Vector3(center.x, -0.175, center.y),
			Vector3(region.size.x, 0.35, region.size.y))


func _build_shell() -> void:
	_select_passage_frames()
	_build_floor_collision()
	for tile: Vector2i in map_cells:
		var base := tile_position(tile)
		var shade := 0.84 + absf(sin(float(tile.x * 17 - tile.y * 23))) * 0.16
		var tint := Color(shade, shade, shade, 1.0)
		var pose := Transform3D(Basis.IDENTITY, base)
		var room := int(map_cells[tile])
		var tall := _is_tall_room(room)
		if not _is_basin_tile(tile):
			_place_module(tile, &"Floor", pose, tint)
		if tall:
			pose.origin.y += PLATFORM_CEILING_HEIGHT - CEILING_HEIGHT
		_place_module(tile, &"Ceiling", pose, tint)
		var sconce_built := false
		for direction in DIRECTIONS:
			if _stair_edges.get(tile, Vector2i.ZERO) == direction:
				continue
			var neighbor := tile + direction
			if tall and int(map_cells.get(neighbor, -2)) != room:
				_upper_wall_panel(tile, direction)
			if map_cells.has(neighbor):
				if room >= 0 and int(map_cells[neighbor]) == -1:
					_thresholds[tile] = true
					var mouth := tile * 2 + direction
					if _passage_frames.has(mouth):
						_doorway(tile, direction)
				continue
			_wall_panel(tile, direction, tint)
			if room == 0 or (_generation_version == 1 and room >= 0):
				var wall_center := _room_centers[room] + _wall_center_offset(room, direction)
				if tile == wall_center:
					_wall_relic(tile, direction, room)
			if room < 0 and not sconce_built and posmod(tile.x + tile.y, 3) == 0:
				_sconce(tile, direction)
				sconce_built = true


func _upper_wall_panel(tile: Vector2i, direction: Vector2i) -> void:
	var outward := Vector3(direction.x, 0.0, direction.y)
	var across := Vector3(-direction.y, 0.0, direction.x)
	var height := PLATFORM_CEILING_HEIGHT - CEILING_HEIGHT
	var position_at_wall := tile_position(tile) + outward * (CELL_SIZE * 0.5 - 0.05)
	position_at_wall.y = CEILING_HEIGHT + height * 0.5
	var panel_basis := Basis(across, Vector3.UP, -outward)
	_surface(tile, UPPER_STONE).box(position_at_wall, Vector3(CELL_SIZE + 0.10, height, 0.23), panel_basis)
	var size := Vector3(CELL_SIZE + 0.10, height, 0.23) if direction.x == 0 else Vector3(0.23, height, CELL_SIZE + 0.10)
	_collision_box(_collision_body(tile), position_at_wall, size)


func _select_passage_frames() -> void:
	var entrance := _room_centers[0] + _wall_center_offset(0, _arrival_gate)
	_reserve_passage_frame(entrance, _arrival_gate)
	if _generation_version >= 4:
		for port in _routed_ports:
			var tile := Vector2i(port.x, port.y)
			var room := int(map_cells[tile])
			var role: StringName = rooms[room].role
			if role in [&"guard", &"arena", &"vault"] or posmod(room, 4) == 2:
				_reserve_passage_frame(tile, Vector2i(port.z, port.w))
		return
	for tile: Vector2i in map_cells:
		if int(map_cells[tile]) < 0:
			continue
		for direction in DIRECTIONS:
			_reserve_passage_frame(tile, direction)


func _reserve_passage_frame(tile: Vector2i, direction: Vector2i) -> void:
	var throat := tile + direction
	var across := Vector2i(-direction.y, direction.x)
	if map_cells.get(throat) != -1 or map_cells.has(throat + across) or map_cells.has(throat - across):
		return
	var center := Vector2(tile) + Vector2(direction) * 0.5
	# A frame is slightly wider than a tile so its jambs seat in the flanks.
	var half_width := Vector2(across.abs()) * 0.53 + Vector2(direction.abs()) * 0.11
	var footprint := Rect2(center - half_width, half_width * 2.0)
	for existing: Rect2 in _passage_frames.values():
		if existing.intersects(footprint):
			return
	_passage_frames[tile * 2 + direction] = footprint


func _wall_panel(tile: Vector2i, direction: Vector2i, tint: Color) -> void:
	var outward := Vector3(direction.x, 0.0, direction.y)
	var across := Vector3(-direction.y, 0.0, direction.x)
	var wall_basis := Basis(across, Vector3.UP, -outward)
	var center := tile_position(tile)
	var pose := Transform3D(wall_basis, center)
	_place_module(tile, &"Wall", pose, tint)
	if posmod(tile.x * 3 + tile.y + direction.x * 2, 5) == 0:
		_place_module(tile, &"Pilaster", pose, tint)


func _wall_center_offset(room: int, direction: Vector2i) -> Vector2i:
	var bounds := room_bounds[room]
	var center := _room_centers[room]
	var x := bounds.position.x if direction.x < 0 else bounds.end.x - 1
	var z := bounds.position.y if direction.y < 0 else bounds.end.y - 1
	return Vector2i(x - center.x, 0) if direction.x != 0 else Vector2i(0, z - center.y)


func _wall_relic(tile: Vector2i, direction: Vector2i, room: int) -> void:
	var outward := Vector3(direction.x, 0.0, direction.y)
	var across := Vector3(-direction.y, 0.0, direction.x)
	var inward := -outward
	var relic_basis := Basis(across, Vector3.UP, inward)
	var anchor := tile_position(tile) + outward * (CELL_SIZE * 0.5 - 0.12)
	var bronze := _surface(tile, BRONZE)
	if room == 0 or room % 3 == 1:
		var top := anchor + inward * 0.20 + Vector3.UP * 3.48
		var cloth := _surface(tile, CLOTH)
		var gold := _surface(tile, CLOTH_TRIM)
		bronze.box(top, Vector3(1.38, 0.08, 0.10), relic_basis)
		for side in [-1.0, 1.0]:
			var edge: Vector3 = across * side
			bronze.box(top + edge * 0.57 - inward * 0.13, Vector3(0.065, 0.08, 0.29), relic_basis)
			bronze.box(top + edge * 0.73, Vector3(0.14, 0.14, 0.14), relic_basis)
			var shoulder: Vector3 = top + edge * 0.50 - Vector3.UP * 0.06
			var hem: Vector3 = shoulder - Vector3.UP * 1.68 + inward * 0.04
			cloth.quad(top, shoulder, hem, top - Vector3.UP * 1.94, inward)
			_beam(gold, shoulder + inward * 0.012, hem + inward * 0.012, 0.025, 0.015, inward)
		var badge := top - Vector3.UP * 0.80 + inward * 0.03
		var crest_top := badge + Vector3.UP * 0.27
		var crest_bottom := badge - Vector3.UP * 0.27
		_beam(gold, crest_top, crest_bottom, 0.06, 0.016, inward)
		for side in [-1.0, 1.0]:
			var tip: Vector3 = badge + across * (0.24 * side)
			_beam(gold, crest_top, tip, 0.025, 0.016, inward)
			_beam(gold, tip, crest_bottom, 0.025, 0.016, inward)
	elif room % 3 == 2:
		var iron := _surface(tile, IRON)
		var rack := anchor + Vector3.UP * 3.39
		bronze.box(rack, Vector3(1.8, 0.12, 0.19), relic_basis)
		_chain(iron, rack - across * 0.51 + inward * 0.12, relic_basis, 6)
		_chain(iron, rack + across * 0.51 + inward * 0.12, relic_basis, 9)
	else:
		var grille := anchor + Vector3.UP * 2.25
		_surface(tile, IRON).box(grille, Vector3(1.67, 2.25, 0.09), relic_basis)
		bronze.box(grille + Vector3.UP * 1.08, Vector3(1.78, 0.12, 0.15), relic_basis)
		bronze.box(grille - Vector3.UP * 1.08, Vector3(1.78, 0.12, 0.15), relic_basis)
		for bar in range(-3, 4):
			bronze.box(grille + across * (0.23 * float(bar)) + inward * 0.08, Vector3(0.07, 2.13, 0.08), relic_basis)


func _chain(geometry: Geometry, anchor: Vector3, base: Basis, link_count: int) -> void:
	for link in range(link_count):
		var link_basis := base.rotated(Vector3.UP, PI * 0.5 * float(link % 2))
		var center := anchor - Vector3.UP * (0.19 * float(link) + 0.14)
		for side in [-1.0, 1.0]:
			geometry.box(center + link_basis.x * (0.064 * side), Vector3(0.026, 0.23, 0.029), link_basis)
			geometry.box(center + Vector3.UP * (0.110 * side), Vector3(0.154, 0.026, 0.029), link_basis)


func _doorway(tile: Vector2i, direction: Vector2i) -> void:
	var outward := Vector3(direction.x, 0.0, direction.y)
	var across := Vector3(-direction.y, 0.0, direction.x)
	var doorway_basis := Basis(across, Vector3.UP, -outward)
	var door := tile_position(tile) + outward * (CELL_SIZE * 0.5) - outward * 0.1
	var room := int(map_cells[tile])
	var maintenance := depth_theme == &"ashen_catacomb" and room > 0 and posmod(room, 3) == 1
	_place_module(tile, &"Doorway" if maintenance else &"StonePortal", Transform3D(doorway_basis, door))
	var reflective_fill: Color = _palette.get("threshold_fill", Color.TRANSPARENT)
	if reflective_fill.a > 0.0:
		_light(door - outward * 0.33 + Vector3.UP * 0.48, reflective_fill, 4.5, 0.42)
	if room == 0:
		for side in [-1.0, 1.0]:
			var guard: Vector3 = door + across * (2.32 * side) - outward * 0.38
			_sentinel(tile, guard, doorway_basis, side)
			_light(guard - outward * 0.90 + Vector3.UP * 3.02, Color("f5bd99"), 6.2, 1.85)


func _sentinel(tile: Vector2i, point: Vector3, doorway_basis: Basis, side: float) -> void:
	var base_size := doorway_basis.x.abs() * 1.04 + doorway_basis.z.abs() * 0.71 + Vector3.UP * 2.53
	_navigation_blockers.append(_collision_box(_collision_body(tile), point + Vector3.UP * 1.265, base_size))
	var pose := doorway_basis * Basis.from_scale(Vector3(side, 1.0, 1.0))
	_place_module(tile, &"Sentinel", Transform3D(pose, point))


func _beam(
	geometry: Geometry, first: Vector3, last: Vector3, width: float,
	depth: float, surface_normal: Vector3
) -> void:
	var vertical := (last - first).normalized()
	var across := vertical.cross(surface_normal).normalized()
	geometry.box((first + last) * 0.5, Vector3(width, first.distance_to(last) + 0.12, depth), Basis(across, vertical, surface_normal))


func _populate_legacy(level: int) -> void:
	var eligible_chest_rooms: Array[int] = []
	for room in range(1, room_bounds.size()):
		eligible_chest_rooms.append(room)
	var chest_count := mini(room_bounds.size() - 1, 2 + mini(5, floori(level * 0.5)))
	var chest_rooms := {}
	for index in range(chest_count):
		var selection := _rng.randi_range(0, eligible_chest_rooms.size() - 1)
		var room: int = eligible_chest_rooms.pop_at(selection)
		chest_rooms[room] = index

	for room in range(1, room_bounds.size()):
		var bounds := room_bounds[room]
		var positions: Array[Vector2i] = []
		var corners: Array[Vector2i] = []
		for z in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var tile := Vector2i(x, z)
				if _thresholds.has(tile):
					continue
				positions.append(tile)
				if (x == bounds.position.x or x == bounds.end.x - 1) and (z == bounds.position.y or z == bounds.end.y - 1):
					corners.append(tile)
		if chest_rooms.has(room):
			var tiles := corners if not corners.is_empty() else positions
			var tile := tiles[_rng.randi_range(0, tiles.size() - 1)]
			positions.erase(tile)
			var chest_id := int(chest_rooms[room])
			chests.append({
				"id": chest_id, "position": tile_position(tile), "room": room,
				"locked": chest_id == 1 or (chest_id > 1 and _rng.randf() < 0.52),
			})
		var ambush := room == 2 or (room > 2 and _rng.randf() < minf(0.82, 0.17 + level * 0.052))
		var mob_count := _rng.randi_range(2, 3) + mini(3, floori((level - 1) / 3.0))
		if ambush:
			mob_count += 1
		for member in range(mini(mob_count, positions.size())):
			var tile: Vector2i = positions.pop_at(_rng.randi_range(0, positions.size() - 1))
			var offset := Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35))
			encounters.append({
				"position": tile_position(tile) + offset,
				"archetype": _pick_archetype(level),
				"pack": room, "room": room, "ambush": ambush,
				"alert_radius": minf(11.0, 6.6 + level * 0.38),
			})


func _build_legacy_chambers() -> void:
	for room in range(room_bounds.size()):
		var bounds := room_bounds[room]
		var left := bounds.position
		var right := bounds.end - Vector2i.ONE
		var lanterns: Array[Vector2i] = [left, right]
		for index in range(lanterns.size()):
			var tile := lanterns[index]
			if coffer_tiles.has(tile):
				continue
			# Corner lamps stay inside the wall trim and clear of chest and enemy spawn centers.
			var sign_value := 1.0 if index == 0 else -1.0
			var center := tile_position(tile) - Vector3(0.96, 0.0, 0.96) * sign_value
			var cool := room % 4 == 3
			_brazier(tile, center, cool)
		if room == 0 or bounds.size.x >= 5:
			var mark := _room_centers[room]
			if room == 0:
				mark += _arrival_gate
			_sigils(mark, 1.45 if room == 0 else 1.10)


func _build_expedition_chambers(seed_value: int, depth: int, floor_index: int) -> void:
	var decorations := Node3D.new()
	decorations.name = "ChamberSetpieces"
	add_child(decorations)
	var dressing := Node3D.new()
	dressing.name = "EdgeDressing"
	decorations.add_child(dressing)
	var occupied: Dictionary = {}
	var gate_enabled := _generation_version >= GATE_GENERATION_VERSION and depth >= 2 \
		and _feature_enabled(FEATURE_ROUTE_GATE, floor_index == 0 or (floor_index == 1 and depth >= 7))
	var altar_enabled := _feature_enabled(FEATURE_BLOOD_ALTAR, false)
	var stair_approaches: Variant = get("stair_approach_tiles")
	if stair_approaches is Dictionary:
		occupied.merge(stair_approaches)
	for entry in chests + hazard_points + encounters:
		occupied[tile_at(entry.position)] = true
	if secret_merchant_position.is_finite():
		occupied[tile_at(secret_merchant_position)] = true
	occupied.merge(coffer_tiles)
	for room in rooms:
		var id: int = room.id
		var center: Vector2i = room.center
		if id == int(challenge_chamber.get("room", -1)):
			var names := {ChallengeChambers.PLATFORM: "Raised Crypt", ChallengeChambers.LAVA: "Cinder Furnace",
				ChallengeChambers.SUBMERGED: "Drowned Bath"}
			room_names[id] = names[challenge_chamber.kind]
			for tile: Vector2i in room.tiles:
				occupied[tile] = true
			continue
		var theme := &"reliquary" if room.role == &"vault" else Setpieces.archetype_for(depth_theme, id, seed_value)
		room["theme"] = theme
		var display_name := String(theme).capitalize()
		if id == 0:
			display_name = "Arrival Gate"
		elif room.role == &"vault":
			display_name = "Warded Reliquary"
		room_names[id] = display_name
		var decorated_tiles := Setpieces.build(decorations, self, room, depth_theme, seed_value)
		if _generation_version >= 4:
			EdgeDressing.place_chamber(dressing, self, room, decorated_tiles, occupied, seed_value, _generation_version >= 5,
				_generation_version >= EXPANDED_ROSTER_VERSION)
		if gate_enabled or altar_enabled:
			for tile: Vector2i in decorated_tiles:
				occupied[tile] = true
		if id == 0:
			_sigils(center + _arrival_gate, 1.45)
		if id == 0 or id % 2 == 0:
			for tile: Vector2i in room.tiles:
				if tile in room.doors or tile in decorated_tiles or _cover_tiles.has(tile) or coffer_tiles.has(tile):
					continue
				var inset := Vector3.ZERO
				var walls := 0
				for step in DIRECTIONS:
					if not map_cells.has(tile + step):
						inset += Vector3(step.x, 0, step.y) * 0.95
						walls += 1
				if walls >= 2:
					_brazier(tile, tile_position(tile) + inset, id % 4 == 2)
					if gate_enabled or altar_enabled:
						occupied[tile] = true
					break
		for tile: Vector2i in room.cover:
			_build_cover(tile, int(_cover_tiles[tile]))
	if _generation_version >= 4:
		EdgeDressing.place_passages(dressing, self)
		if gate_enabled:
			occupied.merge(_thresholds)
			for secret: Dictionary in secret_passages:
				for tile: Vector2i in secret.hidden_tiles:
					occupied[tile] = true
			var gate := RouteGates.choose(self, occupied, floor_index, seed_value)
			if not gate.is_empty():
				route_gates.append(gate)
				occupied[gate.gate_tile] = true
				occupied[gate.key_tile] = true
	if altar_enabled:
		var tile := _blood_altar_site(occupied, seed_value)
		if map_cells.has(tile):
			blood_altar_position = tile_position(tile)
			occupied[tile] = true
	if _generation_version >= 4:
		if _generation_version >= 5:
			EdgeDressing.place_gallery_niches(dressing, self, occupied, seed_value)
		if _generation_version >= EXPANDED_ROSTER_VERSION:
			EdgeDressing.place_secret_approach_pottery(dressing, self, occupied, seed_value)
		for prop in dressing.get_children():
			if prop.has_signal("broken"):
				var id := str(prop.name)
				_breakable_props[id] = prop
				prop.connect("broken", _emit_breakable_destroyed.bind(prop, id))
	for blocker in decorations.find_children("*", "CollisionShape3D", true, false):
		_navigation_blockers.append(blocker)


func _blood_altar_site(occupied: Dictionary, seed_value: int) -> Vector2i:
	var best := -INF
	var selected := Vector2i(999999, 999999)
	for room: Dictionary in rooms:
		if room.id < 2 or room.role == &"vault" or room.id == int(challenge_chamber.get("room", -1)):
			continue
		for tile: Vector2i in room.interior:
			if occupied.has(tile) or _thresholds.has(tile) or _cover_tiles.has(tile):
				continue
			var access := 0
			for direction: Vector2i in DIRECTIONS:
				if int(map_cells.get(tile + direction, -1)) == room.id and not _cover_tiles.has(tile + direction):
					access += 1
			if access < 3:
				continue
			var score := access + (2.0 if room.role == &"quiet" else 0.0) \
				+ float(posmod(hash([tile, seed_value, 4013]), 1000)) / 1000.0
			if score > best:
				best = score
				selected = tile
	return selected


func _seat_coffers(seed_value: int) -> void:
	# The seeded records still reserve the same content and address the same save IDs.
	_coffer_poses = CofferPlacement.solve(self, _thresholds, _cover_tiles, seed_value)
	for pose: Transform3D in _coffer_poses.values():
		coffer_tiles[tile_at(pose.origin)] = true


func coffer_pose(id: int) -> Transform3D:
	return _coffer_poses[id]


## Both the input and the returned point use the floor's local coordinate system.
func return_portal_clearance(point: Vector3) -> Vector3:
	for pose: Transform3D in _coffer_poses.values():
		var local := pose.affine_inverse() * point
		if absf(local.x) < 0.92 and absf(local.z) < 1.02:
			var clearing := pose.origin + pose.basis.z * 1.42
			clearing.y = point.y
			var tile := Vector2i(roundi(clearing.x / CELL_SIZE), roundi(clearing.z / CELL_SIZE))
			if map_cells.has(tile) and not _cover_tiles.has(tile):
				return clearing
	return point


func _emit_breakable_destroyed(prop: Node3D, id: String) -> void:
	var inward := prop.global_basis.z.normalized()
	breakable_destroyed.emit(id, prop.global_position + inward * 0.62)


func restore_breakables(broken_ids: Dictionary) -> void:
	for id: String in broken_ids:
		var prop := _breakable_props.get(id) as Node3D
		if not is_instance_valid(prop):
			continue
		if prop.is_node_ready():
			prop.break_silently()
		else:
			prop.ready.connect(prop.break_silently, CONNECT_ONE_SHOT)


func _build_cover(tile: Vector2i, form: int) -> void:
	var module := StringName("Cover%d" % clampi(form, 0, COVER_SCENES.size() - 1))
	_place_module(tile, module, Transform3D(Basis.IDENTITY, tile_position(tile)))


func _sigils(tile: Vector2i, radius: float) -> void:
	var mark := _surface(tile, BRONZE)
	var center := tile_position(tile) + Vector3.UP * 0.018
	for edge in range(8):
		var angle := TAU * float(edge) / 8.0
		var next := TAU * float(edge + 1) / 8.0
		var first := center + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var last := center + Vector3(cos(next), 0.0, sin(next)) * radius
		var line := last - first
		mark.box((first + last) * 0.5, Vector3(line.length(), 0.017, 0.052), Basis(Vector3.UP, atan2(-line.z, line.x)))
	for edge in range(4):
		var angle := PI * float(edge) / 4.0
		mark.box(center, Vector3(radius * 1.6, 0.018, 0.05), Basis(Vector3.UP, angle))


func _brazier(tile: Vector2i, center: Vector3, low_flame: bool) -> void:
	_place_module(tile, &"Brazier", Transform3D(Basis.IDENTITY, center), Color.WHITE,
		_palette.ember if low_flame else _palette.light, 0.76 if low_flame else 0.87)


func _sconce(tile: Vector2i, direction: Vector2i) -> void:
	var outward := Vector3(direction.x, 0.0, direction.y)
	var across := Vector3(-direction.y, 0.0, direction.x)
	var center := tile_position(tile) + outward * (CELL_SIZE * 0.5 - 0.26)
	var sconce_basis := Basis(across, Vector3.UP, -outward)
	_place_module(tile, &"Sconce", Transform3D(sconce_basis, center), Color.WHITE,
		_palette.light if _generation_version > 1 else Color("ffa775"), 0.85)


func _light(point: Vector3, tint: Color, reach: float, energy: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = point
	lamp.light_color = tint
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.45
	add_child(lamp)
	_torches.append(lamp)
	_torch_energies.append(energy)


func _chunk(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / CHUNK_SIZE), floori(float(tile.y) / CHUNK_SIZE))


func _surface(tile: Vector2i, material: StringName) -> Geometry:
	var chunk := _chunk(tile)
	if not _batches.has(chunk):
		_batches[chunk] = {}
	var group: Dictionary = _batches[chunk]
	if not group.has(material):
		group[material] = Geometry.new()
	return group[material]


func _collision_body(tile: Vector2i) -> StaticBody3D:
	var chunk := _chunk(tile)
	if not _colliders.has(chunk):
		var body := StaticBody3D.new()
		body.name = "CryptCollision_%d_%d" % [chunk.x, chunk.y]
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		_colliders[chunk] = body
	return _colliders[chunk]


func _collision_box(body: StaticBody3D, center: Vector3, size: Vector3) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = center
	body.add_child(collision)
	return collision


func _flush_meshes() -> void:
	if _floor_material != null and not _floor_geometry.vertices.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _floor_geometry.arrays())
		mesh.surface_set_material(0, _floor_material)
		var floor_mesh := MeshInstance3D.new()
		floor_mesh.name = "Flagstones"
		floor_mesh.mesh = mesh
		_floor_body.add_child(floor_mesh)
		var receiver := BloodFloorProjection.instantiate()
		receiver.collision_body = _floor_body
		receiver.receiver_mesh = floor_mesh
		_floor_body.add_child(receiver)
		_floor_geometry = Geometry.new()
	for chunk: Vector2i in _batches:
		var batch: Dictionary = _batches[chunk]
		var mesh := ArrayMesh.new()
		for material: StringName in batch:
			var geometry: Geometry = batch[material]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, geometry.arrays())
			mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[material])
		var instance := MeshInstance3D.new()
		instance.name = "CryptMesh_%d_%d" % [chunk.x, chunk.y]
		instance.mesh = mesh
		add_child(instance)
	_batches.clear()

