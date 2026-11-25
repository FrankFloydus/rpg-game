extends Node3D

const Items = preload("res://systems/items.gd")
const HeldModels := preload("res://data/items/held_item_models.gd")
const COFFER = preload("res://world/props/coffer.tscn")
const RETURN_PORTAL = preload("res://world/props/return_portal.tscn")
const COINS = preload("res://world/props/coins.tscn")
const TREASURE_KEY = preload("res://world/props/treasure_key.tscn")
const CARD_LOOT = preload("res://world/props/card_loot.tscn")
const CardItems = preload("res://systems/card_items.gd")
const CardFace = preload("res://ui/card_face.gd")
const MONSTER_PART = preload("res://world/props/monster_part.tscn")
const UNVEILING_SCROLL = preload("res://world/props/unveiling_scroll.tscn")
const WEAPON_LOOT = preload("res://world/props/weapon_loot.tscn")
const GEAR_LOOT = preload("res://world/props/gear_loot.tscn")
const LOOT_OUTLINE = preload("res://world/props/loot_outline.gdshader")
const LOOT_BEAM = preload("res://world/props/loot_legendary_beam.gdshader")

const LOOT_LABEL_NORMAL := Color(0.012, 0.010, 0.010, 0.96)
const LOOT_LABEL_TARGETED := Color(0.135, 0.088, 0.054, 0.98)
const LOOT_LABEL_READABLE_DEPTH := 2.55
const LOOT_LABEL_RANGE := 9.0
const DROP_HEIGHT := 0.42
const DROP_SECONDS := 0.57

var payload: Dictionary
var interaction_point := Vector3.UP * 0.35
var margin := 0.56
var tint := Color("#f0dabd")
var text := ""
var _label: Label3D
var _body: Node3D
var _lid: Node3D
var _label_size := 0.0025
var _lid_angle := 0.0
var _kind := ""
var _loot_back: MeshInstance3D
var _loot_back_size := Vector2.ZERO
var _loot_ink: StandardMaterial3D
var _loot_outline: ShaderMaterial
var _loot_meshes: Array[MeshInstance3D] = []
var _loot_item_aim := Vector3.UP * 0.12
var _legendary := false
var _fall: RigidBody3D
var _settled_body: Transform3D
var _fall_left := 0.0


func setup(data: Dictionary) -> void:
	payload = data
	_kind = String(data.kind)
	var appearance: Node3D
	match _kind:
		"chest":
			appearance = COFFER.instantiate()
			_configure_coffer(appearance)
		"portal":
			appearance = RETURN_PORTAL.instantiate()
			margin = 1.0
			text = "Return to Cinderhold"
			tint = Color("#a4ddd0")
		"loot":
			appearance = _loot_model()
		_:
			return
	add_child(appearance)
	_body = appearance.get_node("Body")
	_label = appearance.get_node("WorldLabel")
	_label_size = _label.pixel_size
	if _kind == "loot":
		_set_up_ground_loot()
	else:
		_label.visible = bool(data.get("show_world_label", false))
	interaction_point = _label.position
	_label.text = text
	_label.modulate = tint
	if _kind == "chest" and bool(data.get("opened", false)):
		opened(false)


func _process(delta: float) -> void:
	if not is_instance_valid(_label):
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and _label.visible:
		var offset := _label.global_position - camera.global_position
		# Cap close-up projected size using depth along the view. Let perspective shrink farther labels.
		var label_scale := clampf(-camera.global_basis.z.dot(offset) / LOOT_LABEL_READABLE_DEPTH, 0.01, 1.0) \
			if _kind == "loot" else clampf(offset.length() / 1.4, 0.28, 1.0)
		var pixels := _label_size * label_scale
		if not is_equal_approx(_label.pixel_size, pixels):
			_label.pixel_size = pixels
			if _loot_back != null:
				_loot_back.scale = Vector3(label_scale, label_scale, 1.0)
	if _kind == "loot":
		if is_instance_valid(_fall):
			_fall_left -= delta
			if _fall_left <= 0.0:
				_body.reparent(_fall.get_parent(), false)
				_body.transform = _settled_body
				_fall.queue_free()
				_fall = null
	elif _kind == "chest":
		_lid.rotation.x = lerpf(_lid.rotation.x, _lid_angle, minf(1.0, delta * 12.0))


func _set_up_ground_loot() -> void:
	# Keep the model's randomized facing stable when a loot record is restored.
	var identity := String(payload.get("id_on_ground", text))
	_body.rotation.y = float(posmod(identity.hash(), 360)) * PI / 180.0
	var bounds := _model_bounds(_body, Transform3D.IDENTITY)
	if bounds.has_volume():
		_body.position.y -= bounds.position.y
		_loot_item_aim.y = maxf(0.06, bounds.size.y * 0.50)
	for mesh: MeshInstance3D in _body.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null:
			_loot_meshes.append(mesh)
	_label.position.y = clampf(float(payload.get("label_height", 0.39)), 0.29, 0.69)
	_label.font_size = 36
	_label.outline_size = 0
	_label.render_priority = 1
	_label.visibility_range_end = LOOT_LABEL_RANGE
	_label.double_sided = false
	var font: Font = _label.font if _label.font != null else ThemeDB.fallback_font
	var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _label.font_size)
	_loot_back_size = Vector2(measured.x + 24.0, font.get_height(_label.font_size) + 10.0) * _label_size
	var quad := QuadMesh.new()
	quad.size = _loot_back_size
	_loot_ink = StandardMaterial3D.new()
	_loot_ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_loot_ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_loot_ink.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_loot_ink.billboard_keep_scale = true
	_loot_ink.albedo_color = LOOT_LABEL_NORMAL
	_loot_ink.render_priority = -1
	_loot_back = MeshInstance3D.new()
	_loot_back.name = "LootLabelBackground"
	_loot_back.mesh = quad
	_loot_back.material_override = _loot_ink
	_loot_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_loot_back.visibility_range_end = _label.visibility_range_end
	_label.add_child(_loot_back)
	margin = 0.31
	if _legendary:
		_add_legendary_beam()


func _add_legendary_beam() -> void:
	var beam := MeshInstance3D.new()
	beam.name = "LegendaryLootBeam"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.40, 2.2)
	beam.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = LOOT_BEAM
	material.set_shader_parameter(&"beam_color", tint)
	beam.material_override = material
	beam.position.y = 1.12
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visibility_range_end = 19.0
	# The beam's shader faces the camera horizontally, so give it bounds on both axes.
	beam.custom_aabb = AABB(Vector3(-0.26, -1.12, -0.26), Vector3(0.52, 2.24, 0.52))
	add_child(beam)


func loot_aim_points() -> PackedVector3Array:
	return PackedVector3Array([_label.position, _loot_item_aim]) if _kind == "loot" \
		else PackedVector3Array([interaction_point])


func set_targeted(active: bool) -> void:
	if _loot_ink == null:
		return
	_loot_ink.albedo_color = LOOT_LABEL_TARGETED if active else LOOT_LABEL_NORMAL
	if active and _loot_outline == null:
		_loot_outline = ShaderMaterial.new()
		_loot_outline.shader = LOOT_OUTLINE
		_loot_outline.set_shader_parameter(&"edge_color", tint.lerp(Color("#fcd39c"), 0.36))
	for mesh: MeshInstance3D in _loot_meshes:
		mesh.material_overlay = _loot_outline if active else null


## New drops fall and bounce on the world, then settle at their saved ground anchor.
func animate_drop() -> void:
	if _kind != "loot" or not is_inside_tree() or is_instance_valid(_fall):
		return
	var bounds := _model_bounds(_body, _body.transform.affine_inverse())
	if not bounds.has_volume():
		return
	_settled_body = _body.transform
	_fall = RigidBody3D.new()
	_fall.name = "LootLanding"
	_fall.collision_layer = 0
	_fall.collision_mask = 1
	_fall.continuous_cd = true
	_fall.axis_lock_linear_x = true
	_fall.axis_lock_linear_z = true
	_fall.lock_rotation = true
	_fall.gravity_scale = 1.16
	_fall.position = _body.position + Vector3.UP * DROP_HEIGHT
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.22
	_fall.physics_material_override = bounce
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3.ONE * 0.014)
	collider.shape = box
	collider.transform = Transform3D(_body.basis, _body.basis * bounds.get_center())
	_fall.add_child(collider)
	_body.get_parent().add_child(_fall)
	_body.reparent(_fall, false)
	_body.position = Vector3.ZERO
	_fall_left = DROP_SECONDS


func opened(animate := true) -> void:
	payload.opened = true
	_lid_angle = -1.17
	if not animate:
		_lid.rotation.x = _lid_angle
	_label.hide()


func pick_available() -> bool:
	return not ((_kind == "chest" and bool(payload.get("opened", false)))
		or (_kind == "loot" and payload.get("category") == "gold"))


func _loot_model() -> Node3D:
	match String(payload.get("category", "")):
		"item":
			text = Items.visible_name(payload.item)
			tint = Items.item_color(payload.item.rarity)
			_legendary = payload.item.rarity == "legendary"
			match String(payload.item.get("supply_kind", "")):
				"material":
					return _material_pickup(String(payload.item.get("supply_id", "")))
				"treasure_key", "route_key":
					tint = Color("#efbe63")
					return TREASURE_KEY.instantiate()
				"unveiling_scroll":
					return UNVEILING_SCROLL.instantiate()
				CardItems.KIND:
					return _card_pickup(payload.item)
			return _gear_pickup(String(payload.item.type), String(payload.item.get("base_id", "")))
		"key":
			text = "Treasure Key"
			tint = Color("#efbe63")
			return TREASURE_KEY.instantiate()
		"card":
			return _card_pickup(payload.get("item", {}))
		"gold":
			text = "%d Gold" % int(payload.amount)
			tint = Color("#dba957")
			return COINS.instantiate()
		_:
			var material_id := String(payload.get("id", ""))
			text = Items.material_name(material_id)
			tint = Color("#cbad93")
			return _material_pickup(material_id)


func _card_pickup(item: Dictionary) -> Node3D:
	var model := CARD_LOOT.instantiate() as Node3D
	var stock := model.get_node("Body/CardStock") as Node3D
	stock.rotation.x = -PI * 0.5
	if not CardItems.is_card(item) or item.get("unidentified", true):
		text = CardItems.UNIDENTIFIED_NAME
		tint = Items.item_color("normal")
		_legendary = false
		return model
	text = "%s Card" % item.name
	tint = Items.item_color(item.rarity)
	_legendary = item.rarity == "legendary"
	var illustration := model.get_node("Body/CardStock/Illustration") as MeshInstance3D
	var material := illustration.material_override.duplicate() as StandardMaterial3D
	var atlas := CardFace.art_texture(int(item.art))
	var atlas_size := atlas.atlas.get_size()
	var ratio := atlas.region.size / atlas_size
	var offset := atlas.region.position / atlas_size
	material.albedo_texture = atlas.atlas
	material.uv1_scale = Vector3(ratio.x, ratio.y, 1.0)
	material.uv1_offset = Vector3(offset.x, offset.y, 0.0)
	illustration.material_override = material
	return model


func _material_pickup(material_id: String) -> Node3D:
	var model := MONSTER_PART.instantiate() as Node3D
	var variants := model.get_node("Body/MaterialVariants")
	var part := variants.find_child(material_id.to_pascal_case(), true, false)
	if part == null:
		part = variants.find_child("BoneShard", true, false)
	if part != null:
		for unused in part.get_parent().get_children():
			if unused != part:
				unused.free()
	return model


func _gear_pickup(type: String, base_id: String) -> Node3D:
	var is_long_weapon := type in ["dagger_1h", "sword_1h", "sword_2h", "axe_1h", "axe_2h", "mace_1h", "mace_2h", "staff"]
	var equipment := type in ["helm", "chest", "gloves", "boots", "ring", "amulet", "belt"]
	var held := is_long_weapon or type in ["shield", "focus", "orb"]
	var appearance := (WEAPON_LOOT if is_long_weapon else GEAR_LOOT).instantiate() as Node3D
	if not equipment and not held:
		_tint_materials(appearance, &"loot_rarity", tint)
		return appearance
	var directory := "res://assets/models/equipment/" if equipment else "res://player/weapons/models/"
	var path := directory + type + ".glb"
	var scene := HeldModels.scene_for(base_id, type)
	var has_base_model := scene != null
	if scene == null and ResourceLoader.exists(path, "PackedScene"):
		scene = ResourceLoader.load(path, "PackedScene") as PackedScene
	if scene == null:
		_tint_materials(appearance, &"loot_rarity", tint)
		return appearance
	var model := scene.instantiate() as Node3D
	for piece: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if piece.skin != null or "forearm" in piece.name.to_lower():
			piece.free()
	var geometry := _model_bounds(model, Transform3D.IDENTITY)
	var longest := maxf(geometry.size.x, maxf(geometry.size.y, geometry.size.z))
	if longest <= 0.0:
		model.free()
		_tint_materials(appearance, &"loot_rarity", tint)
		return appearance
	var extent := 0.38 if type == "dagger_1h" else (0.71 if is_long_weapon else 0.37)
	if type.ends_with("_2h") or type == "staff":
		extent = 0.94
	elif type in ["amulet", "ring"]:
		extent = 0.19
	var angle := -84.0 if is_long_weapon else (-80.0 if type == "shield" else -27.0)
	if has_base_model and type == "shield":
		angle = 80.0
	# A single pickup scale preserves the relative proportions between authored bases.
	var scale_factor := 0.62 if has_base_model else (extent / longest)
	var pickup_basis := Basis(Vector3.RIGHT, deg_to_rad(angle)).scaled(Vector3.ONE * scale_factor)
	var posed := Transform3D(pickup_basis, Vector3.ZERO) * geometry
	var center := posed.get_center()
	var body := appearance.get_node("Body") as Node3D
	for placeholder in body.get_children():
		placeholder.free()
	var mount := Node3D.new()
	mount.name = "EquipmentModel"
	mount.transform = Transform3D(pickup_basis, Vector3(-center.x, 0.0, -center.z))
	body.add_child(mount)
	mount.add_child(model)
	return appearance


func _model_bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform_in_model := parent_transform * node.transform
	var bounds := AABB()
	if node is MeshInstance3D:
		bounds = transform_in_model * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _model_bounds(child, transform_in_model)
			if child_bounds.has_volume():
				bounds = bounds.merge(child_bounds) if bounds.has_volume() else child_bounds
	return bounds


func _configure_coffer(model: Node3D) -> void:
	var locked := bool(payload.locked)
	var guarded := bool(payload.get("guarded", false))
	text = "Warded Reliquary" if guarded else ("Locked Coffer" if locked else "Treasure Coffer")
	tint = Color("#d5b0df") if guarded else (Color("#e5ba72") if locked else Color("#e4c8a2"))
	if int(payload.get("trial_waves", 0)) > 1:
		text = "Trial Coffer"
		tint = Color("#ec9476")
	elif payload.get("challenge_type", "") == "submerged":
		text = "Drowned Coffer"
		for surface: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for index in surface.mesh.get_surface_count():
				var material := surface.get_active_material(index) as StandardMaterial3D
				if material != null:
					var stained := material.duplicate() as StandardMaterial3D
					stained.albedo_color *= Color("#8bac93")
					surface.set_surface_override_material(index, stained)
	margin = 0.88
	_lid = model.get_node("Lid")
	_lid.get_node("Keyhole").visible = locked or guarded
	if guarded or locked:
		var binding := Color("#d0accf") if guarded else Color("#d7b38a")
		for piece: MeshInstance3D in model.find_children("BindingIron*", "MeshInstance3D", true, false):
			var iron := piece.get_active_material(0) as StandardMaterial3D
			if iron == null:
				continue
			var variant := iron.duplicate() as StandardMaterial3D
			variant.albedo_color = binding
			piece.material_override = variant


func _tint_materials(model: Node3D, group: StringName, color: Color) -> void:
	var tinted: Dictionary[Material, StandardMaterial3D] = {}
	for piece: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var original := piece.material_override as StandardMaterial3D
		if not piece.is_in_group(group) or original == null:
			continue
		if not tinted.has(original):
			var material := original.duplicate() as StandardMaterial3D
			material.albedo_color = color
			if material.emission_enabled:
				material.emission = color
			tinted[original] = material
		piece.material_override = tinted[original]
