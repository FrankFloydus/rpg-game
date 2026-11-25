extends RefCounted
## Reserves feature slots for the entire expedition before building individual floors.

const Dungeon := preload("res://world/dungeon.gd")
const Rules := preload("res://data/expedition_rules.tres")
const Broker := preload("res://data/secret_merchant_rules.tres")


static func make_plan(depth: int, seed_value: int, floor_count: int) -> Dictionary:
	var masks := PackedInt32Array()
	masks.resize(floor_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "expedition_features"])
	var plans := 0
	if depth >= 2 and rng.randf() < Rules.primary_event_chance:
		var first_options := _features_at_depth(depth)
		var event := first_options[rng.randi_range(0, first_options.size() - 1)]
		if depth >= Broker.minimum_depth and rng.randf() < Broker.share_of_primary_events:
			event = Dungeon.FEATURE_SECRET_MERCHANT
		var first_floor := 0 if event == Dungeon.FEATURE_ROUTE_GATE else rng.randi_range(0, floor_count - 1)
		masks[first_floor] |= event
		plans += 1
		if floor_count > 1 and depth >= Rules.second_event_depth and rng.randf() < Rules.second_event_chance:
			if event != Dungeon.FEATURE_ROUTE_GATE or depth < 9:
				first_options.erase(event)
			if not first_options.is_empty():
				var second := first_options[rng.randi_range(0, first_options.size() - 1)]
				var another_floor := (first_floor + rng.randi_range(1, floor_count - 1)) % floor_count
				masks[another_floor] |= second
				plans += 1
	if rng.randf() < Rules.incidental_ambush_chance:
		var suitable: Array[int] = []
		for floor_index in floor_count:
			if masks[floor_index] == 0:
				suitable.append(floor_index)
		if not suitable.is_empty():
			var ambush_floor := suitable[rng.randi_range(0, suitable.size() - 1)]
			var coffer := depth >= 2 and rng.randf() < 0.44
			masks[ambush_floor] |= Dungeon.FEATURE_COFFER_AMBUSH if coffer else Dungeon.FEATURE_THRESHOLD_AMBUSH
	var legate := depth >= 3 and plans < 2 and rng.randf() < Rules.legate_incursion_chance
	return {"masks": Array(masks), "legate": legate}


static func _features_at_depth(depth: int) -> Array[int]:
	var features: Array[int] = [Dungeon.FEATURE_ROUTE_GATE, Dungeon.FEATURE_BLOOD_ALTAR]
	if depth >= 4:
		features.append_array([Dungeon.FEATURE_TRIAL_COFFER, Dungeon.FEATURE_PLATFORM_CHAMBER])
	if depth >= 5:
		features.append(Dungeon.FEATURE_LAVA_CHAMBER)
	if depth >= 6:
		features.append(Dungeon.FEATURE_SUBMERGED_CHAMBER)
	return features
