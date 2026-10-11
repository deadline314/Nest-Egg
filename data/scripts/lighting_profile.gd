class_name LightingProfile
extends Resource
## 光影設定：一個區段（或一個事件）的整體光影。環境光、背景、霧與泛光都在這裡，新增設定只需建立新的 .tres。
## 設計見 design/08-lighting/DESIGN.md。LightingController 會在相鄰兩份設定之間平滑插值。

## 所有可插值的欄位。新增欄位時加在這裡，插值與驗證會自動涵蓋。
const BLENDED: Array[StringName] = [
	&"ambient_color", &"background_tint", &"fog_color", &"fog_density", &"glow_threshold", &"glow_intensity",
	&"saturation", &"contrast", &"shadow_tint", &"highlight_tint", &"vignette", &"grain", &"aberration", &"character_floor", &"enemy_fill_scale", &"lamp_power", &"lightning_rate", &"rim_color", &"rim_energy",
]

## 角色最低可讀亮度（0~1）：環境光再暗，角色補光後至少要有這個亮度。
const MIN_READABLE_CHARACTER_LUMA := 0.2
## 亮度分級（BG-33）：依環境光的亮度分成暗、一般、亮。暗的區域要靠槍燈與場景燈才看得清楚；亮的留給安全區與特殊場景。
const TIER_DARK_BELOW := 0.2
const TIER_BRIGHT_FROM := 0.35
## 特殊情境的顆粒上限：再高就會蓋過文字與人物。
const MAX_SPECIAL_GRAIN := 0.05

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
@export_group("Grade")
## 飽和度（1 = 原色，0 = 黑白）。壓抑的畫面通常去飽和，霓虹本身仍然鮮豔。
@export_range(0.0, 2.0, 0.01) var saturation: float = 1.0
## 對比（1 = 不變）。提高會讓暗部更黑、亮部更突出。
@export_range(0.5, 2.0, 0.01) var contrast: float = 1.0
## 陰影的色調（乘上去，白色 = 不變）：偏冷讓暗部帶藍。
@export var shadow_tint: Color = Color(1, 1, 1, 1)
## 亮部的色調：偏暖讓光源附近帶橘黃。
@export var highlight_tint: Color = Color(1, 1, 1, 1)
@export_group("Readability")
## 角色（主角與敵人）的最低可讀亮度：環境光比這個暗時，角色零件會被補亮到這個程度（0 = 不補）。
## 重度壓抑的畫面靠它維持公平：環境可以很暗，但角色永遠看得到。
@export_range(0.0, 1.0, 0.01) var character_floor: float = 0.0
## 敵人的補光占角色補光的比例（1 = 和主角一樣）。牆面是中間調的室內把它調低：敵人比牆暗、成為清楚的剪影，
## 主角維持原本的亮度。背景很暗的場景不要調低，敵人會沉進背景裡。
@export_range(0.5, 1.0, 0.01) var enemy_fill_scale: float = 1.0
@export_group("Rim")
## 輪廓光（對有法線貼圖的角色與地形，只在邊緣打亮）：顏色與強度（0 = 沒有）。
@export var rim_color: Color = Color(1, 1, 1, 1)
@export_range(0.0, 3.0, 0.05) var rim_energy: float = 0.0
@export_group("Weather")
## 每分鐘平均閃電次數（0 = 沒有閃電）。室外區段才有。
@export_range(0.0, 20.0, 0.1) var lightning_rate: float = 0.0
@export_group("Lamps")
## 場景燈與招牌的供電（1 = 全亮，0 = 全滅）：降低時各盞燈依序熄滅，停電事件用。
@export_range(0.0, 1.0, 0.01) var lamp_power: float = 1.0
## 這個區段的場景燈風格（生成時套用，不插值）。
@export var lamp_style: LampStyle
## 這個區段霓虹招牌的色盤與亮度倍率（生成時套用）。沒有色盤時使用預設霓虹色。
@export var neon_colors: PackedColorArray = PackedColorArray()
@export_range(0.0, 3.0, 0.05) var neon_energy: float = 1.0
@export_group("Screen")
## 暗角強度（0 = 沒有）：畫面邊緣壓暗。
@export_range(0.0, 1.5, 0.01) var vignette: float = 0.0
## 畫面顆粒強度（0 = 沒有）。一般遊玩一律 0；只有回憶、訊號干擾這類特殊情境才用，而且要在 grain_reason 寫明理由。
@export_range(0.0, 0.3, 0.005) var grain: float = 0.0
## 這份設定為什麼需要顆粒（玩家當下處在什麼特殊情境）。grain 大於 0 時必填。
@export var grain_reason: String = ""
## 邊緣色差（螢幕寬度的比例，0 = 沒有）：只在畫面邊緣偏移紅藍通道。
@export_range(0.0, 0.01, 0.0005) var aberration: float = 0.0


## 角色在這份設定下實際的亮度：環境光與補光底線取大者。
func character_luma() -> float:
	return maxf(LightKit.luminance(ambient_color), character_floor)


## 回傳問題清單（空代表沒問題）。
## 這份光影設定屬於哪一級亮度：&"dark"、&"normal" 或 &"bright"。
func brightness_tier() -> StringName:
	var luma := LightKit.luminance(ambient_color)
	return &"dark" if luma < TIER_DARK_BELOW else (&"bright" if luma >= TIER_BRIGHT_FROM else &"normal")


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
	for color_name in [&"shadow_tint", &"highlight_tint"]:
		var tint: Color = get(color_name)
		if tint.r < 0.0 or tint.g < 0.0 or tint.b < 0.0:
			problems.append("%s 的 %s 有負值" % [id, color_name])
	if lamp_style != null:
		for problem in lamp_style.validate():
			problems.append("%s：%s" % [id, problem])
	if rim_energy < 0.0:
		problems.append("%s 的輪廓光強度不能是負的" % id)
	if lightning_rate < 0.0:
		problems.append("%s 的閃電頻率不能是負的" % id)
	if lamp_power < 0.0 or lamp_power > 1.0:
		problems.append("%s 的燈供電必須在 0~1 之間" % id)
	if character_floor < 0.0 or character_floor > 1.0:
		problems.append("%s 的角色最低亮度必須在 0~1 之間" % id)
	if enemy_fill_scale < 0.5 or enemy_fill_scale > 1.0:
		problems.append("%s 的敵人補光比例必須在 0.5~1 之間" % id)
	if character_luma() < MIN_READABLE_CHARACTER_LUMA:
		problems.append("%s 的角色亮度過低（%.2f < %.2f）：請調高環境光或 character_floor" % [id, character_luma(), MIN_READABLE_CHARACTER_LUMA])
	if neon_energy < 0.0:
		problems.append("%s 的霓虹亮度不能是負的" % id)
	if saturation < 0.0 or contrast <= 0.0:
		problems.append("%s 的飽和度不能是負的、對比必須大於 0" % id)
	if vignette < 0.0 or grain < 0.0 or aberration < 0.0:
		problems.append("%s 的暗角、顆粒、色差不能是負的" % id)
	if grain > MAX_SPECIAL_GRAIN:
		problems.append("%s 的顆粒 %.3f 超過特殊情境的上限 %.3f" % [id, grain, MAX_SPECIAL_GRAIN])
	if grain > 0.0 and grain_reason.strip_edges().is_empty():
		problems.append("%s 有顆粒卻沒寫 grain_reason：一般遊玩不加顆粒，特殊情境要寫明理由" % id)
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
