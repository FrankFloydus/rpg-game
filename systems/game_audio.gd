extends Node

## Crossfaded exploration ambience and layered game cues from the sound catalogue.

const SILENCE_DB := -60.0
const FADE_SECONDS := 1.15
const Catalogue = preload("res://assets/audio/sound_catalogue.tres")
const SoundCue = preload("res://systems/sound_cue.gd")
const ItemBases := preload("res://data/items/bases.gd")
const Supplies := preload("res://systems/pack_supplies.gd")
const CardItems := preload("res://systems/card_items.gd")
const ZONES: Array[StringName] = [&"hub", &"dungeon"]

var _zone: StringName = &"hub"
var _active_zone: StringName
var _ambient: Dictionary[StringName, AudioStreamPlayer] = {}
var _oneshots: Dictionary[StringName, AudioStreamPlayer] = {}
var _custom_oneshots: Dictionary[SoundCue, AudioStreamPlayer] = {}
var _spatial_streams: Dictionary[StringName, AudioStream] = {}
var _fade: Tween
var _pitch_rng := RandomNumberGenerator.new()
var _audio_ready := false


func _ready() -> void:
	# Real-time audio cleanup can lag behind fixed-rate headless runs.
	if DisplayServer.get_name() == "headless" and AudioServer.get_driver_name() == "Dummy":
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pitch_rng.randomize()
	_audio_ready = true
	for zone: StringName in ZONES:
		var sound := _zone_sound(zone)
		var loop := sound.make_ambience() if sound != null else null
		if loop != null:
			_ambient[zone] = _make_player(loop, SILENCE_DB, 1)
	_crossfade(_zone)


func set_zone(zone: StringName) -> void:
	if not ZONES.has(zone):
		return
	_zone = zone
	if _audio_ready:
		_crossfade(zone)


func cue(event: StringName, weapon_heft := -1.0) -> void:
	var pitch := 1.0
	var extra_gain := 0.0
	if event == &"hit" and weapon_heft >= 0.0:
		var weight := clampf(weapon_heft / 1.24, 0.0, 1.0)
		pitch = lerpf(1.25, 0.73, weight)
		extra_gain = lerpf(-1.9, 1.35, weight)
	if not _play(event, pitch, extra_gain) and (event == &"walk" or event == &"sprint"):
		_play(&"step", pitch, extra_gain)


## The cue is determined by the item that lands, even when its affixes are unidentified.
static func item_placement_cue(item: Dictionary) -> StringName:
	match item.get("supply_kind"):
		Supplies.MATERIAL:
			return &"item_place_material"
		Supplies.TREASURE_KEY, Supplies.ROUTE_KEY:
			return &"item_place_key"
		Supplies.UNVEILING_SCROLL:
			return &"item_place_scroll"
		CardItems.KIND:
			return &"item_place_card"
	var type: String = item.get("type", "")
	return StringName("item_place_" + type) if ItemBases.TYPES.has(type) else &"item_place_generic"


func place_item(item: Dictionary) -> void:
	cue(item_placement_cue(item))


## Plays an authored override with the same volume and variation controls as a catalogue cue.
func play_sound(sound: SoundCue) -> void:
	if not _audio_ready or sound == null:
		return
	var playback := _custom_oneshots.get(sound) as AudioStreamPlayer
	if playback == null:
		var stream := sound.make_one_shot()
		if stream == null:
			return
		playback = _make_player(stream, sound.volume_db, 3)
		_custom_oneshots[sound] = playback
	playback.volume_db = sound.volume_db
	playback.play()


## Plays a catalogue cue on an authored spatial emitter. The caller retains its lifetime and attenuation.
func play_on(event: StringName, emitter: AudioStreamPlayer3D, extra_gain := 0.0) -> void:
	if not _audio_ready or not is_instance_valid(emitter):
		return
	var sound := Catalogue.sound_for(event)
	if sound == null:
		return
	var stream := _spatial_streams.get(event) as AudioStream
	if stream == null:
		stream = sound.make_one_shot()
		if stream == null:
			return
		_spatial_streams[event] = stream
	emitter.stream = stream
	emitter.volume_db = sound.volume_db + extra_gain
	emitter.play()


func swing(weapon: String, heft: float) -> void:
	var event := &"blunt_swing"
	if weapon == "unarmed":
		event = &"unarmed_swing"
	elif weapon == "sword_1h" or weapon == "dagger_1h":
		event = &"light_blade_swing" if heft < 0.48 else &"heavy_blade_swing"
	elif weapon.begins_with("sword_"):
		event = &"heavy_blade_swing"
	var weight := clampf(heft / 1.24, 0.0, 1.0)
	_play(event, lerpf(1.05, 0.92, weight), lerpf(-0.75, 0.75, weight))


func _play(event: StringName, pitch: float, extra_gain: float) -> bool:
	if not _audio_ready:
		return false
	var sound := Catalogue.sound_for(event)
	if sound == null:
		return false
	var playback: AudioStreamPlayer = _oneshots.get(event)
	if playback == null:
		var stream := sound.make_one_shot()
		if stream == null:
			return false
		playback = _make_player(stream, sound.volume_db, 1 if event == &"card_hover" else 3)
		_oneshots[event] = playback
	playback.volume_db = sound.volume_db + extra_gain
	playback.pitch_scale = pitch
	playback.play()
	return true


func _make_player(stream: AudioStream, gain: float, polyphony: int) -> AudioStreamPlayer:
	var playback := AudioStreamPlayer.new()
	playback.stream = stream
	playback.volume_db = gain
	playback.max_polyphony = polyphony
	add_child(playback)
	return playback


func _crossfade(zone: StringName) -> void:
	if zone == _active_zone:
		return
	_active_zone = zone
	if _fade != null:
		_fade.kill()
	var incoming: AudioStreamPlayer = _ambient.get(zone)
	var outgoing: AudioStreamPlayer = _ambient.get(&"dungeon" if zone == &"hub" else &"hub")
	if incoming == null and (outgoing == null or not outgoing.playing):
		return
	_fade = create_tween().set_parallel(true)
	if incoming != null:
		if not incoming.playing:
			incoming.play(_pitch_rng.randf_range(0.0, incoming.stream.get_length()))
		_fade.tween_property(incoming, "volume_linear",
			db_to_linear(_zone_sound(zone).volume_db), FADE_SECONDS)
	if outgoing != null and outgoing.playing:
		_fade.tween_property(outgoing, "volume_linear", db_to_linear(SILENCE_DB), FADE_SECONDS)
		_fade.tween_callback(outgoing.stop).set_delay(FADE_SECONDS)


func _zone_sound(zone: StringName) -> SoundCue:
	return Catalogue.sound_for(&"hub_ambience" if zone == &"hub" else &"dungeon_ambience")
