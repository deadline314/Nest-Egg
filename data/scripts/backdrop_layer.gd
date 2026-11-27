class_name BackdropLayer
extends Resource
## 背景視差層：一張可左右平鋪的貼圖（寬 640 邏輯像素）。有同名 `_glow.png` 時疊上自發光窗光。

@export_file("*.png", "*.webp") var texture: String = ""
## 隨鏡頭移動的比例（0 = 固定在畫面，1 = 跟世界一起）。越遠越小。
@export_range(0.0, 1.0) var scroll_scale: float = 0.2
## 貼圖底邊的世界 y（邏輯像素）。
@export var bottom_y: float = 300.0
## 貼圖解析度倍率（背景用 2 倍）。
@export var texture_scale: int = 2
## Original file width, recorded by the import policy. Keeps world geometry after downsizing.
@export var source_width: int = 0
@export var tint: Color = Color.WHITE
@export var glow_intensity: float = 1.3
## 這一層自己的橫向漂移（邏輯像素／秒，負值往左；0 = 不動）。雲、霧帶、遠處交通用；貼圖左右無縫才看不出接縫（BG-65）。
@export_range(-40.0, 40.0, 0.1) var drift: float = 0.0
## 疊在這一層前面的霧色濃度（0 = 沒有，最大 1）；-1 = 依遠近自動（越遠越濃），做出大氣透視。
@export_range(-1.0, 1.0, 0.01) var haze: float = -1.0

## 自動霧色：捲動比例低於這個值的層才有霧，每遠一點增加多少，以及上限。
const AUTO_HAZE_NEAR := 0.45
const AUTO_HAZE_GAIN := 0.9
const AUTO_HAZE_MAX := 0.32


func pixel_scale(imported: Texture2D) -> float:
	var ratio := float(source_width) / float(imported.get_width()) if source_width > 0 and imported != null and imported.get_width() > 0 else 1.0
	return ratio / float(maxi(1, texture_scale))


## 這一層前面霧色的濃度（0～1）：資料有指定就用指定的，否則依捲動比例算（越遠越濃）。
func haze_strength() -> float:
	if not is_finite(haze):
		return 0.0
	if haze >= 0.0:
		return clampf(haze, 0.0, 1.0)
	return clampf((AUTO_HAZE_NEAR - scroll_scale) * AUTO_HAZE_GAIN, 0.0, AUTO_HAZE_MAX)


## 可以安全使用的漂移速度：資料損毀（不是數字）時當成不動。
func drift_speed() -> float:
	return drift if is_finite(drift) else 0.0


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if not is_finite(drift) or not is_finite(haze):
		problems.append("背景層 %s 的漂移或霧色不是有效數字" % texture)
	if texture.is_empty() or not ResourceLoader.exists(texture):
		problems.append("背景層貼圖不存在：%s" % texture)
	return problems


func glow_path() -> String:
	return texture.get_basename() + "_glow." + texture.get_extension()
