extends Node
## 開發工具：以程式繪製所有環境元件的暫代圖（4 倍解析度），輸出 PNG（含 _n 法線、_glow 自發光），
## 並產生對應的資料檔（.tres）。只用 CPU，可以 --headless 執行。
## 用法：godot --headless --path . res://tools/art/paint_environment.tscn [-- --only=materials,facades,props,backdrop]
## 會覆蓋同名檔案；已換成手繪的項目請用 --only 指定要重畫的範圍（資料檔只在不存在時才建立，不會覆蓋手改的數值）。
## 已換成免費素材的項目（列在 assets_src/pipeline/<類別>.json）一律略過，不會被暫代圖蓋掉。

const ART_DIR := "res://art/environment"
const DATA_DIR := "res://data/environment"

var _only: PackedStringArray = []
var _written := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
	_run.call_deferred()


func _run() -> void:
	if _wanted("materials"):
		_paint_materials()
	if _wanted("facades"):
		_paint_facades()
	if _wanted("props"):
		_paint_props()
	if _wanted("backdrop"):
		_paint_backdrop()
	print("paint_environment: wrote %d files" % _written)
	get_tree().quit()


func _wanted(group: String) -> bool:
	return _only.is_empty() or _only.has(group)


## 這個項目已由免費素材流程接手（見 design/11-free-assets）：重畫暫代圖會把它蓋掉，所以略過。
func _replaced(group: String, id: String) -> bool:
	var path := "res://assets_src/pipeline/%s.json" % group
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	for entry in parsed.get(group, []):
		if str(entry.get("id", "")) == id:
			return true
	return false


# ---------------------------------------------------------------------------
# 地形材質
# ---------------------------------------------------------------------------

func _paint_materials() -> void:
	for spec in MaterialPainter.CATALOG:
		var id := str(spec["id"])
		if _replaced("materials", id):
			continue
		var images := MaterialPainter.paint(spec)
		var paths := {}
		for part: String in ["body", "top", "side"]:
			var canvas: EnvCanvas = images[part]
			var path := "%s/materials/%s_%s.png" % [ART_DIR, id, part]
			_save_png(canvas.image, path)
			# 平鋪材質沒有透明邊：法線完全靠亮度細節。
			_save_png(NormalMapMaker.make(canvas.image, 0, 0.0, 9.0), path.get_basename() + "_n.png")
			paths[part] = path
		var data := TerrainMaterialData.new()
		data.id = StringName(id)
		data.display_name = str(spec["name"])
		data.body = paths["body"]
		data.top = paths["top"]
		data.side = paths["side"]
		if spec.has("edge"):
			var edge: PackedStringArray = str(spec["edge"]).split(",")
			data.edge_color = Color(Color.html(edge[0]), float(edge[1]))
		_save_resource_once(data, "%s/materials/%s.tres" % [DATA_DIR, id])


# ---------------------------------------------------------------------------
# 建築立面
# ---------------------------------------------------------------------------

func _paint_facades() -> void:
	for spec in FacadePainter.CATALOG:
		var id := str(spec["id"])
		if _replaced("facades", id):
			continue
		var modules := FacadePainter.paint(spec)
		var data := FacadeData.new()
		data.id = StringName(id)
		data.display_name = str(spec["name"])
		for group: String in ["ground", "body", "cap"]:
			var list: Array = modules[group]
			var paths := PackedStringArray()
			for i in list.size():
				var pair: Array = list[i]
				var path := "%s/facades/%s_%s%d.png" % [ART_DIR, id, group.left(1) if group != "cap" else "cap", i]
				var diffuse: EnvCanvas = pair[0]
				var glow: EnvCanvas = pair[1]
				_save_png(diffuse.image, path)
				_save_png(NormalMapMaker.make(diffuse.image, 0, 0.0, 7.0), path.get_basename() + "_n.png")
				_save_png(glow.image, FacadeData.glow_path(path))
				paths.append(path)
			match group:
				"ground":
					data.ground = paths
				"body":
					data.body = paths
				_:
					data.cap = paths
		_save_resource_once(data, "%s/facades/%s.tres" % [DATA_DIR, id])


# ---------------------------------------------------------------------------
# 道具
# ---------------------------------------------------------------------------

func _paint_props() -> void:
	for spec in PropPainter.CATALOG:
		var id := str(spec["id"])
		if _replaced("props", id):
			continue
		var images := PropPainter.paint(spec)
		var path := "%s/props/%s.png" % [ART_DIR, id]
		var diffuse: EnvCanvas = images["diffuse"]
		_save_png(diffuse.image, path)
		_save_png(NormalMapMaker.make(diffuse.image, 3, 4.0, 1.5), path.get_basename() + "_n.png")
		var glow: EnvCanvas = images["glow"]
		if glow != null:
			_save_png(glow.image, path.get_basename() + "_glow.png")
		var size: Array = spec["size"]
		var data := PropData.new()
		data.id = StringName(id)
		data.display_name = str(spec["name"])
		data.texture = path
		data.size = Vector2(float(size[0]), float(size[1]))
		data.category = StringName(str(spec["cat"]))
		data.layer = PropData.Layer.FRONT if str(spec.get("layer", "back")) == "front" else PropData.Layer.BACK
		data.has_glow = glow != null
		data.flicker = float(spec.get("flicker", 0.0))
		data.casts_shadow = bool(spec.get("shadow", false))
		if spec.has("light"):
			var light: Array = spec["light"]
			var rgb: Array = light[0]
			data.light_color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
			data.light_radius = float(light[1])
			data.light_energy = float(light[2])
			data.light_offset = Vector2(float(light[3][0]), float(light[3][1]))
		if spec.has("platform"):
			var p: Array = spec["platform"]
			data.platform = Rect2(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
		_save_resource_once(data, "%s/props/%s.tres" % [DATA_DIR, id])


# ---------------------------------------------------------------------------
# 背景層
# ---------------------------------------------------------------------------

func _paint_backdrop() -> void:
	for spec in BackdropPainter.CATALOG:
		var id := str(spec["id"])
		if _replaced("backdrop", id):
			continue
		var images := BackdropPainter.paint(spec)
		var path := "%s/backdrop/%s.png" % [ART_DIR, id]
		var diffuse: EnvCanvas = images["diffuse"]
		var glow: EnvCanvas = images["glow"]
		_save_png(diffuse.image, path)
		_save_png(glow.image, path.get_basename() + "_glow.png")


# ---------------------------------------------------------------------------

func _save_png(image: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("寫入失敗 %s：%s" % [path, error_string(err)])
		return
	_written += 1


## 資料檔只在不存在時建立：手改過的數值不會被重畫覆蓋。
func _save_resource_once(resource: Resource, path: String) -> void:
	if ResourceLoader.exists(path):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("儲存資料失敗 %s：%s" % [path, error_string(err)])
		return
	_written += 1
