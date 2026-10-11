class_name ContactShadow
extends Node2D
## 角色腳下的接觸陰影：往下找實際的支撐面（地面或單向平台），陰影畫在那個面上。
## 離地越高越小越淡；腳下 MAX_DROP 以內沒有支撐面就不畫，所以不會浮在坑洞上，也不會穿到下一層樓。
## 只蓋住有支撐的範圍（站在平台邊緣時不會懸在空中），並依最近的場景燈往反方向偏一點。
## 用固定幾支 RayCast2D 取樣，沒有每影格配置；數值沒變就不重畫。原點要放在角色的腳底。

## 橫向取樣的射線數（奇數，中間一支在正下方）。
const SAMPLES := 5
## 往下找支撐面的最遠距離（像素）：大約是主角跳躍的最高點再多一點。
const MAX_DROP := 150.0
## 射線起點在腳底上方多少，避免起點卡在地面裡。
const PROBE_LIFT := 6.0
## 相鄰取樣的落點高度差在這個範圍內算同一個面。
const SURFACE_TOLERANCE := 5.0
const BASE_ALPHA := 0.8
## 離地最高時，寬度剩下的比例。
const HEIGHT_SHRINK := 0.45
## 陰影的高 ÷ 寬，以及高度上限（像素）：側視的地板只有頂面那一條，陰影要整個落在頂面上，不爬上後面的牆。
const FLATTEN := 0.32
const MAX_HEIGHT := 7.0
## 地板的亮邊比碰撞面高一點：陰影從這麼多像素以上開始，才會蓋在看得到的地板面上。
const SURFACE_LIP := 2.0
## 深色核心占整個陰影寬度的比例。
const CORE_WIDTH := 0.7
## 被最近的燈推開的最大位移，以及燈的影響距離（像素）。
const LIGHT_SHIFT := 3.0
const LIGHT_RANGE := 220.0
## 多久重新找一次最近的燈（秒）；所有陰影共用同一份燈的清單。
const LIGHT_REFRESH := 0.3
const REDRAW_EPSILON := 0.25

## 腳印的半寬（像素）。姿勢改變（倒地、四足）時由擁有者調整。
var half_width := 10.0:
	set(value):
		half_width = maxf(2.0, value)
		_place_rays()

var _rays: Array[RayCast2D] = []
## 支撐範圍的左右邊界與支撐面高度（本地座標）、目前的強度（0＝不畫）與被燈推開的位移。
var _left := 0.0
var _right := 0.0
var _surface := 0.0
var _strength := 0.0
var _shift := 0.0
var _light_timer := 0.0

static var _lights: Array[PointLight2D] = []
static var _lights_frame := -1


## 在 body（原點在腳底的角色）底下建立陰影；body 是碰撞體時射線會略過它自己。
static func attach(body: Node2D, footprint_half_width: float) -> ContactShadow:
	var shadow := ContactShadow.new()
	shadow.name = "ContactShadow"
	shadow.half_width = footprint_half_width
	body.add_child(shadow)
	# 站在地上、有接觸陰影的角色，也會依光源在背後的牆上投影（WallShadows）。
	body.add_to_group(WallShadows.CASTER_GROUP)
	return shadow


func _ready() -> void:
	# 畫在地形之上、所有角色零件之下。
	z_as_relative = false
	z_index = WorldLayers.ENTITY_BEHIND
	var owner_body := get_parent() as CollisionObject2D
	for i in SAMPLES:
		var ray := RayCast2D.new()
		ray.collision_mask = Layers.SOLID
		ray.hit_from_inside = false
		ray.target_position = Vector2(0.0, MAX_DROP + PROBE_LIFT)
		if owner_body != null:
			ray.add_exception(owner_body)
		add_child(ray)
		_rays.append(ray)
	_place_rays()
	_light_timer = randf() * LIGHT_REFRESH


func _place_rays() -> void:
	for i in _rays.size():
		var offset := lerpf(-half_width, half_width, float(i) / float(SAMPLES - 1))
		_rays[i].position = Vector2(offset, -PROBE_LIFT)


## 目前有沒有畫出陰影（測試與量測用）。
func is_cast() -> bool:
	return _strength > 0.0


## 陰影在世界座標的範圍（沒有陰影時是空的）。
func world_rect() -> Rect2:
	if _strength <= 0.0:
		return Rect2()
	var width := _right - _left
	return Rect2(to_global(Vector2(_left + _shift, _surface - SURFACE_LIP)), Vector2(width, minf(width * FLATTEN, MAX_HEIGHT)))


func _physics_process(delta: float) -> void:
	# 最高的那個落點就是腳下的支撐面；高度相近的相鄰取樣組成支撐範圍。
	var surface := INF
	for ray in _rays:
		if ray.is_colliding():
			surface = minf(surface, to_local(ray.get_collision_point()).y)
	var strength := 0.0
	var left := 0.0
	var right := 0.0
	if surface != INF:
		var step := half_width * 2.0 / float(SAMPLES - 1)
		left = INF
		right = -INF
		for ray in _rays:
			if ray.is_colliding() and absf(to_local(ray.get_collision_point()).y - surface) <= SURFACE_TOLERANCE:
				left = minf(left, ray.position.x - step * 0.5)
				right = maxf(right, ray.position.x + step * 0.5)
		var height := clampf(surface / MAX_DROP, 0.0, 1.0)
		var shrink := lerpf(1.0, HEIGHT_SHRINK, height)
		var center := (left + right) * 0.5
		var half := (right - left) * 0.5 * shrink
		left = center - half
		right = center + half
		strength = pow(1.0 - height, 1.5)
	_light_timer -= delta
	var shift := _shift
	if _light_timer <= 0.0:
		_light_timer = LIGHT_REFRESH
		shift = _light_shift()
	if absf(left - _left) > REDRAW_EPSILON or absf(right - _right) > REDRAW_EPSILON or absf(surface - _surface) > REDRAW_EPSILON \
			or absf(strength - _strength) > 0.01 or absf(shift - _shift) > REDRAW_EPSILON:
		_left = left
		_right = right
		_surface = surface if surface != INF else 0.0
		_strength = strength
		_shift = shift
		queue_redraw()


## 最近一盞亮著的場景燈把陰影往反方向推多少像素；附近沒有燈就是 0。
func _light_shift() -> float:
	var frame := Engine.get_physics_frames()
	if frame - _lights_frame > int(LIGHT_REFRESH * Engine.physics_ticks_per_second) or _lights_frame < 0:
		_lights_frame = frame
		_lights.clear()
		for node: Node in get_tree().get_nodes_in_group(LightKit.SCENE_LIGHTS):
			var light := node as PointLight2D
			if light != null:
				_lights.append(light)
	var nearest := LIGHT_RANGE
	var result := 0.0
	for light in _lights:
		if not is_instance_valid(light) or not light.enabled or not light.visible:
			continue
		var offset := global_position - light.global_position
		var distance := offset.length()
		if distance < nearest:
			nearest = distance
			result = signf(offset.x) * LIGHT_SHIFT * (1.0 - distance / LIGHT_RANGE) * minf(1.0, absf(offset.x) / 24.0)
	return result


func _draw() -> void:
	if _strength <= 0.0 or _right - _left < 1.0:
		return
	var width := _right - _left
	var height := minf(width * FLATTEN, MAX_HEIGHT)
	var soft := LightKit.soft_texture()
	var top := _surface - SURFACE_LIP
	# 外圈淡、中間再疊一層較深的核心：7 像素高的地板條上只畫一層柔邊會淡到看不見。
	draw_texture_rect(soft, Rect2(_left + _shift, top, width, height), false, Color(0.0, 0.0, 0.0, BASE_ALPHA * _strength))
	var core := width * CORE_WIDTH
	draw_texture_rect(soft, Rect2(_left + _shift + (width - core) * 0.5, top + 1.0, core, height - 1.0), false,
			Color(0.0, 0.0, 0.0, BASE_ALPHA * _strength))
