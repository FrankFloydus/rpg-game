extends RefCounted
## The shell owns the carved layout. These fixtures occupy unused wall faces,
## with solid furniture confined to the perimeter beside those faces.

const WALL_TEXTURE := preload("res://assets/rework/crypt_wall.png")
const WORN_LINEN := preload("res://assets/grounded/worn_linen.png")
const CREATURE_SURFACES := preload("res://assets/rework/creature_materials.png")
const FUNGUS_SURFACES := preload("res://assets/grounded/fungus_surface.png")
const DRESSING_PARTS := preload("res://world/modules/dungeon_dressing_parts.tscn")
const TORCH_FLAME := preload("res://world/modules/torch_flame.tscn")
const CRYPT_SLAB := preload("res://assets/models/dressing/room_themes/crypt_slab.glb")
const CHAPEL_ALTAR := preload("res://assets/models/dressing/room_themes/chapel_altar.glb")
const ARMORY_RACK := preload("res://assets/models/dressing/room_themes/armory_rack.glb")
const GAOL_GRILLE := preload("res://assets/models/dressing/room_themes/gaol_grille.glb")
const ARCHIVE_SHELF := preload("res://assets/models/dressing/room_themes/archive_shelves.glb")
const RELIQUARY_CHASSE := preload("res://assets/models/dressing/room_themes/reliquary_chasse.glb")
const CISTERN_OUTFALL := preload("res://assets/models/dressing/room_themes/cistern_outfall.glb")
const SLUICE_GATE := preload("res://assets/models/dressing/room_themes/sluice_gate.glb")
const FORGE_HEARTH := preload("res://assets/models/dressing/room_themes/forge_hearth.glb")
const PYRE_STAND := preload("res://assets/models/dressing/room_themes/pyre_stand.glb")
const OSSUARY_SHELVES := preload("res://assets/models/dressing/room_themes/ossuary_shelves.glb")
const BONE_GATE_TROPHY := preload("res://assets/models/dressing/room_themes/bone_gate_trophy.glb")
const GROTTO_FUNGI := preload("res://assets/models/dressing/room_themes/grotto_colony.glb")
const AGED_WOOD := preload("res://assets/rework/materials/aged_wood.tres")
const FORGED_STEEL := preload("res://assets/rework/materials/forged_steel.tres")
const WEATHERED_BRONZE := preload("res://assets/rework/materials/weathered_bronze.tres")
const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const ARCHETYPES := {
	&"iron_crypt": [&"crypt", &"chapel", &"armory", &"gaol", &"archive", &"reliquary", &"ossuary", &"sluice"],
	&"drowned_vault": [&"cistern", &"sluice", &"drowned_altar", &"crypt", &"gaol", &"reliquary", &"archive", &"grotto"],
	&"ashen_catacomb": [&"forge", &"pyre", &"cinder_shrine", &"armory", &"gaol", &"crypt", &"archive", &"reliquary"],
	&"blighted_ossuary": [&"ossuary", &"grotto", &"bone_gate", &"archive", &"cistern", &"crypt", &"reliquary", &"gaol"],
}
const REGION_STONE := {
	&"iron_crypt": Color("#9c918c"), &"drowned_vault": Color("#748f89"),
	&"ashen_catacomb": Color("#a08067"), &"blighted_ossuary": Color("#99829c"),
}
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 water_tint : source_color = vec4(0.06, 0.28, 0.24, 1.0);
uniform bool falling = false;
void fragment() {
	vec2 uv = UV;
	float sway = sin(uv.y * 7.0 - TIME * 1.28) * 0.54;
	float wave = falling
		? sin(uv.x * 75.0 + sway + sin(uv.y * 11.0 - TIME * 3.6) * 0.48)
		: sin(uv.x * 35.0 + uv.y * 17.0 + TIME * 1.5 + 2.0 * sin(uv.y * 8.0));
	float wave_b = sin(uv.x * 55.0 + uv.y * 75.0 + TIME * (falling ? -10.8 : 1.78));
	float foam = smoothstep(0.33, 1.07, wave * 0.75 + wave_b * 0.31);
	float edges = smoothstep(0.02, 0.20, uv.x) * (1.0 - smoothstep(0.80, 0.98, uv.x));
	float ends = smoothstep(0.00, 0.11, uv.y) * (1.0 - smoothstep(0.78, 1.0, uv.y));
	ALBEDO = water_tint.rgb * (0.55 + foam * 1.28);
	EMISSION = water_tint.rgb * (0.06 + foam * 0.15);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = edges * ends * ((falling ? 0.30 : 0.49) + foam * 0.38);
}
"""

enum Shape { BOX, CYLINDER, DOME, PLANE }

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


class WallFace:
	var tile: Vector2i
	var point: Vector3
	var basis: Basis

	func _init(cell: Vector2i, base: Vector3, normal: Vector3) -> void:
		tile = cell
		point = base
		basis = Basis(Vector3.UP.cross(normal), Vector3.UP, normal)

	func to_room(local: Vector3) -> Vector3:
		return point + basis * local


class Decoration:
	var root: Node3D
	var rng := RandomNumberGenerator.new()
	var _mesh_catalog: Dictionary
	var _palette: Dictionary
	var _groups: Dictionary = {}
	var _collision: StaticBody3D
	var _water: Dictionary = {}

	func _init(parent: Node3D, room_id: int, tag: StringName, seed_value: int,
			mesh_catalog: Dictionary, palette: Dictionary) -> void:
		root = Node3D.new()
		root.name = "Room%d_%s" % [room_id, String(tag).to_pascal_case()]
		parent.add_child(root)
		rng.seed = seed_value
		_mesh_catalog = mesh_catalog
		_palette = palette

	func put(face: WallFace, shape: int, key: StringName, point: Vector3, size: Vector3,
			rotation := Vector3.ZERO) -> void:
		var pose := face.basis * Basis.from_euler(rotation) * Basis.from_scale(size)
		var batch_key := Vector2i(shape, int(_palette[key][0]))
		if not _groups.has(batch_key):
			_groups[batch_key] = []
		_groups[batch_key].append(Transform3D(pose, face.to_room(point)))

	func box(face: WallFace, key: StringName, point: Vector3, size: Vector3,
			rotation := Vector3.ZERO) -> void:
		put(face, Shape.BOX, key, point, size, rotation)


	func place_prop(face: WallFace, scene: PackedScene, point: Vector3, size: Vector3,
			turn := 0.0) -> void:
		var prop := scene.instantiate() as Node3D
		var pose := face.basis * Basis(Vector3.UP, turn) * Basis.from_scale(size)
		prop.transform = Transform3D(pose, face.to_room(point))
		root.add_child(prop)

	func solid(face: WallFace, point: Vector3, size: Vector3) -> void:
		if _collision == null:
			_collision = StaticBody3D.new()
			_collision.collision_layer = 1
			_collision.collision_mask = 0
			root.add_child(_collision)
		var shape := BoxShape3D.new()
		shape.size = size
		var body := CollisionShape3D.new()
		body.shape = shape
		body.transform = Transform3D(face.basis, face.to_room(point))
		_collision.add_child(body)

	func light(face: WallFace, point: Vector3, tint: Color, reach: float, strength: float) -> void:
		var lamp := OmniLight3D.new()
		lamp.position = face.to_room(point)
		lamp.light_color = tint
		lamp.light_energy = strength
		lamp.omni_range = reach
		lamp.omni_attenuation = 1.4
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 23.0
		lamp.distance_fade_length = 6.0
		root.add_child(lamp)

	func water(face: WallFace, point: Vector3, size: Vector2, falling := false) -> void:
		if not _water.has(falling):
			var ripples := Shader.new()
			ripples.code = WATER_SHADER
			var material := ShaderMaterial.new()
			material.shader = ripples
			material.set_shader_parameter("falling", falling)
			_water[falling] = material
		var geometry := MeshInstance3D.new()
		geometry.mesh = _mesh_catalog[Shape.PLANE]
		geometry.material_override = _water[falling]
		var tilt := Basis.IDENTITY if falling else Basis(Vector3.RIGHT, PI / 2.0)
		geometry.transform = Transform3D(face.basis * tilt * Basis.from_scale(Vector3(size.x, size.y, 1.0)),
			face.to_room(point))
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(geometry)

	func flush() -> void:
		var by_index: Dictionary = {}
		for row: Array in _palette.values():
			by_index[row[0]] = row[1]
		for key: Vector2i in _groups:
			var instances: Array = _groups[key]
			var mesh_batch := MultiMesh.new()
			mesh_batch.transform_format = MultiMesh.TRANSFORM_3D
			mesh_batch.mesh = _mesh_catalog[key.x]
			mesh_batch.instance_count = instances.size()
			for index in instances.size():
				mesh_batch.set_instance_transform(index, instances[index])
			var renderer := MultiMeshInstance3D.new()
			renderer.multimesh = mesh_batch
			renderer.material_override = by_index[key.y]
			renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(renderer)


static func archetype_for(region: StringName, index: int, seed_value: int) -> StringName:
	if index == 0:
		return &"vestibule"
	var ordered: Array = ARCHETYPES.get(region, ARCHETYPES[&"iron_crypt"]).duplicate()
	var choice := RandomNumberGenerator.new()
	choice.seed = hash([region, seed_value])
	# Every run opens its pool with the region's three signature rooms.
	_shuffle_range(ordered, 0, 3, choice)
	_shuffle_range(ordered, 3, ordered.size(), choice)
	return ordered[posmod(index - 1, ordered.size())]


static func _shuffle_range(ordered: Array, first: int, end: int, choice: RandomNumberGenerator) -> void:
	for cursor in range(end - 1, first, -1):
		var other := choice.randi_range(first, cursor)
		var key: StringName = ordered[cursor]
		ordered[cursor] = ordered[other]
		ordered[other] = key


static func build(parent: Node3D, dungeon: Node3D, room: Dictionary, region: StringName,
		seed_value: int) -> Array[Vector2i]:
	var room_id := int(room.get("id", 0))
	var tag: StringName = room.get("theme", &"")
	if tag.is_empty():
		tag = archetype_for(region, room_id, seed_value)
	if tag == &"vestibule":
		return []
	var local_seed := hash([seed_value, room_id, tag])
	var chooser := RandomNumberGenerator.new()
	chooser.seed = local_seed
	var faces := _candidate_faces(dungeon, room, chooser)
	if faces.is_empty():
		return []
	_prepare_meshes()
	var art := Decoration.new(parent, room_id, tag, local_seed, _meshes, _palette(region))
	_build_floor_signature(art, dungeon, room, tag)
	_build_feature(art, faces[0], tag, true)
	var maximum := 3 if room.tiles.size() >= 21 else 2
	var used_tiles: Array[Vector2i] = [faces[0].tile]
	var used_points: Array[Vector3] = [faces[0].point]
	for index in range(1, faces.size()):
		var candidate := faces[index]
		if candidate.tile in used_tiles:
			continue
		var near_fixture := false
		for point in used_points:
			if candidate.point.distance_squared_to(point) < 12.0:
				near_fixture = true
				break
		if not near_fixture:
			_build_feature(art, candidate, tag, false)
			used_tiles.append(candidate.tile)
			used_points.append(candidate.point)
		if used_tiles.size() >= maximum:
			break
	art.flush()
	return used_tiles


static func _build_floor_signature(art: Decoration, dungeon: Node3D, room: Dictionary,
		tag: StringName) -> void:
	var floor_tiles := {}
	for tile: Vector2i in room.get("interior", []):
		if tile not in room.cover:
			floor_tiles[tile] = true
	for door: Vector2i in room.doors:
		floor_tiles.erase(door)
		for direction in CARDINALS:
			floor_tiles.erase(door + direction)
	for hazard: Dictionary in dungeon.hazard_points:
		if hazard.room == room.id:
			floor_tiles.erase(dungeon.tile_at(hazard.position))
	for chest: Dictionary in dungeon.chests:
		if chest.room == room.id:
			floor_tiles.erase(dungeon.tile_at(chest.position))
	if floor_tiles.is_empty():
		return
	match tag:
		&"cistern", &"sluice":
			_reservoir_lanes(art, dungeon, room.center, floor_tiles)
		&"forge", &"pyre", &"armory":
			_floor_lane(art, dungeon, room.center, floor_tiles, &"duct")
		&"chapel", &"drowned_altar", &"cinder_shrine":
			_floor_lane(art, dungeon, room.center, floor_tiles, &"runner")
		&"crypt", &"reliquary", &"ossuary", &"bone_gate", &"grotto":
			_ritual_inlay(art, dungeon, room.center, floor_tiles, tag)


static func _reservoir_lanes(art: Decoration, dungeon: Node3D, center: Vector2i, tiles: Dictionary) -> void:
	var across := [_longest_lane_cells(tiles, Vector2i.RIGHT, center, -1),
		_longest_lane_cells(tiles, Vector2i.RIGHT, center, 1)]
	var along := [_longest_lane_cells(tiles, Vector2i.DOWN, center, -1),
		_longest_lane_cells(tiles, Vector2i.DOWN, center, 1)]
	var across_length: int = across[0].size() + across[1].size()
	var along_length: int = along[0].size() + along[1].size()
	var axis := Vector2i.RIGHT if across_length >= along_length else Vector2i.DOWN
	var lanes := across if axis == Vector2i.RIGHT else along
	for lane: Array[Vector2i] in lanes:
		if lane.size() < 2:
			continue
		var floor_face := _lane_face(dungeon, lane, axis)
		var width: float = dungeon.CELL_SIZE*0.90
		var length: float = dungeon.CELL_SIZE*(lane.size() - 0.15)
		art.box(floor_face, &"soot", Vector3(0, 0.007, 0), Vector3(length, 0.012, width))
		art.water(floor_face, Vector3(0, 0.024, 0), Vector2(length, width))
		for side: float in [-1.0, 1.0]:
			art.box(floor_face, &"copper", Vector3(0, 0.019, side*width*0.47), Vector3(length, 0.022, 0.105))
		for end: float in [-1.0, 1.0]:
			art.box(floor_face, &"iron", Vector3(end*length*0.47, 0.023, 0), Vector3(0.17, 0.025, width))


static func _floor_lane(art: Decoration, dungeon: Node3D, center: Vector2i, tiles: Dictionary,
		tag: StringName) -> void:
	var across := _longest_lane_cells(tiles, Vector2i.RIGHT, center)
	var along := _longest_lane_cells(tiles, Vector2i.DOWN, center)
	var axis := Vector2i.RIGHT if across.size() >= along.size() else Vector2i.DOWN
	var lane := across if axis == Vector2i.RIGHT else along
	if lane.size() < 2:
		return
	var floor_face := _lane_face(dungeon, lane, axis)
	var length: float = dungeon.CELL_SIZE*(lane.size() - 0.18)
	var width := 1.58 if tag == &"runner" else 1.72
	art.box(floor_face, tag, Vector3(0, 0.009, 0), Vector3(length, 0.012, width))
	for edge: float in [-1.0, 1.0]:
		art.box(floor_face, &"inlay", Vector3(0, 0.019, edge*width*0.46), Vector3(length, 0.012, 0.053))
	if tag == &"duct":
		for index in range(1, lane.size()*3):
			var x := lerpf(-length*0.48, length*0.48, float(index) / (lane.size()*3.0))
			art.box(floor_face, &"iron", Vector3(x, 0.023, 0), Vector3(0.095, 0.01, width*0.91))
		art.box(floor_face, &"brass", Vector3(0, 0.024, 0), Vector3(length, 0.011, 0.06))
	else:
		for index in lane.size():
			var x := lerpf(-length*0.4, length*0.4, (float(index) + 0.5)/lane.size())
			art.box(floor_face, &"inlay", Vector3(x, 0.020, 0), Vector3(0.26, 0.01, 0.26), Vector3(0, PI/4.0, 0))


static func _longest_lane_cells(tiles: Dictionary, axis: Vector2i, center: Vector2i,
		side := 0) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var side_axis := Vector2i(-axis.y, axis.x)
	for tile: Vector2i in tiles:
		if tiles.has(tile - axis):
			continue
		var offset := tile - center
		var distance_from_center := offset.x*side_axis.x + offset.y*side_axis.y
		if side != 0 and signi(distance_from_center) != side:
			continue
		var run: Array[Vector2i] = [tile]
		var next := tile + axis
		while tiles.has(next):
			run.append(next)
			next += axis
		if run.size() > best.size():
			best = run
	return best


static func _lane_face(dungeon: Node3D, lane: Array[Vector2i], axis: Vector2i) -> WallFace:
	var middle: Vector3 = (dungeon.tile_position(lane.front()) + dungeon.tile_position(lane.back())) * 0.5
	return WallFace.new(Vector2i.ZERO, middle, Vector3.BACK if axis == Vector2i.RIGHT else Vector3.LEFT)


static func _ritual_inlay(art: Decoration, dungeon: Node3D, center: Vector2i, tiles: Dictionary,
		tag: StringName) -> void:
	if not tiles.has(center):
		return
	var origin: Vector3 = dungeon.tile_position(center)
	var floor_face := WallFace.new(center, origin, Vector3.BACK)
	var material := &"ivory" if tag in [&"ossuary", &"bone_gate"] else &"inlay"
	if tag == &"grotto":
		material = &"moss"
	var radius := 2.65
	var segments := 12 if tag == &"reliquary" else 8
	for ring: float in [radius, radius - 0.37]:
		for edge in segments:
			var first := Vector2.from_angle(TAU*float(edge)/segments) * ring
			var second := Vector2.from_angle(TAU*float(edge + 1)/segments) * ring
			var a := Vector3(first.x, 0.018, first.y)
			var b := Vector3(second.x, 0.018, second.y)
			if not tiles.has(dungeon.tile_at(origin + a)) or not tiles.has(dungeon.tile_at(origin + b)):
				continue
			var line := b - a
			art.box(floor_face, material, (a+b)*0.5, Vector3(line.length(), 0.013, 0.087 if ring == radius else 0.046),
				Vector3(0, atan2(-line.z, line.x), 0))
	for spoke in 4:
		var azimuth := TAU*float(spoke)/4.0 + PI/4.0
		var line := Vector2.from_angle(azimuth) * 0.83
		art.box(floor_face, material, Vector3(line.x, 0.019, line.y), Vector3(0.48, 0.014, 0.18),
			Vector3(0, -azimuth, 0))


static func _candidate_faces(dungeon: Node3D, room: Dictionary, chooser: RandomNumberGenerator) -> Array[WallFace]:
	var result: Array[WallFace] = []
	var doors: Array = room.get("doors", [])
	var covers: Array = room.get("cover", [])
	var half_cell: float = dungeon.CELL_SIZE * 0.5
	var stair_tiles: Variant = dungeon.get("stair_approach_tiles")
	for cell: Vector2i in room.tiles:
		if cell in doors or cell in covers or dungeon.coffer_tiles.has(cell):
			continue
		if stair_tiles is Dictionary and stair_tiles.has(cell):
			continue
		for direction in CARDINALS:
			if dungeon.map_cells.has(cell + direction):
				continue
			var outward := Vector3(direction.x, 0.0, direction.y)
			var boundary: Vector3 = dungeon.tile_position(cell) + outward * (half_cell - 0.045)
			result.append(WallFace.new(cell, boundary, -outward))
	for index in range(result.size() - 1, 0, -1):
		var other := chooser.randi_range(0, index)
		var face := result[index]
		result[index] = result[other]
		result[other] = face
	return result


static func _build_feature(art: Decoration, face: WallFace, tag: StringName, primary: bool) -> void:
	match tag:
		&"crypt":
			_crypt(art, face, primary)
		&"chapel", &"drowned_altar", &"cinder_shrine":
			_chapel(art, face, tag, primary)
		&"armory":
			_armory(art, face, primary)
		&"gaol":
			_gaol(art, face, primary)
		&"archive":
			_archive(art, face, primary)
		&"reliquary":
			_reliquary(art, face, primary)
		&"cistern", &"sluice":
			_cistern(art, face, tag, primary)
		&"forge":
			_forge(art, face, primary)
		&"pyre":
			_pyre(art, face, primary)
		&"ossuary", &"bone_gate":
			_ossuary(art, face, tag, primary)
		&"grotto":
			_grotto(art, face, primary)


static func _prepare_meshes() -> void:
	if not _meshes.is_empty():
		return
	var kit := DRESSING_PARTS.instantiate()
	for shape in Shape.values():
		var part := kit.get_node(String(Shape.find_key(shape)).capitalize()) as MeshInstance3D
		_meshes[shape] = part.mesh
	kit.free()


static func _palette(region: StringName) -> Dictionary:
	if _materials.has(region):
		return _materials[region]
	var tint: Color = REGION_STONE.get(region, REGION_STONE[&"iron_crypt"])
	var stone := _material(tint, WALL_TEXTURE)
	stone.uv1_triplanar = true
	stone.uv1_world_triplanar = true
	stone.uv1_scale = Vector3.ONE * 0.48
	var palette := {
		&"stone": stone, &"ash": _material(tint.lightened(0.17), WALL_TEXTURE),
		&"soot": _material(Color("#322829"), WALL_TEXTURE),
		&"iron": FORGED_STEEL,
		&"brass": WEATHERED_BRONZE,
		&"oak": AGED_WOOD,
		&"duct": _tinted_material(FORGED_STEEL, Color("#a07c63")),
		&"runner": _material(Color("#703838"), WORN_LINEN),
		&"inlay": WEATHERED_BRONZE,
		&"copper": _tinted_material(WEATHERED_BRONZE, Color("#75a79a")),
		&"ivory": _atlas_material(Color("#d3c0a1"), CREATURE_SURFACES, Vector2.ZERO),
		&"linen": _material(Color("#d9c6a5"), WORN_LINEN),
		&"wax": _atlas_material(Color("#e9c59d"), CREATURE_SURFACES, Vector2.ZERO),
		&"cloth": _material(Color("#813d40"), WORN_LINEN),
		&"violet": _material(Color("#87627a"), WORN_LINEN),
		&"moss": _atlas_material(Color("#6b9168"), FUNGUS_SURFACES, Vector2(0.5, 0.5)),
		&"gold": _material(Color("#ffba80"), WALL_TEXTURE, 1.22),
		&"ember": _material(Color("#ef6835"), WALL_TEXTURE, 1.61),
		&"ghost": _material(Color("#8be5d2"), WALL_TEXTURE, 1.21),
		&"spore": _material(Color("#c995ec"), WALL_TEXTURE, 0.91),
	}
	var tagged: Dictionary = {}
	var index := 0
	for key: StringName in palette:
		tagged[key] = [index, palette[key]]
		index += 1
	_materials[region] = tagged
	return tagged


static func _material(color: Color, texture: Texture2D, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = texture
	material.roughness = 1.0
	material.metallic_specular = 0.0
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


static func _tinted_material(surface: StandardMaterial3D, tint: Color) -> StandardMaterial3D:
	var material := surface.duplicate() as StandardMaterial3D
	material.albedo_color = tint
	return material


static func _atlas_material(color: Color, texture: Texture2D, tile: Vector2) -> StandardMaterial3D:
	var material := _material(color, texture)
	material.uv1_scale = Vector3(0.484, 0.484, 1.0)
	material.uv1_offset = Vector3(tile.x + 0.008, tile.y + 0.008, 0.0)
	material.texture_repeat = false
	return material


static func _crypt(art: Decoration, face: WallFace, primary: bool) -> void:
	var positions := PackedFloat32Array([-0.65, 0.65] if primary else [0.20])
	for index in positions.size():
		var x := positions[index]
		var height := art.rng.randf_range(0.92, 1.05)
		art.place_prop(face, CRYPT_SLAB, Vector3(x, 0, 0), Vector3(1, height, 1))
		art.solid(face, Vector3(x, 0.85, 0.35), Vector3(0.93, 1.7, 0.62))
		_candle(art, face, Vector3(x + (0.45 if index == 0 else -0.44), 0.32, 0.59), 0.23, &"gold")
	art.light(face, Vector3(0.0, 1.25, 1.24), Color("#ffab75"), 5.8 if primary else 4.5, 0.99)


static func _chapel(art: Decoration, face: WallFace, tag: StringName, primary: bool) -> void:
	var sea := tag == &"drowned_altar"
	var ash := tag == &"cinder_shrine"
	var flame := &"ghost" if sea else (&"ember" if ash else &"gold")
	var cast := Color("#7ce1cc") if sea else (Color("#ff8654") if ash else Color("#ffc38a"))
	art.place_prop(face, CHAPEL_ALTAR, Vector3.ZERO, Vector3.ONE)
	art.solid(face, Vector3(0, 0.4, 0.43), Vector3(1.77, 0.8, 0.72))
	for candle_index in (7 if primary else 4):
		var offset := (candle_index % 4) * 0.33 - 0.57
		var row := 0.59 if candle_index > 3 else 0.43
		_candle(art, face, Vector3(offset, 0.855, row), art.rng.randf_range(0.12, 0.30), flame)
	art.light(face, Vector3(0, 1.61, 1.08), cast, 7.0 if primary else 4.5, 1.34 if primary else 0.74)


static func _armory(art: Decoration, face: WallFace, primary: bool) -> void:
	var width := 2.75 if primary else 1.92
	art.place_prop(face, ARMORY_RACK, Vector3.ZERO, Vector3(width / 2.75, 1, 1))
	art.solid(face, Vector3(0, 0.39, 0.41), Vector3(width, 0.78, 0.65))
	_lantern(art, face, Vector3(0, 2.96, 0.56), &"gold")
	art.light(face, Vector3(0, 2.69, 1.11), Color("#f2bb91"), 5.7, 1.06)


static func _gaol(art: Decoration, face: WallFace, primary: bool) -> void:
	var width := 1.0 if primary else 0.68
	art.place_prop(face, GAOL_GRILLE, Vector3.ZERO, Vector3(width, 1, 1))
	_lantern(art, face, Vector3(0.80, 2.65, 0.66), &"ember")
	art.light(face, Vector3(0.68, 2.24, 1.11), Color("#e8916d"), 6.0, 1.04)


static func _archive(art: Decoration, face: WallFace, primary: bool) -> void:
	var span := 2.83 if primary else 1.77
	art.place_prop(face, ARCHIVE_SHELF, Vector3.ZERO, Vector3(span / 2.83, 1, 1))
	art.solid(face, Vector3(0, 1.28, 0.39), Vector3(span, 2.56, 0.60))
	_lantern(art, face, Vector3(0, 3.25, 0.47), &"spore")
	art.light(face, Vector3(0, 2.67, 1.11), Color("#e3ba99"), 5.6, 1.10)


static func _reliquary(art: Decoration, face: WallFace, primary: bool) -> void:
	var width := 1.17 if primary else 0.80
	art.place_prop(face, RELIQUARY_CHASSE, Vector3.ZERO, Vector3(width / 1.17, 1, 1))
	for side: float in [-1.0, 1.0]:
		_candle(art, face, Vector3(side*0.83*width, 1.125, 0.59), 0.24, &"gold")
	art.solid(face, Vector3(0, 0.49, 0.38), Vector3(width*2.1, 0.98, 0.68))
	art.light(face, Vector3(0, 1.87, 1.29), Color("#93e9ce"), 6.8 if primary else 5.0, 1.37)


static func _candle(art: Decoration, face: WallFace, point: Vector3, height: float, flame: StringName) -> void:
	art.put(face, Shape.CYLINDER, &"wax", point + Vector3.UP * height*0.5, Vector3(0.075, height, 0.075))
	_particle_fire(art, face, point + Vector3.UP * height, 0.30, flame, true)


static func _lantern(art: Decoration, face: WallFace, point: Vector3, flame: StringName) -> void:
	art.box(face, &"brass", point + Vector3.UP*0.31, Vector3(0.17, 0.06, 0.25))
	_particle_fire(art, face, point - Vector3.UP * 0.13, 0.61, flame, true)
	for level: float in [-0.155, 0.155]:
		art.put(face, Shape.DOME, &"iron", point + Vector3.UP*level,
			Vector3(0.28, 0.06, 0.28), Vector3(0, PI/4.0, 0))
	for x: float in [-0.095, 0.095]:
		for z: float in [-0.095, 0.095]:
			art.box(face, &"brass", point + Vector3(x, 0.0, z), Vector3(0.025, 0.33, 0.025))






static func _cistern(art: Decoration, face: WallFace, tag: StringName, primary: bool) -> void:
	var mechanical := tag == &"sluice"
	var width := 2.62 if primary else 1.81
	var fixture := SLUICE_GATE if mechanical else CISTERN_OUTFALL
	art.place_prop(face, fixture, Vector3.ZERO, Vector3(width / 2.62, 1, 1))
	art.water(face, Vector3(0, 0.016, 0.80), Vector2(width, 1.6))
	if mechanical:
		art.water(face, Vector3(-width*0.22, 1.49, 0.26), Vector2(width*0.35, 2.89), true)
	else:
		for flow_index in 3:
			var offset := (float(flow_index) - 1.0)*width*0.28
			art.water(face, Vector3(offset, 1.38, 0.63), Vector2(width*0.19, 2.75), true)
	_lantern(art, face, Vector3(-width*0.36, 3.34, 0.55), &"ghost")
	art.light(face, Vector3(0, 1.89, 1.32), Color("#89d9ca"), 7.4 if primary else 5.5, 1.23)


static func _forge(art: Decoration, face: WallFace, primary: bool) -> void:
	var radius := 1.19 if primary else 0.87
	art.place_prop(face, FORGE_HEARTH, Vector3.ZERO, Vector3(radius / 1.19, 1, 1))
	for fire: float in [-0.50, -0.15, 0.28, 0.55]:
		_flame(art, face, Vector3(fire*radius, 0.87, 0.42), art.rng.randf_range(0.30, 0.52))
	art.solid(face, Vector3(0, 0.43, 0.38), Vector3(2.25*radius, 0.86, 0.76))
	art.light(face, Vector3(0, 1.44, 1.08), Color("#ff9258"), 8.5 if primary else 6.4, 1.80)


static func _pyre(art: Decoration, face: WallFace, primary: bool) -> void:
	var count := 3 if primary else 2
	for index in count:
		var x := ((float(index) + 0.5) / count - 0.5) * 2.56
		var y := 0.93 + (0.35 if primary and index == 1 else 0.0)
		var size := Vector3(1.0, (y + 0.108) / 0.89, 1.0)
		art.place_prop(face, PYRE_STAND, Vector3(x, 0, 0.41), size, art.rng.randf_range(-0.3, 0.3))
		_flame(art, face, Vector3(x, y + 0.12, 0.41), 0.61 if primary and index == 1 else 0.49)
		art.solid(face, Vector3(x, y/2.0, 0.41), Vector3(0.55, y, 0.62))
	art.light(face, Vector3(0, 1.82, 1.22), Color("#ff7f4a"), 7.6 if primary else 5.6, 1.59)


static func _flame(art: Decoration, face: WallFace, point: Vector3, height: float) -> void:
	_particle_fire(art, face, point, height / 0.36, &"gold")


static func _particle_fire(art: Decoration, face: WallFace, point: Vector3,
		size: float, palette: StringName, compact := false) -> void:
	var fire := TORCH_FLAME.instantiate() as Node3D
	var lean := art.rng.randf_range(-0.14, 0.14)
	fire.transform = Transform3D(face.basis * Basis(Vector3.BACK, lean).scaled(Vector3.ONE * size),
		face.to_room(point))
	if compact:
		fire.get_node("Smoke").free()
		fire.get_node("Embers").free()
	const TINTS := {
		&"ember": Color(1.0, 0.77, 0.50),
		&"ghost": Color(0.39, 0.95, 1.74),
		&"spore": Color(0.59, 1.06, 0.66),
	}
	var tint: Color = TINTS.get(palette, Color.WHITE)
	for emitter: GPUParticles3D in fire.get_children():
		emitter.set_instance_shader_parameter("flame_tint", tint)
	art.root.add_child(fire)


static func _ossuary(art: Decoration, face: WallFace, tag: StringName, primary: bool) -> void:
	var fixture_scale := 1.0 if primary else 1.72 / 2.52
	var fixture := BONE_GATE_TROPHY if tag == &"bone_gate" and primary else OSSUARY_SHELVES
	art.place_prop(face, fixture, Vector3.ZERO, Vector3.ONE * fixture_scale)
	art.solid(face, Vector3(0, 0.8, 0.35) * fixture_scale, Vector3(2.52, 1.6, 0.59) * fixture_scale)
	_lantern(art, face, Vector3(0, 3.39, 0.56), &"ghost")
	art.light(face, Vector3(0, 2.21, 1.14) * fixture_scale, Color("#b0dabc"),
		7.2 if primary else 5.1, 1.33)




static func _grotto(art: Decoration, face: WallFace, primary: bool) -> void:
	art.place_prop(face, GROTTO_FUNGI, Vector3(-0.66 if primary else 0.0, 0.0, 0.16),
		Vector3.ONE * art.rng.randf_range(0.86, 1.09), art.rng.randf_range(-0.2, 0.2))
	if primary:
		art.place_prop(face, GROTTO_FUNGI, Vector3(0.69, 0.0, 0.11), Vector3.ONE * 0.74, 0.24)
	art.light(face, Vector3(-0.38, 1.26, 1.10), Color("#a9c8ae"), 7.6 if primary else 5.3, 0.93)
