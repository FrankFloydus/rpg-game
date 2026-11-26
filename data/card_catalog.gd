extends RefCounted
## Player combat cards. Art coordinates index the two manuscript atlases.

const LOOT := preload("res://data/items/loot_records.tres")

const STARTERS: Array[String] = ["red_mercy", "cinder_circle", "iron_oath"]
const SLOTS := 3
const COLORS := {
	"normal": Color("#d4c1a1"), "magic": Color("#a3b9de"),
	"rare": Color("#e7bd6a"), "legendary": Color("#e78651"),
}
const HOVER_SOUND := &"card_hover"
const ELEMENT_SOUNDS := {
	"fire": &"card_use_fire", "cold": &"card_use_cold",
	"lightning": &"card_use_lightning", "physical": &"card_use_physical",
}
static var CARDS: Dictionary = _ordered_cards()
static var DROP_CHANCES: Dictionary:
	get:
		return LOOT.card_chances
static var DROP_WEIGHTS: Dictionary:
	get:
		return LOOT.card_weights


static func color(card: Dictionary) -> Color:
	return COLORS.get(card.get("rarity", "normal"), COLORS.normal)


static func default_use_sound(card: Dictionary) -> StringName:
	if bool(card.get("summon_skeletons", false)):
		return &"card_use_summon"
	var element := String(card.get("element", ""))
	if float(card.get("radius", 0.0)) > 0.0:
		return ELEMENT_SOUNDS.get(element, &"spell_cast")
	if float(card.get("heal", 0.0)) > 0.0:
		return &"card_use_heal"
	if float(card.get("protection", 0.0)) > 0.0 or bool(card.get("stamina", false)):
		return &"card_use_guard"
	return &"card_use_buff"


static func roll_drop(depth: int, monster_rarity: String, unavailable: Dictionary,
		rng: RandomNumberGenerator) -> String:
	var chance := float(DROP_CHANCES.get(monster_rarity, 0.0))
	if chance <= 0.0 or rng.randf() >= chance:
		return ""
	var weights: Dictionary = DROP_WEIGHTS[monster_rarity]
	var eligible: Array[String] = []
	var cutoffs := PackedFloat32Array()
	var total := 0.0
	for id: String in CARDS:
		var card: Dictionary = CARDS[id]
		var weight := float(weights.get(card.rarity, 0.0))
		if unavailable.has(id) or depth < int(card.get("minimum_depth", 1)) or weight <= 0.0:
			continue
		# Keep the legendary chance bounded even when the common collection is complete.
		if card.rarity == "legendary" and rng.randf() >= LOOT.legendary_card_eligibility:
			continue
		total += weight
		eligible.append(id)
		cutoffs.append(total)
	if eligible.is_empty():
		return ""
	var roll := rng.randf() * total
	for index in eligible.size():
		if roll < cutoffs[index]:
			return eligible[index]
	return eligible.back()


static func _ordered_cards() -> Dictionary:
	# ResourceSaver sorts dictionary keys. Keep the original order for seeded rolls.
	var ordered := {}
	for id: String in LOOT.card_order:
		if LOOT.cards.has(id):
			ordered[id] = LOOT.cards[id]
	ordered.merge(LOOT.cards)
	return ordered
