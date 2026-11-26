extends SceneTree

const Hud := preload("res://ui/hud.tscn")
const Cards := preload("res://ui/card_interface.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1422, 800)
	root.add_child(viewport)
	await _check_shades(viewport)
	await _check_achievement_size(viewport)
	print("Hearth Below UI presentation: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_shades(viewport: SubViewport) -> void:
	var cards := Cards.instantiate()
	viewport.add_child(cards)
	var hand_shade := cards.get_node("HandShade") as ColorRect
	var deck_shade := cards.get_node("DeckShade") as ColorRect
	var deck: Array[String] = ["red_mercy", "cinder_circle", "iron_oath"]
	cards.show_hand(deck)
	_check(hand_shade.visible and not deck_shade.visible and hand_shade.self_modulate.a == 0.0,
		"Combat hand opens with a transparent black shade")
	await cards._shade_animation.finished
	_check(hand_shade.color == Color(0, 0, 0, 0.50)
		and is_equal_approx(hand_shade.self_modulate.a, 1.0), "The fade darkens the world")
	cards.show_hand(deck)
	await process_frame
	cards.show_loadout(deck, deck)
	await create_timer(0.28, true, false, true).timeout
	_check(not hand_shade.visible and deck_shade.visible
		and deck_shade.color == Color(0, 0, 0, 0.82), "Switching to the deck uses its own dark shade")
	cards.dismiss()
	_check(not deck_shade.is_visible_in_tree(), "Closing the cards also hides the shade")
	cards.free()


func _check_achievement_size(viewport: SubViewport) -> void:
	var hud := Hud.instantiate()
	viewport.add_child(hud)
	var toast := hud.get_node("AchievementUnlock") as PanelContainer
	var long_description := "Learn to read enemy attacks, recover from heavy strikes, and find an opening to counter with your equipped weapon."
	hud.present_achievement({"name": "Practiced Fighter", "description": long_description, "points": 15})
	hud.present_achievement({"name": "Gilded Purse", "description": "Collect 500 gold.", "points": 10})
	await create_timer(0.50).timeout
	var wrapped_height := toast.size.y
	_check(toast.visible and wrapped_height >= 100.0 and wrapped_height < 150.0
		and is_equal_approx(wrapped_height, toast.get_combined_minimum_size().y),
		"A wrapped achievement description takes only the height it needs")
	await create_timer(4.30).timeout
	_check(toast.visible and toast.size.y < wrapped_height and toast.size.y <= 110.0
		and is_equal_approx(toast.size.y, toast.get_combined_minimum_size().y),
		"The next short toast shrinks again and does not retain the previous height")
	_check(toast.get_node("Contents/Labels/Title").text == "Gilded Purse"
		and toast.get_node("Contents/Badge/Points").text == "+10", "Queued toast keeps the right title and points")
	hud.free()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
