extends HumanoidAnimator
## Deliberately discard the idle contact target during gait solving: the original failure.


func _step_legs() -> void:
	var saved := _idle_pin_w
	_idle_pin_w = 0.0
	super._step_legs()
	_idle_pin_w = saved
