class_name LightingController
extends Node
## 區段光影控制：依玩家所在位置，在相鄰區段的光影設定之間平滑插值，
## 套用到環境光（CanvasModulate）、背景、霧與泛光。事件可暫時覆蓋（停電、警報），結束後平滑回復。
## 插值全部就地寫進固定的 LightingProfile 實例，不會每影格配置物件。設計見 design/08-lighting/DESIGN.md。

const MIN_FADE := 0.01
## 角色補光倍率上限（避免環境光趨近全黑時補到過曝）。
const MAX_CHARACTER_FILL := 4.0
## 閃電：兩次閃電之間的最短間隔（秒）、閃光顏色、雷聲延遲範圍（秒，距離感）。
const LIGHTNING_MIN_GAP := 6.0
const LIGHTNING_COLOR := Color(0.72, 0.8, 1.0)
const THUNDER_DELAY := Vector2(0.4, 1.5)
## 輪廓光：光的範圍、高度（0 = 與畫面平行，只照亮傾斜的法線）、相對鏡頭中心的位置（右上方）。
const RIM_LIGHT_RADIUS := 1500.0
const RIM_LIGHT_HEIGHT := 0.0
const RIM_LIGHT_OFFSET := Vector2(380.0, -300.0)

## 目前實際套用中的光影（唯讀）。
var current := LightingProfile.new()

var _zones: Array[LightingZone] = []
var _tile := 16.0
var _target: Node2D
var _modulate: CanvasModulate
var _background: CanvasItem
var _fog: FogLayer
var _post: PostProcess
var _neutral := LightingProfile.new()
var _zone_state := LightingProfile.new()
var _overrides: Array[_Override] = []
var _flash_color := Color.WHITE
var _flash_level := 0.0
var _flash_decay := 0.0
var _lightning_gap := 0.0
## 最近一次對外宣告的區段 id（環境音與背景音樂靠 EventBus.zone_changed 切換）。
var _announced_zone: StringName = &""
var _rim_light: PointLight2D


## zones 會被複製並排序；沒有有效區段時整關使用預設（全亮）光影，霧顏色取 fallback_fog。
func setup(zones: Array[LightingZone], tile_size: int, target: Node2D, canvas_modulate: CanvasModulate,
		background: CanvasItem, fog: FogLayer, fallback_fog: Color, post: PostProcess = null) -> void:
	_tile = float(maxi(1, tile_size))
	_target = target
	_modulate = canvas_modulate
	_background = background
	_fog = fog
	_post = post
	_neutral.id = &"neutral"
	_neutral.fog_color = fallback_fog
	_zones.clear()
	for zone in zones:
		if zone == null:
			push_error("[LightingController] 略過空的光影區段。")
			continue
		if zone.profile == null:
			push_error("[LightingController] 略過沒有光影設定的區段（起點 %d）" % zone.start_tile)
			continue
		for problem in zone.validate():
			push_error("[LightingController] %s" % problem)
		_zones.append(zone)
	_zones.sort_custom(func(a: LightingZone, b: LightingZone) -> bool: return a.start_tile < b.start_tile)
	EventBus.lighting_override_requested.connect(set_override)
	EventBus.lighting_override_cleared.connect(clear_override)
	EventBus.ambient_flash_requested.connect(flash)
	_rim_light = _create_rim_light()
	add_child(_rim_light)
	Settings.display_changed.connect(_on_display_changed)
	_on_display_changed()
	tree_exiting.connect(_on_exiting)
	snap()


func _process(delta: float) -> void:
	_advance_overrides(delta)
	_advance_flash(delta)
	_update_lightning(delta)
	_evaluate()
	_apply()


## 立刻套用目前位置的光影（不插值）。生成關卡與從檢查點重生時使用。
func snap() -> void:
	for override in _overrides:
		override.weight = override.goal
	_evaluate()
	_apply()


## x（世界座標）所在位置的區段光影，寫進 into。公開給測試與其他系統查詢。
func zone_state_at(x: float, into: LightingProfile) -> void:
	if _zones.is_empty():
		LightingProfile.copy_into(into, _neutral)
		return
	var index := _zone_index_at(x)
	if index == 0:
		LightingProfile.copy_into(into, _zones[0].profile)
		return
	var width := _half_blend(index) * 2.0
	if width <= 0.0:
		LightingProfile.copy_into(into, _zones[index].profile)
		return
	var t := clampf((x - (_boundary(index) - width * 0.5)) / width, 0.0, 1.0)
	LightingProfile.blend_into(into, _zones[index - 1].profile, _zones[index].profile, smoothstep(0.0, 1.0, t))


## x 所在的區段索引（進入過渡區就算新的區段）。
func _zone_index_at(x: float) -> int:
	var index := 0
	for i in range(1, _zones.size()):
		if x > _boundary(i) - _half_blend(i):
			index = i
		else:
			break
	return index


## x 所在區段的光影設定 id（沒有區段時是 neutral）。公開給環境音、背景音樂與測試。
func zone_id_at(x: float) -> StringName:
	return _zones[_zone_index_at(x)].profile.id if not _zones.is_empty() else _neutral.id


## 暫時覆蓋光影（停電、警報…）。同 id 的覆蓋會被取代；fade_time 秒內淡入。
func set_override(id: StringName, profile: LightingProfile, fade_time := 0.6) -> void:
	if profile == null:
		push_error("[LightingController] 覆蓋光影「%s」沒有指定設定，已忽略。" % id)
		return
	var override := _find_override(id)
	if override == null:
		override = _Override.new()
		override.id = id
		_overrides.append(override)
	override.profile = profile
	override.goal = 1.0
	override.rate = 1.0 / maxf(MIN_FADE, fade_time)


## 結束覆蓋，fade_time 秒內淡出並回到區段光影。
func clear_override(id: StringName, fade_time := 0.8) -> void:
	var override := _find_override(id)
	if override != null:
		override.goal = 0.0
		override.rate = 1.0 / maxf(MIN_FADE, fade_time)


## 環境光瞬間閃亮（爆炸、閃電）：color 疊加到環境光上，strength 為峰值，duration 秒內線性衰減。
## 更強的閃光取代較弱的；「減少閃光」設定開啟時強度大幅降低。
func flash(color: Color, strength: float, duration: float) -> void:
	var scaled := strength * Settings.flash_scale()
	if scaled > _flash_level:
		_flash_level = scaled
		_flash_color = color
		_flash_decay = scaled / maxf(0.05, duration)


## 目前閃光的強度（0 = 沒有）。
func flash_level() -> float:
	return _flash_level


## 打一次閃電：強烈的環境光閃亮與延遲的雷聲。距離上次閃電太近時回傳 false，什麼都不做。
## 「減少閃光」開啟時只閃一次且較弱，不會連續閃爍。
func strike() -> bool:
	if _lightning_gap > 0.0:
		return false
	_lightning_gap = LIGHTNING_MIN_GAP
	flash(LIGHTNING_COLOR, 1.0, 0.18)
	if not Settings.get_reduce_flashes():
		get_tree().create_timer(0.22, false).timeout.connect(flash.bind(LIGHTNING_COLOR, 0.5, 0.4))
	var delay := randf_range(THUNDER_DELAY.x, THUNDER_DELAY.y)
	get_tree().create_timer(delay, false).timeout.connect(Sfx.play.bind(&"thunder", -4.0))
	return true


func has_override(id: StringName) -> bool:
	return _find_override(id) != null


func _boundary(index: int) -> float:
	return float(_zones[index].start_tile) * _tile


func _half_blend(index: int) -> float:
	return float(_zones[index].blend_tiles) * _tile * 0.5


func _find_override(id: StringName) -> _Override:
	for override in _overrides:
		if override.id == id:
			return override
	return null


func _advance_overrides(delta: float) -> void:
	var i := _overrides.size() - 1
	while i >= 0:
		var override := _overrides[i]
		override.weight = move_toward(override.weight, override.goal, override.rate * delta)
		if override.goal <= 0.0 and override.weight <= 0.0:
			_overrides.remove_at(i)
		i -= 1


## 輪廓光：一盞很大的「高度 0」點光，放在鏡頭右上方遠處（效果像方向光）。平面（法線朝向鏡頭）幾乎不受影響，
## 只有法線貼圖中朝向光的邊緣會被打亮，勾出角色與地形的輪廓。
## 不用 DirectionalLight2D：它會讓不受光的背景層也被打亮，破壞背景的環境光壓暗。
func _create_rim_light() -> PointLight2D:
	var light := LightKit.create_point_light(Color.WHITE, RIM_LIGHT_RADIUS, 0.0, false, false)
	light.name = "RimLight"
	light.height = RIM_LIGHT_HEIGHT
	return light


## 光影品質改變：法線貼圖與輪廓光跟著開關。
func _on_display_changed() -> void:
	LitTextures.set_enabled(LightQuality.normal_maps())


func _advance_flash(delta: float) -> void:
	if _flash_level > 0.0:
		_flash_level = maxf(0.0, _flash_level - _flash_decay * delta)


## 室外區段隨機打閃電（頻率來自光影設定）。劇情過場期間不打；暫停時控制器不執行，自然也不打。
func _update_lightning(delta: float) -> void:
	_lightning_gap = maxf(0.0, _lightning_gap - delta)
	if current.lightning_rate <= 0.0 or _lightning_gap > 0.0 or Story.is_cinematic_active():
		return
	if randf() < current.lightning_rate / 60.0 * delta:
		strike()


func _evaluate() -> void:
	var x := _target.global_position.x if is_instance_valid(_target) else 0.0
	zone_state_at(x, _zone_state)
	var zone_id := zone_id_at(x)
	if zone_id != _announced_zone:
		_announced_zone = zone_id
		EventBus.zone_changed.emit(zone_id)
	LightingProfile.copy_into(current, _zone_state)
	for override in _overrides:
		if override.weight > 0.0:
			LightingProfile.blend_into(current, current, override.profile, override.weight)
	if _flash_level > 0.0:
		var lift := _flash_color * _flash_level
		# 閃光最亮到全亮為止（不超過 1）。
		current.ambient_color = Color(minf(1.0, current.ambient_color.r + lift.r), minf(1.0, current.ambient_color.g + lift.g), minf(1.0, current.ambient_color.b + lift.b), 1.0)


func _apply() -> void:
	if is_instance_valid(_modulate) and _modulate.color != current.ambient_color:
		_modulate.color = current.ambient_color
	if is_instance_valid(_background):
		_background.modulate = current.background_tint
	if is_instance_valid(_fog):
		_fog.color = current.fog_color
		_fog.density = current.fog_density
	LightKit.set_glow(current.glow_threshold, current.glow_intensity)
	if is_instance_valid(_post):
		_post.apply(current)
	var ambient_luma := maxf(0.01, LightKit.luminance(current.ambient_color))
	LightKit.character_fill = clampf(current.character_floor / ambient_luma, 1.0, MAX_CHARACTER_FILL)
	LightKit.player_light_energy = LightKit.player_light_for(ambient_luma, LightKit.character_fill)
	LightKit.lamp_power = current.lamp_power
	_rim_light.color = current.rim_color
	_rim_light.energy = current.rim_energy
	_rim_light.enabled = LightQuality.normal_maps() and current.rim_energy > 0.0
	var viewport := get_viewport()
	if viewport != null:
		var center := viewport.get_canvas_transform().affine_inverse() * (viewport.get_visible_rect().size * 0.5)
		_rim_light.global_position = center + RIM_LIGHT_OFFSET


## 離開關卡時還原泛光預設，避免主選單沿用最後一個區段的設定。
func _on_exiting() -> void:
	if _announced_zone != &"":
		_announced_zone = &""
		EventBus.zone_changed.emit(&"")
	LightKit.set_glow(LightKit.DEFAULT_GLOW_THRESHOLD, LightKit.DEFAULT_GLOW_INTENSITY)
	LightKit.character_fill = 1.0
	LightKit.player_light_energy = LightKit.PLAYER_LIGHT_BASE_ENERGY
	LightKit.lamp_power = 1.0
	LitTextures.set_enabled(true)
	if EventBus.lighting_override_requested.is_connected(set_override):
		EventBus.lighting_override_requested.disconnect(set_override)
	if EventBus.lighting_override_cleared.is_connected(clear_override):
		EventBus.lighting_override_cleared.disconnect(clear_override)
	if EventBus.ambient_flash_requested.is_connected(flash):
		EventBus.ambient_flash_requested.disconnect(flash)


## 一個進行中的覆蓋：權重往目標值（1 = 完全覆蓋，0 = 淡出後移除）移動。
class _Override:
	extends RefCounted

	var id: StringName
	var profile: LightingProfile
	var weight := 0.0
	var goal := 1.0
	var rate := 1.0
