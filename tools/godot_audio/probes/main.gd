extends Node2D

var voices: Array[AudioStreamPlayer2D] = []
var capture: AudioEffectCapture
var started := 0
var last_sample := 0
var samples_seen := 0
var peak := 0.0
var frames := 0
var seconds := 12.0
var output := ""
var finishing := false
var loading := true
var behavior := {}
var heap_churn: Array[PackedByteArray] = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--seconds="):
			seconds = clampf(float(arg.trim_prefix("--seconds=")), 1.0, 60.0)
	Engine.max_fps = 500
	Engine.physics_ticks_per_second = 120
	capture = AudioEffectCapture.new()
	capture.buffer_length = 0.2
	AudioServer.add_bus_effect(0, capture)
	var data := PackedByteArray()
	data.resize(8820)
	for i in 4410:
		data.encode_s16(i * 2, roundi(sin(TAU * 220.0 * i / 44100.0) * 8192.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 4410
	stream.data = data
	var camera := Camera2D.new()
	camera.position = Vector2(320, 180)
	add_child(camera)
	behavior = await _check_behavior(stream)
	for i in 32:
		var voice := AudioStreamPlayer2D.new()
		voice.stream = stream
		voice.volume_db = -30.0
		voice.max_distance = 2000.0
		voice.position = Vector2(320, 180)
		add_child(voice)
		voice.play()
		voices.append(voice)
	loading = false
	started = Time.get_ticks_msec()
	print("AUDIO_LIFETIME_BEGIN ", JSON.stringify({"engine": Engine.get_version_info(), "driver": AudioServer.get_driver_name(), "voices": voices.size(), "seconds": seconds}))

func _process(_delta: float) -> void:
	if finishing or loading:
		return
	frames += 1
	var now := Time.get_ticks_msec()
	var elapsed := float(now - started) / 1000.0
	for i in voices.size():
		voices[i].position.x = 320.0 + sin(elapsed * 4.0 + i) * 120.0
		voices[i].volume_db = -30.0 + sin(elapsed * 3.0 + i)
	# Ordinary bounded frame allocations make freed storage get reused, rather
	# than retaining a compatible bus-detail layout by allocator coincidence.
	heap_churn.clear()
	for i in 128:
		var bytes := PackedByteArray()
		bytes.resize(184 + (i % 10) * 8)
		bytes.fill(85)
		heap_churn.append(bytes)
	if now - last_sample >= 200:
		last_sample = now
		var available := capture.get_frames_available()
		if available > 0:
			var samples := capture.get_buffer(available)
			samples_seen += samples.size()
			for sample in samples:
				peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	if elapsed >= seconds:
		finishing = true
		var result := {"frames": frames, "seconds": elapsed, "samples_seen": samples_seen, "peak": peak,
			"audio_active": samples_seen > 1024 and peak > 0.001, "engine": Engine.get_version_info(),
			"behavior": behavior, "audio_behavior": behavior.get("passed", false)}
		for voice in voices:
			voice.stop()
		var mix_before: int = capture.get_pushed_frames() + capture.get_discarded_frames()
		var deadline := Time.get_ticks_msec() + 5000
		while capture.get_pushed_frames() + capture.get_discarded_frames() < mix_before + 2048 and Time.get_ticks_msec() < deadline:
			var available := capture.get_frames_available()
			if available > 0:
				capture.get_buffer(available)
			await get_tree().create_timer(0.01).timeout
		result["shutdown_mix_frames"] = capture.get_pushed_frames() + capture.get_discarded_frames() - mix_before
		result["shutdown_mixed"] = result["shutdown_mix_frames"] >= 2048
		for voice in voices:
			voice.stream = null
			voice.queue_free()
		voices.clear()
		AudioServer.remove_bus_effect(0, 0)
		capture = null
		await get_tree().process_frame
		await get_tree().process_frame
		print("AUDIO_LIFETIME_RESULT ", JSON.stringify(result))
		if not output.is_empty():
			var file := FileAccess.open(output, FileAccess.WRITE)
			file.store_string(JSON.stringify(result, "  "))
			file.close()
		get_tree().quit(0 if result["audio_active"] and result["shutdown_mixed"] and result["audio_behavior"] else 1)


# Capture stable mixed samples after each actual position/volume change.
# The deadline only guards a stalled driver; success requires real samples.
func _sample_level(voice: AudioStreamPlayer2D, x: float, db: float) -> Vector3:
	voice.position = Vector2(x, 180)
	voice.volume_db = db
	var mixed_before: int = capture.get_pushed_frames() + capture.get_discarded_frames()
	var deadline := Time.get_ticks_msec() + 3000
	while capture.get_pushed_frames() + capture.get_discarded_frames() < mixed_before + 8192 and Time.get_ticks_msec() < deadline:
		capture.clear_buffer()
		await get_tree().create_timer(0.005).timeout
	capture.clear_buffer()
	while capture.get_frames_available() < 2048 and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.005).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var level := Vector3(0, 0, samples.size())
	for sample in samples:
		level.x += absf(sample.x)
		level.y += absf(sample.y)
	if samples.size() > 0:
		level.x /= samples.size()
		level.y /= samples.size()
	return level


func _check_behavior(stream: AudioStreamWAV) -> Dictionary:
	var voice := AudioStreamPlayer2D.new()
	voice.stream = stream
	voice.max_distance = 2000.0
	voice.position = Vector2(320, 180)
	add_child(voice)
	voice.play()
	var center := await _sample_level(voice, 320, -12)
	var quiet := await _sample_level(voice, 320, -24)
	var left := await _sample_level(voice, 100, -12)
	var right := await _sample_level(voice, 540, -12)
	voice.stop()
	voice.stream = null
	voice.queue_free()
	var ratio := quiet.x / maxf(center.x, 0.000001)
	var enough := center.z >= 2048 and quiet.z >= 2048 and left.z >= 2048 and right.z >= 2048
	var balanced := absf(center.x - center.y) < center.x * 0.05
	var passed := enough and center.x > 0.001 and balanced and ratio > 0.20 and ratio < 0.30 and left.x > left.y * 1.2 and right.y > right.x * 1.2
	return {"passed": passed, "center": [center.x, center.y, center.z], "quiet": [quiet.x, quiet.y, quiet.z],
		"left": [left.x, left.y, left.z], "right": [right.x, right.y, right.z], "quiet_ratio": ratio}
