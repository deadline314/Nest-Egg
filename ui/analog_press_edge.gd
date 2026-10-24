extends RefCounted
## A held analog input is one confirmation, even if its pressure keeps changing.
## Digital events retain their existing behavior, including explicit repeat rules.
var _axes: Dictionary[Vector2i, float] = {}


func sync() -> void:
	_axes.clear()
	for device: int in Input.get_connected_joypads():
		for axis in JOY_AXIS_MAX:
			_axes[Vector2i(device, axis)] = Input.get_joy_axis(device, axis)


func is_action_pressed(event: InputEvent, action: StringName) -> bool:
	if not event is InputEventJoypadMotion:
		return event.is_action_pressed(action)
	var motion := event as InputEventJoypadMotion
	var key := Vector2i(motion.device, motion.axis)
	var previous: float = _axes.get(key, 0.0)
	_axes[key] = motion.axis_value
	return event.is_action_pressed(action) and previous * signf(motion.axis_value) < InputMap.action_get_deadzone(action)
