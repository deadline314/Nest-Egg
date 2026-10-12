extends Node
## 每影格耗時走查：機器人在正式關卡裡實際往前跑、跳、開槍、衝刺（敵人照常行動），關掉垂直同步，
## 記錄每一格和上一格實際隔了多久。回答「玩起來卡不卡、卡在哪一關、卡在哪幾格」，不是量單一系統。
## 用法（原生 Forward+；量的時候不要同時跑別的重工作）：
##   godot --path . res://tools/frame_time_probe.tscn -- --out=<絕對資料夾> [--level=ch1_street,ch1_warehouse]
##     [--seconds=20] [--tag=<名稱>] [--idle]
##   --idle：主角站著不動（只量場景本身），和預設的「邊跑邊打」對照。
##   --vsync：不關垂直同步，照玩家實際的設定跑（看的是畫面更新穩不穩：每一格隔幾毫秒的分佈 pacing）。
##   --off=lights,shadows,glow,enemies,weather,props,hud：關掉某一類東西再量，和全開的結果相減就是那一類的成本
##     （lights＝所有 2D 光源、shadows＝只關光源的陰影、glow＝泛光與後製、enemies＝敵人不行動也不畫、
##      weather＝雨與霧、props＝場景擺設、hud＝介面、prefetch＝不預載隔壁區域的貼圖）。
## 輸出 <tag>-frame-time.json：每一關的中位數、第 95／99 百分位、最長的一格、超過 16.7／33.3 毫秒的格數與比例、
##   最長的幾格發生在第幾秒與主角的位置、進關卡花的時間、結束時的節點數與繪製次數。逐關印一行摘要。
## 兩個版本要比較時，用同一份工具、同一組關卡、交替各量幾輪取中位數（機器忙的時候單次的數字會飄）。

const DEFAULT_LEVELS := ["ch1_prologue", "ch1_pawnshop", "ch1_street", "ch1_warehouse", "ch2_market", "ch2_loading", "ch3_plaza", "ch3_pump"]
## 進關卡後先跑這麼久才開始記（著色器第一次編譯、資源第一次載入另外記在 warmup）。
const WARMUP_SECONDS := 2.0
const SLOW_FRAME_MS := 16.7
const HITCH_MS := 33.3
const WORST_KEPT := 8
const JUMP_EVERY := 1.3
const DASH_EVERY := 3.1
const STUCK_JUMP := 0.6
const STUCK_TURN := 2.2

var _out := ""
var _tag := "probe"
var _levels: PackedStringArray = []
var _seconds := 20.0
var _idle := false
var _off: PackedStringArray = []
var _vsync := false
var _recording := false
var _last_usec := 0
var _samples := PackedFloat32Array()
var _stamps := PackedFloat32Array()
var _clock := 0.0
var _player: Node2D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=").replace("\\", "/")
		elif arg.begins_with("--level="):
			_levels = arg.trim_prefix("--level=").split(",", false)
		elif arg.begins_with("--seconds="):
			_seconds = maxf(3.0, float(arg.trim_prefix("--seconds=")))
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
		elif arg == "--idle":
			_idle = true
		elif arg == "--vsync":
			_vsync = true
		elif arg.begins_with("--off="):
			_off = arg.trim_prefix("--off=").split(",", false)
	if _levels.is_empty():
		_levels = PackedStringArray(DEFAULT_LEVELS)
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[FrameTimeProbe] --out 必須是可建立的絕對路徑：%s" % _out)
		get_tree().quit(2)
		return
	if not _vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _recording:
		return
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	_clock += ms / 1000.0
	_samples.append(ms)
	_stamps.append(_player.global_position.x if is_instance_valid(_player) else 0.0)


func _run() -> void:
	Story.auto_skip = true
	var report: Array[Dictionary] = []
	for level_id in _levels:
		var path := "res://data/levels/%s.tres" % level_id
		if not ResourceLoader.exists(path):
			push_error("[FrameTimeProbe] 找不到關卡：%s" % path)
			continue
		report.append(await _play(level_id, path))
	var file := FileAccess.open(_out.path_join("%s-frame-time.json" % _tag), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"tag": _tag, "seconds": _seconds, "idle": _idle, "levels": report}, "  "))
	get_tree().quit(0)


func _play(level_id: String, path: String) -> Dictionary:
	var load_start := Time.get_ticks_usec()
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(path) as LevelData)
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	var load_ms := float(Time.get_ticks_usec() - load_start) / 1000.0
	_player = level.player
	level.player.health.setup(99999, 0.0)
	level.player.health.grant_invulnerability(100000.0)
	level._next_story_trigger = level._layout.story_triggers.size()
	AimInput.set_virtual_gamepad(level.player, true)
	var right_edge := level._layout.pixel_size().x - 48.0
	_apply_off(level)
	var census := _census(level)
	var prefetch_before: Dictionary = AssetPrefetch.stats()
	if _off.has("prefetch"):
		AssetPrefetch.clear()
	# 熱身：這一段的最長一格另外記（第一次看到的特效與貼圖會在這裡編譯、載入）。
	var warmup := await _drive(level, WARMUP_SECONDS, right_edge)
	var result := await _drive(level, _seconds, right_edge)
	_release()
	AimInput.set_virtual_gamepad(level.player, false)
	result["level"] = level_id
	result["census"] = census
	var prefetch_after: Dictionary = AssetPrefetch.stats()
	result["prefetch"] = {"loads": int(prefetch_after.get("main_load_total", 0)) - int(prefetch_before.get("main_load_total", 0)),
			"queued_at_start": int(prefetch_before.get("queued", 0)), "queued_at_end": int(prefetch_after.get("queued", 0)),
			"max_load_ms": snappedf(float(prefetch_after.get("main_max_load_us", 0)) / 1000.0, 0.1),
			"over_budget": int(prefetch_after.get("main_over_budget_total", 0)) - int(prefetch_before.get("main_over_budget_total", 0)),
			"warmed_files": int(prefetch_after.get("warm_files_total", 0)) - int(prefetch_before.get("warm_files_total", 0)),
			"waited_frames": int(prefetch_after.get("warm_waits_total", 0)) - int(prefetch_before.get("warm_waits_total", 0)),
			"warm_timeouts": int(prefetch_after.get("warm_timeouts_total", 0)) - int(prefetch_before.get("warm_timeouts_total", 0)),
			"busy_skips": int(prefetch_after.get("busy_skips_total", 0)) - int(prefetch_before.get("busy_skips_total", 0))}
	print("PREFETCH %s %s" % [level_id, JSON.stringify(result["prefetch"])])
	result["load_ms"] = snappedf(load_ms, 0.1)
	result["warmup_max_ms"] = warmup["max_ms"]
	result["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	result["draw_calls"] = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	result["canvas_items"] = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	print("CENSUS %s %s" % [level_id, JSON.stringify(census)])
	print("PACING %s %s changes %.1f%%" % [level_id, JSON.stringify(result["pacing_percent"]), result["pace_changes_percent"]])
	print("FRAME_TIME %s median %.2f ms p95 %.2f p99 %.2f max %.1f | >16.7ms %d (%.2f%%) >33.3ms %d | load %.0f ms warmup max %.1f | nodes %d draws %d" % [
			level_id, result["median_ms"], result["p95_ms"], result["p99_ms"], result["max_ms"], result["slow_frames"], result["slow_percent"],
			result["hitches"], load_ms, warmup["max_ms"], result["nodes"], result["draw_calls"]])
	_player = null
	level.queue_free()
	for i in 6:
		await get_tree().process_frame
	return result


## 讓機器人玩 seconds 秒並記錄每一格；回傳這一段的統計。
func _drive(level: Level, seconds: float, right_edge: float) -> Dictionary:
	var player := level.player
	_samples.clear()
	_stamps.clear()
	_clock = 0.0
	_last_usec = Time.get_ticks_usec()
	_recording = true
	var direction := 1.0
	var since_jump := 0.0
	var since_dash := 0.0
	var stuck := 0.0
	var last_x := player.global_position.x
	var tree := get_tree()
	while _clock < seconds and is_instance_valid(player):
		await tree.physics_frame
		var step := 1.0 / float(Engine.physics_ticks_per_second)
		if _idle:
			continue
		since_jump += step
		since_dash += step
		var x := player.global_position.x
		stuck = stuck + step if absf(x - last_x) < 0.4 else 0.0
		last_x = x
		if x > right_edge or stuck > STUCK_TURN:
			direction = -1.0 if x > right_edge or direction > 0.0 else 1.0
			stuck = 0.0
		elif x < 48.0:
			direction = 1.0
		_hold(&"move_right", direction > 0.0)
		_hold(&"move_left", direction < 0.0)
		_hold(&"aim_right", direction > 0.0)
		_hold(&"aim_left", direction < 0.0)
		_hold(&"shoot", true)
		var jump := since_jump > JUMP_EVERY or stuck > STUCK_JUMP
		_hold(&"jump", jump and since_jump > 0.25)
		if jump and since_jump > 0.45:
			since_jump = 0.0
		_hold(&"dash", since_dash > DASH_EVERY)
		if since_dash > DASH_EVERY + 0.1:
			since_dash = 0.0
	_recording = false
	return _stats()


## 關卡裡各類節點有幾個（光源、有陰影的光源、遮光體、粒子、圖片、敵人），兩個版本對照用。
func _census(level: Node) -> Dictionary:
	var counts := {"lights": 0, "lights_enabled": 0, "lights_shadow": 0, "light_pixels": 0.0, "occluders": 0, "particles": 0, "sprites": 0, "canvas_items": 0, "processing": 0, "physics_processing": 0}
	var classes: Dictionary = {}
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is PointLight2D:
			var light := node as PointLight2D
			counts["lights"] += 1
			if light.enabled and light.is_visible_in_tree():
				counts["lights_enabled"] += 1
				if light.shadow_enabled:
					counts["lights_shadow"] += 1
				if light.texture != null:
					var size: Vector2 = light.texture.get_size() * light.texture_scale * light.global_scale
					counts["light_pixels"] = float(counts["light_pixels"]) + size.x * size.y
		elif node is LightOccluder2D:
			counts["occluders"] += 1
		elif node is GPUParticles2D or node is CPUParticles2D:
			counts["particles"] += 1
		elif node is Sprite2D:
			counts["sprites"] += 1
		if node is CanvasItem:
			counts["canvas_items"] += 1
		if node.is_processing():
			counts["processing"] += 1
		if node.is_physics_processing():
			counts["physics_processing"] += 1
		var script: Script = node.get_script()
		var kind: String = node.get_class()
		if script != null and not String(script.get_global_name()).is_empty():
			kind = String(script.get_global_name())
		classes[kind] = int(classes.get(kind, 0)) + 1
	counts["light_pixels"] = snappedf(counts["light_pixels"] / 1000000.0, 0.01)
	var names: Array = classes.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return int(classes[a]) > int(classes[b]))
	var top: Dictionary = {}
	for i in mini(14, names.size()):
		top[names[i]] = classes[names[i]]
	counts["top_classes"] = top
	counts["enemies"] = get_tree().get_nodes_in_group(&"enemies").size()
	return counts


func _apply_off(level: Level) -> void:
	if _off.is_empty():
		return
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is PointLight2D:
			if _off.has("lights"):
				(node as PointLight2D).enabled = false
			if _off.has("shadows"):
				(node as PointLight2D).shadow_enabled = false
		elif node is WorldEnvironment and _off.has("glow"):
			node.queue_free()
		elif node is CanvasItem and node.get_script() != null:
			var kind := String((node.get_script() as Script).get_global_name())
			if (_off.has("weather") and kind in ["RainLayer", "FogLayer"]) or (_off.has("props") and kind == "PropNode"):
				(node as CanvasItem).visible = false
				node.set_process(false)
	if _off.has("enemies"):
		for enemy in get_tree().get_nodes_in_group(&"enemies"):
			enemy.set_physics_process(false)
			enemy.set_process(false)
			if enemy is CanvasItem:
				(enemy as CanvasItem).visible = false
	if _off.has("hud") and level.hud != null:
		level.hud.visible = false


func _stats() -> Dictionary:
	var count := _samples.size()
	if count == 0:
		return {"pacing_percent": {}, "pace_changes_percent": 0.0, "frames": 0, "median_ms": 0.0, "p95_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0, "slow_frames": 0, "slow_percent": 0.0, "hitches": 0, "worst": []}
	var sorted := _samples.duplicate()
	sorted.sort()
	var slow := 0
	var hitches := 0
	var order: Array[int] = []
	for i in count:
		if _samples[i] > SLOW_FRAME_MS:
			slow += 1
		if _samples[i] > HITCH_MS:
			hitches += 1
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _samples[a] > _samples[b])
	var worst: Array[Dictionary] = []
	var elapsed := PackedFloat32Array()
	elapsed.resize(count)
	var total := 0.0
	for i in count:
		total += _samples[i] / 1000.0
		elapsed[i] = total
	for i in mini(WORST_KEPT, count):
		var index := order[i]
		worst.append({"ms": snappedf(_samples[index], 0.1), "at_second": snappedf(elapsed[index], 0.01), "player_x": snappedf(_stamps[index], 1.0)})
	# 每一格隔多久的分佈（毫秒）：垂直同步開著時，間隔會落在螢幕更新週期的整數倍，忽長忽短就是看起來卡的原因。
	var pacing := {"under_6": 0, "6_to_9": 0, "9_to_12": 0, "12_to_17": 0, "over_17": 0}
	for i in count:
		var ms := _samples[i]
		var bucket := "under_6" if ms < 6.0 else ("6_to_9" if ms < 9.0 else ("9_to_12" if ms < 12.0 else ("12_to_17" if ms < 17.0 else "over_17")))
		pacing[bucket] = int(pacing[bucket]) + 1
	for key: String in pacing:
		pacing[key] = snappedf(100.0 * int(pacing[key]) / count, 0.1)
	var jumps := 0
	for i in range(1, count):
		if absf(_samples[i] - _samples[i - 1]) > 2.5:
			jumps += 1
	return {"pacing_percent": pacing, "pace_changes_percent": snappedf(100.0 * jumps / count, 0.1),
			"frames": count, "median_ms": snappedf(sorted[count / 2], 0.01), "p95_ms": snappedf(sorted[int(count * 0.95)], 0.01),
			"p99_ms": snappedf(sorted[int(count * 0.99)], 0.01), "max_ms": snappedf(sorted[count - 1], 0.1), "slow_frames": slow,
			"slow_percent": snappedf(100.0 * slow / count, 0.01), "hitches": hitches, "worst": worst}


func _hold(action: StringName, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release() -> void:
	for action: StringName in [&"move_left", &"move_right", &"aim_left", &"aim_right", &"shoot", &"jump", &"dash"]:
		_hold(action, false)
