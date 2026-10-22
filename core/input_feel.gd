class_name InputFeel
extends RefCounted
## 輸入手感（NE-145）：資料化的緩衝與取消窗口（data/feel/input.json）、手把專用的瞄準輔助、輸入延遲量測。
## 資料缺漏或損毀時記錄「檔案、欄位」並退回呼叫端給的預設值。

const PATH := "res://data/feel/input.json"
const KNOWN_BUFFERS: PackedStringArray = ["jump_buffer", "coyote", "dash_buffer", "melee_buffer"]
const MAX_BUFFER := 0.3

static var _data: Dictionary = {}
static var _loaded := false
static var _reported: Dictionary = {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var json: JSON = load(PATH) as JSON if ResourceLoader.exists(PATH) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		_report("load", "[InputFeel] 無法讀取輸入手感資料：%s，全部用預設值" % PATH)
		return
	_data = json.data


static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()


## 緩衝／取消窗口（秒）；缺漏或不合理（負數、超過上限）時用 fallback 並記錄一次。
static func window(key: String, fallback: float) -> float:
	_ensure_loaded()
	var value: Variant = (_data.get("windows", {}) as Dictionary).get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		_report("window:" + key, "[InputFeel] %s 沒有 windows.%s，改用預設 %s" % [PATH, key, fallback])
		return fallback
	var seconds := float(value)
	if seconds < 0.0 or seconds > MAX_BUFFER:
		_report("range:" + key, "[InputFeel] %s 的 windows.%s = %s 不在 0～%s 秒內，改用預設 %s" % [PATH, key, seconds, MAX_BUFFER, fallback])
		return fallback
	return seconds


static func validate() -> PackedStringArray:
	_ensure_loaded()
	var errors := PackedStringArray()
	var windows: Dictionary = _data.get("windows", {})
	for key in KNOWN_BUFFERS:
		if not windows.has(key):
			errors.append("%s 缺少 windows.%s" % [PATH, key])
		elif float(windows[key]) < 0.0 or float(windows[key]) > MAX_BUFFER:
			errors.append("%s 的 windows.%s 要在 0～%s 秒內" % [PATH, key, MAX_BUFFER])
	var assist: Dictionary = _data.get("aim_assist", {})
	for key in ["cone_degrees", "strength", "max_distance"]:
		if float(assist.get(key, 0.0)) <= 0.0:
			errors.append("%s 的 aim_assist.%s 要大於 0" % [PATH, key])
	if float(assist.get("strength", 0.0)) > 0.6:
		errors.append("%s 的 aim_assist.strength 不能超過 0.6（輔助太強會搶走玩家控制）" % PATH)
	return errors


# ---------------------------------------------------------------------------
# 手把瞄準輔助：只給手把，玩家輸入優先
# ---------------------------------------------------------------------------

## 把手把的瞄準方向輕輕拉向錐形範圍內最近的敵人。
## 只在手把時使用（滑鼠永遠不會被輔助）；玩家正在大幅轉動搖桿（角速度超過 turn_cutoff）時輔助關閉；
## 敵人必須在 cone_degrees 的錐形與 max_distance 之內，所以輔助拉不過去的就是玩家沒有瞄向的。
static func assist(origin: Vector2, stick_dir: Vector2, targets: Array, stick_turn_rate: float, using_gamepad: bool, protected_hit_distance := INF) -> Vector2:
	if not using_gamepad or stick_dir == Vector2.ZERO:
		return stick_dir
	_ensure_loaded()
	var cfg: Dictionary = _data.get("aim_assist", {})
	if not bool(cfg.get("enabled", true)):
		return stick_dir
	if stick_turn_rate > float(cfg.get("turn_cutoff", 6.0)):
		return stick_dir
	var cone := deg_to_rad(float(cfg.get("cone_degrees", 12.0)))
	var reach := float(cfg.get("max_distance", 260.0))
	var best: Vector2 = Vector2.ZERO
	var best_angle := cone
	var best_distance := INF
	for target: Variant in targets:
		var node := target as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var offset := node.global_position + Vector2(0.0, -20.0) - origin
		if offset.length() > reach or offset.length_squared() < 1.0:
			continue
		var angle := absf(stick_dir.angle_to(offset))
		if angle < best_angle:
			best_angle = angle
			best = offset.normalized()
			best_distance = offset.length()
	if best == Vector2.ZERO:
		return stick_dir
	# An explosive already on the player's raw ray has priority over a farther enemy.
	# This never adds magnetism toward explosives that the player did not aim at.
	if protected_hit_distance >= 0.0 and protected_hit_distance < best_distance:
		return stick_dir
	# 越靠近中心拉得越多：輔助強度乘上「離錐形邊緣多遠」。
	var pull := float(cfg.get("strength", 0.35)) * (1.0 - best_angle / cone)
	return stick_dir.slerp(best, clampf(pull, 0.0, 1.0)).normalized()


static func assist_max_distance() -> float:
	_ensure_loaded()
	return float((_data.get("aim_assist", {}) as Dictionary).get("max_distance", 260.0))


# ---------------------------------------------------------------------------
# 輸入延遲：按下輸入到效果發生的時間
# ---------------------------------------------------------------------------

static var _marks: Dictionary = {}
static var last_ms := 0.0
static var average_ms := 0.0
static var samples := 0


## 收到按鍵事件時呼叫（記下時間）。
static func mark(action: StringName) -> void:
	_marks[action] = Time.get_ticks_usec()


## 效果發生時呼叫；回傳這次延遲（毫秒），沒有對應的按鍵記錄時回傳 -1。
static func resolve(action: StringName) -> float:
	if not _marks.has(action):
		return -1.0
	var elapsed := float(Time.get_ticks_usec() - int(_marks[action])) * 0.001
	_marks.erase(action)
	last_ms = elapsed
	samples += 1
	average_ms = average_ms + (elapsed - average_ms) / float(samples)
	return elapsed


static func reset_latency() -> void:
	_marks.clear()
	last_ms = 0.0
	average_ms = 0.0
	samples = 0


static func _report(key: String, message: String) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	push_error(message)
