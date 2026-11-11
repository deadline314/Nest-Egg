extends "res://tools/ne277_delivery_probe.gd"
## Same formal Player/Enemy hit path, arranged targets. Native records actual master mix.
## No new sound assets, human listening or physical controller claim.
var _sounds: Array[Dictionary] = []
var _shakes: Array[Dictionary] = []
var _hits: Array[Dictionary] = []
var _segment := ""
var _audio := AudioEffectRecord.new()
var _audio_index := -1
var _start_usec := 0


func _run() -> void:
	if not out_dir.is_absolute_path() or (_only != "" and _only not in WEAPONS) or _negative != "" or (_capture and DisplayServer.get_name() == "headless"):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	Settings.use_storage("user://ne277-feedback-settings.cfg")
	Story.auto_skip = true
	var data := NewEnemiesSuite.arena_data()
	data.chapter = &"ch1_kasa"
	await open_arena("res://data/lighting/neutral.tres", 12.0, data)
	# Headless has no visible-screen activation events. Keep these arranged targets in physics.
	var old_culling := Enemy.activation_culling_enabled
	Enemy.activation_culling_enabled = false
	_camera = get_viewport().get_camera_2d()
	_camera.set_physics_process(false)
	_camera.zoom = Vector2.ONE * 2
	_steps_before = Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 1
	Sfx.sound_played.connect(_heard)
	EventBus.screen_shake.connect(_shaken)
	_start_usec = Time.get_ticks_usec()
	if _capture:
		_audio.format = AudioStreamWAV.FORMAT_16_BITS
		_audio_index = AudioServer.get_bus_effect_count(0)
		AudioServer.add_bus_effect(0, _audio)
		_audio.set_recording_active(true)
	for id in WEAPONS:
		if _only != "" and id != _only:
			continue
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % id) as WeaponData
		var set := MeleeData.set_of(weapon)
		var moves: Array = set.combo()
		# First and last combo moves contrast authored impact/reaction; single-move whip stays one.
		var choices := [str(moves[0])]
		if moves.size() > 1:
			choices.append(str(moves[-1]))
		for side in _sides:
			for reduced in [false, true]:
				Settings.set_reduce_flashes(reduced)
				Settings.set_reduce_ui_motion(reduced)
				Settings.set_feel_scale("shake", 0.0 if reduced else 1.0)
				Settings.set_zoom_pulse(not reduced)
				for move in choices:
					await _contact(id, weapon, set, move, side, reduced)
	if _capture:
		_audio.set_recording_active(false)
		var wav := _audio.get_recording()
		_check(wav != null and wav.data.size() > 1024, "native audio recording contains frames")
		if wav != null:
			_check(wav.save_to_wav(out_dir.path_join("master.wav")) == OK, "writes original master mix WAV")
		AudioServer.remove_bus_effect(0, _audio_index)
	Sfx.sound_played.disconnect(_heard)
	EventBus.screen_shake.disconnect(_shaken)
	var result := {"checks": _checks, "failures": _failures, "rows": _rows, "sounds": _sounds,
		"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(),
		"display": DisplayServer.get_name(), "capture": _capture, "output_device": AudioServer.output_device, "mix_rate": AudioServer.get_mix_rate(),
		"scope": "arranged stationary 9999-HP formal grunt; actual natural melee contacts; no human listening, controller or performance claim"}
	var file := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	Settings.set_reduce_flashes(false)
	Settings.set_reduce_ui_motion(false)
	Settings.set_feel_scale("shake", 1.0)
	Settings.set_zoom_pulse(true)
	Engine.max_physics_steps_per_frame = _steps_before
	await clear_enemies()
	Enemy.activation_culling_enabled = old_culling
	await finish()
	await AudioRelease.settle(get_tree())
	print("NE277_FEEDBACK_DONE checks=%d failures=%d rows=%d" % [_checks, _failures.size(), _rows.size()])
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _heard(id: StringName) -> void:
	_sounds.append({"segment": _segment, "id": str(id), "tick": Engine.get_physics_frames(), "seconds": (Time.get_ticks_usec() - _start_usec) / 1000000.0})


func _shaken(px: float, duration: float, _direction: Vector2, _origin: Vector2) -> void:
	_shakes.append({"px": px, "duration": duration, "tick": Engine.get_physics_frames()})


func _contact(id: String, weapon: WeaponData, set: MeleeSet, move: String, side: int, reduced: bool) -> void:
	await clear_enemies()
	player._interrupt_melee()
	player.loadout.reset(weapon)
	player._melee_cooldown_left = 0
	player._melee_combo_left = 0
	player.guard = player.guard_stats.guard_max()
	place_player(12)
	player.facing = side
	player.aim_dir = Vector2(side, 0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2(side, 0)
	_camera.global_position = player.global_position + Vector2(side * 24, -30)
	var def := set.attack(move)
	var distance := maxf(float(def["min_range"]) + 12, float(def["range"]) * 0.65)
	var foe := spawn_enemy("res://data/enemies/grunt.tres", 12)
	foe.data = foe.data.duplicate()
	foe.data.detect_range = 0
	foe.data.attack_range = 0
	foe.data.move_speed = 0
	foe.health.setup(9999, 0)
	foe.position.x = player.position.x + side * distance
	_hits = []
	foe.health.damaged.connect(func(info: DamageInfo) -> void:
		_hits.append({"amount": info.amount, "impact": info.impact, "stagger": info.stagger, "contact": str(info.contact_point), "tick": Engine.get_physics_frames(),
			"attacker": info.attacker != null and info.attacker.get_ref() == player, "freeze_attacker": info.freeze_attacker,
			"enemy_hurt_scale": foe._rig_input.hurt_scale, "flinch": foe._flinch_left, "stun": foe._stun_left}))
	for i in 20:
		await _step()
	print("NE277_TARGET ", JSON.stringify({"player": str(player.global_position), "foe": str(foe.global_position), "direction": str(player.aim_dir), "range": def["range"], "hurtbox": str(foe.hurtbox.global_position)}))
	_segment = "%s/%d/%s/reduced-%s" % [id, side, move, str(reduced)]
	var start := (Time.get_ticks_usec() - _start_usec) / 1000000.0
	var sound_from := _sounds.size()
	var shake_from := _shakes.size()
	var settings := {"reduce_flashes": Settings.get_reduce_flashes(), "reduce_ui_motion": Settings.get_reduce_ui_motion(), "shake": Settings.get_feel_scale("shake"), "zoom_enabled": Settings.zoom_pulse_active(), "flash_scale": Settings.flash_scale()}
	_check(settings["reduce_flashes"] == reduced and settings["shake"] == (0.0 if reduced else 1.0) and settings["zoom_enabled"] == (not reduced), _segment + " reads back actual flash/motion settings")
	_check(player._start_melee_attack(false), _segment + " starts formal attack")
	player._melee_attack = def
	player.melee.swing_direction = player.melee.aim_direction(def)
	var freeze_pair := false
	var first_hit_checked := false
	var frames := []
	var traced := false
	for tick in 240:
		await _step()
		if player.melee.phase == MeleeModule.Phase.ACTIVE and not traced:
			traced = true
			print("NE277_ACTIVE ", JSON.stringify({"player": str(player.global_position), "foe": str(foe.global_position), "direction": str(player.melee.swing_direction), "targets": player.melee.targets(def).size(), "foe_center": str(foe.hurtbox.center()), "enemy_layer": foe.hurtbox.collision_layer}))
		var pair := Fx._frozen.has(player) and Fx._frozen.has(foe)
		frames.append({"tick": Engine.get_physics_frames(), "phase": player.melee.phase, "player_frozen": Fx._frozen.has(player), "enemy_frozen": Fx._frozen.has(foe)})
		if not _hits.is_empty() and not first_hit_checked:
			first_hit_checked = true
			freeze_pair = pair
			if _capture:
				var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
				var path := out_dir.path_join(_segment.replace("/", "-") + ".png")
				_check(image.save_png(path) == OK, _segment + " writes first rendered hit")
		if player.melee.phase == MeleeModule.Phase.NONE:
			break
	_check(player.melee.phase == MeleeModule.Phase.NONE, _segment + " finishes")
	_check(not _hits.is_empty() and foe.health.current < 9999 and _hits[0]["attacker"], _segment + " real damage/attacker")
	_check(first_hit_checked and freeze_pair, _segment + " both actors freeze on first observed hit frame")
	var expected := MeleeMove.hit_layers(def)
	var played: Array[String] = []
	for index in range(sound_from, _sounds.size()):
		played.append(str(_sounds[index]["id"]))
	_check(expected.size() == 2 and expected[0] != expected[1], _segment + " declares separate low/high hit layers")
	for layer in expected:
		var leaves: Array[String] = []
		if Sfx.has_event(layer):
			# sound_played emits resolved leaf voices, not the enclosing sound-event name.
			var events := RigLibrary.load_json("res://data/feel/sound_events.json")
			var definitions: Dictionary = events.get("events", {})
			for sound_layer: Dictionary in (definitions.get(str(layer), {}) as Dictionary).get("layers", []):
				for leaf in sound_layer.get("sounds", []):
					leaves.append(str(leaf))
		else:
			leaves.append(str(layer))
		var heard := false
		for leaf in leaves:
			heard = heard or played.has(leaf)
		_check(not leaves.is_empty() and heard, _segment + " actually plays resolved " + str(layer))
	var shakes := _shakes.slice(shake_from)
	_check(shakes.is_empty() if reduced else not shakes.is_empty(), _segment + " actual world shake signal obeys motion setting")
	_rows.append({"name": _segment, "weapon": id, "move": move, "side": side, "reduced": reduced, "start_seconds": start,
		"end_seconds": (Time.get_ticks_usec() - _start_usec) / 1000000.0, "expected_layers": expected, "played": played,
		"hits": _hits.duplicate(true), "frames": frames, "settings": settings, "world_shakes": shakes, "first_observed_pair_freeze": freeze_pair})
	print("NE277_CONTACT ", JSON.stringify({"name": _segment, "hits": _hits.size(), "pair": freeze_pair, "sounds": played}))
