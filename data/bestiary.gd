extends RefCounted
## Field notes indexed by the combat catalogue's persistent archetype IDs.

const Catalog := preload("res://combat/enemies/enemy_catalog.gd")
const Affixes := preload("res://combat/effects/enemy_affixes.gd")
const Statuses := preload("res://combat/effects/status_catalog.gd")

const FIELD_NOTES := {
	"thrall": {
		"lore": "The last gravediggers were buried with their work knives so they could keep the Undervault in order. They still tend the graves and mistake every living footstep for another body to lay out.",
	},
	"skeleton": {
		"lore": "A watch of archers once guarded the burial shafts from grave robbers. Their bones settled facing the stairs, and their first volley still flies toward the light.",
	},
	"hound": {
		"lore": "The old kennel fed its hounds on offal from the burial kitchens. Even after the ovens cooled, the hounds kept their taste for warm meat.",
	},
	"spider": {
		"lore": "Embalmers bought its silk to bind the hands of the dead. A thread laid across a threshold now tells the crawlers exactly when supper has arrived.",
	},
	"ghoul": {
		"lore": "Prisoners left to starve in the crypt fed on the tongues of the dead. The grave flesh still festers between their teeth.",
	},
	"cultist": {
		"lore": "The acolytes kept one taper lit for every family that could pay. When the chapel burned, they took the flames with them into the burial chambers.",
	},
	"knight": {
		"lore": "Crypt guards swore to hold their posts until a bell released them. The bell was melted down, and the watch remains at its doors.",
	},
	"widow": {
		"lore": "The widows spin their webs with strips of winding cloth. Look closely and you can still read the names embroidered on the shrouds.",
	},
	"rat": {
		"lore": "Smugglers once traded maps of the drain tunnels for scraps of iron. Their marksmen remember the toll and collect it from behind a crossbow.",
	},
	"moth": {
		"lore": "Grave moths hatch in the oil of burial lamps. Their wings shed a stinging dust when they search for the warmth of a new flame.",
	},
	"husk": {
		"lore": "When the Mire flooded, its ferrymen tied themselves to the boat poles to keep from being swept away. Years later the poles came walking out of the water.",
	},
	"wraith": {
		"lore": "These mourners waited at the gate for bodies that never arrived. The frost on a lintel is often the first sign that a vigil is still being kept.",
	},
	"brute": {
		"lore": "The plague carts carried so many bodies that the wheels split under the weight. Something that had been riding beneath the corpses picked up a hook and dragged the load the rest of the way.",
	},
	"reaper": {
		"lore": "The executioners sealed their visors before each sentence so the condemned could see no human face. The last executioner died with his visor sealed and his work unfinished.",
	},
	"revenant": {
		"lore": "The wardens of the cinder chambers hammered copper rods into the stone to draw off storms. Their rods are still warm, and soot gathers wherever the wardens stop to rest.",
	},
	"thornback": {
		"lore": "Briar hedges kept scavengers away from the open graves. Over time the briars took root in the scavengers, who came back wearing thorns like armour.",
	},
	"golem": {
		"lore": "The first masons set the bones of their foremen inside the foundation stones. One of those stones broke loose and still tries to hammer the floor level.",
	},
	"cantor": {
		"lore": "The cantor's funeral hymn had as many verses as there were graves. He sang until the choir had no voices left, and kept singing after his own breath ran out.",
	},
	"fiend": {
		"lore": "The chalice of the lower chapel was filled with oil on the night the clergy fled. The thing that rose from the font still carries the cup and spills fire at its feet.",
	},
	"dread": {
		"lore": "The last lord of the vault ordered his knight to kneel until the dead were counted. His armour still bears the names, one scratched into the iron for each coffin that passed.",
	},
	"mire": {
		"lore": "The Censer carries a furnace across the drowned floors. Water cannot put it out. Where its fuel spills, even the lichen draws back.",
	},
	"bell_warden": {
		"lore": "At the last toll the sextons found the bell halfway to the crypt, with its ropes untied. The Warden still carries it, face down, so that the stone can hear it.",
	},
	"wax_brood": {
		"lore": "The lower chantry kept candles alight over its nameless dead. When the clergy sealed the door, pale creatures hatched in the warm wax and learned to carry their own flames.",
	},
	"hollow_standard": {
		"lore": "The shreds on this pole once marked the last rank at the gate. What follows the standard has forgotten the regiment's name and still remembers its orders.",
	},
	"burrower": {
		"lore": "Bones pressed into the vault's foundations started moving after the first flood. The Burrower follows the joins beneath the walkways and shoves its way up where the mortar gives.",
	},
	"grave_legate": {
		"lore": "The old commanders sent legates ahead with orders nobody could refuse. Something still blows the hollow horn when the battle is already underway.",
	},
	"grave_reclaimer": {
		"lore": "Embalmers kept a lamp burning until the last corpse stopped moving. This one tends the lamp by reversing the work, calling fallen bodies up to serve again.",
	},
	"scurrer": {
		"lore": "Scurrers lived on candle drippings and bone dust until they learned to hunt in packs. Their first mistake is easy to forgive. Their fifth bite comes before you can step away.",
	},
	"manymouth": {
		"lore": "There were seven names carved on the old choir stalls. Each mouth still turns at its name, but all of them cry out when the living draw near.",
	},
}

const ELITE_NOTES := {
	"armored": "Takes less Physical damage from hits.",
	"draining": "Landing a hit restores part of this enemy's maximum Life.",
	"enraged": "At 45% Life or below, it moves faster, attacks more quickly, and deals more damage.",
	"frozen": "Adds Cold attacks that can Chill you. Other available elements alternate with Cold.",
	"incendiary": "Adds Fire attacks that can Burn you, dealing damage over time.",
	"quick": "Moves faster and winds up its attacks more quickly.",
	"ravaging": "Its attacks deal more damage.",
	"renewing": "Recovers Life after a short time without taking damage. Hitting it interrupts the recovery.",
	"venomous": "Adds Poison attacks that can deal damage over time.",
	"volatile": "Its death leaves a red ring. A moment later, the corpse erupts for Fire damage and can Burn you.",
	"vital": "Has a larger maximum Life pool.",
}

const ELITE_ELEMENTS := {"frozen": "cold", "incendiary": "fire", "venomous": "poison", "volatile": "fire"}

const ELITE_ICONS := {
	"armored": preload("res://assets/rework/icons/elite_armored.tres"),
	"draining": preload("res://assets/rework/icons/elite_draining.tres"),
	"enraged": preload("res://assets/rework/icons/elite_enraged.tres"),
	"frozen": preload("res://assets/rework/icons/elite_frozen.tres"),
	"incendiary": preload("res://assets/rework/icons/elite_incendiary.tres"),
	"quick": preload("res://assets/rework/icons/elite_quick.tres"),
	"ravaging": preload("res://assets/rework/icons/elite_ravaging.tres"),
	"renewing": preload("res://assets/rework/icons/elite_renewing.tres"),
	"venomous": preload("res://assets/rework/icons/elite_venomous.tres"),
	"volatile": preload("res://assets/rework/icons/elite_volatile.tres"),
	"vital": preload("res://assets/rework/icons/elite_vital.tres"),
}


static func entry_count() -> int:
	return Catalog.ARCHETYPES.size()


static func portrait_spec(id: int) -> Dictionary:
	return Catalog.ARCHETYPES[id] if id >= 0 and id < entry_count() else {}


static func portrait_texture(id: int) -> Texture2D:
	var path := "res://assets/rework/bestiary/%d.png" % id
	if not ResourceLoader.exists(path, "Texture2D"):
		path = "res://assets/bestiary/%d.png" % id
	return ResourceLoader.load(path, "Texture2D") as Texture2D if ResourceLoader.exists(path, "Texture2D") else null


static func combat_ability(archetype_id: int, move: Variant, _unused_overrides: Dictionary = {}) -> Dictionary:
	var spec := portrait_spec(archetype_id)
	var loadout: Array = spec.get("abilities", [])
	var ability := move as AbilityDefinition if move is AbilityDefinition else _find_ability(loadout, String(move))
	if ability != null:
		var details := ability.combat_details()
		details["description"] = _ability_tooltip(ability, spec, _move_minimum_level(ability, _first_attack(loadout), spec))
		return details
	var key := String(move)
	if ELITE_NOTES.has(key):
		return {"id": key, "name": Affixes.AFFIX_NAMES[key], "description": ELITE_NOTES[key]}
	var effect := Statuses.get_effect(key)
	if effect != null:
		return {"id": key, "name": effect.display_name, "description": effect.tooltip_description()}
	var fallback := key.strip_edges().capitalize()
	return {"id": key, "name": fallback if not fallback.is_empty() else "Unknown Ability",
		"description": "No field notes are available for this ability."}


static func entry(id: int) -> Dictionary:
	var spec := portrait_spec(id)
	if spec.is_empty():
		return {}
	var notes: Dictionary = FIELD_NOTES[spec["family"]]
	var loadout: Array = spec.get("abilities", [])
	var first_attack := _first_attack(loadout)
	var attack_type := _damage_type(first_attack, spec)
	var behavior := Catalog.behavior_for(id)
	var position_style: String = behavior.get("positioning", "ranged" if spec.get("ranged", false) else "melee")
	var abilities: Array[Dictionary] = []
	var encountered := {}
	for ability: AbilityDefinition in loadout:
		if ability == null or encountered.has(ability.id):
			continue
		encountered[ability.id] = true
		abilities.append({
			"id": ability.id, "name": ability.display_name, "icon": ability.icon_key,
			"texture": ability.icon, "element": _damage_type(ability, spec),
			"tooltip": _ability_tooltip(ability, spec, _move_minimum_level(ability, first_attack, spec)),
		})
	var traits := _traits(loadout)
	traits.append_array(spec.get("traits", []))
	return {
		"id": id, "name": spec["name"], "family": spec["family"], "lore": notes["lore"],
		"min_depth": spec["level"], "ranged": position_style == "ranged", "attack_type": attack_type,
		"abilities": abilities, "traits": traits, "buffs": _elite_buffs(),
	}


static func _find_ability(loadout: Array, key: String) -> AbilityDefinition:
	for ability: AbilityDefinition in loadout:
		if ability != null and String(ability.id) == key:
			return ability
	for ability: AbilityDefinition in loadout:
		if ability != null and ability.action_key == key:
			return ability
	return null


static func _is_ordinary_attack(ability: AbilityDefinition) -> bool:
	return ability.action_key not in ["cobweb", "cocoon", "thornback_guard"]


static func _first_attack(loadout: Array) -> AbilityDefinition:
	for ability: AbilityDefinition in loadout:
		if ability != null and _is_ordinary_attack(ability):
			return ability
	return null


static func _move_minimum_level(ability: AbilityDefinition, first_attack: AbilityDefinition, spec: Dictionary) -> int:
	if _is_ordinary_attack(ability) and first_attack != null and ability.id != first_attack.id:
		return int(spec.get("additional_moves_level", 3))
	return 1


static func _damage_type(ability: AbilityDefinition, spec: Dictionary) -> String:
	if ability != null and not ability.damage_type.is_empty():
		return ability.damage_type
	return spec.get("type", "physical")


static func _ability_tooltip(ability: AbilityDefinition, spec: Dictionary, minimum_level: int) -> String:
	var lines := PackedStringArray()
	if not ability.description.is_empty():
		lines.append(ability.description + "\n")
	_add_execution_details(lines, ability, spec)
	if ability.mana_cost > 0.0:
		lines.append("Cost %.1f Mana" % ability.mana_cost)
	if ability.cooldown > 0.0:
		lines.append("Cooldown %.2f s" % ability.cooldown)
	for effect: EffectDefinition in ability.on_hit_effects:
		if effect == null or effect.chance <= 0.0 or effect.duration <= 0.0:
			continue
		var chance := String.num(effect.chance, 2).trim_suffix(".0")
		var effect_level := effect.minimum_on_hit_level()
		var level_requirement := " · Caster Level %d+" % effect_level if effect_level > 1 else ""
		if effect is BleedEffectDefinition:
			lines.append("On Physical hit · %s%% chance to Bleed%s" % [chance, level_requirement])
			lines.append(effect.tooltip_description())
			continue
		var trigger := "On Physical hit" if effect.requires_physical_hit() else "On hit"
		var duration := String.num(effect.duration, 2).trim_suffix(".0")
		lines.append("%s · %s · %s%% for %s s%s" % [
			trigger, effect.display_name, chance, duration, level_requirement,
		])
		if effect is DamageOverTimeEffectDefinition and effect.hit_damage_percent > 0.0:
			var percent_damage := String.num(effect.hit_damage_percent, 2).trim_suffix(".0")
			lines.append("Deals %s%% of hit damage over its duration" % percent_damage)
	if minimum_level > 1:
		lines.append("Available from Enemy Level %d" % minimum_level)
	return "\n".join(lines)


static func _add_execution_details(lines: PackedStringArray, ability: AbilityDefinition, spec: Dictionary) -> void:
	var profile := ability.runtime_profile()
	match ability.action_key:
		"kindle_brood":
			lines.append("Hatching range %.2f m · Windup %.2f s" % [
				float(profile["start"]), ability.windup,
			])
			return
		"waxling_flare":
			lines.append("Blast radius %.2f m · Fuse at least %.2f s" % [
				float(profile["flare_radius"]), ability.windup,
			])
			return
		"raise_the_levy":
			lines.append("Invocation range %.2f m · Windup %.2f s" % [
				float(profile["start"]), ability.windup,
			])
			return
		"raise_the_fallen":
			lines.append("Revival range %.2f m · Windup %.2f s" % [
				float(profile["revival_range"]), ability.windup,
			])
			return
		"cocoon":
			lines.append("Hatches in %.2f s · %.0f%% of maximum Life" % [
				float(profile.get("hatch_seconds", 0.0)), float(profile.get("health_fraction", 0.0)) * 100.0,
			])
			return
		"thornback_guard":
			lines.append("Reflection lasts %.2f s" % float(profile.get("duration", 0.0)))
			return
	var shape := String(profile.get("shape", ""))
	var reach := float(profile.get("reach", 0.0))
	if reach > 0.0:
		if shape == "disc":
			lines.append("Radius %.2f m" % reach)
		elif shape == "ray" or ability.action_key == "cobweb":
			lines.append("Firing range %.2f m" % float(profile.get("start", reach)))
		else:
			lines.append("Reach %.2f m" % reach)
	if profile.has("second"):
		lines.append("Second shot after %.2f s" % float(profile["second"]))
	var melee := ability as MeleeAbilityDefinition
	if melee != null and melee.double_slash_chance > 0.0:
		lines.append("%s%% chance of a second slash after %.2f s" % [
			String.num(melee.double_slash_chance, 2), melee.follow_up_delay,
		])
	var timing := "Base windup %.2f s" % ability.windup if ability.windup > 0.0 else "Instant"
	if ability.recovery > 0.0:
		timing += " · Base recovery %.2f s" % ability.recovery
	lines.append(timing)
	if ability.action_key == "cobweb" or not spec.has("damage"):
		return
	var damage := float(spec["damage"]) * ability.damage_multiplier
	var hit_label := "Base hit"
	if profile.has("second"):
		hit_label = "Base hit per projectile"
	elif melee != null and melee.double_slash_chance > 0.0:
		hit_label = "Base hit per slash"
	elif profile.has("spread"):
		hit_label = "Base center hit"
	lines.append("%s %.1f %s damage" % [hit_label, damage, _damage_type(ability, spec).capitalize()])


static func _traits(loadout: Array) -> Array[Dictionary]:
	var traits: Array[Dictionary] = []
	var encountered := {}
	for ability: AbilityDefinition in loadout:
		if ability == null:
			continue
		for effect: EffectDefinition in ability.on_hit_effects:
			if effect == null or effect.chance <= 0.0 or effect.duration <= 0.0 or encountered.has(effect.id):
				continue
			encountered[effect.id] = true
			var tooltip := effect.tooltip_description()
			if effect is BleedEffectDefinition:
				tooltip = "Deals Physical damage over time. See each ability for its Bleed chance, damage, and duration."
			traits.append({
				"name": effect.display_name,
				"icon": String(effect.id),
				"texture": effect.icon, "element": effect.damage_type,
				"tooltip": tooltip,
			})
	return traits


static func _elite_buffs() -> Array[Dictionary]:
	var buffs: Array[Dictionary] = []
	for affix: String in Affixes.AFFIX_NAMES:
		buffs.append({
			"name": Affixes.AFFIX_NAMES[affix], "icon": affix, "element": ELITE_ELEMENTS.get(affix, ""),
			"texture": ELITE_ICONS.get(affix),
			"tooltip": ELITE_NOTES[affix],
		})
	return buffs
