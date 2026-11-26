@tool
extends RefCounted
## Keeps workbench edits within the invariants required by the runtime tables.

const Catalog := preload("res://addons/hearth_workbench/workbench_catalog.gd")
const AffixRecords := preload("res://data/items/affix_records.tres")
const MINIMUM_RARITIES := ["normal", "magic", "rare"]
const SLOTS := ["main_hand", "one_hand", "off_hand", "helm", "chest", "gloves", "boots", "belt", "ring", "amulet"]


static func check(path: String, resource: Resource, gear: Resource) -> String:
	match path:
		Catalog.GEAR: return _check_gear(resource)
		Catalog.AFFIXES: return _check_affixes(resource)
		Catalog.LEGENDARIES: return _check_legendaries(resource, gear)
		Catalog.LOOT: return _check_loot(resource)
		Catalog.PLAYER: return _check_player(resource)
		Catalog.WEAPON_HIT_SHAKE: return resource.validation_error()
		Catalog.MELEE_CONTACT: return resource.validation_error()
	if path.begins_with(Catalog.ABILITIES + "/") or path.begins_with(Catalog.EFFECTS + "/"):
		var previous := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if previous != null and previous.id != resource.id:
			return "The record ID is used by existing references. Keep the original ID."
		if str(resource.display_name).strip_edges().is_empty():
			return "The record needs a display name."
		if resource is AbilityDefinition:
			var profile: Dictionary = resource.runtime_profile()
			var shape := str(profile.get("shape", ""))
			var reach := float(profile.get("reach", 0.0))
			if shape.is_empty() and previous is AbilityDefinition \
					and not String(previous.runtime_profile().get("shape", "")).is_empty():
				return "This attack needs a hit shape to be registered by its caster."
			if shape in ["arc", "disc", "ring", "lane"] and reach <= 0.0:
				return "The attack's hit reach must be greater than zero."
			if shape == "ring" and float(profile.get("inner_radius", 0.0)) >= reach:
				return "The ring's inner safe radius must be smaller than its hit reach."
			if shape == "lane" and float(profile.get("width", 0.0)) <= 0.0:
				return "The lane needs a positive half-width."
	return ""


static func _check_gear(value: Resource) -> String:
	for id: String in value.types:
		var family: Dictionary = value.types[id]
		if family.slot not in SLOTS or str(family.name).strip_edges().is_empty():
			return "Item family %s needs a name and a valid equipment slot." % id
		if not _valid_footprint(family.size):
			return "Item family %s needs a footprint that fits the inventory." % id
	for id: String in value.base_footprints:
		if not _valid_footprint(value.base_footprints[id]):
			return "Base footprint %s must fit the inventory." % id
	for base: Dictionary in value.bases:
		if str(base.name).strip_edges().is_empty() or base.type not in value.types or int(base.level) < 1:
			return "Base %s needs a name, a valid family, and a positive level." % base.id
		var stats: Dictionary = base.get("stats", {})
		if stats.has("damage_max") and float(stats.get("damage_min", 0)) > float(stats.damage_max):
			return "Minimum damage exceeds maximum damage on %s." % base.name
	var previous := 0.0
	for point: Vector3 in value.power_by_level:
		if point.x <= previous or point.y <= 0.0 or point.z <= 0.0:
			return "Item power levels must increase and both multipliers must stay positive."
		previous = point.x
	return ""


static func _check_affixes(value: Resource) -> String:
	var previous := 0
	for level: int in value.tier_levels:
		if level <= previous:
			return "Affix minimum levels must increase from the lowest tier to the highest tier."
		previous = level
	for scale: float in value.tier_multipliers:
		if not is_finite(scale) or scale <= 0.0:
			return "Affix tier multipliers must be positive."
	for pool: Array in [value.prefixes, value.suffixes]:
		for affix: Dictionary in pool:
			if str(affix.name).strip_edges().is_empty() or int(affix.weight) < 0:
				return "Affix %s needs a name and a nonnegative weight." % affix.id
			for slot: String in affix.get("slots", []):
				if slot not in SLOTS:
					return "%s uses an unknown slot: %s." % [affix.name, slot]
			for stat: String in affix.stats:
				var bounds: Array = affix.stats[stat]
				if float(bounds[0]) > float(bounds[1]):
					return "The %s minimum exceeds the maximum on %s." % [stat.capitalize(), affix.name]
	for recipe: Dictionary in value.recipes:
		var side := String(recipe.get("side", ""))
		var affix_id := String(recipe.get("affix_id", ""))
		if side not in ["prefix", "suffix"]:
			return "%s needs a prefix or suffix for its crafted affix." % recipe.name
		var pool: Array = value.prefixes if side == "prefix" else value.suffixes
		var matching := pool.any(func(affix: Dictionary) -> bool: return String(affix.id) == affix_id)
		if not matching:
			return "%s needs an affix from the selected %s pool." % [recipe.name, side]
	return ""


static func _check_legendaries(value: Resource, gear: Resource) -> String:
	var known := {}
	if gear != null:
		for base: Dictionary in gear.bases:
			known[base.id] = true
	for entry: Dictionary in value.legendaries:
		if not known.has(entry.base_id) or str(entry.name).strip_edges().is_empty() or int(entry.level) < 1:
			return "%s needs a valid base, a name, and a positive level." % entry.id
		var weight := float(entry.get("drop_weight", 1.0))
		if not is_finite(weight) or weight < 0.0001:
			return "%s needs a legendary drop weight of at least 0.0001." % entry.name
		var tier := int(entry.get("affix_tier", 4))
		if tier < 1 or tier > AffixRecords.tier_levels.size():
			return "%s needs an existing fixed stat tier." % entry.name
		var ranges: Dictionary = entry.get("stat_ranges", {})
		for stat: String in ranges:
			var bounds: Variant = ranges[stat]
			if not entry.stats.has(stat) or not bounds is Vector2 or not bounds.is_finite() or bounds.x > bounds.y:
				return "%s has an invalid roll range for %s." % [entry.name, stat.capitalize()]
	return ""


static func _check_loot(value: Resource) -> String:
	for source: String in value.item_profiles:
		var profile: Dictionary = value.item_profiles[source]
		var minimum := String(profile.get("minimum", "normal"))
		if minimum not in MINIMUM_RARITIES:
			return "%s has an unrecognized minimum rarity." % source.capitalize()
		var magic := float(profile.get("magic", 0.0))
		var rare := float(profile.get("rare", 0.0))
		if not _probability(magic) or not _probability(rare) or (minimum == "normal" and magic + rare > 1.000001):
			return "%s magic and rare probabilities share one roll and must total at most 100 percent." % source.capitalize()
		if not _probability(float(profile.get("legendary", 0.0))):
			return "%s legendary probability must be between 0 and 100 percent." % source.capitalize()
	for rarity: String in value.card_chances:
		if not _probability(float(value.card_chances[rarity])):
			return "%s card drop probability must be between 0 and 100 percent." % rarity.capitalize()
	return ""


static func _check_player(value: Resource) -> String:
	if value.life_by_level.is_empty():
		return "Player progression needs at least one Life point."
	var previous := 0.0
	for point: Vector2 in value.life_by_level:
		if point.x <= previous or point.y <= 0.0:
			return "Player Life curve levels must increase and Life must stay positive."
		previous = point.x
	if value.max_expected_enemies < value.base_expected_enemies:
		return "Maximum expected enemy count must be at least the baseline count."
	return ""


static func _valid_footprint(value: Vector2i) -> bool:
	return value.x >= 1 and value.x <= 12 and value.y >= 1 and value.y <= 6


static func _probability(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0

