class_name FootGait
extends RefCounted
## 一隻腳的落腳狀態：釘在地上（世界座標不動）或正在跨步（沿拋物線抬起、前伸、落地）。
## 何時跨步由 ChainCreature 統一排程（多條腿交替），這裡只管單隻腳的軌跡。

var foot := Vector2.ZERO
var group := 0
var stepping := false
## 這一影格剛落地（給腳步特效與身體起伏用）。
var landed := false

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0
var _duration := 0.3
var _lift := 0.0


func place(at: Vector2) -> void:
	foot = at
	stepping = false


func begin_step(to: Vector2, duration: float, lift: float) -> void:
	_from = foot
	_to = to
	_t = 0.0
	_duration = maxf(0.05, duration)
	_lift = lift
	stepping = true


## 前進 delta 秒；回傳這一影格是否落地。
func advance(delta: float) -> bool:
	landed = false
	if not stepping:
		return false
	_t = minf(1.0, _t + delta / _duration)
	var eased := _t * _t * (3.0 - 2.0 * _t)
	foot = _from.lerp(_to, eased) + Vector2(0.0, -_lift * sin(PI * _t))
	if _t >= 1.0:
		foot = _to
		stepping = false
		landed = true
	return landed


## 目前跨步的目標（釘住時就是腳的位置）。
func target() -> Vector2:
	return _to if stepping else foot
