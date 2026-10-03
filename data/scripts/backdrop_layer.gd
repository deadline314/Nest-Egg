class_name BackdropLayer
extends Resource
## 背景視差層：一張可左右平鋪的貼圖（寬 640 邏輯像素）。有同名 `_glow.png` 時疊上自發光窗光。

@export_file("*.png") var texture: String = ""
## 隨鏡頭移動的比例（0 = 固定在畫面，1 = 跟世界一起）。越遠越小。
@export_range(0.0, 1.0) var scroll_scale: float = 0.2
## 貼圖底邊的世界 y（邏輯像素）。
@export var bottom_y: float = 300.0
## 貼圖解析度倍率（背景用 2 倍）。
@export var texture_scale: int = 2
@export var tint: Color = Color.WHITE
@export var glow_intensity: float = 1.3


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if texture.is_empty() or not ResourceLoader.exists(texture):
		problems.append("背景層貼圖不存在：%s" % texture)
	return problems


func glow_path() -> String:
	return texture.get_basename() + "_glow." + texture.get_extension()
