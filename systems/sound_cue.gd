class_name HearthSoundCue
extends Resource
## An editable game sound and its playback settings.

## Drag imported audio files here. One-shot cues choose one variation at each playback.
## Ambience uses the first available file. An empty list silences the cue.
@export var clips: Array[AudioStream] = []
## Playback gain in decibels. Negative values make the cue quieter.
@export_range(-60.0, 12.0, 0.5, "suffix:dB") var volume_db := 0.0
## Small random pitch changes for one-shots. Zero plays each file at its recorded pitch.
@export_range(0.0, 0.25, 0.01) var pitch_variation := 0.0


func make_one_shot() -> AudioStream:
	var available := clips.filter(func(clip: AudioStream) -> bool: return clip != null)
	if available.is_empty():
		return null
	if available.size() == 1 and is_zero_approx(pitch_variation):
		return available[0]
	var variations := AudioStreamRandomizer.new()
	variations.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	variations.random_pitch = 1.0 + pitch_variation
	for clip in available:
		variations.add_stream(-1, clip)
	return variations


func make_ambience() -> AudioStream:
	for clip in clips:
		if clip == null:
			continue
		var loop := clip.duplicate() as AudioStream
		if loop is AudioStreamOggVorbis or loop is AudioStreamMP3:
			loop.loop = true
		elif loop is AudioStreamWAV and loop.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_begin = 0
			loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
		return loop
	return null
