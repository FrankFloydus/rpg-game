@tool
extends RefCounted
## Categories point to the same resources the game reads when it starts.

const BobStyle := preload("res://player/weapon_sway/weapon_bob_style.gd")
const HitShake := preload("res://data/weapon_hit_shake.gd")
const GEAR := "res://data/items/gear_records.tres"
const ITEM_NAMES := "res://data/items/item_name_records.tres"
const INVENTORY_ITEM_STYLE := "res://data/inventory_item_style.tres"
const AFFIXES := "res://data/items/affix_records.tres"
const LEGENDARIES := "res://data/items/legendary_records.tres"
const LOOT := "res://data/items/loot_records.tres"
const PLAYER := "res://data/player_progression_records.tres"
const ENEMIES := "res://combat/enemies/enemy_scaling.tres"
const COMBAT_LIFETIMES := "res://data/combat_lifetime_rules.tres"
const COMBAT_FEEDBACK := "res://data/combat_feedback.tres"
const IMPACT_FEEDBACK := "res://data/impact_feedback.tres"
const STAMINA := "res://data/stamina_rules.tres"
const TELEGRAPH_TIMING := "res://data/telegraph_rules.tres"
const ATTACK_TEMPO := "res://data/attack_tempo.tres"
const WEAPON_DAMAGE := "res://data/player_weapon_balance.tres"
const MELEE_CONTACT := "res://data/melee_contact.tres"
const WEAPON_HIT_SHAKE := "res://data/weapon_hit_shake.tres"
const DEFENSIVE_LEGENDARIES := "res://data/defensive_legendary_rules.tres"
const WEAPON_LEGENDARIES := "res://data/weapon_legendary_rules.tres"
const CASTER_LEGENDARIES := "res://data/caster_legendary_rules.tres"
const SCREEN_BLOOD := "res://data/screen_blood_rules.tres"
const ENEMY_RARITY_STYLE := "res://data/enemy_rarity_style.tres"
const SOUND_CATALOGUE := "res://assets/audio/sound_catalogue.tres"
const WEAPON_MOTION := "res://player/weapon_sway/default_weapon_motion.tres"
const WEAPON_BOB_STYLES := "res://player/weapon_sway/styles"
const WEAPON_SCENES := "res://player/weapons"
const PLAYER_SCENE := "res://player/player.tscn"
const ENEMY_SCENES := "res://combat/enemies"
const EFFECTS := "res://combat/effects"
const ABILITIES := "res://combat/abilities"

const GROUPS := [
	{"name": "Weapons & Player", "categories": [
		{"name": "Weapon scenes and animations", "label": "Weapons",
			"description": "Weapon scenes, attack clips, combo timing, and per-weapon impact shake.",
			"directory": WEAPON_SCENES, "scenes": true},
		{"name": "Attack timing", "label": "Attack tempo",
			"description": "The cap and modifiers that convert authored attack timings into gameplay time.",
			"path": ATTACK_TEMPO},
		{"name": "Weapon damage", "label": "Weapon damage",
			"description": "Damage shares for charged two-handers, cleaves, and forked staff bolts.",
			"path": WEAPON_DAMAGE},
		{"name": "Melee contact profiles", "label": "Melee contact",
			"description": "Weapon sweep reach and cleave budgets for light and charged attacks.",
			"path": MELEE_CONTACT, "field": &"families"},
		{"name": "Shared melee contact rules", "label": "Melee rules",
			"description": "Contact angles, downcut targeting, refuge sweep size, and cleave power and mass.",
			"path": MELEE_CONTACT},
		{"name": "Player movement and charge", "label": "Movement & charge",
			"nav_label": "Move & charge",
			"description": "Player movement speeds and the shared attack input and charge settings.",
			"path": PLAYER_SCENE, "scene": true},
		{"name": "Stamina and guard", "label": "Stamina & guard",
			"description": "Stamina, blocking costs, guard breaks, and recovery.",
			"path": STAMINA},
		{"name": "First-person weapon motion", "label": "First-person motion",
			"nav_label": "First-person rig",
			"description": "Shared first-person sway, step motion, and movement response.",
			"path": WEAPON_MOTION},
		{"name": "Weapon bob styles", "label": "Motion styles",
			"description": "Reusable weapon movement profiles assigned to weapon scenes.",
			"directory": WEAPON_BOB_STYLES, "class_name": "WeaponBobStyle"},
		{"name": "Defensive legendary effects", "label": "Legendary defense",
			"nav_label": "Legendary guard",
			"description": "Legendary perks triggered by blocks, stuns, and incoming damage.",
			"path": DEFENSIVE_LEGENDARIES},
		{"name": "Legendary weapon effects", "label": "Legendary strikes",
			"description": "Legendary perks triggered by melee hits, attack chains, and tempo.",
			"path": WEAPON_LEGENDARIES},
		{"name": "Legendary caster effects", "label": "Legendary casting",
			"description": "Legendary perks tied to staff hits and abilities.",
			"path": CASTER_LEGENDARIES},
	]},
	{"name": "Encounters", "categories": [
		{"name": "Enemy scenes and stats", "label": "Enemy scenes",
			"description": "Enemy health, defenses, movement, and ability references by archetype.",
			"directory": ENEMY_SCENES, "scenes": true, "nested": true},
		{"name": "Enemy scaling", "label": "Enemy scaling",
			"description": "Enemy Life, damage, speed, attack timing, and projectile scaling by level.",
			"path": ENEMIES},
		{"name": "Combat lifetimes", "label": "Combat lifetimes",
			"description": "Persistence of fallen enemies and the Training Ground's weapon trace overlay.",
			"path": COMBAT_LIFETIMES},
		{"name": "Abilities", "label": "Abilities",
			"description": "Player and enemy moves, including attack footprints, timing, and damage.",
			"directory": ABILITIES, "class_name": "AbilityDefinition"},
		{"name": "Effects", "label": "Status effects",
			"description": "Rules for status effects applied by combat and abilities.",
			"directory": EFFECTS, "class_name": "EffectDefinition"},
		{"name": "Floor warning timing", "label": "Floor warnings",
			"description": "Player escape time and timing limits for ground warnings.",
			"path": TELEGRAPH_TIMING},
	]},
	{"name": "Gear", "categories": [
		{"name": "Gear bases", "label": "Base items",
			"description": "Base item names, level requirements, and starting stats.",
			"path": GEAR, "field": &"bases"},
		{"name": "Item families", "label": "Item families",
			"description": "Shared equipment slots and footprints for item families.",
			"path": GEAR, "field": &"types"},
		{"name": "Base footprints", "label": "Base item footprints",
			"description": "Inventory size overrides for individual gear bases.",
			"path": GEAR, "field": &"base_footprints"},
		{"name": "Legendary items", "label": "Legendary items",
			"description": "Legendary bases, stat ranges, weights, and equipped effects.",
			"path": LEGENDARIES, "field": &"legendaries"},
		{"name": "Inventory item appearance", "label": "Inventory appearance",
			"description": "Inventory slot colors, outlines, item highlights, and placement feedback.",
			"path": INVENTORY_ITEM_STYLE},
		{"name": "Rare name prefixes", "label": "Rare name prefixes",
			"description": "Word pools used to generate display names for rare items.",
			"path": ITEM_NAMES, "field": &"rare_prefixes"},
		{"name": "Rare name suffixes", "label": "Rare name suffixes",
			"description": "Word pools that supply the final part of generated rare item names.",
			"path": ITEM_NAMES, "field": &"rare_suffixes"},
	]},
	{"name": "Affixes & Crafting", "categories": [
		{"name": "Prefixes", "label": "Prefix affixes",
			"description": "Allowed slots, weights, and base stat rolls for prefixes.",
			"path": AFFIXES, "field": &"prefixes"},
		{"name": "Suffixes", "label": "Suffix affixes",
			"description": "Allowed slots, weights, and base stat rolls for suffixes.",
			"path": AFFIXES, "field": &"suffixes"},
		{"name": "Affix tiers", "label": "Affix tiers",
			"description": "Minimum item levels and stat roll multipliers for each tier.",
			"path": AFFIXES, "field": &"tier_levels", "tier": true},
		{"name": "Crafting materials", "label": "Crafting materials",
			"description": "Ingredient names and the level at which they enter random reward pools.",
			"path": AFFIXES, "field": &"materials"},
		{"name": "Crafting recipes", "label": "Crafting recipes",
			"description": "Crafted affixes and their material costs.",
			"path": AFFIXES, "field": &"recipes"},
	]},
	{"name": "Loot & Merchants", "categories": [
		{"name": "Item rarity tables", "label": "Gear rarity",
			"description": "Rarity floors and upgrade odds by reward source.",
			"path": LOOT, "field": &"item_profiles"},
		{"name": "Hub merchant stock and prices", "label": "Hub merchant stock",
			"nav_label": "Hub merchant",
			"description": "The stock upgrade level, rarity, level cap, and level-based prices.",
			"path": LOOT, "fields": [&"vendor_upgrade_level", &"vendor_rare_chance", &"vendor_max_depth", &"vendor_price_per_depth"]},
	]},
	{"name": "Cards", "categories": [
		{"name": "Card definitions", "label": "Card definitions",
			"description": "Card effects, quantities, durations, and sound.",
			"path": LOOT, "field": &"cards"},
		{"name": "Card drop chances", "label": "Card drop odds",
			"description": "Chance for each enemy rarity to yield an eligible card in the card reward table.",
			"path": LOOT, "field": &"card_chances"},
		{"name": "Card rarity weights", "label": "Card rarity weights",
			"description": "Relative card rarity weights for eligible drops.",
			"path": LOOT, "field": &"card_weights"},
		{"name": "Legendary card eligibility",
			"description": "The independent eligibility roll for legendary cards.",
			"path": LOOT, "fields": [&"legendary_card_eligibility"]},
	]},
	{"name": "Progression", "categories": [
		{"name": "Player progression", "label": "Player progression",
			"description": "Experience requirements, attribute bonuses, and combat level-gap penalties.",
			"path": PLAYER},
		{"name": "Player Life by level", "label": "Life by level",
			"description": "Base maximum Life at each authored character level.",
			"path": PLAYER, "fields": [&"life_by_level"]},
		{"name": "Item power", "label": "Item power by level",
			"description": "Attack and defense scaling points by item level.",
			"path": GEAR, "fields": [&"power_by_level"]},
	]},
	{"name": "Feedback & Audio", "categories": [
		{"name": "Directional hit reactions", "label": "Enemy hit reactions",
			"description": "Enemy flinch directions and reactions to weapon and spell hits.",
			"path": COMBAT_FEEDBACK},
		{"name": "Overkill and severance", "label": "Overkill & severance",
			"description": "Body resistance, severance, corpse impulse, and live knockback.",
			"path": IMPACT_FEEDBACK},
		{"name": "Camera blood", "label": "Camera blood",
			"description": "Camera blood amounts and decay for qualifying hits.",
			"path": SCREEN_BLOOD},
		{"name": "Enemy rarity edge color", "label": "Enemy rarity outlines",
			"description": "Outline colors and presentation for enemy rarity.",
			"path": ENEMY_RARITY_STYLE},
		{"name": "Sound catalogue", "label": "Sound catalogue",
			"description": "Game sound cues, their clips, and the volume and pitch applied at playback.",
			"path": SOUND_CATALOGUE},
	]},
]


static func category_label(category: Dictionary) -> String:
	return category.get("label", category.get("name", ""))


static func category_id(category: Dictionary) -> String:
	var source: String = category.get("path", category.get("directory", ""))
	var field := String(category.get("field", ""))
	var fields: Array = category.get("fields", [])
	if not fields.is_empty():
		field = String(fields[0])
	return source if field.is_empty() else "%s#%s" % [source, field]


static func matches_category(category: Dictionary, query: String) -> bool:
	return query.nocasecmp_to(category.get("name", "")) == 0 \
		or query.nocasecmp_to(category_label(category)) == 0 or query == category_id(category)


static func weapon_hit_shake_source(scene_path: String) -> String:
	if scene_path.get_base_dir() == WEAPON_SCENES and HitShake.has_weapon(scene_path.get_file().get_basename()):
		return WEAPON_HIT_SHAKE
	return ""


static func describe_records(category: Dictionary, resource: Resource) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if category.get("scene", false):
		return [{"name": category.name, "id": "", "path": category.path, "scene": true}]
	if category.has("directory"):
		if category.get("nested", false):
			for folder: String in DirAccess.get_directories_at(category.directory):
				var path := "%s/%s/%s.tscn" % [category.directory, folder, folder]
				if ResourceLoader.exists(path, "PackedScene"):
					rows.append({"name": folder.capitalize(), "id": folder, "path": path, "scene": true})
			return rows
		for file: String in DirAccess.get_files_at(category.directory):
			var path := "%s/%s" % [category.directory, file]
			if category.get("scenes", false):
				if file.get_extension() == "tscn":
					var key := file.get_basename()
					rows.append({"name": key.capitalize(), "id": key, "path": path, "scene": true})
				continue
			if file.get_extension() != "tres":
				continue
			var entry := ResourceLoader.load(path) as Resource
			if entry == null or not _has_script_class(entry, category.class_name):
				continue
			if entry is BobStyle:
				var name := entry.resource_name if not entry.resource_name.is_empty() else file.get_basename().capitalize()
				rows.append({"name": name, "id": "", "path": path})
			else:
				rows.append({"name": str(entry.display_name), "id": str(entry.id), "path": path})
		return rows
	if resource == null:
		return rows
	var field: StringName = category.get("field", &"")
	if field.is_empty():
		return [{"name": category.name, "id": category.get("id", "")}]
	var entries: Variant = resource.get(field)
	if entries is Array:
		for index in entries.size():
			var value: Variant = entries[index]
			var name: String
			var id: String
			if category.get("tier", false):
				name = "Tier %d" % (entries.size() - index)
				id = "Level %d+" % value
			elif value is Vector2 or value is Vector3:
				name = "Level %d" % int(value.x)
				id = "Level point %d" % (index + 1)
			else:
				id = str(value.get("id", index))
				name = str(value.get("name", id.capitalize()))
			rows.append({"name": name, "id": id, "key": index})
	elif entries is Dictionary:
		for key: String in entries:
			var value: Variant = entries[key]
			var name := str(value.get("name", key.capitalize())) if value is Dictionary else key.capitalize()
			rows.append({"name": name, "id": key, "key": key})
	return rows


static func _has_script_class(entry: Resource, wanted: String) -> bool:
	var script := entry.get_script() as Script
	while script != null:
		if script.get_global_name() == wanted:
			return true
		script = script.get_base_script()
	return false

