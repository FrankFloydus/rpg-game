extends RefCounted

## Append-only checkpoints adapted from the local Godot Save System's
## staged publication, checksum, and immutable generation design.

const SAVE_DIRECTORY := "user://checkpoints"
const MAGIC := "RPGSAVE"
const FORMAT_VERSION := 1
const RETAIN_GENERATIONS := 3
const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_JSON_DEPTH := 32
const MAX_JSON_INTEGER := 9007199254740991

static var _writer := Mutex.new()


static func has_save(directory: String = SAVE_DIRECTORY) -> bool:
	return not load_game(directory).is_empty()


static func load_game(directory: String = SAVE_DIRECTORY) -> Dictionary:
	for filename in _generations(directory):
		var checkpoint := _read_generation(directory.path_join(filename), filename)
		if checkpoint.error == OK:
			return checkpoint.state
		if checkpoint.error == ERR_FILE_UNRECOGNIZED:
			return {}
	return {}


static func write_game(state: Dictionary, directory: String = SAVE_DIRECTORY) -> Error:
	if state.is_empty() or not _is_json_value(state, 0):
		return ERR_INVALID_DATA
	_writer.lock()
	var result := _publish(state, directory)
	_writer.unlock()
	return result


static func _publish(state: Dictionary, directory: String) -> Error:
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if mkdir_error != OK:
		return mkdir_error
	var generations := _generations(directory)
	var sequence := 1
	if not generations.is_empty():
		var latest := generations[0]
		sequence = latest.substr(2, 20).to_int() + 1
		for name in generations:
			var checkpoint := _read_generation(directory.path_join(name), name)
			if checkpoint.error == ERR_FILE_UNRECOGNIZED:
				return ERR_FILE_UNRECOGNIZED
			if checkpoint.error == OK:
				break
	if sequence <= 0:
		return ERR_FILE_CANT_WRITE

	var nonce := Crypto.new().generate_random_bytes(8).hex_encode()
	var filename := "g-%020d-%s.save" % [sequence, nonce]
	var staging_path := directory.path_join(filename + ".tmp")
	var final_path := directory.path_join(filename)
	var payload := JSON.stringify(state, "", true, true)
	var header := "%s %d\n%s\n" % [MAGIC, FORMAT_VERSION, filename]
	var digest := (header + payload).sha256_text()
	var frame := (header + digest + "\n" + payload).to_utf8_buffer()
	if frame.size() > MAX_FILE_BYTES:
		return ERR_OUT_OF_MEMORY

	var staging := FileAccess.open(staging_path, FileAccess.WRITE)
	if staging == null:
		return FileAccess.get_open_error()
	staging.store_buffer(frame)
	staging.flush()
	var write_error := staging.get_error()
	staging.close()
	if write_error == OK and FileAccess.get_file_as_bytes(staging_path) != frame:
		write_error = ERR_FILE_CORRUPT
	if write_error == OK:
		write_error = DirAccess.rename_absolute(staging_path, final_path)
	if write_error != OK:
		DirAccess.remove_absolute(staging_path)
		return write_error
	if FileAccess.get_file_as_bytes(final_path) != frame:
		return ERR_FILE_CORRUPT

	_prune(directory)
	return OK


static func _generations(directory: String) -> PackedStringArray:
	var generations := PackedStringArray()
	var files := DirAccess.open(directory)
	if files == null:
		return generations
	for filename in files.get_files():
		if filename.length() != 44 or not filename.begins_with("g-") or not filename.ends_with(".save"):
			continue
		var sequence := filename.substr(2, 20)
		var nonce := filename.substr(23, 16)
		if filename[22] == "-" and sequence.is_valid_int() and sequence.to_int() > 0 and nonce.is_valid_hex_number():
			generations.append(filename)
	generations.sort()
	generations.reverse()
	return generations


static func _read_generation(path: String, expected_name: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return {"error": ERR_FILE_CORRUPT}
	var version_line := file.get_line()
	var generation_line := file.get_line()
	var digest_line := file.get_line()
	var payload := file.get_buffer(file.get_length() - file.get_position()).get_string_from_utf8()
	file.close()
	var header := version_line + "\n" + generation_line + "\n"
	if generation_line != expected_name or (header + payload).sha256_text() != digest_line:
		return {"error": ERR_FILE_CORRUPT}
	if version_line != "%s %d" % [MAGIC, FORMAT_VERSION]:
		return {"error": ERR_FILE_UNRECOGNIZED}
	var document := JSON.new()
	if document.parse(payload) != OK or document.data is not Dictionary or document.data.is_empty():
		return {"error": ERR_FILE_CORRUPT}
	if not _is_json_value(document.data, 0):
		return {"error": ERR_FILE_CORRUPT}
	return {"error": OK, "state": document.data}


static func _prune(directory: String) -> void:
	var healthy := 0
	for filename in _generations(directory):
		var path := directory.path_join(filename)
		if _read_generation(path, filename).error == OK:
			healthy += 1
			if healthy > RETAIN_GENERATIONS:
				DirAccess.remove_absolute(path)


static func _is_json_value(value: Variant, depth: int) -> bool:
	if depth > MAX_JSON_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_INT:
			# The JSON parser returns numbers as doubles. Store wider IDs as strings.
			return value >= -MAX_JSON_INTEGER and value <= MAX_JSON_INTEGER
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for element: Variant in value:
				if not _is_json_value(element, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not _is_json_value(value[key], depth + 1):
					return false
			return true
	return false
