class_name LightingController
extends Node
## 區段光影控制：依玩家所在位置，在相鄰區段的光影設定之間平滑插值，
## 套用到環境光（CanvasModulate）、背景、霧與泛光。事件可暫時覆蓋（停電、警報），結束後平滑回復。
## 插值全部就地寫進固定的 LightingProfile 實例，不會每影格配置物件。設計見 design/08-lighting/DESIGN.md。

const MIN_FADE := 0.01

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
	tree_exiting.connect(_on_exiting)
	snap()


func _process(delta: float) -> void:
	_advance_overrides(delta)
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
	var index := 0
	for i in range(1, _zones.size()):
		if x > _boundary(i) - _half_blend(i):
			index = i
		else:
			break
	if index == 0:
		LightingProfile.copy_into(into, _zones[0].profile)
		return
	var width := _half_blend(index) * 2.0
	if width <= 0.0:
		LightingProfile.copy_into(into, _zones[index].profile)
		return
	var t := clampf((x - (_boundary(index) - width * 0.5)) / width, 0.0, 1.0)
	LightingProfile.blend_into(into, _zones[index - 1].profile, _zones[index].profile, smoothstep(0.0, 1.0, t))


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


func _evaluate() -> void:
	if is_instance_valid(_target):
		zone_state_at(_target.global_position.x, _zone_state)
	else:
		zone_state_at(0.0, _zone_state)
	LightingProfile.copy_into(current, _zone_state)
	for override in _overrides:
		if override.weight > 0.0:
			LightingProfile.blend_into(current, current, override.profile, override.weight)


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


## 離開關卡時還原泛光預設，避免主選單沿用最後一個區段的設定。
func _on_exiting() -> void:
	LightKit.set_glow(LightKit.DEFAULT_GLOW_THRESHOLD, LightKit.DEFAULT_GLOW_INTENSITY)
	if EventBus.lighting_override_requested.is_connected(set_override):
		EventBus.lighting_override_requested.disconnect(set_override)
	if EventBus.lighting_override_cleared.is_connected(clear_override):
		EventBus.lighting_override_cleared.disconnect(clear_override)


## 一個進行中的覆蓋：權重往目標值（1 = 完全覆蓋，0 = 淡出後移除）移動。
class _Override:
	extends RefCounted

	var id: StringName
	var profile: LightingProfile
	var weight := 0.0
	var goal := 1.0
	var rate := 1.0
