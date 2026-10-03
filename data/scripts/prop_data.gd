class_name PropData
extends Resource
## 場景道具：一張貼圖（4 倍解析度）+ 可選的自發光層、法線、光源、單向平台與遮光。
## 地圖 JSON 的 props 清單以 id 擺放；新增道具只需要這份資料與圖片。
##
## 貼圖的左上角對齊 size 的左上角，logical size 是遊戲裡的大小（貼圖會縮成 size）。

enum Layer { BACK, FRONT }

const TEXTURE_SCALE := 4

@export var id: StringName = &""
@export var display_name: String = ""
@export_file("*.png") var texture: String = ""
## 遊戲中的大小（邏輯像素）。
@export var size: Vector2 = Vector2(16, 16)
## BACK：在角色後面；FRONT：在角色前面（半透明，不遮住敵人與子彈）。
@export var layer: Layer = Layer.BACK
## 前層道具的透明度上限。
@export_range(0.1, 1.0) var front_alpha: float = 0.7
## 有同名 `_glow.png` 時自動疊上自發光層。
@export var has_glow: bool = false
@export var glow_intensity: float = 1.6
## 閃爍強度（0 不閃）。
@export_range(0.0, 1.0) var flicker: float = 0.0
## 光源（radius 為 0 代表沒有）。位置相對於道具左上角。
@export var light_color: Color = Color(1, 0.75, 0.4)
@export var light_radius: float = 0.0
@export var light_energy: float = 0.8
@export var light_offset: Vector2 = Vector2.ZERO
## 單向平台（逃生梯平台、雨棚）：x、y、寬、高，相對道具左上角；寬度為 0 代表沒有。
@export var platform: Rect2 = Rect2()
## 被風吹的搖動幅度（頂端的位移，邏輯像素；0 = 不搖）。植物用，由共用的著色器處理，不增加每影格的腳本。
@export_range(0.0, 8.0) var sway: float = 0.0
## 是否遮擋光線（產生影子）。
@export var casts_shadow: bool = false
## 裝飾分類（預覽與檢查用）。
@export var category: StringName = &"street"


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("道具缺少 id")
	if texture.is_empty() or not ResourceLoader.exists(texture):
		problems.append("道具 %s 的貼圖不存在：%s" % [id, texture])
	elif has_glow and not ResourceLoader.exists(glow_path()):
		problems.append("道具 %s 標示有自發光層，但找不到：%s" % [id, glow_path()])
	if size.x <= 0.0 or size.y <= 0.0:
		problems.append("道具 %s 的大小無效" % id)
	return problems


func glow_path() -> String:
	return texture.get_basename() + "_glow." + texture.get_extension()
