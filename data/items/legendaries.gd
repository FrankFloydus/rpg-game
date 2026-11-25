extends RefCounted

const RECORDS := preload("res://data/items/legendary_records.tres")

static var DROPS: Array[Dictionary]:
	get:
		return RECORDS.legendaries
