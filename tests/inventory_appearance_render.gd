extends SceneTree
## Native pixel regression for Workbench alpha and its saved gameplay colors.

const Inventory := preload("res://systems/inventory.gd")
const Items := preload("res://systems/items.gd")
const BoardScene := preload("res://ui/inventory_ui.tscn")
const Appearance := preload("res://ui/inventory_appearance.gd")
const Preview := preload("res://ui/inventory_appearance_preview.gd")
const Frame := preload("res://ui/menu_frame.gd")
const GRID_SAMPLE := Vector2(7, 16)
const PIXEL_TOLERANCE := 2.0 / 255.0

var _stock := Inventory.new()
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Inventory appearance render check needs a native renderer.")
		quit()
		return
	root.size = Vector2i(1280, 800)
	var authored := ResourceLoader.load(Appearance.SOURCE, "", ResourceLoader.CACHE_MODE_IGNORE) as Appearance.Style
	var live := Appearance.LIVE
	_check(live.identified_fill.is_equal_approx(authored.identified_fill) and
		live.unidentified_fill.is_equal_approx(authored.unidentified_fill), "Production appearance starts with the saved colors")
	# Keep this test focused on the fill, beneath any optional leather texture.
	live.grain_opacity = 0.0
	authored.grain_opacity = 0.0
	_stock.add_item(Items.training_weapon_item("oath_blade", "equipped"))
	_stock.add_item(Items.training_weapon_item("oath_blade", "pack"))
	_stock.add_item(Items.training_weapon_item("oath_blade", "stash"))
	_check(_stock.equip_item(&"equipped", "main_hand").is_empty(), "Equipped fixture")
	_check(_stock.quick_stash_transfer("bag", &"stash", "stash:0").is_empty(), "Stash fixture")
	var concealed := Items.training_weapon_item("oath_blade", "unidentified")
	concealed.unidentified = true
	_stock.add_item(concealed)
	var merchandise := Items.training_weapon_item("oath_blade", "merchandise")
	merchandise.unidentified = true
	_stock.set_vendor_items([merchandise])

	var board := BoardScene.instantiate()
	board.bind(_stock)
	root.add_child(board)
	board.open()
	var pack := await _capture()
	_check_pixel(pack, _item_point(board._pack_grid, &"pack"), _expected(authored.identified_fill), "Saved identified pack fill")
	_check_pixel(pack, _item_point(board._pack_grid, &"unidentified"), _expected(authored.unidentified_fill), "Saved unidentified pack fill")
	_check_pixel(pack, _local_point(board._slots.main_hand, Vector2(10, 31)), _expected(authored.identified_fill), "Saved equipped fill")

	board.close()
	board.open("stash")
	_check_pixel(await _capture(), _item_point(board._stash_grid, &"stash"), _expected(authored.identified_fill), "Saved stash fill")
	board.close()
	board.open("vendor")
	_check_pixel(await _capture(), _item_point(board._vendor_grid, &"merchandise"), _expected(authored.unidentified_fill), "Saved merchant fill")
	board.close()
	board.open()
	# Mutate only this process to check opacity endpoints, including complete removal of the fill.
	live.identified_fill = Color(1, 1, 1, 0)
	live.unidentified_fill = Color(0.49, 0.19, 0.12, 0.25)
	var low_alpha := await _capture()
	_check_pixel(low_alpha, _item_point(board._pack_grid, &"pack"), Frame.WELL, "Zero alpha matches the empty grid")
	_check_pixel(low_alpha, _item_point(board._pack_grid, &"unidentified"), _expected(live.unidentified_fill), "25 percent alpha produces a faint tint")
	live.identified_fill = Color(0.26, 0.44, 0.57, 1.0)
	_check_pixel(await _capture(), _item_point(board._pack_grid, &"pack"), live.identified_fill, "Full alpha produces the authored color")
	live.highlight_items = true
	live.identified_hover_fill = Color(0.68, 0.53, 0.78, 0.1)
	live.unidentified_hover_fill = Color(0.72, 0.41, 0.33, 0.15)
	var grid: Control = board._pack_grid
	grid._hover = _stock.get_grid("bag").get_placement(&"pack").origin
	grid.queue_redraw()
	_check_pixel(await _capture(), _item_point(grid, &"pack"), _expected(live.identified_hover_fill), "Identified hover respects its own alpha")
	grid._hover = _stock.get_grid("bag").get_placement(&"unidentified").origin
	grid.queue_redraw()
	_check_pixel(await _capture(), _item_point(grid, &"unidentified"), _expected(live.unidentified_hover_fill), "Unidentified hover respects its own alpha")
	board.close()
	board.free()

	var preview := Preview.new()
	preview.theme = Frame.THEME
	preview.size = Vector2(480, 180)
	root.add_child(preview)
	preview.bind_style(authored)
	var swatches := await _capture()
	_check_pixel(swatches, _local_point(preview, Vector2(37, 12)), _expected(authored.identified_fill), "Workbench preview matches identified pack fill")
	_check_pixel(swatches, _local_point(preview, Vector2(277, 12)), _expected(authored.unidentified_fill), "Workbench preview matches unidentified pack fill")
	print("Inventory appearance render (%s, HDR 2D %s): %d checks, %d failures" %
		[RenderingServer.get_current_rendering_method(), root.use_hdr_2d, _checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expected(tint: Color) -> Color:
	var base := Frame.WELL
	return Color(base.r + (tint.r - base.r) * tint.a, base.g + (tint.g - base.g) * tint.a,
		base.b + (tint.b - base.b) * tint.a)


func _item_point(grid: Control, id: StringName) -> Vector2:
	var origin: Vector2i = _stock.get_grid(grid.endpoint).get_placement(id).origin
	return _local_point(grid, Vector2(origin * grid.cell_size) + GRID_SAMPLE)


func _local_point(control: Control, point: Vector2) -> Vector2:
	return control.get_global_transform_with_canvas() * point


func _capture() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _check_pixel(image: Image, point: Vector2, expected: Color, caption: String) -> void:
	var image_point := Vector2i(point * Vector2(image.get_size()) / root.get_visible_rect().size)
	var pixel := image.get_pixelv(image_point)
	# HDR viewport readback contains linear values before presentation to the screen.
	if root.use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		pixel = pixel.linear_to_srgb()
	var difference := maxf(absf(pixel.r - expected.r), maxf(absf(pixel.g - expected.g), absf(pixel.b - expected.b)))
	_check(difference <= PIXEL_TOLERANCE, "%s, expected #%s, got #%s" %
		[caption, expected.to_html(false), pixel.to_html(false)])


func _check(condition: bool, caption: String) -> void:
	_checks += 1
	if condition:
		print("PASS ", caption)
	else:
		_failures += 1
		push_error(caption)
