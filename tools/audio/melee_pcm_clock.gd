extends Node
## NE261 probe-only four-bus recording. No gameplay or bus-routing change.
const NAMES := ["Master", "SFX", "Music", "Ambience"]
var buses: Array[Dictionary] = []
var problems: Array[String] = []
var active := false
var cleaned := false
var buffer_seconds := 10.0

func fail(context: String) -> void:
	problems.append(context)
	push_error("[MeleePCMClock] " + context)

func counters(capture: AudioEffectCapture) -> Dictionary:
	return {"pushed":capture.get_pushed_frames(),"discarded":capture.get_discarded_frames()}

func attach() -> bool:
	if not buses.is_empty() or cleaned:
		fail("attach called twice or after cleanup")
		return false
	for name in NAMES:
		var index := AudioServer.get_bus_index(name)
		if index < 0:
			fail("missing bus=" + name)
			continue
		var capture := AudioEffectCapture.new()
		capture.buffer_length = buffer_seconds
		AudioServer.add_bus_effect(index, capture)
		buses.append({"name":name,"index":index,"capture":capture,
			"chunks":[],"gains":[],"gain_checks":0})
	return problems.is_empty()

func start() -> bool:
	if buses.size() != NAMES.size() or not problems.is_empty():return false
	var deadline := Time.get_ticks_usec() + 2000000
	while Time.get_ticks_usec() < deadline:
		var ready := true
		for bus in buses:ready = ready and bus["capture"].get_pushed_frames() > 0
		if ready:break
		await get_tree().process_frame
	for bus in buses:
		if bus["capture"].get_pushed_frames() <= 0:fail("audio-thread readiness timeout bus=" + bus["name"])
	if not problems.is_empty():return false
	AudioServer.lock()
	for bus in buses:
		bus["capture"].clear_buffer()
		bus["base"] = counters(bus["capture"])
		bus["gain_db"] = AudioServer.get_bus_volume_db(bus["index"])
		bus["send"] = String(AudioServer.get_bus_send(bus["index"]))
		bus["last_gain"] = bus["gain_db"]
		bus["last_send"] = bus["send"]
		_observe(bus,"first")
	active = true
	AudioServer.unlock()
	return true

func mark() -> Dictionary:
	var result := {}
	AudioServer.lock()
	for bus in buses:
		var current := counters(bus["capture"])
		result[bus["name"]] = current["pushed"] + current["discarded"] - bus["base"]["pushed"] - bus["base"]["discarded"]
	AudioServer.unlock()
	return result

func _observe(bus: Dictionary, kind: String) -> void:
	bus["gains"].append({"kind":kind,"counter":counters(bus["capture"]),
		"gain_db":AudioServer.get_bus_volume_db(bus["index"]),"send":String(AudioServer.get_bus_send(bus["index"]))})

func _drain(bus: Dictionary, last := false) -> void:
	var index: int = bus["index"]
	if index >= AudioServer.bus_count or String(AudioServer.get_bus_name(index)) != bus["name"]:
		fail("bus index/name changed bus=" + bus["name"])
		return
	var available: int = bus["capture"].get_frames_available()
	if available > 0:bus["chunks"].append(bus["capture"].get_buffer(available))
	bus["gain_checks"] += 1
	var gain := AudioServer.get_bus_volume_db(index)
	var send := String(AudioServer.get_bus_send(index))
	if gain != bus["last_gain"] or send != bus["last_send"]:
		_observe(bus,"change")
		fail("gain/send changed bus=%s gain=%s->%s send=%s->%s" % [bus["name"],bus["last_gain"],gain,bus["last_send"],send])
		bus["last_gain"] = gain
		bus["last_send"] = send
	if last:_observe(bus,"last")

func _process(_delta: float) -> void:
	if not active:return
	AudioServer.lock()
	for bus in buses:_drain(bus)
	AudioServer.unlock()

func stop() -> Dictionary:
	AudioServer.lock()
	var wall := Time.get_ticks_usec()
	var frames := {}
	for bus in buses:
		bus["end"] = counters(bus["capture"])
		frames[bus["name"]] = bus["end"]["pushed"] + bus["end"]["discarded"] - bus["base"]["pushed"] - bus["base"]["discarded"]
		_drain(bus,true)
		# Stop feeding only this capture, by identity, at the frozen boundary.
		var found := false
		for n in AudioServer.get_bus_effect_count(bus["index"]):
			if AudioServer.get_bus_effect(bus["index"],n)==bus["capture"]:
				AudioServer.set_bus_effect_enabled(bus["index"],n,false)
				found=true
		if not found:fail("stop-feed effect missing bus=" + bus["name"])
	active = false
	AudioServer.unlock()
	return {"wall_usec_diagnostic_only":wall,"frames":frames}

func save(out: String, end: Dictionary) -> Dictionary:
	var result := {"schema":"ne261-capture-pcm-v1","stop":end,"mix_rate":int(AudioServer.get_mix_rate()),"buses":{},"problems":problems}
	for bus in buses:
		var captured := PackedVector2Array()
		for chunk: PackedVector2Array in bus["chunks"]:captured.append_array(chunk)
		var pushed: int = bus["end"]["pushed"] - bus["base"]["pushed"]
		var discarded: int = bus["end"]["discarded"] - bus["base"]["discarded"]
		var name: String = bus["name"]
		if discarded != 0 or pushed != captured.size():fail("PCM/counter/discard mismatch bus=" + name)
		var pcm := PackedByteArray()
		pcm.resize(captured.size()*4)
		var finite := true
		for frame in captured.size():
			var sample := captured[frame]
			if not is_finite(sample.x) or not is_finite(sample.y):
				finite=false
				fail("nonfinite captured PCM bus=%s frame=%d" % [name,frame])
				break
			# Exact same quantization as official AudioEffectRecord 16-bit output.
			pcm.encode_s16(frame*4,int(clampf(sample.x*32768.0,-32768.0,32767.0)))
			pcm.encode_s16(frame*4+2,int(clampf(sample.y*32768.0,-32768.0,32767.0)))
		var wave: AudioStreamWAV
		if finite:
			wave=AudioStreamWAV.new()
			wave.format=AudioStreamWAV.FORMAT_16_BITS
			wave.stereo=true
			wave.mix_rate=result["mix_rate"]
			wave.data=pcm
		var frames: int = wave.data.size()/4 if wave != null else 0
		var path := out.path_join("bus-" + name + ".f32")
		var file := FileAccess.open(path,FileAccess.WRITE)
		var capture_error := FileAccess.get_open_error()
		if file == null:
			fail("open failed bus=%s path=%s error=%s" % [name,path,error_string(capture_error)])
		else:
			file.store_buffer(captured.to_byte_array())
			file.flush()
			capture_error = file.get_error()
			file.close()
			if capture_error != OK:fail("write failed bus=%s path=%s error=%s" % [name,path,error_string(capture_error)])
		var wav_path := out.path_join("bus-" + name + ".wav")
		var saved: Error = wave.save_to_wav(wav_path) if wave != null else ERR_INVALID_DATA
		if saved != OK:fail("WAV save failed bus=%s path=%s error=%s" % [name,wav_path,error_string(saved)])
		var legacy_file := ""
		var legacy_copy_error := OK
		var legacy_copy_attempted := false
		if saved == OK and name in ["Master","SFX"]:
			legacy_file = "melee-master.wav" if name=="Master" else "melee-sfx.wav"
			var legacy_path := out.path_join(legacy_file)
			legacy_copy_attempted = true
			legacy_copy_error = DirAccess.copy_absolute(wav_path,legacy_path)
			if legacy_copy_error != OK:fail("legacy WAV copy failed bus=%s source=%s target=%s error=%s" % [name,wav_path,legacy_path,error_string(legacy_copy_error)])
		result["buses"][name] = {"base":bus["base"],"end":bus["end"],"pushed_delta":pushed,"discarded_delta":discarded,
			"wav_frames":frames,"capture_frames":captured.size(),"gain_db":bus["gain_db"],"gain_observations":bus["gains"],
			"gain_check_count":bus["gain_checks"],"send":bus["send"],"save_error":saved,"capture_save_error":capture_error,
			"legacy_file":legacy_file,"legacy_copy_error":legacy_copy_error,"legacy_copy_attempted":legacy_copy_attempted,
			"after_save_counter":counters(bus["capture"]),"pcm_source":"AudioEffectCapture","float_format":"stereo_f32le"}
	result["problems"] = problems.duplicate()
	return result

func cleanup() -> Dictionary:
	if cleaned:return {"already_cleaned":true,"removed":0}
	AudioServer.lock()
	active = false
	AudioServer.unlock()
	var removed := 0
	for bus in buses:
		var index := AudioServer.get_bus_index(bus["name"])
		if index < 0:continue
		for effect_index in range(AudioServer.get_bus_effect_count(index)-1,-1,-1):
			var effect := AudioServer.get_bus_effect(index,effect_index)
			if effect == bus["capture"]:
				AudioServer.remove_bus_effect(index,effect_index)
				removed += 1
	buses.clear()
	cleaned = true
	return {"already_cleaned":false,"removed":removed}

func _exit_tree() -> void:
	cleanup()
