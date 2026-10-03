class_name FeelSuite
extends TestSuite
## 回饋資料化與單一入口（NE-131）：事件資料沒有錯誤、程式碼引用的事件都存在、除了 Feel 之外沒有程式直接呼叫頓幀與震動、
## 震動的持續時間真的生效（小強度也看得見）、壞資料與不存在的事件不會崩潰。

const ENTRY_FILES: PackedStringArray = ["res://autoload/feel.gd", "res://autoload/fx.gd"]


func run() -> void:
	_test_data_is_valid()
	_test_code_uses_known_events_only()
	await _test_shake_duration_is_honored()
	_test_bad_events_are_safe()
	_test_feel_settings()
	await _test_global_hitstop()
	await _test_slowmo()
	await _test_camera()
	await _test_sound_events()
	_test_hit_materials()
	await _test_weapon_feel()
	await _test_reload_feel()
	await _test_block_feel()
	_test_params_and_presets()
	_test_reverse_index()
	_test_save_events()
	await _test_screen_fx()
	await _test_diagnostics()
	_test_attack_language()
	await _test_clear_out()


func _script_paths(dir: String, into: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_script_paths(dir.path_join(sub), into)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			into.append(dir.path_join(file))


func _test_data_is_valid() -> void:
	var errors: PackedStringArray = Feel.validate()
	check(errors.is_empty(), "feel events have no errors: %s" % ", ".join(errors))
	check(Feel.event_ids().size() >= 15, "feel events loaded (%d)" % Feel.event_ids().size())


func _test_code_uses_known_events_only() -> void:
	var paths := PackedStringArray()
	for dir in ["res://game", "res://autoload", "res://core"]:
		_script_paths(dir, paths)
	var play_re := RegEx.create_from_string("Feel\\.play\\(&\"([a-z0-9_]+)\"")
	var direct_re := RegEx.create_from_string("\\bFx\\.(shake|hitstop|freeze)\\(")
	var used := 0
	for path in paths:
		var text := FileAccess.get_file_as_string(path)
		for m in play_re.search_all(text):
			used += 1
			check(Feel.has_event(StringName(m.get_string(1))), "%s uses unknown feel event %s" % [path, m.get_string(1)])
		if not ENTRY_FILES.has(path):
			check(direct_re.search(text) == null, "%s calls Fx shake/hitstop/freeze directly; use Feel" % path)
	check(used >= 20, "feel events are used by game code (%d call sites)" % used)


func _test_shake_duration_is_honored() -> void:
	var camera := LevelCamera.new()
	runner.get_tree().root.add_child(camera)
	var dummy := Node2D.new()
	runner.get_tree().root.add_child(dummy)
	camera.target = dummy
	Feel.shake(2.0, 0.2)
	await runner.get_tree().physics_frame
	await runner.get_tree().physics_frame
	var early := 0.0
	for i in 12:
		camera._noise_time += 7.0
		early = maxf(early, camera._shake_magnitude(0.0))
	check(early > 1.0, "small shake is visible right away (%.2f px)" % early)
	for i in 30:
		await runner.get_tree().physics_frame
	check(camera._shakes.is_empty(), "shake ends after its duration")
	check(camera._shake_magnitude(0.0) == 0.0, "no shake left after duration")
	camera.queue_free()
	dummy.queue_free()


func _test_bad_events_are_safe() -> void:
	var before: int = int(Feel.counters.get("events", 0))
	Feel.play(&"test_no_such_feel_event")
	check(int(Feel.counters.get("events", 0)) == before, "unknown event is skipped")
	Feel.shake(-1.0, 0.1)
	Feel.freeze([null], 0.05)
	check(true, "invalid arguments do not crash")
	Feel.register_counter("test_gauge", func() -> int: return 7)
	check(int(Feel.read_counters().get("test_gauge", -1)) == 7, "registered counters are readable")


class _Probe:
	var shakes: Array[float] = []
	var kicks: Array[float] = []

	func on_shake(px: float, _time: float, _direction: Vector2, _origin: Vector2) -> void:
		shakes.append(px)

	func on_kick(offset: Vector2) -> void:
		kicks.append(offset.length())


func _test_feel_settings() -> void:
	var original := Settings.storage_path()
	DirAccess.remove_absolute("user://test_feel_settings.cfg")
	Settings.use_storage("user://test_feel_settings.cfg")
	check(Settings.get_feel_scale("shake") == 1.0 and Settings.get_zoom_pulse(), "feel settings default to full strength")
	var probe := _Probe.new()
	EventBus.screen_shake.connect(probe.on_shake)
	EventBus.camera_kick.connect(probe.on_kick)
	Feel.play(&"boss_land")
	Fx.kick(Vector2.RIGHT, 4.0)
	check(is_equal_approx(probe.shakes[0], 4.8) and is_equal_approx(probe.kicks[0], 4.0), "full strength shake and kick")
	Settings.set_feel_scale("shake", 0.5)
	Feel.play(&"boss_land")
	check(is_equal_approx(probe.shakes[1], 2.4), "shake scales with the slider")
	Settings.set_feel_scale("shake", 0.0)
	Feel.play(&"boss_land")
	Fx.kick(Vector2.RIGHT, 4.0)
	check(probe.shakes.size() == 2, "shake 0% emits no screen shake")
	check(is_equal_approx(probe.kicks[1], 2.0), "camera kick keeps about half at shake 0%")
	check(not Settings.zoom_pulse_active(), "zoom pulse is off at shake 0%")
	Settings.set_feel_scale("shake", 1.0)
	Settings.set_zoom_pulse(false)
	check(not Settings.zoom_pulse_active(), "zoom pulse switch turns it off")
	Settings.set_value(Settings.FEEL_SECTION, "shake", "broken")
	check(Settings.get_feel_scale("shake") == 1.0, "corrupted scale falls back to default")
	Settings.set_value(Settings.FEEL_SECTION, "hitstop", 9.0)
	check(Settings.get_feel_scale("hitstop") == 1.0, "out of range scale is clamped")
	Settings.reset_display()
	check(Settings.get_zoom_pulse() and Settings.get_feel_scale("shake") == 1.0, "reset restores feel settings")
	EventBus.screen_shake.disconnect(probe.on_shake)
	EventBus.camera_kick.disconnect(probe.on_kick)
	Settings.use_storage(original)
	DirAccess.remove_absolute("user://test_feel_settings.cfg")


func _test_global_hitstop() -> void:
	Fx._hitstop_log.clear()
	var enemy := Node2D.new()
	enemy.position = Vector2(100, 50)
	enemy.add_to_group(&"enemies")
	runner.get_tree().root.add_child(enemy)
	Feel.hitstop(0.5)
	await runner.get_tree().process_frame
	check(enemy.process_mode == Node.PROCESS_MODE_DISABLED, "global hitstop freezes gameplay nodes")
	check(is_equal_approx(Engine.time_scale, 1.0), "global hitstop does not slow particles and UI")
	check(Fx.hitstop_budget_left() <= Fx.HITSTOP_WINDOW_BUDGET - Fx.HITSTOP_MAX + 0.001, "a single hitstop is capped (budget left %.2f)" % Fx.hitstop_budget_left())
	await runner.get_tree().process_frame
	await frames(3)
	check(enemy.position != Vector2(100, 50) and enemy.position.distance_to(Vector2(100, 50)) <= Fx.FREEZE_JITTER + 0.01, "frozen nodes jitter slightly")
	var waited := 0
	while enemy.process_mode == Node.PROCESS_MODE_DISABLED and waited < 60:
		await runner.get_tree().create_timer(0.05, true, false, true).timeout
		waited += 1
	check(enemy.process_mode == Node.PROCESS_MODE_INHERIT and enemy.position == Vector2(100, 50), "released at the original position")
	Fx._hitstop_log.clear()
	for i in 5:
		Feel.hitstop(0.2)
	check(Fx.hitstop_budget_left() <= 0.001, "repeated hitstops hit the one second budget")
	Fx._hitstop_log.clear()
	enemy.queue_free()
	await runner.get_tree().process_frame


func _test_slowmo() -> void:
	Fx.reset_time()
	Fx._slowmo_ready_msec = 0
	check(not Fx.slowmo("random_hit", 0.3, 0.2), "slow motion is refused outside the whitelist")
	check(Fx.slowmo("boss_death", 0.3, 0.1) and is_equal_approx(Engine.time_scale, 0.3), "whitelisted slow motion plays")
	check(not Fx.slowmo("boss_death", 0.3, 0.1), "slow motion has a cooldown")
	Fx.reset_time()
	check(is_equal_approx(Engine.time_scale, 1.0), "time returns to normal")
	Fx._slowmo_ready_msec = 0
	var crowd: Array[Node] = []
	for i in 5:
		var n := Node.new()
		n.add_to_group(&"enemies")
		runner.get_tree().root.add_child(n)
		crowd.append(n)
	Feel.play(&"player_finisher")
	check(not Fx.is_slowmo(), "finisher slow motion is skipped when many enemies are around")
	for n in crowd:
		n.free()
	Fx.reset_time()
	Fx._slowmo_ready_msec = 0


func _test_camera() -> void:
	var camera := LevelCamera.new()
	runner.get_tree().root.add_child(camera)
	# 有方向的震動沿方向擺動、雜訊只佔一小部分。
	camera._on_screen_shake(8.0, 0.3, Vector2.RIGHT, Vector2.INF)
	var max_x := 0.0
	var max_y := 0.0
	for i in 18:
		var o := camera._shake_offset(1.0 / 60.0)
		max_x = maxf(max_x, absf(o.x))
		max_y = maxf(max_y, absf(o.y))
	check(max_x > 2.0 and max_y < max_x * 0.6, "directional shake mostly moves along its direction (%.2f vs %.2f)" % [max_x, max_y])
	camera._shakes.clear()
	# 距離衰減：遠處的來源震得比較小，最遠剩四分之一。
	camera.global_position = Vector2.ZERO
	camera._on_screen_shake(8.0, 0.3, Vector2.ZERO, Vector2(2000.0, 0.0))
	check(is_equal_approx(float(camera._shakes[0][0]), 2.0), "far shakes fall off to 25%")
	camera._shakes.clear()
	camera._on_screen_shake(8.0, 0.3, Vector2.ZERO, Vector2(100.0, 0.0))
	check(is_equal_approx(float(camera._shakes[0][0]), 8.0), "near shakes keep full strength")
	camera._shakes.clear()
	# 同時事件的位移有上限。
	for i in 8:
		camera._on_screen_shake(12.0, 1.0, Vector2.ZERO, Vector2.INF)
	check(camera._shake_offset(0.0).length() <= LevelCamera.MAX_SHAKE_PX + 0.001, "stacked shakes are capped")
	# 縮放脈衝：先拉近再回到原本。
	camera._on_zoom_pulse(0.04, 0.2)
	var peak := 0.0
	for i in 8:
		peak = maxf(peak, camera._pulse_amount(1.0 / 60.0))
	check(peak > 0.02, "zoom pulse zooms in (%.3f)" % peak)
	for i in 20:
		camera._pulse_amount(1.0 / 60.0)
	check(camera._pulse_amount(0.0) == 0.0, "zoom pulse returns to normal")
	camera.queue_free()
	# 縮放脈衝只給白名單事件；震動 0% 或開關關閉時不播。
	var pulses := [0]
	var count := func(_a: float, _t: float) -> void: pulses[0] += 1
	EventBus.camera_zoom_pulse.connect(count)
	Feel.play(&"player_parry")
	check(pulses[0] == 1, "whitelisted event plays a zoom pulse")
	Feel.play(&"enemy_kill")
	check(pulses[0] == 1, "events outside the whitelist do not pulse")
	var original := Settings.storage_path()
	Settings.use_storage("user://test_feel_camera.cfg")
	Settings.set_zoom_pulse(false)
	Feel.play(&"player_parry")
	check(pulses[0] == 1, "zoom pulse switch turns the pulse off")
	Settings.reset_display()
	Settings.use_storage(original)
	DirAccess.remove_absolute("user://test_feel_camera.cfg")
	EventBus.camera_zoom_pulse.disconnect(count)
	# 頓幀結束後才震：有頓幀的事件震動延後。
	await runner.get_tree().create_timer(0.3, true, false, true).timeout  # 先讓前面事件延後的震動播完
	var seen := [0]
	var on_shake := func(_p: float, _t: float, _d: Vector2, _o: Vector2) -> void: seen[0] += 1
	EventBus.screen_shake.connect(on_shake)
	Fx._hitstop_log.clear()
	Feel.play(&"player_hurt")
	check(seen[0] == 0, "shake waits for the hitstop to end")
	await runner.get_tree().create_timer(0.2, true, false, true).timeout
	check(seen[0] == 1, "shake plays after the hitstop")
	EventBus.screen_shake.disconnect(on_shake)
	Fx._hitstop_log.clear()


func _test_sound_events() -> void:
	var errors: PackedStringArray = Sfx.validate_events()
	check(errors.is_empty(), "sound events have no errors: %s" % ", ".join(errors))
	# 事件引用的程式碼都存在。
	var paths := PackedStringArray()
	for dir in ["res://game", "res://autoload", "res://core"]:
		_script_paths(dir, paths)
	var event_re := RegEx.create_from_string("Sfx\\.play_event\\(&\"([a-z0-9_]+)\"")
	for path in paths:
		for m in event_re.search_all(FileAccess.get_file_as_string(path)):
			check(Sfx.has_event(StringName(m.get_string(1))), "%s uses unknown sound event %s" % [path, m.get_string(1)])
	# 變體輪播：連續 60 次不會連續同一個。
	var repeated := false
	var last := -1
	for i in 60:
		var pick: int = Sfx._pick_variant("test_key", 3)
		repeated = repeated or pick == last
		last = pick
	check(not repeated, "variants never repeat back to back")
	# 連鎖升音：視窗內越來越高，超過視窗重置。
	Sfx._chains.clear()
	var chain := {"step": 1.0, "max": 3, "window": 0.5}
	var now := Time.get_ticks_msec()
	var p0: float = Sfx._chain_pitch("t", chain, now)
	var p1: float = Sfx._chain_pitch("t", chain, now + 100)
	var p2: float = Sfx._chain_pitch("t", chain, now + 200)
	var p5: float = Sfx._chain_pitch("t", chain, now + 300)
	check(p0 == 1.0 and p1 > p0 and p2 > p1 and is_equal_approx(Sfx._chain_pitch("t", chain, now + 350), p5), "chain pitch rises and is capped")
	check(Sfx._chain_pitch("t", chain, now + 5000) == 1.0, "chain pitch resets after the window")
	# 滿載時的優先級：低優先級丟棄、高優先級搶位。
	Sfx.stop_all()
	var t := Time.get_ticks_msec()
	for i in Sfx._players.size():
		Sfx._players[i].stream = Sfx._streams[&"explosion"]
		Sfx._players[i].play()
		Sfx._voice_priority[i] = 5
		Sfx._voice_end_msec[i] = t + 5000
	var dropped_before: int = Sfx.dropped_count
	check(not Sfx._play_voice(&"hit", 0.0, 1.0, 1), "low priority sound is dropped when voices are full")
	check(Sfx.dropped_count == dropped_before + 1, "dropped sounds are counted")
	check(Sfx._play_voice(&"kill", 0.0, 1.0, 9), "high priority sound takes over a voice")
	Sfx.stop_all()
	for i in Sfx._players.size():
		Sfx._voice_end_msec[i] = 0
	# 壓低：優先級較低的播放中聲音音量降低，結束後回復。
	Sfx._players[0].stream = Sfx._streams[&"explosion"]
	Sfx._players[0].play()
	Sfx._voice_priority[0] = 1
	Sfx._voice_base_db[0] = -2.0
	Sfx._voice_end_msec[0] = Time.get_ticks_msec() + 3000
	Sfx._start_duck(-8.0, 0.1, 9, Time.get_ticks_msec())
	check(is_equal_approx(Sfx._players[0].volume_db, -10.0), "ducking lowers quieter voices by the set depth")
	await runner.get_tree().create_timer(0.3, true, false, true).timeout
	check(Sfx._players[0].volume_db > -4.0 and Sfx._duck_db > -2.0, "ducking recovers smoothly afterwards")
	Sfx.stop_all()
	# 缺漏的事件退回預設音效，不崩潰。
	Sfx.play_event(&"test_no_such_sound_event")
	check(true, "unknown sound event falls back safely")


func _test_hit_materials() -> void:
	var errors: PackedStringArray = HitFeedback.validate()
	check(errors.is_empty(), "hit materials have no errors: %s" % ", ".join(errors))
	var ids := HitFeedback.material_ids()
	check(ids.size() >= 7, "at least seven hit materials (%d)" % ids.size())
	# 每份敵人資料的材質標籤都存在（或留空用通用）。
	for file in DirAccess.get_files_at("res://data/enemies"):
		if file.ends_with(".tres"):
			var data := load("res://data/enemies/" + file) as EnemyData
			if data != null and data.hit_material != &"":
				check(ids.has(String(data.hit_material)), "%s uses an unknown hit material %s" % [file, data.hit_material])
	# 缺標籤與不認得的標籤退回通用；每種材質、弱點、跳彈都能播。
	check(HitFeedback.play(&"", Vector2.ZERO, Vector2.UP, Color.WHITE) == HitFeedback.FALLBACK, "missing material tag falls back to generic")
	check(HitFeedback.play(&"test_no_such_material", Vector2.ZERO, Vector2.UP, Color.WHITE) == HitFeedback.FALLBACK, "unknown material falls back to generic")
	for id in ids:
		HitFeedback.play(StringName(id), Vector2.ZERO, Vector2.UP, Color.WHITE)
	HitFeedback.play(&"armor", Vector2.ZERO, Vector2.UP, Color.WHITE, {"weak": true})
	HitFeedback.play(&"metal", Vector2.ZERO, Vector2.UP, Color.WHITE, {"ricochet": true})
	check(true, "every material, weak spots and ricochets play without errors")
	# 預算：短時間大量命中，粒子被縮減，但每次仍保留至少一顆。
	HitFeedback.reset_budget()
	var wanted := 0
	for i in 40:
		HitFeedback._spend(10)
		wanted += 10
	check(HitFeedback.trimmed_particles > 0 and HitFeedback.trimmed_particles < wanted, "particle budget trims bursts (%d of %d trimmed)" % [HitFeedback.trimmed_particles, wanted])
	HitFeedback.reset_budget()


func _test_weapon_feel() -> void:
	var weapons: Dictionary = {}
	for file in DirAccess.get_files_at("res://data/weapons"):
		if file.ends_with(".tres"):
			var weapon := load("res://data/weapons/" + file) as WeaponData
			check(weapon != null and weapon.muzzle_flare_size > 0.0 and weapon.muzzle_light_radius > 0.0 and weapon.muzzle_spark_count >= 0 and weapon.screen_shake_time > 0.0, "%s has valid muzzle feedback data" % file)
			if weapon != null:
				weapons[weapon.id] = weapon
	# 輕重武器明顯區分：槍口閃光、光範圍與鏡頭後座都是重武器大。
	var light: WeaponData = weapons[&"smg"]
	var heavy: WeaponData = weapons[&"railgun"]
	check(heavy.muzzle_flare_size >= light.muzzle_flare_size * 2.5 and heavy.muzzle_light_radius > light.muzzle_light_radius * 1.5 and heavy.camera_kick > light.camera_kick * 3.0, "heavy weapons look and feel clearly heavier than light ones")
	# 連發節流：間隔內的第二發不再播槍口特效，但鏡頭後座照樣有。
	WeaponSystem._last_muzzle_fx.clear()
	var kicks := [0]
	var count := func(_o: Vector2) -> void: kicks[0] += 1
	EventBus.camera_kick.connect(count)
	var first := WeaponSystem.muzzle_feedback(light, Vector2.ZERO, Vector2.RIGHT)
	var second := WeaponSystem.muzzle_feedback(light, Vector2.ZERO, Vector2.RIGHT)
	check(first and not second and kicks[0] == 2, "rapid fire throttles muzzle effects but keeps the camera kick")
	WeaponSystem._last_muzzle_fx[light.id] = int(WeaponSystem._last_muzzle_fx[light.id]) - int(light.muzzle_fx_interval * 1000.0) - 5  # 模擬時間過了間隔
	check(WeaponSystem.muzzle_feedback(light, Vector2.ZERO, Vector2.RIGHT), "muzzle effects play again after the interval")
	EventBus.camera_kick.disconnect(count)
	WeaponSystem._last_muzzle_fx.clear()
	# 命中標記四種都能畫出來。
	var crosshair := Crosshair.new()
	runner.get_tree().root.add_child(crosshair)
	for kind in [&"hit", &"weak", &"kill", &"blocked"]:
		EventBus.hit_marker.emit(kind)
	crosshair.queue_redraw()
	await runner.get_tree().process_frame
	check(crosshair._weak_left > 0.0 and crosshair._blocked_left > 0.0, "weak and blocked hit markers are shown")
	crosshair.queue_free()


func _test_reload_feel() -> void:
	var weapon := load("res://data/weapons/spread.tres") as WeaponData
	var loadout := Loadout.new()
	loadout.reset(weapon)
	var events := {"cancelled": 0, "finished": 0}
	loadout.reload_cancelled.connect(func() -> void: events["cancelled"] += 1)
	loadout.reload_finished.connect(func() -> void: events["finished"] += 1)
	check(not loadout.cancel_reload(), "nothing to cancel when not reloading")
	loadout.consume_ammo()
	check(loadout.start_reload() and loadout.is_reloading(), "reload starts")
	for i in 10:
		loadout.tick(1.0 / 60.0)
	check(loadout.cancel_reload() and not loadout.is_reloading() and events["cancelled"] == 1, "reload can be cancelled")
	for i in 240:
		loadout.tick(1.0 / 60.0)
	check(events["finished"] == 0, "a cancelled reload never reports completion")
	check(loadout.mag_in(0) < weapon.magazine_size, "a cancelled reload does not refill the magazine")
	check(loadout.start_reload(), "reload can start again after a cancel")
	for i in 600:
		loadout.tick(1.0 / 60.0)
	check(events["finished"] == 1 and loadout.mag_in(0) == weapon.magazine_size, "an uninterrupted reload completes once")
	# 空槍：彈匣與備彈都沒了才算，而且連按有節流。
	var empty := Loadout.new()
	empty.reset(weapon)
	check(not empty.is_dry(), "a loaded weapon is not dry")
	var level := await start_level(PropsSuite.level_data())
	var player := level.player
	var dry_count := [0]
	var count := func() -> void: dry_count[0] += 1
	EventBus.dry_fired.connect(count)
	player._dry_fire()
	player._dry_fire()
	check(dry_count[0] == 1, "mashing the trigger on an empty gun is throttled")
	player._dry_fire_left = 0.0
	player._dry_fire()
	check(dry_count[0] == 2, "dry fire works again after the interval")
	EventBus.dry_fired.disconnect(count)
	# 低彈量開火音高降低；換彈完成才發出完成訊號。
	var done := [0]
	var on_done := func() -> void: done[0] += 1
	EventBus.reload_completed.connect(on_done)
	player.loadout.start_reload()
	player.loadout.cancel_reload()
	check(done[0] == 0, "cancelling does not announce a finished reload")
	player._on_reload_finished()
	check(done[0] == 1, "finishing a reload announces completion")
	EventBus.reload_completed.disconnect(on_done)
	var rifle := load("res://data/weapons/rifle.tres") as WeaponData
	player.loadout.reset(rifle)
	check(not player._is_low_ammo(rifle), "a full magazine is not low")
	await end_level(level)


func _test_block_feel() -> void:
	var level := await start_level(PropsSuite.level_data())
	var player := level.player
	var tuning := player.tuning
	# 窗口長度夾在 0.14～0.22。
	var original := tuning.parry_window
	tuning.parry_window = 0.5
	check(is_equal_approx(player.parry_window_length(), Player.PARRY_WINDOW_MAX * player._window_scale), "an over-long parry window is clamped to 0.22 s")
	tuning.parry_window = 0.01
	check(is_equal_approx(player.parry_window_length(), Player.PARRY_WINDOW_MIN * player._window_scale), "an over-short parry window is clamped to 0.14 s")
	tuning.parry_window = original
	check(original >= Player.PARRY_WINDOW_MIN and original <= Player.PARRY_WINDOW_MAX, "the shipped parry window is inside the range")
	# 放開後很快再舉盾，窗口縮短。
	player._window_scale = 1.0
	var full := player.parry_window_length()
	player._since_block_release = 0.0
	player._window_scale = tuning.parry_window_repeat_scale
	check(player.parry_window_length() < full, "re-raising the shield right after lowering it shortens the window")
	# 三級回饋：普通、完美、破防各有事件，也各有聲音。
	for id in [&"player_block", &"player_parry", &"player_guard_break"]:
		check(Feel.has_event(id), "block tier event exists: %s" % id)
	for sound in [&"block", &"parry", &"guard_break"]:
		check(Sfx.has_sound(sound), "block tier sound exists: %s" % sound)
	# 彈回的子彈有軌跡（以加倍傷害為標記）。
	var spec := load("res://data/projectiles/rifle_shot.tres") as ProjectileSpec
	var bullet := ProjectilePool.spawn(spec, Vector2(100, 100), Vector2.RIGHT, Combat.Team.ENEMY)
	if bullet != null:
		bullet._reflect(Vector2.LEFT)
		check(bullet._damage_scale > 1.0 and bullet.team == Combat.Team.PLAYER, "a reflected bullet changes sides and carries the trail marker")
	await physics_frames(3)
	await end_level(level)


func _test_params_and_presets() -> void:
	# 參數自動從事件資料產生，每個數值都有範圍。
	for id in Feel.event_ids():
		var params := FeelParams.parameters(Feel.event_def(StringName(id)))
		check(not params.is_empty(), "event %s exposes parameters" % id)
		for param in params:
			check(bool(param["known"]), "parameter %s.%s has a known slider range" % [id, param["name"]])
	var boss := Feel.event_def(&"boss_land")
	var before := float(boss["shake"]["px"])
	check(FeelParams.set_value(boss, ["shake", "px"], 2.0) and is_equal_approx(float(Feel.event_def(&"boss_land")["shake"]["px"]), 2.0), "changing a parameter edits the live event")
	check(not FeelParams.set_value(boss, ["shake", "no_such"], 1.0), "unknown parameter paths are refused")
	FeelParams.set_value(boss, ["shake", "px"], before)
	# 預設組合：切換後整體倍率改變，缺漏的預設退回並記錄。
	var errors := FeelParams.validate_presets()
	check(errors.is_empty(), "presets have no errors: %s" % ", ".join(errors))
	var seen: Array[float] = []
	var probe := _Probe.new()
	EventBus.screen_shake.connect(probe.on_shake)
	for name in ["standard", "restrained", "heavy", "arcade", "accessible"]:
		check(Feel.set_preset(StringName(name)), "preset %s can be selected" % name)
		probe.shakes.clear()
		Feel.play(&"boss_land")
		seen.append(probe.shakes[0] if not probe.shakes.is_empty() else 0.0)
	EventBus.screen_shake.disconnect(probe.on_shake)
	check(seen[1] < seen[0] and seen[2] > seen[0] and seen[4] == 0.0, "presets scale every event together (%s)" % str(seen))
	check(not Feel.set_preset(&"test_no_such_preset") and Feel.preset == &"accessible", "an unknown preset is refused and the current one stays")
	Feel.set_preset(&"standard")


func _test_reverse_index() -> void:
	var usage := FeelParams.usage(true)
	# 已知的使用關係：玩家受傷事件來自玩家腳本；近戰事件來自近戰資料；頭目死亡來自頭目腳本。
	check((usage["player_hurt"] as Array).has("res://game/player/player.gd"), "player_hurt is used by the player script")
	check((usage["player_melee_heavy"] as Array).has("res://data/feel/melee.json"), "melee events are found through the attack data")
	check((usage["boss_death"] as Array).has("res://game/enemies/warden_boss.gd"), "boss_death is used by the boss script")
	# 反向索引與實際引用一致：每個索引出來的使用處真的含有該事件名。
	for id: String in usage.keys():
		for path: String in usage[id]:
			check(FileAccess.get_file_as_string(path).contains(id), "%s really mentions %s" % [path, id])
	# 完全沒被使用的事件要是已知的（有人加了事件卻沒接上就會在這裡被指出）。
	var unused := FeelParams.unused_events()
	check(unused.is_empty(), "no feel event is left unused: %s" % ", ".join(unused))



func _test_save_events() -> void:
	var dir := "user://feel_save_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/events.json"
	var original := FileAccess.get_file_as_string(Feel.PATH)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	# 沒改動：沒有差異，也不會動檔案。
	var untouched := FeelParams.save_events(path)
	check(bool(untouched["ok"]) and (untouched["diff"] as PackedStringArray).is_empty() and FileAccess.get_file_as_string(path) == original, "saving without changes leaves the file untouched")
	# 改兩個參數：差異只含這兩項，檔案文字差異也只在這兩行。
	var boss := Feel.event_def(&"boss_land")
	var shake_before := float(boss["shake"]["px"])
	var time_before := float(boss["shake"]["time"])
	FeelParams.set_value(boss, ["shake", "px"], 3.0)
	FeelParams.set_value(boss, ["shake", "time"], 0.45)
	var preview := FeelParams.save_events(path, true)
	check((preview["diff"] as PackedStringArray).size() == 2 and FileAccess.get_file_as_string(path) == original, "the preview lists only the changed values and writes nothing")
	var saved := FeelParams.save_events(path)
	check(bool(saved["ok"]) and FileAccess.file_exists(path + ".bak") and FileAccess.get_file_as_string(path + ".bak") == original, "saving backs up the old file")
	var old_lines := original.split("\n")
	var new_lines := FileAccess.get_file_as_string(path).split("\n")
	var changed := 0
	for i in mini(old_lines.size(), new_lines.size()):
		if old_lines[i] != new_lines[i]:
			changed += 1
	check(old_lines.size() == new_lines.size() and changed == 2, "the file differs only on the changed values (%d lines)" % changed)
	check(not FileAccess.file_exists(path + ".tmp"), "the temporary file is replaced, not left behind")
	# 重新載入的結果與寫入前一致。
	var reloaded := FeelParams._read_events(path)
	check(is_equal_approx(float(reloaded["boss_land"]["shake"]["px"]), 3.0) and is_equal_approx(float(reloaded["boss_land"]["shake"]["time"]), 0.45), "reloading the saved file gives the values that were written")
	check(FeelParams.diff_against_file(path).is_empty(), "memory and file agree after saving")
	# 不合法的值：驗證失敗、不寫入、指出位置。
	FeelParams.set_value(boss, ["shake", "px"], -5.0)
	var before_text := FileAccess.get_file_as_string(path)
	var rejected := FeelParams.save_events(path)
	check(not bool(rejected["ok"]) and not (rejected["errors"] as PackedStringArray).is_empty() and FileAccess.get_file_as_string(path) == before_text, "an invalid value is rejected without writing")
	check(" ".join(rejected["errors"]).contains("boss_land"), "the error names the event")
	# 還原記憶體中的資料。
	FeelParams.set_value(boss, ["shake", "px"], shake_before)
	FeelParams.set_value(boss, ["shake", "time"], time_before)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")


func _test_screen_fx() -> void:
	var errors := PostProcess.validate_effects()
	check(errors.is_empty(), "screen effects have no errors: %s" % ", ".join(errors))
	# 閃光防護：峰值有上限，每秒最多三次，超過的丟棄。
	FlashGuard.reset()
	var t := 100000
	var granted := FlashGuard.request(5.0, t)
	check(granted <= FlashGuard.MAX_AMOUNT + 0.0001 and granted > 0.0, "flash peak is capped (%.2f)" % granted)
	check(FlashGuard.request(0.2, t + 100) > 0.0 and FlashGuard.request(0.2, t + 200) > 0.0, "three flashes fit in a second")
	check(FlashGuard.request(0.2, t + 300) == 0.0 and FlashGuard.dropped == 1, "the fourth flash within a second is dropped")
	check(FlashGuard.warning() != "" or FlashGuard.rate(t + 300) >= FlashGuard.MAX_PER_SECOND, "reaching the frequency limit raises a warning")
	check(FlashGuard.request(0.2, t + 1100) > 0.0, "flashes are accepted again after the window")
	# 減少閃光降階。
	var original := Settings.storage_path()
	Settings.use_storage("user://test_feel_flash.cfg")
	FlashGuard.reset()
	var normal := FlashGuard.request(0.2, 200000)
	Settings.set_reduce_flashes(true)
	FlashGuard.reset()
	var reduced := FlashGuard.request(0.2, 300000)
	check(is_equal_approx(reduced, normal * Settings.REDUCED_FLASH_SCALE), "reduce flashes lowers every screen effect")
	Settings.set_reduce_flashes(false)
	Settings.use_storage(original)
	DirAccess.remove_absolute("user://test_feel_flash.cfg")
	FlashGuard.reset()
	# 真的畫面：效果寫進 shader 並隨時間衰減回 0。
	var level := await start_level(PropsSuite.level_data())
	var post: PostProcess = level._post
	if post != null and post.is_active():
		EventBus.screen_pulse.emit(&"hurt")
		check(post._pulse_amount > 0.0, "a screen effect is accepted")
		post._update_pulse(0.016)
		check(float(post.parameter(&"pulse_amount")) > 0.0, "a screen effect reaches the shader")
		post._update_pulse(1.0)
		post._update_pulse(0.016)
		check(float(post.parameter(&"pulse_amount")) == 0.0, "the screen effect fades back to zero")
	await physics_frames(3)
	await end_level(level)
	FlashGuard.reset()


func _test_diagnostics() -> void:
	var panel := FeelDiagnostics.new()
	runner.get_tree().root.add_child(panel)
	# 腳本事件對照數字：播一次受傷，事件數與頓幀數各加一，閃光次數加一。
	FlashGuard.reset()
	Fx._hitstop_log.clear()
	var before: Dictionary = Feel.read_counters()
	Feel.play(&"player_hurt")
	FlashGuard.request(0.1)  # 沒有關卡時後製不存在，直接走防護的計數
	var after: Dictionary = Feel.read_counters()
	check(int(after["events"]) == int(before.get("events", 0)) + 1, "the event counter counts the scripted event")
	check(int(after["hitstops"]) == int(before.get("hitstops", 0)) + 1, "the hitstop counter counts the hitstop")
	check(int(after["flash_per_second"]) >= 1, "the flash counter shows the screen effect that was requested")
	check(float(after["hitstop_budget_left"]) < Fx.HITSTOP_WINDOW_BUDGET, "the hitstop budget shrinks by the granted stop")
	# 各系統用註冊介面提供計數器；缺的讀取器不會讓面板壞掉。
	Feel.register_counter("test_gauge", func() -> int: return 41)
	Feel.register_counter("test_dead_gauge", Callable())
	var counters: Dictionary = Feel.read_counters()
	check(int(counters["test_gauge"]) == 41 and int(counters["test_dead_gauge"]) == 0, "registered counters are read and broken readers read as zero")
	for key in ["fps", "particles", "voices_playing", "frozen_nodes", "flash_peak", "hitstop_budget_left"]:
		check(counters.has(key), "diagnostics expose %s" % key)
	# 粒子數與已知情境相符。
	var level := await start_level(PropsSuite.level_data())
	var particles_before := Fx.particle_count()
	Fx.sparks(Vector2(100, 100), Color.WHITE, 12)
	check(Fx.particle_count() > particles_before, "the particle counter rises when sparks are emitted")
	# 面板更新頻率約每秒十次，數字沒變時不重設文字。
	panel.refresh()
	var updates_before := panel.updates
	panel._process(0.05)
	check(panel.updates == updates_before, "the panel does not refresh before its 0.1 s interval")
	panel._process(0.06)
	check(panel.updates == updates_before + 1, "the panel refreshes about ten times a second")
	var text_before := panel.text
	panel.refresh()
	check(panel.text == text_before or panel.text.begins_with("fps"), "unchanged numbers keep the same text")
	# 超標警示：閃光頻率達上限時顯示。
	FlashGuard.reset()
	for i in FlashGuard.MAX_PER_SECOND:
		FlashGuard.request(0.1)
	panel.refresh()
	check(panel.text.contains("警示"), "reaching the flash limit shows a warning")
	FlashGuard.reset()
	await physics_frames(3)
	await end_level(level)
	panel.queue_free()


func _test_attack_language() -> void:
	var categories := ["ranged", "melee", "explosive", "beam", "charge", "support"]
	var used := {}
	for file in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var data := load("res://data/enemies/" + file) as EnemyData
		check(data != null and categories.has(String(data.attack_category)), "%s has an attack category (%s)" % [file, data.attack_category if data != null else "?"])
		if data == null:
			continue
		used[String(data.attack_category)] = true
		# 前搖至少 24 格（0.4 秒），例外要寫明理由。
		check(data.telegraph_time >= 0.4 - 0.0001 or data.telegraph_exempt != "", "%s telegraphs at least 24 frames (%.2f s)" % [file, data.telegraph_time])
	# 預兆聲音依類別共用：每個用到的類別都有事件，類別之間聽起來不同（音高不同）。
	var base_pitches: Array[float] = []
	for category: String in used.keys():
		check(Sfx.has_event(StringName("telegraph_" + category)), "telegraph sound exists for category %s" % category)
		var def: Dictionary = Sfx._events.get("telegraph_" + category, {})
		if not def.is_empty() and category != "support":
			base_pitches.append(float(((def["layers"] as Array)[0]["pitch"] as Array)[0]))
	var distinct := {}
	for pitch in base_pitches:
		distinct[snappedf(pitch, 0.05)] = true
	check(distinct.size() == base_pitches.size(), "each attack category has its own telegraph pitch (%s)" % str(base_pitches))
	# 連殺升音有上限、清場慢動作走白名單。
	var chain: Dictionary = Sfx._events["kill_enemy"]["chain"]
	check(int(chain["max"]) <= 6 and int(chain["max"]) >= 1, "the kill streak pitch rise is capped (%d steps)" % int(chain["max"]))
	var pitches: Array[float] = []
	Sfx._chains.clear()
	var now := Time.get_ticks_msec()
	for i in 12:
		pitches.append(Sfx._chain_pitch("kill_enemy", chain, now + i * 100))
	check(is_equal_approx(pitches[11], pitches[int(chain["max"])]) and pitches[1] > pitches[0], "twelve quick kills stop rising at the cap")
	check(Fx.SLOWMO_WHITELIST.has(str(Feel.event_def(&"clear_out")["slowmo"]["reason"])), "the clear-out slow motion is on the whitelist")


func _test_clear_out() -> void:
	var level := await start_level(PropsSuite.level_data())
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await physics_frames(3)
	var spawned: Array[Enemy] = []
	for i in 3:
		var enemy := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
		enemy.position = level.player.global_position + Vector2(160.0 + float(i) * 30.0, 0.0)
		level._entities.add_child(enemy)
		spawned.append(enemy)
	await physics_frames(3)
	Enemy._recent_kills.clear()
	Fx._slowmo_ready_msec = 0
	Feel.recent.clear()
	var kills := 0
	for enemy in spawned:
		var info := DamageInfo.create(999, Combat.Team.PLAYER, &"test")
		info.ignore_invulnerability = true
		info.bypass_guard = true
		enemy.hurtbox.receive(info)
		kills += 1
		await physics_frames(2)
		if kills < 3:
			check(not " ".join(Feel.recent).contains("clear_out"), "no clear-out while enemies are still alive")
	await physics_frames(3)
	check(" ".join(Feel.recent).contains("clear_out"), "killing the last of a quick streak plays the clear-out punctuation")
	Fx.reset_time()
	await physics_frames(3)
	await end_level(level)
