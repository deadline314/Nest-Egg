extends Node2D
## 字型比較（NE-215）：同一組介面文字（對話框、HUD 提示、背包文字、數字與標題）用兩種字型在幾個字級下並排。
## 用法：godot --path . res://tools/font_compare.tscn -- --out=/絕對路徑.png --a=res://art/fonts/Cubic_11.ttf --b=res://art/fonts/NotoSansTC-Regular-subset.ttf [--sizes=11,13,14]

const SAMPLES: Array[String] = [
	"老 K：水位又上來了。鷺等一下來，有差事。",
	"{E} 上屋頂　信用點 1,240　醫療針 ×2　護盾電池 ×1",
	"復原館：欠著。下次來，記得帶傘。",
	"The quick brown fox 0123456789 — 水位 3.2 m",
]


func _ready() -> void:
	var out := ""
	var path_a := "res://art/fonts/Cubic_11.ttf"
	var path_b := ""
	var sizes: Array[int] = [11, 13, 14]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--a="):
			path_a = arg.trim_prefix("--a=")
		elif arg.begins_with("--b="):
			path_b = arg.trim_prefix("--b=")
		elif arg.begins_with("--sizes="):
			sizes.clear()
			for part in arg.trim_prefix("--sizes=").split(","):
				sizes.append(int(part))
	var bg := ColorRect.new()
	bg.color = Color("0b1220")
	bg.size = Vector2(640, 360)
	add_child(bg)
	var y := 4.0
	for path in [path_a, path_b]:
		if path.is_empty():
			continue
		var font := FontFile.new()
		font.data = FileAccess.get_file_as_bytes(path)
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE if path.contains("Cubic") else TextServer.FONT_ANTIALIASING_GRAY
		font.hinting = TextServer.HINTING_NONE if path.contains("Cubic") else TextServer.HINTING_LIGHT
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED if path.contains("Cubic") else TextServer.SUBPIXEL_POSITIONING_AUTO
		var title := Label.new()
		title.text = path.get_file()
		title.add_theme_font_override("font", font)
		title.add_theme_font_size_override("font_size", 11)
		title.add_theme_color_override("font_color", Color("ffcc33"))
		title.position = Vector2(4, y)
		add_child(title)
		y += 14.0
		for size in sizes:
			for sample in SAMPLES.slice(0, 2 if size != sizes[0] else 4):
				var label := Label.new()
				label.text = "%d  %s" % [size, sample]
				label.add_theme_font_override("font", font)
				label.add_theme_font_size_override("font_size", size)
				label.add_theme_color_override("font_color", Color("d8f4ff"))
				label.position = Vector2(4, y)
				add_child(label)
				y += float(size) + 4.0
		y += 6.0
	if not out.is_empty():
		_capture.call_deferred(out)


func _capture(out: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
