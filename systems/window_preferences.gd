extends RefCounted

const PREFERENCES_PATH := "user://settings.cfg"
const SECTION := "display"
const FULLSCREEN_KEY := "fullscreen"


static func load_fullscreen(path: String, fallback: bool) -> bool:
	var value: Variant = _read_fullscreen(path)
	if value is not bool:
		value = _read_fullscreen(path + ".bak")
	return value if value is bool else fallback


static func save_fullscreen(path: String, enabled: bool) -> Error:
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	var final_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(final_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var staging_path := "%s.%d.%d.tmp" % [final_path, OS.get_process_id(), Time.get_ticks_usec()]
	var config := ConfigFile.new()
	config.set_value(SECTION, FULLSCREEN_KEY, enabled)
	var file := FileAccess.open(staging_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written := file.store_string(config.encode_to_text())
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK and (not written or _read_fullscreen(staging_path) != enabled):
		result = ERR_FILE_CANT_WRITE
	# A verified previous value remains readable between the two renames.
	if result == OK and _read_fullscreen(final_path) is bool:
		result = DirAccess.rename_absolute(final_path, final_path + ".bak")
	if result == OK:
		result = DirAccess.rename_absolute(staging_path, final_path)
	if result != OK:
		DirAccess.remove_absolute(staging_path)
	return result


static func _read_fullscreen(path: String) -> Variant:
	var config := ConfigFile.new()
	if config.load(path) != OK or not config.has_section_key(SECTION, FULLSCREEN_KEY):
		return null
	return config.get_value(SECTION, FULLSCREEN_KEY)
