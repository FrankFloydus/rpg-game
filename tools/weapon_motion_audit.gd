extends SceneTree
## Audits external reference exports and samples authored weapon scenes without modifying either.

const AttackAnimation := preload("res://combat/attack_animation.gd")
const BASIS_TOLERANCE := 0.0001
const TRANSFORM_TOLERANCE := 0.0002
const PHASES := ["chamber", "trace_start", "impact", "trace_end", "retraction"]
const PHASE_PAIRS := {
	"chamber_to_impact": ["chamber", "impact"],
	"trace_start_to_end": ["trace_start", "trace_end"],
	"impact_to_retraction": ["impact", "retraction"],
}

var _input_paths := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args.size() > 2:
		printerr("Usage: godot --headless --path . --script res://tools/weapon_motion_audit.gd -- jobs.json [report.json]")
		quit(2)
		return
	var path := _resolve_path(ProjectSettings.globalize_path("res://"), args[0])
	var errors: Array[String] = []
	var config := _read_json(path, errors)
	var results: Array[Dictionary] = []
	var jobs: Variant = config.get("jobs")
	var ids := {}
	if (not jobs is Array or jobs.is_empty()) and errors.is_empty():
		errors.append("The configuration must contain a nonempty jobs array.")
	if jobs is Array:
		for index in jobs.size():
			var job: Variant = jobs[index]
			if not job is Dictionary or not job.get("id") is String or job.id.strip_edges().is_empty():
				errors.append("Job %d requires a nonempty string id." % index)
			elif ids.has(job.id):
				errors.append("Duplicate job id %s." % job.id)
			else:
				ids[job.id] = true
				results.append(_audit_job(job, path.get_base_dir()))
	var failed := 0
	var review := 0
	for result in results:
		if result.status == "fail":
			failed += 1
		elif result.status == "review":
			review += 1
	var report := {
		"version": 1, "errors": errors, "jobs": results, "failed": failed, "review": review,
		"passed": results.size() - failed - review,
		"scope": "Isolated clip samples and configured measurements. Verify gameplay transitions and camera framing in Forward+.",
	}
	var body := JSON.stringify(report, "\t", false) + "\n"
	if args.size() == 2:
		var output_path := _resolve_path(ProjectSettings.globalize_path("res://"), args[1])
		if output_path.get_extension().to_lower() != "json" or _input_paths.has(output_path.to_lower()):
			printerr("The report must be a JSON path distinct from any audit input.")
			quit(2)
			return
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null or not file.store_string(body):
			printerr("Could not write report to ", output_path)
			quit(2)
			return
		print("Weapon motion audit: %d passed, %d for review, %d failed. %s" %
			[report.passed, review, failed, output_path])
	else:
		print(body)
	quit(2 if not errors.is_empty() else int(failed > 0))


func _audit_job(job: Dictionary, folder: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var report := {"id": job.id, "errors": errors, "warnings": warnings}
	var reference: Variant = job.get("reference")
	var target: Variant = job.get("target")
	if reference is Dictionary:
		report.reference = _audit_reference(reference, folder, errors, warnings)
	else:
		errors.append("reference must be an object.")
	if target is Dictionary:
		report.target = _audit_target(target, folder, errors, warnings)
	elif target != null:
		errors.append("target must be an object.")
	else:
		warnings.append("No target scene supplied.")
	report.gates = _check_gates(job.get("gates", {}), report, errors)
	report.status = "fail" if not errors.is_empty() else ("review" if not warnings.is_empty() else "pass")
	return report


func _audit_reference(config: Dictionary, folder: String, errors: Array[String], warnings: Array[String]) -> Dictionary:
	var motion_path := ""
	var clip := {}
	var initial_errors := errors.size()
	var manifest_path: Variant = config.get("manifest")
	var raw_path: Variant = config.get("motion")
	if manifest_path is String and raw_path == null:
		var manifest := _read_json(_resolve_path(folder, manifest_path), errors)
		var format: Variant = manifest.get("format")
		var version: Variant = manifest.get("version")
		if not ((format == "vermintide_sequence_reference" and version == 2)
				or (format == "vermintide_analytical_motion_reference" and version == 1)):
			errors.append("Unsupported reference manifest format/version.")
		var manifest_motion: Variant = manifest.get("motion")
		if manifest_motion is String and not manifest_motion.is_empty():
			motion_path = _resolve_path(_resolve_path(folder, manifest_path).get_base_dir(), manifest_motion)
		else:
			errors.append("The reference manifest has no motion file.")
		var capture: Variant = manifest.get("capture")
		if capture is Dictionary and capture.get("clip") is Dictionary:
			clip = capture.clip
	elif raw_path is String and manifest_path == null:
		motion_path = _resolve_path(folder, raw_path)
	else:
		errors.append("Provide exactly one of reference.manifest or reference.motion.")
	if errors.size() != initial_errors:
		return {}
	var data := _read_json(motion_path, errors)
	if errors.size() != initial_errors:
		return {}
	if data.get("format") != "vermintide_sequence_motion" or data.get("version") != 1 \
			or data.get("axes") != "godot" or data.get("units") != "meters" \
			or data.get("time_unit") != "seconds" or data.get("space") != "model" \
			or data.get("transform_layout") != {"origin": "XYZ", "basis": "three XYZ column vectors"}:
		errors.append("Expected Viewer motion v1 with model-space Godot XYZ basis columns, metres and seconds.")
		return {}
	var source_rows: Variant = data.get("samples")
	if not source_rows is Array or source_rows.size() < 2:
		errors.append("Reference requires at least two motion samples.")
		return {}
	var rows := _read_motion_rows(source_rows, errors)
	if errors.size() != initial_errors:
		return {}
	var start: float = rows.front().time
	var end: float = rows.back().time
	if clip.has("duration") and _is_number(clip.duration) and not is_equal_approx(float(clip.duration), end):
		errors.append("Reference endpoint differs from the manifest clip duration.")
	var times := _phase_times(config.get("phases", {}), start, end, "reference", errors, warnings)
	var provenance: Variant = config.get("provenance")
	if not provenance is String or provenance.strip_edges().is_empty():
		warnings.append("Source phase provenance is missing. Phase labels alone do not establish in-game timing.")
	var head: Variant = _optional_vector(config, "head", "reference", errors, warnings)
	var shaft := _shaft_axis(config, "reference", errors)
	var socket: Variant = config.get("socket", "right")
	if not socket is String or socket.is_empty():
		errors.append("reference.socket must be a nonempty socket name.")
		return {}
	var phases := {}
	var opening_camera: Variant = rows.front().get("camera")
	var camera_available := opening_camera is Transform3D
	for name in times:
		var sample := _motion_sample(rows, times[name], socket)
		if sample.get("socket") is Transform3D:
			var socket_pose: Transform3D = sample.socket
			phases[name] = _phase_measurement(times[name], socket_pose, head, shaft)
			phases[name].socket = _vector_json(socket_pose.origin)
			phases[name].socket_depth = -socket_pose.origin.z
			if sample.get("camera") is Transform3D and opening_camera is Transform3D:
				var rotation: Basis = opening_camera.basis.inverse() * sample.camera.basis
				phases[name].camera_degrees = _camera_angles(rotation)
			else:
				camera_available = false
		else:
			warnings.append("Reference has no camera-relative %s socket at phase %s." % [socket, name])
	if not camera_available:
		warnings.append("Source camera rotation is unavailable at one or more phases.")
	return {
		"motion": motion_path,
		"motion_sha256": FileAccess.get_sha256(motion_path),
		"clip": clip,
		"sample_count": rows.size(), "start": start, "end": end,
		"provenance": provenance, "socket": socket,
		"hand_observable": "Attachment socket; standard Viewer motion export does not supply actual wrist joints.",
		"track_nodes": data.get("track_nodes", {}),
		"camera_observable": "Model-space camera rotation relative to the first sample; may include model root motion.",
		"head_local": _vector_json(head) if head is Vector3 else null,
		"phases": phases,
		"metrics": _phase_metrics(phases),
	}


func _read_motion_rows(samples: Array, errors: Array[String]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var previous := -INF
	for index in samples.size():
		var source: Variant = samples[index]
		var label := "Reference sample %d" % index
		if not source is Dictionary or not _is_number(source.get("time")) \
				or float(source.time) < 0.0 or float(source.time) <= previous:
			errors.append("%s has an invalid or non-increasing timestamp." % label)
			break
		previous = float(source.time)
		var before := errors.size()
		var row := {"time": previous, "camera_relative_sockets": {}}
		var camera: Variant = _read_transform(source.camera, label + " camera", errors) if source.has("camera") else null
		var sockets := _read_socket_map(source, "sockets", label, errors)
		var relative := _read_socket_map(source, "camera_relative_sockets", label, errors)
		var head: Variant = _read_transform(source.head, label + " head", errors) if source.has("head") else null
		var relative_head: Variant = _read_transform(source.camera_relative_head, label + " camera_relative_head", errors) \
			if source.has("camera_relative_head") else null
		if camera is Transform3D:
			row.camera = camera
			var model_to_camera: Transform3D = camera.affine_inverse()
			for side in sockets:
				var derived: Transform3D = model_to_camera * sockets[side]
				if relative.has(side) and not _poses_agree(derived, relative[side]):
					errors.append("%s camera-relative %s socket disagrees with the model-space transform." % [label, side])
				relative[side] = relative.get(side, derived)
			if head is Transform3D and relative_head is Transform3D and not _poses_agree(model_to_camera * head, relative_head):
				errors.append("%s camera-relative head disagrees with the model-space transform." % label)
		if errors.size() != before:
			break
		row.camera_relative_sockets = relative
		rows.append(row)
	return rows


func _motion_sample(rows: Array[Dictionary], time: float, socket: String) -> Dictionary:
	for index in range(1, rows.size()):
		var later := rows[index]
		if time > float(later.time):
			continue
		var earlier := rows[index - 1]
		var fraction := inverse_lerp(float(earlier.time), float(later.time), time)
		return {
			"socket": _interpolate_pose(earlier.camera_relative_sockets.get(socket),
				later.camera_relative_sockets.get(socket), fraction),
			"camera": _interpolate_pose(earlier.get("camera"), later.get("camera"), fraction),
		}
	return {}


func _interpolate_pose(a: Variant, b: Variant, fraction: float) -> Variant:
	if fraction <= 0.0:
		return a
	if fraction >= 1.0:
		return b
	if a is Transform3D and b is Transform3D:
		return a.interpolate_with(b, fraction)
	return null


func _audit_target(config: Dictionary, folder: String, errors: Array[String], warnings: Array[String]) -> Dictionary:
	var scene_path: Variant = config.get("scene")
	var animation: Variant = config.get("animation")
	if not scene_path is String or scene_path.is_empty() or not animation is String or animation.is_empty():
		errors.append("Target requires a weapon PackedScene and a nonempty animation name.")
		return {}
	var path: String = scene_path if scene_path.begins_with("res://") else _resolve_path(folder, scene_path)
	if not ResourceLoader.exists(path, "PackedScene"):
		errors.append("Target PackedScene %s does not exist." % path)
		return {}
	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		errors.append("Could not load target scene %s." % path)
		return {}
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		errors.append("Target weapon scene root must be a Node3D.")
		return {}
	var weapon := instance as Node3D
	root.add_child(weapon)
	var report := _sample_target(weapon, config, errors, warnings)
	weapon.free()
	report.scene = path
	report.animation = animation
	return report


func _sample_target(weapon: Node3D, config: Dictionary, errors: Array[String], warnings: Array[String]) -> Dictionary:
	var player := weapon.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var pose := weapon.get_node_or_null("Pose") as Node3D
	if not is_instance_valid(player) or not is_instance_valid(pose) or not player.has_animation(config.animation):
		errors.append("Target scene requires Pose and AnimationPlayer with animation %s." % config.animation)
		return {}
	var animation := player.get_animation(config.animation)
	var timing := AttackAnimation.read(animation)
	if timing == null or timing.trace_start >= timing.trace_end:
		errors.append("Target animation lacks valid AttackAnimation combat markers.")
		return {}
	var impact_is_explicit := animation.has_marker(AttackAnimation.IMPACT)
	if impact_is_explicit and not is_equal_approx(timing.impact, animation.get_marker_time(AttackAnimation.IMPACT)):
		warnings.append("Target authored Impact is outside the trace window. The gameplay sampler clamps it.")
	if not is_equal_approx(timing.input_buffer, animation.get_marker_time(AttackAnimation.INPUT_BUFFER)):
		warnings.append("Target authored Input Buffer is outside the clip. The gameplay sampler clamps it.")
	var requested := {
		"trace_start": timing.trace_start,
		"impact": timing.impact,
		"trace_end": timing.trace_end,
	}
	for name in ["chamber", "retraction"]:
		if config.has(name):
			requested[name] = config[name]
	var times := _phase_times(requested, 0.0, timing.length, "target", errors, warnings)
	var head: Variant = _optional_vector(config, "head", "target", errors, warnings)
	var shaft := _shaft_axis(config, "target", errors)
	var camera := weapon.get_node_or_null("CameraMotion") as Node3D
	var markers := {
		"right_wrist": pose.get_node_or_null("RightWrist") as Node3D,
		"left_wrist": pose.get_node_or_null("LeftWrist") as Node3D,
		"trace_root": pose.get_node_or_null("TraceRoot") as Node3D,
		"trace_tip": pose.get_node_or_null("TraceTip") as Node3D,
	}
	var phases := {}
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(config.animation)
	var ordered: Array = times.keys()
	ordered.sort_custom(func(first: String, second: String) -> bool: return times[first] < times[second])
	for name in ordered:
		player.seek(times[name], true, true)
		phases[name] = _phase_measurement(times[name], pose.global_transform, head, shaft)
		for role in markers:
			var marker: Node3D = markers[role]
			if is_instance_valid(marker):
				phases[name][role] = _vector_json(marker.global_position)
				phases[name][role + "_depth"] = -marker.global_position.z
		if is_instance_valid(camera):
			phases[name].camera_degrees = _camera_angles(camera.basis)
	return {
		"length": timing.length,
		"input_buffer": timing.input_buffer,
		"impact_is_explicit": impact_is_explicit,
		"provenance": "Authored Godot animation sampled in the rest weapon mount at clip time.",
		"hand_observable": "Target Pose wrist markers; excludes procedural sway and runtime arm blending.",
		"camera_observable": "Authored local CameraMotion rotation; excludes movement, recoil and user aim.",
		"head_local": _vector_json(head) if head is Vector3 else null,
		"phases": phases,
		"metrics": _phase_metrics(phases),
	}


func _phase_times(requested: Variant, start: float, end: float, label: String, errors: Array[String],
		warnings: Array[String]) -> Dictionary:
	var times := {}
	if not requested is Dictionary:
		errors.append("%s phases must be an object." % label)
		return times
	var missing := PackedStringArray()
	for name in PHASES:
		if not requested.has(name):
			missing.append(name)
		elif not _is_number(requested[name]) or requested[name] < start or requested[name] > end:
			errors.append("%s.%s must be a finite clip time within [%.6f, %.6f]." % [label, name, start, end])
		else:
			times[name] = float(requested[name])
	for pair in [["chamber", "impact"], ["trace_start", "impact"], ["impact", "trace_end"], ["impact", "retraction"]]:
		if times.has(pair[0]) and times.has(pair[1]) and times[pair[0]] > times[pair[1]]:
			errors.append("%s phase %s is later than %s." % [label, pair[0], pair[1]])
	if not missing.is_empty():
		warnings.append("%s phases not supplied: %s." % [label, ", ".join(missing)])
	return times


func _phase_measurement(time: float, pose: Transform3D, head: Variant, shaft: Vector3) -> Dictionary:
	var heading := (pose.basis * shaft).normalized()
	var result := {
		"time": time, "shaft": _vector_json(heading),
		"shaft_pitch_deg": rad_to_deg(asin(clampf(heading.y, -1.0, 1.0))),
	}
	if head is Vector3:
		var center: Vector3 = pose * head
		result.head = _vector_json(center)
		result.head_depth = -center.z
	return result


func _phase_metrics(phases: Dictionary) -> Dictionary:
	var metrics := {}
	for name in PHASE_PAIRS:
		var pair: Array = PHASE_PAIRS[name]
		if not phases.has(pair[0]) or not phases.has(pair[1]):
			continue
		var start: Dictionary = phases[pair[0]]
		var finish: Dictionary = phases[pair[1]]
		if start.has("head") and finish.has("head"):
			var delta := _vector(finish.head) - _vector(start.head)
			metrics[name + "_forward"] = -delta.z
			metrics[name + "_horizontal"] = delta.x
			metrics[name + "_vertical"] = delta.y
			if name == "impact_to_retraction":
				metrics.impact_to_retraction_back = delta.z
		if start.has("trace_tip") and finish.has("trace_tip"):
			var tip_delta := _vector(finish.trace_tip) - _vector(start.trace_tip)
			metrics[name + "_trace_tip_forward"] = -tip_delta.z
	for name in phases:
		var phase: Dictionary = phases[name]
		for measure in ["shaft_pitch_deg", "head_depth", "right_wrist_depth", "left_wrist_depth", "socket_depth"]:
			if phase.has(measure):
				metrics[name + "_" + measure] = phase[measure]
	return metrics


func _check_gates(gates: Variant, report: Dictionary, errors: Array[String]) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if not gates is Dictionary:
		errors.append("gates must be an object keyed by dotted report metric paths.")
		return results
	for key in gates:
		var bounds: Variant = gates[key]
		if not bounds is Dictionary or (not bounds.has("min") and not bounds.has("max")) \
				or (bounds.has("min") and not _is_number(bounds.min)) \
				or (bounds.has("max") and not _is_number(bounds.max)):
			errors.append("Gate %s must declare finite min and/or max." % key)
			continue
		var low := float(bounds.get("min", -INF))
		var high := float(bounds.get("max", INF))
		var value: Variant = report
		for part in String(key).split("."):
			value = value.get(part) if value is Dictionary else null
		var accepted: bool = _is_number(value) and float(value) >= low and float(value) <= high
		if not accepted:
			errors.append("Gate %s failed (actual %s, min %s, max %s)." % [key, value, low, high])
		results.append({"path": key, "bounds": bounds, "actual": value, "accepted": accepted})
	return results


func _camera_angles(basis: Basis) -> Dictionary:
	var angles := basis.orthonormalized().get_euler()
	return {"yaw_right": -rad_to_deg(angles.y), "pitch_up": rad_to_deg(angles.x), "roll": rad_to_deg(angles.z)}


func _read_socket_map(row: Dictionary, name: String, label: String, errors: Array[String]) -> Dictionary:
	var raw: Variant = row.get(name, {})
	var map := {}
	if not raw is Dictionary:
		errors.append("%s.%s must be an object." % [label, name])
		return map
	for side in raw:
		var pose: Variant = _read_transform(raw[side], "%s.%s.%s" % [label, name, side], errors)
		if pose is Transform3D:
			map[side] = pose
	return map


func _read_transform(raw: Variant, label: String, errors: Array[String]) -> Variant:
	if not raw is Dictionary or not _is_vector(raw.get("origin")) or not raw.get("basis") is Array \
			or raw.basis.size() != 3 or not raw.basis.all(_is_vector):
		errors.append("%s must have finite XYZ origin and three finite basis columns." % label)
		return null
	var basis := Basis(_vector(raw.basis[0]), _vector(raw.basis[1]), _vector(raw.basis[2]))
	var result := Transform3D(basis, _vector(raw.origin))
	if not result.is_finite() or absf(basis.determinant() - 1.0) > BASIS_TOLERANCE \
			or absf(basis.x.length_squared() - 1.0) > BASIS_TOLERANCE \
			or absf(basis.y.length_squared() - 1.0) > BASIS_TOLERANCE \
			or absf(basis.z.length_squared() - 1.0) > BASIS_TOLERANCE \
			or absf(basis.x.dot(basis.y)) > BASIS_TOLERANCE \
			or absf(basis.x.dot(basis.z)) > BASIS_TOLERANCE \
			or absf(basis.y.dot(basis.z)) > BASIS_TOLERANCE:
		errors.append("%s must be a proper orthonormal transform." % label)
		return null
	return result


func _poses_agree(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= TRANSFORM_TOLERANCE \
		and a.basis.x.distance_to(b.basis.x) <= TRANSFORM_TOLERANCE \
		and a.basis.y.distance_to(b.basis.y) <= TRANSFORM_TOLERANCE \
		and a.basis.z.distance_to(b.basis.z) <= TRANSFORM_TOLERANCE


func _optional_vector(config: Dictionary, name: String, label: String, errors: Array[String],
		warnings: Array[String]) -> Variant:
	if not config.has(name):
		warnings.append("%s has no calibrated %s point." % [label, name])
		return null
	var raw: Variant = config[name]
	if not _is_vector(raw) or not _vector(raw).is_finite():
		errors.append("%s.%s must be a finite XYZ vector." % [label, name])
		return null
	return _vector(raw)


func _shaft_axis(config: Dictionary, label: String, errors: Array[String]) -> Vector3:
	var raw: Variant = config.get("shaft", [0.0, 1.0, 0.0])
	if not _is_vector(raw) or not _vector(raw).is_finite() or _vector(raw).is_zero_approx():
		errors.append("%s.shaft must be a finite nonzero XYZ direction." % label)
		return Vector3.UP
	return _vector(raw).normalized()


func _is_vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(_is_number)


func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


func _vector_json(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _resolve_path(folder: String, path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	if not path.is_absolute_path():
		path = folder.path_join(path)
	return path.replace("\\", "/").simplify_path()


func _read_json(path: String, errors: Array[String]) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	_input_paths[path.to_lower()] = true
	if file == null:
		errors.append("Could not read %s." % path)
		return {}
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK:
		errors.append("%s line %d: %s" % [path, parsed.get_error_line(), parsed.get_error_message()])
		return {}
	if not parsed.data is Dictionary:
		errors.append("%s must contain a JSON object." % path)
		return {}
	return parsed.data
