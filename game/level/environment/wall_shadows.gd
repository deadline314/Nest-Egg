class_name WallShadows
extends Node2D
## 牆上的影子（BG-34）：主角、敵人與人物依最近的幾盞燈在背後的牆上投影。影子偏向遠離燈的那一側，離燈越遠偏得越多；
## 燈熄滅、閃爍或被關掉時影子跟著變；同時有兩盞燈就有兩個方向的影子。只畫在有背牆的地方，露天的天空沒有影子。
##
## 做法：會投影的東西另外畫進一張低解析度的輪廓圖（同一個世界、同一個鏡頭，只看得到標了 CASTER_LAYER 的東西），
## 這個節點把背牆的範圍再畫一次，用著色器依每盞燈往回取樣輪廓圖，把牆乘暗。
## 不在角色身上掛遮光體：那樣角色會被自己的影子蓋住，側視畫面裡影子也會變成橫掃整面牆的黑色楔形。
## 影子在牆那一層，不會畫在角色自己身上，也不會蓋住子彈、特效與介面。腳下的接觸陰影（ContactShadow）照舊。
##
## 誰會投影：加入 CASTER_GROUP 的節點（ContactShadow.attach 會自動加：有接觸陰影的角色就有牆上的影子）。
## 光影品質決定最多幾盞燈投影（LightQuality.wall_shadow_lights）；低品質是 0，整個關掉、輪廓圖也不畫。
## 沒有每影格配置：燈的候選清單每隔 RESCAN 秒整理一次，每影格只更新被選中的那幾盞的位置與亮度。

const SHADER := preload("res://game/level/environment/wall_shadows.gdshader")
const CASTER_GROUP := &"wall_shadow_casters"
## 輪廓圖只畫這個顯示層上的東西（第 10 層；其他東西都在預設的第 1 層）。
const CASTER_LAYER := 1 << 9
const MAX_LIGHTS := 4
## 輪廓圖相對於畫面的解析度。影子本來就是柔的，不需要全解析度。
const RESOLUTION := 0.5
## 角色離牆多遠，相對於燈離角色多遠（影子以燈為中心放大 1 + DEPTH 倍）。垂直方向放大得少：頭頂的燈照理把影子推到地板上，
## 那一部分已經有腳下的接觸陰影；牆上留的是往旁邊偏的部分。
const DEPTH := Vector2(0.6, 0.16)
## 貼近燈的地方再多放大多少倍：離燈越近影子越大。
const NEAR_BOOST := 0.7
## 影子的範圍是光池半徑的幾倍：光池邊緣的光已經很弱，但頭頂的燈照到地面附近常常就在邊緣，那裡的角色仍然要有影子。
const SHADOW_REACH := 1.35
## 光源周圍多少像素內的東西不投影：拿著或裝著這盞燈的角色與擺設不會被自己的燈投出一大片影子。
const OWN_RADIUS := 16.0
## 一盞正常亮度的燈在暗處的影子有多深；所有影子疊起來最多把牆壓暗多少。環境越亮影子越淡（著色器依環境光調整）。
const LIGHT_DARK := 0.85
const MAX_DARK := 0.82
## 亮度多少算「正常亮度」；太暗的燈不算（影子看不見）。
const FULL_ENERGY := 1.2
const MIN_ENERGY := 0.08
## 多久重新整理一次候選的燈與會投影的東西（秒）。
const RESCAN := 0.25
## 輪廓圖每幾格重畫一次。把角色再畫一遍是這個功能最花時間的部分；影子是柔的，慢一格看不出來。
## 鏡頭在兩次重畫之間的移動由著色器補回來（shift）。
const REDRAW_EVERY := 3
## 不會投影的子節點：接觸陰影、光錐、火花與介面元件不是「身體」。
const SKIPPED_GROUP := &"no_wall_shadow"

## 暫停（對照與量測用）：不畫影子，輪廓圖也不更新。
var suspended := false:
	set(value):
		suspended = value
		_refresh_state()

var _rects: Array[Rect2] = []
var _viewport: SubViewport
var _material: ShaderMaterial
## 著色器裡每盞燈的參數名稱。
const LIGHT_PARAMS: Array[StringName] = [&"light_0", &"light_1", &"light_2", &"light_3"]
const CONE_PARAMS: Array[StringName] = [&"cone_0", &"cone_1", &"cone_2", &"cone_3"]
const OMNI := Vector4(0.0, 0.0, -2.0, 0.0)
var _chosen: Array[PointLight2D] = []
var _scores := PackedFloat32Array()
var _since_scan := RESCAN
var _count := -1
var _frame := 0
## 輪廓圖上次重畫時鏡頭的位置與倍率。
var _drawn_origin := Vector2.ZERO
var _drawn_scale := Vector2.ZERO
var _ambient := -1.0
var _limit := -1
var _flagged: Dictionary[int, int] = {}


## walls＝背牆實際蓋住的範圍（世界座標，BackWallGeometry.support_rects）。沒有背牆的關卡不會有任何影子。
func setup(walls: Array[Rect2]) -> void:
	_rects = walls


func _ready() -> void:
	z_as_relative = false
	z_index = WorldLayers.DECOR
	_chosen.resize(MAX_LIGHTS)
	_scores.resize(MAX_LIGHTS)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"depth", DEPTH)
	_material.set_shader_parameter(&"near_boost", NEAR_BOOST)
	_material.set_shader_parameter(&"max_dark", MAX_DARK)
	_material.set_shader_parameter(&"light_dark", LIGHT_DARK)
	material = _material
	Settings.display_changed.connect(_apply_quality)
	_apply_quality()


## 目前有幾盞燈在投影（測試與量測用）。
func active_lights() -> int:
	return maxi(_count, 0) if visible else 0


## 輪廓圖（測試與量測用）；關閉時是 null。
func silhouette() -> ViewportTexture:
	return _viewport.get_texture() if _viewport != null else null


func is_enabled() -> bool:
	return _viewport != null


func _apply_quality() -> void:
	var limit := mini(LightQuality.wall_shadow_lights(), MAX_LIGHTS) if not _rects.is_empty() else 0
	if limit == _limit:
		return
	_limit = limit
	if limit > 0 and _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = "Silhouettes"
		_viewport.transparent_bg = true
		_viewport.disable_3d = true
		_viewport.use_hdr_2d = false
		_viewport.canvas_cull_mask = CASTER_LAYER
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_viewport.gui_disable_input = true
		add_child(_viewport)
		_viewport.world_2d = get_viewport().find_world_2d()
		_material.set_shader_parameter(&"silhouette", _viewport.get_texture())
		_since_scan = RESCAN
	elif limit == 0 and _viewport != null:
		_viewport.queue_free()
		_viewport = null
		_material.set_shader_parameter(&"silhouette", null)
		_material.set_shader_parameter(&"light_count", 0)
		_count = -1
	_refresh_state()
	queue_redraw()


func _refresh_state() -> void:
	var active := _limit > 0 and not suspended
	visible = active
	set_process(active)
	if _viewport != null:
		# 重畫由 _process 每隔幾格要求一次；停用時不再重畫。
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_drawn_scale = Vector2.ZERO


func _draw() -> void:
	for rect in _rects:
		draw_rect(rect, Color.WHITE)


func _process(delta: float) -> void:
	var view := get_viewport()
	var screen := Vector2(view.size)
	if screen.x < 1.0 or screen.y < 1.0:
		return
	# 輪廓圖和主畫面同一個鏡頭，只是解析度較低：畫面上的同一點在兩邊的位置（0～1）相同。
	var to_screen := view.get_final_transform() * view.get_canvas_transform()
	var size := Vector2i((screen * RESOLUTION).ceil())
	if _viewport.size != size:
		_viewport.size = size
		_material.set_shader_parameter(&"texel", Vector2.ONE / Vector2(size))
		_material.set_shader_parameter(&"aspect", screen.x / screen.y)
		_material.set_shader_parameter(&"own_radius", OWN_RADIUS * to_screen.get_scale().y / screen.y)
	_frame += 1
	if _frame % REDRAW_EVERY == 0 or not to_screen.get_scale().is_equal_approx(_drawn_scale):
		_viewport.canvas_transform = Transform2D(0.0, Vector2(RESOLUTION, RESOLUTION), 0.0, Vector2.ZERO) * to_screen
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_drawn_origin = to_screen.origin
		_drawn_scale = to_screen.get_scale()
	_material.set_shader_parameter(&"shift", (to_screen.origin - _drawn_origin) / screen)
	_since_scan += delta
	if _since_scan >= RESCAN:
		_since_scan = 0.0
		_flag_casters()
		_choose_lights(to_screen, screen)
	var count := 0
	var pixel_scale := to_screen.get_scale().y
	for index in _limit:
		var light := _chosen[index]
		if light == null or not is_instance_valid(light) or not light.is_inside_tree() or not light.enabled or not light.is_visible_in_tree():
			continue
		if light.energy <= MIN_ENERGY:
			continue
		var strength := clampf(light.energy / FULL_ENERGY, 0.0, 1.0)
		var at := to_screen * light.global_position / screen
		var reach := float(light.get_meta(LightKit.META_REACH, 0.0))
		var radius := reach if reach > 0.0 else light.texture_scale * LightKit.TEXTURE_SIZE * 0.5
		_material.set_shader_parameter(LIGHT_PARAMS[count], Vector4(at.x, at.y, radius * SHADOW_REACH * pixel_scale / screen.y, strength))
		if light.is_in_group(LightKit.AIMED_LIGHTS):
			var aim := Vector2.from_angle(light.global_rotation)
			_material.set_shader_parameter(CONE_PARAMS[count], Vector4(aim.x, aim.y, float(light.get_meta(LightKit.META_HALF_ANGLE, PI)), 0.0))
		else:
			_material.set_shader_parameter(CONE_PARAMS[count], OMNI)
		count += 1
	if count != _count:
		_count = count
		_material.set_shader_parameter(&"light_count", count)
	if not is_equal_approx(LightKit.ambient_luma, _ambient):
		_ambient = LightKit.ambient_luma
		_material.set_shader_parameter(&"ambient", _ambient)


## 從場景裡的燈（場景燈、敵人的光、擺設的燈）與朝某個方向照的燈（槍燈）挑出對畫面影響最大的幾盞。
func _choose_lights(to_screen: Transform2D, screen: Vector2) -> void:
	for index in MAX_LIGHTS:
		_chosen[index] = null
		_scores[index] = 0.0
	var centre := screen * 0.5
	var reach_limit := centre.length()
	var pixel_scale := to_screen.get_scale().y
	for group: StringName in [LightKit.SCENE_LIGHTS, LightKit.AIMED_LIGHTS]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var light := node as PointLight2D
			if light == null or not light.enabled or not light.is_visible_in_tree() or _chosen.has(light):
				continue
			var reach := float(light.get_meta(LightKit.META_REACH, 0.0))
			var radius := (reach if reach > 0.0 else light.texture_scale * LightKit.TEXTURE_SIZE * 0.5) * pixel_scale
			var at := to_screen * light.global_position
			# 整個光池都在畫面外的燈不佔名額。
			if at.x < -radius or at.y < -radius or at.x > screen.x + radius or at.y > screen.y + radius:
				continue
			# 光池大、離畫面中心近、亮的燈優先：擺設上的小燈不該把頭頂的主燈擠掉。
			_offer(light, maxf(light.energy, 0.3) * radius * clampf(1.0 - at.distance_to(centre) / (radius + reach_limit), 0.0, 1.0))


## 把一盞燈放進依分數排序的前幾名。
func _offer(light: PointLight2D, score: float) -> void:
	for index in _limit:
		if score > _scores[index]:
			for shift in range(_limit - 1, index, -1):
				_chosen[shift] = _chosen[shift - 1]
				_scores[shift] = _scores[shift - 1]
			_chosen[index] = light
			_scores[index] = score
			return


## 讓會投影的東西出現在輪廓圖裡：它自己、它的上層節點與它底下的身體都要在 CASTER_LAYER 上。
## 角色的零件可能在生成之後才換（換外觀、換武器），所以定期重看一次；子節點數沒變的就不重做。
func _flag_casters() -> void:
	for node: Node in get_tree().get_nodes_in_group(CASTER_GROUP):
		var caster := node as CanvasItem
		if caster == null:
			continue
		var id := caster.get_instance_id()
		var count := _descendant_count(caster)
		if _flagged.get(id, -1) == count:
			continue
		_flagged[id] = count
		var parent := caster.get_parent()
		while parent != null:
			if parent is CanvasItem:
				(parent as CanvasItem).visibility_layer |= CASTER_LAYER
			parent = parent.get_parent()
		_flag_branch(caster)
	if _flagged.size() > 256:
		# 離開關卡的角色不留紀錄。
		for id: int in _flagged.keys():
			if not is_instance_id_valid(id):
				_flagged.erase(id)


func _flag_branch(item: CanvasItem) -> void:
	item.visibility_layer |= CASTER_LAYER
	for child: Node in item.get_children():
		var branch := child as CanvasItem
		if branch == null or branch is ContactShadow or branch is LightShaft or branch is Control or branch is GPUParticles2D \
				or branch is CPUParticles2D or branch.is_in_group(SKIPPED_GROUP):
			continue
		_flag_branch(branch)


static func _descendant_count(node: Node) -> int:
	var total := node.get_child_count()
	for child: Node in node.get_children():
		total += _descendant_count(child)
	return total
