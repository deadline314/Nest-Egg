class_name LightKit
extends RefCounted
## 2D 光源工具：共用光源貼圖（只建立一次，節省記憶體）與光源工廠。
## 光源一律使用加法混合（ADD），不需整體壓暗畫面，維持遊戲可讀性。

const TEXTURE_SIZE := 128
## 發光倍率的上限（敵人預兆的警示光最亮到 3.5）。
const HDR_PEAK_MAX := 3.5
const DEFAULT_GLOW_THRESHOLD := 1.0
const DEFAULT_GLOW_INTENSITY := 0.9
## 泛光（bloom）每個像素最多貢獻到這個亮度（Godot 的 glow_hdr_luminance_cap 預設 12，閃光疊在白色頭髮上時一個像素就能把整片糊掉）。
## 發光物（子彈、霓虹、爆炸）的亮度本來就在 HDR_PEAK_MAX 以內，這個上限只擋「光源疊加的意外」。
const GLOW_LUMINANCE_CAP := 2.0
## 角色曝光預算（NE-213）：白色零件（頭髮、衣服）在「環境光 × 補光 + 玩家自己的光 + 附近的燈」之下，峰值要壓在泛光門檻附近，
## 超過就會被泛光吃成一團白。玩家自己的光依這個預算在亮場景自動調暗（player_light_energy）。
const CHARACTER_EXPOSURE_BUDGET := 1.0
## 預留給附近路燈與閃光的亮度（估計值）。
const NEARBY_LIGHT_ALLOWANCE := 0.2
## 單盞光對角色的亮度上限（角色專用的受光，見 art/shaders/character_light.gdshader）：亮場景小、暗場景大。
const CHARACTER_LIGHT_CAP_MAX := 0.5
const CHARACTER_LIGHT_CAP_MIN := 0.2
const PLAYER_LIGHT_BASE_ENERGY := 0.75
const PLAYER_LIGHT_MIN_ENERGY := 0.15
## 離玩家很近的閃光（受傷、格擋反彈、補給…）能量上限：閃光是回饋，不是要把角色照成白色。
const NEAR_CHARACTER_FLASH_CAP := 1.4
## 供電變化時，一盞燈從全亮到全滅的過渡寬度。
const POWER_RAMP := 0.1
## 一般點光源離畫面的高度（像素；0 = 與畫面平行）。有法線貼圖的表面要靠它才照得到：
## 平面（法線朝向鏡頭）受光量取決於光有多「高」，太低角色會比沒有法線貼圖時更暗。
const LIGHT_HEIGHT := 140.0

static var _soft_texture: GradientTexture2D
## 角色（骨架零件）的補光倍率，由 LightingController 依環境光與區段的 character_floor 更新。
## 環境光很暗時把角色零件的亮度往上補，確保玩家與敵人永遠有最低可讀亮度。
static var character_fill := 1.0
## 敵人的補光倍率：角色補光乘上區段的 enemy_fill_scale，不低於 1（不會比環境光更暗）。
static var enemy_fill := 1.0
## 單盞光對角色的亮度上限目前值，由 LightingController 依環境光與補光更新。
static var character_light_cap := CHARACTER_LIGHT_CAP_MAX
## 玩家身上那盞光目前的能量（亮場景自動調暗，由 LightingController 依光影設定更新，Player 每影格套用）。
static var player_light_energy := PLAYER_LIGHT_BASE_ENERGY
## 場景燈的供電（0~1）：由 LightingController 依光影設定更新，每盞燈依自己的門檻依序熄滅／亮起。
static var lamp_power := 1.0
const WINDOW_LIFE_SHADER := preload("res://game/level/environment/window_life.gdshader")

static var _emissive_material: CanvasItemMaterial
static var _window_life_material: ShaderMaterial
static var _additive_material: CanvasItemMaterial
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


## 場景光源群組：LightBudget 只管理這個群組裡的光源（鏡頭外停用、同時啟用與陰影數量有上限）。
const SCENE_LIGHTS := &"scene_lights"
## 光源「想要陰影」的標記（預算決定實際給不給）。
const META_WANTS_SHADOW := &"wants_shadow"

## 建立點光源。radius 為像素半徑；shadows 表示這盞燈想要陰影（較耗效能，實際由 LightBudget 依預算決定）。
## managed = false 的光源不受預算管理（玩家自己的光、戰鬥特效的光源池）。
static func create_point_light(color: Color, radius: float, energy: float, shadows := false, managed := true) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = soft_texture()
	light.texture_scale = maxf(0.05, radius * 2.0 / TEXTURE_SIZE)
	light.color = color
	light.energy = energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.height = LIGHT_HEIGHT
	light.shadow_enabled = shadows
	light.set_meta(META_WANTS_SHADOW, shadows)
	if managed:
		light.add_to_group(SCENE_LIGHTS)
	if shadows:
		light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		light.shadow_filter_smooth = 2.0
		light.shadow_color = Color(0, 0, 0, 0.75)
	return light


## 場景光源在某個世界座標的照亮程度（0 = 沒被任何燈照到；光學迷彩敵人用它判斷要不要現形）。
## 只計算受預算管理的場景燈（路燈、霓虹…），不含環境光；關掉的燈與停電的燈不算。
static func light_level_at(tree: SceneTree, position: Vector2) -> float:
	var level := 0.0
	for node in tree.get_nodes_in_group(SCENE_LIGHTS):
		var light := node as PointLight2D
		if light == null or not light.enabled or light.energy <= 0.0 or not light.is_visible_in_tree():
			continue
		var radius := light.texture_scale * TEXTURE_SIZE * 0.5
		var distance := light.global_position.distance_to(position)
		if distance < radius:
			level += light.energy * (1.0 - distance / radius)
	return level


## 自發光材質（共用同一份）：不受環境光與光源影響，永遠維持原本的亮度。
## 環境光（CanvasModulate）會壓暗所有受光的東西；子彈、霓虹、危險物、敵人等需要永遠看得見的東西用這個。
static func emissive_material() -> CanvasItemMaterial:
	if _emissive_material == null:
		_emissive_material = CanvasItemMaterial.new()
		_emissive_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _emissive_material


## 窗光的生命：自發光、不受環境光壓暗，一部分窗戶區塊緩慢閃爍、純紅的點（屋頂信標）規律明滅。
## 全部是著色器、共用一份材質，靜態繪製的立面與背景因此也會動（見 window_life.gdshader）。
static func window_life_material() -> ShaderMaterial:
	if _window_life_material == null:
		_window_life_material = ShaderMaterial.new()
		_window_life_material.shader = WINDOW_LIFE_SHADER
	return _window_life_material


## 加法混合的自發光材質（光錐、光暈、倒影用）：疊在畫面上只會變亮，不會被環境光壓暗。
static func additive_emissive_material() -> CanvasItemMaterial:
	if _additive_material == null:
		_additive_material = CanvasItemMaterial.new()
		_additive_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_material


## 讓這個節點自發光（不受環境光壓暗）。已經指定自己材質的節點不會被覆蓋。
static func mark_emissive(item: CanvasItem) -> void:
	if item.material == null:
		item.material = emissive_material()


## HDR 發光色：強度 > 1 時在 HDR 2D 下會產生泛光（bloom）。強度夾在 HDR_PEAK_MAX 以內：
## 所有光影設定的泛光門檻在 0.95～1.3、強度在 0.6～1.1，這個上限下任何設定的泛光超出量都在預算內，不會被吃成一片白（FxUpgradesSuite 檢查）。
static func glow(color: Color, intensity: float) -> Color:
	var level := minf(intensity, HDR_PEAK_MAX)
	return Color(color.r * level, color.g * level, color.b * level, color.a)


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
	env.glow_hdr_luminance_cap = GLOW_LUMINANCE_CAP
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for level in 7:
		env.set_glow_level(level, 1.0 if level in [1, 2, 3, 4] else 0.0)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	return world_env


## 單盞燈在目前供電下的亮度比例（0~1）：供電低於這盞燈的門檻時熄滅，在門檻附近有一小段漸暗。
## threshold 建議在 0.1~0.95 之間（供電 0 時所有燈都會熄滅、供電 1 時都亮）。
static func power_gate(power: float, threshold: float) -> float:
	return clampf((power - threshold) / POWER_RAMP + 1.0, 0.0, 1.0)


## 玩家自己的光在這個環境下可以多亮：預算扣掉「環境光 × 補光」與附近燈光的預留，夾在最小與基本能量之間。
static func player_light_for(ambient_luma: float, fill: float) -> float:
	return clampf(CHARACTER_EXPOSURE_BUDGET - ambient_luma * fill - NEARBY_LIGHT_ALLOWANCE, PLAYER_LIGHT_MIN_ENERGY, PLAYER_LIGHT_BASE_ENERGY)


## 單盞光對角色的亮度上限：預算扣掉「環境光 × 補光」，夾在最小與最大之間。
static func character_light_cap_for(ambient_luma: float, fill: float) -> float:
	return clampf(CHARACTER_EXPOSURE_BUDGET - ambient_luma * fill, CHARACTER_LIGHT_CAP_MIN, CHARACTER_LIGHT_CAP_MAX)


## 白色零件的曝光估計峰值（0~1 以上）：環境光 × 補光 + 玩家的光 + 最亮的一盞附近的燈（兩者都被單盞上限夾住）。大於預算很多代表會被泛光吃掉。
static func character_exposure(ambient_luma: float, fill: float) -> float:
	var cap := character_light_cap_for(ambient_luma, fill)
	return ambient_luma * fill + minf(player_light_for(ambient_luma, fill), cap) + cap


## 離角色很近的閃光能量夾在上限內；遠的不動。
static func capped_flash_energy(energy: float, near_character: bool) -> float:
	return minf(energy, NEAR_CHARACTER_FLASH_CAP) if near_character else energy


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
