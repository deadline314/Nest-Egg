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
