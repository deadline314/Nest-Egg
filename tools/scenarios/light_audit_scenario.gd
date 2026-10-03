class_name LightAuditScenario
extends ScenarioBase
## 開發工具（BG-12）：戰鬥中的光影與粒子負載量測。玩家對一排站著的敵人連續開火（真的子彈、真的受擊與死亡），
## 每 0.5 秒取樣：每影格處理時間、繪製呼叫、畫面物件數、節點數、場景裡的光源數（全部／啟用中／預算管理／想要陰影）、
## 粒子場存活的粒子數，結束時印出每一項的最小、平均、最大值，並在幾個時間點截圖。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=light_audit [--lighting=transfer] [--weapon=rifle] [--enemies=10] [--seconds=14]
##        [--level=level_01 --tile=115]（改在真實關卡的某一欄量測，敵人站在玩家前方；不給就用空曠場地）

var _lighting := "transfer"
var _weapon := "rifle"
var _enemies := 10
var _seconds := 14.0
var _level_id := ""
var _tile := 12.0
var _series := {}
var _frame_ms: Array[float] = []
var _spikes: Array[String] = []


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lighting="):
			_lighting = arg.trim_prefix("--lighting=")
		elif arg.begins_with("--weapon="):
			_weapon = arg.trim_prefix("--weapon=")
		elif arg.begins_with("--enemies="):
			_enemies = int(arg.trim_prefix("--enemies="))
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--level="):
			_level_id = arg.trim_prefix("--level=")
		elif arg.begins_with("--tile="):
			_tile = float(arg.trim_prefix("--tile="))
	if _level_id.is_empty():
		await open_arena("res://data/lighting/%s.tres" % _lighting, 8.0)
	else:
		await _open_level()
	await clear_enemies()
	var weapon := load("res://data/weapons/%s.tres" % _weapon) as WeaponData
	for i in _enemies:
		var enemy := spawn_enemy("res://data/enemies/grunt.tres", _base_tile() + 8.0 + i * 1.6, _floor_y())
		enemy.data = enemy.data.duplicate()
		enemy.data.detect_range = 0.0
		enemy.data.attack_range = 0.0
		enemy.data.move_speed = 0.0
		enemy.health.setup(60, 0.0)
	await wait(0.8)
	capture("light_audit_0_before")
	# 關掉垂直同步與幀率上限，量到的才是真實的每影格耗時（不然都被 60 FPS 蓋住）。
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await settle(10)
	var elapsed := 0.0
	var next_sample := 0.0
	var next_shot := 0.0
	var shots_captured := 0
	while elapsed < _seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		elapsed += dt
		_frame_ms.append(dt * 1000.0)
		if dt > 0.03:
			_spikes.append("%.1fs: %.0f ms" % [elapsed, dt * 1000.0])
		if elapsed >= next_shot:
			next_shot = elapsed + 0.12
			var origin := player.global_position + Vector2(10.0, -26.0)
			WeaponSystem.fire(weapon, origin, Vector2.RIGHT.rotated(randf_range(-0.04, 0.04)), Combat.Team.PLAYER)
		# 敵人被打死就補一隻，保持場面的負載
		if get_tree().get_nodes_in_group(&"enemies").size() < _enemies:
			spawn_enemy("res://data/enemies/grunt.tres", _base_tile() + 10.0 + randf() * 14.0, _floor_y())
		if elapsed >= next_sample:
			next_sample = elapsed + 0.5
			_sample()
			if shots_captured < 3 and elapsed > 2.0 + shots_captured * 3.0:
				capture("light_audit_%d_during" % (shots_captured + 1))
				shots_captured += 1
	_report()
	_census()
	await finish()


func _base_tile() -> float:
	return player.global_position.x / 16.0


func _floor_y() -> float:
	return player.global_position.y


## 真實關卡：玩家站在指定欄的地面，血量加滿、HUD 關掉（同 screenshot 的 spots 情境）。
func _open_level() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load("res://data/levels/%s.tres" % _level_id))
	add_child(level)
	await settle(25)
	level.hud.visible = false
	player = level.player
	player.health.setup(999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var layout: LevelLayout = level._layout
	var y := layout.surface_heights[int(_tile)] - 2.0
	if layout.surface_heights[int(_tile)] < layout.tile_size * 4.0:
		y = layout.floor_below(int(_tile), 4) - 2.0
	player.global_position = Vector2(_tile * layout.tile_size + 8.0, y)
	player.velocity = Vector2.ZERO
	snap_camera()
	await wait(TITLE_CARD_TIME)


func _sample() -> void:
	var lights_total := 0
	var lights_enabled := 0
	var shadow_on := 0
	for light: Node in level.find_children("*", "PointLight2D", true, false):
		var l := light as PointLight2D
		lights_total += 1
		if l.enabled and l.visible:
			lights_enabled += 1
			if l.shadow_enabled:
				shadow_on += 1
	var managed := get_tree().get_nodes_in_group(LightKit.SCENE_LIGHTS).size()
	var alive := 0
	for node: Node in level.find_children("*", "ParticleField", true, false):
		var field := node as ParticleField
		alive += int(field.get("_alive")) if field.get("_alive") != null else 0
	_add("fps", Engine.get_frames_per_second())
	_add("process_ms", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_add("physics_ms", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_add("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add("objects_in_frame", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_add("nodes", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_add("lights_all", lights_total)
	_add("lights_on", lights_enabled)
	_add("lights_managed", managed)
	_add("lights_shadow", shadow_on)
	_add("particles_alive", alive)
	_add("texture_mem_mb", Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0)


func _add(key: String, value: float) -> void:
	if not _series.has(key):
		_series[key] = []
	(_series[key] as Array).append(value)


func _report() -> void:
	_frame_ms.sort()
	var sum_ms := 0.0
	for v: float in _frame_ms:
		sum_ms += v
	print("== frame time without vsync (ms): avg %.2f  median %.2f  p95 %.2f  p99 %.2f  max %.2f  (%d frames)" % [sum_ms / _frame_ms.size(), _frame_ms[_frame_ms.size() / 2], _frame_ms[int(_frame_ms.size() * 0.95)], _frame_ms[int(_frame_ms.size() * 0.99)], _frame_ms[-1], _frame_ms.size()])
	print("== frames over 30 ms: %d  %s" % [_spikes.size(), ", ".join(_spikes.slice(0, 12))])
	print("== light_audit lighting=%s weapon=%s enemies=%d samples=%d" % [_lighting, _weapon, _enemies, (_series["fps"] as Array).size()])
	for key: String in _series:
		var values: Array = _series[key]
		var lo: float = values[0]
		var hi: float = values[0]
		var sum := 0.0
		for v: float in values:
			lo = minf(lo, v)
			hi = maxf(hi, v)
			sum += v
		print("  %-18s min %8.2f  avg %8.2f  max %8.2f" % [key, lo, sum / values.size(), hi])


## 畫面上可見的 CanvasItem 依「腳本類別／節點類別」統計（找出繪製呼叫的大宗），並列出各自的材質種類數。
func _census() -> void:
	var viewport := get_viewport()
	var inverse := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(inverse * Vector2.ZERO, inverse.basis_xform(viewport.get_visible_rect().size)).abs().grow(64.0)
	var counts := {}
	var onscreen := {}
	var materials := {}
	for node: Node in level.find_children("*", "CanvasItem", true, false):
		var item := node as CanvasItem
		if not item.is_visible_in_tree():
			continue
		var script := item.get_script() as Script
		var key := String(script.get_global_name()) if script != null and script.get_global_name() != &"" else item.get_class()
		counts[key] = int(counts.get(key, 0)) + 1
		if item is Node2D and view.has_point((item as Node2D).global_position):
			onscreen[key] = int(onscreen.get(key, 0)) + 1
		if item.material != null:
			materials[item.material] = true
	print("-- by top-level child of the level (visible CanvasItems below it)")
	for child in level.get_children():
		var n := 0
		for d: Node in child.find_children("*", "CanvasItem", true, false):
			if (d as CanvasItem).is_visible_in_tree():
				n += 1
		if n > 20:
			print("  %-28s %5d" % [child.name, n])
	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	print("== census: visible CanvasItems %d (distinct materials %d)" % [_sum(counts), materials.size()])
	for i in mini(18, keys.size()):
		print("  %-26s %5d  (near the camera: %d)" % [keys[i], counts[keys[i]], int(onscreen.get(keys[i], 0))])


func _sum(d: Dictionary) -> int:
	var total := 0
	for k in d:
		total += int(d[k])
	return total
