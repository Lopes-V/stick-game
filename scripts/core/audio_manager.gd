class_name AudioManager
extends Node

const SAMPLE_RATE := 22050
const MAX_VOICES := 8

var enabled := true
var volume_scale := 0.55

var _voices: Array[AudioStreamPlayer] = []
var _stream_cache: Dictionary = {}
var _next_voice := 0

func play_event(event_name: String, _world_position := Vector2.ZERO, strength := 1.0) -> void:
	if not enabled or DisplayServer.get_name() == "headless":
		return
	_ensure_voices()
	var cache_key := _cache_key(event_name, strength)
	var stream: AudioStreamWAV = _stream_cache.get(cache_key)
	if stream == null:
		stream = _build_stream(event_name, strength, cache_key.hash())
		_stream_cache[cache_key] = stream
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stop()
	voice.stream = stream
	voice.volume_db = linear_to_db(maxf(volume_scale, 0.01))
	voice.play()

func _ensure_voices() -> void:
	if not _voices.is_empty():
		return
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "EffectVoice%d" % index
		voice.max_polyphony = 1
		add_child(voice)
		_voices.append(voice)

func _cache_key(event_name: String, strength: float) -> String:
	var bucket := clampi(int(strength / 180.0), 0, 5)
	return "%s_%d" % [event_name, bucket]

func _build_stream(event_name: String, strength: float, seed: int) -> AudioStreamWAV:
	var profile := _profile_for(event_name, strength)
	var duration := float(profile.duration)
	var frame_count := maxi(int(duration * SAMPLE_RATE), 1)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for frame in frame_count:
		var time := float(frame) / float(SAMPLE_RATE)
		var progress := time / duration
		var envelope := pow(maxf(1.0 - progress, 0.0), float(profile.decay))
		var frequency := lerpf(float(profile.frequency), float(profile.end_frequency), progress)
		var tone := sin(TAU * frequency * time)
		var noise := rng.randf_range(-1.0, 1.0)
		var sample := (tone * (1.0 - float(profile.noise)) + noise * float(profile.noise)) * envelope * float(profile.gain)
		pcm.encode_s16(frame * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	return stream

func _profile_for(event_name: String, strength: float) -> Dictionary:
	var normalized_strength := clampf(strength / 700.0, 0.0, 1.0)
	match event_name:
		"muzzle":
			return {"duration": 0.055 + normalized_strength * 0.045, "frequency": 150.0 - normalized_strength * 45.0, "end_frequency": 72.0, "noise": 0.62, "decay": 3.2, "gain": 0.52}
		"explosion", "core_shockwave", "ko":
			return {"duration": 0.18, "frequency": 82.0, "end_frequency": 38.0, "noise": 0.58, "decay": 2.0, "gain": 0.68}
		"impact_player", "hit", "slash":
			return {"duration": 0.065, "frequency": 210.0, "end_frequency": 105.0, "noise": 0.42, "decay": 2.8, "gain": 0.42}
		"impact_wall", "impact_object", "throw_impact":
			return {"duration": 0.075, "frequency": 430.0, "end_frequency": 165.0, "noise": 0.68, "decay": 3.5, "gain": 0.35}
		"pickup":
			return {"duration": 0.09, "frequency": 520.0, "end_frequency": 820.0, "noise": 0.04, "decay": 1.6, "gain": 0.28}
		_:
			return {"duration": 0.055, "frequency": 260.0, "end_frequency": 180.0, "noise": 0.25, "decay": 3.0, "gain": 0.25}
