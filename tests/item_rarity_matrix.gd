extends SceneTree
## Runs actual item rolls in equally sized item level, quality profile and player rarity strata.

const Items := preload("res://systems/items.gd")
const Legendaries := preload("res://data/items/legendaries.gd")
const ITEM_LEVELS := [1, 3, 6, 7, 10, 15, 20, 30, 40, 50]
const SOURCES := ["normal", "magic", "rare"]
const RARITY_BONUSES := [0, 50, 100, 250]
const SAMPLES_PER_GROUP := 10000
const SEED := 49134123

var _output := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_msec()
	var rows: Array[Dictionary] = []
	var all_counts := _empty_counts()
	var legendary_counts := {}
	var target := ITEM_LEVELS.size() * SOURCES.size() * RARITY_BONUSES.size() * SAMPLES_PER_GROUP
	var actual := 0
	for item_level in ITEM_LEVELS:
		for source in SOURCES:
			for bonus in RARITY_BONUSES:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([SEED, item_level, source, bonus])
				var counts := _empty_counts()
				var uniques := {}
				for _sample in SAMPLES_PER_GROUP:
					var item := Items.roll_item(item_level, source, rng, float(bonus))
					var rarity := String(item.get("rarity", ""))
					if not counts.has(rarity):
						printerr("Item generator returned an invalid rarity for item level %d (%s)." % [item_level, source])
						quit(1)
						return
					counts[rarity] += 1
					if rarity == "legendary":
						var id := String(item.legendary_id)
						uniques[id] = int(uniques.get(id, 0)) + 1
						legendary_counts[id] = int(legendary_counts.get(id, 0)) + 1
				rows.append({"item_level": item_level, "source": source, "loot_rarity": bonus,
					"rolls": SAMPLES_PER_GROUP, "rarities": counts, "legendaries": uniques})
				for rarity in counts:
					all_counts[rarity] += counts[rarity]
				actual += SAMPLES_PER_GROUP
		print("Item rarity matrix item level %02d: %d of %d generated" % [item_level, actual, target])
	var legendary_list := []
	for item: Dictionary in Legendaries.DROPS:
		legendary_list.append({"id": item.id, "name": item.name, "minimum_item_level": item.level,
			"observed": int(legendary_counts.get(item.id, 0))})
	var report := {"seed": SEED, "count": actual, "equal_strata": true, "rarities": all_counts,
		"legendary_items": legendary_list, "loot_quantity_stat": false, "rows": rows,
		"elapsed_ms": Time.get_ticks_msec() - started}
	if not _output.is_empty():
		var output := FileAccess.open(_output, FileAccess.WRITE)
		if output == null:
			printerr("Could not write the item rarity report.")
			quit(1)
			return
		output.store_string(JSON.stringify(report, "\t"))
	print("Item rarity matrix total: ", all_counts)
	quit(0 if actual == target else 1)


func _empty_counts() -> Dictionary:
	return {"normal": 0, "magic": 0, "rare": 0, "legendary": 0}
