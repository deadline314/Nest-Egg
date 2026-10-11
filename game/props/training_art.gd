class_name TrainingArt
extends Node2D
## 序章訓練器材的外觀（BG-37）：把場景包裡畫好的器材墊在訓練站後面，並負責器材自己的動作——
## 被打中的晃動（繞著底座，像裝在彈簧上）、訓練器手臂的後拉與出手。
## 器材用哪張圖、燈號畫在哪、手臂接在哪，都寫在 data/environment/training_art.json，新增器材只改資料。
## 圖或資料讀不到時 build() 回傳 null 並指出是哪一筆，訓練站退回原本的簡單畫法，序章不會壞。
## 判定完全不看這裡：這個節點只有畫面。

const TABLE_PATH := "res://data/environment/training_art.json"
const DEFAULT_PACK := "res://data/environment/scene_props/training_range"
## 晃動的彈簧：角頻率（弧度／秒）與阻尼比；低於這個幅度就停下來、不再每格更新。
const SWAY_OMEGA := 26.0
const SWAY_DAMPING := 0.22
const SWAY_REST := 0.002
## 彈簧每一小步最長多久、一格最多算幾小步：掉格時（一格很長）分成小步算才不會算爆；再長就當成慢動作。
const SWAY_STEP := 1.0 / 120.0
const SWAY_MAX_STEPS := 8
## 手臂轉到目標角度的速度（度／秒）：後拉慢、出手快、收回中等。
const ARM_SPEED_WARN := 110.0
const ARM_SPEED_STRIKE := 900.0
const ARM_SPEED_RETURN := 140.0

static var _table: Dictionary = {}
static var _table_loaded := false

## 狀態燈的位置（訓練站的本地座標，腳底為原點）。
var lamp_at := Vector2.ZERO

var _sway_max := 0.0
var _sway := 0.0
var _sway_speed := 0.0
var _arms: Array[Node2D] = []
var _arm_rest := 0.0
var _arm_warn := 0.0
var _arm_strike := 0.0
var _arm_targets: Array[float] = []
var _arm_speed := ARM_SPEED_RETURN


## 依訓練種類建立外觀並掛在 station 底下（畫在 station 自己的燈號後面）。沒有對應資料或圖讀不到回傳 null。
static func build(station: Node2D, kind_name: String) -> TrainingArt:
	var entry: Dictionary = _entry(kind_name)
	if entry.is_empty():
		return null
	var pack := str(_table.get("pack", DEFAULT_PACK))
	var body := PropLibrary.find(StringName(str(entry.get("prop", ""))), pack)
	if body == null:
		push_error("[TrainingArt] %s 的器材圖 %s 不在 %s，改用簡單畫法" % [kind_name, entry.get("prop", ""), pack])
		return null
	var art := TrainingArt.new()
	art.name = "TrainingArt"
	art.show_behind_parent = true
	art.lamp_at = _vector(entry.get("lamp"), Vector2(0.0, -body.size.y - 3.0))
	art._sway_max = deg_to_rad(float(entry.get("sway_deg", 0.0)))
	art._add_prop(art, body, Vector2(-body.size.x * 0.5, -body.size.y), false)
	var arm: Dictionary = entry.get("arm", {})
	if not arm.is_empty():
		art._add_arms(arm, pack, kind_name)
	station.add_child(art)
	art.set_process(false)
	return art


## 被打中：往受力方向晃一下再彈回來（direction＝-1 往左、1 往右）。
func hit(direction: float) -> void:
	if _sway_max <= 0.0:
		return
	_sway_speed = signf(direction if direction != 0.0 else 1.0) * _sway_max * SWAY_OMEGA
	set_process(true)


## 訓練器的手臂：warn＝兩支都後拉；strike＝朝 side（-1 左、1 右）那一支打出去；其餘回到待機。
func set_arm_phase(phase: StringName, side := 0) -> void:
	if _arms.is_empty():
		return
	for i in _arms.size():
		_arm_targets[i] = _arm_rest
	match phase:
		&"warn":
			_arm_speed = ARM_SPEED_WARN
			for i in _arms.size():
				_arm_targets[i] = _arm_warn
		&"strike":
			_arm_speed = ARM_SPEED_STRIKE
			_arm_targets[0 if side < 0 else 1] = _arm_strike
		_:
			_arm_speed = ARM_SPEED_RETURN
	set_process(true)


func _process(delta: float) -> void:
	var busy := false
	if _sway != 0.0 or _sway_speed != 0.0:
		# 阻尼彈簧（半隱式積分，分成小步，不配置記憶體）。
		var steps := clampi(ceili(delta / SWAY_STEP), 1, SWAY_MAX_STEPS)
		var step := minf(delta / steps, SWAY_STEP)
		for i in steps:
			_sway_speed += (-SWAY_OMEGA * SWAY_OMEGA * _sway - 2.0 * SWAY_DAMPING * SWAY_OMEGA * _sway_speed) * step
			_sway += _sway_speed * step
		if absf(_sway) < SWAY_REST and absf(_sway_speed) < SWAY_REST * SWAY_OMEGA:
			_sway = 0.0
			_sway_speed = 0.0
		else:
			busy = true
		rotation = _sway
	for i in _arms.size():
		# 左手臂是鏡像的，角度反過來才是同一個動作。
		var mirror := -1.0 if i == 0 else 1.0
		var target := deg_to_rad(_arm_targets[i]) * mirror
		var arm := _arms[i]
		arm.rotation = move_toward(arm.rotation, target, deg_to_rad(_arm_speed) * delta)
		if not is_equal_approx(arm.rotation, target):
			busy = true
	if not busy:
		set_process(false)


func _add_arms(arm: Dictionary, pack: String, kind_name: String) -> void:
	var data := PropLibrary.find(StringName(str(arm.get("prop", ""))), pack)
	if data == null:
		push_error("[TrainingArt] %s 的手臂圖 %s 不在 %s，只顯示機身" % [kind_name, arm.get("prop", ""), pack])
		return
	var shoulder := _vector(arm.get("shoulder"), Vector2(0.0, -30.0))
	var spread := float(arm.get("spread", 4.0))
	_arm_rest = float(arm.get("rest_deg", 20.0))
	_arm_warn = float(arm.get("warn_deg", -50.0))
	_arm_strike = float(arm.get("strike_deg", -5.0))
	for side: float in [-1.0, 1.0]:
		var pivot := Node2D.new()
		pivot.name = "ArmLeft" if side < 0.0 else "ArmRight"
		pivot.position = shoulder + Vector2(spread * side, 0.0)
		pivot.rotation = deg_to_rad(_arm_rest) * side
		add_child(pivot)
		# 手臂的圖：樞紐在左端、拳墊在右端；左手臂整張鏡像，樞紐才會留在肩上。
		var top_left := Vector2(-data.size.x if side < 0.0 else 0.0, -data.size.y * 0.5)
		_add_prop(pivot, data, top_left, side < 0.0)
		_arms.append(pivot)
		_arm_targets.append(_arm_rest)


func _add_prop(parent: Node2D, data: PropData, top_left: Vector2, flip: bool) -> void:
	var node := PropNode.new()
	node.setup(data, top_left, flip)
	parent.add_child(node)


static func _entry(kind_name: String) -> Dictionary:
	if not _table_loaded:
		_table_loaded = true
		_table = _load_table()
	var kinds: Variant = _table.get("kinds", {})
	if kinds is Dictionary and kinds.get(kind_name) is Dictionary:
		return kinds[kind_name]
	return {}


static func _load_table() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_error("[TrainingArt] 找不到 %s，訓練器材改用簡單畫法" % TABLE_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	if not parsed is Dictionary:
		push_error("[TrainingArt] %s 不是有效的 JSON 物件，訓練器材改用簡單畫法" % TABLE_PATH)
		return {}
	return parsed


static func _vector(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2(float(value[0]), float(value[1]))
	return fallback


## 測試用：清掉讀過的資料，下次重新讀檔。
static func clear_cache() -> void:
	_table = {}
	_table_loaded = false
