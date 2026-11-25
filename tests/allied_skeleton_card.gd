extends SceneTree
## Plays the real Q card, then proves pursuit, melee contact and lifecycle in the arena.

const Game := preload("res://main.tscn")
const Catalog := preload("res://data/card_catalog.gd")
const CARD_ID := "oathbound_three"

var _game: Node3D
var _player: CharacterBody3D
var _events: Array[Dictionary] = []
var _checks := 0
var _failures := 0
var _enemy_deaths := 0
var _captures := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_captures = argument.trim_prefix("--capture-dir=")
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	current_scene = _game
	_game._start_training_from_title()
	await _ticks(6)
	_player = _game.player
	_player.combat_event.connect(_events.append)
	_player.place_at(Vector3(0.0, 0.06, 4.4), 0.0, -0.15)
	if not await _equip_from_training_cards():
		_finish()
		return
	await _tap_key(KEY_Q)
	if not _check(_game._card_hand_open and not _game.card_screen._hand.is_empty()
			and _game.card_screen._hand[0].accessibility_name == "Oathbound Three",
			"The combat hand shows the correct illustrated card"):
		_finish()
		return
	var mana: float = _player.mana
	_game.card_screen._hand[0].pressed.emit()
	await _ticks(4)
	var party := _game._training_actors.get_node_or_null("OathboundThree") as Node3D
	if not _check(is_instance_valid(party) and get_nodes_in_group("friendly_skeletons").size() == 3,
			"The card raises exactly three allies and consumes one hand slot"):
		_finish()
		return
	_check(get_nodes_in_group("enemies").is_empty() and not _game._remaining_cards().has(CARD_ID)
		and is_equal_approx(_player.mana, mana), "Allies are outside the hostile roster, and the card costs no Mana")
	var actors := get_nodes_in_group("friendly_skeletons")
	for actor in actors:
		var model := actor.get_node("Model")
		_check(model.strike_clip() != null and not model._motion.is_empty() and actor.owner_player == _player,
			"Each skeleton has a skinned melee clip and a real player owner")
	await _ticks(28)
	var occupied := PackedVector3Array()
	for actor in actors:
		occupied.append(actor.global_position)
	_check(occupied[0].distance_to(occupied[1]) > 0.65 and occupied[1].distance_to(occupied[2]) > 0.65,
		"All three rise from distinct grounded formation positions")
	_player.place_at(Vector3(0.0, 0.06, 6.35), 0.0, -0.15)
	await _ticks(12)
	await _capture("oathbound_formation")
	var enemy := _place_thrall(Vector3(0.0, 0.06, -1.35))
	enemy.died.connect(func(_enemy: CharacterBody3D) -> void: _enemy_deaths += 1)
	var original_life: float = enemy.health
	await _ticks(120)
	await _capture("oathbound_engagement")
	await _ticks(105)
	_check(enemy.health < original_life and _has_skeleton_hit("Grave Thrall"),
		"The companions pursue a real hostile and resolve Physical damage without player attack input")
	_check(_timeline_ordered(), "The allied melee log records windup, completion and damage in order")
	await _ticks(108)
	_check(enemy.health <= 0.0 and _enemy_deaths == 1,
		"Companions can kill a real hostile and emit exactly one normal enemy death")
	# A long move must pull the same three companions back to the player through the arena.
	_game.player.place_at(Vector3(-11.4, 0.06, 6.40))
	await _ticks(164)
	_check(actors.all(func(member: CharacterBody3D) -> bool:
		return member.global_position.distance_to(_player.global_position) < 5.0
	), "The same companions abandon a distant fight and follow the player")
	await _ticks(1120)
	_check(get_nodes_in_group("friendly_skeletons").is_empty() and not _game._remaining_cards().has(CARD_ID),
		"Temporary companions expire while the used card remains spent")
	_check(int(Catalog.CARDS[CARD_ID].minimum_depth) == 4 and Catalog.CARDS[CARD_ID].rarity == "rare",
		"The card is a level-gated Rare reward in normal expeditions")
	await _test_pillar_route()
	_finish()


func _test_pillar_route() -> void:
	_game._reset_training_combat()
	await _ticks(3)
	_player.place_at(Vector3(-7.25, 0.06, -3.50), PI)
	var enemy := _place_thrall(Vector3(-7.25, 0.06, 3.40))
	var life: float = enemy.health
	await _tap_key(KEY_Q)
	if not _check(_game._card_hand_open and not _game.card_screen._hand.is_empty(), "A reset training session refreshes the card"):
		return
	_game.card_screen._hand[0].pressed.emit()
	await _ticks(9)
	var companions := get_nodes_in_group("friendly_skeletons")
	var detour := false
	for _frame in 460:
		await _ticks(1)
		for member in companions:
			if member._path.size() > 2 and absf(member.global_position.x + 7.25) > 2.1:
				detour = true
		if detour and enemy.health < life:
			break
	_check(detour and enemy.health < life,
		"An ally routes around the real arena pillar before landing a clear melee hit")


func _place_thrall(point: Vector3) -> CharacterBody3D:
	var enemy: CharacterBody3D = _game.EnemyCatalog.instantiate(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1024
	enemy.setup(_player, 1, "normal", rng, _game.training_ground.navigation_route, _game.BestiaryData.combat_ability)
	enemy.position = point
	enemy.configure_ai(_game._training_encounter, _game._training_pressure)
	_game._training_actors.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _has_skeleton_hit(target: String) -> bool:
	return _events.any(func(entry: Dictionary) -> bool:
		return (entry.kind == &"damage" and entry.ability_id == &"oathbound_slash"
			and entry.target == target and entry.side == &"player" and entry.actor == "Oathbound Skeleton")
	)


func _timeline_ordered() -> bool:
	var before := false
	var committed := false
	for entry in _events:
		if entry.ability_id != &"oathbound_slash":
			continue
		if entry.kind == &"cast_start":
			before = true
		elif entry.kind == &"cast_end" and before:
			committed = true
		elif entry.kind == &"damage":
			return before and committed
	return false


func _equip_from_training_cards() -> bool:
	await _tap_key(KEY_F1)
	var tabs := _game.training_roster.find_child("TrainingTabs", true, false) as TabContainer
	var tab_bar := tabs.get_tab_bar()
	var tab_position := tab_bar.get_global_transform_with_canvas() * tab_bar.get_tab_rect(2).get_center()
	await _click(tab_position, MOUSE_BUTTON_LEFT)
	var collection := _game.training_roster.find_child("CardCollection", true, false) as GridContainer
	if not _check(tabs.current_tab == 2 and is_instance_valid(collection) and collection.is_visible_in_tree(),
			"The Cards tab opens from the Training Ground roster"):
		return false
	var choice := collection.get_node_or_null("DeckCard_" + CARD_ID) as Button
	if not _check(is_instance_valid(choice), "Oathbound Three is in the Cards collection"):
		return false
	var scroll := collection.get_parent() as ScrollContainer
	var scroll_bounds := scroll.get_global_rect()
	for _attempt in 32:
		if scroll_bounds.encloses(choice.get_global_rect()):
			break
		await _click(scroll_bounds.get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	var choice_bounds := choice.get_global_rect()
	if not _check(scroll_bounds.encloses(choice_bounds) and root.get_visible_rect().encloses(choice_bounds),
			"The actual Cards gallery can scroll the summon card fully into view"):
		return false
	await _capture("oathbound_training_cards")
	await _click(choice_bounds.get_center(), MOUSE_BUTTON_LEFT)
	var equipped: bool = _game._training_card_deck.equipped[0] == CARD_ID
	await _tap_key(KEY_F1)
	return _check(equipped and not _game.training_roster.is_open(),
		"Clicking the summon card equips it in the practice deck")


func _click(point: Vector2, button: MouseButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)
	await _ticks(2)


func _tap_key(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await _ticks(2)
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await _ticks(1)


func _capture(name_tag: String) -> void:
	if _captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if root.use_hdr_2d:
		frame.convert(Image.FORMAT_RGB8)
		frame.linear_to_srgb()
	_check(frame.save_png(_captures.path_join(name_tag + ".png")) == OK, "Captured %s" % name_tag)


func _ticks(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame


func _finish() -> void:
	_game.free()
	print("Oathbound Three card: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
	return condition
