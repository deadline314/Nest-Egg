extends Node
## 場景巡覽：把關卡依固定格子從左到右、從上到下拍成原生畫面，逐區檢查佈景、背景覆蓋與光影。
## 修前修後用同一組格子重拍就能逐格對照（BG-20、BG-21、BG-27、BG-28、BG-30 共用）。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/scene_tour.tscn -- --out=<絕對資料夾> --level=<關卡檔名，逗號分隔> [--tag=<標籤>]
##     [--cells=<欄:列，逗號分隔；只拍指定格>] [--no-enemies] [--show-player] [--player] [--flat]
## --player：每一格把主角放在畫面中央下方最近的地面上（帶著他自己的光），看實際遊玩時的光影；沒有地面的格子不放。
##   同時量主角、畫面內敵人的輪廓對比與腳下地面亮邊（算法與門檻同 tools/contrast_probe.gd），寫進索引。
## --quality=low|medium|high：這次巡覽改用該光影品質（結束時還原）。
## --no-shadows：拿掉角色腳下的接觸陰影（量陰影成本時當對照）。索引會記錄每關的陰影數與每格實際花的時間
##   （關掉垂直同步後相鄰兩格的間隔，取中位數；引擎的處理時間監測值不是每格時間，不要用）。
## --flat 是盤點用的診斷畫面：環境光與背景調成全亮、關掉後製，只看擺放、支撐與圖層；不能拿來驗收光影。
## 輸出 <關卡>/<標籤>-c<欄>-r<列>.png 與 <關卡>/<標籤>-index.json（每格實際拍到的世界範圍）。
## 敵人與主角停在原地不動；主角預設隱藏。拼圖用 tools/scene_tour_sheet.py。

const Capture := preload("res://tools/viewport_capture.gd")
const SETTLE_FRAMES := 24
## 相鄰兩格重疊的比例，避免物件剛好被格線切開。
const OVERLAP := 0.08
## 量對比時取幾次樣（燈會閃爍、脈動，取中位數）。
const CONTRAST_SAMPLES := 5
const BENCH_FRAMES := 60
const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}

var _out := ""
var _levels: PackedStringArray = []
var _tag := "tour"
var _cells: Dictionary = {}
var _keep_enemies := true
var _show_player := false
var _flat := false
var _walk_player := false
var _quality := ""
var _no_shadows := false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--level="):
			_levels = argument.trim_prefix("--level=").split(",", false)
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--cells="):
			for cell: String in argument.trim_prefix("--cells=").split(",", false):
				_cells[cell] = true
		elif argument == "--no-enemies":
			_keep_enemies = false
		elif argument == "--show-player":
			_show_player = true
		elif argument == "--flat":
			_flat = true
		elif argument == "--player":
			_walk_player = true
		elif argument == "--no-shadows":
			_no_shadows = true
		elif argument.begins_with("--quality="):
			_quality = argument.trim_prefix("--quality=")
	if not _out.is_absolute_path() or _levels.is_empty() or DisplayServer.get_name() == "headless":
		push_error("[SceneTour] 需要原生視窗、--out=<絕對資料夾> 與 --level=<關卡檔名>")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var failures := 0
	var quality_before := Settings.get_light_quality()
	if QUALITY.has(_quality):
		Settings.set_light_quality(QUALITY[_quality])
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	# 主角被放到各處會觸發地圖上的通訊；通訊框不是場景的一部分，巡覽時不顯示。
	Story._layer.visible = false
	for level_id: String in _levels:
		if not await _tour(level_id):
			failures += 1
	if QUALITY.has(_quality):
		Settings.set_light_quality(quality_before)
	await AudioRelease.settle(get_tree())
	get_tree().quit(1 if failures > 0 else 0)


## 把停住的主角放到這一格中央往下最近的地面；整格沒有地面就藏起來。
## 主角停住是為了不觸發換區與劇情；他的補光與自己的光改由 _sync_player_light 在拍攝前更新成這一格的值。
func _place_player(level: Level, center: Vector2, view: Vector2) -> void:
	var layout := level._layout
	var column := clampi(int(center.x / layout.tile_size), 0, layout.width - 1)
	var from_row := maxi(0, int((center.y - view.y * 0.25) / layout.tile_size))
	var floor_y := layout.floor_below(column, from_row)
	var on_screen := floor_y != INF and floor_y > center.y - view.y * 0.5 + 60.0 and floor_y < center.y + view.y * 0.5
	level.player.visible = on_screen
	if on_screen:
		level.player.global_position = Vector2(column * layout.tile_size + layout.tile_size * 0.5, floor_y - 2.0)


## 這一格的可讀性：主角與畫面內每個敵人的輪廓對比、腳下地面亮邊、整格平均亮度；取 CONTRAST_SAMPLES 次的中位數。
func _measure(level: Level, world: Rect2) -> Dictionary:
	var player_values: Array[float] = []
	var edge_values: Array[float] = []
	var luma_values: Array[float] = []
	var enemy_values: Dictionary = {}
	var inner := world.grow(-24.0)
	for sample in CONTRAST_SAMPLES:
		await _settle(3)
		var probe := ContrastProbe.capture(get_viewport())
		luma_values.append(probe.mean_luma(world))
		if level.player.visible:
			player_values.append(probe.character_contrast(level.player.global_position, true))
			edge_values.append(probe.edge_contrast(level.player.global_position))
		for node: Node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Node2D
			if enemy == null or not enemy.is_visible_in_tree() or not inner.has_point(enemy.global_position):
				continue
			if not enemy_values.has(enemy.get_instance_id()):
				enemy_values[enemy.get_instance_id()] = []
			(enemy_values[enemy.get_instance_id()] as Array).append(probe.character_contrast(enemy.global_position))
	var result := {"mean_luma": _median(luma_values)}
	if not player_values.is_empty():
		result["player_contrast"] = _median(player_values)
		result["edge_contrast"] = _median(edge_values)
	var enemies: Array[float] = []
	for values: Array in enemy_values.values():
		var typed: Array[float] = []
		typed.assign(values)
		enemies.append(_median(typed))
	if not enemies.is_empty():
		result["enemy_contrast"] = enemies
	return result


## 這一格實際每影格花多久（毫秒）：暫時關掉垂直同步，量 BENCH_FRAMES 格的間隔取中位數。
func _frame_interval_ms() -> float:
	var vsync_before := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for _frame in 4:
		await get_tree().process_frame
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	for _frame in BENCH_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - last) / 1000.0)
		last = now
	DisplayServer.window_set_vsync_mode(vsync_before)
	return _median(samples)


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


## 停住的主角不會自己更新：把光影控制器算出的補光倍率、單盞光上限與自身光源亮度套上去。
func _sync_player_light(player: Player) -> void:
	var rig: CharacterRig = player._visual.rig
	rig._apply_fill(LightKit.character_fill)
	rig._apply_light_cap(LightKit.character_light_cap)
	player._light.energy = LightKit.player_light_energy


func _tour(level_id: String) -> bool:
	var path := "res://data/levels/%s.tres" % level_id
	var data := load(path) as LevelData if ResourceLoader.exists(path) else null
	if data == null:
		push_error("[SceneTour] 找不到關卡：%s" % path)
		return false
	var folder := _out.path_join(level_id)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_error("[SceneTour] 無法建立輸出資料夾：%s" % folder)
		return false
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _settle(SETTLE_FRAMES)
	level.hud.visible = false
	# 章節標題卡是進場演出，不是場景的一部分。
	for child: Node in level.get_children():
		if child is ChapterCard:
			child.queue_free()
	level.player.health.setup(999, 0.0)
	level.player.process_mode = Node.PROCESS_MODE_DISABLED
	level.player.visible = _show_player
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		if _keep_enemies:
			node.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			node.queue_free()
	# 角色停住時，腳下的陰影仍要依所在位置更新。
	var shadows := level.find_children("ContactShadow", "Node2D", true, false)
	for shadow: Node in shadows:
		if _no_shadows:
			shadow.free()
		else:
			shadow.process_mode = Node.PROCESS_MODE_ALWAYS
	# 閃電會讓某幾格突然變亮，修前修後就對不起來：巡覽期間不打雷。
	level._lighting._lightning_gap = 1.0e9
	var frame_ms: Array[float] = []
	if _flat:
		level._lighting.process_mode = Node.PROCESS_MODE_DISABLED
		level._lighting._modulate.color = Color.WHITE
		level._background.modulate = Color.WHITE
		level._post.visible = false
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera == null:
		push_error("[SceneTour] %s 沒有關卡鏡頭" % level_id)
		level.queue_free()
		return false
	# 鏡頭自己的跟隨（看向瞄準方向、前視、震動）會讓每次位置不同；停掉它，直接擺鏡頭，修前修後才能逐格對照。
	camera.set_physics_process(false)
	camera.offset = Vector2.ZERO
	camera.rotation = 0.0
	camera.zoom = Vector2.ONE * LevelCamera.ZOOM
	var size := level._layout.pixel_size()
	var view := get_viewport().get_visible_rect().size / camera.zoom
	var step := view * (1.0 - OVERLAP)
	var columns := maxi(1, ceili((size.x - view.x) / step.x) + 1)
	var rows := maxi(1, ceili((size.y - view.y) / step.y) + 1)
	var shots: Array[Dictionary] = []
	for row in rows:
		for column in columns:
			if not _cells.is_empty() and not _cells.has("%d:%d" % [column, row]):
				continue
			var center := Vector2(minf(view.x * 0.5 + step.x * column, maxf(view.x * 0.5, size.x - view.x * 0.5)),
				minf(view.y * 0.5 + step.y * row, maxf(view.y * 0.5, size.y - view.y * 0.5)))
			if _walk_player:
				_place_player(level, center, view)
			camera.global_position = center
			camera.reset_smoothing()
			camera.force_update_scroll()
			await _settle(SETTLE_FRAMES)
			if _walk_player and level.player.visible:
				_sync_player_light(level.player)
				await _settle(4)
			var to_world := (get_viewport().get_final_transform() * get_viewport().get_canvas_transform()).affine_inverse()
			var window := Vector2(get_viewport().get_window().size)
			var top_left := to_world * Vector2.ZERO
			var bottom_right := to_world * window
			var file := "%s-c%02d-r%02d.png" % [_tag, column, row]
			if Capture.image(get_viewport()).save_png(folder.path_join(file)) != OK:
				push_error("[SceneTour] 無法寫入：%s" % folder.path_join(file))
				level.queue_free()
				return false
			frame_ms.append(await _frame_interval_ms())
			var shot := {"file": file, "column": column, "row": row,
				"world": [top_left.x, top_left.y, bottom_right.x - top_left.x, bottom_right.y - top_left.y]}
			if _walk_player:
				shot.merge(await _measure(level, Rect2(top_left, bottom_right - top_left)))
			shots.append(shot)
	var index := {"level": level_id, "tag": _tag, "level_size": [size.x, size.y], "view": [view.x, view.y],
		"columns": columns, "rows": rows, "tile": level._layout.tile_size, "shots": shots,
		"contact_shadows": 0 if _no_shadows else shadows.size(),
		"frame_ms_median": _median(frame_ms)}
	var writer := FileAccess.open(folder.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[SceneTour] 無法寫入索引：%s" % folder)
		level.queue_free()
		return false
	writer.store_string(JSON.stringify(index, "\t"))
	writer.close()
	print("SCENE_TOUR:", level_id, " ", columns, "x", rows, " cells, ", shots.size(), " shots")
	level.queue_free()
	await _settle(4)
	return true
