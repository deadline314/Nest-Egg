extends Node
## 原生 Forward+ 的正式暫停／任務／地圖開啟量測。
## 合成鍵盤事件操作真 PauseMenu；不是人工或實體手把驗收。
## python tools/comfyui/gpu_lock.py -- godot --path . res://tools/quest_map_perf_probe.tscn -- --out=<絕對資料夾>

var _out := ""
var _rounds := 16
var _width := 1280
var _height := 720
var _shared_workload := false
var _rows: Array[Dictionary] = []
var _freeze_samples: Array[Dictionary] = []
var _issues: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=").replace("\\", "/")
		elif arg.begins_with("--rounds="):
			_rounds = maxi(4, int(arg.trim_prefix("--rounds=")))
		elif arg.begins_with("--width="):
			_width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="):
			_height = int(arg.trim_prefix("--height="))
		elif arg == "--shared-workload":
			_shared_workload = true
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[QuestMapPerf] --out 必須是可建立的絕對路徑。")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(_width, _height)
	DisplayMode.ensure_scaling(get_window())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	var sources := preload("res://tools/world_pause_sample.gd").source_receipt(_out, ["res://tools/quest_map_perf_probe.gd", "res://tools/world_pause_sample.gd", "res://ui/kit/scene_backdrop.gd"])
	Settings.use_storage("user://ne223-perf-probe-settings.cfg")
	Settings.set_ui_text_scale(1.0)
	get_window().size = Vector2i(_width, _height)
	DisplayMode.ensure_scaling(get_window())
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[0])
	add_child(LightKit.create_environment())
	var level := Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	level.configure(load("res://data/levels/ch1_pawnshop.tres") as LevelData)
	add_child(level)
	# 真場景暖身；首次開 UI 仍獨立列出，不預建地圖或覆蓋畫面。
	await get_tree().create_timer(2.0, true, false, true).timeout
	var pause: PauseMenu = level._pause_menu
	var texture: Texture2D
	for round_index in _rounds:
		await _measure("idle", round_index)
		await _measure("pause", round_index, KEY_P)
		_expect(pause._root.visible and get_tree().paused, "暫停應開啟並凍結世界。")
		var frozen := preload("res://tools/world_pause_sample.gd").snapshot(level)
		await _measure("journal", round_index, KEY_O)
		_expect(is_instance_valid(pause._navigation) and pause._navigation._page == "quests", "任務快捷鍵應打開正式任務目錄。")
		if not is_instance_valid(pause._navigation):
			break
		if round_index == _rounds - 1:
			await _capture("journal")
		await _measure("region", round_index, KEY_E)
		var screen: QuestMapScreen = pause._navigation
		_expect(screen._page == "region" and screen._canvas != null, "下一分頁應顯示區域地圖。")
		if screen._canvas == null:
			break
		var canvas: QuestMapCanvas = screen._canvas
		if round_index > 0:
			_expect(canvas.builds == 0 and canvas._texture == texture, "反覆開啟地圖應重用同一份探索地形。")
		texture = canvas._texture
		if round_index == _rounds - 1:
			if not canvas._markers.is_empty():
				canvas._markers[0].grab_focus()
				_expect(screen._status.text == canvas._markers[0].tooltip_text, "聚焦圖示應顯示同一份 tooltip。")
			await _capture("region-focus")
		await _measure("world", round_index, KEY_E)
		_expect(screen._page == "world", "下一分頁應顯示世界地圖。")
		if round_index == _rounds - 1:
			await _capture("world")
		await _measure("back-region", round_index, KEY_ESCAPE)
		_expect(screen._page == "region" and screen._canvas.builds == 0, "世界地圖返回應重用區域地形。")
		await _tap(KEY_ESCAPE)
		_expect(screen._page == "quests", "區域返回應先回任務目錄。")
		await _tap(KEY_ESCAPE)
		_expect(not is_instance_valid(pause._navigation) and pause._root.visible and get_tree().paused, "任務返回應先回暫停選單。")
		var after := preload("res://tools/world_pause_sample.gd").snapshot(level)
		_freeze_samples.append({"round": round_index, "before": frozen, "after": after, "unchanged": frozen == after})
		_expect(frozen == after and level.process_mode == Node.PROCESS_MODE_PAUSABLE, "選單操作期間玩家、鏡頭、世界霧時間與遊玩時間都必須真正凍結。")
		await _tap(KEY_ESCAPE)
		_expect(not pause._root.visible and not get_tree().paused, "暫停返回後才恢復遊戲。")
		await _settle()
		_rows.append({"action": "retained", "round": round_index, "static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "cache_entries": QuestMapCanvas._cache.size()})
	var report := {"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info()["string"], "resolution": [_width, _height], "rounds": _rounds, "vsync": false, "shared_workload": _shared_workload, "timing": "input to next frame_post_draw; includes frame scheduling and rendering submission, not physical display latency", "input": "synthetic keyboard events through the real PauseMenu; no physical controller", "level": level.data.resource_path, "sources": sources, "samples": _rows, "freeze_samples": _freeze_samples, "summary": _summary(), "issues": _issues}
	var file := FileAccess.open(_out.path_join("quest-map-perf-%d.json" % _width), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("QUEST_MAP_PERF ", JSON.stringify(report["summary"]))
	print("QUEST_MAP_PERF issues: ", _issues)
	get_tree().paused = false
	level.queue_free()
	await _settle()
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await get_tree().create_timer(0.3, true, false, true).timeout
	get_tree().quit(0 if _issues.is_empty() else 1)


## 輸入到下一個 frame_post_draw；包含排程與送交繪製，非螢幕實體顯示延遲。
func _measure(action: String, round_index: int, key: Key = KEY_NONE) -> void:
	await RenderingServer.frame_post_draw
	var start := Time.get_ticks_usec()
	if key != KEY_NONE:
		_event(key, true)
	var cpu_ms := (Time.get_ticks_usec() - start) / 1000.0
	await RenderingServer.frame_post_draw
	_rows.append({"action": action, "round": round_index, "first_open": round_index == 0, "input_ms": cpu_ms, "frame_ms": (Time.get_ticks_usec() - start) / 1000.0})
	if key != KEY_NONE:
		_event(key, false)
	await _settle()


func _event(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	get_viewport().push_input(event)


func _tap(key: Key) -> void:
	_event(key, true)
	await _settle()
	_event(key, false)
	await _settle()


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


func _capture(page: String) -> void:
	await RenderingServer.frame_post_draw
	var encoded := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_expect(encoded.get_size() == Vector2i(_width, _height), "截圖實際像素必須符合要求的原生解析度。")
	var error := encoded.save_png(_out.path_join("NE-223-native-%s-%d.png" % [page, _width]))
	_expect(error == OK, "截圖應可儲存：%s" % page)


func _expect(condition: bool, issue: String) -> void:
	if not condition:
		_issues.append(issue)
		push_error("[QuestMapPerf] " + issue)


func _summary() -> Dictionary:
	var result := {}
	for action in ["idle", "pause", "journal", "region", "world", "back-region"]:
		var samples: Array[float] = []
		var first := 0.0
		for row in _rows:
			if row["action"] != action:
				continue
			if row["round"] == 0:
				first = row["frame_ms"]
			else:
				samples.append(row["frame_ms"])
		samples.sort()
		if not samples.is_empty():
			result[action] = {"first_ms": first, "warm_median_ms": samples[samples.size() / 2], "warm_p95_ms": samples[mini(samples.size() - 1, int(samples.size() * 0.95))], "warm_max_ms": samples.back()}
	return result
