class_name ChainCreature
extends Node2D
## 觸手生物：中央本體加數條觸手。每條觸手是一串骨頭，貼圖是一張連續的圖，用網格變形貼在骨頭鏈上（Polygon2D＋Skeleton2D），
## 彎曲處沒有縫，才有「軟」的感覺。動作與組裝全部是資料（art/creatures/<id>.json）：
##   組裝    本體與單條觸手兩張圖；tentacles[] 每條有掛點 anchor、角度 angle、縮放 scale、鏡像 mirror、色差 tint、生命 life、角色 role
##   行進波  沿骨頭鏈往尖端傳遞的正弦波（amp 幅度、wavelength 一個波長跨幾節、speed 傳遞速度），越靠近尖端擺得越大；
##   收縮波  寬度（pulse）與長度（stretch）沿鏈起伏，像蠕蟲一伸一縮；extend 整條伸縮（縮回、伸出）；
##   鞭擊    state＝lash 時，波的包絡由根部傳到尖端（先捲起蓄力、再甩出去）；aim_weight 讓自由觸手朝 set_aim 的方向指；
##   落腳    role＝leg 的觸手尖端是腳：離落腳點太遠就抬起、前伸、落地釘住，兩組交替；身體隨腳高起伏、落地震一下；
##   斷肢    每條觸手有自己的生命（damage_tentacle），打斷後整條飛出，步態變慢、身體變低；全部斷光露出核心（core_exposed）。
## 狀態之間的參數會平滑過渡。用法：setup("<id>")，每影格 animate(delta, 狀態名稱, 速度)。
## 資料有錯（缺貼圖、骨頭數不對、狀態不存在）時記錄具體位置並用安全的預設值，不會崩潰。

signal tentacle_severed(index: int)
signal foot_planted(index: int, at: Vector2)
signal core_exposed

const PATH := "res://art/creatures/%s.json"
const BLEND_SPEED := 6.0
## 受擊波：同時最多幾道、傳遞速度（節／秒）、壽命（秒）、波寬（節）。
const MAX_IMPULSES := 4
const IMPULSE_SPEED := 14.0
const IMPULSE_LIFE := 0.7
const IMPULSE_WIDTH := 1.6
## 斷肢飛出的速度。
const SEVER_SPEED := Vector2(110.0, -140.0)
const FLASH_TIME := 0.07
const FLASH_GAIN := 0.9
const DEFAULT_LIFE := 3
const DEFAULT_STATE := {"amp": 0.15, "wavelength": 7.0, "speed": 1.6, "pulse": 0.05, "stretch": 0.02, "pulse_speed": 2.0, "curl": 0.0, "bob": 0.5, "duration": 0.8, "extend": 1.0, "aim_weight": 0.0, "swell": 0.0, "whip": 0.0, "swell_amp": 0.0, "swell_freq": 1.0}
const DEFAULT_GAIT := {"stance": 0.0, "step_time": 0.3, "lift": 6.0, "trigger": 7.0, "lead": 0.5, "full_speed": 80.0, "dip": 1.2, "groups": 2, "wave": 0.0}
## 腿的姿勢：根部到腳的弦長上限比例（超過就必須換步）、碰不到時的最小腳步距離。
const REACH_LIMIT := 0.96
const DIP_RECOVER := 9.0

var creature_id := ""
var state: StringName = &"idle"
var state_time := 0.0
## -1／1：面向。改的是自身的水平縮放，落腳點是世界座標所以不會跟著翻。
var facing := 1:
	set(value):
		facing = -1 if value < 0 else 1
		scale = Vector2(float(facing) * body_scale, body_scale)
## 整體縮放（小隻的同種生物）。落腳距離會跟著換算。
var body_scale := 1.0:
	set(value):
		body_scale = maxf(0.1, value)
		scale = Vector2(float(facing) * body_scale, body_scale)
## 查詢地面高度：func(world_x: float) -> float（世界座標 y）；沒設定時用這個節點自己的高度當地面。
var ground_probe: Callable = Callable()

var _rig: Node2D
var _skeleton: Skeleton2D
var _body: Sprite2D
var _body_rest := Vector2.ZERO
var _body_scale_rest := Vector2.ONE
var _body_size := Vector2.ZERO
var _chains: Array[Dictionary] = []
var _states: Dictionary = {}
var _params: Dictionary = DEFAULT_STATE.duplicate()
var _gait: Dictionary = DEFAULT_GAIT.duplicate()
var _combat: Dictionary = {}
var _wave := 0.0
var _pulse := 0.0
var _time := 0.0
var _segments := 8
var _aim := 0.0
var _mean_angle := 0.0
var _stance_now := 0.0
var _dip := 0.0
var _speed_ratio := 0.0
var _exposed := false
## 受擊波：{chain, at（骨頭序）, amp, age} 的固定容量陣列（重複使用，不每影格配置）。
var _impulses: Array[Dictionary] = []


## 建立身體、骨頭與網格。回傳 false 代表資料無法使用（已記錄原因）。
func setup(id: String) -> bool:
	creature_id = id
	var data := RigLibrary.load_json(PATH % id)
	if data.is_empty():
		return false
	var tentacle: Dictionary = data.get("tentacle", {})
	var tex_path := str(tentacle.get("texture", ""))
	if tex_path.is_empty() or not ResourceLoader.exists(tex_path):
		RigLibrary.report_once("creature_tex:" + id, "[ChainCreature] %s 的觸手貼圖不存在：%s" % [PATH % id, tex_path])
		return false
	var tex := LitTextures.load_texture(tex_path)
	_segments = clampi(int(tentacle.get("segments", 8)), 2, 24)
	_states = data.get("states", {})
	if not _states.has("idle"):
		RigLibrary.report_once("creature_idle:" + id, "[ChainCreature] %s 沒有 idle 狀態，使用預設參數" % (PATH % id))
	_gait.merge(data.get("gait", {}), true)
	_combat = data.get("combat", {})
	_rig = Node2D.new()
	_rig.name = "Rig"
	add_child(_rig)
	var scale_px := float(data.get("texture_scale", 0.25))
	_build_body(data.get("body", {}), scale_px)
	_skeleton = Skeleton2D.new()
	_skeleton.name = "Skeleton"
	_rig.add_child(_skeleton)
	var list: Variant = data.get("tentacles", [])
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		RigLibrary.report_once("creature_list:" + id, "[ChainCreature] %s 沒有 tentacles" % (PATH % id))
		return true
	for entry: Variant in list:
		if typeof(entry) == TYPE_DICTIONARY:
			_add_tentacle(entry as Dictionary, tex, tentacle)
	for chain in _chains:
		_mean_angle += float(chain["angle"]) / float(_chains.size())
	_params = (_states.get("idle", DEFAULT_STATE) as Dictionary).duplicate()
	for key: String in DEFAULT_STATE.keys():
		if not _params.has(key):
			_params[key] = DEFAULT_STATE[key]
	_stance_now = float(_gait["stance"])
	return true


func _build_body(body: Dictionary, scale_px: float) -> void:
	var path := str(body.get("texture", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_body = Sprite2D.new()
	_body.texture = LitTextures.load_texture(path)
	_body.centered = false
	_body.scale = Vector2.ONE * scale_px
	_body.position = RigLibrary.vec2(body.get("offset"), Vector2(-20, -16))
	_body.z_index = 0
	_body_rest = _body.position
	_body_scale_rest = _body.scale
	_body_size = _body.texture.get_size() * _body.scale
	_rig.add_child(_body)


static func _tint_of(value: Variant) -> Color:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		var a := value as Array
		return Color(float(a[0]), float(a[1]), float(a[2]), 1.0)
	var k := float(value) if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT else 1.0
	return Color(k, k, k, 1.0)


## 一條觸手：N 根骨頭串成一條鏈（朝下為 0 度，負角往前），加上沿鏈的網格，頂點依到各骨頭的位置分配權重。
func _add_tentacle(entry: Dictionary, tex: Texture2D, defaults: Dictionary) -> void:
	var segments := clampi(int(entry.get("segments", defaults.get("segments", _segments))), 2, 24)
	var width := float(entry.get("width", defaults.get("width", 16.0)))
	var length := float(entry.get("length", defaults.get("length", 90.0)))
	var s := float(entry.get("scale", 1.0))
	var anchor := RigLibrary.vec2(entry.get("anchor"))
	var angle := deg_to_rad(float(entry.get("angle", 0.0)))
	var seg_len := length * s / float(segments)
	var index := _chains.size()
	var bones: Array[Bone2D] = []
	var parent: Node = _skeleton
	for i in segments:
		var bone := Bone2D.new()
		bone.name = "T%d_%d" % [index, i]
		var rest_pos := anchor if i == 0 else Vector2(0, seg_len)
		var rest_rot := angle if i == 0 else 0.0
		bone.position = rest_pos
		bone.rotation = rest_rot
		bone.rest = Transform2D(rest_rot, rest_pos)
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(seg_len)
		bone.set_bone_angle(PI * 0.5)
		parent.add_child(bone)
		bones.append(bone)
		parent = bone
	var geometry := ChainMesh.build_geometry(tex.get_size(), segments, width * s, seg_len, anchor, angle, bool(entry.get("mirror", false)))
	var topology := ChainMesh.topology(segments)
	var polygon := Polygon2D.new()
	polygon.name = "Mesh%d" % index
	polygon.texture = tex
	polygon.polygon = geometry["verts"]
	polygon.uv = geometry["uvs"]
	polygon.polygons = topology["polys"]
	polygon.z_index = int(entry.get("z", 0))
	var tint := _tint_of(entry.get("tint", 1.0))
	polygon.self_modulate = tint
	_rig.add_child(polygon)
	polygon.skeleton = polygon.get_path_to(_skeleton)
	var weights: Array[PackedFloat32Array] = topology["weights"]
	for i in segments:
		polygon.add_bone(polygon.get_path_to(bones[i]), weights[i])
	var is_leg := str(entry.get("role", "free")) == "leg"
	var life := maxi(1, int(entry.get("life", DEFAULT_LIFE)))
	_chains.append({
		"index": index, "bones": bones, "angle": angle, "phase": float(entry.get("phase", 0.0)), "seg_len": seg_len, "scale": s,
		"polygon": polygon, "tint": tint, "width": width * s, "anchor": anchor,
		"life": life, "max_life": life, "flash": 0.0,
		"leg": is_leg, "free": false, "foot_x": float(entry.get("foot", anchor.x)), "foot_planted": false,
		"foot": FootGait.new(),
	})
	(_chains[index]["foot"] as FootGait).group = int(entry.get("group", index % maxi(1, int(_gait["groups"]))))


## 某個狀態的持續時間參數（鞭擊的進度用；預覽工具也用）。
func state_duration(state_name: StringName) -> float:
	var found: Variant = _states.get(String(state_name), null)
	return float((found as Dictionary).get("duration", DEFAULT_STATE["duration"])) if typeof(found) == TYPE_DICTIONARY else float(DEFAULT_STATE["duration"])


func set_state(new_state: StringName) -> void:
	if new_state != state:
		state = new_state
		state_time = 0.0


## 自由觸手（含暫時放開步態的腿）指向的方向，世界座標的一個點。
func set_aim_point(world_point: Vector2) -> void:
	var local := _rig.to_local(world_point) if _rig != null else to_local(world_point)
	_aim = ChainPose.heading_of(local.normalized()) if local.length() > 0.001 else 0.0


## 每影格呼叫：狀態參數平滑過渡，行進波與收縮波往前走，腿落腳，更新每根骨頭的角度、寬度與長度。
## velocity 是敵人的速度（步態與起伏用）。
func animate(delta: float, new_state: StringName = &"", velocity := Vector2.ZERO) -> void:
	if _rig == null:
		return
	if new_state != &"":
		set_state(new_state)
	_time += delta
	state_time += delta
	var target: Dictionary = DEFAULT_STATE.duplicate()
	var found: Variant = _states.get(String(state), null)
	if typeof(found) == TYPE_DICTIONARY:
		target.merge(found as Dictionary, true)
	elif not _states.is_empty():
		RigLibrary.report_once("creature_state:%s:%s" % [creature_id, state], "[ChainCreature] %s 沒有狀態「%s」，改用預設參數" % [PATH % creature_id, state])
	var blend := 1.0 - exp(-BLEND_SPEED * delta)
	for key: String in target.keys():
		_params[key] = lerpf(float(_params.get(key, target[key])), float(target[key]), blend)
	_wave += delta * float(_params["speed"])
	_pulse += delta * float(_params["pulse_speed"])
	var lashing := state == &"lash" or float(target["whip"]) > 0.5
	var progress := clampf(state_time / maxf(0.05, float(target["duration"])), 0.0, 1.0)
	for impulse in _impulses:
		impulse["age"] = float(impulse["age"]) + delta
	_update_gait(delta, velocity)
	for chain: Dictionary in _chains:
		if chain.get("severed", false):
			continue
		_tick_flash(chain, delta)
		if bool(chain["leg"]) and not bool(chain["free"]):
			_pose_leg(chain)
		else:
			_pose_chain(chain, lashing, progress)
	_update_body(delta, blend)


func _update_body(delta: float, blend: float) -> void:
	var ratio := _alive_ratio()
	var stance := float(_gait["stance"]) * (0.55 + 0.45 * ratio)
	_stance_now = lerpf(_stance_now, stance, blend)
	_dip = move_toward(_dip, 0.0, DIP_RECOVER * delta)
	var bob := sin(_time * 2.1) * float(_params["bob"])
	_rig.position = Vector2(0.0, -_stance_now + bob + _dip)
	if _body != null:
		# 鼓起（swell）：以底邊中心為準放大，預兆用。
		var swell := float(_params["swell"]) + float(_params["swell_amp"]) * sin(_time * TAU * float(_params["swell_freq"]))
		var grow := Vector2(1.0 + swell * 0.5, 1.0 + swell)
		_body.scale = _body_scale_rest * grow
		_body.position = _body_rest + Vector2(_body_size.x * (1.0 - grow.x) * 0.5, _body_size.y * (1.0 - grow.y))
		if _exposed:
			var glow := 1.15 + 0.2 * sin(_time * 7.0)
			_body.self_modulate = Color(glow, 0.85, glow, 1.0)


func _tick_flash(chain: Dictionary, delta: float) -> void:
	var left := float(chain["flash"])
	if left <= 0.0:
		return
	left = maxf(0.0, left - delta)
	chain["flash"] = left
	var k := 1.0 + FLASH_GAIN * left / FLASH_TIME
	var tint: Color = chain["tint"]
	(chain["polygon"] as Polygon2D).self_modulate = Color(tint.r * k, tint.g * k, tint.b * k, 1.0)


# ---------------------------------------------------------------------------
# 落腳步行
# ---------------------------------------------------------------------------

func _ground_y(world_x: float) -> float:
	return float(ground_probe.call(world_x)) if ground_probe.is_valid() else global_position.y


## 兩組腿交替：腳離理想落點太遠就換步，但同一時間不讓另一組的腿一起離地（碰不到時例外）。
func _update_gait(delta: float, velocity: Vector2) -> void:
	var speed := absf(velocity.x)
	var full := maxf(1.0, float(_gait["full_speed"]))
	_speed_ratio = clampf(speed / full, 0.0, 1.0)
	var ratio := _alive_ratio()
	var step_time := lerpf(float(_gait["step_time"]), float(_gait["step_time"]) * 0.6, _speed_ratio) / (0.5 + 0.5 * ratio)
	var moving := speed > 6.0
	var k := absf(global_scale.y)  # 世界座標與本地像素的比例（被放大時，距離要換算）
	for chain: Dictionary in _chains:
		if not bool(chain["leg"]) or chain.get("severed", false) or bool(chain["free"]):
			continue
		var gait: FootGait = chain["foot"]
		var rest_x := global_position.x + float(facing) * float(chain["foot_x"]) * k
		if not bool(chain["foot_planted"]):
			gait.place(Vector2(rest_x, _ground_y(rest_x)))
			chain["foot_planted"] = true
			continue
		if gait.advance(delta):
			_dip += float(_gait["dip"])
			foot_planted.emit(int(chain["index"]), gait.foot)
			continue
		if gait.stepping:
			continue
		var limit := float(_gait["trigger"]) * k * (1.0 if moving else 1.8)
		var root_world := _rig.to_global(chain["anchor"] as Vector2)
		var reach := float(chain["seg_len"]) * float((chain["bones"] as Array).size()) * REACH_LIMIT * k
		var overreach := gait.foot.distance_to(root_world) > reach
		if absf(gait.foot.x - rest_x) <= limit and not overreach:
			continue
		if not overreach and _other_group_stepping(gait.group):
			continue
		var to_x := rest_x + velocity.x * float(_gait["lead"]) * step_time
		gait.begin_step(Vector2(to_x, _ground_y(to_x)), step_time, float(_gait["lift"]) * k)


func _other_group_stepping(group: int) -> bool:
	for chain: Dictionary in _chains:
		if bool(chain["leg"]) and not chain.get("severed", false) and not bool(chain["free"]):
			var other: FootGait = chain["foot"]
			if other.stepping and other.group != group:
				return true
	return false


func _alive_ratio() -> float:
	return float(alive_tentacles()) / float(maxi(1, _chains.size()))


## 腿的姿勢：整條鏈彎成一道弧，尖端落在釘住（或跨步中）的腳上；膝蓋往外上方抬起。
func _pose_leg(chain: Dictionary) -> void:
	var bones: Array[Bone2D] = chain["bones"]
	var n := bones.size()
	var gait: FootGait = chain["foot"]
	var anchor: Vector2 = chain["anchor"]
	var chord := _rig.to_local(gait.foot) - anchor
	var outward := signf(anchor.x) if absf(anchor.x) > 1.0 else signf(chord.x)
	var rotations := ChainPose.arc(chord, float(chain["seg_len"]), n, Vector2(outward * 0.6, -1.0))
	var seg_len: float = chain["seg_len"]
	var pulse := float(_params["pulse"])
	var wobble := float(_gait["wave"])
	var previous_pulse := 1.0
	for i in n:
		var a := rotations[i]
		if wobble > 0.0:
			a += wobble * sin(TAU * float(i) / maxf(1.0, float(_params["wavelength"])) - _wave + float(chain["phase"])) * float(i) / float(n)
		a += _impulse_bend(chain, i)
		var bone := bones[i]
		bone.rotation = a
		var absolute := 1.0 + pulse * 0.5 * sin(TAU * float(i) / (float(_params["wavelength"]) * 0.7) - _pulse + float(chain["phase"]))
		bone.scale = Vector2(absolute / previous_pulse, 1.0)
		previous_pulse = absolute
		if i > 0:
			bone.position = Vector2(0, seg_len)


func _pose_chain(chain: Dictionary, lashing: bool, progress: float) -> void:
	var bones: Array[Bone2D] = chain["bones"]
	var n := bones.size()
	var phase: float = chain["phase"]
	var amp := float(_params["amp"])
	var wavelength := maxf(1.0, float(_params["wavelength"]))
	var pulse := float(_params["pulse"])
	var stretch := float(_params["stretch"])
	var curl := float(_params["curl"])
	var extend := float(_params["extend"])
	var seg_len: float = chain["seg_len"]
	var aim_offset := float(_params["aim_weight"]) * (_aim - _mean_angle)
	var previous_pulse := 1.0
	for i in n:
		var reach := float(i) / float(maxi(1, n - 1))
		var envelope := 0.35 + 0.65 * reach  # 越靠近尖端擺得越大
		var a := amp * envelope * sin(TAU * float(i) / wavelength - _wave + phase) + curl * (0.4 + reach)
		if lashing:
			# 鞭擊：先往後捲起蓄力（前 35%），再把一個「向前甩」的脈衝從根部送到尖端。
			var windup := smoothstep(0.0, 0.35, progress) * (1.0 - smoothstep(0.35, 0.5, progress))
			var front := smoothstep(0.35, 1.0, progress) * float(n + 3)
			var bump := exp(-pow((float(i) - front) / 2.0, 2.0))
			a += 0.5 * windup * (0.5 + reach) - 1.1 * bump * (0.4 + reach)
		a += _impulse_bend(chain, i)
		var bone := bones[i]
		bone.rotation = (float(chain["angle"]) + aim_offset if i == 0 else 0.0) + a
		var absolute := 1.0 + pulse * sin(TAU * float(i) / (wavelength * 0.7) - _pulse + phase)
		bone.scale = Vector2(absolute / previous_pulse, 1.0)  # 寬度起伏：子骨頭補償父骨頭的縮放，不會逐節累積
		previous_pulse = absolute
		if i > 0:
			bone.position = Vector2(0, seg_len * extend * (1.0 + stretch * sin(TAU * float(i) / wavelength - _pulse * 1.1 + phase + 1.2)))


# ---------------------------------------------------------------------------
# 受擊波
# ---------------------------------------------------------------------------

## 被打到：在離 world_point 最近的那條觸手的最近一節產生一道波，往兩端傳（strength 約 0.3 輕～1.2 重）。
## 已有最大數量的波時，覆蓋最舊的一道。
func hit_wave(world_point: Vector2, strength: float) -> void:
	var best_chain := -1
	var best_bone := 0
	var best_distance := INF
	for c in _chains.size():
		if _chains[c].get("severed", false):
			continue
		var bones: Array[Bone2D] = _chains[c]["bones"]
		for i in bones.size():
			var d := bones[i].global_position.distance_squared_to(world_point)
			if d < best_distance:
				best_distance = d
				best_chain = c
				best_bone = i
	if best_chain < 0:
		return
	var slot := -1
	for k in _impulses.size():
		if float(_impulses[k]["age"]) >= IMPULSE_LIFE:
			slot = k
			break
	if slot < 0:
		if _impulses.size() < MAX_IMPULSES:
			_impulses.append({})
			slot = _impulses.size() - 1
		else:
			slot = 0
			for k in _impulses.size():
				if float(_impulses[k]["age"]) > float(_impulses[slot]["age"]):
					slot = k
	_impulses[slot] = {"chain": best_chain, "at": best_bone, "amp": clampf(strength, 0.0, 2.0) * 0.9, "age": 0.0}


## 這條觸手在第 i 節受到的受擊波彎曲量：波包從受擊點往兩端以 IMPULSE_SPEED 傳，邊傳邊衰減。
func _impulse_bend(chain: Dictionary, i: int) -> float:
	var total := 0.0
	for impulse in _impulses:
		var age: float = impulse["age"]
		if age >= IMPULSE_LIFE or int(impulse["chain"]) != int(chain["index"]):
			continue
		var front := age * IMPULSE_SPEED
		var distance := absf(float(i) - float(impulse["at"]))
		var packet := exp(-pow((distance - front) / IMPULSE_WIDTH, 2.0))
		var decay := 1.0 - age / IMPULSE_LIFE
		total += float(impulse["amp"]) * packet * decay * sin(age * 40.0 - distance * 1.3)
	return total


# ---------------------------------------------------------------------------
# 斷肢
# ---------------------------------------------------------------------------

## 對第 index 條觸手造成傷害：先閃一下並產生受擊波，生命歸零就打斷。回傳 true 代表這一擊把它打斷了。
func damage_tentacle(index: int, amount: int, impulse := Vector2.ZERO) -> bool:
	if index < 0 or index >= _chains.size() or _chains[index].get("severed", false):
		return false
	var chain := _chains[index]
	chain["life"] = int(chain["life"]) - maxi(0, amount)
	chain["flash"] = FLASH_TIME
	if int(chain["life"]) <= 0:
		return sever(index, impulse)
	return false


## 打斷第 index 條觸手：整條離開身體飛出去（用脫落零件的物件池，場上已滿就只消失），之後不再擺動。
## impulse 是飛出的方向（世界座標，會被正規化）。回傳 false 代表這條已經斷了或編號不存在。
func sever(index: int, impulse := Vector2.ZERO) -> bool:
	if index < 0 or index >= _chains.size() or _chains[index].get("severed", false):
		return false
	var chain := _chains[index]
	chain["severed"] = true
	chain["life"] = 0
	var polygon: Polygon2D = chain["polygon"]
	polygon.visible = false
	var tex := polygon.texture
	if tex != null:
		var verts := polygon.polygon
		var uvs := polygon.uv
		var x_axis := (verts[2] - verts[0]) / (uvs[2].x - uvs[0].x)
		var rows := verts.size() / ChainMesh.COLUMNS
		var last := (rows - 1) * ChainMesh.COLUMNS
		var y_axis := (verts[last] - verts[0]) / (uvs[last].y - uvs[0].y)
		var origin: Vector2 = verts[0] - x_axis * uvs[0].x - y_axis * uvs[0].y
		var root: Bone2D = (chain["bones"] as Array[Bone2D])[0]
		var source := root.global_transform * root.rest.affine_inverse() * Transform2D(x_axis, y_axis, origin)
		var dir := impulse.normalized() if impulse != Vector2.ZERO else Vector2.RIGHT
		var debris := RigDebris.spawn(tex, source, Vector2.ZERO, Vector2(dir.x * SEVER_SPEED.x, SEVER_SPEED.y) * randf_range(0.8, 1.2))
		if debris != null and not Fx.add_world_node(debris):
			debris.cancel()
	tentacle_severed.emit(index)
	if alive_tentacles() == 0 and not _exposed:
		_exposed = true
		core_exposed.emit()
	return true


## 暫時放開（或收回）一條腿的步態：放開的腿像自由觸手一樣擺動、朝 set_aim_point 指（出招用）。收回時從現在的位置重新找落腳點。
func set_free(index: int, free: bool) -> void:
	if index < 0 or index >= _chains.size() or _chains[index].get("severed", false):
		return
	var chain := _chains[index]
	if bool(chain["free"]) != free:
		chain["free"] = free
		chain["foot_planted"] = false


## 全部的腿都放開步態（死亡：觸手失去張力軟下去）。
func go_limp() -> void:
	for chain in _chains:
		if bool(chain["leg"]):
			chain["free"] = true


func alive_tentacles() -> int:
	var count := 0
	for chain in _chains:
		if not chain.get("severed", false):
			count += 1
	return count


func is_alive(index: int) -> bool:
	return index >= 0 and index < _chains.size() and not _chains[index].get("severed", false)


func is_leg(index: int) -> bool:
	return index >= 0 and index < _chains.size() and bool(_chains[index]["leg"])


func is_exposed() -> bool:
	return _exposed


## 剩餘觸手比例對應的移動速度倍率（斷得越多越慢，最慢 0.35）。
func speed_scale() -> float:
	return lerpf(0.35, 1.0, _alive_ratio()) if _chains.size() > 0 else 1.0


## 資料裡的戰鬥設定（combat 段）：armor_scale（觸手還在時本體的傷害倍率）、exposed_scale（核心露出後的倍率）等。
func combat_value(key: String, fallback: float) -> float:
	return float(_combat.get(key, fallback))


# ---------------------------------------------------------------------------
# 判定
# ---------------------------------------------------------------------------

## 每條觸手尖端的世界座標（傷害判定與落點預兆用）；斷掉的那條回傳 Vector2.INF。
func tip_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for chain: Dictionary in _chains:
		out.append(tip_of(int(chain["index"])))
	return out


func tip_of(index: int) -> Vector2:
	if not is_alive(index):
		return Vector2.INF
	var bones: Array[Bone2D] = _chains[index]["bones"]
	return bones[bones.size() - 1].to_global(Vector2(0, float(_chains[index]["seg_len"])))


## 把第 index 條觸手上的判定點（每 stride 節一個，加尖端）的世界座標填進 out（重複使用同一個陣列，不每影格配置）。
func fill_hit_points(index: int, stride: int, out: PackedVector2Array) -> void:
	out.clear()
	if not is_alive(index):
		return
	var bones: Array[Bone2D] = _chains[index]["bones"]
	var i := stride - 1
	while i < bones.size() - 1:
		out.append(bones[i].global_position)
		i += maxi(1, stride)
	out.append(tip_of(index))


## 判定圓的半徑（世界像素，含整體縮放）：觸手寬度的一半再放寬一點。
func hit_radius(index: int) -> float:
	return (float(_chains[index]["width"]) * 0.5 + 1.5) * body_scale if index >= 0 and index < _chains.size() else 0.0


## 簡化的受擊膠囊：觸手 55% 處與尖端（世界座標）。
func capsule_of(index: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not is_alive(index):
		return out
	var bones: Array[Bone2D] = _chains[index]["bones"]
	out.append(bones[mini(bones.size() - 1, int(float(bones.size()) * 0.55))].global_position)
	out.append(tip_of(index))
	return out


## 每條觸手有幾根骨頭。
func bone_count() -> int:
	return _segments


func tentacle_count() -> int:
	return _chains.size()


## 第 index 條觸手的第 i 根骨頭（測試與判定用）。
func bone_of(index: int, i: int) -> Bone2D:
	if index < 0 or index >= _chains.size():
		return null
	var bones: Array[Bone2D] = _chains[index]["bones"]
	return bones[clampi(i, 0, bones.size() - 1)]


## 第 index 條腿目前的腳（世界座標，測試與特效用）。
func foot_of(index: int) -> Vector2:
	return (_chains[index]["foot"] as FootGait).foot if index >= 0 and index < _chains.size() else Vector2.INF


func is_stepping(index: int) -> bool:
	return index >= 0 and index < _chains.size() and (_chains[index]["foot"] as FootGait).stepping


func life_of(index: int) -> int:
	return int(_chains[index]["life"]) if index >= 0 and index < _chains.size() else 0
