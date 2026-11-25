@tool
extends Control

const MenuFrame := preload("res://ui/menu_frame.gd")

var key := ""
var tint := MenuFrame.TEXT
var texture: Texture2D

func _draw() -> void:
	if texture != null:
		var texture_size := texture.get_size()
		var interior := Rect2(Vector2.ONE, size - Vector2.ONE * 2.0)
		var fitted_size := texture_size * minf(interior.size.x / texture_size.x, interior.size.y / texture_size.y)
		draw_rect(Rect2(Vector2.ZERO, size), MenuFrame.WELL)
		draw_texture_rect(texture, Rect2((size - fitted_size) * 0.5, fitted_size), false)
		draw_rect(Rect2(Vector2.ZERO, size), MenuFrame.LINE, false, 1.0)
		return
	draw_set_transform(size*0.5, 0.0, Vector2.ONE*minf(size.x, size.y)/28.0)
	match key:
		"cut":
			_path([Vector2(-6, 8), Vector2(5, -10), Vector2(8, -10), Vector2(7, -6), Vector2(-3, 9)])
			_line(Vector2(-8, 4), Vector2(-1, 8))
		"sweep":
			draw_arc(Vector2(-2, 4), 10, -2.7, 0.05, 19, tint, 1.6, true)
			_path([Vector2(2, 3), Vector2(9, 6), Vector2(10, -1)])
		"pounce", "quick":
			_path([Vector2(-8, -6), Vector2(-1, 0), Vector2(-8, 6)])
			_path([Vector2(1, -6), Vector2(8, 0), Vector2(1, 6)])
			if key == "pounce":
				_line(Vector2(-10, 10), Vector2(8, 10))
		"slam":
			_path([Vector2(0, -9), Vector2(0, 2), Vector2(-4, -2), Vector2(0, 2), Vector2(4, -2)])
			_path([Vector2(-10, 8), Vector2(-5, 5), Vector2(0, 8), Vector2(5, 5), Vector2(10, 8)])
		"arrow":
			_arrow(Vector2(-7, 7), Vector2(8, -8))
			_line(Vector2(-6, 6), Vector2(-8, 1))
		"doublet":
			_arrow(Vector2(-9, 3), Vector2(3, -9))
			_arrow(Vector2(-3, 9), Vector2(9, -3))
		"fan":
			_arrow(Vector2(0, 8), Vector2(-9, -3))
			_arrow(Vector2(0, 8), Vector2(0, -9))
			_arrow(Vector2(0, 8), Vector2(9, -3))
		"cobweb":
			var inner: Array[Vector2] = []
			var outer: Array[Vector2] = []
			for index in 8:
				var spoke := Vector2.from_angle(TAU * float(index) / 8.0)
				_line(Vector2.ZERO, spoke * 10.5)
				inner.append(spoke * 4.0)
				outer.append(spoke * 8.0)
			inner.append(inner[0])
			outer.append(outer[0])
			_path(inner)
			_path(outer)
		"cocoon":
			_path([Vector2(0, -9), Vector2(5, -7), Vector2(8, -2), Vector2(8, 4),
				Vector2(4, 9), Vector2(0, 10), Vector2(-5, 8), Vector2(-8, 4), Vector2(-8, -1),
				Vector2(-5, -6), Vector2(0, -9), Vector2(2, -11)])
			_path([Vector2(-6, -4), Vector2(-1, -3), Vector2(5, -5)])
			_path([Vector2(-8, 0), Vector2(-2, 2), Vector2(8, -1)])
			_path([Vector2(-7, 5), Vector2(0, 7), Vector2(7, 5)])
		"briar_guard":
			_path([Vector2(-11, 6), Vector2(-8, 2), Vector2(-10, -6), Vector2(-5, -1),
					Vector2(-3, -10), Vector2(0, -3), Vector2(4, -8), Vector2(5, -1),
					Vector2(10, -4), Vector2(8, 3), Vector2(11, 6), Vector2(4, 8), Vector2(-4, 8), Vector2(-11, 6)])
			_line(Vector2(-6, 4), Vector2(6, 4))
		"bolt", "shocked":
			_path([Vector2(2, -10), Vector2(-7, 0), Vector2(-1, 0), Vector2(-3, 10),
				Vector2(7, -1), Vector2(1, -1), Vector2(2, -10)])
		"armored":
			_path([Vector2(-8, -7), Vector2(0, -9), Vector2(8, -7), Vector2(6, 4),
				Vector2(0, 9), Vector2(-6, 4), Vector2(-8, -7)])
			_line(Vector2(0, -5), Vector2(0, 5))
		"draining", "bleed":
			_droplet()
			if key == "draining":
				_path([Vector2(-3, 3), Vector2(0, 6), Vector2(3, 3)])
			else:
				_line(Vector2(-3, 3), Vector2(-2, 5))
		"enraged", "incendiary":
			_path([Vector2(-7, 7), Vector2(-8, 2), Vector2(-4, -4), Vector2(-2, -2),
				Vector2(2, -10), Vector2(7, -2), Vector2(8, 4), Vector2(4, 8), Vector2(-7, 7)])
			if key == "enraged":
				_line(Vector2(-4, 2), Vector2(-1, 5))
				_line(Vector2(2, 5), Vector2(5, 2))
		"frozen", "chilled":
			for index in 3:
				var spoke := Vector2.from_angle(PI*float(index)/3.0)
				var wing := Vector2(-spoke.y, spoke.x)
				_line(spoke*-9, spoke*9)
				for end: float in [-1.0, 1.0]:
					_line(spoke*(end*7), spoke*(end*4) + wing*3)
					_line(spoke*(end*7), spoke*(end*4) - wing*3)
		"ravaging":
			for line_index in range(-1, 2):
				var x := float(line_index) * 5.0
				_path([Vector2(x + 3, -8), Vector2(x - 1, 1), Vector2(x - 3, 8)])
		"renewing":
			draw_arc(Vector2.ZERO, 8.5, 0.3, TAU - 0.08, 20, tint, 1.5, true)
			_line(Vector2(0, -4), Vector2(0, 4))
			_line(Vector2(-4, 0), Vector2(4, 0))
		"poisoned", "venomous":
			_droplet()
			draw_circle(Vector2(-2, 3), 1.0, tint, true, -1.0, true)
			draw_circle(Vector2(2, 5), 1.2, tint, true, -1.0, true)
		"volatile":
			for index in 8:
				var spoke := Vector2.from_angle(TAU*float(index)/8.0)
				_line(spoke*4, spoke*10)
			draw_arc(Vector2.ZERO, 2.3, 0, TAU, 16, tint, 1.6, true)
		"vital":
			_path([Vector2(0, 9), Vector2(-8, 2), Vector2(-9, -3), Vector2(-6, -7),
				Vector2(-2, -7), Vector2(0, -4), Vector2(2, -7), Vector2(6, -7),
				Vector2(9, -3), Vector2(8, 2), Vector2(0, 9)])
		"dread":
			_path([Vector2(-10, 0), Vector2(-5, -4), Vector2(0, -6), Vector2(5, -4),
				Vector2(10, 0), Vector2(5, 4), Vector2(0, 6), Vector2(-5, 4), Vector2(-10, 0)])
			draw_circle(Vector2.ZERO, 2.1, tint, true, -1.0, true)
		_:
			_path([Vector2(0, -7), Vector2(7, 0), Vector2(0, 7), Vector2(-7, 0), Vector2(0, -7)])

func _arrow(origin: Vector2, tip: Vector2) -> void:
	var axis := (tip - origin).normalized()
	var wing := Vector2(-axis.y, axis.x)
	_line(origin, tip)
	_line(tip, tip - axis*4 + wing*2.4)
	_line(tip, tip - axis*4 - wing*2.4)

func _droplet() -> void:
	_path([Vector2(0, -10), Vector2(-5, -1), Vector2(-6, 5), Vector2(-2, 8),
		Vector2(2, 8), Vector2(6, 5), Vector2(5, -1), Vector2(0, -10)])

func _line(start: Vector2, finish: Vector2) -> void:
	draw_line(start, finish, tint, 1.55, true)

func _path(points: Array[Vector2]) -> void:
	draw_polyline(PackedVector2Array(points), tint, 1.55, true)
