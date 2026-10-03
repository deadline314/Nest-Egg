extends Node2D
## 開發工具：把道具排成一列、用同一組側光照亮，看法線貼圖的立體感（BG-8）。
## 用法：godot --path . res://tools/assets/preview_prop_lighting.tscn -- --ids=barrels,water_tower --out=<png 路徑> [--normals=<資料夾>] [--zoom=3]
## 預設用專案裡目前的法線；--normals 指到另一個資料夾時，改用該資料夾裡的 <id>_n.png（例如事先備份的舊版法線），
## 兩次輸出就能並排比較。每個道具左上一盞暖光、右下一盞冷光，畫法與遊戲相同（LightKit 的點光源與 CanvasTexture 法線）。

const CELL_PAD := 16.0
const ROW_H := 200.0

var _ids: PackedStringArray = []
var _normals_dir := ""
var _out := "user://preview_prop_lighting.png"
var _zoom := 3.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="):
			_ids = arg.trim_prefix("--ids=").split(",", false)
		elif arg.begins_with("--normals="):
			_normals_dir = arg.trim_prefix("--normals=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
	_run.call_deferred()


func _run() -> void:
	var modulate_node := CanvasModulate.new()
	modulate_node.color = Color(0.22, 0.24, 0.32)
	add_child(modulate_node)
	var x := CELL_PAD
	var count := 0
	for id in _ids:
		var data := load("res://data/environment/props/%s.tres" % id) as PropData
		if data == null:
			push_error("[PreviewPropLighting] 找不到道具資料：%s" % id)
			continue
		var size := data.size * _zoom
		var origin := Vector2(x, ROW_H - 8.0 - size.y)
		var sprite := Sprite2D.new()
		var canvas := CanvasTexture.new()
		canvas.diffuse_texture = load(data.texture) as Texture2D
		if _normals_dir != "":
			var image := Image.load_from_file("%s/%s_n.png" % [_normals_dir, id])
			canvas.normal_texture = ImageTexture.create_from_image(image) if image != null else null
		else:
			canvas.normal_texture = load(data.texture.get_basename() + "_n.png") as Texture2D
		sprite.texture = canvas
		sprite.centered = false
		sprite.position = origin
		sprite.scale = size / Vector2(canvas.diffuse_texture.get_size())
		add_child(sprite)
		var warm := LightKit.create_point_light(Color(1.0, 0.82, 0.6), maxf(60.0, size.x * 0.9 + 40.0), 1.7, false, false)
		warm.position = origin + Vector2(-10.0, size.y * 0.15)
		add_child(warm)
		var cyan := LightKit.create_point_light(Color(0.4, 0.85, 1.0), maxf(50.0, size.x * 0.8 + 30.0), 1.1, false, false)
		cyan.position = origin + Vector2(size.x + 10.0, size.y * 0.8)
		add_child(cyan)
		x += size.x + CELL_PAD
		count += 1
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED  # 不套專案的 640x360 縮放，畫面大小就是視窗大小
	get_window().size = Vector2i(int(x), int(ROW_H))
	for i in 8:
		await get_tree().process_frame
	var shot := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	shot.save_png(_out)
	print("saved %s (%d props, normals: %s)" % [_out, count, _normals_dir if _normals_dir != "" else "project"])
	get_tree().quit()
