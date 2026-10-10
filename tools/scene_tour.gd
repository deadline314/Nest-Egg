extends Node
## 場景巡覽：把關卡依固定格子從左到右、從上到下拍成原生畫面，逐區檢查佈景、背景覆蓋與光影。
## 修前修後用同一組格子重拍就能逐格對照（BG-20、BG-21、BG-27、BG-28、BG-30 共用）。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/scene_tour.tscn -- --out=<絕對資料夾> --level=<關卡檔名，逗號分隔> [--tag=<標籤>]
##     [--cells=<欄:列，逗號分隔；只拍指定格>] [--no-enemies] [--show-player] [--flat]
## --flat 是盤點用的診斷畫面：環境光與背景調成全亮、關掉後製，只看擺放、支撐與圖層；不能拿來驗收光影。
## 輸出 <關卡>/<標籤>-c<欄>-r<列>.png 與 <關卡>/<標籤>-index.json（每格實際拍到的世界範圍）。
## 敵人與主角停在原地不動；主角預設隱藏。拼圖用 tools/scene_tour_sheet.py。

const Capture := preload("res://tools/viewport_capture.gd")
const SETTLE_FRAMES := 24
## 相鄰兩格重疊的比例，避免物件剛好被格線切開。
const OVERLAP := 0.08

var _out := ""
var _levels: PackedStringArray = []
var _tag := "tour"
var _cells: Dictionary = {}
var _keep_enemies := true
var _show_player := false
var _flat := false


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
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	for level_id: String in _levels:
		if not await _tour(level_id):
			failures += 1
	await AudioRelease.settle(get_tree())
	get_tree().quit(1 if failures > 0 else 0)


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
			camera.global_position = center
			camera.reset_smoothing()
			camera.force_update_scroll()
			await _settle(SETTLE_FRAMES)
			var to_world := (get_viewport().get_final_transform() * get_viewport().get_canvas_transform()).affine_inverse()
			var window := Vector2(get_viewport().get_window().size)
			var top_left := to_world * Vector2.ZERO
			var bottom_right := to_world * window
			var file := "%s-c%02d-r%02d.png" % [_tag, column, row]
			if Capture.image(get_viewport()).save_png(folder.path_join(file)) != OK:
				push_error("[SceneTour] 無法寫入：%s" % folder.path_join(file))
				level.queue_free()
				return false
			shots.append({"file": file, "column": column, "row": row,
				"world": [top_left.x, top_left.y, bottom_right.x - top_left.x, bottom_right.y - top_left.y]})
	var index := {"level": level_id, "tag": _tag, "level_size": [size.x, size.y], "view": [view.x, view.y],
		"columns": columns, "rows": rows, "tile": level._layout.tile_size, "shots": shots}
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
