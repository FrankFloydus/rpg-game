extends Control
## Draws the discovered dungeon on the gameplay HUD with no input or focus ownership.

const Fog := preload("res://ui/dungeon_map_fog.gd")
const FRAGMENT_FEATHER := 1.0 / Fog.WALL_SAMPLES
const ENEMY := Color("#ec8b72")
const TRAIL := Color(0.93, 0.69, 0.42, 0.72)
const STAIR_UP := Color("#a8d0c8")
const STAIR_DOWN := Color("#e7b981")
const LANDMARK_STYLES := {
	"locked_coffer": {"label": "Locked coffer", "color": Color("#e0bd79")},
	"route_gate": {"label": "Gate", "color": Color("#b2bfc9")},
	"trial_coffer": {"label": "Trial coffer", "color": Color("#ec9a72")},
	"blood_altar": {"label": "Blood Altar", "color": Color("#db8f94")},
}

## Font for the overlay's floor caption. An empty value uses the HUD's theme font.
@export var caption_font: Font
## Center of the explored map as a fraction of the gameplay viewport.
@export var map_center := Vector2(0.5, 0.575)
## Fraction of the gameplay viewport that the explored map can occupy.
@export var viewport_fraction := Vector2(0.56, 0.44)
## Tint of explored walls. Alpha controls how much of the world shows through.
@export var wall_tint := Color(0.84, 0.86, 0.89, 0.82)
## Shadow behind the map's lines, marks, and captions to separate them from the world.
@export var outline_tint := Color(0.025, 0.028, 0.034, 0.83)
## Tint of the floor name above the map.
@export var caption_tint := Color(0.894, 0.906, 0.922, 0.94)
## Tint of the arrow showing the player and facing direction.
@export var player_tint := Color("#e4e7eb")

var _wall_fragments: Array[PackedVector2Array] = []
var _wall_colors: Array[PackedColorArray] = []
var _wall_shadows: Array[PackedColorArray] = []
var _wall_bounds := Rect2()
var _fog_revision := -1
var _floor: Node3D
var _player: Node3D
var _cell_size := 1.0
var _player_at := Vector2.ZERO
var _heading := Vector2.UP
var _targets: Array[Vector2i] = []
var _trail: Array[Vector2i] = []
var _stairs: Dictionary = {}
var _landmarks: Array[Dictionary] = []
var _legend_types: Array[String] = []
var _caption := ""


func _ready() -> void:
	visibility_changed.connect(_update_processing)
	resized.connect(queue_redraw)
	accessibility_name = "Dungeon map"
	_update_processing()


func update_projection(fog: Fog, targets: Array[Vector2i],
		caption: String, trail: Array[Vector2i], stairs: Dictionary, player: Node3D,
		dungeon_floor: Node3D, cell_size: float) -> void:
	if not is_instance_valid(_floor) or _floor != dungeon_floor or fog.revision != _fog_revision:
		_rebuild_fragments(fog.coverage)
		_fog_revision = fog.revision
	_floor = dungeon_floor
	_player = player
	_cell_size = cell_size
	_caption = caption
	_targets = targets
	_trail = trail
	_stairs = stairs
	_landmarks = fog.landmarks
	_update_legend()
	_track_player()
	queue_redraw()


func _update_legend() -> void:
	var entries: Array[String] = []
	for kind: String in LANDMARK_STYLES:
		if _landmarks.any(func(point: Dictionary) -> bool: return point.kind == kind):
			entries.append(kind)
	if _legend_types != entries:
		_legend_types = entries
		var names := PackedStringArray()
		for kind in _legend_types:
			names.append(LANDMARK_STYLES[kind].label)
		accessibility_description = ", ".join(names)


func has_route() -> bool:
	return _trail.size() > 1


func _update_processing() -> void:
	set_process(is_visible_in_tree())


func _process(_delta: float) -> void:
	if _track_player():
		queue_redraw()


func _track_player() -> bool:
	if not is_instance_valid(_player) or not is_instance_valid(_floor) or not _floor.is_inside_tree():
		return false
	var pose := _floor.global_transform.affine_inverse() * _player.get_global_transform_interpolated()
	var map_position := Vector2(pose.origin.x, pose.origin.z) / _cell_size
	var heading := Vector2(-pose.basis.z.x, -pose.basis.z.z).normalized()
	if map_position.is_equal_approx(_player_at) and heading.is_equal_approx(_heading):
		return false
	_player_at = map_position
	_heading = heading
	return true


func _rebuild_fragments(coverage: Dictionary[Vector3i, int]) -> void:
	_wall_fragments.clear()
	_wall_colors.clear()
	_wall_shadows.clear()
	_wall_bounds = Rect2()
	var segments := PackedVector2Array()
	var joins: Dictionary[Vector2, int] = {}
	for wall: Vector3i in coverage:
		var origin := Fog.wall_start(wall)
		var direction := Fog.wall_direction(wall)
		var interval_start := -1
		for sample in Fog.WALL_SAMPLES + 1:
			var sample_seen := (coverage[wall] & (1 << sample)) != 0
			if sample_seen and interval_start < 0:
				interval_start = sample
			elif not sample_seen and interval_start >= 0:
				var a := origin + direction * (float(interval_start) / Fog.WALL_SAMPLES)
				var b := origin + direction * (float(sample) / Fog.WALL_SAMPLES)
				if segments.is_empty():
					_wall_bounds = Rect2(a, Vector2.ZERO)
				_wall_bounds = _wall_bounds.expand(a).expand(b)
				segments.append(a)
				segments.append(b)
				joins[a] = int(joins.get(a, 0)) + 1
				joins[b] = int(joins.get(b, 0)) + 1
				interval_start = -1
	for index in range(0, segments.size(), 2):
		var a := segments[index]
		var b := segments[index + 1]
		var inset := (b - a).normalized() * minf(FRAGMENT_FEATHER, a.distance_to(b) * 0.4)
		_wall_fragments.append(PackedVector2Array([a, a + inset, b - inset, b]))
		_wall_colors.append(_feather(wall_tint, joins[a] > 1, joins[b] > 1))
		_wall_shadows.append(_feather(outline_tint, joins[a] > 1, joins[b] > 1))


func _feather(tint: Color, start_joined: bool, end_joined: bool) -> PackedColorArray:
	var transparent := Color(tint, 0.0)
	return PackedColorArray([tint if start_joined else transparent, tint, tint,
		tint if end_joined else transparent])


func _map_projection() -> Dictionary:
	var explored := _wall_bounds.expand(_player_at) if not _wall_fragments.is_empty() else Rect2(_player_at, Vector2.ZERO)
	for landmark: Dictionary in _landmarks:
		explored = explored.expand(landmark.at)
	for tile: Vector2i in _stairs:
		explored = explored.expand(Vector2(tile))
	for tile: Vector2i in _trail:
		explored = explored.expand(Vector2(tile))
	var center := size * map_center
	var footprint := size * viewport_fraction
	var viewport := Rect2(center - footprint * 0.5, footprint)
	# Inset the fit to leave space for full-size landmark icons at the map edges.
	var fitted := (footprint - Vector2.ONE * 24.0).max(Vector2.ONE) / explored.size.max(Vector2.ONE)
	var spacing := minf(minf(fitted.x, fitted.y), clampf(minf(size.x, size.y) * 0.016, 8.0, 14.0))
	var origin := center - explored.get_center() * spacing
	var drawn := Rect2(origin + explored.position * spacing, explored.size * spacing)
	return {"viewport": viewport, "spacing": spacing, "origin": origin, "drawn": drawn}


func _draw() -> void:
	if not is_instance_valid(_floor):
		return
	var projection := _map_projection()
	var viewport_bounds: Rect2 = projection.viewport
	var drawn: Rect2 = projection.drawn
	var spacing: float = projection.spacing
	var origin: Vector2 = projection.origin
	_draw_terrain(Rect2((viewport_bounds.position - origin) / spacing, viewport_bounds.size / spacing),
		origin, spacing)
	for index in range(1, _trail.size()):
		var from := origin + Vector2(_trail[index - 1]) * spacing
		var to := origin + Vector2(_trail[index]) * spacing
		if not viewport_bounds.intersects(Rect2(from, to - from).abs().grow(2.0)):
			continue
		draw_dashed_line(from, to, outline_tint, 3.2, 5.0, true, true)
		draw_dashed_line(from, to, TRAIL, 1.8, 5.0, true, true)
	for tile in _targets:
		var point := origin + Vector2(tile) * spacing
		if viewport_bounds.has_point(point):
			_diamond(point, clampf(spacing * 0.21, 2.4, 4.0), ENEMY)
	for tile: Vector2i in _stairs:
		var point := origin + Vector2(tile) * spacing
		if viewport_bounds.has_point(point):
			_draw_stair(point, int(_stairs[tile]))
	for landmark in _landmarks:
		var point := origin + Vector2(landmark.at) * spacing
		if viewport_bounds.has_point(point):
			_draw_landmark(point, String(landmark.kind))
	_draw_player(origin + _player_at * spacing)
	var caption_y := drawn.position.y - 15.0
	var caption_center := size.x * map_center.x
	_draw_caption(_caption, Vector2(caption_center, caption_y), 16, caption_tint, caption_font)
	_draw_legend(Vector2(caption_center, drawn.end.y + 19.0))
	if has_route():
		var route_y := drawn.end.y + (16.0 if _legend_types.is_empty() else 41.0)
		_draw_caption("Route to nearest remaining enemy", Vector2(caption_center, route_y),
			13, TRAIL)


func _draw_terrain(view: Rect2, origin: Vector2, spacing: float) -> void:
	draw_set_transform(origin, 0.0, Vector2.ONE * spacing)
	for index in _wall_fragments.size():
		var points := _wall_fragments[index]
		if not view.intersects(Rect2(points[0], points[3] - points[0]).abs().grow(0.05)):
			continue
		draw_polyline_colors(points, _wall_shadows[index], 2.65 / spacing, true)
		draw_polyline_colors(points, _wall_colors[index], 1.15 / spacing, true)
	draw_set_transform(Vector2.ZERO)


func _diamond(at: Vector2, radius: float, color: Color) -> void:
	var shape := PackedVector2Array([
		at + Vector2(0.0, -radius), at + Vector2(radius, 0.0),
		at + Vector2(0.0, radius), at + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(shape, color)
	shape.append(shape[0])
	draw_polyline(shape, outline_tint, 1.25, true)


func _draw_stair(at: Vector2, direction: int) -> void:
	var up := direction < 0
	var color := STAIR_UP if up else STAIR_DOWN
	_diamond(at, 8.0, outline_tint)
	var offset := Vector2.UP if up else Vector2.DOWN
	draw_polyline(PackedVector2Array([at + Vector2(-3.3, 0.0), at + offset * 3.8,
		at + Vector2(3.3, 0.0)]), color, 1.5, true)
	draw_polyline(PackedVector2Array([at + Vector2(-3.3, 0.0) - offset * 3.2, at + offset * 0.6,
		at + Vector2(3.3, 0.0) - offset * 3.2]), color, 1.2, true)


func _draw_landmark(at: Vector2, kind: String) -> void:
	if not LANDMARK_STYLES.has(kind):
		return
	var pigment: Color = LANDMARK_STYLES[kind].color
	draw_circle(at, 8.5, outline_tint, true, -1.0, true)
	draw_arc(at, 8.25, 0.0, TAU, 24, Color(pigment, 0.58), 0.9, true)
	match kind:
		"locked_coffer":
			draw_rect(Rect2(at + Vector2(-4.8, -1.5), Vector2(9.6, 5.0)), pigment, false, 1.15)
			_landmark_stroke(at, [Vector2(-4.8, -1.5), Vector2(-3.3, -3.8),
				Vector2(3.3, -3.8), Vector2(4.8, -1.5)], pigment)
			draw_circle(at + Vector2(0.0, 0.3), 1.0, pigment, true, -1.0, true)
		"route_gate":
			_landmark_stroke(at, [Vector2(-4.5, 4.1), Vector2(-4.5, -1.7), Vector2(-2.3, -4.1),
				Vector2(2.3, -4.1), Vector2(4.5, -1.7), Vector2(4.5, 4.1)], pigment)
			for column: float in [-2.2, 0.0, 2.2]:
				draw_line(at + Vector2(column, -2.1), at + Vector2(column, 3.8), pigment, 1.05, true)
		"trial_coffer":
			_landmark_stroke(at, [Vector2(-4.2, -3.5), Vector2(4.2, 3.4)], pigment, 1.35)
			_landmark_stroke(at, [Vector2(4.2, -3.5), Vector2(-4.2, 3.4)], pigment, 1.35)
			draw_line(at + Vector2(-4.3, 0.8), at + Vector2(-1.4, 4.1), pigment, 1.05, true)
			draw_line(at + Vector2(4.3, 0.8), at + Vector2(1.4, 4.1), pigment, 1.05, true)
		"blood_altar":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -5.0), at + Vector2(2.6, -0.7),
				at + Vector2(1.4, 1.4), at + Vector2(-1.4, 1.4), at + Vector2(-2.6, -0.7)]), pigment)
			_landmark_stroke(at, [Vector2(-4.6, 2.3), Vector2(-2.9, 4.0),
				Vector2(2.9, 4.0), Vector2(4.6, 2.3)], pigment)


func _landmark_stroke(at: Vector2, offsets: Array[Vector2], color: Color, width := 1.15) -> void:
	var points := PackedVector2Array()
	for offset in offsets:
		points.append(at + offset)
	draw_polyline(points, color, width, true)


func _draw_legend(at: Vector2) -> void:
	const FONT_SIZE := 13
	const LABEL_OFFSET := 13.0
	const GAP := 21.0
	var font := get_theme_default_font()
	var width := 0.0
	var lengths: Array[float] = []
	for kind in _legend_types:
		var length := font.get_string_size(LANDMARK_STYLES[kind].label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
		lengths.append(length)
		width += LABEL_OFFSET + length + GAP
	var left := at.x - (width - GAP) * 0.5
	for index in _legend_types.size():
		var kind := _legend_types[index]
		var style: Dictionary = LANDMARK_STYLES[kind]
		_draw_landmark(Vector2(left, at.y), kind)
		_draw_caption(style.label, Vector2(left + LABEL_OFFSET + lengths[index] * 0.5, at.y + 4.0),
			FONT_SIZE, style.color, font)
		left += LABEL_OFFSET + lengths[index] + GAP


func _draw_player(at: Vector2) -> void:
	var side := _heading.orthogonal()
	var nose := at + _heading * 8.4
	var pocket := at - _heading * 3.0
	var tail := at - _heading * 5.4
	var kite := PackedVector2Array([nose, tail + side * 4.8, pocket, tail - side * 4.8])
	draw_colored_polygon(kite, player_tint)
	kite.append(nose)
	draw_polyline(kite, outline_tint, 1.3, true)


func _draw_caption(caption: String, at: Vector2, font_size: int, color: Color, font: Font = null) -> void:
	if caption.is_empty():
		return
	if font == null:
		font = get_theme_default_font()
	var left := at - Vector2(font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x * 0.5, 0.0)
	draw_string_outline(font, left, caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, outline_tint)
	draw_string(font, left, caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

