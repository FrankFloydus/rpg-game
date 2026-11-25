@tool
extends RefCounted
## Categories point to the same resources the game reads when it starts.

const BobStyle := preload("res://player/weapon_sway/weapon_bob_style.gd")
const GEAR := "res://data/items/gear_records.tres"
const ITEM_NAMES := "res://data/items/item_name_records.tres"
const INVENTORY_ITEM_STYLE := "res://data/inventory_item_style.tres"
const AFFIXES := "res://data/items/affix_records.tres"
const LEGENDARIES := "res://data/items/legendary_records.tres"
const LOOT := "res://data/items/loot_records.tres"
const PLAYER := "res://data/player_progression_records.tres"
const ENEMIES := "res://combat/enemies/enemy_scaling.tres"
const DEPTH_DIFFICULTY := "res://data/depth_difficulty.tres"
const EXPEDITIONS := "res://data/expedition_rules.tres"
const BLOOD_ALTAR := "res://data/blood_altar_rules.tres"
const SECRET_MERCHANT := "res://data/secret_merchant_rules.tres"
const COMBAT_FEEDBACK := "res://data/combat_feedback.tres"
const IMPACT_FEEDBACK := "res://data/impact_feedback.tres"
const STAMINA := "res://data/stamina_rules.tres"
const TELEGRAPH_TIMING := "res://data/telegraph_rules.tres"
const ATTACK_TEMPO := "res://data/attack_tempo.tres"
const WEAPON_DAMAGE := "res://data/player_weapon_balance.tres"
const DEFENSIVE_LEGENDARIES := "res://data/defensive_legendary_rules.tres"
const WEAPON_LEGENDARIES := "res://data/weapon_legendary_rules.tres"
const CASTER_LEGENDARIES := "res://data/caster_legendary_rules.tres"
const LEGENDARY_EXPLORATION := "res://data/legendary_exploration_rules.tres"
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
	{"name": "Items", "icon": "BoxMesh", "categories": [
		{"name": "Inventory item appearance", "path": INVENTORY_ITEM_STYLE},
		{"name": "Gear bases", "path": GEAR, "field": &"bases"},
		{"name": "Item families", "path": GEAR, "field": &"types"},
		{"name": "Base footprints", "path": GEAR, "field": &"base_footprints"},
		{"name": "Legendary items", "path": LEGENDARIES, "field": &"legendaries"},
		{"name": "Legendary exploration effects", "path": LEGENDARY_EXPLORATION},
		{"name": "Crafting materials", "path": AFFIXES, "field": &"materials"},
		{"name": "Crafting recipes", "path": AFFIXES, "field": &"recipes"},
		{"name": "Rare name prefixes", "path": ITEM_NAMES, "field": &"rare_prefixes"},
		{"name": "Rare name suffixes", "path": ITEM_NAMES, "field": &"rare_suffixes"},
	]},
	{"name": "Affixes", "icon": "Add", "categories": [
		{"name": "Prefixes", "path": AFFIXES, "field": &"prefixes"},
		{"name": "Suffixes", "path": AFFIXES, "field": &"suffixes"},
		{"name": "Affix tiers", "path": AFFIXES, "field": &"tier_levels", "tier": true},
	]},
	{"name": "Loot", "icon": "RandomNumberGenerator", "categories": [
		{"name": "Enemy drops", "path": LOOT, "field": &"enemy_chances"},
		{"name": "Item rarity tables", "path": LOOT, "field": &"item_profiles"},
		{"name": "Card drop chances", "path": LOOT, "field": &"card_chances"},
		{"name": "Card rarity weights", "path": LOOT, "field": &"card_weights"},
		{"name": "Card definitions", "path": LOOT, "field": &"cards"},
		{"name": "Depth and chest rules", "path": LOOT, "fields": [
			&"chance_max_depth", &"side_cache_gear_chance", &"protected_coffer_bonus_depth",
			&"protected_coffer_bonus_gear_chance", &"legendary_card_eligibility"]},
		{"name": "Hub merchant stock and prices", "path": LOOT, "fields": [
			&"vendor_upgrade_level", &"vendor_rare_chance", &"vendor_max_depth", &"vendor_price_per_depth"]},
	]},
	{"name": "Level scaling", "icon": "Curve", "categories": [
		{"name": "Item power", "path": GEAR, "field": &"power_by_level"},
		{"name": "Enemy scaling", "path": ENEMIES},
		{"name": "Depth Difficulty", "id": "depth_difficulty", "path": DEPTH_DIFFICULTY},
		{"name": "Player Life by level", "path": PLAYER, "field": &"life_by_level"},
		{"name": "Player progression", "path": PLAYER},
	]},
	{"name": "Combat", "icon": "Animation", "categories": [
		{"name": "Abilities", "directory": ABILITIES, "class_name": "AbilityDefinition"},
		{"name": "Effects", "directory": EFFECTS, "class_name": "EffectDefinition"},
		{"name": "Enemy scenes and stats", "directory": ENEMY_SCENES, "scenes": true, "nested": true},
		{"name": "Directional hit reactions", "path": COMBAT_FEEDBACK},
		{"name": "Overkill and severance", "path": IMPACT_FEEDBACK},
		{"name": "Stamina and guard", "path": STAMINA},
		{"name": "Defensive legendary effects", "path": DEFENSIVE_LEGENDARIES},
		{"name": "Legendary weapon effects", "path": WEAPON_LEGENDARIES},
		{"name": "Legendary caster effects", "path": CASTER_LEGENDARIES},
		{"name": "Attack timing", "path": ATTACK_TEMPO},
		{"name": "Weapon damage", "path": WEAPON_DAMAGE},
		{"name": "Floor warning timing", "path": TELEGRAPH_TIMING},
		{"name": "Player movement and charge", "path": PLAYER_SCENE, "scene": true},
		{"name": "Camera blood", "path": SCREEN_BLOOD},
		{"name": "Enemy rarity edge color", "path": ENEMY_RARITY_STYLE},
		{"name": "First-person weapon motion", "path": WEAPON_MOTION},
		{"name": "Weapon bob styles", "directory": WEAPON_BOB_STYLES, "class_name": "WeaponBobStyle"},
		{"name": "Weapon scenes and animations", "directory": WEAPON_SCENES, "scenes": true},
	]},
	{"name": "Expeditions", "icon": "NavigationRegion3D", "categories": [
		{"name": "Expedition rules", "path": EXPEDITIONS},
		{"name": "Blood altar", "path": BLOOD_ALTAR},
		{"name": "Secret merchant", "path": SECRET_MERCHANT},
	]},
	{"name": "Audio", "icon": "AudioStreamPlayer", "categories": [
		{"name": "Sound catalogue", "path": SOUND_CATALOGUE},
	]},
]


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

