extends SceneTree
## Verifies recorded combat and the pause-menu log using the live Training Ground.

const Game = preload("res://main.tscn")
const GUARD := 6
const GUARD_NAME := "Crypt Guard"

var _game: Node3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game.title_screen.character_created.emit(0, "Combat Log Fixture")
	_aim(_game.hub.training_arrival_position(), _game.hub.interaction_position("training_portal"))
	await _tap(KEY_E)
	if _check(is_instance_valid(_game.training_ground), "The hub portal opens the Training Ground"):
		var enemy := await _spawn_guard()
		if is_instance_valid(enemy) and await _exercise_combat(enemy):
			await _exercise_log()
	_game.free()
	await _ticks(2)
	print("Hearth Below combat log: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _spawn_guard() -> CharacterBody3D:
	var player: Node3D = _game.player
	player.stats.merge({"max_health": 1000.0, "damage_min": 12.0, "damage_max": 12.0,
		"fire_damage": 3.0, "crit_chance": 0.0, "dodge_chance": 0.0,
		"life_regen": 0.0, "life_leech": 0.0, "ward": 0.0}, true)
	player.restore_full()
	player.place_at(Vector3(0.0, 0.08, 3.0))
	await _tap(KEY_F1)
	var portrait := _game.training_roster.find_child("Enemy%d" % GUARD, true, false) as Button
	if not _check(_game.training_roster.is_open() and is_instance_valid(portrait), "The F1 roster offers Crypt Guard"):
		return null
	portrait.grab_focus()
	await _tap(KEY_ENTER)
	for actor: Node in _game._training_actors.get_children():
		if actor is CharacterBody3D and actor.archetype_id == GUARD:
			return actor
	_check(false, "Selecting the portrait spawns Crypt Guard")
	return null


func _exercise_combat(enemy: CharacterBody3D) -> bool:
	var first_start := await _wait_for_event(&"cast_start", &"enemy", 320)
	if not _check(first_start.get("actor") == GUARD_NAME and _describes_ability(first_start),
			"Native attack windup logs a named and described ability"):
		return false
	_check(not enemy.receive_stun_impact(50.0, _game.player), "One hit builds stun without interrupting")
	_check(enemy.receive_stun_impact(50.0, _game.player) and enemy.is_stunned(),
		"Crossing the buildup threshold stuns during a live enemy cast")
	var stun_icon := enemy.find_child("StunStatusIcon", true, false) as Sprite3D
	_check(is_instance_valid(stun_icon) and stun_icon.visible and stun_icon.texture != null,
		"The actor shows the authored Stunned icon while control is lost")
	var cancelled := await _wait_for_event(&"cast_cancel", &"enemy", 30)
	_check(cancelled.get("ability") == first_start.get("ability")
		and cancelled.get("time", -1.0) > first_start.get("time", 0.0)
		and _find_event(&"damage", &"enemy").is_empty()
		and _find_event(&"cast_end", &"enemy").is_empty(),
		"Interrupting the windup cancels the same cast before damage or completion")

	var starting_life: float = _game.player.life
	var incoming := await _wait_for_event(&"damage", &"enemy", 320)
	_check(is_instance_valid(stun_icon) and not stun_icon.visible and not enemy.is_stunned(),
		"Recovered actors hide the Stunned icon before their next attack")
	var completed := await _wait_for_event(&"cast_end", &"enemy", 35)
	if not _check(incoming.get("actor") == GUARD_NAME and incoming.get("target") == "Player"
			and float(incoming.get("amount", 0.0)) > 0.0
			and is_equal_approx(float(incoming.get("amount", 0.0)), starting_life - _game.player.life),
			"An enemy hit logs the exact damage actually received"):
		return false
	_check(not completed.is_empty() and completed.get("ability") == incoming.get("ability")
		and _describes_ability(incoming) and _describes_ability(completed),
		"Enemy cast completion and damage identify the same named ability")

	enemy.set_physics_process(false)
	# Leave room for both damage types, independent of the guard's balanced Life.
	enemy.max_health = maxf(enemy.max_health, 16.0)
	enemy.health = enemy.max_health
	_aim(enemy.global_position + Vector3(0.0, 0.06, 1.55), enemy.aim_point())
	await _ticks(2)
	var target_life: float = enemy.health
	Input.action_press("attack")
	await _ticks(1)
	Input.action_release("attack")
	var outgoing := await _wait_for_event(&"damage", &"player", 45)
	_check(outgoing.get("actor") == "Player" and outgoing.get("target") == GUARD_NAME
		and _describes_ability(outgoing) and is_equal_approx(float(outgoing.get("amount", 0.0)), 15.0)
		and is_equal_approx(float(outgoing.get("amount", 0.0)), target_life - enemy.health),
		"A weapon hit logs one combined Physical and Fire amount")
	_check(_events_are_ordered(), "Recorded combat timestamps are chronological")
	return not outgoing.is_empty()


func _exercise_log() -> void:
	await _tap(KEY_ESCAPE)
	var log_button := _visible_button(_game.hud, "Combat Log")
	if not _check(is_instance_valid(log_button), "Esc pause menu offers Combat Log"):
		return
	log_button.grab_focus()
	await _tap(KEY_ENTER)
	if not _check(_game.combat_log.is_open() and _game._modal and not _game.player.gameplay_enabled,
			"Opening the log leaves gameplay paused"):
		return
	var overlay: Control = _game.combat_log
	var table := overlay.find_child("EventTable", true, false) as Tree
	if _check(is_instance_valid(table) and table.get_root() != null, "The log displays recorded combat events"):
		await _check_log_rows(overlay, table)

	await _tap(KEY_ESCAPE)
	_check(not _game.combat_log.is_open() and _game.hud.is_menu_open() and _game._modal,
		"Escape closes the log and returns to the still-paused menu")
	await _tap(KEY_ESCAPE)
	_check(not _game._modal and _game.player.gameplay_enabled, "Returning from the pause menu resumes play")


func _check_log_rows(overlay: Control, table: Tree) -> void:
	var oldest := table.get_root().get_first_child()
	if _check(is_instance_valid(oldest), "Combat log shows recorded rows"):
		var first_event: Dictionary = _game._combat_events.front()
		_check(oldest.get_text(3) == first_event.get("ability") and oldest.get_text(2) == first_event.get("actor"),
			"The oldest event is at the top of the log")
		_check(_cast_rows_are_ordered(table), "A cast reads Start, End, Damage from top to bottom, even when End and Damage share a timestamp")
		table.scroll_to_item(oldest)
		await _ticks(1)
		var motion := InputEventMouseMotion.new()
		motion.position = table.get_global_rect().position + table.get_item_area_rect(oldest, 3).get_center()
		motion.global_position = motion.position
		root.push_input(motion, true)
		await _ticks(2)
		var tooltip := overlay.find_child("AbilityTooltip", true, false) as Control
		_check(is_instance_valid(tooltip) and tooltip.is_visible_in_tree()
			and _has_label(tooltip, String(first_event.get("description", ""))),
			"Hovering an ability displays its combat description")

	_check(_row_count(table, "Damage", "Player") > 0 and _row_count(table, "Damage", GUARD_NAME) > 0,
		"Player and enemy damage both appear by default")
	if not await _toggle_filter(overlay, "Filter_player"):
		return
	_check(_row_count(table, "", "Player") == 0 and _row_count(table, "Damage", GUARD_NAME) > 0
		and _row_count(table, "Cast Started", GUARD_NAME) > 0,
		"Disabling Player hides all player events and keeps enemy damage and casts visible")
	await _toggle_filter(overlay, "Filter_player")
	if not await _toggle_filter(overlay, "Filter_enemy"):
		return
	_check(_row_count(table, "", GUARD_NAME) == 0 and _row_count(table, "Damage", "Player") > 0
		and _row_count(table, "Cast Started", "Player") > 0 and _row_count(table, "Cast Ended", "Player") > 0,
		"Disabling Enemies hides all enemy events and keeps player damage and casts visible")
	await _toggle_filter(overlay, "Filter_enemy")
	if not await _toggle_filter(overlay, "Filter_cast_cancel"):
		return
	_check(_row_count(table, "Cast Cancelled", GUARD_NAME) == 0 and _row_count(table, "Cast Started", GUARD_NAME) > 0
		and _row_count(table, "Cast Ended", GUARD_NAME) > 0,
		"Filtering cancelled casts leaves cast starts and completions visible")


func _cast_rows_are_ordered(table: Tree) -> bool:
	var cast_rows: Array[TreeItem] = []
	var item := table.get_root().get_first_child()
	while item:
		if item.get_text(2) == GUARD_NAME and item.get_text(1) in ["Cast Started", "Cast Cancelled", "Cast Ended", "Damage"]:
			cast_rows.append(item)
		item = item.get_next()
	var sequence := ["Cast Started", "Cast Cancelled", "Cast Started", "Cast Ended", "Damage"]
	if cast_rows.size() != sequence.size():
		return false
	for index in range(sequence.size()):
		if cast_rows[index].get_text(1) != sequence[index]:
			return false
	var ability := cast_rows[2].get_text(3)
	return cast_rows[3].get_text(3) == ability and cast_rows[4].get_text(3) == ability \
		and cast_rows[3].get_text(0) == cast_rows[4].get_text(0)


func _toggle_filter(overlay: Control, filter_name: String) -> bool:
	var button := overlay.find_child(filter_name, true, false) as Button
	if not _check(is_instance_valid(button) and button.is_visible_in_tree(), "The %s filter is available" % filter_name):
		return false
	button.grab_focus()
	await _tap(KEY_ENTER)
	return true


func _row_count(table: Tree, caption: String, actor: String) -> int:
	var count := 0
	var item := table.get_root().get_first_child()
	while item:
		if item.get_text(2) == actor and (caption.is_empty() or item.get_text(1) == caption):
			count += 1
		item = item.get_next()
	return count


func _has_label(owner: Control, message: String) -> bool:
	for node: Node in owner.find_children("*", "Label", true, false):
		if node.text == message:
			return true
	return false


func _find_event(kind: StringName, side: StringName) -> Dictionary:
	for event: Dictionary in _game._combat_events:
		if event.get("kind") == kind and event.get("side") == side:
			return event
	return {}


func _wait_for_event(kind: StringName, side: StringName, frames: int) -> Dictionary:
	for frame in range(frames):
		var event := _find_event(kind, side)
		if not event.is_empty():
			return event
		await _ticks(1)
	return {}


func _events_are_ordered() -> bool:
	var previous := -1.0
	for event: Dictionary in _game._combat_events:
		var timestamp := float(event.get("time", -1.0))
		if timestamp < 0.0 or timestamp < previous:
			return false
		previous = timestamp
	return true


func _describes_ability(event: Dictionary) -> bool:
	return not String(event.get("ability", "")).is_empty() and not String(event.get("description", "")).is_empty()


func _visible_button(owner: Node, caption: String) -> Button:
	for node: Node in owner.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.text == caption:
			return button
	return null


func _aim(point: Vector3, target: Vector3) -> void:
	var direction := (target - point - Vector3.UP * 1.56).normalized()
	_game.player.place_at(point, atan2(-direction.x, -direction.z), asin(direction.y))


func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(3)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _ticks(3)


func _ticks(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + description)
	else:
		_failures += 1
		push_error("FAIL  " + description)
	return condition
