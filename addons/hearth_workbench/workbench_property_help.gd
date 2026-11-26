@tool
extends RefCounted
## Help for values inside runtime dictionaries and for custom controls backed by exported properties.

const LABELS := {
	"vendor_max_depth": "Stock level cap",
	"vendor_price_per_depth": "Price increase per stock level",
	"condition_power": "Condition strength", "condition_time": "Condition duration",
	"crit_chance": "Critical chance", "crit_multiplier": "Critical damage",
	"max_health": "Maximum Life", "max_mana": "Maximum Mana", "max_stamina": "Maximum Stamina",
	"physical_dot_reduction": "Physical damage over time reduction", "summon_seconds": "Summon duration",
}
const FIELDS := {
	"id": "Stable record ID used by saved data and references.",
	"name": "Name shown in the inventory and item labels.",
	"type": "Item family. It determines the default footprint, icon, equipment fit, and combat behavior.",
	"slot": "Equipment slot this family can use.",
	"two_handed": "Occupies both hands while equipped and uses the two-handed combat rules.",
	"base_id": "Base item whose family, inventory footprint, and core behavior the legendary inherits.",
	"side": "Whether the affix occupies a prefix or suffix slot.",
	"slots": "Equipment slots allowed to roll this affix. Leave every slot clear to allow all slots.",
	"level": "Earliest item level at which this record becomes eligible.",
	"minimum_depth": "Minimum reward level for this card in the card reward table.",
	"rarity": "Card rarity used by enemy drop weights and card presentation.",
	"size": "Inventory footprint in cells. Width is horizontal and height is vertical.",
	"weight": "Relative weight among eligible options. A weight of zero excludes this record from the roll.",
	"minimum": "Guaranteed minimum rarity for gear from this source. Higher rarities can still roll.",
	"multiplier": "Multiplies the affix's base stat roll at this tier. A value of 1 keeps the base roll.",
	"legendary_card_eligibility": "Independent percent chance that each otherwise eligible legendary enters the card pool before rarity weights are rolled.",
	"vendor_upgrade_level": "Player level that unlocks the vendor's higher-level gear catalogue.",
	"vendor_rare_chance": "Percent chance a stock roll creates a rare item.",
	"vendor_max_depth": "Highest level used to calculate merchant stock levels and prices.",
	"vendor_price_per_depth": "Percentage of the base price added for each eligible level above 1, up to the stock level cap.",
	"drop_weight": "Relative weight among eligible legendaries after legendary rarity rolls. The default is 1 and the minimum is 0.0001.",
	"effect": "Special behavior granted by equipping this legendary. An empty effect grants only the item stats.",
	"affix_id": "Affix applied by the blacksmith when using this recipe.",
	"affix_tier": "Displayed tier for the legendary's exclusive stat lines. Tier 1 is strongest. The authored values and ranges below control the actual rolls.",
	"description": "Player-facing text explaining this record.",
	"flat": "Flat damage added after multiplying average weapon damage.",
	"power": "Multiplies average weapon damage before the flat bonus. A value of 2 deals twice the average weapon damage plus that bonus.",
	"heal": "Percentage of maximum Life restored immediately when played.",
	"radius": "Distance in meters from the player within which this card can hit enemies. Solid world geometry can block a hit.",
	"protection": "Percentage by which incoming damage decreases during the protection window.",
	"protection_time": "How many seconds the damage reduction lasts after playing the card.",
	"strike_bonus": "Percentage increase to damage while the card has empowered hits remaining.",
	"strike_time": "How many seconds the card waits for its empowered hits before they expire.",
	"strikes": "Maximum number of landed weapon attacks that can consume the card's bonus before it expires.",
	"timed_bonus": "Percentage increase to attack damage during the card's active window.",
	"timed_duration": "How many seconds the timed damage bonus lasts.",
	"element": "Damage element of the card's hit. It determines which enemy mitigation applies.",
	"condition": "Status effect applied to surviving targets struck by the card.",
	"condition_time": "Duration of the status applied by the card, in seconds before target adjustments.",
	"condition_power": "Potency of the status effect applied to a target. For Chill, a value of 0.5 means a 50% movement slow before target adjustments.",
	"stun_buildup": "Points added to the target's stun buildup on a qualifying damaging hit.",
	"stamina": "Restores the player's full Stamina immediately when enabled.",
	"summon_skeletons": "Spawns the Oathbound Three and replaces an existing active party of summoned skeletons.",
	"summon_seconds": "How many seconds the summoned Oathbound Three remain active.",
	"play_sound": "Sound cue played when the card is used. An empty cue uses the sound for its card effect.",
}
const STATS := {
	"max_health": "Life points added to maximum Life.",
	"max_mana": "Mana points added to maximum Mana.",
	"max_stamina": "Stamina points added to maximum Stamina.",
	"armor": "Armour rating used to mitigate physical hits.",
	"ward": "Points added to maximum Ward. Available Ward absorbs damage before it reaches Life.",
	"damage_min": "Damage at the low end of the physical hit roll.",
	"damage_max": "Damage at the high end of the physical hit roll.",
	"attack_speed": "Attack speed bonus in percentage points. The effective attack rate also respects the Attack tempo cap.",
	"crit_chance": "Critical hit chance in percentage points.",
	"crit_multiplier": "Critical hit damage bonus in percentage points, added to the attack type's base critical multiplier.",
	"move_speed": "Movement speed bonus in percentage points.",
	"life_regen": "Life points regenerated per second.",
	"mana_regen": "Mana points regenerated per second.",
	"life_leech": "Percentage of damage dealt by eligible hits recovered as Life.",
	"life_on_kill": "Life points restored for a credited kill.",
	"mana_on_kill": "Mana points restored for a credited kill.",
	"dodge_chance": "Dodge chance in percentage points for eligible hits.",
	"cooldown_recovery": "Cooldown recovery speed bonus in percentage points. Higher recovery shortens ability cooldowns.",
	"loot_rarity": "Rarity bonus in percentage points applied to eligible gear rarity rolls.",
	"gold_find": "Percentage bonus to gold awarded from eligible loot.",
	"stun_power": "Percentage bonus to stun duration when this actor inflicts a stun.",
	"bleed_chance": "Use percentage points to set the chance for an eligible physical hit to apply a bleed.",
	"bleed_damage": "Percentage bonus to Bleed damage.",
	"damage_over_time": "Percentage bonus to damage dealt over time.",
	"physical_dot_reduction": "Percentage by which incoming physical damage over time is reduced.",
}
const MELEE_FIELDS := {
	"reach_target": "Target distance from gameplay aim in meters. The actual sweep length depends on the weapon pose and the reach assist cap.",
	"reach_assist": "Maximum distance in meters added beyond the scaled animated trace span. Increase this when the sweep is already at its assist cap.",
	"width": "Full width of the enemy and prop sweep box in meters. The physical wall contact has a separate footprint.",
	"height": "Full height of the enemy and prop sweep box in meters.",
	"length_scale": "Multiplies the animated span before reach assistance is added.",
	"damage": "Mass budget for damage at reference attack power. A new enemy's damage checks the mass already spent before adding that enemy.",
	"stagger": "Mass budget for stagger at reference attack power. This can let a sweep stagger foes after it has spent its damage budget.",
	"slides_armor": "Allow a swing to continue through armor while its remaining contact budget permits.",
}
const ARCHETYPES := {"physical": "Physical", "fire": "Fire", "cold": "Cold",
	"lightning": "Lightning", "poison": "Poison"}
const UNITS := {"s": "seconds", "m": "meters", "m/s": "meters per second",
	"%": "percentage points", "°": "degrees", "°/s": "degrees per second"}

static var _script_docs := {}


static func property_label(key: String) -> String:
	return LABELS.get(key, key.get_slice("/", key.get_slice_count("/") - 1).capitalize())


static func field(key: String, scope: String, kind: StringName, source: Object = null) -> String:
	match kind:
		&"families":
			return MELEE_FIELDS.get(key, "Saved %s for this weapon profile." % property_label(key).to_lower())
		&"base_footprints":
			return "Overrides this item's family footprint. Width and height are measured in inventory cells."
		&"power_by_level":
			return "This level's attack and defense scaling factors. A factor of 1 preserves the base value. Intermediate item levels interpolate between points."
		&"life_by_level":
			return "Base maximum Life by character level. Between authored points, Life is interpolated."
		&"card_chances":
			return "Percent chance an enemy of this rarity rolls an eligible card. Card availability and rarity weights are checked after this roll."
		&"card_weights":
			return "Relative weight of %s cards among cards eligible for this enemy's drop. Zero excludes this rarity." % key
		&"item_profiles":
			if key in ["legendary", "rare", "magic"]:
				return "Base percent chance to roll %s gear from this source. Item level and Loot Rarity modify this chance." % key
		&"tier_levels":
			if key == "level":
				return "Earliest item level eligible for this affix tier. Tier 1 is strongest."
		&"materials":
			if key == "level":
				return "First reward level where this material enters random reward pools. Enemy-assigned material drops use their own roll."
	if scope == "materials":
		return "Number of units of this material consumed when crafting the recipe."
	if scope in ["stats", "implicit", "stat_ranges"]:
		return _stat_help(key, scope)
	if key == "name" and kind == &"cards":
		return "Name shown on the card and in the Combat Log."
	if key == "level" and kind == &"recipes":
		return "Earliest item level at which this recipe can be applied."
	var specific: String = FIELDS.get(key, "")
	if not specific.is_empty():
		return specific
	if source != null:
		return for_property(source, key)
	return "Saved %s value for this record." % property_label(key).to_lower()


static func for_property(object: Object, key: String, hint_string := "") -> String:
	var entry := {}
	if object != null:
		for property: Dictionary in object.get_property_list():
			if property.name == key:
				entry = property
				break
	var help := _authored_help(object.get_script() as Script, key) if object != null else ""
	if help.is_empty():
		help = FIELDS.get(key, "")
	if help.is_empty():
		help = "%s for this %s." % [property_label(key), _source_label(object)]
	if hint_string.is_empty():
		hint_string = entry.get("hint_string", "")
	if entry.get("hint") == PROPERTY_HINT_RANGE:
		var range_help := _range_help(hint_string)
		if not range_help.is_empty():
			help += "\n" + range_help
	return help


static func _stat_help(key: String, scope: String) -> String:
	var help: String = STATS.get(key, "")
	var attribute := key.get_slice("_", 0)
	if help.is_empty() and attribute in ARCHETYPES:
		if key.ends_with("_damage"):
			help = "Flat %s damage added to compatible hits." % ARCHETYPES[attribute]
		elif key.ends_with("_resist"):
			help = "Resistance to %s damage in percentage points." % ARCHETYPES[attribute]
	if help.is_empty():
		help = "%s applied by this record." % property_label(key)
	if scope == "implicit":
		help += " This is granted by the base item before affixes roll."
	return help


static func _source_label(object: Object) -> String:
	if object == null:
		return "record"
	var script := object.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		return script.resource_path.get_file().get_basename().replace("_", " ")
	return object.get_class()


static func _authored_help(script: Script, key: String) -> String:
	while script != null:
		if script is GDScript:
			var docs := _read_script_docs(script)
			if docs.has(key):
				return docs[key]
		script = script.get_base_script()
	return ""


static func _read_script_docs(script: GDScript) -> Dictionary:
	var source := script.source_code
	var source_hash := source.hash()
	var cached: Array = _script_docs.get(script.resource_path, [])
	if not cached.is_empty() and cached[0] == source_hash:
		return cached[1]
	var comments := PackedStringArray()
	var docs := {}
	var declaration := RegEx.create_from_string("\\bvar\\s+([A-Za-z_][A-Za-z0-9_]*)\\b")
	var annotation_continues := false
	for raw: String in source.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("##"):
			comments.append(line.substr(2).strip_edges())
		elif line.begins_with("@export") or annotation_continues:
			var found := declaration.search(line)
			if found != null and not comments.is_empty():
				docs[found.get_string(1)] = " ".join(comments).replace("[code]", "").replace("[/code]", "")
				comments.clear()
			elif line.begins_with("@export_group") or line.begins_with("@export_subgroup") or line.begins_with("@export_category"):
				comments.clear()
			annotation_continues = not comments.is_empty()
		else:
			comments.clear()
			annotation_continues = false
	if not script.resource_path.is_empty():
		_script_docs[script.resource_path] = [source_hash, docs]
	return docs


static func _range_help(hint_string: String) -> String:
	var limits := hint_string.split(",", false)
	if limits.size() < 2:
		return ""
	var unit := ""
	for token: String in limits:
		if token.begins_with("suffix:"):
			var suffix := token.trim_prefix("suffix:")
			unit = " " + UNITS.get(suffix, suffix)
		elif token == "degrees" or token == "radians_as_degrees":
			unit = " degrees"
	if "or_greater" in limits and "or_less" in limits:
		return "Editor slider spans %s to %s%s. Typed values can extend beyond it." % [limits[0], limits[1], unit]
	if "or_greater" in limits:
		return "Editor minimum is %s%s. The slider ends at %s%s and accepts higher typed values." % [limits[0], unit, limits[1], unit]
	if "or_less" in limits:
		return "Editor maximum is %s%s. The slider starts at %s%s and accepts lower typed values." % [limits[1], unit, limits[0], unit]
	return "Editor range is %s to %s%s." % [limits[0], limits[1], unit]
