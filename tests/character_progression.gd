extends SceneTree
## Run with Godot 4.7: --headless --path <project> --script res://tests/character_progression.gd

const Progression = preload("res://systems/character_progression.gd")
const SaveStore = preload("res://systems/save_store.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var character := Progression.new()
	_check(character.level == 1 and character.xp == 0 and character.points_available() == 0,
		"New character starts at level 1 with no points spent or earned")
	_check(character.max_life() == 24.0 and not character.allocate(&"strength"),
		"Level-one Life stays 24 and unearned points cannot be allocated")
	var normal_reward := character.award_kill(1, "normal")
	var rare_reward := character.award_kill(1, "rare")
	_check(normal_reward > 0 and rare_reward > normal_reward and character.xp == normal_reward + rare_reward,
		"Relevant kills give persistent experience and rarer enemies reward more")
	_check(character.award_clear(1) > 0 and character.level == 2 and character.points_available() == 1,
		"First Depth 1 clear reaches level 2 and earns a point")
	_check(character.award_clear(1) == 0 and character.level == 2,
		"Replayed clears cannot grant the first-clear reward")

	var training := Progression.for_training(25)
	_check(training.level == 25 and training.points_available() == 24 and training.max_life() == 49.0,
		"Training level 25 provides the correct Life anchor and 24 independent points")
	_check(training.allocate(&"dexterity", 24) and not training.allocate(&"strength"),
		"Attribute allocation is bounded by the earned point total")
	_check(is_equal_approx(training.base_damage_multiplier(&"dexterity"), 1.18)
		and is_equal_approx(training.critical_chance_bonus(&"dexterity"), 3.6)
		and training.base_damage_multiplier(&"strength") == 1.0
		and training.critical_chance_bonus(&"strength") == 0.0,
		"Dexterity affects only associated attacks and grants percentage points of critical chance")
	training.reset_attributes()
	_check(training.allocate(&"strength", 12) and training.allocate(&"intelligence", 12)
		and is_equal_approx(training.max_stamina_bonus(), 2.4) and training.max_mana_bonus() == 6.0,
		"Strength and Intelligence grant their independent resource bonuses")

	var continued := Progression.new()
	var saved := training.snapshot()
	_check(typeof(saved.attributes.keys()[0]) == TYPE_STRING,
		"Attribute names serialize as plain strings")
	var test_directory := "user://character_progression_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(SaveStore.write_game({"progression": saved}, test_directory) == OK,
		"Progression can be written by the real checkpoint store")
	var checkpoint := SaveStore.load_game(test_directory)
	continued.restore(checkpoint.get("progression", {}))
	_check(continued.level == 25 and continued.attribute(&"strength") == 12
		and continued.attribute(&"intelligence") == 12 and continued.points_available() == 0,
		"Allocation and level survive writing and loading a real checkpoint")
	for filename: String in DirAccess.get_files_at(test_directory):
		DirAccess.remove_absolute(test_directory.path_join(filename))
	DirAccess.remove_absolute(test_directory)
	character.award_kill(2, "normal")
	continued.restore(JSON.parse_string(JSON.stringify(character.snapshot())))
	_check(continued.level == 2 and continued.xp == character.xp and continued.award_clear(1) == 0,
		"Checkpoint round-trip preserves partial XP and one-time clear rewards")
	continued.restore({}, 10)
	_check(continued.level == 10 and continued.max_life() == 30.0 and continued.points_available() == 9
		and continued.award_clear(10) == 0,
		"Existing saves migrate from highest cleared depth without earning past clear bonuses again")
	_check(continued.award_kill(4, "rare") == 0 and continued.award_kill(5, "normal") > 0,
		"Trivial enemies grant no XP while weaker relevant ones still award some")
	continued.restore({"level": 100, "xp": 10, "attributes": {"dexterity": 10000, "strength": -2}})
	_check(continued.level == 100 and continued.xp == 0 and continued.points_available() == 0
		and continued.award_kill(100, "rare") == 0 and continued.xp_for_next_level() == 0,
		"Max level stops XP accumulation and out-of-range saved attributes stay in budget")

	_check(Progression.outgoing_multiplier(1, 3) == 1.0
		and is_equal_approx(Progression.outgoing_multiplier(1, 6), 0.421875)
		and is_equal_approx(Progression.outgoing_multiplier(1, 9), 0.041063625)
		and is_equal_approx(Progression.outgoing_multiplier(1, 10), 0.0188892675)
		and Progression.outgoing_multiplier(1, 25) == 0.005
		and Progression.outgoing_multiplier(25, 1) == 1.0,
		"Player attacks have a two-level grace range and a steep large-gap penalty")
	_check(Progression.incoming_multiplier(3, 1) == 1.0
		and is_equal_approx(Progression.incoming_multiplier(10, 1), 1.35)
		and Progression.incoming_multiplier(25, 1) == 2.0
		and Progression.incoming_multiplier(1, 25) == 1.0,
		"Enemy attack scaling has a two-level grace range and caps at twice the damage")
	print("Character progression: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr(description)
