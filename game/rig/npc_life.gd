class_name NpcLife
extends RefCounted
## NPC 的生命感層（NE-206）：在 NPC 動畫器算好的基本姿勢上，再疊四種「人在待著」的東西，全部由資料驅動
## （art/rigs/npc_animations.json 的 life 是預設，art/motion/<角色>.json 的 npc.life 逐項蓋過，給每個人自己的節奏）：
##  - drift：各骨頭各自一條兩個正弦疊起來的緩慢飄動，週期由「角色＋骨頭」決定（不同步、不重複），像沒在動又沒停；
##  - breath：呼吸速率緩慢起伏，偶爾一次較深的嘆氣；
##  - shift：站著時每隔幾秒把重心從一隻腳移到另一隻（骨盆側移、腿反向轉讓腳不滑，空出來的腳微彎）；
##  - glance：偶爾把頭轉開看一下再轉回來（先轉頭、身體稍後跟上）；
##  - beat：說話時從角色自己的手勢清單（vocab 權重）挑手勢，每個手勢有預備、準備、重音、停留、收回（NpcGesture），
##    接得近的兩個手勢不收回直接接上；開口前吸一口氣、說完放鬆，重音時點頭（NE-250）；
##  - listen：聆聽時偶爾點頭附和（backchannel）；
##  - fidget：站著沒事時偶爾做一個角色專屬的小動作（揉脖子、看錶、揉眼…），手忙（工作循環、揮手）或說話時不做；
##  - follow：頭、軀幹、前臂用有點欠阻尼的二階彈簧追目標角度，停下來時有一點餘勢與過衝。
## 亂數由角色名稱決定種子：同一個角色每次都一樣（測試可重現），不同角色不同步。

const MAX_STEP := 1.0 / 60.0

var _rng := RandomNumberGenerator.new()
var _cfg: Dictionary = {}
var _skin := ""
var _amount := 1.0
var _tempo := 1.0
var _time := 0.0
var _drift: Array[Dictionary] = []
var _breath_phase := 0.0
var _sigh_next := 0.0
var _sigh_t := -1.0
var _shift_next := 0.0
var _shift_side := 1.0
var _shift_x := 0.0
var _shift_v := 0.0
var _glance_next := 0.0
var _glance_t := -1.0
var _glance_hold := 0.0
var _glance_target := 0.0
var _glance_head := 0.0
var _beat_next := 0.0
var _last_gesture := &""
var _gestures: Dictionary = {}
var _hands := NpcGesture.new()
var _hands_out: Dictionary = {}
var _hands_kind := ""
var _chain := true
var _head := NpcGesture.new()
var _nod_next := 0.0
var _fidget_next := 0.0
var _glance_body := 0.0
var _was_talking := false
var _inhale_t := -1.0
var _settle_t := -1.0
var _spring_x: Dictionary[StringName, float] = {}
var _spring_v: Dictionary[StringName, float] = {}
## 這個角色的事件計數（測試用：長時間待機一定會發生）。
var shifts := 0
var glances := 0
var beats := 0
var sighs := 0
var nods := 0
var fidgets := 0


## defaults：npc_animations.json 的 life；overrides：角色自己的 npc.life（項目逐一蓋過；amount 與 tempo 是整體倍率）；
## gestures：npc_animations.json 的 gestures（手勢與小動作的形狀）。
func setup(skin: String, defaults: Dictionary, overrides: Dictionary, gestures: Dictionary = {}) -> void:
	_skin = skin
	_gestures = gestures
	_cfg = defaults.duplicate(true)
	for key: Variant in overrides.keys():
		if typeof(overrides[key]) == TYPE_DICTIONARY and typeof(_cfg.get(key)) == TYPE_DICTIONARY:
			(_cfg[key] as Dictionary).merge(overrides[key], true)
		else:
			_cfg[key] = overrides[key]
	_amount = maxf(0.0, float(_cfg.get("amount", 1.0)))
	_tempo = maxf(0.2, float(_cfg.get("tempo", 1.0)))
	_rng.seed = hash("%s:%d" % [skin, int(_cfg.get("seed", 0))])
	_drift.clear()
	var tracks: Variant = _cfg.get("drift", [])
	if typeof(tracks) == TYPE_ARRAY:
		for track: Variant in tracks:
			if typeof(track) != TYPE_DICTIONARY:
				continue
			var bone := StringName(str((track as Dictionary).get("bone", "")))
			var periods_value: Variant = (track as Dictionary).get("periods", [7.0, 13.0])
			var periods: Array = periods_value if typeof(periods_value) == TYPE_ARRAY else [7.0, 13.0]
			var low := float(periods[0]) if periods.size() > 0 else 7.0
			var high := float(periods[1]) if periods.size() > 1 else low * 2.0
			# 每條軌道自己的兩個週期（高低各取一個，避免整數倍關係）與相位。
			_drift.append({
				"bone": bone, "amp": float((track as Dictionary).get("amp", 0.02)),
				"p1": _rng.randf_range(low, (low + high) * 0.5), "p2": _rng.randf_range((low + high) * 0.5, high) * 1.0137,
				"a1": _rng.randf() * TAU, "a2": _rng.randf() * TAU,
			})
	_shift_next = _next_in("shift", "every", 3.0)
	_glance_next = _next_in("glance", "every", 2.0)
	_sigh_next = _next_in("breath", "sigh_every", 8.0)
	_beat_next = 0.3
	_nod_next = _next_in("listen", "nod_every", 2.5)
	_fidget_next = _next_in("fidget", "every", 6.0)


## 這個角色的飄動軌道（測試與稽核用）：每個元素有 bone、p1、p2。
func drift_tracks() -> Array[Dictionary]:
	return _drift


## 往前走 delta 秒。context：{"posture": 基本姿勢（stand／sit／lean／crouch）, "talking": bool, "listening": bool,
## "busy": bool（手在忙：工作循環、揮手，不做小動作）, "thigh": 大腿骨長（像素，重心轉移時腿反向轉動要用）}。
## 回傳 {"bones": {骨頭: 角度增量}, "hip_x": 像素, "hip_y": 像素, "breath_rate": 呼吸速度倍率, "breath_extra": 額外的呼吸起伏（0 以上）}。
func step(delta: float, context: Dictionary) -> Dictionary:
	_time += delta
	var posture := StringName(str(context.get("posture", "stand")))
	var talking := bool(context.get("talking", false))
	var listening := bool(context.get("listening", false)) and not talking
	var busy := bool(context.get("busy", false))
	var bones: Dictionary = {}
	var living := _amount
	for track in _drift:
		var bone: StringName = track["bone"]
		var wave := 0.6 * sin(TAU * _time / float(track["p1"]) + float(track["a1"])) + 0.4 * sin(TAU * _time / float(track["p2"]) + float(track["a2"]))
		bones[bone] = float(bones.get(bone, 0.0)) + wave * float(track["amp"]) * living
	var hip_x := 0.0
	var hip_y := 0.0
	# 呼吸
	var breath_cfg := _section("breath")
	var rate := 1.0 + float(breath_cfg.get("rate_var", 0.1)) * sin(TAU * _time / 23.0 + float(_rng.seed % 100) * 0.1)
	var extra := 0.0
	if _time >= _sigh_next and _sigh_t < 0.0:
		_sigh_t = 0.0
		sighs += 1
	if _sigh_t >= 0.0:
		_sigh_t += delta
		var duration := maxf(0.5, float(breath_cfg.get("sigh_time", 2.4)))
		var u := clampf(_sigh_t / duration, 0.0, 1.0)
		extra = sin(PI * u) * float(breath_cfg.get("sigh_amp", 1.8)) * living
		if _sigh_t >= duration:
			_sigh_t = -1.0
			_sigh_next = _time + _next_in("breath", "sigh_every", 8.0)
	# 重心轉移：只有站著才換腳
	var shift_cfg := _section("shift")
	if posture == &"stand":
		if _time >= _shift_next:
			_shift_side = -_shift_side
			_shift_next = _time + _next_in("shift", "every", 3.0)
			shifts += 1
		var goal := _shift_side * float(shift_cfg.get("hip_x", 0.8)) * living
		_shift_x = _spring(_shift_x, goal, "_shift", delta, 1.0 / maxf(0.2, float(shift_cfg.get("time", 1.1))) * 3.0, 1.0)
	else:
		_shift_x = lerpf(_shift_x, 0.0, 1.0 - exp(-4.0 * delta))
		_shift_next = maxf(_shift_next, _time + 1.0)
	hip_x += _shift_x
	var lean := float(shift_cfg.get("lean", 0.03))
	var free_knee := float(shift_cfg.get("knee", 0.1))
	var free_side := signf(_shift_x) if absf(_shift_x) > 0.02 else 0.0
	var thigh := maxf(4.0, float(context.get("thigh", 12.0)))
	var counter := asin(clampf(_shift_x / thigh, -0.5, 0.5))
	if posture == &"stand":
		for leg: StringName in [&"leg_front_upper", &"leg_back_upper"]:
			bones[leg] = float(bones.get(leg, 0.0)) + counter
		for leg: StringName in [&"leg_front_lower", &"leg_back_lower"]:
			bones[leg] = float(bones.get(leg, 0.0)) - counter
		# 重心移到哪一側，另一側的腳微彎放鬆
		var free_leg: StringName = &"leg_back_lower" if free_side > 0.0 else &"leg_front_lower"
		if free_side != 0.0:
			# 空出來的腳膝蓋微彎，大腿反向轉一半讓腳踝留在原地（腳不滑）
			var bend := free_knee * minf(1.0, absf(_shift_x) / maxf(0.1, float(shift_cfg.get("hip_x", 0.8))))
			var free_upper: StringName = &"leg_back_upper" if free_side > 0.0 else &"leg_front_upper"
			bones[free_leg] = float(bones.get(free_leg, 0.0)) + bend
			bones[free_upper] = float(bones.get(free_upper, 0.0)) - bend * 0.5
		bones[&"chest"] = float(bones.get(&"chest", 0.0)) - _shift_x * lean
	# 轉頭看一下
	var glance_cfg := _section("glance")
	if _glance_t < 0.0 and _time >= _glance_next:
		_glance_t = 0.0
		_glance_target = (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.5, 1.0) * float(glance_cfg.get("head", 0.2))
		_glance_hold = _range_of(glance_cfg, "hold", 0.8)
		glances += 1
	var want_head := 0.0
	if _glance_t >= 0.0:
		_glance_t += delta
		var rise := maxf(0.05, float(glance_cfg.get("time", 0.4)))
		if _glance_t < rise + _glance_hold:
			want_head = _glance_target
		elif _glance_t > rise + _glance_hold + rise:
			_glance_t = -1.0
			_glance_next = _time + _next_in("glance", "every", 2.0)
	if talking:
		want_head = 0.0  # 說話時看著對方
	_glance_head = _spring(_glance_head, want_head * living, "_glance", delta, 14.0, 0.7)
	# 視線先動、頭跟上、身體最後：頸與胸追頭的角度，比頭慢約 0.1 秒
	_glance_body = _spring(_glance_body, _glance_head, "_glance_body", delta, 7.0, 0.9)
	bones[&"head"] = float(bones.get(&"head", 0.0)) + _glance_head
	bones[&"neck"] = float(bones.get(&"neck", 0.0)) + _glance_body * 0.25
	bones[&"chest"] = float(bones.get(&"chest", 0.0)) + _glance_body * 0.12
	# 說話：開口前吸氣、重音手勢、說完放鬆
	var beat_cfg := _section("beat")
	if talking and not _was_talking:
		_inhale_t = 0.0
		_beat_next = _time + _rng.randf_range(0.3, 0.7)  # 吸一口氣才開始比手勢，每個人每次不一樣
	if not talking and _was_talking:
		_settle_t = 0.0
	_was_talking = talking
	if _inhale_t >= 0.0:
		_inhale_t += delta
		var inhale := maxf(0.1, float(beat_cfg.get("inhale", 0.3)))
		bones[&"chest"] = float(bones.get(&"chest", 0.0)) - sin(PI * clampf(_inhale_t / inhale, 0.0, 1.0)) * float(beat_cfg.get("inhale_amp", 0.05)) * living
		hip_y -= sin(PI * clampf(_inhale_t / inhale, 0.0, 1.0)) * 0.3
		if _inhale_t >= inhale:
			_inhale_t = -1.0
	if _settle_t >= 0.0:
		_settle_t += delta
		var settle := maxf(0.1, float(beat_cfg.get("settle", 0.6)))
		var u := clampf(_settle_t / settle, 0.0, 1.0)
		bones[&"chest"] = float(bones.get(&"chest", 0.0)) + sin(PI * u) * float(beat_cfg.get("settle_amp", 0.03)) * living
		bones[&"head"] = float(bones.get(&"head", 0.0)) - sin(PI * u) * 0.04 * living
		if _settle_t >= settle:
			_settle_t = -1.0
	# 重音手勢：上一個手勢過了重音才接下一個（太近就不收回直接接），說完話提早收回
	# 手在忙（工作循環、揮手）時只點頭不比手勢
	if talking and _time >= _beat_next and (not _hands.active() or (_hands.past_stroke() and _chain)):
		if busy or _play(_hands, "beat", posture, _hands_out):
			beats += 1
			var nod := float(beat_cfg.get("nod", 0.07)) if typeof(beat_cfg.get("nod", 0.07)) in [TYPE_INT, TYPE_FLOAT] else 0.07
			if nod > 0.0 and not _head.active():
				_head.start(&"nod", _gesture_def(&"nod"), _rng, _speed("beat"), nod / 0.07 * living)
		_beat_next = _time + _range_of(beat_cfg, "every", 0.8)
		# 有時候手勢之間把手放下休息一下（rest＝放下的機率），不是一直舉著手接下一個
		var rest: Variant = beat_cfg.get("rest", 0.3)
		_chain = _rng.randf() >= (float(rest) if typeof(rest) in [TYPE_INT, TYPE_FLOAT] else 0.3)
	if not talking and _hands_kind == "beat":
		_hands.release()
	# 聆聽時偶爾點頭附和
	var listen_cfg := _section("listen")
	if listening and _time >= _nod_next and not _head.active():
		var amount := float(listen_cfg.get("nod", 0.8)) if typeof(listen_cfg.get("nod", 0.8)) in [TYPE_INT, TYPE_FLOAT] else 0.8
		_head.start(&"nod", _gesture_def(&"nod"), _rng, _speed("listen"), amount * living)
		nods += 1
		_nod_next = _time + _next_in("listen", "nod_every", 2.5)
	elif not listening:
		_nod_next = maxf(_nod_next, _time + 0.6)
	# 站著沒事時的小動作（聆聽時頻率減半）
	if talking or busy:
		_fidget_next = maxf(_fidget_next, _time + 1.5)
	elif _time >= _fidget_next and not _hands.active():
		if _play(_hands, "fidget", posture, {}):
			fidgets += 1
		_fidget_next = _time + _next_in("fidget", "every", 6.0) * (2.0 if listening else 1.0)
	_hands_out = _hands.step(delta)
	for bone: StringName in _hands_out.keys():
		bones[bone] = float(bones.get(bone, 0.0)) + float(_hands_out[bone]) * living
	var head_out := _head.step(delta)
	for bone: StringName in head_out.keys():
		bones[bone] = float(bones.get(bone, 0.0)) + float(head_out[bone])
	return {"bones": bones, "hip_x": hip_x, "hip_y": hip_y, "breath_rate": rate, "breath_extra": extra}


## 從 section（beat／fidget）的 vocab 依權重挑一個這個姿勢能用的手勢並開始播放；連續兩次盡量不同。回傳有沒有開始。
func _play(player: NpcGesture, section: String, posture: StringName, carry: Dictionary) -> bool:
	var cfg := _section(section)
	var vocab: Variant = cfg.get("vocab", {})
	if typeof(vocab) != TYPE_DICTIONARY or (vocab as Dictionary).is_empty():
		vocab = {"beat": 1.0} if section == "beat" else {}
	var names: Array[StringName] = []
	var weights: Array[float] = []
	var total := 0.0
	for key: Variant in (vocab as Dictionary).keys():
		var gesture_name := StringName(str(key))
		var def := _gesture_def(gesture_name)
		var weight: Variant = (vocab as Dictionary)[key]
		if def.is_empty() or typeof(weight) not in [TYPE_INT, TYPE_FLOAT] or float(weight) <= 0.0 or not _allows(def, posture):
			continue
		var w := float(weight) * (0.35 if gesture_name == _last_gesture and (vocab as Dictionary).size() > 1 else 1.0)
		names.append(gesture_name)
		weights.append(w)
		total += w
	if names.is_empty() and section == "beat":
		names.append(&"beat")  # 資料都不能用時退回內建的小幅重音
		weights.append(1.0)
		total = 1.0
	if names.is_empty():
		return false
	var pick := _rng.randf() * total
	var chosen := names[names.size() - 1]
	for i in names.size():
		pick -= weights[i]
		if pick <= 0.0:
			chosen = names[i]
			break
	_last_gesture = chosen
	_hands_kind = section
	var expanse := float(cfg.get("expanse", 1.0)) if typeof(cfg.get("expanse", 1.0)) in [TYPE_INT, TYPE_FLOAT] else 1.0
	player.start(chosen, _gesture_def(chosen), _rng, _speed(section), expanse * _rng.randf_range(0.8, 1.1), carry, player.velocity() if not carry.is_empty() else {})
	return true


## 直接播放指定的手勢或小動作（過場指定動作、預覽工具用）；手勢不存在或這個姿勢不能用時回傳 false。
func play_gesture(gesture_name: StringName, posture: StringName = &"stand") -> bool:
	var def := _gesture_def(gesture_name)
	if def.is_empty() or not _allows(def, posture):
		return false
	_hands.start(gesture_name, def, _rng, _speed("beat"), 1.0, _hands_out, _hands.velocity())
	_hands_kind = "cue"
	_fidget_next = maxf(_fidget_next, _time + 3.0)
	return true


## 手勢的形狀；資料裡沒有這個手勢時退回內建的小幅重音（beat）與點頭（nod），其他回傳空的。
func _gesture_def(gesture_name: StringName) -> Dictionary:
	var value: Variant = _gestures.get(String(gesture_name), {})
	if typeof(value) == TYPE_DICTIONARY and not (value as Dictionary).is_empty():
		return value
	if gesture_name == &"nod":
		return {"pose": {"head": 0.07}, "wind": 0.2, "time": {"wind": 0.06, "prep": 0.12, "stroke": 0.05, "hold": [0.02, 0.06], "retract": 0.25}}
	if gesture_name == &"beat":
		return {"pose": {"arm_front_upper": -0.3, "arm_front_lower": -0.5}, "stroke": {"arm_front_lower": 0.2}, "drag": {"arm_front_lower": 0.05}}
	return {}


func _allows(def: Dictionary, posture: StringName) -> bool:
	var postures: Variant = def.get("postures", ["stand"])
	return typeof(postures) == TYPE_ARRAY and (postures as Array).has(String(posture))


func _speed(section: String) -> float:
	var value: Variant = _section(section).get("speed", 1.0)
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 1.0


## 追目標角度的欠阻尼二階彈簧（頭、軀幹、前臂的餘勢與過衝）；沒設定的骨頭原樣通過。回傳新的姿勢角度。
func follow(bone: StringName, target: float, delta: float) -> float:
	var follow_cfg := _section("follow")
	if not follow_cfg.has(String(bone)):
		return target
	var entry: Variant = follow_cfg[String(bone)]
	if typeof(entry) != TYPE_DICTIONARY:
		return target
	var x := float(_spring_x.get(bone, target))
	var v := float(_spring_v.get(bone, 0.0))
	var omega := float(entry.get("w", 14.0))
	var zeta := float(entry.get("z", 0.6))
	var t := delta
	while t > 0.0:
		var h := minf(t, MAX_STEP)
		v += (omega * omega * (target - x) - 2.0 * zeta * omega * v) * h
		x += v * h
		t -= h
	_spring_x[bone] = x
	_spring_v[bone] = v
	return x


## 正在播放的手勢或小動作名稱（沒有時是空的；測試與除錯用）。
func current_gesture() -> StringName:
	return _hands.name if _hands.active() else &""


## 設定的一個區段（給 NPC 動畫器讀角色自己的調整，例如 posture）。
func section(name: String) -> Dictionary:
	return _section(name)


# ---------------------------------------------------------------------------

## 設定的一個區段；資料缺漏或寫成別的型別時當作空的（全部走預設值）。
func _section(name: String) -> Dictionary:
	var value: Variant = _cfg.get(name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


## key 在 section 裡的 [最短, 最長] 秒之間挑一個，再除以 tempo（tempo 越大事件越頻繁）。
func _next_in(section: String, key: String, fallback: float) -> float:
	return _range_of(_section(section), key, fallback) / _tempo


func _range_of(cfg: Dictionary, key: String, fallback: float) -> float:
	var span: Variant = cfg.get(key, [fallback, fallback * 2.0])
	if typeof(span) == TYPE_ARRAY and (span as Array).size() >= 2 and typeof(span[0]) in [TYPE_FLOAT, TYPE_INT] and typeof(span[1]) in [TYPE_FLOAT, TYPE_INT]:
		return _rng.randf_range(float(span[0]), maxf(float(span[0]), float(span[1])))
	return fallback


## 單一數值的欠阻尼彈簧（內部狀態用名稱區分）。
func _spring(x: float, target: float, name: String, delta: float, omega: float, zeta: float) -> float:
	var key := StringName(name)
	var cur := float(_spring_x.get(key, x))
	var vel := float(_spring_v.get(key, 0.0))
	var t := delta
	while t > 0.0:
		var h := minf(t, MAX_STEP)
		vel += (omega * omega * (target - cur) - 2.0 * zeta * omega * vel) * h
		cur += vel * h
		t -= h
	_spring_x[key] = cur
	_spring_v[key] = vel
	return cur
