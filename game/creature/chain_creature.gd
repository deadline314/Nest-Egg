class_name ChainCreature
extends Node2D
## 觸手生物（原型）：中央本體加數條觸手。每條觸手是一串骨頭，貼圖是一張連續的圖，用網格變形貼在骨頭鏈上（Polygon2D＋Skeleton2D），
## 彎曲處沒有縫，才有「軟」的感覺。動作全部是資料（art/creatures/<id>.json）：
##   行進波  沿骨頭鏈往尖端傳遞的正弦波（amp 幅度、wavelength 一個波長跨幾節、speed 傳遞速度），越靠近尖端擺得越大；
##   收縮波  寬度（pulse）與長度（stretch）沿鏈起伏，像蠕蟲一伸一縮；
##   鞭擊    state＝lash 時，波的包絡由根部傳到尖端（先捲起蓄力、再甩出去）。
## 狀態之間的參數會平滑過渡。用法：setup("<id>")，每影格 animate(delta, 狀態名稱)。
## 資料有錯（缺貼圖、骨頭數不對、狀態不存在）時記錄具體位置並用安全的預設值，不會崩潰。

const PATH := "res://art/creatures/%s.json"
const BLEND_SPEED := 6.0
## 受擊波：同時最多幾道、傳遞速度（節／秒）、壽命（秒）、波寬（節）。
const MAX_IMPULSES := 4
const IMPULSE_SPEED := 14.0
const IMPULSE_LIFE := 0.7
const IMPULSE_WIDTH := 1.6
## 斷肢飛出的速度。
const SEVER_SPEED := Vector2(110.0, -140.0)
const DEFAULT_STATE := {"amp": 0.15, "wavelength": 7.0, "speed": 1.6, "pulse": 0.05, "stretch": 0.02, "pulse_speed": 2.0, "curl": 0.0, "bob": 0.5, "duration": 0.8}

var creature_id := ""
var state: StringName = &"idle"
var state_time := 0.0

var _skeleton: Skeleton2D
var _body: Sprite2D
var _body_rest := Vector2.ZERO
var _chains: Array[Dictionary] = []
var _states: Dictionary = {}
var _params: Dictionary = DEFAULT_STATE.duplicate()
var _wave := 0.0
var _pulse := 0.0
var _time := 0.0
var _segments := 8
## 受擊波：{chain, at（骨頭序）, amp, age} 的固定容量陣列（重複使用，不每影格配置）。
var _impulses: Array[Dictionary] = []


## 建立身體、骨頭與網格。回傳 false 代表資料無法使用（已記錄原因）。
func setup(id: String) -> bool:
	creature_id = id
	var data := RigLibrary.load_json(PATH % id)
	if data.is_empty():
		return false
	var tentacle: Dictionary = data.get("tentacle", {})
	var tex := RigLibrary.optional_texture(str(tentacle.get("texture", "")))
	if tex == null:
		RigLibrary.report_once("creature_tex:" + id, "[ChainCreature] %s 的觸手貼圖不存在：%s" % [PATH % id, tentacle.get("texture", "")])
		return false
	_segments = clampi(int(tentacle.get("segments", 8)), 2, 24)
	_states = data.get("states", {})
	if not _states.has("idle"):
		RigLibrary.report_once("creature_idle:" + id, "[ChainCreature] %s 沒有 idle 狀態，使用預設參數" % (PATH % id))
	var scale_px := float(data.get("texture_scale", 0.25))
	_build_body(data.get("body", {}), scale_px)
	_skeleton = Skeleton2D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)
	var width := float(tentacle.get("width", 16.0))
	var length := float(tentacle.get("length", 90.0))
	var list: Variant = data.get("tentacles", [])
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		RigLibrary.report_once("creature_list:" + id, "[ChainCreature] %s 沒有 tentacles" % (PATH % id))
		return true
	for entry: Variant in list:
		if typeof(entry) == TYPE_DICTIONARY:
			_add_tentacle(entry as Dictionary, tex, width, length)
	_params = (_states.get("idle", DEFAULT_STATE) as Dictionary).duplicate()
	return true


func _build_body(body: Dictionary, scale_px: float) -> void:
	var tex := RigLibrary.optional_texture(str(body.get("texture", "")))
	if tex == null:
		return
	_body = Sprite2D.new()
	_body.texture = tex
	_body.centered = false
	_body.scale = Vector2.ONE * scale_px
	_body.position = RigLibrary.vec2(body.get("offset"), Vector2(-20, -16))
	_body.z_index = 0
	_body_rest = _body.position
	add_child(_body)


## 一條觸手：N 根骨頭串成一條鏈（朝下為 0 度，負角往前），加上沿鏈的網格（每節 2 排、3 欄頂點），頂點依到各骨頭的位置分配權重。
func _add_tentacle(entry: Dictionary, tex: Texture2D, width: float, length: float) -> void:
	var s := float(entry.get("scale", 1.0))
	var anchor := RigLibrary.vec2(entry.get("anchor"))
	var angle := deg_to_rad(float(entry.get("angle", 0.0)))
	var seg_len := length * s / float(_segments)
	var half := width * s * 0.5
	var bones: Array[Bone2D] = []
	var parent: Node = _skeleton
	for i in _segments:
		var bone := Bone2D.new()
		bone.name = "T%d_%d" % [_chains.size(), i]
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
	var rows := _segments * 2 + 1
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var tex_size := tex.get_size()
	var rot := Transform2D(angle, Vector2.ZERO)
	for r in rows:
		var y := float(r) / float(rows - 1) * seg_len * float(_segments)
		for c in 3:
			var x := lerpf(-half, half, float(c) / 2.0)
			verts.append(anchor + rot * Vector2(x, y))
			uvs.append(Vector2(float(c) / 2.0 * tex_size.x, float(r) / float(rows - 1) * tex_size.y))
	var polys: Array = []
	for r in rows - 1:
		for c in 2:
			var a := r * 3 + c
			polys.append(PackedInt32Array([a, a + 1, a + 4, a + 3]))
	var polygon := Polygon2D.new()
	polygon.name = "Mesh%d" % _chains.size()
	polygon.texture = tex
	polygon.polygon = verts
	polygon.uv = uvs
	polygon.polygons = polys
	polygon.z_index = int(entry.get("z", 0))
	add_child(polygon)
	polygon.skeleton = polygon.get_path_to(_skeleton)
	var weights: Array[PackedFloat32Array] = []
	for i in _segments:
		weights.append(PackedFloat32Array())
		weights[i].resize(verts.size())
	for r in rows:
		var t := float(r) / float(rows - 1) * float(_segments)  # 沿鏈的位置，單位＝節
		var k := mini(int(floor(t)), _segments - 1)
		var f := t - float(k)
		for c in 3:
			var v := r * 3 + c
			if k + 1 < _segments:
				weights[k][v] = 1.0 - f
				weights[k + 1][v] = f
			else:
				weights[k][v] = 1.0
	for i in _segments:
		polygon.add_bone(polygon.get_path_to(bones[i]), weights[i])
	_chains.append({"index": _chains.size(), "bones": bones, "angle": angle, "phase": float(entry.get("phase", 0.0)), "seg_len": seg_len, "scale": s, "polygon": polygon})


func set_state(new_state: StringName) -> void:
	if new_state != state:
		state = new_state
		state_time = 0.0


## 每影格呼叫：狀態參數平滑過渡，行進波與收縮波往前走，更新每根骨頭的角度、寬度與長度。
func animate(delta: float, new_state: StringName = &"") -> void:
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
	var lashing := state == &"lash"
	var progress := clampf(state_time / maxf(0.05, float(target["duration"])), 0.0, 1.0)
	for impulse in _impulses:
		impulse["age"] = float(impulse["age"]) + delta
	for chain: Dictionary in _chains:
		if not chain.get("severed", false):
			_pose_chain(chain, lashing, progress)
	if _body != null:
		_body.position = _body_rest + Vector2(0, sin(_time * 2.1) * float(_params["bob"]))


func _pose_chain(chain: Dictionary, lashing: bool, progress: float) -> void:
	var bones: Array[Bone2D] = chain["bones"]
	var n := bones.size()
	var phase: float = chain["phase"]
	var amp := float(_params["amp"])
	var wavelength := maxf(1.0, float(_params["wavelength"]))
	var pulse := float(_params["pulse"])
	var stretch := float(_params["stretch"])
	var curl := float(_params["curl"])
	var seg_len: float = chain["seg_len"]
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
		bone.rotation = (chain["angle"] if i == 0 else 0.0) + a
		var absolute := 1.0 + pulse * sin(TAU * float(i) / (wavelength * 0.7) - _pulse + phase)
		bone.scale = Vector2(absolute / previous_pulse, 1.0)  # 寬度起伏：子骨頭補償父骨頭的縮放，不會逐節累積
		previous_pulse = absolute
		if i > 0:
			bone.position = Vector2(0, seg_len * (1.0 + stretch * sin(TAU * float(i) / wavelength - _pulse * 1.1 + phase + 1.2)))


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


## 打斷第 index 條觸手：整條離開身體飛出去（用脫落零件的物件池，場上已滿就只消失），之後不再擺動。
## impulse 是飛出的方向（世界座標，會被正規化）。回傳 false 代表這條已經斷了或編號不存在。
func sever(index: int, impulse := Vector2.ZERO) -> bool:
	if index < 0 or index >= _chains.size() or _chains[index].get("severed", false):
		return false
	var chain := _chains[index]
	chain["severed"] = true
	var polygon: Polygon2D = chain["polygon"]
	polygon.visible = false
	var tex := polygon.texture
	if tex != null:
		var verts := polygon.polygon
		var origin := verts[0]
		var x_axis := (verts[2] - verts[0]) / maxf(1.0, tex.get_size().x)
		var y_axis := (verts[verts.size() - 3] - verts[0]) / maxf(1.0, tex.get_size().y)
		var source := global_transform * Transform2D(x_axis, y_axis, origin)
		var dir := impulse.normalized() if impulse != Vector2.ZERO else Vector2.RIGHT
		var debris := RigDebris.spawn(tex, source, Vector2.ZERO, Vector2(dir.x * SEVER_SPEED.x, SEVER_SPEED.y) * randf_range(0.8, 1.2))
		if debris != null and not Fx.add_world_node(debris):
			debris.cancel()
	return true


func alive_tentacles() -> int:
	var count := 0
	for chain in _chains:
		if not chain.get("severed", false):
			count += 1
	return count


## 每條觸手尖端的世界座標（傷害判定與落點預兆用）。
func tip_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for chain: Dictionary in _chains:
		var bones: Array[Bone2D] = chain["bones"]
		var last := bones[bones.size() - 1]
		out.append(last.to_global(Vector2(0, float(chain["seg_len"]))))
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
