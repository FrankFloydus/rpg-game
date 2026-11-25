@tool
extends Resource
## Blood Altar bargains apply until the current expedition ends.

@export_group("The Coin Oath")
## Enemy damage multiplier after swearing the Coin Oath.
@export_range(1.0, 4.0, 0.01) var coin_enemy_damage := 1.18
## Gold awarded by kills and coffers after swearing the Coin Oath.
@export_range(1.0, 4.0, 0.01) var coin_gold := 1.38
@export_group("The Steel Oath")
## Enemy Life multiplier after swearing the Steel Oath.
@export_range(1.0, 4.0, 0.01) var steel_enemy_life := 1.20
## Multiplier to the chance of an equipment drop from enemies after swearing the Steel Oath.
@export_range(1.0, 4.0, 0.01) var steel_gear_chance := 1.32
@export_group("The Key Oath")
## Multiplier to both enemy Life and attack damage after swearing the Key Oath.
@export_range(1.0, 4.0, 0.01) var key_enemy_power := 1.10
## Treasure Keys granted directly to the backpack after swearing the Key Oath.
@export_range(1, 10, 1) var key_count := 1


func choices() -> Array[Dictionary]:
	return [
		{"id": "coin", "name": "Coin Oath", "curse": "Enemy damage +%d%%" % _percent(coin_enemy_damage),
			"reward": "Gold from enemies and coffers +%d%%" % _percent(coin_gold),
			"damage": coin_enemy_damage, "gold": coin_gold},
		{"id": "steel", "name": "Steel Oath", "curse": "Enemy Life +%d%%" % _percent(steel_enemy_life),
			"reward": "Enemy equipment drop chance +%d%%" % _percent(steel_gear_chance),
			"life": steel_enemy_life, "gear": steel_gear_chance},
		{"id": "key", "name": "Key Oath", "curse": "Enemy Life and damage +%d%%" % _percent(key_enemy_power),
			"reward": "Receive %d Treasure %s" % [key_count, "Key" if key_count == 1 else "Keys"],
			"life": key_enemy_power, "damage": key_enemy_power, "keys": key_count},
	]


func choice(id: String) -> Dictionary:
	for offer in choices():
		if offer.id == id:
			return offer
	return {}


func _percent(multiplier: float) -> int:
	return roundi((multiplier - 1.0) * 100.0)
