extends SceneTree
## Verify authored routes keep their safety and isolation when stamped into seeded dungeons.

const Dungeon := preload("res://world/dungeon.gd")
const Scene := preload("res://world/dungeon.tscn")
const Routes := preload("res://world/secret_challenges/secret_challenge_catalog.gd")
const Gates := preload("res://world/dungeon_route_gates.gd")

var _checks := 0
var _failures := 0
var _paired_endcaps := 0
var _pair_example := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var expected := {}
	for route in Routes.ROUTES:
		expected[route.id] = true
		_check_blueprint(route, false)
		if not route.alternate_rows.is_empty():
			_check_blueprint(route, true)
	_check(expected.size() >= 20, "Every authored route has a distinct stable identifier")
	var sampled := {}
	var shorter_and_longer := {}
	var floors_with_challenge := 0
	var depths := [2, 4, 7, 10, 15, 24]
	for index in 432:
		var depth: int = depths[index % depths.size()]
		var seed_value := 5874629 + index * 110129
		var floor_index := floori(index / 6.0) % 3
		var rise := -1 if index % 2 else 1
		var mask := Dungeon.FEATURE_SECRET_MERCHANT if depth >= 10 and index % 13 == 0 else 0
		var floor := _layout(depth, seed_value, floor_index, rise, mask, Dungeon.GENERATION_VERSION)
		var count := 0
		for opening: Dictionary in floor.secret_passages:
			if not opening.has("challenge_id"):
				continue
			count += 1
			sampled[opening.challenge_id] = int(sampled.get(opening.challenge_id, 0)) + 1
			shorter_and_longer[opening.challenge_variant] = true
			_check_placement(floor, opening, seed_value, depth, floor_index)
		if count > 0:
			floors_with_challenge += 1
		_check(count <= 1, "A floor reserves at most one authored challenge")
		if index % 41 == 0:
			var replay := _layout(depth, seed_value, floor_index, rise, mask, Dungeon.GENERATION_VERSION)
			_check(floor.map_cells == replay.map_cells and floor.secret_passages == replay.secret_passages
				and floor.hazard_points == replay.hazard_points, "Replay retains route shape, socket rolls and concealed IDs")
			replay.free()
		floor.free()
	var older := _layout(8, 5874629, 0, -1, 0, Dungeon.EXPANDED_ROSTER_VERSION)
	_check(not older.secret_passages.any(func(opening: Dictionary) -> bool: return opening.has("challenge_id")),
		"Version 9 checkpoints still build their original secret passages")
	older.free()
	var missing := expected.keys().filter(func(id: StringName) -> bool: return not sampled.has(id))
	_check(missing.is_empty(), "Full-floor generation samples every authored route, missing %s" % str(missing))
	_check(shorter_and_longer.has(true) and shorter_and_longer.has(false), "Seeded generation uses both authored forms")
	_check(_paired_endcaps > 0 and _paired_endcaps < floors_with_challenge / 4.0, "Two-chest endcaps remain an uncommon seeded variant")
	print("Secret challenge layout: %d checks, %d failures; %d/432 floors; %d/%d route IDs" % [
		_checks, _failures, floors_with_challenge, sampled.size(), expected.size()])
	print("Route samples: %s" % str(sampled))
	print("Paired endcaps: %d/%d, first example %s" % [_paired_endcaps, floors_with_challenge, _pair_example])
	quit(0 if _failures == 0 else 1)


func _layout(depth: int, seed_value: int, index: int, rise: int, features: int, version: int) -> Dungeon:
	var floor := Scene.instantiate() as Dungeon
	floor._generation_version = version
	floor._feature_mask = features
	floor._room_limit = clampi(ceili(float(mini(24, 6 + depth * 2)) / 3.0), 6, 8)
	floor._population_scale = 0.70
	floor._rng.seed = seed_value
	floor._layout_expedition(depth, seed_value, index, 3, rise)
	return floor


func _check_blueprint(template: SecretChallengeRoute, alternative: bool) -> void:
	var cells := {}
	for tile: Vector2i in template.floor_cells(alternative):
		cells[tile] = true
	var ingress := template.ingress(alternative)
	var reward := template.reward(alternative)
	var reachable := Gates.reachable(cells, ingress)
	_check(reachable.has(reward) and reachable.size() == cells.size(), "%s has one connected walkable layout" % template.id)
	var required := 0
	for tile: Vector2i in template.sockets(alternative):
		var socket: SecretChallengeSocket = template.sockets(alternative)[tile]
		if socket.optional:
			continue
		required += 1
		var perpendicular := Vector2i(-socket.facing.y, socket.facing.x)
		_check(not cells.has(tile + perpendicular) and not cells.has(tile - perpendicular)
			and not Gates.reachable(cells, ingress, tile).has(reward), "%s has a non-bypassable mandatory trap socket" % template.id)
	_check(required > 0, "%s contains at least one required fixture" % template.id)


func _check_placement(floor: Dungeon, secret: Dictionary, seed_value: int, depth: int, floor_index: int) -> void:
	var branch := floor.side_passages[int(secret.branch)]
	var entry: Vector2i = branch.cells[int(secret.entry)]
	var reward: Vector2i = branch.tip
	var arrival := floor.tile_at(floor.spawn_position)
	var sealed := Gates.reachable(floor.map_cells, arrival, entry)
	var connected := Gates.reachable(floor.map_cells, arrival)
	_check(connected.has(reward) and not sealed.has(reward) and secret.id != floor.secret_merchant_passage,
		"The closed slab protects the route and the merchant keeps its own passage")
	var required := 0
	for hazard: Dictionary in secret.challenge_hazards:
		if bool(hazard.optional):
			continue
		required += 1
		var tile: Vector2i = hazard.tile
		var facing: Vector2i = hazard.heading
		var perpendicular := Vector2i(-facing.y, facing.x)
		_check(not floor.map_cells.has(tile + perpendicular) and not floor.map_cells.has(tile - perpendicular)
			and not Gates.reachable(floor.map_cells, arrival, tile).has(reward),
			"Stamps preserve the mandatory trap choke without a route alongside or around it")
	_check(required >= 1, "The recipe never omits every mandatory trap")
	var rewards := floor.chests.filter(func(chest: Dictionary) -> bool:
		return bool(chest.get("secret_cache", false)) and floor.tile_at(chest.position) == reward)
	_check(rewards.size() == (2 if bool(branch.get("bonus_coffer", false)) else 1),
		"The coffer or coffer pair remains in the protected terminal cell")
	if rewards.size() == 2:
		_paired_endcaps += 1
		if _pair_example.is_empty():
			_pair_example = "%s · Depth %d · Floor %d · Seed %d" % [secret.challenge_name, depth, floor_index + 1, seed_value]
		floor._seat_coffers(seed_value)
		var first := floor.coffer_pose(int(rewards[0].id))
		var second := floor.coffer_pose(int(rewards[1].id))
		var direction: Vector2i = reward - branch.cells[-2]
		var outward := Vector3(direction.x, 0.0, direction.y)
		_check(first.origin.distance_to(second.origin) >= 1.46 and first.basis.z.dot(outward) < -0.98
			and second.basis.z.dot(outward) < -0.98 and floor.tile_at(first.origin) == reward
			and floor.tile_at(second.origin) == reward, "Paired native coffer poses face a common clear approach with no overlap")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL  ", description)
