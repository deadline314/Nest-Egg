class_name LightBudget
extends Node
## 光源預算：只管理場景光源群組（LightKit.SCENE_LIGHTS）。每隔一小段時間重新評估：
##   1. 鏡頭外、照不到畫面的光源停用（visible = false）
##   2. 剩下的依「亮度 × 範圍 ÷ 離鏡頭距離」排序，只啟用前 N 盞（N 由光影品質決定）
##   3. 其中只有前 M 盞想要陰影的光源實際開啟陰影
## 玩家自己的光與戰鬥特效的光源池不受管理（固定數量，另外計算）。
## 設計見 design/08-lighting/DESIGN.md 的「光源分級與預算」。

const TICK := 0.1

var _elapsed := 0.0
## 本輪評估後啟用的光源數與陰影光源數（測試與除錯用）。
var active_lights := 0
var active_shadow_lights := 0


func _ready() -> void:
	# 光影品質改變時馬上重新評估。
	Settings.display_changed.connect(refresh)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= TICK:
		_elapsed = 0.0
		refresh()


## 立刻重新評估（生成關卡後與品質改變時呼叫）。
func refresh() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var inverse := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(inverse * Vector2.ZERO, inverse.basis_xform(viewport.get_visible_rect().size)).abs()
	var center := view.get_center()
	var candidates: Array[Array] = []
	for node in get_tree().get_nodes_in_group(LightKit.SCENE_LIGHTS):
		var light := node as PointLight2D
		# 自己熄滅（停電、壞掉）的燈不佔預算。
		if light == null or not light.is_inside_tree() or not light.enabled:
			continue
		var radius := light.texture_scale * LightKit.TEXTURE_SIZE * 0.5
		var distance := _distance_to_rect(view, light.global_position)
		if distance > radius:
			light.visible = false
			continue
		var score := maxf(light.energy, 0.2) * radius / (1.0 + distance + center.distance_to(light.global_position) * 0.1)
		candidates.append([score, light])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var max_lights := LightQuality.max_lights()
	var max_shadows := LightQuality.shadow_lights()
	var filter := LightQuality.shadow_filter()
	active_lights = 0
	active_shadow_lights = 0
	for pair in candidates:
		var light: PointLight2D = pair[1]
		var keep := active_lights < max_lights
		light.visible = keep
		if not keep:
			light.shadow_enabled = false
			continue
		active_lights += 1
		var shadow := bool(light.get_meta(LightKit.META_WANTS_SHADOW, false)) and active_shadow_lights < max_shadows
		light.shadow_enabled = shadow
		if shadow:
			active_shadow_lights += 1
			light.shadow_filter = filter


## 點到矩形的距離（點在矩形內回傳 0）。
static func _distance_to_rect(rect: Rect2, point: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return sqrt(dx * dx + dy * dy)
