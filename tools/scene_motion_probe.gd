extends Node
## 場景動態驗收（BG-25）：把鏡頭對準指定擺設，連拍幾個時刻，再檢查暫停、恢復與反覆重進關卡。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/scene_motion_probe.tscn -- --out=<絕對資料夾> --level=<關卡檔名> --prop=<擺設 id>
##     [--times=0,0.2,0.4,0.8,1.2] [--quality=low|medium|high] [--reentries=10] [--tag=<標籤>]
## 輸出 <標籤>-t<秒>.png 與 <標籤>-report.json：
##   暫停時滴水與水流的時鐘有沒有停住、恢復後有沒有繼續；
##   每次重進關卡後的節點數、孤兒節點、引擎回報的貼圖記憶體；
##   連拍期間每影格處理時間的中位數（--no-motion 把這個擺設的動態拿掉當對照）。

const Capture := preload("res://tools/viewport_capture.gd")
const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}
const SETTLE_FRAMES := 30
const PAUSE_SECONDS := 0.5
const FRAME_SAMPLES := 180
## 重進關卡時允許的量測起伏：貼圖 4 MiB（分批載入的時間差）、引擎配置 1 MiB。
const TEXTURE_GROWTH_SLACK := 4 * 1048576
const STATIC_GROWTH_SLACK := 1048576

var _out := ""
var _level_id := ""
var _prop_id := ""
var _times := PackedFloat32Array([0.0, 0.2, 0.4, 0.8, 1.2])
var _quality := ""
var _reentries := 10
var _tag := "motion"
var _no_motion := false
var _checks := 0
var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--level="):
			_level_id = argument.trim_prefix("--level=")
		elif argument.begins_with("--prop="):
			_prop_id = argument.trim_prefix("--prop=")
		elif argument.begins_with("--times="):
			_times = PackedFloat32Array()
			for value: String in argument.trim_prefix("--times=").split(",", false):
				_times.append(float(value))
		elif argument.begins_with("--quality="):
			_quality = argument.trim_prefix("--quality=")
		elif argument.begins_with("--reentries="):
			_reentries = clampi(int(argument.trim_prefix("--reentries=")), 0, 30)
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument == "--no-motion":
			_no_motion = true
	if not _out.is_absolute_path() or _level_id.is_empty() or _prop_id.is_empty() or DisplayServer.get_name() == "headless":
		push_error("[SceneMotionProbe] 需要原生視窗、--out=<絕對資料夾>、--level 與 --prop")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[SceneMotionProbe] 無法建立輸出資料夾：%s" % _out)
		get_tree().quit(2)
		return
	_run.call_deferred()


func _check(value: bool, label: String) -> bool:
	_checks += 1
	if not value:
		_failures += 1
	print("MOTION_CHECK:", "PASS" if value else "FAIL", ":", label)
	return value


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _open_level() -> Level:
	var path := "res://data/levels/%s.tres" % _level_id
	var data := load(path) as LevelData if ResourceLoader.exists(path) else null
	if data == null:
		return null
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	level.configure(data)
	add_child(level)
	await _settle(SETTLE_FRAMES)
	level.hud.visible = false
	for child: Node in level.get_children():
		if child is ChapterCard:
			child.queue_free()
	level.player.process_mode = Node.PROCESS_MODE_DISABLED
	level.player.visible = false
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		node.process_mode = Node.PROCESS_MODE_DISABLED
	level._lighting._lightning_gap = 1.0e9
	return level


func _find_prop(level: Level) -> PropNode:
	for node: Node in level.find_children("*", "Node2D", true, false):
		var prop := node as PropNode
		if prop != null and prop.data != null and String(prop.data.id) == _prop_id:
			return prop
	return null


## 這個擺設身上會動的元件的時鐘（滴水、水流）；沒有就是空的。
func _clocks(prop: PropNode) -> Dictionary:
	var result := {}
	var drip := prop.get_node_or_null("LocalDrip") as LocalDrip
	if drip != null:
		result["drip"] = drip.clock
	var flow := prop.get_node_or_null("LocalWaterFlow")
	if flow != null:
		result["flow"] = float(flow.get("clock"))
	return result


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _stats() -> Dictionary:
	return {"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"texture_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"static_bytes": OS.get_static_memory_usage()}


func _run() -> void:
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	Story._layer.visible = false
	var quality_before := Settings.get_light_quality()
	if QUALITY.has(_quality):
		Settings.set_light_quality(QUALITY[_quality])
	var report := {"level": _level_id, "prop": _prop_id, "tag": _tag, "quality": _quality, "no_motion": _no_motion}
	var level := await _open_level()
	var prop := _find_prop(level) if level != null else null
	if not _check(prop != null, "prop found in the level: " + _prop_id):
		await _finish(report, quality_before)
		return
	if _no_motion:
		for name: String in ["LocalDrip", "LocalWaterFlow"]:
			var part := prop.get_node_or_null(name)
			if part != null:
				part.free()
	var camera := get_viewport().get_camera_2d() as LevelCamera
	camera.set_physics_process(false)
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * LevelCamera.ZOOM * 2.0
	camera.global_position = prop.global_position + prop.data.size * 0.5
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _settle(SETTLE_FRAMES)
	report["prop_rect"] = [prop.global_position.x, prop.global_position.y, prop.data.size.x, prop.data.size.y]
	# 連拍：從滴水週期的起點開始，時間對得上才看得出落下、濺開、等待。
	var drip := prop.get_node_or_null("LocalDrip") as LocalDrip
	if drip != null:
		drip.clock = 0.0
	var started := Time.get_ticks_msec()
	var shots: Array[Dictionary] = []
	for at: float in _times:
		while (Time.get_ticks_msec() - started) / 1000.0 < at:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file := "%s-t%04d.png" % [_tag, int(round(at * 1000.0))]
		Capture.image(get_viewport()).save_png(_out.path_join(file))
		shots.append({"file": file, "time": at, "clocks": _clocks(prop), "drip_stage": String(drip.stage()) if drip != null else ""})
	report["shots"] = shots
	# 每影格實際花的時間：關掉垂直同步，量相鄰兩格之間的間隔（開著的話只會量到螢幕更新率）。
	var vsync_before := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _settle(10)
	var frame_ms: Array[float] = []
	var last_usec := Time.get_ticks_usec()
	for _frame in FRAME_SAMPLES:
		await get_tree().process_frame
		var now_usec := Time.get_ticks_usec()
		frame_ms.append(float(now_usec - last_usec) / 1000.0)
		last_usec = now_usec
	DisplayServer.window_set_vsync_mode(vsync_before)
	report["frame_ms_median"] = _median(frame_ms)
	report["monitor_process_s"] = Performance.get_monitor(Performance.TIME_PROCESS)
	report["monitor_physics_s"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	# 暫停與恢復
	if not _no_motion and not _clocks(prop).is_empty():
		var before := _clocks(prop)
		get_tree().paused = true
		await get_tree().create_timer(PAUSE_SECONDS, true).timeout
		var during := _clocks(prop)
		get_tree().paused = false
		await get_tree().create_timer(PAUSE_SECONDS, true).timeout
		var after := _clocks(prop)
		var frozen := true
		var resumed := true
		for key: String in before:
			frozen = frozen and is_equal_approx(float(before[key]), float(during[key]))
			resumed = resumed and not is_equal_approx(float(during[key]), float(after[key]))
		_check(frozen, "motion clocks stop while the game is paused")
		_check(resumed, "motion clocks continue after resuming")
		report["pause"] = {"before": before, "during": during, "after": after}
	# 反覆重進關卡：節點與貼圖不累積。
	var entries: Array[Dictionary] = []
	level.queue_free()
	await _settle(8)
	for index in _reentries:
		level = await _open_level()
		var again := _find_prop(level) if level != null else null
		var entry := _stats()
		entry["motion_nodes"] = (1 if again != null and again.get_node_or_null("LocalDrip") != null else 0) \
				+ (1 if again != null and again.get_node_or_null("LocalWaterFlow") != null else 0)
		entries.append(entry)
		level.queue_free()
		await _settle(8)
	report["reentries"] = entries
	if entries.size() >= 4:
		var first := entries[1]
		var last := entries[entries.size() - 1]
		_check(int(last["nodes"]) == int(first["nodes"]) and int(last["orphans"]) == 0,
				"node count is the same after repeated re-entry (%d → %d), no orphans" % [first["nodes"], last["nodes"]])
		# 貼圖是分批載入的，取樣當下的數字會上下跳；看的是後半段的最高點有沒有超過前半段。
		var half := entries.size() / 2
		var early_peak := 0
		var late_peak := 0
		for index in entries.size():
			if index < half:
				early_peak = maxi(early_peak, int(entries[index]["texture_bytes"]))
			else:
				late_peak = maxi(late_peak, int(entries[index]["texture_bytes"]))
		_check(late_peak <= early_peak + TEXTURE_GROWTH_SLACK,
				"texture memory does not keep growing across re-entries (peaks %d → %d bytes)" % [early_peak, late_peak])
		_check(absi(int(last["static_bytes"]) - int(first["static_bytes"])) <= STATIC_GROWTH_SLACK,
				"engine memory is the same after repeated re-entry")
	report["after_cleanup"] = _stats()
	await _finish(report, quality_before)


func _finish(report: Dictionary, quality_before: int) -> void:
	if QUALITY.has(_quality):
		Settings.set_light_quality(quality_before)
	report["checks"] = _checks
	report["failures"] = _failures
	var writer := FileAccess.open(_out.path_join(_tag + "-report.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[SceneMotionProbe] 無法寫入報告：%s" % _out)
		_failures += 1
	else:
		writer.store_string(JSON.stringify(report, "\t"))
		writer.close()
	print("MOTION_RESULT:", _checks, " checks / ", _failures, " failures")
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if _failures == 0 else 1)
