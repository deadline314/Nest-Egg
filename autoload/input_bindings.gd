extends Node
## 預設按鍵配置。
## 動作若已在專案設定的 Input Map 中定義（例如玩家自訂），則不覆寫。

const DEADZONE := 0.4

const KEYS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"jump": [KEY_K, KEY_SPACE],
	&"shoot": [KEY_J],
	&"dash": [KEY_L, KEY_SHIFT],
	&"melee": [KEY_I],
	&"swap_weapon": [KEY_U],
	&"aim_lock": [KEY_O],
	&"interact": [KEY_E],
	&"pause": [KEY_ESCAPE, KEY_P],
}

const JOY_BUTTONS := {
	&"move_left": [JOY_BUTTON_DPAD_LEFT],
	&"move_right": [JOY_BUTTON_DPAD_RIGHT],
	&"move_up": [JOY_BUTTON_DPAD_UP],
	&"move_down": [JOY_BUTTON_DPAD_DOWN],
	&"jump": [JOY_BUTTON_A],
	&"shoot": [JOY_BUTTON_X],
	&"dash": [JOY_BUTTON_B],
	&"melee": [JOY_BUTTON_Y],
	&"swap_weapon": [JOY_BUTTON_LEFT_SHOULDER],
	&"aim_lock": [JOY_BUTTON_RIGHT_SHOULDER],
	&"interact": [JOY_BUTTON_BACK],
	&"pause": [JOY_BUTTON_START],
}

## [軸, 方向]
const JOY_AXES := {
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}


func _ready() -> void:
	for action: StringName in KEYS.keys():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		for keycode: Key in KEYS[action]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode
			InputMap.action_add_event(action, key_event)
		for button: JoyButton in JOY_BUTTONS.get(action, []):
			var joy_event := InputEventJoypadButton.new()
			joy_event.button_index = button
			InputMap.action_add_event(action, joy_event)
		if JOY_AXES.has(action):
			var axis_def: Array = JOY_AXES[action]
			var motion := InputEventJoypadMotion.new()
			motion.axis = axis_def[0]
			motion.axis_value = axis_def[1]
			InputMap.action_add_event(action, motion)
