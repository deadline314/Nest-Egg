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
## 懸掛物（衣繩、燈籠串、纜線）：搖動改成頂端固定、底部擺動。
@export var sway_hang: bool = false
## 自發光層帶「窗光生命」：一部分區塊緩慢閃爍，純紅的點（信標、警示燈）規律明滅。
@export var glow_life: bool = false
## 螢幕掃描強度：自發光層上有一條較亮的橫帶緩慢上移（看板、螢幕、販賣機）。0 = 不掃描。
@export_range(0.0, 1.0) var glow_scan: float = 0.0
## 水窪：自發光層（霓虹倒影）上有雨滴漣漪向外擴散。
@export var ripple: bool = false
## BG-25：來源貼圖 UV 的局部水柱與承接面；零矩形表示保持原靜態圖。
@export var flow_region: Rect2 = Rect2()
@export var flow_surface: Rect2 = Rect2()
## 水柱原圖亮部只保留克制反光，不模仿發光彈道。
@export_range(0.0, 1.0) var flow_glow_gain: float = 0.4

## 冒蒸汽（煙囪、通風管）；位置相對於道具左上角。
@export var steam: bool = false
@export var steam_offset: Vector2 = Vector2.ZERO
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
	if has_local_flow() and not local_flow_valid():
		problems.append("道具 %s 局部水流 UV 無效" % id)
	return problems


func glow_path() -> String:
	return texture.get_basename() + "_glow." + texture.get_extension()


func has_local_flow() -> bool:
	return flow_region.size != Vector2.ZERO


func local_flow_valid() -> bool:
	if not is_finite(flow_glow_gain) or flow_glow_gain < 0.0 or flow_glow_gain > 1.0:
		return false
	for rect in [flow_region, flow_surface]:
		if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return false
		if not Rect2(Vector2.ZERO, Vector2.ONE).encloses(rect):
			return false
	return flow_surface.position.y >= flow_region.end.y
