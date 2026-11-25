extends RefCounted
## Saved counters and one-time awards for a named character.

signal achievement_unlocked(entry: Dictionary)

const ACHIEVEMENTS := [
	{"id": "first_blood", "name": "First Blood", "description": "Slay your first enemy in the Undervault.",
		"stat": "kills", "threshold": 1, "points": 5},
	{"id": "vaultbreaker", "name": "Vaultbreaker", "description": "Clear an entire dungeon depth.",
		"stat": "depths_cleared", "threshold": 1, "points": 15},
	{"id": "behind_stone", "name": "Behind the Stone", "description": "Open a concealed passage.",
		"stat": "secrets_opened", "threshold": 1, "points": 10},
	{"id": "trial_survivor", "name": "Trial Survivor", "description": "Defeat every wave and open a Trial Coffer.",
		"stat": "trials_claimed", "threshold": 1, "points": 20},
	{"id": "gilded_purse", "name": "Gilded Purse", "description": "Gather 500 gold in the Undervault.",
		"stat": "gold_collected", "threshold": 500, "points": 10},
]
const GROUPS := {
	"Combat": {
		"damage_dealt": "Damage dealt", "damage_taken": "Damage taken", "kills": "Enemies slain",
		"magic_kills": "Magic enemies slain", "rare_kills": "Rare enemies slain", "deaths": "Times fallen",
		"cards_cast": "Cards played",
	},
	"Exploration": {
		"depths_entered": "Expeditions begun", "depths_cleared": "Expeditions cleared",
		"coffers_opened": "Coffers opened", "secrets_opened": "Secret passages opened",
		"gates_opened": "Route gates opened", "trials_claimed": "Trial coffers looted",
		"breakables": "Destructibles broken",
	},
	"Wealth": {
		"gold_dropped": "Gold dropped", "gold_collected": "Gold collected", "gold_spent": "Gold spent",
		"gold_earned_trade": "Gold earned from trade", "items_dropped": "Equipment dropped",
		"items_looted": "Equipment collected", "materials_looted": "Materials collected",
		"cards_looted": "Cards acquired", "items_bought": "Items bought", "items_sold": "Items sold",
		"items_crafted": "Items crafted",
	},
}

var _totals: Dictionary = {}
var _kills: Dictionary = {}
var _deaths: Dictionary = {}
var _awards: Dictionary = {}


func add(stat: String, amount := 1) -> void:
	if amount <= 0:
		return
	_totals[stat] = int(_totals.get(stat, 0)) + amount
	for entry in ACHIEVEMENTS:
		if entry.stat == stat and _totals[stat] >= entry.threshold and not _awards.has(entry.id):
			_awards[entry.id] = true
			achievement_unlocked.emit(entry)


func kill(enemy: String, rarity: String) -> void:
	add("kills")
	_kills[enemy] = int(_kills.get(enemy, 0)) + 1
	if rarity in ["magic", "rare"]:
		add(rarity + "_kills")


func death(enemy: String) -> void:
	add("deaths")
	var source := enemy if not enemy.is_empty() else "Unknown"
	_deaths[source] = int(_deaths.get(source, 0)) + 1


func groups() -> Dictionary:
	var result := {}
	for category: String in GROUPS:
		var entries: Dictionary = GROUPS[category]
		var rows := []
		for stat: String in entries:
			rows.append([entries[stat], compact(int(_totals.get(stat, 0)))])
		result[category] = rows
	result["Kills by enemy"] = _enemy_rows(_kills)
	result["Deaths by source"] = _enemy_rows(_deaths)
	return result


func achievements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in ACHIEVEMENTS:
		var entry: Dictionary = definition.duplicate()
		entry["unlocked"] = _awards.has(entry.id)
		entry["progress"] = mini(int(_totals.get(entry.stat, 0)), int(entry.threshold))
		result.append(entry)
	return result


func points() -> int:
	var total := 0
	for entry in ACHIEVEMENTS:
		if _awards.has(entry.id):
			total += int(entry.points)
	return total


func snapshot() -> Dictionary:
	return {"totals": _totals.duplicate(), "kills": _kills.duplicate(), "deaths": _deaths.duplicate(),
		"awards": _awards.keys()}


func restore(state: Dictionary) -> void:
	_totals = _read_counts(state.get("totals", {}))
	_kills = _read_counts(state.get("kills", {}))
	_deaths = _read_counts(state.get("deaths", {}))
	_awards.clear()
	var saved: Variant = state.get("awards", [])
	if saved is Array:
		for entry in ACHIEVEMENTS:
			if entry.id in saved:
				_awards[entry.id] = true


static func compact(value: int) -> String:
	if value < 1000:
		return str(value)
	var reduced := float(value)
	for suffix in ["K", "M", "B", "T", "Qa", "Qi"]:
		reduced /= 1000.0
		if reduced < 999.95 or suffix == "Qi":
			return ("%.1f" % reduced).trim_suffix(".0") + suffix
	return str(value)


static func _enemy_rows(counts: Dictionary) -> Array:
	var names := counts.keys()
	names.sort_custom(func(first: String, second: String) -> bool:
		return int(counts[first]) > int(counts[second]) if counts[first] != counts[second] else first < second)
	var rows := []
	for enemy: String in names:
		rows.append([enemy, compact(int(counts[enemy]))])
	return rows


static func _read_counts(data: Variant) -> Dictionary:
	var counts := {}
	if data is Dictionary:
		for key: String in data:
			var count: Variant = data[key]
			if (count is int or count is float) and is_finite(float(count)) and count >= 0:
				counts[key] = int(count)
	return counts
