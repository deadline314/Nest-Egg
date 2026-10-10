class_name NpcGesture
extends RefCounted
## 一個手勢／小動作的播放器（NE-250）：照「預備（反向蓄勢）→ 準備 → 重音 → 停留 → 收回」五段播放，
## 骨頭之間有拖曳延遲（上臂先動、前臂與手晚一點跟上＝重疊動作），兩個手勢接得很近時不收回、直接從目前姿勢接到下一個。
## 手勢的形狀全部在資料（art/rigs/npc_animations.json 的 gestures）：
##   pose：準備完成時各骨頭的角度增量；stroke：重音那一下再加的增量；wind：反向蓄勢的比例（pose 的反方向）；
##   time：{wind, prep, stroke, hold: [最短, 最長], retract}（秒）；drag：{骨頭: 延遲秒數}（舉起時的先後）；
##   drag_out：{骨頭: 延遲秒數}（放下時的先後，沒寫就用 drag；例如舉手時手肘先彎、肩後抬，放下時肩先落、手肘後伸）；
##   sag：停留期間慢慢加上的增量（手舉久了肩膀垂下、手肘多彎一點維持手的位置，停留不是凍住），收回時一起淡掉；
##   wiggle：停留時疊上的小幅搓動 [{bone, amp, period, phase}]（揉眼、抓頭、搓手；肩與肘反相＝手在原處來回搓）；postures：可以在哪些姿勢用（預設只有站）。
## 播放速度（speed）與幅度（expanse）是角色自己的資料（個性：快慢、動作大小）。資料缺漏時用安全預設，不會報錯中斷。

const DEFAULT_TIME := {"wind": 0.08, "prep": 0.24, "stroke": 0.14, "hold": [0.15, 0.4], "retract": 0.42}

var _def: Dictionary = {}
var _pose: Dictionary = {}
var _stroke: Dictionary = {}
var _sag: Dictionary = {}
var _drag: Dictionary = {}
var _drag_out: Dictionary = {}
## 最晚收回的骨頭比其他骨頭晚多久（延遲最大值）：手勢要等它也回到原位才結束，否則最後一格會跳回去。
var _tail := 0.0
var _wiggle: Array = []
var _wind := 0.0
var _t_wind := 0.0
var _t_prep := 0.0
var _t_stroke := 0.0
var _t_hold := 0.0
var _t_retract := 0.0
var _scale := 1.0
var _t := -1.0
var _released := false
## 接手時上一個手勢留下的姿勢，在準備階段慢慢淡掉（不回到原位就接下一個）。
var _carry: Dictionary = {}
## 接手時上一個手勢各骨頭的速度（弧度／秒）：用 Hermite 曲線從「目前的位置與速度」淡到 0，不會突然停住（保留餘勢）。
var _carry_v: Dictionary = {}
var _last_out: Dictionary = {}
var _last_v: Dictionary = {}
var name := &""


## 開始播放 def；hold 秒數由 rng 在範圍內挑；speed > 1 越快、expanse 是幅度倍率；carry／carry_v 是上一個手勢目前的增量與速度（接續用，
## 見 velocity()）。
func start(gesture_name: StringName, def: Dictionary, rng: RandomNumberGenerator, speed: float, expanse: float, carry: Dictionary = {}, carry_v: Dictionary = {}) -> void:
	name = gesture_name
	_def = def
	_pose = _dict(def, "pose")
	_stroke = _dict(def, "stroke")
	_sag = _dict(def, "sag")
	_drag = _dict(def, "drag")
	_drag_out = _dict(def, "drag_out") if def.has("drag_out") else _drag
	_tail = 0.0
	for value: Variant in _drag_out.values():
		if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			_tail = maxf(_tail, float(value))
	var wiggle: Variant = def.get("wiggle", [])
	_wiggle = wiggle if typeof(wiggle) == TYPE_ARRAY else []
	_wind = clampf(_num(def, "wind", 0.12), 0.0, 0.5)
	var times := _dict(def, "time")
	var k := 1.0 / clampf(speed, 0.3, 3.0)
	_t_wind = maxf(0.0, _num(times, "wind", DEFAULT_TIME["wind"])) * k
	_t_prep = maxf(0.05, _num(times, "prep", DEFAULT_TIME["prep"])) * k
	_t_stroke = maxf(0.03, _num(times, "stroke", DEFAULT_TIME["stroke"])) * k
	var hold: Variant = times.get("hold", DEFAULT_TIME["hold"])
	if typeof(hold) == TYPE_ARRAY and (hold as Array).size() >= 2 and typeof(hold[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(hold[1]) in [TYPE_INT, TYPE_FLOAT]:
		_t_hold = rng.randf_range(float(hold[0]), maxf(float(hold[0]), float(hold[1]))) * k
	else:
		_t_hold = 0.3 * k
	_t_retract = maxf(0.08, _num(times, "retract", DEFAULT_TIME["retract"])) * k
	_scale = clampf(expanse, 0.0, 2.0)
	_carry = carry.duplicate()
	_carry_v = carry_v.duplicate()
	_t = 0.0
	_released = false


func active() -> bool:
	return _t >= 0.0


## 是否已經過了重音（可以接下一個手勢而不顯得打斷）。
func past_stroke() -> bool:
	return _t >= _t_wind + _t_prep + _t_stroke


## 提早收回（例如說話結束）：從目前的樣子緩緩回到原位（用 retract 的秒數），不跳格；已在收回就不動。
func release() -> void:
	if _t < 0.0 or _released or _t >= _t_wind + _t_prep + _t_stroke + _t_hold:
		return
	_carry = _last_out.duplicate()
	_carry_v = _last_v.duplicate()
	_pose = {}
	_stroke = {}
	_sag = {}
	_drag_out = {}
	_tail = 0.0
	_wiggle = []
	_t = 0.0
	_t_wind = 0.0
	_t_prep = _t_retract
	_t_stroke = 0.0
	_t_hold = 0.0
	_t_retract = 0.01
	_released = true


## 往前走 delta 秒，回傳 {骨頭: 角度增量}。播完之後回傳空字典並變成不活動。
func step(delta: float) -> Dictionary:
	if _t < 0.0:
		return {}
	_t += delta
	var total := _t_wind + _t_prep + _t_stroke + _t_hold + _t_retract + _tail
	var out: Dictionary = {}
	for bone: Variant in _pose.keys():
		_add(out, bone, _num(_pose, bone, 0.0), 0)
	for bone: Variant in _stroke.keys():
		_add(out, bone, _num(_stroke, bone, 0.0), 1)
	for bone: Variant in _sag.keys():
		_add(out, bone, _num(_sag, bone, 0.0), 2)
	# 停留時的小幅搓動，隨停留淡入淡出
	var hold_start := _t_wind + _t_prep + _t_stroke
	if _t > hold_start and _t < hold_start + _t_hold + _t_retract * 0.5:
		var u := (_t - hold_start) / maxf(0.01, _t_hold + _t_retract * 0.5)
		var envelope := sin(PI * clampf(u, 0.0, 1.0))
		for entry: Variant in _wiggle:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var bone := StringName(str((entry as Dictionary).get("bone", "")))
			var period := maxf(0.05, _num(entry, "period", 0.4))
			out[bone] = float(out.get(bone, 0.0)) + _num(entry, "amp", 0.0) * _scale * envelope * sin(TAU * (_t - hold_start) / period + _num(entry, "phase", 0.0))
	# 上一個手勢留下的姿勢在準備階段淡掉
	if not _carry.is_empty():
		var span := maxf(0.01, _t_wind + _t_prep)
		var u := clampf(_t / span, 0.0, 1.0)
		var h00 := 2.0 * u * u * u - 3.0 * u * u + 1.0
		var h10 := u * u * u - 2.0 * u * u + u
		for bone: Variant in _carry.keys():
			out[bone] = float(out.get(bone, 0.0)) + float(_carry[bone]) * h00 + float(_carry_v.get(bone, 0.0)) * span * h10
		if u >= 1.0:
			_carry.clear()
			_carry_v.clear()
	if _t >= total:
		_t = -1.0
		_last_out = {}
		_last_v = {}
		return {}
	if delta > 0.0:
		_last_v.clear()
		for bone: Variant in out.keys():
			_last_v[bone] = (float(out[bone]) - float(_last_out.get(bone, 0.0))) / delta
	_last_out = out
	return out


## 目前各骨頭的速度（弧度／秒），給下一個手勢接續用。
func velocity() -> Dictionary:
	return _last_v if _t >= 0.0 else {}


## 這根骨頭在 _t 減掉拖曳延遲之後的權重：channel 0＝準備姿勢、1＝重音。
func _add(out: Dictionary, bone: Variant, value: float, channel: int) -> void:
	var retract_at := _t_wind + _t_prep + _t_stroke + _t_hold
	var t_out := _t - maxf(0.0, _num(_drag_out, bone, 0.0))
	var t := t_out if t_out >= retract_at else minf(_t - maxf(0.0, _num(_drag, bone, 0.0)), retract_at)
	var w := _weights(t)
	var k := w.x if channel == 0 else w.y
	if channel == 2:
		# 停留期間 0→1，收回時跟著準備權重一起淡掉
		var hold_start := _t_wind + _t_prep + _t_stroke
		k = clampf((t - hold_start) / maxf(0.01, _t_hold), 0.0, 1.0) * (w.x if t >= hold_start + _t_hold else 1.0)
		k = NpcGesture._smooth(k) if t < hold_start + _t_hold else k
	out[StringName(str(bone))] = float(out.get(StringName(str(bone)), 0.0)) + value * _scale * k


## 時間 t 的 (準備權重, 重音權重)。預備階段準備權重退到負的小值（反向蓄勢）並在那裡停一瞬，再一路到 1；
## 每段都從速度零開始、在速度零結束，段與段之間沒有轉折（重音靠很短的秒數表現力道）。
func _weights(t: float) -> Vector2:
	if t <= 0.0:
		return Vector2.ZERO
	if t < _t_wind:
		return Vector2(-_wind * _smooth(t / _t_wind), 0.0)
	t -= _t_wind
	if t < _t_prep:
		return Vector2(lerpf(-_wind if _t_wind > 0.0 else 0.0, 1.0, _smooth(t / _t_prep)), 0.0)
	t -= _t_prep
	if t < _t_stroke:
		return Vector2(1.0, _smooth(t / _t_stroke))
	t -= _t_stroke
	if t < _t_hold:
		return Vector2(1.0, 1.0)
	t -= _t_hold
	var back := 1.0 - _smooth(clampf(t / _t_retract, 0.0, 1.0))
	return Vector2(back, back)


static func _smooth(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


static func _dict(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _num(source: Variant, key: Variant, fallback: float) -> float:
	if typeof(source) != TYPE_DICTIONARY:
		return fallback
	var value: Variant = (source as Dictionary).get(key, fallback)
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else fallback
