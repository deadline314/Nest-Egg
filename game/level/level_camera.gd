class_name LevelCamera
extends Camera2D
## 平台射擊遊戲鏡頭（依業界常見做法）：
##   - 前瞻：鏡頭偏向角色面向，讓玩家看得到前方敵人
##   - 垂直死區：空中小跳躍不晃鏡頭，落地或離開死區才跟隨
##   - trauma 震動：強度平方衰減 + 噪聲，比純隨機震動自然
##   - 射擊後座：方向性位移，快速回彈

## 基礎縮放倍率（畫面 640×360，視野 = 640／ZOOM × 360／ZOOM 世界像素）：主角是畫面主角，所以拉近到角色約佔畫面高度兩成多；
## 縮放越大視野越小，前瞻、瞄準偏移、垂直偏移與死區都要跟著這個值調（見下面各項），改縮放只改這一個常數。
## 1.5 時視野 427×240，前方（前瞻＋瞄準偏移）看得到約 300 像素，涵蓋大多數敵人的攻擊距離（240～300）。
const ZOOM := 1.5
const LOOK_AHEAD := 56.0
const LOOK_AHEAD_SPEED := 2.5
const VERTICAL_OFFSET := -32.0
const DEADZONE_UP := 60.0
const DEADZONE_DOWN := 20.0
## 下落時鏡頭往下看：下落速度超過 FALL_LOOK_FROM 後，每增加一份速度往下多看 FALL_LOOK_GAIN 像素（上限 FALL_LOOK_MAX），讓玩家看得到要落下去的地方。
const FALL_LOOK_FROM := 200.0
const FALL_LOOK_GAIN := 0.1
const FALL_LOOK_MAX := 36.0
const FALL_LOOK_SPEED := 4.0
const MAX_SHAKE_PX := 12.0
const SHAKE_ROTATION_PER_PX := 0.0014
const MAX_SHAKES := 8
## 震動來源超過這段距離（像素）後開始衰減，最遠剩 25%。
const SHAKE_FALLOFF_START := 240.0
const SHAKE_FALLOFF_RANGE := 640.0
const DIRECTIONAL_FREQUENCY := 16.0
## 瞄準前瞻：鏡頭往準星方向偏移的像素，垂直只取一半。
const AIM_LOOK := 30.0
const AIM_LOOK_SPEED := 5.0
const KICK_RECOVERY := 16.0
const MAX_KICK := 8.0

var _shake_reader := Callable()
var _zoom_reader := Callable()
var target: Node2D

## 進行中的震動：[峰值像素, 總秒數, 剩餘秒數, 方向]。
var _shakes: Array[Array] = []
## 縮放脈衝：[幅度, 總秒數, 剩餘秒數]。
var _pulse: Array = []
var _aim_look := Vector2.ZERO
var _kick := Vector2.ZERO
var _look := 0.0
var _fall_look := 0.0
var _anchor_y := 0.0
var _noise := FastNoiseLite.new()
var _noise_time := 0.0


func _ready() -> void:
	zoom = Vector2.ONE * ZOOM
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = true
	position_smoothing_speed = 7.0
	limit_smoothed = true
	ignore_rotation = false
	_noise.frequency = 0.15
	EventBus.screen_shake.connect(_on_screen_shake)
	EventBus.camera_kick.connect(_on_camera_kick)
	EventBus.camera_zoom_pulse.connect(_on_zoom_pulse)
	_shake_reader = func() -> float: return snappedf(offset.length(), 0.1)
	_zoom_reader = func() -> float: return snappedf(zoom.x, 0.001)
	Feel.register_counter("camera_shake_px", _shake_reader)
	Feel.register_counter("camera_zoom", _zoom_reader)
	make_current()


func _exit_tree() -> void:
	# 診斷面板還會讀這兩個計數，鏡頭離開後不能留下指向自己的讀取函式。
	Feel.unregister_counter("camera_shake_px", _shake_reader)
	Feel.unregister_counter("camera_zoom", _zoom_reader)


func set_bounds(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


## 鎖住左界（頭目戰），鏡頭平滑推進。
func lock_left(x: float) -> void:
	limit_left = int(x)


## 立即跳到目標位置（重生時避免鏡頭從遠處滑過來）。
func snap_to_target() -> void:
	if not is_instance_valid(target):
		return
	_anchor_y = target.global_position.y
	_look = _facing() * LOOK_AHEAD
	_fall_look = 0.0
	global_position = _desired_position()
	reset_smoothing()


func _physics_process(delta: float) -> void:
	if is_instance_valid(target):
		_look = lerpf(_look, _facing() * LOOK_AHEAD, minf(1.0, LOOK_AHEAD_SPEED * delta))
		var y := target.global_position.y
		if _is_grounded():
			_anchor_y = y
		elif y > _anchor_y + DEADZONE_DOWN:
			_anchor_y = y - DEADZONE_DOWN
		elif y < _anchor_y - DEADZONE_UP:
			_anchor_y = y + DEADZONE_UP
		_update_aim_look(delta)
		_update_fall_look(delta)
		global_position = _desired_position()
	_kick = _kick.lerp(Vector2.ZERO, minf(1.0, KICK_RECOVERY * delta))
	_noise_time += delta * 60.0
	var shake_offset := _shake_offset(delta)
	offset = _kick + shake_offset
	rotation = SHAKE_ROTATION_PER_PX * shake_offset.length() * _noise.get_noise_2d(_noise_time, 100.0) * 2.0
	zoom = Vector2.ONE * ZOOM * (1.0 + _pulse_amount(delta))


func _desired_position() -> Vector2:
	return Vector2(target.global_position.x + _look, _anchor_y + VERTICAL_OFFSET + _fall_look) + _aim_look


func _facing() -> float:
	var player := target as Player
	return float(player.facing) if player != null else 1.0


func _is_grounded() -> bool:
	var player := target as Player
	if player != null and is_instance_valid(player.mounted_vehicle):
		return player.mounted_vehicle.is_on_floor()
	var body := target as CharacterBody2D
	return body.is_on_floor() if body != null else true


## 把進行中的震動加總成鏡頭位移：每個震動從峰值像素隨剩餘時間平方衰減，持續秒數真的生效；
## 有方向的震動沿方向來回衰減（加一點雜訊），沒有方向的用雜訊；總量有上限。
func _shake_offset(delta: float) -> Vector2:
	var total := Vector2.ZERO
	var noise := Vector2(_noise.get_noise_2d(_noise_time, 0.0), _noise.get_noise_2d(0.0, _noise_time)) * 2.0
	for i in range(_shakes.size() - 1, -1, -1):
		var entry := _shakes[i]
		entry[2] = float(entry[2]) - delta
		if float(entry[2]) <= 0.0:
			_shakes.remove_at(i)
			continue
		var k := float(entry[2]) / float(entry[1])
		var amplitude := float(entry[0]) * k * k
		var direction: Vector2 = entry[3]
		if direction == Vector2.ZERO:
			total += noise * amplitude
		else:
			total += direction * sin(float(entry[2]) * TAU * DIRECTIONAL_FREQUENCY) * amplitude + noise * amplitude * 0.25
	return total.limit_length(MAX_SHAKE_PX)


func _shake_magnitude(delta: float) -> float:
	return _shake_offset(delta).length()


func _on_screen_shake(px: float, duration: float, direction: Vector2, origin: Vector2) -> void:
	if origin != Vector2.INF:
		var falloff := clampf(1.0 - (origin.distance_to(global_position) - SHAKE_FALLOFF_START) / SHAKE_FALLOFF_RANGE, 0.25, 1.0)
		px *= falloff
	if _shakes.size() >= MAX_SHAKES:
		_shakes.remove_at(0)
	_shakes.append([px, duration, duration, direction.normalized()])


func _on_zoom_pulse(amount: float, duration: float) -> void:
	if duration > 0.0:
		_pulse = [amount, duration, duration]


## 縮放脈衝：先拉近再回復（正弦一個半週期）。
func _pulse_amount(delta: float) -> float:
	if _pulse.is_empty():
		return 0.0
	_pulse[2] = float(_pulse[2]) - delta
	if float(_pulse[2]) <= 0.0:
		_pulse = []
		return 0.0
	return float(_pulse[0]) * sin(PI * (1.0 - float(_pulse[2]) / float(_pulse[1])))


## 鏡頭往準星方向偏移一點；暫時不能瞄準（講電話、死亡）時固定不動。
func _update_aim_look(delta: float) -> void:
	var player := target as Player
	var goal := Vector2.ZERO
	if player != null and not player.is_dead() and not player.is_on_phone():
		goal = Vector2(player.aim_dir.x, player.aim_dir.y * 0.5) * AIM_LOOK
		_aim_look = _aim_look.lerp(goal, minf(1.0, AIM_LOOK_SPEED * delta))


## 下落時鏡頭往下看（視野拉近後腳下的空間變少）；落地或上升時平滑回到原位。
func _update_fall_look(delta: float) -> void:
	var body := target as CharacterBody2D
	var fall_speed := body.velocity.y if body != null and not _is_grounded() else 0.0
	var goal := clampf((fall_speed - FALL_LOOK_FROM) * FALL_LOOK_GAIN, 0.0, FALL_LOOK_MAX)
	_fall_look = lerpf(_fall_look, goal, minf(1.0, FALL_LOOK_SPEED * delta))


func _on_camera_kick(kick_offset: Vector2) -> void:
	_kick = (_kick + kick_offset).limit_length(MAX_KICK)
