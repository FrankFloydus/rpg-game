extends RefCounted
## Physical cards share the inventory's single-cell supply format.

const Cards := preload("res://data/card_catalog.gd")
const BACK_ART := preload("res://assets/rework/ui/card_casing.png")
const KIND := "expedition_card"
const UNIDENTIFIED_NAME := "Unidentified Card"


static func is_card(item: Dictionary) -> bool:
	return item.get("supply_kind") == KIND


static func make(card_id: String, id: String, unidentified := true) -> Dictionary:
	if id.is_empty() or not Cards.CARDS.has(card_id):
		return {}
	var item := {
		"id": id, "card_id": card_id, "unidentified": unidentified,
		"supply_kind": KIND, "supply_id": KIND, "type": KIND,
		"base_name": UNIDENTIFIED_NAME, "name": UNIDENTIFIED_NAME,
		"rarity": "normal", "item_level": 1, "width": 1, "height": 1, "gold_value": 1,
	}
	if not unidentified:
		var card: Dictionary = Cards.CARDS[card_id]
		item["base_name"] = "Card"
		item["name"] = card.name
		item["rarity"] = card.rarity
		item["description"] = card.description
		item["art"] = card.art
	return item


static func restore_item(item: Dictionary) -> Dictionary:
	var unidentified: Variant = item.get("unidentified", true)
	var quantity: Variant = item.get("quantity", 1)
	if not unidentified is bool or quantity != 1:
		return {}
	return make(String(item.get("card_id", "")), String(item.get("id", "")), unidentified)
