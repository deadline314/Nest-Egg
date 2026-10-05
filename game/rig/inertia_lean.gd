class_name InertiaLean
extends RefCounted
## 慣性前傾：身體隨「加速度」前傾或後仰，用彈簧追目標，所以起步前傾、煞車後仰、反向時有過衝，不是一按鍵就切到跑姿。
## 輸入是角色自己的前進方向速度（骨架空間，面向為正）；輸出是要加到胸的角度（弧度，正＝前傾）。
## 參數（動作資料的 inertia 段）：gain＝滿加速度時的角度（0＝不啟用）、ref_accel＝算滿加速度的基準（像素／秒²）、
## stiffness／damping＝彈簧、max＝角度上限。

## 加速度的平滑速度（每秒）：物理在 60 Hz 算速度，直接差分會抖。
const ACCEL_SMOOTHING := 25.0
## 單次彈簧積分的最長時間（秒），超過就切成多步，避免大 delta 時發散。
const MAX_STEP := 1.0 / 120.0

var _value := 0.0
var _velocity := 0.0
var _previous_speed := NAN
var _accel := 0.0


## 面向翻轉、瞬移、重生時呼叫：忘掉上一格的速度，避免把「翻轉造成的速度符號改變」誤算成巨大的加速度。
func reset(speed := NAN) -> void:
	_previous_speed = speed
	_accel = 0.0


## 回傳這一格的前傾角度。params 缺欄位時視為不啟用。
func update(delta: float, speed: float, params: Dictionary) -> float:
	var gain := float(params.get("gain", 0.0))
	if gain <= 0.0 or delta <= 0.0:
		_previous_speed = speed
		_value = 0.0
		_velocity = 0.0
		return 0.0
	if is_nan(_previous_speed):
		_previous_speed = speed
	_accel = lerpf(_accel, (speed - _previous_speed) / delta, 1.0 - exp(-ACCEL_SMOOTHING * delta))
	_previous_speed = speed
	var limit := float(params.get("max", 0.3))
	var target := clampf(_accel / maxf(1.0, float(params.get("ref_accel", 1600.0))), -1.0, 1.0) * gain
	var stiffness := float(params.get("stiffness", 90.0))
	var damping := float(params.get("damping", 11.0))
	var steps := maxi(1, ceili(delta / MAX_STEP))
	var dt := delta / steps
	for i in steps:
		_velocity += ((target - _value) * stiffness - _velocity * damping) * dt
		_value = clampf(_value + _velocity * dt, -limit, limit)
	return _value
