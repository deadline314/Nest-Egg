class_name WormCreature
extends Node2D
## 蠕行生物：一個頭帶路，身體是一串關節沿著頭走過的路徑跟上（跟隨領頭），一張可重複的身體貼圖沿關節鋪成連續的帶狀網格。
## 動作全部是資料（art/creatures/<id>.json）：
##   行進波  關節沿路徑的法線方向左右擺（amp 幅度、wavelength 一個波長幾節、speed），越靠尾端擺得越大；
##   收縮波  關節間距沿身體起伏（pulse、pulse_speed），像蠕蟲一伸一縮；
##   入地    clip_y（地面高度）以下的身體被裁掉，鑽進地裡或從地裡冒出的樣子；
##   死亡    slack＝true 時關節失去張力，順著重力垂下並攤在地面。
## 節點的位置就是頭的位置；用法：setup("<id>")，每影格 animate(delta, 狀態名稱)。資料有錯時記錄具體位置並回傳 false。

const PATH := "res://art/creatures/%s.json"
const BLEND_SPEED := 5.0
const DEFAULT_STATE := {"amp": 0.8, "wavelength": 5.0, "speed": 3.0, "pulse": 0.1, "pulse_speed": 4.0}
const SAG_SPEED := 220.0
const BELLY_ROLL_SPEED := 6.0

var creature_id := ""
var state: StringName = &"idle"
## 地面高度（世界座標 y），以下的身體不畫；INF＝不裁。
var clip_y := INF
## 失去張力（死亡）。
var slack := false

var _head: Sprite2D
var _mesh: Polygon2D
var _pts := PackedVector2Array()
var _drawn := PackedVector2Array()
var _verts := PackedVector2Array()
var _uvs := PackedVector2Array()
var _belly_roll := PackedFloat32Array()
var _states: Dictionary = {}
var _params: Dictionary = DEFAULT_STATE.duplicate()
var _joints := 12
var _spacing := 5.0
var _width := 6.0
var _taper := 0.5
var _segment_len := 12.0
var _tex_size := Vector2.ONE
var _wave := 0.0
var _pulse := 0.0
var _started := false
var _head_heading := 0.0
var _neck_join := Vector2.ZERO
var _neck_width := 0.0


func setup(id: String) -> bool:
	creature_id = id
	var data := RigLibrary.load_json(PATH % id)
	if data.is_empty():
		return false
	var segment: Dictionary = data.get("segment", {})
	var seg_path := str(segment.get("texture", ""))
	if seg_path.is_empty() or not ResourceLoader.exists(seg_path):
		RigLibrary.report_once("worm_tex:" + id, "[WormCreature] %s 的身體貼圖不存在：%s" % [PATH % id, seg_path])
		return false
	var body: Dictionary = data.get("body", {})
	_joints = clampi(int(body.get("joints", 12)), 3, 40)
	_spacing = maxf(1.0, float(body.get("spacing", 5.0)))
	_width = maxf(1.0, float(body.get("width", 6.0)))
	_taper = clampf(float(body.get("taper", 0.5)), 0.0, 1.0)
	var tint := float(body.get("tint", 1.0))
	_segment_len = maxf(1.0, float(segment.get("length", 12.0)))
	_states = data.get("states", {})
	if not _states.has("idle"):
		RigLibrary.report_once("worm_idle:" + id, "[WormCreature] %s 沒有 idle 狀態，使用預設參數" % (PATH % id))
	var tex := LitTextures.load_texture(seg_path)
	_tex_size = tex.get_size()
	_mesh = Polygon2D.new()
	_mesh.name = "Body"
	_mesh.texture = tex
	_mesh.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var belly_material := ShaderMaterial.new()
	belly_material.shader = preload("res://game/creature/worm_belly.gdshader")
	_mesh.material = belly_material
	_mesh.top_level = true  # 頂點直接用世界座標
	_mesh.self_modulate = Color(tint, tint, tint, 1.0)
	add_child(_mesh)
	_build_head(data.get("head", {}), float(data.get("texture_scale", 0.25)))
	if _head != null:
		_head.self_modulate = Color(tint, tint, tint, 1.0)
	_pts.resize(_joints)
	_drawn.resize(_joints)
	_verts.resize(_joints * 2)
	_uvs.resize(_joints * 2)
	_belly_roll.resize(_joints)
	var polys: Array = []
	for i in _joints - 1:
		polys.append(PackedInt32Array([i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2]))
	_mesh.polygons = polys
	_params = (_states.get("idle", DEFAULT_STATE) as Dictionary).duplicate()
	for key: String in DEFAULT_STATE.keys():
		if not _params.has(key):
			_params[key] = DEFAULT_STATE[key]
	return true


func _build_head(head: Dictionary, scale_px: float) -> void:
	var path := str(head.get("texture", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_head = Sprite2D.new()
	_head.name = "Head"
	_head.texture = LitTextures.load_texture(path)
	_head.centered = false
	_head.scale = Vector2.ONE * scale_px
	# 頸部關節在貼圖左邊中央，旋轉中心放在那裡。
	_head.offset = Vector2(0.0, -_head.texture.get_size().y * 0.5)
	# Optional source-pixel calibration: overlap an opaque cross-section of the head.
	# A missing calibration retains the original left-edge attachment.
	_neck_join = RigLibrary.vec2(head.get("join"), Vector2(0.0, -_head.offset.y)) + _head.offset
	_neck_width = maxf(0.0, float(head.get("join_width", 0.0))) * scale_px
	_head.z_index = 1
	add_child(_head)


func set_state(new_state: StringName) -> void:
	state = new_state


## 把整條身體排在頭後面（出生或傳送後用）：沿 direction 的反方向直線排開。
func reset_trail(direction: Vector2) -> void:
	var back := -direction.normalized() if direction != Vector2.ZERO else Vector2.LEFT
	_head_heading = (-back).angle()
	_belly_roll.fill(1.0 if -back.x < 0.0 else 0.0)
	for i in _joints:
		_pts[i] = global_position + back * _spacing * float(i)
	_started = true


func animate(delta: float, new_state: StringName = &"") -> void:
	if _mesh == null:
		return
	if new_state != &"":
		set_state(new_state)
	if not _started:
		reset_trail(Vector2.LEFT)
	var target: Dictionary = DEFAULT_STATE.duplicate()
	var found: Variant = _states.get(String(state), null)
	if typeof(found) == TYPE_DICTIONARY:
		target.merge(found as Dictionary, true)
	elif not _states.is_empty():
		RigLibrary.report_once("worm_state:%s:%s" % [creature_id, state], "[WormCreature] %s 沒有狀態「%s」，改用預設參數" % [PATH % creature_id, state])
	var blend := 1.0 - exp(-BLEND_SPEED * delta)
	for key: String in target.keys():
		_params[key] = lerpf(float(_params.get(key, target[key])), float(target[key]), blend)
	_wave += delta * float(_params["speed"])
	_pulse += delta * float(_params["pulse_speed"])
	_follow(delta)
	_build_mesh(delta)


## 跟隨領頭：頭在節點位置，後面每個關節被拉到離前一個剛好一個間距（間距有收縮波起伏）。
func _follow(delta: float) -> void:
	_pts[0] = global_position
	var pulse := float(_params["pulse"])
	var wavelength := maxf(1.0, float(_params["wavelength"]))
	for i in range(1, _joints):
		var gap := _spacing * (1.0 + pulse * sin(TAU * float(i) / wavelength - _pulse))
		var from_prev := _pts[i] - _pts[i - 1]
		var dir := from_prev.normalized() if from_prev.length_squared() > 0.0001 else Vector2.LEFT
		var next := _pts[i - 1] + dir * gap
		if slack:
			next.y += SAG_SPEED * delta
			var floor_y := clip_y - _width * 0.25 if clip_y != INF else INF
			next.y = minf(next.y, floor_y)
		_pts[i] = next


## 關節 i 朝頭的方向（單位向量）。
func _toward_head(points: PackedVector2Array, i: int) -> Vector2:
	var d := (points[0] - points[1]) if i == 0 else (points[i - 1] - points[i])
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT


func _build_mesh(delta: float) -> void:
	var amp := float(_params["amp"])
	var wavelength := maxf(1.0, float(_params["wavelength"]))
	# 行進波：關節沿法線左右擺，越靠尾端越大。
	for i in _joints:
		var tail := float(i) / float(maxi(1, _joints - 1))
		var sway := 0.0 if slack else amp * _width * 0.5 * sin(TAU * float(i) / wavelength - _wave) * minf(1.0, tail * 2.0)
		_drawn[i] = _pts[i] + _toward_head(_pts, i).rotated(-PI * 0.5) * sway
	_place_head()
	var mirrored := _head != null and _head.scale.y < 0.0
	var total := 0.0
	for i in range(1, _joints):
		total += _drawn[i].distance_to(_drawn[i - 1])
	var covered := 0.0
	var last_visible := _drawn[0]
	for i in _joints:
		var p := _drawn[i]
		if i > 0:
			covered += p.distance_to(_drawn[i - 1])
		if clip_y != INF and p.y > clip_y:
			if i > 0 and _drawn[i - 1].y <= clip_y:
				p = _drawn[i - 1].lerp(p, clampf(inverse_lerp(_drawn[i - 1].y, p.y, clip_y), 0.0, 1.0))  # 穿過地面的那一節裁在地面上
			else:
				p = last_visible
		last_visible = p
		var normal := _toward_head(_drawn, i).rotated(-PI * 0.5)
		var half := _width * 0.5 * lerpf(1.0, 1.0 - _taper, float(i) / float(maxi(1, _joints - 1)))
		if _head != null and _neck_width > 0.0:
			# Blend the first two intervals from the opaque neck to the full body.
			# The trail and damage joints remain unchanged.
			half = lerpf(_neck_width * 0.5, half, clampf(covered / (_spacing * 2.0), 0.0, 1.0))
			if i == 0:
				p = _head.to_global(_neck_join)
				normal = Vector2.from_angle(_head_heading).rotated(-PI * 0.5)
				if clip_y != INF:
					p.y = minf(p.y, clip_y)
		_verts[i * 2] = p + normal * half
		_verts[i * 2 + 1] = p - normal * half
		# 貼圖往頭的方向增加，一節貼圖長 _segment_len 世界像素。
		var u := (total - covered) / _segment_len * _tex_size.x
		# The opaque head covers row zero. Exposed sections roll independently as
		# their own tangent turns; the head must never flip a still-forward tail.
		if i == 0:
			_belly_roll[i] = 1.0 if mirrored else 0.0
		else:
			var target_roll := 1.0 if _toward_head(_drawn, i).x < 0.0 else 0.0
			_belly_roll[i] = move_toward(_belly_roll[i], target_roll, maxf(0.0, delta) * BELLY_ROLL_SPEED)
		_uvs[i * 2] = Vector2(u, _tex_size.y * _belly_roll[i])
		_uvs[i * 2 + 1] = Vector2(u, _tex_size.y * (1.0 - _belly_roll[i]))
	_mesh.polygon = _verts
	_mesh.uv = _uvs


func _place_head() -> void:
	if _head == null:
		return
	var dir := _drawn[0] - _drawn[1]
	if dir.length_squared() > 0.0001:
		_head_heading = wrapf(lerp_angle(_head_heading, dir.angle(), 0.35), -PI, PI)
	_head.rotation = _head_heading
	_head.scale.y = absf(_head.scale.y) * (-1.0 if cos(_head_heading) < 0.0 else 1.0)
	_head.visible = clip_y == INF or global_position.y <= clip_y + 2.0


## 身體上的判定點（世界座標，每 stride 個關節一個，只含在地面以上的）填進 out（重複使用同一個陣列）。
func fill_hit_points(stride: int, out: PackedVector2Array) -> void:
	out.clear()
	if _mesh == null:
		return
	var i := 0
	while i < _joints:
		if clip_y == INF or _pts[i].y <= clip_y:
			out.append(_pts[i])
		i += maxi(1, stride)


func hit_radius() -> float:
	return _width * 0.5 + 1.0


func joint_count() -> int:
	return _joints


func joint_position(i: int) -> Vector2:
	return _pts[clampi(i, 0, _joints - 1)]
