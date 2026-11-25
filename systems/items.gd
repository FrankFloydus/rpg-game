extends RefCounted

const LOOT := preload("res://data/items/loot_records.tres")
const ItemNames := preload("res://data/items/item_name_records.tres")

const BaseData = preload("res://data/items/bases.gd")
const AffixData = preload("res://data/items/affixes.gd")
const LegendaryData = preload("res://data/items/legendaries.gd")
const OriginalAffixes = preload("res://data/items/original_affix_ranges.gd")
const Progression = preload("res://systems/character_progression.gd")
const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const ITEM_BALANCE_VERSION := 5
const ITEM_LEVEL_POWER_BALANCE_VERSION := 3
const WEAPON_SLOTS := ["one_hand", "main_hand", "off_hand"]
const SUPPRESSED_DROPS := ["focus", "orb"]
const STAMINA_BALANCE_VERSION := 2
const FIRST_BALANCE_SENTRY_RANGES := {"of_the_sentry": {"block_chance": Vector2(2, 4)}}
const BASE_MELEE_CRITICAL_DAMAGE := 200.0
const BASE_SPELL_CRITICAL_DAMAGE := 150.0

const BASE_STATS := {
	"max_health": 24.0, "max_mana": 12.0, "max_stamina": 12.0, "armor": 0.0, "ward": 0.0,
	"damage_min": 0.0, "damage_max": 0.0, "attack_speed": 0.0,
	"crit_chance": 5.0, "crit_multiplier": BASE_MELEE_CRITICAL_DAMAGE, "move_speed": 0.0,
	"life_regen": 0.0, "mana_regen": 0.25, "life_leech": 0.0,
	"life_on_kill": 0.0, "mana_on_kill": 0.0,
	"fire_damage": 0.0, "cold_damage": 0.0, "lightning_damage": 0.0, "poison_damage": 0.0,
	"fire_resist": 0.0, "cold_resist": 0.0, "lightning_resist": 0.0, "poison_resist": 0.0,
	"dodge_chance": 0.0, "cooldown_recovery": 0.0,
	"loot_rarity": 0.0, "gold_find": 0.0, "stun_power": 0.0,
	"bleed_chance": 0.0, "bleed_damage": 0.0, "damage_over_time": 0.0,
	"physical_dot_reduction": 0.0,
}

const STAT_LABELS := {
	"max_health": "Maximum Life", "max_mana": "Maximum Mana", "max_stamina": "Maximum Stamina",
	"armor": "Armour", "ward": "Ward",
	"damage_min": "Minimum Physical Damage", "damage_max": "Maximum Physical Damage",
	"attack_speed": "Attack Speed", "crit_chance": "Critical Chance", "crit_multiplier": "Critical Damage",
	"move_speed": "Movement Speed", "life_regen": "Life Regeneration", "mana_regen": "Mana Regeneration",
	"life_leech": "Life Leech", "life_on_kill": "Life on Kill", "mana_on_kill": "Mana on Kill",
	"fire_damage": "Fire Damage", "cold_damage": "Cold Damage", "lightning_damage": "Lightning Damage",
	"poison_damage": "Poison Damage", "fire_resist": "Fire Resistance", "cold_resist": "Cold Resistance",
	"lightning_resist": "Lightning Resistance", "poison_resist": "Poison Resistance",
	"dodge_chance": "Dodge Chance", "cooldown_recovery": "Cooldown Recovery",
	"loot_rarity": "Loot Rarity", "gold_find": "Gold Find", "stun_power": "Stun Power",
	"bleed_chance": "Chance to Bleed on Hit", "bleed_damage": "Bleed Damage",
	"damage_over_time": "Damage over Time", "physical_dot_reduction": "Physical Damage over Time Reduction",
}

const PERCENT_STATS := [
	"attack_speed", "crit_chance", "crit_multiplier", "move_speed", "life_leech",
	"fire_resist", "cold_resist", "lightning_resist", "poison_resist",
	"dodge_chance", "cooldown_recovery", "loot_rarity", "gold_find", "stun_power",
	"bleed_chance", "bleed_damage", "damage_over_time", "physical_dot_reduction",
]
const REGEN_STATS := ["life_regen", "mana_regen"]
const DAMAGE_STATS := ["damage_min", "damage_max", "fire_damage", "cold_damage", "lightning_damage", "poison_damage"]
const DEFENSIVE_CORE_STATS := ["armor", "ward", "max_health", "max_stamina"]
static var VENDOR_UPGRADE_LEVEL: int:
	get:
		return LOOT.vendor_upgrade_level

static var DROP_CHANCE_MAX_DEPTH: int:
	get:
		return LOOT.chance_max_depth
# Gear, crafting part and key chances interpolate from Depth 1 to the authored depth cap.
static var ENEMY_DROP_CHANCES: Dictionary:
	get:
		return LOOT.enemy_chances
static var SIDE_CACHE_GEAR_CHANCE: float:
	get:
		return LOOT.side_cache_gear_chance
static var PROTECTED_COFFER_BONUS_DEPTH: int:
	get:
		return LOOT.protected_coffer_bonus_depth
static var PROTECTED_COFFER_BONUS_GEAR_CHANCE: float:
	get:
		return LOOT.protected_coffer_bonus_gear_chance

# The first two chances are mutually exclusive. The legendary chance is a separate gated roll.
static var DROP_PROFILES: Dictionary:
	get:
		return LOOT.item_profiles
const RARITY_COLORS := {
	"normal": Color("ded9cf"), "magic": Color("8db9f9"),
	"rare": Color("f2d68b"), "legendary": Color("ffac65"),
}


static func starter_weapon() -> Dictionary:
	var item := _make_item(_find_by_id(BaseData.BASES, "oath_blade"), 1, "normal", "starter_oath_blade")
	_refresh_item(item)
	return item


static func training_weapon_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for base: Dictionary in BaseData.BASES:
		var kind: Dictionary = BaseData.TYPES[base.type]
		if kind.slot in WEAPON_SLOTS:
			choices.append({"id": String(base.id), "name": String(base.name),
				"base_id": base.id, "type": base.type, "type_label": kind.name, "rarity": "normal"})
	for legendary: Dictionary in LegendaryData.DROPS:
		var base := _find_by_id(BaseData.BASES, legendary["base_id"])
		var kind: Dictionary = BaseData.TYPES[base.type]
		if kind.slot in WEAPON_SLOTS:
			choices.append({"id": String(legendary.id), "name": String(legendary.name),
				"base_id": base.id, "type": base.type, "type_label": kind.name, "rarity": "legendary"})
	return choices


static func training_weapon_preview(choice_id: String, requested_level := 1) -> Dictionary:
	return training_weapon_item(choice_id, "training_preview", requested_level)


static func training_weapon_item(choice_id: String, instance_id: String, requested_level := 1,
		rng: RandomNumberGenerator = null, loot_rarity := 0.0) -> Dictionary:
	var legendary := _find_by_id(LegendaryData.DROPS, choice_id)
	var base_id: String = legendary.get("base_id", choice_id)
	var base := _find_by_id(BaseData.BASES, base_id)
	if base.is_empty() or BaseData.TYPES[base.type].slot not in WEAPON_SLOTS:
		return {}
	if not legendary.is_empty():
		return _make_legendary(base, legendary, maxi(int(legendary.level), requested_level), instance_id, rng)
	var level := maxi(int(base.level), requested_level)
	if rng != null:
		# An explicit practice spawn uses the dungeon's magic-enemy drop profile.
		var rolled := roll_item(level, "magic", rng, loot_rarity, base)
		rolled["id"] = instance_id
		return rolled
	var item := _make_item(base, level, "normal", instance_id)
	_refresh_item(item)
	return item


static func canonical_footprint(item: Dictionary) -> Vector2i:
	return BaseData.footprint(str(item.get("base_id", "")), str(item.get("type", "")))


static func visible_name(item: Dictionary) -> String:
	return String(item.get("base_name", "Unknown Item")) if item.get("unidentified", false) else String(item.get("name", ""))


static func restore_item(saved: Dictionary) -> Dictionary:
	var item := saved.duplicate(true)
	if item.get("type", "") in WeaponRoles.ONE_HANDED_WEAPONS:
		item["slot"] = "one_hand"
	var version := int(item.get("balance_version", 0))
	if version >= ITEM_BALANCE_VERSION:
		return item
	if version >= STAMINA_BALANCE_VERSION or (
		version == 1 and item.get("stats") is Dictionary and not item["stats"].has("block_chance")
	):
		if version < ITEM_LEVEL_POWER_BALANCE_VERSION and _has_item_stat_parts(item):
			_apply_item_level_power(item)
		_restore_weapon_base_damage(item)
		_sync_item_stats(item)
		item["balance_version"] = ITEM_BALANCE_VERSION
		return item
	var base := _find_by_id(BaseData.BASES, str(item.get("base_id", "")))
	if base.is_empty() or not item.get("prefixes") is Array or not item.get("suffixes") is Array:
		_remove_old_block_stats(item)
		_sync_item_stats(item)
		return item
	if version == 1 and (not item.get("base_stats") is Dictionary or not item.get("implicit") is Dictionary):
		_remove_old_block_stats(item)
		_sync_item_stats(item)
		return item
	if version < 1:
		item["base_stats"] = base["stats"].duplicate()
		item["implicit"] = base.get("implicit", {}).duplicate()
		_restore_affix_rolls(item["prefixes"], AffixData.PREFIXES, OriginalAffixes.RANGES)
		_restore_affix_rolls(item["suffixes"], AffixData.SUFFIXES, OriginalAffixes.RANGES)
	else:
		var implicit: Dictionary = base.get("implicit", {})
		if implicit.has("max_stamina") and item.get("implicit") is Dictionary:
			item["implicit"]["max_stamina"] = implicit["max_stamina"]
		_restore_affix_rolls(item["suffixes"], AffixData.SUFFIXES, FIRST_BALANCE_SENTRY_RANGES)
	var legendary := _find_by_id(LegendaryData.DROPS, str(item.get("legendary_id", "")))
	if version < 1 and not legendary.is_empty():
		item["legendary_stats"] = legendary["stats"].duplicate()
	elif not legendary.is_empty() and legendary["stats"].has("max_stamina") and item.get("legendary_stats") is Dictionary:
		item["legendary_stats"]["max_stamina"] = legendary["stats"]["max_stamina"]
	_remove_old_block_stats(item)
	_apply_item_level_power(item)
	_restore_weapon_base_damage(item)
	_sync_item_stats(item)
	item["balance_version"] = ITEM_BALANCE_VERSION
	return item


static func _restore_weapon_base_damage(item: Dictionary) -> void:
	var type := str(item.get("type", ""))
	if WeaponRoles.family(type).is_empty() or not item.get("base_stats") is Dictionary:
		return
	var base := _find_by_id(BaseData.BASES, str(item.get("base_id", "")))
	if base.is_empty():
		return
	var power := BaseData.power_at_item_level(int(item.get("item_level", 1))).x
	for stat in ["damage_min", "damage_max"]:
		if base.stats.has(stat):
			item.base_stats[stat] = float(base.stats[stat]) * power


static func _remove_old_block_stats(item: Dictionary) -> void:
	for section in ["base_stats", "implicit", "legendary_stats", "stats"]:
		var stats: Variant = item.get(section)
		if stats is Dictionary:
			stats.erase("block_chance")
	for side in ["prefixes", "suffixes"]:
		var rolls: Variant = item.get(side)
		if rolls is Array:
			for roll: Variant in rolls:
				if roll is Dictionary and roll.get("stats") is Dictionary:
					roll["stats"].erase("block_chance")


static func _restore_affix_rolls(saved_rolls: Array, definitions: Array, old_ranges: Dictionary) -> void:
	for roll: Variant in saved_rolls:
		if not roll is Dictionary or not roll.get("stats") is Dictionary:
			continue
		var id := str(roll.get("id", ""))
		var tier := AffixData.LEVELS.size() - int(roll.get("tier", 0))
		var definition := _find_by_id(definitions, id)
		var bounds: Dictionary = old_ranges.get(id, {})
		if definition.is_empty() or bounds.is_empty() or tier < 0 or tier >= OriginalAffixes.TIER_MULTIPLIERS.size():
			continue
		var quality := 0.0
		var count := 0
		var stats: Dictionary = roll.get("stats", {})
		for stat: String in bounds:
			if not stats.has(stat):
				continue
			var range_bounds: Vector2 = bounds[stat]
			var magnitude := float(stats[stat]) / float(OriginalAffixes.TIER_MULTIPLIERS[tier])
			quality += clampf(inverse_lerp(range_bounds.x, range_bounds.y, magnitude), 0.0, 1.0)
			count += 1
		if count > 0:
			var balanced := _make_affix(definition, tier, quality / count)
			stats.merge(balanced["stats"], true)


static func enemy_drop_chance(depth: int, source: String, reward: String) -> float:
	var profile: Dictionary = ENEMY_DROP_CHANCES.get(source, ENEMY_DROP_CHANCES["normal"])
	var bounds: Vector2 = profile[reward]
	var progression := inverse_lerp(1.0, float(DROP_CHANCE_MAX_DEPTH), clampf(depth, 1, DROP_CHANCE_MAX_DEPTH))
	return lerpf(bounds.x, bounds.y, progression)


static func roll_item(level: int, source: String, rng: RandomNumberGenerator, loot_rarity: float = 0.0,
		selected_base: Dictionary = {}) -> Dictionary:
	level = maxi(1, level)
	var profile: Dictionary = DROP_PROFILES.get(source, DROP_PROFILES["normal"])
	var depth_bonus := 1.0 + 0.025 * mini(level - 1, 20)
	var rarity_multiplier := clampf((1.0 + loot_rarity / 100.0) * depth_bonus, 0.5, 3.0)
	if level >= 4 and rng.randf() < float(profile["legendary"]) * sqrt(rarity_multiplier):
		var legendary := _roll_legendary(level, rng, selected_base)
		if not legendary.is_empty():
			return legendary
	var rarity: String = profile.get("minimum", "normal")
	if rarity != "rare":
		var rare_chance := minf(0.8, float(profile.get("rare", 0.0)) * rarity_multiplier)
		var magic_chance := minf(1.0 - rare_chance, float(profile.get("magic", 0.0)) * sqrt(rarity_multiplier))
		var roll := rng.randf()
		if roll < rare_chance:
			rarity = "rare"
		elif roll < rare_chance + magic_chance:
			rarity = "magic"
	var base := _roll_base(level, rng, "", false, true) if selected_base.is_empty() else selected_base
	return _roll_gear(base, level, rarity, rng)


static func roll_vendor(level: int, rng: RandomNumberGenerator, count: int = 10) -> Array[Dictionary]:
	var stock: Array[Dictionary] = []
	var staple_slots := ["main_hand", "chest", "helm", "boots", "off_hand"]
	var item_level := clampi(level, 1, LOOT.vendor_max_depth)
	var markup: float = 1.0 + LOOT.vendor_price_per_depth * float(item_level - 1)
	for index in range(maxi(0, count)):
		var slot := ""
		if index < staple_slots.size():
			slot = staple_slots[index]
		var rarity := "rare" if rng.randf() < LOOT.vendor_rare_chance else "magic"
		# Reserve appropriate upgrades in the staple slots. Other offers retain the full base pool.
		var recent_base := item_level >= VENDOR_UPGRADE_LEVEL and not slot.is_empty()
		var offer := _roll_gear(_roll_base(item_level, rng, slot, recent_base), item_level, rarity, rng)
		offer.price = roundi(float(offer.price) * markup)
		stock.append(offer)
	return stock


static func roll_secret_vendor(depth: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var rules := preload("res://data/secret_merchant_rules.tres")
	var highest := maxi(1, depth)
	var stock: Array[Dictionary] = []
	if rng.randf() < rules.legendary_chance:
		var legendary := _roll_legendary(highest, rng, {}, true)
		if not legendary.is_empty():
			legendary.price = ceili(float(legendary.price) * rules.legendary_price)
			stock.append(legendary)
	var varied_slots := ["main_hand", "chest", "ring", "belt", "boots"]
	for index in range(rules.stock_count - stock.size()):
		var slot: String = varied_slots[index] if index < varied_slots.size() else ""
		var level := rng.randi_range(maxi(1, highest - rules.item_level_window + 1), highest)
		var offer := _roll_gear(_roll_base(level, rng, slot, not slot.is_empty(), true), level, "rare", rng)
		offer.price = ceili(float(offer.price) * rules.rare_price)
		stock.append(offer)
	return stock


static func material_drop(level: int, rng: RandomNumberGenerator) -> String:
	var eligible: Array[String] = []
	for material_id: String in AffixData.MATERIALS:
		if int(AffixData.MATERIALS[material_id]["level"]) <= maxi(1, level):
			eligible.append(material_id)
	if eligible.is_empty():
		return ""
	return eligible[rng.randi_range(0, eligible.size() - 1)]


static func material_name(material_id: String) -> String:
	if AffixData.MATERIALS.has(material_id):
		return AffixData.MATERIALS[material_id]["name"]
	return material_id.replace("_", " ").capitalize()


static func recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(AffixData.RECIPES.duplicate(true))
	return result


static func can_craft(item: Dictionary, recipe_id: String, materials: Dictionary) -> bool:
	var recipe := _find_by_id(AffixData.RECIPES, recipe_id)
	if _craft_affix(item, recipe).is_empty():
		return false
	for material_id: String in recipe["materials"]:
		if int(materials.get(material_id, 0)) < int(recipe["materials"][material_id]):
			return false
	return true


static func craft(item: Dictionary, recipe_id: String) -> Dictionary:
	var recipe := _find_by_id(AffixData.RECIPES, recipe_id)
	var affix := _craft_affix(item, recipe)
	if affix.is_empty():
		return {}
	var result := item.duplicate(true)
	var field := _affix_field(recipe["side"])
	var installed: Array = result[field]
	var tier_index := _highest_affix_tier(int(item["item_level"]))
	installed.append(_make_affix(affix, tier_index, 0.75, int(item["item_level"])))
	if result["rarity"] == "normal":
		result["rarity"] = "magic"
	_refresh_item(result)
	return result


static func player_stats(equipment: Dictionary, progression: Progression = null) -> Dictionary:
	var totals := BASE_STATS.duplicate()
	if progression != null:
		totals["max_health"] = progression.max_life()
		totals["max_mana"] += progression.max_mana_bonus()
		totals["max_stamina"] += progression.max_stamina_bonus()
	var weapon: Dictionary = equipment.get("main_hand", {})
	var offhand: Dictionary = equipment.get("off_hand", {})
	if weapon.get("type", "") == "staff":
		totals["crit_multiplier"] = BASE_SPELL_CRITICAL_DAMAGE
	if weapon.is_empty() and offhand.get("type", "") not in WeaponRoles.ONE_HANDED_WEAPONS:
		totals["damage_min"] = 1.0
		totals["damage_max"] = 2.0
	for item: Dictionary in equipment.values():
		_merge_stats(totals, item.get("stats", {}))
	if WeaponRoles.can_dual_wield(str(weapon.get("type", "")), str(offhand.get("type", ""))):
		var primary_stats: Dictionary = weapon.get("stats", {})
		var secondary_stats: Dictionary = offhand.get("stats", {})
		for stat in DAMAGE_STATS:
			totals[stat] -= (float(primary_stats.get(stat, 0.0)) + float(secondary_stats.get(stat, 0.0))) * 0.5
	totals.erase("block_chance")
	return totals


static func critical_damage_for_attack(equipped_multiplier: float, weapon_type: String, melee: bool) -> float:
	var equipped_base := BASE_SPELL_CRITICAL_DAMAGE if weapon_type == "staff" else BASE_MELEE_CRITICAL_DAMAGE
	var attack_base := BASE_MELEE_CRITICAL_DAMAGE if melee else BASE_SPELL_CRITICAL_DAMAGE
	return attack_base + (equipped_multiplier - equipped_base)


static func legendary_effects(equipment: Dictionary) -> Array[String]:
	var effects: Array[String] = []
	for item: Dictionary in equipment.values():
		var effect: String = item.get("effect", "")
		if not effect.is_empty() and not effects.has(effect):
			effects.append(effect)
	return effects


static func physical_damage_after_armor(damage: float, armor: float) -> float:
	if damage <= 0.0:
		return 0.0
	var effective_armor := maxf(0.0, armor)
	var reduction := minf(0.9, effective_armor / (effective_armor + 5.0 * damage))
	return damage * (1.0 - reduction)


static func damage_after_resistance(damage: float, resistance: float) -> float:
	return maxf(0.0, damage) * (1.0 - clampf(resistance, -100.0, 75.0) / 100.0)


static func attack_interval(base_interval: float, bonus_attack_speed: float) -> float:
	return base_interval / maxf(0.25, 1.0 + bonus_attack_speed / 100.0)


static func item_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS["normal"])


static func stat_label(stat: String) -> String:
	return STAT_LABELS.get(stat, stat.replace("_", " ").capitalize())


static func stat_value(stat: String, value: float) -> String:
	var result := ("%.2f" % value).rstrip("0").rstrip(".")
	if stat in PERCENT_STATS:
		return result + "%"
	if stat in REGEN_STATS:
		return result + "/s"
	return result


static func physical_damage_range(minimum: float, maximum: float) -> String:
	return "%s–%s" % [stat_value("damage_min", minimum), stat_value("damage_max", maximum)]


static func tooltip(item: Dictionary, advanced: bool = false) -> String:
	if item.is_empty():
		return ""
	var lines: PackedStringArray = [visible_name(item), item_subtitle(item)]
	for section in tooltip_sections(item, advanced):
		if not str(section["caption"]).is_empty():
			lines.append(section["caption"])
		lines.append_array(section["lines"])
	return "\n".join(lines)


static func item_subtitle(item: Dictionary) -> String:
	var type: Dictionary = BaseData.TYPES.get(item["type"], {})
	return "%s %s  ·  Item level %d" % [str(item["rarity"]).capitalize(), type.get("name", "gear"), int(item["item_level"])]


static func tooltip_sections(item: Dictionary, advanced: bool = false) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	if item.get("unidentified", false):
		sections.append({"kind": "base", "caption": "", "lines": PackedStringArray(["Unidentified"]), "stats": PackedStringArray()})
		return sections
	var base_stats := _stat_section("base", "", item.get("base_stats", {}))
	if item["rarity"] in ["rare", "legendary"]:
		base_stats["lines"].insert(0, item["base_name"])
		base_stats["stats"].insert(0, "")
	if not base_stats["lines"].is_empty():
		sections.append(base_stats)
	var implicit := _stat_section("implicit", "Implicit", item.get("implicit", {}))
	if not implicit["lines"].is_empty():
		sections.append(implicit)

	var modifiers := _stat_section("affix", "", {})
	for side in ["prefix", "suffix"]:
		for affix: Dictionary in item.get(_affix_field(side), []):
			var section := _stat_section("affix", "", affix["stats"])
			if advanced:
				section["caption"] = "%s  ·  %s  ·  Tier %d" % [side.capitalize(), affix["name"], int(affix["tier"])]
				sections.append(section)
			else:
				modifiers["lines"].append_array(section["lines"])
				modifiers["stats"].append_array(section["stats"])
	var legendary := _stat_section("affix", "", item.get("legendary_stats", {}))
	modifiers["lines"].append_array(legendary["lines"])
	modifiers["stats"].append_array(legendary["stats"])
	if not modifiers["lines"].is_empty():
		sections.append(modifiers)
	var effect: String = item.get("effect", "")
	if not effect.is_empty():
		sections.append({
			"kind": "effect", "caption": effect.replace("_", " ").capitalize(),
			"lines": PackedStringArray([item["effect_description"]]),
		})
	return sections


static func item_comparison_deltas(equipped: Dictionary, compared: Dictionary) -> Dictionary:
	var previous: Dictionary = equipped.get("stats", {})
	var current: Dictionary = compared.get("stats", {})
	var changes := {}
	for stat: String in current:
		if previous.has(stat):
			var delta := float(current[stat]) - float(previous[stat])
			if not is_zero_approx(delta):
				changes[stat] = delta
	return changes


static func stat_lines(stats: Dictionary) -> PackedStringArray:
	return _stat_section("", "", stats)["lines"]


static func _stat_section(kind: String, caption: String, stats: Dictionary) -> Dictionary:
	var lines := PackedStringArray()
	var keys := PackedStringArray()
	var has_damage_range := stats.has("damage_min") and stats.has("damage_max")
	if has_damage_range:
		lines.append("%s Physical Damage" % physical_damage_range(stats["damage_min"], stats["damage_max"]))
		keys.append("damage_range")
	for stat: String in stats:
		if has_damage_range and stat in ["damage_min", "damage_max"]:
			continue
		var value := float(stats[stat])
		var sign_prefix := "+" if stat == "crit_multiplier" and value > 0.0 else ""
		lines.append("%s%s %s" % [sign_prefix, stat_value(stat, value), stat_label(stat)])
		keys.append(stat)
	return {"kind": kind, "caption": caption, "lines": lines, "stats": keys}


static func _roll_gear(base: Dictionary, level: int, rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	var item := _make_item(base, level, rarity, _generate_id(rng))
	if rarity == "magic":
		var both_sides := rng.randf() < 0.42
		var prefix_first := rng.randf() < 0.5
		if both_sides or prefix_first:
			item["prefixes"] = _roll_affixes(AffixData.PREFIXES, item["slot"], level, 1, rng)
		if both_sides or not prefix_first:
			item["suffixes"] = _roll_affixes(AffixData.SUFFIXES, item["slot"], level, 1, rng)
	elif rarity == "rare":
		item["prefixes"] = _roll_affixes(AffixData.PREFIXES, item["slot"], level, rng.randi_range(1, 3), rng)
		item["suffixes"] = _roll_affixes(AffixData.SUFFIXES, item["slot"], level, rng.randi_range(1, 3), rng)
		item["name"] = ItemNames.roll_rare_name(item["type"], rng)
		item["unidentified"] = true
	_refresh_item(item)
	return item


static func _roll_base(level: int, rng: RandomNumberGenerator, slot: String, recent_base: bool,
		dungeon_reward := false) -> Dictionary:
	var eligible: Array[Dictionary] = []
	var newest_base_level := 1
	for base: Dictionary in BaseData.BASES:
		var base_type: String = base["type"]
		var base_slot: String = BaseData.TYPES[base_type]["slot"]
		var matches := slot.is_empty() or base_slot == slot or (slot == "main_hand" and base_slot == "one_hand")
		if int(base["level"]) <= level and matches and (not dungeon_reward or base_type not in SUPPRESSED_DROPS):
			eligible.append(base)
			newest_base_level = maxi(newest_base_level, int(base["level"]))
	var weights := PackedFloat32Array()
	for base in eligible:
		var distance := newest_base_level - int(base["level"])
		weights.append(0.0 if recent_base and distance > 0 else 1.0 / (1.0 + 0.12 * distance * distance))
	return eligible[rng.rand_weighted(weights)]


static func _roll_legendary(level: int, rng: RandomNumberGenerator, selected_base: Dictionary,
		fixed_power := false) -> Dictionary:
	var available: Array[Dictionary] = []
	var weights := PackedFloat32Array()
	var selected_id := String(selected_base.get("id", ""))
	for drop: Dictionary in LegendaryData.DROPS:
		if int(drop["level"]) <= level and (selected_id.is_empty() or drop["base_id"] == selected_id):
			var candidate_base := _find_by_id(BaseData.BASES, str(drop.base_id))
			if not candidate_base.is_empty() and (not selected_id.is_empty() or candidate_base.type not in SUPPRESSED_DROPS):
				available.append(drop)
				weights.append(maxf(0.0001, float(drop.get("drop_weight", 1.0))))
	if available.is_empty():
		return {}
	var legendary := available[rng.rand_weighted(weights)]
	var base := _find_by_id(BaseData.BASES, legendary["base_id"])
	return _make_legendary(base, legendary, int(legendary.level) if fixed_power else level, _generate_id(rng), rng)


static func _make_legendary(base: Dictionary, legendary: Dictionary, level: int, id: String,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var item := _make_item(base, level, "legendary", id)
	item["legendary_id"] = legendary["id"]
	item["name"] = legendary["name"]
	item["legendary_stats"] = _legendary_stats(legendary, rng)
	item["legendary_affix_tier"] = int(legendary.get("affix_tier", 4))
	item["effect"] = legendary["effect"]
	item["effect_description"] = legendary["description"]
	_refresh_item(item)
	return item


static func _legendary_stats(legendary: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var stats: Dictionary = legendary.stats.duplicate()
	if rng == null:
		return stats
	var ranges: Dictionary = legendary.get("stat_ranges", {})
	for stat: String in stats:
		var bounds: Variant = ranges.get(stat)
		if not bounds is Vector2 or not bounds.is_finite():
			continue
		var lower := minf(bounds.x, bounds.y)
		var upper := maxf(bounds.x, bounds.y)
		if stat in ["life_regen", "mana_regen"]:
			stats[stat] = snappedf(rng.randf_range(lower, upper), 0.01)
		elif ceili(lower) <= floori(upper):
			stats[stat] = rng.randi_range(ceili(lower), floori(upper))
		else:
			stats[stat] = roundi((lower + upper) * 0.5)
	return stats


static func _roll_affixes(pool: Array, slot: String, level: int, count: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var eligible: Array[Dictionary] = []
	var weights := PackedFloat32Array()
	for affix: Dictionary in pool:
		if _matches_slot(affix, slot):
			eligible.append(affix)
			weights.append(float(affix["weight"]))
	var highest_tier := _highest_affix_tier(level)
	var chosen: Array[Dictionary] = []
	for index in range(mini(count, eligible.size())):
		var selected := rng.rand_weighted(weights)
		var tier := highest_tier
		while tier > 0 and rng.randf() < 0.30:
			tier -= 1
		chosen.append(_make_affix(eligible[selected], tier, rng.randf(), level))
		eligible.remove_at(selected)
		weights.remove_at(selected)
	return chosen


static func _highest_affix_tier(level: int) -> int:
	for index in range(AffixData.LEVELS.size() - 1, -1, -1):
		if level >= AffixData.LEVELS[index]:
			return index
	return 0


static func _make_affix(affix: Dictionary, tier_index: int, quality: float, item_level := 1) -> Dictionary:
	var stats := {}
	var power := Vector2.ONE.lerp(BaseData.power_at_item_level(item_level), 0.32)
	for stat: String in affix["stats"]:
		var bounds: Array = affix["stats"][stat]
		var magnitude := lerpf(float(bounds[0]), float(bounds[1]), quality) * float(AffixData.TIER_MULTIPLIERS[tier_index])
		magnitude *= _core_stat_multiplier(stat, power)
		if stat in DAMAGE_STATS:
			stats[stat] = magnitude
		else:
			stats[stat] = snappedf(magnitude, 0.1 if stat in REGEN_STATS else 1.0)
	return {
		"id": affix["id"], "name": affix["name"], "tier": AffixData.LEVELS.size() - tier_index,
		"stats": stats,
	}


static func _make_item(base: Dictionary, level: int, rarity: String, id: String) -> Dictionary:
	var type: Dictionary = BaseData.TYPES[base["type"]]
	var size := BaseData.footprint(base["id"], base["type"])
	var item := {
		"id": id, "base_id": base["id"], "base_name": base["name"], "name": base["name"],
		"balance_version": ITEM_BALANCE_VERSION,
		"type": base["type"], "slot": type["slot"], "width": size.x, "height": size.y,
		"two_handed": type.get("two_handed", false), "rarity": rarity, "item_level": level,
		"base_stats": base["stats"].duplicate(), "implicit": base.get("implicit", {}).duplicate(),
		"prefixes": [], "suffixes": [], "effect": "", "effect_description": "",
	}
	_apply_item_level_power(item)
	return item


static func _apply_item_level_power(item: Dictionary) -> void:
	var power := BaseData.power_at_item_level(int(item.get("item_level", 1)))
	if power == Vector2.ONE:
		return
	for section in ["base_stats", "implicit"]:
		var stats: Dictionary = item[section]
		for stat: String in stats:
			var multiplier := _core_stat_multiplier(stat, power)
			if not is_equal_approx(multiplier, 1.0):
				var magnitude := float(stats[stat]) * multiplier
				stats[stat] = magnitude if stat in DAMAGE_STATS else snappedf(magnitude, 1.0)


static func _core_stat_multiplier(stat: String, power: Vector2) -> float:
	if stat in DAMAGE_STATS:
		return power.x
	if stat in DEFENSIVE_CORE_STATS:
		return power.y
	return 1.0


static func _combined_stats(item: Dictionary) -> Dictionary:
	var stats: Dictionary = item["base_stats"].duplicate()
	_merge_stats(stats, item["implicit"])
	for affix: Variant in item["prefixes"] + item["suffixes"]:
		if affix is Dictionary and affix.get("stats") is Dictionary:
			_merge_stats(stats, affix["stats"])
	_merge_stats(stats, item.get("legendary_stats", {}))
	return stats


static func _has_item_stat_parts(item: Dictionary) -> bool:
	return (item.get("base_stats") is Dictionary and item.get("implicit") is Dictionary
		and item.get("prefixes") is Array and item.get("suffixes") is Array)


static func _whole_damage_stats(stats: Dictionary) -> void:
	for stat: String in DAMAGE_STATS:
		if stats.has(stat):
			var value := float(stats[stat])
			stats[stat] = maxi(1, roundi(value)) if value > 0.0 else roundi(value)


static func _sync_item_stats(item: Dictionary) -> void:
	for section in ["base_stats", "implicit", "legendary_stats"]:
		var stats: Variant = item.get(section)
		if stats is Dictionary:
			_whole_damage_stats(stats)
	for side in ["prefixes", "suffixes"]:
		var rolls: Variant = item.get(side)
		if rolls is Array:
			for roll: Variant in rolls:
				if roll is Dictionary and roll.get("stats") is Dictionary:
					_whole_damage_stats(roll["stats"])
	if _has_item_stat_parts(item):
		item["stats"] = _combined_stats(item)
	var totals: Variant = item.get("stats")
	if totals is Dictionary:
		_whole_damage_stats(totals)


static func _refresh_item(item: Dictionary) -> void:
	_sync_item_stats(item)
	var prefixes: Array = item["prefixes"]
	var suffixes: Array = item["suffixes"]
	var explicit_count := prefixes.size() + suffixes.size()
	var sale_value := 3 + int(item["item_level"]) * 2 + explicit_count * 3
	if item["rarity"] == "magic":
		var name_parts := PackedStringArray()
		if not prefixes.is_empty():
			name_parts.append(prefixes[0]["name"])
		name_parts.append(item["base_name"])
		if not suffixes.is_empty():
			name_parts.append(suffixes[0]["name"])
		item["name"] = " ".join(name_parts)
	elif item["rarity"] == "legendary":
		sale_value += 60
	item["gold_value"] = sale_value
	item["price"] = sale_value * 3 + 9


static func _craft_affix(item: Dictionary, recipe: Dictionary) -> Dictionary:
	if item.is_empty() or recipe.is_empty() or item.has("supply_kind") or item.get("unidentified", false) \
			or item["rarity"] == "legendary":
		return {}
	var side: String = recipe["side"]
	var pool := AffixData.PREFIXES if side == "prefix" else AffixData.SUFFIXES
	var affix := _find_by_id(pool, recipe["affix_id"])
	if affix.is_empty() or not _matches_slot(affix, item["slot"]):
		return {}
	var installed: Array = item[_affix_field(side)]
	var limit := 3 if item["rarity"] == "rare" else 1
	if installed.size() >= limit or not _find_by_id(installed, affix["id"]).is_empty():
		return {}
	return affix


static func _matches_slot(affix: Dictionary, slot: String) -> bool:
	return not affix.has("slots") or slot in affix["slots"]


static func _affix_field(side: String) -> String:
	return "prefixes" if side == "prefix" else "suffixes"


static func _merge_stats(destination: Dictionary, source: Dictionary) -> void:
	for stat: String in source:
		destination[stat] = float(destination.get(stat, 0.0)) + float(source[stat])


static func _find_by_id(entries: Array, id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry["id"] == id:
			return entry
	return {}


static func _generate_id(rng: RandomNumberGenerator) -> String:
	return "%08x%08x" % [rng.randi(), rng.randi()]
