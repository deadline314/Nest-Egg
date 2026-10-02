class_name LevelCamera
extends Camera2D
## 平台射擊遊戲鏡頭（依業界常見做法）：
##   - 前瞻：鏡頭偏向角色面向，讓玩家看得到前方敵人
##   - 垂直死區：空中小跳躍不晃鏡頭，落地或離開死區才跟隨
##   - trauma 震動：強度平方衰減 + 噪聲，比純隨機震動自然
##   - 射擊後座：方向性位移，快速回彈

const LOOK_AHEAD := 56.0
const LOOK_AHEAD_SPEED := 2.5
const VERTICAL_OFFSET := -28.0
const DEADZONE_UP := 72.0
const DEADZONE_DOWN := 24.0
const MAX_SHAKE_OFFSET := 9.0
const MAX_SHAKE_ROTATION := 0.025
const TRAUMA_PER_STRENGTH := 0.08
const TRAUMA_DECAY := 1.8
const KICK_RECOVERY := 16.0
const MAX_KICK := 8.0

var target: Node2D

var _trauma := 0.0
var _kick := Vector2.ZERO
var _look := 0.0
var _anchor_y := 0.0
var _noise := FastNoiseLite.new()
var _noise_time := 0.0


func _ready() -> void:
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
	_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * delta)
	_kick = _kick.lerp(Vector2.ZERO, minf(1.0, KICK_RECOVERY * delta))
	_noise_time += delta * 60.0
	var shake := _trauma * _trauma
	offset = _kick + Vector2(_noise.get_noise_2d(_noise_time, 0.0), _noise.get_noise_2d(0.0, _noise_time)) * MAX_SHAKE_OFFSET * shake * 2.0
	rotation = MAX_SHAKE_ROTATION * shake * _noise.get_noise_2d(_noise_time, 100.0) * 2.0


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


func _on_screen_shake(strength: float, _duration: float) -> void:
	_trauma = minf(1.0, _trauma + strength * TRAUMA_PER_STRENGTH)


func _on_camera_kick(kick_offset: Vector2) -> void:
	_kick = (_kick + kick_offset).limit_length(MAX_KICK)
