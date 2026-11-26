extends RefCounted

# Scene order is the persistent archetype ID used by the bestiary and character history.
const _SCENES: Array[PackedScene] = [
	preload("res://combat/enemies/grave_thrall/grave_thrall.tscn"),
	preload("res://combat/enemies/ossuary_archer/ossuary_archer.tscn"),
	preload("res://combat/enemies/ashen_hound/ashen_hound.tscn"),
	preload("res://combat/enemies/barrow_crawler/barrow_crawler.tscn"),
	preload("res://combat/enemies/rotmouth/rotmouth.tscn"),
	preload("res://combat/enemies/cinder_acolyte/cinder_acolyte.tscn"),
	preload("res://combat/enemies/crypt_guard/crypt_guard.tscn"),
	preload("res://combat/enemies/pale_widow/pale_widow.tscn"),
	preload("res://combat/enemies/gutter_marksman/gutter_marksman.tscn"),
	preload("res://combat/enemies/grave_moth/grave_moth.tscn"),
	preload("res://combat/enemies/mire_husk/mire_husk.tscn"),
	preload("res://combat/enemies/wailing_remnant/wailing_remnant.tscn"),
	preload("res://combat/enemies/carrion_brute/carrion_brute.tscn"),
	preload("res://combat/enemies/ironbound_reaper/ironbound_reaper.tscn"),
	preload("res://combat/enemies/soot_revenant/soot_revenant.tscn"),
	preload("res://combat/enemies/thornback/thornback.tscn"),
	preload("res://combat/enemies/sepulcher_colossus/sepulcher_colossus.tscn"),
	preload("res://combat/enemies/hollow_cantor/hollow_cantor.tscn"),
	preload("res://combat/enemies/chalice_fiend/chalice_fiend.tscn"),
	preload("res://combat/enemies/dread_knight/dread_knight.tscn"),
	preload("res://combat/enemies/mire_censer/mire_censer.tscn"),
	preload("res://combat/enemies/bell_warden/bell_warden.tscn"),
	preload("res://combat/enemies/wax_brood/wax_brood.tscn"),
	preload("res://combat/enemies/hollow_standard/hollow_standard.tscn"),
	preload("res://combat/enemies/grave_burrower/grave_burrower.tscn"),
	preload("res://combat/enemies/grave_legate/grave_legate.tscn"),
	preload("res://combat/enemies/grave_reclaimer/grave_reclaimer.tscn"),
	preload("res://combat/enemies/crypt_scurrer/crypt_scurrer.tscn"),
	preload("res://combat/enemies/manymouth_choir/manymouth_choir.tscn"),
]

static var ARCHETYPES: Array[Dictionary] = _read_archetypes()


static func instantiate(archetype_id: int) -> CharacterBody3D:
	var id := clampi(archetype_id, 0, _SCENES.size() - 1)
	return _SCENES[id].instantiate() as CharacterBody3D


static func action_ids(archetype_id: int) -> Array:
	return ARCHETYPES[archetype_id]["actions"]


static func behavior_for(archetype_id: int) -> Dictionary:
	return ARCHETYPES[archetype_id].get("behavior", {})


static func pick_archetype(level: int, rng: RandomNumberGenerator, roster_count: int = -1) -> int:
	var weighted: Array[int] = []
	var count := ARCHETYPES.size() if roster_count < 0 else mini(roster_count, ARCHETYPES.size())
	for id in range(count):
		if not bool(ARCHETYPES[id].get("spawn_in_pool", true)):
			continue
		var first_level: int = ARCHETYPES[id]["level"]
		if first_level <= level:
			weighted.append(id)
			if first_level >= level - 2:
				weighted.append(id)
	return weighted[rng.randi_range(0, weighted.size() - 1)]


static func _read_archetypes() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for id in _SCENES.size():
		var scene := _SCENES[id]
		var actor := scene.instantiate()
		var definition: Dictionary = actor.definition().duplicate()
		assert(definition.get("id") == id, "Archetype ID mismatch in %s, expected %d." % [scene.resource_path, id])
		definition["hp"] = actor.base_life
		definition["damage"] = actor.base_attack_damage
		definition["speed"] = actor.base_move_speed
		definition["abilities"] = actor.ability_loadout.duplicate()
		definition["traits"] = actor.combat_traits()
		var actions: Array[String] = []
		for ability in actor.ability_loadout:
			if ability == null:
				continue
			if ability.action_key == "cobweb":
				definition["cobweb"] = true
			elif ability.runtime_profile().has("shape"):
				actions.append(ability.action_key)
		definition["actions"] = actions
		actor.free()
		definitions.append(definition)
	return definitions
