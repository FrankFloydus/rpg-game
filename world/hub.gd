extends Node3D
## Static cloister geometry is authored in hub.tscn. This script handles interaction and portal state.

const NAMEPLATE_SCREEN_WIDTH := 192.0
const APPROACH_FADE_SPEED := 8.0

const STATIONS := {
	"vendor": ^"Vendor/Interaction",
	"blacksmith": ^"Blacksmith/Interaction",
	"altar": ^"PortalAltar/Interaction",
	"close_dungeon": ^"CloseDungeon/Interaction",
	"training_portal": ^"TrainingPortal/Interaction",
	"stash": ^"Stash/Interaction",
}

var spawn_position: Vector3:
	get:
		return $PlayerSpawn.position

var _dungeon_active := false
var _dungeon_cleared := false
var _nameplate_widths: Dictionary[String, float] = {}
var _nameplate_scales: Dictionary[String, float] = {}

@onready var _nameplates: Dictionary[String, Label3D] = {
	"vendor": $Vendor/Label3D1,
	"blacksmith": $Blacksmith/Label3D1,
	"altar": $PortalAltar/Label3D1,
	"training_portal": $TrainingPortal/Label3D1,
	"close_dungeon": %CloseDungeonLabel,
	"stash": $Stash/Nameplate,
}
@onready var _close_label: Label3D = %CloseDungeonLabel
@onready var _seal_glow: MeshInstance3D = %SealGlow.get_node("SealLens")


func _ready() -> void:
	for id: String in _nameplates:
		var label := _nameplates[id]
		var font := label.font if label.font != null else ThemeDB.fallback_font
		var width := 0.0
		for line in label.text.split("\n"):
			width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x)
		_nameplate_widths[id] = width + 2.0 * label.outline_size
		_nameplate_scales[id] = label.pixel_size
	var imported := _seal_glow.get_active_material(0) as StandardMaterial3D
	if imported != null:
		_seal_glow.material_override = imported.duplicate()
	_update_expedition_display()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var aimed_at := active_interaction(camera.global_position, -camera.global_basis.z)
	var merchant_focused := aimed_at in ["vendor", "blacksmith"]
	for id: String in _nameplates:
		var label := _nameplates[id]
		var target_alpha := 0.0 if merchant_focused and id != aimed_at else 1.0
		var alpha := move_toward(label.modulate.a, target_alpha, delta * APPROACH_FADE_SPEED)
		if not is_equal_approx(label.modulate.a, alpha):
			label.modulate.a = alpha
			label.outline_modulate.a = alpha
		var center := label.global_position
		if not label.visible or camera.is_position_behind(center):
			continue
		var origin := camera.unproject_position(center).x
		var nearby := camera.unproject_position(center + camera.global_basis.x).x
		var projected_width := absf(nearby - origin) * _nameplate_widths[id]
		var label_pixel_size := minf(_nameplate_scales[id], NAMEPLATE_SCREEN_WIDTH / maxf(projected_width, 1.0))
		if not is_equal_approx(label_pixel_size, label.pixel_size):
			label.pixel_size = label_pixel_size


func interaction_position(id: String) -> Vector3:
	var marker_path: NodePath = STATIONS.get(id, NodePath())
	if marker_path.is_empty():
		return Vector3.ZERO
	var marker := get_node(marker_path) as Marker3D
	if is_inside_tree():
		return marker.global_position
	return marker.get_parent_node_3d().transform * marker.position


func training_arrival_position() -> Vector3:
	var destination := interaction_position("training_portal")
	destination.y = spawn_position.y
	return destination + ($TrainingPortal/TrainingGroundPortal as Node3D).basis.z * 3.0


func active_interaction(origin: Vector3, direction: Vector3, max_distance := 4.0) -> String:
	var best_id := ""
	var best_score := 0.16
	for id: String in STATIONS:
		var displacement := interaction_position(id) - origin
		var distance := displacement.length()
		if distance <= 0.01 or distance > max_distance:
			continue
		var aim := direction.dot(displacement / distance)
		var radius := 1.12 if id in ["altar", "training_portal"] else 0.78
		var projected := displacement.dot(direction)
		if aim <= 0.1 or (displacement - direction * projected).length() > radius:
			continue
		var score := aim - distance * 0.07
		if score > best_score:
			best_id = id
			best_score = score
	return best_id


func altar_overlaps(player_position: Vector3) -> bool:
	var center: Vector3 = $PortalAltar/OverlapCenter.global_position
	return absf(player_position.x - center.x) < 1.4 and absf(player_position.z - center.z) < 0.85


func set_dungeon_state(active: bool, cleared := false) -> void:
	_dungeon_active = active
	_dungeon_cleared = cleared
	_update_expedition_display()


func _update_expedition_display() -> void:
	if not is_instance_valid(_close_label):
		return
	_close_label.modulate = Color("#e2bbc0") if _dungeon_active else Color("#a59c92")
	var seal := _seal_glow.material_override as StandardMaterial3D
	if seal != null:
		seal.emission_enabled = true
		seal.emission = Color("#db9248") if _dungeon_cleared else Color("#b64540")
		seal.albedo_color = Color("#a55741") if _dungeon_active else Color("#544842")
		seal.emission_energy_multiplier = 1.2 if _dungeon_active else 0.04
