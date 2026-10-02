class_name CountUpLabel
extends Label
## 數字跳動：從 0（或目前的值）在短時間內數到目標值。format 把數值轉成顯示文字。

const DURATION := 0.55

var _value := 0.0
var _format := Callable()
var _tween: Tween


func count_to(target: float, format: Callable, from_zero := true) -> void:
	_format = format
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not from_zero or is_equal_approx(_value, target):
		_set_value(target)
		return
	_set_value(0.0)
	_tween = create_tween()
	_tween.tween_method(_set_value, 0.0, target, DURATION).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _set_value(value: float) -> void:
	_value = value
	text = str(_format.call(value)) if _format.is_valid() else str(roundi(value))
