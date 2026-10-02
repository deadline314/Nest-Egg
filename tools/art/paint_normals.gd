extends Node
## 開發工具：為角色零件、武器與地形材質自動產生法線貼圖（<名稱>_n.png，與原圖同目錄），
## 並產生地形用的金屬面板貼圖。只用 CPU，可用 --headless 執行。
## 用法：godot --headless --path . res://tools/art/paint_normals.tscn [-- --only=rin,weapons,materials]
## 會覆蓋同名的 _n.png；已換成手繪法線貼圖的項目請用 --only 指定要重畫的範圍。

const CHARACTERS_DIR := "res://art/characters"
const WEAPONS_DIR := "res://art/weapons"
const MATERIALS_DIR := "res://art/materials"
const SKIP_SUFFIXES: Array[String] = ["_glow.png", "_n.png", "_guide.png"]
const PANEL_SIZE := 16

var _only: PackedStringArray = []
var _written := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
	_run.call_deferred()


func _run() -> void:
	for character in DirAccess.get_directories_at(CHARACTERS_DIR):
		if _only.is_empty() or _only.has(character):
			_process_dir(CHARACTERS_DIR.path_join(character).path_join("parts"))
	if _only.is_empty() or _only.has("weapons"):
		_process_dir(WEAPONS_DIR)
	if _only.is_empty() or _only.has("materials"):
		_make_metal_panel()
	print("paint_normals: wrote %d files" % _written)
	get_tree().quit()


func _process_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".png") or SKIP_SUFFIXES.any(func(suffix: String) -> bool: return file.ends_with(suffix)):
			continue
		var source := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(file)))
		if source == null:
			push_error("[paint_normals] 無法讀取：%s" % dir.path_join(file))
			continue
		_save(NormalMapMaker.make(source), dir.path_join(file.trim_suffix(".png") + "_n.png"))


## 16×16 的可平鋪金屬面板：深色鋼板、邊緣一圈淡淡的接縫、四角的鉚釘。
func _make_metal_panel() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MATERIALS_DIR))
	var base := Palette.TERRAIN_FILL
	var panel := Image.create(PANEL_SIZE, PANEL_SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for y in PANEL_SIZE:
		for x in PANEL_SIZE:
			var shade := rng.randf_range(-0.012, 0.012)
			var color := Color(base.r + shade, base.g + shade, base.b + shade, 1.0)
			if x == 0 or y == 0:
				color = color.lightened(0.07)
			elif x == PANEL_SIZE - 1 or y == PANEL_SIZE - 1:
				color = color.darkened(0.25)
			panel.set_pixel(x, y, color)
	for rivet in [Vector2i(3, 3), Vector2i(12, 3), Vector2i(3, 12), Vector2i(12, 12)]:
		panel.set_pixelv(rivet, base.lightened(0.22))
		panel.set_pixelv(rivet + Vector2i(1, 1), base.darkened(0.3))
	_save(panel, MATERIALS_DIR.path_join("metal_panel.png"))
	# 面板是不透明且要平鋪：邊緣高低靠亮度細節，不做透明度圓角。
	_save(NormalMapMaker.make(panel, 0, 0.0, 14.0), MATERIALS_DIR.path_join("metal_panel_n.png"))


func _save(image: Image, path: String) -> void:
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("寫入失敗 %s：%s" % [path, error_string(err)])
		return
	_written += 1
