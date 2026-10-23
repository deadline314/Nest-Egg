extends Node2D
## 開發工具（NE-269）：臂盾零件外觀一覽。每一格是同一個格擋呈現（ShieldSurface）裝上不同零件的樣子，
## 上排是一般舉盾，下排是完美格擋窗口內（反應晶片的指示燈會亮）。只看呈現，不跑遊戲規則。
## 用法：godot --path . res://tools/arm_shield_gallery.tscn -- --out=/絕對路徑/檔名.png
## 畫布是專案的 640×360（視窗再放大兩倍）；八格排一列，每格 80×90。

const CELL := Vector2(80, 90)

var _out := ""
var _columns: Array[Dictionary] = []
var _presenters: Array[ShieldSurface] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	RenderingServer.set_default_clear_color(Color(0.07, 0.08, 0.1))
	var tuning := load("res://data/player/player_tuning.tres") as PlayerTuning
	var catalog := Progression.arm_shield_catalog()
	_columns.append({"label": "未裝零件", "parts": []})
	for part in catalog:
		_columns.append({"label": part.display_name, "parts": [part]})
	_columns.append({"label": "全部", "parts": catalog})
	for column in _columns:
		var stats := GuardStats.build(tuning, column["parts"])
		column["arc"] = stats.block_arc_degrees()
		for row in 2:
			var presenter := ShieldSurface.new()
			presenter.parts = stats.parts
			for tick in 30:
				presenter.update(1.0 / 60.0, true, false, Vector2.RIGHT, stats.block_arc_degrees())
			_presenters.append(presenter)
	queue_redraw()
	if not _out.is_empty():
		_capture.call_deferred()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for i in _columns.size():
		for row in 2:
			var presenter := _presenters[i * 2 + row]
			var origin := Vector2(CELL.x * i, CELL.y * row)
			var center := origin + Vector2(26, 48)
			draw_rect(Rect2(center + Vector2(-6, -14), Vector2(12, 28)), Color(0.25, 0.27, 0.32))  # 身體的位置
			presenter.paint(self, center, 1.0, row == 1, 0.8, 0.0, 0.0, 1.0, 1.0)
			if row == 0:
				draw_string(font, origin + Vector2(4, 10), str(_columns[i]["label"]), HORIZONTAL_ALIGNMENT_LEFT, CELL.x - 6, 8, Color.WHITE)
				draw_string(font, origin + Vector2(4, 86), "%d°" % roundi(float(_columns[i]["arc"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.8, 0.9))
			else:
				draw_string(font, origin + Vector2(4, 10), "完美窗口內", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.8, 0.9))


func _capture() -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	image.save_png(_out)
	print("saved ", _out)
	get_tree().quit()
