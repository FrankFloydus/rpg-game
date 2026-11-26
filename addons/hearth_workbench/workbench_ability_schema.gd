@tool
extends RefCounted
## Presentation for the fields consumed by the ability runtime and specialized AI.

const SHAPES := {
	"": "Defined by ability or weapon",
	"arc": "Melee arc",
	"disc": "Circle",
	"ring": "Ring",
	"lane": "Straight lane",
	"ray": "Projectile",
	"projectile": "Projectile (legacy)",
}
const WARNINGS := {"": "Use ability default", "always": "Show a floor warning"}
const FIXED_FOOTPRINTS := {
	"bell_reverb": "ring", "cinder_sigil": "lane", "grave_tunnel": "lane",
	"rime_snare": "ray", "soot_conduit": "lane", "spore_lob": "", "waxling_flare": "",
}
const DAMAGE_TYPES := {
	"": "Default", "physical": "Physical", "fire": "Fire", "cold": "Cold",
	"lightning": "Lightning", "poison": "Poison",
}
const ICONS := {
	"": "Default", "arrow": "Arrow", "bolt": "Bolt", "briar_guard": "Briar guard",
	"cobweb": "Cobweb", "cocoon": "Cocoon", "cut": "Cut", "doublet": "Double shot",
	"enrage": "Enrage", "fan": "Fan", "pounce": "Pounce", "slam": "Slam",
	"sweep": "Sweep", "venom": "Venom",
}
const SHAPE_FIELDS := {
	"": [],
	"arc": ["start", "reach", "arc"],
	"disc": ["start", "reach", "offset"],
	"ring": ["start", "reach", "inner_radius"],
	"lane": ["start", "reach", "width"],
	"ray": ["start", "reach", "speed"],
	"projectile": ["start", "reach", "speed"],
}
const FIELDS := {
	"start": ["AI start range", "Farthest distance from the target where the enemy may start the move. Hit reach controls the area that can deal damage.", "m", 2.1, 0.01],
	"reach": ["Hit reach", "Maximum distance covered by the attack. For a circle or ring this is the outer radius.", "m", 2.25, 0.01],
	"arc": ["Arc half-angle", "Degrees to either side of the caster's facing. A setting of 45° creates a 90° sweep.", "°", 45.0, 0.1, 180.0],
	"offset": ["Center offset", "How far ahead of the caster to place the circle's center.", "m", 0.0, 0.01],
	"inner_radius": ["Inner safe radius", "The ring cannot hit targets closer to the center than this distance.", "m", 1.0, 0.01],
	"width": ["Lane half-width", "Distance from the center line to one edge. The full lane is twice as wide.", "m", 0.55, 0.01],
	"dash_speed": ["Dash speed", "Speed at which the caster moves along a committed dash lane.", "m/s", 6.0, 0.05],
	"speed": ["Projectile speed", "Travel speed of a projectile or the motion speed used by a scripted ranged release.", "m/s", 10.0, 0.1],
	"spread": ["Projectile spread", "Angular separation used when this move launches projectiles across a fan.", "°", 0.0, 0.1, 180.0],
	"second": ["Follow-up shot delay", "Time after the first shot before the same cast releases the second one.", "s", 0.0, 0.01],
	"attack_cost": ["Encounter pressure cost", "Multiplies the attack coordination budget spent on this move. Higher costs leave less room for other enemies to attack at the same time.", "×", 1.0, 0.01],
	"arm_delay": ["Trap arming delay", "Time after the snare lands before it can trigger.", "s", 0.75, 0.01],
	"lifetime": ["Trap lifetime", "How long an untriggered snare stays on the floor.", "s", 6.0, 0.05],
	"trigger_radius": ["Trap trigger radius", "Distance from the snare center at which a target steps onto it.", "m", 0.78, 0.01],
	"impact_radius": ["Surface bite radius", "Distance from the burrow exit within which the creature's surface attack deals damage.", "m", 1.17, 0.01],
	"minimum_distance": ["Minimum start distance", "The burrower will not tunnel at targets closer than this.", "m", 3.25, 0.01],
	"rise_seconds": ["Minimum surfacing tell", "Shortest authored time between the exit warning and the bite. Escape timing can extend it.", "s", 0.27, 0.01],
	"arm_distance": ["Fuse trigger range", "How close a waxling must get before it stops chasing and lights its fuse.", "m", 1.02, 0.01],
	"wake_seconds": ["Wake-up duration", "Time a waxling waits before beginning to chase.", "s", 0.41, 0.01],
	"chase_seconds": ["Chase limit", "If the fuse has not been lit, the waxling cools harmlessly after this much chase time.", "s", 2.8, 0.01],
	"chase_speed": ["Chase speed", "Ground movement speed of the waxling while it closes on its target.", "m/s", 2.72, 0.01],
	"flare_radius": ["Flare radius", "Radius of the waxling's detonation and its floor warning.", "m", 1.42, 0.01],
	"channel_duration": ["Channel duration", "How long the committed beam persists and can hit targets in its lane.", "s", 1.58, 0.01],
	"tick_interval": ["Damage tick interval", "Seconds between consecutive damage checks while channeling.", "s", 0.27, 0.01],
	"duration": ["Active duration", "How long the guard or scripted effect remains active after casting.", "s", 3.0, 0.01],
	"first_delay": ["First-use delay", "Seconds after engagement before the enemy can first use this ability.", "s", 3.0, 0.01],
	"hatch_seconds": ["Hatch time", "Time before the cocoon hatches if the player does not destroy it.", "s", 4.0, 0.01],
	"health_fraction": ["Cocoon Life fraction", "Cocoon maximum Life divided by the moth's maximum Life. 0.34 is 34%.", "×", 0.34, 0.01],
	"revival_range": ["Revival search radius", "Distance the caster can search for an eligible fallen ally.", "m", 6.0, 0.01],
	"heavy": ["Use charged weapon strike", "Use the equipped weapon's charged attack animations, profile, and strike rules.", "", false],
}


static func field_help(key: String) -> String:
	match key:
		"shape":
			return "Defines where the attack can hit and which dimensions can be tuned. The ability's behavior may own a fixed shape."
		"floor_warning":
			return "Shows the attack area during enemy windup. Marked attacks lock their warning area and cannot be blocked."
	if FIELDS.has(key):
		return FIELDS[key][1]
	return "This ability stores the setting for its own script. Edit it in the source resource."


static func keys(profile: Dictionary) -> Array[String]:
	var shown: Array[String] = ["shape"]
	var shape := str(profile.get("shape", ""))
	for key: String in SHAPE_FIELDS.get(shape, []):
		shown.append(key)
	if not shape.is_empty() or profile.has("floor_warning"):
		shown.append("floor_warning")
	for key: String in FIELDS:
		if profile.has(key) and key not in shown:
			shown.append(key)
	for key: String in profile:
		if key not in shown:
			shown.append(key)
	# These stationary lane scripts use reach and width, not stored projectile velocity.
	if shape == "lane":
		shown.erase("speed")
	return shown
