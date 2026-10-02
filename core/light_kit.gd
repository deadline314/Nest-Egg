class_name LightKit
extends RefCounted
## 2D 光源工具：共用光源貼圖（只建立一次，節省記憶體）與光源工廠。
## 光源一律使用加法混合（ADD），不需整體壓暗畫面，維持遊戲可讀性。

const TEXTURE_SIZE := 128
const DEFAULT_GLOW_THRESHOLD := 1.0
const DEFAULT_GLOW_INTENSITY := 0.9

static var _soft_texture: GradientTexture2D
## 角色（骨架零件）的補光倍率，由 LightingController 依環境光與區段的 character_floor 更新。
## 環境光很暗時把角色零件的亮度往上補，確保玩家與敵人永遠有最低可讀亮度。
static var character_fill := 1.0
static var _emissive_material: CanvasItemMaterial
static var _environment: Environment


## 柔和的放射狀光暈貼圖（全部光源共用同一張）。
static func soft_texture() -> GradientTexture2D:
	if _soft_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.35, Color(1, 1, 1, 0.55))
		_soft_texture = GradientTexture2D.new()
		_soft_texture.gradient = gradient
		_soft_texture.fill = GradientTexture2D.FILL_RADIAL
		_soft_texture.fill_from = Vector2(0.5, 0.5)
		_soft_texture.fill_to = Vector2(1.0, 0.5)
		_soft_texture.width = TEXTURE_SIZE
		_soft_texture.height = TEXTURE_SIZE
	return _soft_texture


## 建立點光源。radius 為像素半徑；shadows 會讓地形投射陰影（較耗效能，只給重要光源）。
static func create_point_light(color: Color, radius: float, energy: float, shadows := false) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = soft_texture()
	light.texture_scale = maxf(0.05, radius * 2.0 / TEXTURE_SIZE)
	light.color = color
	light.energy = energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = shadows
	if shadows:
		light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		light.shadow_filter_smooth = 2.0
		light.shadow_color = Color(0, 0, 0, 0.75)
	return light


## 自發光材質（共用同一份）：不受環境光與光源影響，永遠維持原本的亮度。
## 環境光（CanvasModulate）會壓暗所有受光的東西；子彈、霓虹、危險物、敵人等需要永遠看得見的東西用這個。
static func emissive_material() -> CanvasItemMaterial:
	if _emissive_material == null:
		_emissive_material = CanvasItemMaterial.new()
		_emissive_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _emissive_material


## 讓這個節點自發光（不受環境光壓暗）。已經指定自己材質的節點不會被覆蓋。
static func mark_emissive(item: CanvasItem) -> void:
	if item.material == null:
		item.material = emissive_material()


## HDR 發光色：強度 > 1 時在 HDR 2D 下會產生泛光（bloom）。
static func glow(color: Color, intensity: float) -> Color:
	return Color(color.r * intensity, color.g * intensity, color.b * intensity, color.a)


## 2D 後製環境：HDR 泛光（bloom）。顏色強度 > 1 的子彈、槍口焰、爆炸會發光。
## 在 Compatibility 渲染器下不支援泛光，畫面仍可正常顯示（優雅降級）。
static func create_environment() -> WorldEnvironment:
	var env := environment()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = DEFAULT_GLOW_INTENSITY
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = DEFAULT_GLOW_THRESHOLD
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for level in 7:
		env.set_glow_level(level, 1.0 if level in [1, 2, 3, 4] else 0.0)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	return world_env


## 亮度（0.2126 R + 0.7152 G + 0.0722 B）。
static func luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


## 調整泛光（光影設定即時套用）。
static func set_glow(threshold: float, intensity: float) -> void:
	var env := environment()
	env.glow_hdr_threshold = threshold
	env.glow_intensity = intensity


## 全遊戲共用的 Environment（泛光參數由光影設定即時調整，見 LightingController）。
static func environment() -> Environment:
	if _environment == null:
		_environment = Environment.new()
	return _environment
