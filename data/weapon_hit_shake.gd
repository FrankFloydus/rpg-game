@tool
extends Resource
## Camera kick coefficients by weapon, material, weight and authored attack.
## XYZ are degrees and W is duration in seconds.

enum Pulse { STANDARD, MACE_THROUGH, MACE_LATERAL_STOP, MACE_DOWNCUT_STOP }

const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const SURFACES: Array[StringName] = [&"body", &"breakable", &"stone", &"metal", &"wood"]
const MACE_SURFACES: Array[StringName] = [&"armor", &"guard", &"mass"]
const OFFHAND_SUFFIX := "_offhand"
const MACE_CONTACT_DEFAULTS := {
	&"body": Vector4(0.18, 0.52, 0.26, 0.13),
	&"breakable": Vector4(0.32, 0.70, 0.36, 0.14),
	&"stone": Vector4(0.65, 2.15, 1.20, 0.23),
	&"metal": Vector4(0.48, 1.95, 1.05, 0.17),
	&"wood": Vector4(0.50, 1.35, 0.76, 0.24),
	&"armor": Vector4(0.40, 1.50, 0.90, 0.18),
	&"guard": Vector4(0.83, 1.85, 1.20, 0.23),
	&"mass": Vector4(0.38, 1.16, 0.63, 0.17),
}
const MACE_CHARGED_DEFAULTS := {
	&"body": Vector4(0.31, 2.65, 0.92, 0.22),
	&"breakable": Vector4(0.56, 1.36, 0.68, 0.18),
	&"stone": Vector4(0.90, 2.95, 1.52, 0.26),
	&"metal": Vector4(0.68, 2.72, 1.38, 0.20),
	&"wood": Vector4(0.73, 1.90, 1.00, 0.27),
	&"armor": Vector4(0.57, 2.12, 1.18, 0.21),
	&"guard": Vector4(1.05, 2.62, 1.55, 0.26),
	&"mass": Vector4(0.56, 1.66, 0.86, 0.20),
}
const MACE_DOWNCUT_DEFAULTS := {
	&"body": Vector4(0.50, 0.19, 0.31, 0.14),
	&"breakable": Vector4(0.69, 0.25, 0.43, 0.14),
	&"stone": Vector4(2.72, 0.30, 1.95, 0.24),
	&"metal": Vector4(2.43, 0.28, 1.62, 0.19),
	&"wood": Vector4(1.62, 0.24, 1.10, 0.25),
	&"armor": Vector4(1.89, 0.25, 1.23, 0.19),
	&"guard": Vector4(2.35, 0.35, 1.65, 0.24),
	&"mass": Vector4(1.27, 0.21, 0.86, 0.18),
}
# Relative pitch, yaw, roll, and time along the impact. Each axis settles on its own.
const THROUGH_PULSE: Array[Vector4] = [
	Vector4.ZERO, Vector4(0.88, 0.92, 0.85, 0.12), Vector4(1.0, 1.0, 1.0, 0.16),
	Vector4(0.52, 0.30, 0.38, 0.26), Vector4(0.03, 0.04, -0.45, 0.41),
	Vector4(-0.10, 0.26, -0.36, 0.55), Vector4(0.02, 0.04, -0.07, 0.81),
	Vector4(0.0, 0.0, 0.0, 1.0),
]
const LATERAL_STOP_PULSE: Array[Vector4] = [
	Vector4.ZERO, Vector4(-0.19, 0.61, 0.10, 0.13), Vector4(-0.08, 0.36, 0.24, 0.23),
	Vector4(0.36, -0.54, 0.71, 0.37), Vector4(1.0, -1.0, 1.0, 0.52),
	Vector4(0.46, -0.49, 0.53, 0.68), Vector4(-0.10, 0.09, -0.10, 0.85),
	Vector4(0.0, 0.0, 0.0, 1.0),
]
const DOWNCUT_STOP_PULSE: Array[Vector4] = [
	Vector4.ZERO, Vector4(0.76, 0.62, 0.68, 0.10), Vector4(1.0, 1.0, 0.78, 0.17),
	Vector4(0.67, 0.46, 0.24, 0.26), Vector4(0.02, -0.20, -0.63, 0.40),
	Vector4(-0.44, -0.20, -1.0, 0.53), Vector4(-0.17, -0.05, -0.40, 0.69),
	Vector4(0.09, 0.0, 0.10, 0.85), Vector4(0.0, 0.0, 0.0, 1.0),
]

@export var overrides: Dictionary[String, Vector4] = {}


static func has_weapon(weapon_type: String) -> bool:
	return weapon_type == "staff" or WeaponRoles.family(weapon_type) != &""


static func surface_ids(weapon_type: String) -> Array[StringName]:
	if not has_weapon(weapon_type):
		return []
	var rows := SURFACES.duplicate()
	if weapon_type == "mace_2h":
		rows.append_array(MACE_SURFACES)
	return rows


static func motion_id(clip: StringName, offhand := false) -> StringName:
	# Retired close-ready mace names resolve to the direction key they used when authored.
	var name := String(clip).get_file().trim_suffix("_close")
	return StringName(name + OFFHAND_SUFFIX) if offhand and not name.is_empty() else StringName(name)


static func source_clip(swing: StringName) -> StringName:
	return StringName(String(swing).trim_suffix(OFFHAND_SUFFIX))


static func is_charged_motion(swing: StringName) -> bool:
	var name := String(source_clip(swing))
	return name == "heavy" or name.begins_with("heavy_") or name == "dual_heavy" \
		or name.begins_with("dual_heavy_") or name == "dual_clash"


static func is_attack_motion(swing: StringName) -> bool:
	var name := String(source_clip(swing))
	if not (name == "light" or name.begins_with("light_") or name == "dual_light" \
			or name.begins_with("dual_light_") or is_charged_motion(swing)):
		return false
	for index in name.length():
		if not "abcdefghijklmnopqrstuvwxyz_0123456789".contains(name[index]):
			return false
	return motion_id(source_clip(swing), String(swing).ends_with(OFFHAND_SUFFIX)) == swing


func profile(weapon_type: String, surface: StringName, charged: bool, clip: StringName = &"") -> Vector4:
	var key := _key(weapon_type, surface, charged, clip)
	if overrides.has(key) and _valid_profile(overrides[key]):
		return overrides[key]
	return _inherited_profile(weapon_type, surface, charged, clip)


func _inherited_profile(weapon_type: String, surface: StringName, charged: bool, clip: StringName) -> Vector4:
	if not clip.is_empty():
		var shared: Vector4 = overrides.get(_key(weapon_type, surface, charged), Vector4.ZERO)
		if _valid_profile(shared):
			return shared
	return default_profile(weapon_type, surface, charged, clip)


func default_profile(weapon_type: String, surface: StringName, charged: bool, clip: StringName = &"") -> Vector4:
	if weapon_type == "mace_2h":
		var tuning := MACE_DOWNCUT_DEFAULTS if _mace_downcut(clip) else (
			MACE_CHARGED_DEFAULTS if charged else MACE_CONTACT_DEFAULTS)
		return tuning.get(surface, tuning[&"stone"])
	var two_handed := weapon_type.ends_with("2h")
	if surface == &"body":
		var blunt := WeaponRoles.family(weapon_type) == WeaponRoles.BLUNT
		var force := (1.15 if charged else 0.33) * (1.42 if two_handed else 1.0) * (1.27 if blunt else 1.0)
		var duration := (0.19 if charged else 0.12) + (0.025 if two_handed else 0.0) + (0.04 if blunt else 0.0)
		return Vector4(0.92 * force, 0.72 * force, 0.89 * force, duration)
	var force := (1.0 if two_handed else 0.80) if charged else 0.0
	return Vector4(1.12 * force, 0.68 * force, 1.10 * force, 0.16)


func has_profile_override(weapon_type: String, surface: StringName, charged: bool,
		clip: StringName = &"") -> bool:
	return overrides.has(_key(weapon_type, surface, charged, clip))


func set_profile(weapon_type: String, surface: StringName, charged: bool, value: Vector4,
		clip: StringName = &"") -> void:
	if surface not in surface_ids(weapon_type) or not _valid_profile(value):
		return
	var swing := motion_id(clip)
	if swing != &"" and (not is_attack_motion(swing) or is_charged_motion(swing) != charged):
		return
	var key := _key(weapon_type, surface, charged, swing)
	var inherited := _inherited_profile(weapon_type, surface, charged, swing)
	if value.is_equal_approx(inherited):
		clear_profile(weapon_type, surface, charged, swing)
	elif not overrides.has(key) or not overrides[key].is_equal_approx(value):
		overrides[key] = value
		emit_changed()


func clear_profile(weapon_type: String, surface: StringName, charged: bool,
		clip: StringName = &"") -> void:
	if overrides.erase(_key(weapon_type, surface, charged, clip)):
		emit_changed()


func validation_error() -> String:
	for key in overrides:
		var parts := key.split("/")
		if parts.size() not in [3, 4] or StringName(parts[1]) not in surface_ids(parts[0]) \
				or parts[2] not in ["light", "charged"]:
			return "Unknown weapon hit shake profile %s." % key
		if parts.size() == 4:
			var swing := StringName(parts[3])
			if not is_attack_motion(swing) or is_charged_motion(swing) != (parts[2] == "charged"):
				return "Unknown weapon hit shake direction %s." % key
		if not _valid_profile(overrides[key]):
			return "Use 0–30 degrees and 0.02–1.00 seconds for %s." % key
	return ""


func kick_degrees(weapon_type: String, surface: StringName, charged: bool, direction: Vector3,
		normal: Vector3, point_side: float, hits := 1, critical := false, clip: StringName = &"") -> Vector4:
	var tuning := profile(weapon_type, surface, charged, clip)
	var peak: Vector3
	if weapon_type == "mace_2h":
		peak = _mace_kick(tuning, surface, clip, direction, normal, point_side, hits, critical)
	elif surface == &"body":
		var emphasis := 1.0 + 0.06 * clampi(hits - 1, 0, 2) + (0.09 if critical else 0.0)
		peak = Vector3((direction.y + direction.z * (0.62 / 0.92)) * tuning.x,
			-direction.x * tuning.y, -direction.x * tuning.z) * emphasis
	else:
		peak = Vector3(tuning.x, point_side * tuning.y, point_side * tuning.z)
	return Vector4(peak.x, peak.y, peak.z, tuning.w)


static func _mace_kick(tuning: Vector4, surface: StringName, clip: StringName, direction: Vector3,
		normal: Vector3, point_side: float, hits: int, critical: bool) -> Vector3:
	var swing := String(motion_id(clip))
	var side := signf(direction.x + point_side * 0.25)
	if swing.ends_with("_left"):
		side = -1.0
	elif swing.ends_with("_right"):
		side = 1.0
	var downcut := _mace_downcut(clip)
	if surface in [&"body", &"breakable"]:
		var emphasis := 1.0 + 0.06 * clampi(hits - 1, 0, 2) + (0.09 if critical else 0.0)
		return Vector3(-tuning.x, side * tuning.y, side * tuning.z) * emphasis
	var incidence := clampf(-direction.dot(normal.normalized()), 0.0, 1.0) if normal.is_finite() else 0.0
	var strength := lerpf(0.80, 1.0, incidence)
	var pitch := -tuning.x if downcut else tuning.x
	var roll := tuning.z if downcut else side * tuning.z
	return Vector3(pitch, -side * tuning.y, roll) * strength


static func _mace_downcut(clip: StringName) -> bool:
	return motion_id(clip) in [&"light_down_left", &"light_down_right"]


static func pulse_for(weapon_type: String, surface: StringName, clip: StringName) -> Pulse:
	if weapon_type != "mace_2h":
		return Pulse.STANDARD
	if surface in [&"body", &"breakable"]:
		return Pulse.MACE_THROUGH
	return Pulse.MACE_DOWNCUT_STOP if _mace_downcut(clip) else Pulse.MACE_LATERAL_STOP


static func pulse_offset(entry: Vector3, peak: Vector3, elapsed: float, duration: float,
		pulse: Pulse = Pulse.STANDARD) -> Vector3:
	if duration <= 0.0:
		return Vector3.ZERO
	var phase := clampf(elapsed / duration, 0.0, 1.0)
	match pulse:
		Pulse.MACE_THROUGH:
			return _mace_pulse(THROUGH_PULSE, entry, peak, phase)
		Pulse.MACE_LATERAL_STOP:
			return _mace_pulse(LATERAL_STOP_PULSE, entry, peak, phase)
		Pulse.MACE_DOWNCUT_STOP:
			return _mace_pulse(DOWNCUT_STOP_PULSE, entry, peak, phase)
	var strike := smoothstep(0.0, 0.16, phase)
	var recoil := clampf((phase - 0.16) / 0.84, 0.0, 1.0)
	var settling := (1.0 - recoil) * (1.0 - recoil) * cos(recoil * TAU * 0.72)
	return entry * (1.0 - strike) + peak * strike * settling


static func _mace_pulse(keys: Array[Vector4], entry: Vector3, peak: Vector3, phase: float) -> Vector3:
	for index in range(1, keys.size()):
		var after := keys[index]
		if phase <= after.w:
			var before := keys[index - 1]
			var sample := before.lerp(after, smoothstep(before.w, after.w, phase))
			return entry * (1.0 - smoothstep(0.0, 0.17, phase)) + peak * Vector3(sample.x, sample.y, sample.z)
	return Vector3.ZERO


static func _key(weapon_type: String, surface: StringName, charged: bool, clip: StringName = &"") -> String:
	var shared := "%s/%s/%s" % [weapon_type, surface, "charged" if charged else "light"]
	var swing := motion_id(clip)
	return shared if swing == &"" else shared + "/" + String(swing)


static func _valid_profile(value: Vector4) -> bool:
	return value.is_finite() and minf(value.x, minf(value.y, value.z)) >= 0.0 \
		and maxf(value.x, maxf(value.y, value.z)) <= 30.0 \
		and (value.w >= 0.02 or is_equal_approx(value.w, 0.02)) and value.w <= 1.0
