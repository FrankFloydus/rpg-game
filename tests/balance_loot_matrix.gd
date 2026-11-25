extends SceneTree
## A seeded sample of production loot, currency, and vendor rolls by Depth and source.

const Game := preload("res://main.gd")
const Items := preload("res://systems/items.gd")
const Inventory := preload("res://systems/inventory.gd")
const Cards := preload("res://data/card_catalog.gd")
const Enemies := preload("res://combat/enemies/enemy_catalog.gd")
const Bases := preload("res://data/items/bases.gd")
const Affixes := preload("res://data/items/affixes.gd")
const Depths := [1, 3, 6, 7, 10, 20, 40, 50]
const Rarities := ["normal", "magic", "rare"]
const Coffers := ["chest", "locked_chest", "secret_cache", "side_cache"]
const ElementalAffixes := ["fire_damage", "cold_damage", "lightning_damage", "poison_damage"]
const KILLS_PER_CELL := 20_000
const COFFERS_PER_CELL := 1_200
const VENDOR_REFRESHES_PER_DEPTH := 100
const SEED := 7591661

class UnmodifiedPlayer extends CharacterBody3D:
	var stats := {"gold_find": 0.0, "loot_rarity": 0.0}
	var effects: Array[String] = []

var _game := Game.new()
var _stats := UnmodifiedPlayer.new()
var _rng := RandomNumberGenerator.new()
var _card_rng := RandomNumberGenerator.new()
var _family_rng := RandomNumberGenerator.new()
var _unavailable_cards := {}
var _base_levels := {}
var _item_rolls := 0
var _issues: Array[String] = []
var _label := "baseline"
var _out := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_out = argument.trim_prefix("--output=")
		elif argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=")
	_run.call_deferred()


func _run() -> void:
	var start_ms := Time.get_ticks_msec()
	var input_hashes := _input_hashes()
	_game.player = _stats
	_game._rng = _rng
	for starter in Cards.STARTERS:
		_unavailable_cards[starter] = true
	for base: Dictionary in Bases.BASES:
		_base_levels[base.id] = int(base.level)
	var matrix: Array[Dictionary] = []
	for depth in Depths:
		var rows: Array[Dictionary] = []
		for rarity in Rarities:
			rows.append(_monsters(depth, rarity))
		for source in Coffers:
			rows.append(_coffers(depth, source))
		rows.append(_vendor(depth))
		matrix.append_array(rows)
		_print_depth(depth, rows)
	var kills := Depths.size() * Rarities.size() * KILLS_PER_CELL
	var opened := Depths.size() * Coffers.size() * COFFERS_PER_CELL
	var refreshed := Depths.size() * VENDOR_REFRESHES_PER_DEPTH
	if _item_rolls < 250_000:
		_issues.append("The matrix did not execute at least 250,000 item rolls")
	var report := {"label": _label, "seed": SEED, "enemy_kills": kills, "coffers_opened": opened,
		"vendor_refreshes": refreshed, "actual_item_rolls": _item_rolls, "rows": matrix, "issues": _issues,
		"input_hashes": input_hashes, "elapsed_ms": Time.get_ticks_msec() - start_ms}
	if not _out.is_empty():
		var file := FileAccess.open(_out, FileAccess.WRITE)
		if file == null:
			_issues.append("Unable to write result %s" % _out)
		else:
			file.store_string(JSON.stringify(report, "\t"))
	print("Loot matrix %s: %d kills, %d coffers, %d vendor refreshes, %d actual rolls, %d issues, %.2f s"
		% [_label, kills, opened, refreshed, _item_rolls, _issues.size(), float(report.elapsed_ms) / 1000.0])
	for detail in _issues:
		printerr(detail)
	_game.free()
	_stats.free()
	quit(0 if _issues.is_empty() else 1)


func _monsters(depth: int, source: String) -> Dictionary:
	var row := _new_row(depth, source, KILLS_PER_CELL)
	var gear := Items.enemy_drop_chance(depth, source, "gear")
	var material := Items.enemy_drop_chance(depth, source, "material")
	var key := Items.enemy_drop_chance(depth, source, "key")
	var item_level := depth + int(Game.ENEMY_GEAR_LEVEL_BONUS.get(source, 0)) if depth > 10 else depth
	var prefix := hash([SEED, depth, source])
	var deck_available := Cards.DROP_CHANCES.has(source)
	for index in KILLS_PER_CELL:
		_rng.seed = hash([prefix, index])
		if _rng.randf() < gear:
			_record_item(row, Items.roll_item(item_level, source, _rng))
		row.gold_sum += _game._roll_enemy_gold(depth, source)
		if _rng.randf() < material:
			# Use the same catalog lottery as the generated roster, independent of reward randomness.
			_family_rng.seed = hash([prefix, index, "material_family"])
			var archetype := Enemies.pick_archetype(depth, _family_rng)
			var part: String = Enemies.ARCHETYPES[archetype]["part"]
			if part.is_empty():
				part = Items.material_drop(depth, _rng)
			_record_material(row, part)
		# This individual-kill matrix excludes the one-key fallback on the last kill of a floor.
		if _rng.randf() < key:
			row.keys += 1
		if deck_available:
			_card_rng.seed = hash([prefix, index, "card"])
			var card_id := Cards.roll_drop(depth, source, _unavailable_cards, _card_rng)
			if not card_id.is_empty():
				_increment(row.card_ids, card_id)
	return row


func _coffers(depth: int, source: String) -> Dictionary:
	var row := _new_row(depth, source, COFFERS_PER_CELL)
	var protected_reward := source == "locked_chest"
	var hidden_cache := source == "secret_cache"
	var plain_cache := source == "side_cache"
	var prefix := hash([SEED, depth, source])
	for index in COFFERS_PER_CELL:
		_rng.seed = hash([prefix, index])
		var has_gear := not plain_cache or _rng.randf() < Items.SIDE_CACHE_GEAR_CHANCE
		if has_gear:
			_record_item(row, Items.roll_item(depth, source, _rng))
		row.gold_sum += _game._roll_coffer_gold(depth, protected_reward)
		if protected_reward and depth >= Items.PROTECTED_COFFER_BONUS_DEPTH \
				and _rng.randf() < Items.PROTECTED_COFFER_BONUS_GEAR_CHANCE:
			_record_item(row, Items.roll_item(depth, source, _rng))
		if protected_reward or hidden_cache or not has_gear:
			_record_material(row, Items.material_drop(depth, _rng))
	return row


func _vendor(depth: int) -> Dictionary:
	var row := _new_row(depth, "vendor_after_clear", VENDOR_REFRESHES_PER_DEPTH)
	var prefix := hash([SEED, depth, "vendor_after_clear"])
	for index in VENDOR_REFRESHES_PER_DEPTH:
		_rng.seed = hash([prefix, index])
		for item in Items.roll_vendor(maxi(1, depth - 1), _rng):
			_record_item(row, item)
	return row


func _new_row(depth: int, source: String, samples: int) -> Dictionary:
	return {"depth": depth, "source": source, "samples": samples, "gear": 0, "gold_sum": 0, "keys": 0,
		"materials": 0, "material_ids": {}, "card_ids": {}, "rarities": {}, "slots": {}, "types": {},
		"base_levels": {}, "item_levels": {}, "affix_ids": {}, "affix_tiers": {}, "explicit_counts": {},
		"affixes": 0, "sell_sum": 0, "gold_value": {}, "prices": {}, "weapon_hits_doubled": {},
		"armour_amounts": {}, "life_amounts": {}, "stamina_amounts": {}, "inverted_damage_ranges": 0}


func _record_item(row: Dictionary, item: Dictionary) -> void:
	_item_rolls += 1
	row.gear += 1
	var rarity: String = item.rarity
	var item_type: String = item.type
	var slot: String = item.slot
	var stats: Dictionary = item.stats
	_increment(row.rarities, rarity)
	_increment(row.slots, slot)
	_increment(row.types, item_type)
	_increment(row.base_levels, int(_base_levels[item.base_id]))
	_increment(row.item_levels, int(item.item_level))
	_increment(row.gold_value, int(item.gold_value))
	_increment(row.prices, int(item.price))
	row.sell_sum += Inventory.sell_price(item)
	var explicit_count: int = item.prefixes.size() + item.suffixes.size()
	_increment(row.explicit_counts.get_or_add(rarity, {}), explicit_count)
	row.affixes += explicit_count
	for affix: Dictionary in item.prefixes + item.suffixes:
		_increment(row.affix_ids, affix.id)
		_increment(row.affix_tiers, int(affix.tier))
	if slot in ["main_hand", "one_hand"]:
		var minimum := int(stats.get("damage_min", 0))
		var maximum := int(stats.get("damage_max", 0))
		var hit := minimum + maximum
		for element in ElementalAffixes:
			hit += 2 * int(stats.get(element, 0))
		_increment(row.weapon_hits_doubled.get_or_add(item_type, {}).get_or_add(rarity, {}), hit)
		if minimum > maximum:
			row.inverted_damage_ranges += 1
	else:
		_increment(row.armour_amounts.get_or_add(slot, {}).get_or_add(rarity, {}), int(stats.get("armor", 0)))
		_increment(row.life_amounts.get_or_add(slot, {}).get_or_add(rarity, {}), int(stats.get("max_health", 0)))
		_increment(row.stamina_amounts.get_or_add(slot, {}).get_or_add(rarity, {}), int(stats.get("max_stamina", 0)))


func _record_material(row: Dictionary, id: String) -> void:
	row.materials += 1
	_increment(row.material_ids, id)
	if not Affixes.MATERIALS.has(id):
		var diagnostic := "Enemy or coffer can drop an unregistered material: %s" % id
		if not _issues.has(diagnostic):
			_issues.append(diagnostic)


func _print_depth(depth: int, rows: Array[Dictionary]) -> void:
	for row: Dictionary in rows:
		var factor := 100.0 / float(row.samples)
		var by_rarity: Array = row.rarities.keys()
		by_rarity.sort()
		var rarities := PackedStringArray()
		for rarity in by_rarity:
			rarities.append("%s=%.2f" % [rarity, row.rarities[rarity] * factor])
		var cards := 0
		for count in row.card_ids.values():
			cards += int(count)
		print("%02d %-18s /100: gear=%6.2f %s | materials=%6.2f keys=%5.2f cards=%5.2f gold=%6.1f sell=%7.1f"
			% [depth, row.source, row.gear * factor, " ".join(rarities), row.materials * factor,
			row.keys * factor, cards * factor, row.gold_sum * factor, row.sell_sum * factor])


func _input_hashes() -> Dictionary:
	var paths := ["main.gd", "systems/items.gd", "data/card_catalog.gd", "data/items/loot_records.tres",
		"data/items/affix_records.tres", "data/items/gear_records.tres", "data/items/legendary_records.tres",
		"combat/enemies/enemy_catalog.gd", "tests/balance_loot_matrix.gd"]
	var result := {}
	for path in paths:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result


func _increment(histogram: Dictionary, key: Variant) -> void:
	histogram[key] = int(histogram.get(key, 0)) + 1
