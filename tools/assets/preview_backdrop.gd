extends Node2D
## 開發工具：只畫背景（天空與視差層），看新背景在環境光下的樣子（NE-57）。
## 用法：godot --path . res://tools/assets/preview_backdrop.tscn -- --out=<png 路徑> [--theme=res://data/environment/themes/chapter1.tres] [--ambient=0.45] [--x=0,640,1280]
## 每個 --x 拍一張（鏡頭 x 座標），檔名加上 _<x>。背景的環境光與 Level 相同是 CanvasModulate；背景色調同光影區段（這裡用屋頂的 0.9/0.95/1.0）。

var _out := "user://preview_backdrop.png"
var _theme := "res://data/environment/themes/chapter1.tres"
var _ambient := Color(0.36, 0.42, 0.55)
var _xs: PackedFloat32Array = [0.0, 700.0]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--theme="):
			_theme = arg.trim_prefix("--theme=")
		elif arg.begins_with("--ambient="):
			var v := float(arg.trim_prefix("--ambient="))
			_ambient = Color(v, v * 1.1, v * 1.4)
		elif arg.begins_with("--x="):
			_xs = PackedFloat32Array()
			for part in arg.trim_prefix("--x=").split(","):
				_xs.append(float(part))
	_run.call_deferred()


func _run() -> void:
	var theme := load(_theme) as EnvironmentTheme
	if theme == null:
		push_error("[preview_backdrop] 讀不到主題：%s" % _theme)
		get_tree().quit(1)
		return
	var modulate_node := CanvasModulate.new()
	modulate_node.color = _ambient
	add_child(modulate_node)
	var background := LevelBackground.new()
	background.backdrop = theme.backdrop
	background.sky = theme.sky
	background.modulate = Color(0.9, 0.95, 1.0)
	add_child(background)
	var camera := Camera2D.new()
	camera.position = Vector2(320, 250)
	add_child(camera)
	camera.make_current()
	for i in 4:
		await get_tree().process_frame
	for x in _xs:
		camera.position = Vector2(320.0 + x, 250.0)
		for i in 6:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		var path := _out.get_basename() + "_%d." % int(x) + _out.get_extension()
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		image.save_png(path)
		print("saved ", path)
	get_tree().quit()
