extends SceneTree

const Items := preload("res://systems/items.gd")
const Data := preload("res://data/items/legendaries.gd")
const Bases := preload("res://data/items/bases.gd")
const Names := preload("res://data/items/item_name_records.tres")
const Inventory := preload("res://systems/inventory.gd")
const Supplies := preload("res://systems/pack_supplies.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7319481
	var names := {}
	var kinds := {}
	var bases := {}
	for base in Bases.BASES:
		bases[base.id] = base
	var all_match := true
	for definition: Dictionary in Data.DROPS:
		names[definition.id] = true
		var base: Dictionary = bases[definition.base_id]
		kinds[base.type] = true
		var ranges: Dictionary = definition.stat_ranges
		var observed := {}
		for index in 72:
			var item := Items._make_legendary(base, definition, int(definition.level), "legend_test_%d" % index, rng)
			var values: Dictionary = item.legendary_stats
			var in_bounds := ranges.size() == values.size()
			for key: String in values:
				var bounds: Vector2 = ranges[key]
				in_bounds = in_bounds and is_equal_approx(clampf(float(values[key]), bounds.x, bounds.y), float(values[key]))
			all_match = all_match and in_bounds and item.effect == definition.effect and item.name == definition.name \
				and item.legendary_affix_tier == definition.affix_tier and Items.restore_item(item) == item
			observed[hash(values)] = true
		_check(observed.size() > 1, "%s varies values across actual rolls" % definition.name)
	_check(names.size() == Data.DROPS.size() and names.size() >= 30, "Distinct legendary definitions include twenty new items")
	_check(kinds.size() >= 11, "Legendary gear covers at least eleven supported base types")
	_check(all_match, "Every unique keeps its exact affix keys, ranges, tier, effect, and saved roll")
	_check_retired_effects(bases, rng)
	_check(_stock_at(25, 31) == _stock_at(50, 31), "Hub merchant power and prices cap at item level 25")
	var early := _stock_at(1, 31)
	var later := _stock_at(25, 31)
	_check(early[0].item_level == 1 and later[0].item_level == 25 and early[0].price < later[0].price,
		"The standard merchant scales its items and prices with its level")
	_check_item_names(rng)
	print("Legendary rolls and vendor stock: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_retired_effects(bases: Dictionary, rng: RandomNumberGenerator) -> void:
	var old_effects := {
		"undertakers_tithe": "deep_pockets", "cairn_oath": "cairn_oath",
		"masons_listener": "masons_listener", "tollkeepers_mercy": "tollkeepers_mercy",
	}
	var verified := 0
	for definition: Dictionary in Data.DROPS:
		if not old_effects.has(definition.id):
			continue
		var item := Items._make_legendary(bases[definition.base_id], definition, int(definition.level), "legacy_unique", rng)
		var saved := item.duplicate(true)
		saved.effect = old_effects[definition.id]
		saved.effect_description = "Legacy expedition effect"
		_check(item.effect.is_empty() and Items.restore_item(saved) == item,
			"%s keeps item identity and rolls when its retired expedition effect is cleared" % item.name)
		verified += 1
	_check(verified == old_effects.size(), "Every retired effect keeps a readable legendary record")


func _stock_at(level: int, seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Items.roll_vendor(level, rng)


func _check_item_names(rng: RandomNumberGenerator) -> void:
	var all_names_match := true
	var example: Dictionary
	for base: Dictionary in Bases.BASES:
		var family := String(base.type).trim_suffix("_1h").trim_suffix("_2h")
		var pool: PackedStringArray = Names.rare_suffixes[family]
		var white := Items._roll_gear(base, 15, "normal", rng)
		var magic := Items._roll_gear(base, 15, "magic", rng)
		var rare := Items._roll_gear(base, 15, "rare", rng)
		var words := PackedStringArray()
		if not magic.prefixes.is_empty():
			words.append(magic.prefixes[0].name)
		words.append(base.name)
		if not magic.suffixes.is_empty():
			words.append(magic.suffixes[0].name)
		all_names_match = all_names_match and white.name == base.name and magic.name == " ".join(words) \
			and rare.name.get_slice_count(" ") == 2 and rare.name.get_slice(" ", 1) in pool \
			and Items.visible_name(rare) == base.name and not Items.tooltip(rare, true).contains(rare.name)
		example = rare
	_check(all_names_match, "All bases use the rarity-specific name grammar and hide unrecognized rare titles")
	var stock := Inventory.new()
	var seal := Supplies.unveiling_scroll()
	seal.id = "test_scribe_seal"
	stock.add_item(example)
	stock.add_item(seal)
	var reopened := Inventory.new()
	_check(reopened.restore_data(stock.save_data()), "Named rares and seals survive an inventory save round trip")
	var seal_id: StringName
	for placement: Dictionary in reopened.get_grid("bag").get_placements():
		if reopened.get_item(placement.id).get("supply_kind") == Supplies.UNVEILING_SCROLL:
			seal_id = placement.id
	var hidden := reopened.get_item(StringName(example.id))
	_check(hidden.get("unidentified", false) and hidden.name == example.name
		and reopened.identify_item(seal_id, StringName(example.id)).is_empty(),
		"Identification succeeds after reload with the previously selected name")
	var revealed := reopened.get_item(StringName(example.id))
	_check(Items.visible_name(revealed) == example.name and revealed.prefixes == example.prefixes
		and revealed.suffixes == example.suffixes, "The Seal reveals exactly the stored title and modifiers")


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(description)
