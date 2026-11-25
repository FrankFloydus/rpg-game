extends RefCounted
## Each expedition chooses one masonry set independently of its floor layout.

const DEFAULT := &"iron_crypt"
const IDS: Array[StringName] = [
	DEFAULT, &"flooded_ossuary", &"ash_foundry", &"rootbound_vault", &"sable_catacomb",
]

const ALBEDOS := {
	DEFAULT: {
		&"floor": preload("res://assets/rework/crypt_floor.png"),
		&"wall": preload("res://assets/rework/crypt_wall.png"),
		&"ceiling": preload("res://assets/rework/crypt_ceiling.png"),
	},
	&"flooded_ossuary": {
		&"floor": preload("res://assets/dungeon/tilesets/flooded_ossuary/floor.png"),
		&"wall": preload("res://assets/dungeon/tilesets/flooded_ossuary/wall.png"),
		&"ceiling": preload("res://assets/dungeon/tilesets/flooded_ossuary/ceiling.png"),
	},
	&"ash_foundry": {
		&"floor": preload("res://assets/dungeon/tilesets/ash_foundry/floor.png"),
		&"wall": preload("res://assets/dungeon/tilesets/ash_foundry/wall.png"),
		&"ceiling": preload("res://assets/dungeon/tilesets/ash_foundry/ceiling.png"),
	},
	&"rootbound_vault": {
		&"floor": preload("res://assets/dungeon/tilesets/rootbound_vault/floor.png"),
		&"wall": preload("res://assets/dungeon/tilesets/rootbound_vault/wall.png"),
		&"ceiling": preload("res://assets/dungeon/tilesets/rootbound_vault/ceiling.png"),
	},
	&"sable_catacomb": {
		&"floor": preload("res://assets/dungeon/tilesets/sable_catacomb/floor.png"),
		&"wall": preload("res://assets/dungeon/tilesets/sable_catacomb/wall.png"),
		&"ceiling": preload("res://assets/dungeon/tilesets/sable_catacomb/ceiling.png"),
	},
}

# One complete repeat measured in metres. Wall atlases have different course counts.
# Values are wall, floor, and ceiling; walls target roughly 23–29 cm per course.
const REPEAT_METRES := {
	DEFAULT: Vector3(2.35, 3.00, 2.80),
	&"flooded_ossuary": Vector3(2.45, 3.05, 2.85),
	&"ash_foundry": Vector3(1.40, 2.75, 2.55),
	&"rootbound_vault": Vector3(1.45, 2.70, 2.55),
	&"sable_catacomb": Vector3(1.45, 2.90, 2.70),
}

const LIGHTING := {
	DEFAULT: {
		"ambient": Color("918a80"), "ambient_energy": 0.50, "fog": Color("1e1b18"),
		"light": Color("f9e2c7"), "ember": Color("ddba99"),
		"floor": Color("ded7cd"), "wall": Color("dcd6ce"), "ceiling": Color("ada79d"),
		"threshold_fill": Color("b5aa9e"),
	},
	&"flooded_ossuary": {
		"ambient": Color("879693"), "ambient_energy": 0.44, "fog": Color("1a2324"),
		"light": Color("edddc8"), "ember": Color("cebb9f"),
		"floor": Color("bcc7c5"), "wall": Color("bac6c7"), "ceiling": Color("949f9e"),
		"threshold_fill": Color("96a3a0"),
	},
	&"ash_foundry": {
		"ambient": Color("b0aaa4"), "ambient_energy": 0.73, "fog": Color("24201d"),
		"light": Color("f4e3ce"), "ember": Color("dea985"),
		"floor": Color("cbd6dc"), "wall": Color("add2e6"), "ceiling": Color("8c9eaa"),
		"threshold_fill": Color("b5aca3"),
	},
	&"rootbound_vault": {
		"ambient": Color("9ca59c"), "ambient_energy": 0.63, "fog": Color("202624"),
		"light": Color("eadfc9"), "ember": Color("d3bfa1"),
		"floor": Color("c2c7d5"), "wall": Color("bfc8d9"), "ceiling": Color("a2a9b4"),
		"threshold_fill": Color("abb3a6"),
	},
	&"sable_catacomb": {
		"ambient": Color("a9aaa8"), "ambient_energy": 0.85, "fog": Color("202021"),
		"light": Color("eee0ce"), "ember": Color("d5b6a1"),
		"floor": Color("ddd9d6"), "wall": Color("dddad8"), "ceiling": Color("adabaa"),
		"threshold_fill": Color("b1b0aa"),
	},
}


static func choose(seed_value: int) -> StringName:
	return IDS[posmod(hash([&"expedition_masonry", seed_value]), IDS.size())]


static func is_known(id: StringName) -> bool:
	return ALBEDOS.has(id)


static func albedo(id: StringName, surface: StringName) -> Texture2D:
	return ALBEDOS.get(id, ALBEDOS[DEFAULT])[surface]


static func lighting(id: StringName) -> Dictionary:
	return LIGHTING.get(id, LIGHTING[DEFAULT])


static func masonry_surface(source: Texture2D) -> StringName:
	if source == null:
		return &""
	# Imported masonry kits prefix their embedded images with the model name.
	var filename := source.resource_path.get_file()
	for surface: StringName in ALBEDOS[DEFAULT]:
		if filename.ends_with("crypt_%s.png" % surface):
			return surface
	return &""


static func repeats_per_metre(id: StringName, surface: StringName) -> float:
	var repeat: Vector3 = REPEAT_METRES.get(id, REPEAT_METRES[DEFAULT])
	match surface:
		&"floor": return 1.0 / repeat.y
		&"ceiling": return 1.0 / repeat.z
		_: return 1.0 / repeat.x


static func apply_masonry(material: StandardMaterial3D, id: StringName, surface: StringName) -> void:
	material.albedo_texture = albedo(id, surface)
	material.albedo_color *= lighting(id)[surface]
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * repeats_per_metre(id, surface)
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
