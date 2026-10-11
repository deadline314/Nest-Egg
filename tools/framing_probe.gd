extends Node
## 開發工具（NE-256）：在真實關卡量關卡鏡頭的構圖——主角站立時頭頂到腳底佔畫面高度的比例，以及面向前方、背後看得到幾個世界像素。
## 用法（需要可渲染的環境）：
##   godot --path . [--resolution 1920x1080] res://tools/framing_probe.tscn -- [--out=<資料夾>] [--level=ch1_pawnshop] [--zoom=1.5] [--profile=level_wide] [--hud] [--motion]
## 量法：同一格先拍主角在畫面上、再拍主角藏起來，兩張相減後取主角腳下那幾欄有變化的最高、最低列＝主角的像素高度。
##   前方與背後的可見距離用鏡頭實際的畫布轉換換算，主角朝右瞄準、鏡頭停穩之後量（前瞻與瞄準偏移都到位）。
## 主角佔比不在 31%～35%、前方不足 300 世界像素時以非零代碼結束。--zoom 只覆寫倍率；--profile 換一整組鏡頭設定（level_wide＝修前）。
## --motion：改量動態——用真的按鍵跑、跳、轉向、上下瞄準，記錄主角離畫面四邊最近的距離與鏡頭橫移的最大速度（設計畫布像素）。

const MIN_RATIO := 0.31
const MAX_RATIO := 0.35
const MIN_FRONT := 300.0
## 量主角高度時只看主角腳下這幾個世界像素寬的直條（避開槍燈照到的地面與身旁的道具）。
const COLUMN_HALF_WIDTH := 10.0
## 像素在兩張截圖間的亮度差超過這個值才算「主角的像素」。
const DIFF_THRESHOLD := 0.04
## 取樣點 [關卡, 欄, 地面列]：和第一章可讀性檢查同一批平地（室內、戶外、屋頂、倉庫）。
const SPOTS := [
	["ch1_pawnshop", 55, 20], ["ch1_street", 60, 20], ["ch1_rooftop", 42, 18], ["ch1_warehouse", 54, 17],
	["ch1_lounge", 25, 20], ["ch1_stall", 25, 20],
]

var _out_dir := ""
var _zoom_override := 0.0
var _only := ""
var _failed := false
## --hud：保留 HUD 並另存一張不加標記的截圖（看 HUD 與提示有沒有被主角擋住）。
var _keep_hud := false
var _profile := &""
var _motion := false
## --cutscene=場景id：在第一個取樣關卡裡播這段過場，播到 --at 秒時截圖（比較不同鏡頭設定下過場構圖是否相同）。
var _cutscene := &""
var _cutscene_at := 3.0
## 動態量測：主角離畫面邊緣至少要留的設計畫布像素；鏡頭橫移不超過這個速度（設計畫布像素／秒，拉近前實測最快 604）。
const MIN_EDGE_MARGIN := 24.0
const MAX_PAN_SPEED := 620.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--zoom="):
			_zoom_override = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--profile="):
			_profile = StringName(arg.trim_prefix("--profile="))
		elif arg.begins_with("--cutscene="):
			_cutscene = StringName(arg.trim_prefix("--cutscene="))
		elif arg.begins_with("--at="):
			_cutscene_at = float(arg.trim_prefix("--at="))
		elif arg == "--motion":
			_motion = true
		elif arg == "--hud":
			_keep_hud = true
		elif arg.begins_with("--level="):
			_only = arg.trim_prefix("--level=")
	if not _out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var size := get_viewport().get_visible_rect().size
	print("[framing_probe] 視窗 %s，設計畫布 %s" % [DisplayServer.window_get_size(), size])
	if _cutscene != &"":
		await _capture_cutscene(str(SPOTS[0][0]) if _only.is_empty() else _only)
		get_tree().quit(1 if _failed else 0)
		return
	print("%-18s %-6s %-8s %-8s %-8s %-8s" % ["關卡/欄", "倍率", "主角高", "佔比", "前方", "背後"])
	for spot: Array in SPOTS:
		if _only.is_empty() or _only == str(spot[0]):
			await _measure(str(spot[0]), int(spot[1]), int(spot[2]))
	get_tree().quit(1 if _failed else 0)


func _measure(level_id: String, column: int, row: int) -> void:
	var path := "res://data/levels/%s.tres" % level_id
	if not ResourceLoader.exists(path):
		printerr("[framing_probe] 找不到關卡 %s" % path)
		_failed = true
		return
	GameState.start_new_run(GameState.difficulties[1])
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var data := (load(path) as LevelData).duplicate()
	data.intro_scene = &""
	data.show_chapter_card = false
	var level := Level.new()
	level.configure(data)
	add_child(level)
	level._arena_triggered = true
	for i in 20:
		await get_tree().process_frame
	level.hud.visible = _keep_hud
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for node in level.find_children("*", "", true, false):
		if node is WorldPrompt:
			node.visible = false
	var layout: LevelLayout = level._layout
	var player := level.player
	player.health.setup(999, 0.0)
	if not layout.cell(column, row) in ["#", "="]:
		printerr("[framing_probe] %s 第 %d 欄第 %d 列不是地面" % [level_id, column, row])
		_failed = true
	player.global_position = Vector2(column * layout.tile_size + 8.0, float(row) * layout.tile_size - 2.0)
	player.velocity = Vector2.ZERO
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera != null and _profile != &"":
		camera.tuning = CameraTuning.profile(_profile)
		camera.snap_to_target()
	if camera != null and _zoom_override > 0.0:
		camera.tuning = camera.tuning.with_zoom(_zoom_override)
	if _motion:
		for i in 30:
			await get_tree().process_frame
		if camera != null:
			camera.snap_to_target()
		await get_tree().create_timer(1.0).timeout
		await _measure_motion(level, level_id, column)
		return
	for i in 30:
		await get_tree().process_frame
	# 朝右瞄準、鏡頭停穩：前瞻與瞄準偏移收斂到最終位置。
	Input.warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.95, 0.5) * get_viewport().get_final_transform().get_scale())
	if camera != null:
		camera.snap_to_target()
	# 主角身上的燈（槍燈、輪廓光）與遮光體會改變周圍的亮度；兩張都關掉，相減後才只剩主角本身的像素。
	for node in player.find_children("*", "", true, false):
		if node is Light2D:
			(node as Light2D).enabled = false
		elif node is LightOccluder2D:
			(node as LightOccluder2D).visible = false
	await get_tree().create_timer(2.5).timeout
	# 量三次取中位數：偶爾有沒被暫停的特效剛好飄過主角的直條。
	var samples: Array[Dictionary] = []
	for i in 3:
		samples.append(await _capture_height(level, player))
	samples.sort_custom(func(l: Dictionary, r: Dictionary) -> bool: return int(l["bottom"]) - int(l["top"]) < int(r["bottom"]) - int(r["top"]))
	var sample: Dictionary = samples[1]
	var shown: Image = sample["shown"]
	var top: int = sample["top"]
	var bottom: int = sample["bottom"]
	var x0: int = sample["x0"]
	var x1: int = sample["x1"]
	var feet := player.global_position
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	var view := Rect2(inverse * Vector2.ZERO, inverse.basis_xform(get_viewport().get_visible_rect().size)).abs()
	var front := view.end.x - feet.x if player.facing > 0 else feet.x - view.position.x
	var back := feet.x - view.position.x if player.facing > 0 else view.end.x - feet.x
	var px_height := bottom - top + 1 if top >= 0 else 0
	var ratio := float(px_height) / float(shown.get_height())
	var zoom := camera.zoom.x if camera != null else 1.0
	var ok := ratio >= MIN_RATIO and ratio <= MAX_RATIO and front >= MIN_FRONT
	_failed = _failed or not ok
	print("%-18s %-6.2f %-8d %-8s %-8.0f %-8.0f %s" % ["%s/%d" % [level_id, column], zoom, px_height,
			"%.1f%%" % (ratio * 100.0), front, back, "OK" if ok else "不合格（佔比 %d%%～%d%%、前方 ≥ %d）" % [MIN_RATIO * 100, MAX_RATIO * 100, MIN_FRONT]])
	if not _out_dir.is_empty() and _keep_hud:
		shown.save_png(_out_dir.path_join("framing-hud-%s-%d.png" % [level_id, column]))
	if not _out_dir.is_empty() and top >= 0:
		var marked := shown.duplicate() as Image
		for x in range(maxi(0, x0 - 40), mini(marked.get_width(), x1 + 40)):
			marked.set_pixel(x, top, Color.MAGENTA)
			marked.set_pixel(x, bottom, Color.MAGENTA)
		var file := _out_dir.path_join("framing-%s-%d-%dx%d.png" % [level_id, column, shown.get_width(), shown.get_height()])
		if marked.save_png(file) != OK:
			printerr("[framing_probe] 無法存檔 %s" % file)
	remove_child(level)
	level.free()
	await get_tree().process_frame


## 從 start 往 step 方向找最遠一列有變化的像素，中間最多容許 gap 列沒有變化。
func _extend(changed: PackedByteArray, start: int, step: int, gap: int) -> int:
	var last := start
	var y := start
	while y >= 0 and y < changed.size() and y - last <= gap * absi(step) and last - y <= gap:
		if changed[y] == 1:
			last = y
		y += step
	return last


## 跑右、起跳、停、轉身跑左、停、上下瞄準：每個物理影格記主角離畫面四邊的距離與鏡頭的橫移速度。
func _measure_motion(level: Level, level_id: String, column: int) -> void:
	var player := level.player
	# 每一步同時按住的鍵與秒數；瞄準方向跟著跑的方向（手把的右搖桿），主角面向跑的方向。
	var steps := [
		[[&"move_right", &"aim_right"], 1.4], [[&"move_right", &"aim_right", &"jump"], 0.25], [[&"move_right", &"aim_right"], 1.0],
		[[&"aim_right"], 0.6], [[&"move_left", &"aim_left"], 1.8], [[&"aim_left"], 0.8], [[&"aim_up"], 0.7], [[&"aim_down"], 0.7], [[], 0.6],
	]
	# 出入口會把主角送到別的關卡，量測時關掉；鏡頭被地圖邊界夾住的影格，主角本來就可以走到畫面邊緣，不算。
	for node in level.find_children("*", "Portal", true, false):
		node.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := get_viewport().get_camera_2d()
	var min_margin := {"左": INF, "右": INF, "上": INF, "下": INF}
	var max_rise := 0.0
	var fastest_step := ""
	var start_y := player.global_position.y
	var last_feet := player.global_position
	var max_speed := 0.0
	var last_origin := Vector2.INF
	for step: Array in steps:
		var actions: Array = step[0]
		for action: StringName in actions:
			Input.action_press(action)
		# 預設是滑鼠瞄準：把游標移到瞄準方向的畫面邊緣（手把的瞄準鍵另外按住）。
		var window := Vector2(DisplayServer.window_get_size())
		var aim_at := {&"aim_right": Vector2(0.97, 0.55), &"aim_left": Vector2(0.03, 0.55), &"aim_up": Vector2(0.5, 0.02), &"aim_down": Vector2(0.5, 0.98)}
		for action: StringName in actions:
			if aim_at.has(action):
				Input.warp_mouse(window * (aim_at[action] as Vector2))
		var left := float(step[1])
		while left > 0.0:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			left -= dt
			var to_design := get_viewport().get_canvas_transform()
			var size := get_viewport().get_visible_rect().size
			var feet := to_design * player.global_position
			var head := to_design * (player.global_position - Vector2(0.0, 60.0))
			var view := Rect2(to_design.affine_inverse() * Vector2.ZERO, to_design.affine_inverse().basis_xform(size)).abs()
			var clamped_x := view.position.x <= camera.limit_left + 2 or view.end.x >= camera.limit_right - 2
			var clamped_y := view.position.y <= camera.limit_top + 2 or view.end.y >= camera.limit_bottom - 2
			if not clamped_x:
				min_margin["左"] = minf(min_margin["左"], feet.x)
				min_margin["右"] = minf(min_margin["右"], size.x - feet.x)
			if not clamped_y:
				min_margin["上"] = minf(min_margin["上"], head.y)
				min_margin["下"] = minf(min_margin["下"], size.y - feet.y)
			var origin := to_design.origin
			var teleported := player.global_position.distance_to(last_feet) > 24.0
			last_feet = player.global_position
			max_rise = maxf(max_rise, start_y - player.global_position.y)
			if last_origin != Vector2.INF and dt > 0.0 and not teleported:
				var speed := absf(origin.x - last_origin.x) / dt
				if OS.get_cmdline_user_args().has("--trace") and speed > 500.0:
					var cam := camera as LevelCamera
					print("    %.0f px/s  主角 x %.1f vx %.0f  look %.1f aim %.1f  鏡頭 %.1f 中心 %.1f" % [speed, player.global_position.x, player.velocity.x, cam._look, cam._aim_look.x, cam.global_position.x, cam.get_screen_center_position().x])
				if speed > max_speed:
					max_speed = speed
					fastest_step = str(actions)
			last_origin = origin
		if OS.get_cmdline_user_args().has("--trace"):
			var screen := get_viewport().get_canvas_transform() * player.global_position
			print("  %s 之後：主角 %s 畫面 %s 鏡頭 %s" % [actions, player.global_position.round(), screen.round(), camera.get_screen_center_position().round()])
		for action: StringName in actions:
			Input.action_release(action)
	var tightest := minf(minf(min_margin["左"], min_margin["右"]), minf(min_margin["上"], min_margin["下"]))
	var ok := tightest >= MIN_EDGE_MARGIN and max_speed <= MAX_PAN_SPEED
	_failed = _failed or not ok
	print("%-18s 倍率 %.2f  離邊最近：左 %.0f 右 %.0f 上 %.0f 下 %.0f  鏡頭橫移最快 %.0f 像素／秒（%s）  跳起最高 %.0f  %s" % ["%s/%d" % [level_id, column],
			camera.zoom.x, min_margin["左"], min_margin["右"], min_margin["上"], min_margin["下"], max_speed, fastest_step, max_rise,
			"OK" if ok else "不合格（離邊 ≥ %d、橫移 ≤ %d）" % [MIN_EDGE_MARGIN, MAX_PAN_SPEED]])
	remove_child(level)
	level.free()
	await get_tree().process_frame


## 拍一組「有主角／沒有主角」的截圖，回傳主角在畫面上的頭頂與腳底列（沒量到時是 -1）。
func _capture_height(level: Level, player: Player) -> Dictionary:
	# 暫停：灰塵與閃爍的燈停在同一格；雨是著色器的時間在動，暫停不了，量的時候先藏起來。兩張截圖只差主角。
	get_tree().paused = true
	var rain := level.find_children("*", "RainLayer", true, false)
	for node: Node2D in rain:
		node.visible = false
	# 沒主角 → 有主角 → 沒主角：只算和前後兩張都不同、而前後兩張彼此相同的像素（背景自己在閃的不算）。
	player.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var before := preload("res://tools/viewport_capture.gd").image(get_viewport())
	player.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var shown := preload("res://tools/viewport_capture.gd").image(get_viewport())
	var to_screen := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	player.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var hidden := preload("res://tools/viewport_capture.gd").image(get_viewport())
	player.visible = true
	for node: Node2D in rain:
		node.visible = true
	get_tree().paused = false
	var feet := player.global_position
	var x0 := int((to_screen * (feet - Vector2(COLUMN_HALF_WIDTH, 0.0))).x)
	var x1 := int((to_screen * (feet + Vector2(COLUMN_HALF_WIDTH, 0.0))).x)
	# 每一列在主角腳下的直條裡有沒有變化；從腰部那一列往上、往下延伸，容許幾列的空隙（脖子、腳踝），
	# 這樣飄過的灰塵、雨滴等與主角不相連的變化不會算進去。
	var changed := PackedByteArray()
	changed.resize(shown.get_height())
	for y in shown.get_height():
		for x in range(maxi(0, x0), mini(shown.get_width(), x1 + 1)):
			var a := shown.get_pixel(x, y)
			var b := hidden.get_pixel(x, y)
			var c := before.get_pixel(x, y)
			if _differs(a, b) and _differs(a, c) and not _differs(b, c):
				changed[y] = 1
				break
	var seed := clampi(int((to_screen * (feet - Vector2(0.0, 24.0))).y), 0, shown.get_height() - 1)
	var gap := int(ceil(to_screen.get_scale().y * 3.0))
	var top := -1
	var bottom := -1
	if changed[seed] == 1:
		top = _extend(changed, seed, -1, gap)
		# 背景燈會把主角的影子投到身後的牆上，和頭頂連在一起；頭頂不能高過骨架的實際外框（容許 4 世界像素）。
		if is_instance_valid(player._visual) and is_instance_valid(player._visual.rig):
			var bounds: Rect2 = player._visual.rig.visual_bounds()
			if bounds.has_area():
				top = maxi(top, int((to_screen * Vector2(feet.x, bounds.position.y - 4.0)).y))
		# 腳底以下是地面的影子與反光，不算身高。
		bottom = mini(_extend(changed, seed, 1, gap), int((to_screen * (feet + Vector2(0.0, 2.0))).y))
	return {"top": top, "bottom": bottom, "shown": shown, "x0": x0, "x1": x1}


func _differs(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > DIFF_THRESHOLD * 3.0


## 在真實關卡上播一段過場（關卡與它的鏡頭留在底下，和玩家看到的一樣），播到 _cutscene_at 秒時截圖。
func _capture_cutscene(level_id: String) -> void:
	var path := "res://data/levels/%s.tres" % level_id
	if not ResourceLoader.exists(path) or not Story.has_scene(_cutscene):
		printerr("[framing_probe] 找不到關卡 %s 或過場 %s" % [path, _cutscene])
		_failed = true
		return
	GameState.start_new_run(GameState.difficulties[1])
	var data := (load(path) as LevelData).duplicate()
	data.intro_scene = &""
	data.show_chapter_card = false
	var level := Level.new()
	level.configure(data)
	add_child(level)
	for i in 30:
		await get_tree().process_frame
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera != null and _profile != &"":
		camera.tuning = CameraTuning.profile(_profile)
		camera.snap_to_target()
	await get_tree().create_timer(1.0).timeout
	Story.play(_cutscene)
	await get_tree().create_timer(_cutscene_at).timeout
	var shot := preload("res://tools/viewport_capture.gd").image(get_viewport())
	var file := _out_dir.path_join("cutscene-%s-%s.png" % [_cutscene, _profile if _profile != &"" else &"level"])
	if _out_dir.is_empty() or shot.save_png(file) != OK:
		printerr("[framing_probe] 無法存過場截圖 %s" % file)
		_failed = true
	else:
		print("[framing_probe] 過場截圖 %s（鏡頭倍率 %.2f）" % [file, camera.zoom.x if camera != null else 0.0])
