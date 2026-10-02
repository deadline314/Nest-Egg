class_name LightingProfile
extends Resource
## 光影設定：一個區段（或一個事件）的整體光影。環境光、背景、霧與泛光都在這裡，新增設定只需建立新的 .tres。
## 設計見 design/08-lighting/DESIGN.md。LightingController 會在相鄰兩份設定之間平滑插值。

## 所有可插值的欄位。新增欄位時加在這裡，插值與驗證會自動涵蓋。
const BLENDED: Array[StringName] = [
	&"ambient_color", &"background_tint", &"fog_color", &"fog_density", &"glow_threshold", &"glow_intensity",
]

@export var id: StringName = &"lighting"
@export_group("Ambient")
## 環境光：所有受光的東西（地形、角色、背景）乘上這個顏色，光源再疊加在上面。越暗畫面越壓抑。
@export var ambient_color: Color = Color(1, 1, 1, 1)
## 背景整體再乘上的顏色（壓暗或染色），在環境光之外額外調整遠景。
@export var background_tint: Color = Color(1, 1, 1, 1)
@export_group("Fog")
@export var fog_color: Color = Color(0.55, 0.45, 0.85, 1.0)
## 霧的濃度倍率（0 = 沒有霧，1 = 標準，> 1 更濃）。
@export_range(0.0, 3.0, 0.05) var fog_density: float = 1.0
@export_group("Glow")
## 泛光的 HDR 門檻：亮度超過它的東西才會暈開。越高，只有真正的發光體才會泛光。
@export_range(0.5, 4.0, 0.05) var glow_threshold: float = 1.0
@export_range(0.0, 3.0, 0.05) var glow_intensity: float = 0.9


## 回傳問題清單（空代表沒問題）。
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("光影設定缺少 id")
	for color_name in [&"ambient_color", &"background_tint", &"fog_color"]:
		var color: Color = get(color_name)
		if color.r < 0.0 or color.g < 0.0 or color.b < 0.0:
			problems.append("%s 的 %s 有負值" % [id, color_name])
	if fog_density < 0.0:
		problems.append("%s 的霧濃度不能是負的" % id)
	if glow_threshold <= 0.0:
		problems.append("%s 的泛光門檻必須大於 0" % id)
	return problems


## 把 from 與 to 以 t（0~1）插值後寫進 target，不配置新物件（每影格可安全呼叫）。
static func blend_into(target: LightingProfile, from: LightingProfile, to: LightingProfile, t: float) -> void:
	for property in BLENDED:
		var a: Variant = from.get(property)
		var b: Variant = to.get(property)
		target.set(property, lerp(a, b, t))


## 把 source 的插值欄位整份複製進 target。
static func copy_into(target: LightingProfile, source: LightingProfile) -> void:
	for property in BLENDED:
		target.set(property, source.get(property))
