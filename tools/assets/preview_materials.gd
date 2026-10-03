extends Node2D
## 開發工具：把所有地形材質各畫成一塊（本體＋頂面＋左側邊）並打上點光源，看材質與法線在受光下的樣子（NE-57）。
## 用法：godot --path . res://tools/assets/preview_materials.tscn -- --out=<png 路徑> [--dir=res://data/environment/materials] [--ambient=0.3]
## 畫法與 Terrain 相同（同樣的貼圖區域與倍率），所以看到的就是遊戲裡的樣子，只是光線更好。

const BLOCK := Vector2(120, 72)
const GAP := 8.0
const COLUMNS := 4

var _out := "user://preview_materials.png"
var _dir := "res://data/environment/materials"
var _ambient := 0.42


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
		elif arg.begins_with("--ambient="):
			_ambient = float(arg.trim_prefix("--ambient="))
	_run.call_deferred()


func _run() -> void:
	var materials := ResourceCatalog.load_dir(_dir, TerrainMaterialData, "PreviewMaterials")
	var modulate_node := CanvasModulate.new()
	modulate_node.color = Color(_ambient, _ambient * 1.05, _ambient * 1.3)
	add_child(modulate_node)
	for i in materials.size():
		var material := materials[i] as TerrainMaterialData
		var origin := Vector2(GAP + (i % COLUMNS) * (BLOCK.x + GAP), GAP + (i / COLUMNS) * (BLOCK.y + GAP))
		var block := _Block.new()
		block.material_data = material
		block.position = origin
		block.size = BLOCK
		add_child(block)
		var warm := LightKit.create_point_light(Color(1.0, 0.82, 0.6), 110.0, 1.6, false, false)
		warm.position = origin + Vector2(34, 14)
		add_child(warm)
		var cyan := LightKit.create_point_light(Color(0.35, 0.85, 1.0), 90.0, 1.2, false, false)
		cyan.position = origin + Vector2(BLOCK.x - 14, BLOCK.y - 10)
		add_child(cyan)
	for i in 6:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	image.save_png(_out)
	print("saved %s (%d materials)" % [_out, materials.size()])
	get_tree().quit()


class _Block:
	extends Node2D

	var material_data: TerrainMaterialData
	var size := Vector2(120, 72)

	func _ready() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	func _draw() -> void:
		var k := float(material_data.texture_scale)
		var body := LitTextures.load_texture(material_data.body, Vector2i(64, 64))
		var top := LitTextures.load_texture(material_data.top, Vector2i(64, 24))
		var side := LitTextures.load_texture(material_data.side, Vector2i(24, 64))
		var rect := Rect2(Vector2.ZERO, size)
		draw_texture_rect_region(body, rect, Rect2(rect.position * k, rect.size * k))
		var top_h := material_data.top_height
		draw_texture_rect_region(top, Rect2(0, 0, size.x, top_h), Rect2(0, 0, size.x * k, top_h * k))
		var side_w := material_data.side_width
		draw_texture_rect_region(side, Rect2(0, 0, side_w, size.y), Rect2(0, 0, side_w * k, size.y * k))
		draw_string(ThemeDB.fallback_font, Vector2(8, size.y - 5), String(material_data.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.85))
