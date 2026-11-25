@tool
extends EditorInspectorPlugin

const Catalog := preload("res://addons/hearth_workbench/workbench_catalog.gd")
const Schema := preload("res://addons/hearth_workbench/workbench_ability_schema.gd")
const Property := preload("res://addons/hearth_workbench/workbench_property.gd")
const AssetProperty := preload("res://addons/hearth_workbench/workbench_asset_property.gd")
const EffectList := preload("res://addons/hearth_workbench/workbench_effect_list.gd")
const WeaponSway := preload("res://player/weapon_sway/weapon_sway_settings.gd")

const PRESENTATION := {
	"icon": ["Texture2D", "Icon", "The texture used in the Bestiary, Combat Log, and status UI."],
	"hit_fx": ["PackedScene", "On-hit effect", "One-shot visual played at confirmed impact."],
	"on_applied_fx": ["PackedScene", "Application effect", "One-shot visual played when the status applies or refreshes."],
	"while_active_fx": ["PackedScene", "Active effect", "Looping scene that stays attached for the duration of the status."],
	"enemy_while_active_fx": ["PackedScene", "Enemy active effect", "Optional loop used on enemies in place of the shared active effect."],
	"on_end_fx": ["PackedScene", "End effect", "One-shot visual played when the status expires or is removed."],
}

var _behaviors := {}
var open_effect: Callable
var open_bob_style: Callable


func _can_handle(object: Object) -> bool:
	return object is AbilityDefinition or object is EffectDefinition or object is WeaponSway


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint,
		_hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if object is WeaponSway:
		return _parse_weapon_sway(object, name)
	match name:
		"id":
			return true
		"execution_profile":
			var editor := Property.new()
			editor.configure_profile(Schema.FIXED_FOOTPRINTS.has(object.id) or Schema.FIXED_FOOTPRINTS.has(object.action_key))
			add_property_editor(name, editor, false, "Hit shape and targeting")
			return true
		"action_key":
			_add_choice(name, "Behavior", _behavior_choices(),
				"Selects the runtime behavior used by this ability. Use the shape and timing fields below to tune it.")
			return true
		"damage_type":
			_add_choice(name, "Damage type", Schema.DAMAGE_TYPES,
				"Damage element resolved by this hit or periodic effect. Default uses the owning ability or caster's rules.")
			return true
		"icon_key":
			_add_choice(name, "Fallback icon", Schema.ICONS,
				"The built-in icon used when no texture is assigned above.")
			return true
		"on_hit_effects":
			var editor := EffectList.new()
			editor.configure(_effect_choices(), open_effect)
			add_property_editor(name, editor, false, "Effects on confirmed hits")
			return true
	if PRESENTATION.has(name):
		var definition: Array = PRESENTATION[name]
		var editor := AssetProperty.new()
		editor.configure(definition[0], definition[2])
		add_property_editor(name, editor, false, definition[1])
		return true
	return false


func _parse_weapon_sway(object: Resource, name: String) -> bool:
	if name != "bob_style" or object.bob_style == null or object.bob_style.is_built_in():
		return false
	var editor := AssetProperty.new()
	editor.configure("WeaponBobStyle", "Shared movement and bob settings assigned to this profile.", open_bob_style)
	add_property_editor(name, editor, false, "Bob style")
	return true


func _add_choice(property: String, label: String, choices: Dictionary, help: String) -> void:
	var editor := Property.new()
	editor.configure_choice(choices, help)
	add_property_editor(property, editor, false, label)


func _behavior_choices() -> Dictionary:
	if not _behaviors.is_empty():
		return _behaviors
	var keys := PackedStringArray()
	for file: String in DirAccess.get_files_at(Catalog.ABILITIES):
		if file.get_extension() != "tres":
			continue
		var ability := ResourceLoader.load(Catalog.ABILITIES.path_join(file)) as AbilityDefinition
		if ability != null and not ability.action_key.is_empty() and not keys.has(ability.action_key):
			keys.append(ability.action_key)
	keys.sort()
	_behaviors[""] = "Default"
	for key: String in keys:
		_behaviors[key] = key.capitalize()
	return _behaviors


func _effect_choices() -> Array[EffectDefinition]:
	var choices: Array[EffectDefinition] = []
	for file: String in DirAccess.get_files_at(Catalog.EFFECTS):
		if file.get_extension() != "tres":
			continue
		var candidate := ResourceLoader.load(Catalog.EFFECTS.path_join(file)) as EffectDefinition
		if candidate != null:
			choices.append(candidate)
	choices.sort_custom(func(first: EffectDefinition, second: EffectDefinition) -> bool:
		return first.display_name.nocasecmp_to(second.display_name) < 0)
	return choices
