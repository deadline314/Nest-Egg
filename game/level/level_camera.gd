class_name LevelCamera
extends Camera2D
## 平台射擊遊戲鏡頭（依業界常見做法）：
##   - 前瞻：鏡頭偏向角色面向，讓玩家看得到前方敵人
##   - 垂直死區：空中小跳躍不晃鏡頭，落地或離開死區才跟隨
##   - trauma 震動：強度平方衰減 + 噪聲，比純隨機震動自然
##   - 射擊後座：方向性位移，快速回彈

## 鏡頭拉近倍率：角色放大後仍保留足夠的前方視野。
const ZOOM := 1.25
const LOOK_AHEAD := 48.0
const LOOK_AHEAD_SPEED := 2.5
const VERTICAL_OFFSET := -36.0
const DEADZONE_UP := 72.0
const DEADZONE_DOWN := 24.0
const MAX_SHAKE_PX := 12.0
const SHAKE_ROTATION_PER_PX := 0.0014
const MAX_SHAKES := 8
const KICK_RECOVERY := 16.0
const MAX_KICK := 8.0

var target: Node2D

## 進行中的震動：[峰值像素, 總秒數, 剩餘秒數]。
var _shakes: Array[Array] = []
var _kick := Vector2.ZERO
var _look := 0.0
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
	make_current()


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
		global_position = _desired_position()
	_kick = _kick.lerp(Vector2.ZERO, minf(1.0, KICK_RECOVERY * delta))
	_noise_time += delta * 60.0
	var magnitude := _shake_magnitude(delta)
	offset = _kick + Vector2(_noise.get_noise_2d(_noise_time, 0.0), _noise.get_noise_2d(0.0, _noise_time)) * magnitude * 2.0
	rotation = SHAKE_ROTATION_PER_PX * magnitude * _noise.get_noise_2d(_noise_time, 100.0) * 2.0


func _desired_position() -> Vector2:
	return Vector2(target.global_position.x + _look, _anchor_y + VERTICAL_OFFSET)


func _facing() -> float:
	var player := target as Player
	return float(player.facing) if player != null else 1.0


func _is_grounded() -> bool:
	var player := target as Player
	if player != null and is_instance_valid(player.mounted_vehicle):
		return player.mounted_vehicle.is_on_floor()
	var body := target as CharacterBody2D
	return body.is_on_floor() if body != null else true


## 把進行中的震動加總：每個震動從峰值像素隨剩餘時間平方衰減，持續秒數真的生效。
func _shake_magnitude(delta: float) -> float:
	var total := 0.0
	for i in range(_shakes.size() - 1, -1, -1):
		var entry := _shakes[i]
		entry[2] = float(entry[2]) - delta
		if float(entry[2]) <= 0.0:
			_shakes.remove_at(i)
			continue
		var k := float(entry[2]) / float(entry[1])
		total += float(entry[0]) * k * k
	return minf(total, MAX_SHAKE_PX)


func _on_screen_shake(px: float, duration: float) -> void:
	if _shakes.size() >= MAX_SHAKES:
		_shakes.remove_at(0)
	_shakes.append([px, duration, duration])


func _on_camera_kick(kick_offset: Vector2) -> void:
	_kick = (_kick + kick_offset).limit_length(MAX_KICK)
