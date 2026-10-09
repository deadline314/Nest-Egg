extends Node
## Capture the shipped lab playback and representative real-level inputs.
## --out=<absolute directory> --mode=lab|game|phone --slots=P-...,... --screenshots
## Uses an isolated user-data directory; never changes placements or game data.

var out := ""
var mode := "lab"
var only := PackedStringArray()
var screenshots := false
var records: Array[Dictionary] = []
var events: Array[Dictionary] = []
var recording := false
var start_ms := 0
var effect := AudioEffectRecord.new()
var level: Level
var source_revision := ""


func _exit_tree() -> void:
	if is_instance_valid(level) and is_instance_valid(level.player):
		AimInput.set_virtual_gamepad(level.player, false)
	Input.action_release(&"aim_right")


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--slots="):
			only = arg.trim_prefix("--slots=").split(",")
		elif arg.begins_with("--revision="):
			source_revision = arg.trim_prefix("--revision=")
		elif arg == "--screenshots":
			screenshots = true
	if out.is_empty():
		push_error("audition_capture requires --out=<absolute directory>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	# An uncapped headless loop can starve the Dummy audio mixing thread.
	Engine.max_fps = 60
	# Stable comparison: bus gains at 0 dB; shipped per-sound gains and runtime ducking apply.
	for i in AudioServer.bus_count:
		AudioServer.set_bus_volume_db(i, 0.0)
		AudioServer.set_bus_mute(i, false)
	effect.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, effect)
	Sfx.sound_played.connect(_sound_requested)
	Music.track_started.connect(_track_started)
	Story.auto_skip = true
	_run.call_deferred()


func _sound_requested(id: StringName) -> void:
	if recording:
		_voice_event.call_deferred(id, Time.get_ticks_msec() - start_ms)


func _voice_event(id: StringName, elapsed: int) -> void:
	if not recording:
		return
	var voices: Array[Dictionary] = []
	for i in Sfx._players.size():
		var voice: AudioStreamPlayer = Sfx._players[i]
		if voice.playing and Sfx._voice_sound[i] == id and voice.stream != null:
			voices.append({"file": voice.stream.resource_path, "pitch": voice.pitch_scale,
				"volume_db": voice.volume_db, "choking": Sfx._voice_choke[i] != null})
	var event := {"ms": elapsed, "sound": str(id), "source": str(Sfx.source_of(id)), "voices": voices}
	if is_instance_valid(level) and is_instance_valid(level.player):
		event["position"] = [level.player.position.x, level.player.position.y]
		event["on_floor"] = level.player.is_on_floor()
		event["phone_progress"] = level.player._visual.phone_progress()
		event["physics_frame"] = Engine.get_physics_frames()
	events.append(event)


func _track_started(id: StringName) -> void:
	if recording:
		events.append({"ms": Time.get_ticks_msec() - start_ms, "track": str(id),
			"file": Music.track_def(id).get("file", ""), "cue": str(Music.current_cue())})


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _begin() -> void:
	events = []
	start_ms = Time.get_ticks_msec()
	recording = true
	effect.set_recording_active(true)


func _end(name: String, context: Dictionary) -> void:
	recording = false
	effect.set_recording_active(false)
	var wav := effect.get_recording()
	var error := wav.save_to_wav(out.path_join(name + ".wav"))
	records.append({"name": name, "context": context, "events": events.duplicate(true),
		"seconds": wav.get_length(), "wall_seconds": (Time.get_ticks_msec() - start_ms) / 1000.0, "save_error": error})
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"revision": source_revision, "godot": Engine.get_version_info(),
		"mode": mode, "audio_driver": AudioServer.get_driver_name(), "bus_gain_db": 0,
		"subjective_listening": false, "full_playthrough": false, "story_auto_skip": true,
		"records": records}, " "))
	print("CAPTURE ", name, " seconds=", wav.get_length(), " events=", events.size())


func _shot(name: String) -> void:
	if not screenshots:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _stop() -> void:
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)


func _run() -> void:
	if mode == "lab":
		await _lab()
	else:
		await _game()
	_stop()
	await _wait(0.25)
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	effect = null
	await _wait(0.1)
	get_tree().quit()


func _lab() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var lab := SoundLab.new()
	lab.stage_enabled = false
	lab.layout_path = "user://audition-layout.cfg"
	add_child(lab)
	await _wait(0.5)
	var shown := {}
	for slot: Dictionary in lab.catalog.slots:
		var id := str(slot["id"])
		if not only.is_empty() and not only.has(id):
			continue
		_stop()
		lab.slots_tab.select_slot(id)
		await _wait(0.06)
		var duration := 0.5
		if slot["kind"] == "music":
			duration = 12.4 if str(slot["target"]).ends_with("_sting") else 4.0
		else:
			for stream: AudioStream in Sfx.bank().variants(StringName(str(slot["target"]))):
				duration = maxf(duration, minf(4.0, stream.get_length() + 0.2))
		_begin()
		lab.slots_tab._play_in_game()
		if not shown.has(slot["domain"]):
			await _wait(0.1)
			await _shot("lab_" + str(slot["domain"]))
			shown[slot["domain"]] = true
		await _wait(duration)
		_end(id, {"slot": slot, "source_label": lab.slots_tab._source.text,
			"method": "SoundLabSlotsTab: 遊戲內實際聲音"})
	lab.queue_free()
	await _wait(0.1)


func _open_level(path: String) -> void:
	_stop()
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load(path) as LevelData)
	add_child(level)
	await _wait(1.0)
	level.player.health.setup(999999, 0.0)
	await _wait(0.5)


func _close_level() -> void:
	if is_instance_valid(level) and is_instance_valid(level.player):
		AimInput.set_virtual_gamepad(level.player, false)
	for action in [&"shoot", &"move_right", &"jump", &"interact", &"aim_right"]:
		Input.action_release(action)
	GameplayLock.set_base_paused(false)
	level.queue_free()
	await _wait(0.2)
	_stop()


func _game() -> void:
	add_child(LightKit.create_environment())
	if mode != "phone":
		_begin()
		var menu := MainMenu.new()
		add_child(menu)
		await _wait(4.0)
		await _shot("main_menu")
		_end("main_menu", {"method": "real MainMenu; no start-to-finish playthrough"})
		menu.queue_free()
		await _wait(0.1)
	var paths := ["res://data/levels/ch1_booth_alley.tres"] if mode == "phone" else [
		"res://data/levels/ch1_rooftop.tres", "res://data/levels/ch1_booth_alley.tres",
		"res://data/levels/ch1_warehouse.tres", "res://data/levels/level_02.tres"]
	for path: String in paths:
		await _open_level(path)
		var name := str(level.data.id)
		_begin()
		await _wait(3.0)
		await _shot(name + "_entry")
		_end(name + "_entry", {"level": path, "cue": str(Music.current_cue()), "state": str(Music.current_state()),
			"method": "direct real Level entry; auto-skipped story; high player health"})
		Music.stop(0.0)
		Ambience.stop_all(0.0)
		if name in ["ch1_rooftop", "level_02"]:
			_begin()
			Input.action_press(&"move_right")
			await _wait(1.5)
			Input.action_press(&"jump")
			await get_tree().physics_frame
			await get_tree().physics_frame
			await _wait(0.2)
			Input.action_release(&"jump")
			await _wait(1.4)
			Input.action_release(&"move_right")
			await _wait(0.5)
			await _shot(name + "_movement")
			_end(name + "_movement", {"level": path, "method": "real movement/jump input; BGM muted to isolate foley"})
			for weapon_id in ["pistol", "rifle", "smg", "spread", "laser", "launcher", "railgun"]:
				var weapon := load("res://data/weapons/%s.tres" % weapon_id) as WeaponData
				for rate in [1.0, 2.0]:
					level.player.loadout.reset(weapon)
					level.player._fire_cooldown_left = 0.0
					level.player.cyber._ability = (load("res://data/abilities/overclock.tres") as CyberAbilityData).duplicate()
					level.player.cyber._ability.magnitude = rate - 1.0
					level.player.cyber._active_left = 10.0 if rate > 1.0 else 0.0
					AimInput.set_virtual_gamepad(level.player, true)
					Input.action_press(&"aim_right")
					_begin()
					Input.action_press(&"shoot")
					await get_tree().physics_frame
					await get_tree().physics_frame
					await _wait(maxf(0.7, weapon.fire_interval / rate * 2.3))
					Input.action_release(&"shoot")
					await _wait(0.8)
					Input.action_release(&"aim_right")
					AimInput.set_virtual_gamepad(level.player, false)
					_end(name + "_" + weapon_id + "_x" + str(int(rate)), {"level": path, "weapon": weapon_id,
						"rate": rate, "method": "real held-fire input; selected weapon; injected overclock magnitude for 2x; BGM muted"})
		if name == "ch1_booth_alley":
			var booths := level.find_children("*", "Checkpoint", true, false)
			if not booths.is_empty():
				var booth := booths[0] as Checkpoint
				level.player.position = booth.position + Vector2(-20, -8)
				await _wait(0.5)
				_begin()
				await get_tree().process_frame
				Input.action_press(&"interact")
				await get_tree().process_frame
				await get_tree().process_frame
				Input.action_release(&"interact")
				await _wait(1.7)
				await _shot("ch1_phone")
				_end("ch1_phone", {"level": path, "activated": booth.activated,
					"can_dial": booth.can_dial(), "on_floor": level.player.is_on_floor(), "player_state": level.player.state,
					"method": "placed near existing booth then real interact input; BGM muted"})
				if not booth.activated:
					_begin()
					var started := booth.start_call(level.player)
					await _wait(1.8)
					_end("ch1_phone_direct", {"level": path, "started": started, "activated": booth.activated,
						"method": "explicit existing Checkpoint.start_call handler; input attempt did not activate"})
		await _close_level()
