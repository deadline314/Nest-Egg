class_name WeaponIconPainter
extends RefCounted
## 背包的武器圖示（64×24）：把 art/weapons/ 現有的高解析武器圖（含自發光層）自動像素化——
## 縮小、透明度二值化、限色、描邊。之後可用同名 PNG（art/items/weapons/<外觀 id>.png）覆蓋成手繪像素圖。

const SIZE := Vector2i(64, 24)
const OUTLINE := Color("07080d")
const COLOR_LEVELS := 5
## 提亮暗部，讓深色槍身在背包背景上看得清楚。
const GAMMA := 0.62


## 回傳武器外觀 id 對應的像素圖示；原圖讀取失敗回傳 null（並記錄錯誤）。
static func paint(visual_id: String) -> PixelCanvas:
	var def := RigLibrary.weapon(visual_id)
	if def.is_empty():
		return null
	var dir := RigLibrary.WEAPONS_PATH.get_base_dir()
	var base := _load_image(dir.path_join(str(def.get("file", ""))))
	if base == null:
		return null
	if def.has("glow"):
		var glow := _load_image(dir.path_join(str(def["glow"])))
		if glow != null:
			base = PixelCanvas.add_glow(base, glow)
	var canvas := PixelCanvas.from_image_fit(base, SIZE, 1, COLOR_LEVELS, GAMMA)
	canvas.outline(OUTLINE)
	return canvas


static func _load_image(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		push_error("[WeaponIconPainter] 無法讀取武器圖：%s" % path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image
