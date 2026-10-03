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
	var early := camera._shake_magnitude(0.0)
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

	func on_shake(px: float, _time: float) -> void:
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
