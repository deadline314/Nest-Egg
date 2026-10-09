extends Node
## 按鍵綁定服務：預設配置、玩家自訂、衝突處理、存檔與按鍵名稱顯示。
##
## 每個動作有 2 個「鍵盤／滑鼠」欄位與 1 個手把按鈕欄位。
## 欄位以整數代碼儲存：正數 = 鍵盤實體鍵碼，負數 = 滑鼠按鈕（-1 左鍵、-4 滾輪上…），0 = 空。
## 搖桿方向、扳機與數字鍵選武器為固定綁定（避免玩家把移動或瞄準改壞）。
## 綁定到已被使用的按鍵時會「互換」，保證每個動作永遠有輸入可用。
## 文字中的 {動作} 佔位符（例如 "{jump} 跳躍"）可用 format() 換成目前的按鍵名稱。

signal bindings_changed
signal device_changed(gamepad: bool, device: int)
signal controller_options_changed
signal controller_interrupted_changed(interrupted: bool)

const CONTROLLER_SECTION := "controller"
const AIM_DEADZONE_DEFAULT := 0.3
const AXIS_SWITCH_DELTA := 0.08
const MOUSE_SWITCH_DISTANCE := 2.0
const NAVIGATION_REPEAT_DELAY := 0.35
const NAVIGATION_REPEAT_INTERVAL := 0.1
const UI_ACTIONS: Dictionary[StringName, Array] = {
	&"ui_accept": [KEY_ENTER, JOY_BUTTON_A], &"ui_cancel": [KEY_ESCAPE, JOY_BUTTON_B],
	&"ui_up": [KEY_UP, JOY_BUTTON_DPAD_UP], &"ui_down": [KEY_DOWN, JOY_BUTTON_DPAD_DOWN],
	&"ui_left": [KEY_LEFT, JOY_BUTTON_DPAD_LEFT], &"ui_right": [KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT],
}

const DEADZONE := 0.4
const TRIGGER_DEADZONE := 0.3
const KEY_SLOTS := 2
const SETTINGS_SECTION := "input"
## 綁定格式版本。預設操作大改時遞增，舊存檔會自動改回新預設。
const SCHEMA_VERSION := 3
const SCHEMA_KEY := "_schema"
const NONE := 0

## 動作的顯示順序與名稱（設定選單依此排列）。
const ACTIONS: Array[Dictionary] = [
	{"id": &"move_left", "label": "左移"},
	{"id": &"move_right", "label": "右移"},
	{"id": &"move_down", "label": "蹲下／落下平台"},
	{"id": &"jump", "label": "跳躍"},
	{"id": &"shoot", "label": "射擊"},
	{"id": &"block", "label": "格擋"},
	{"id": &"dash", "label": "衝刺"},
	{"id": &"melee", "label": "近戰／終結"},
	{"id": &"weapon_next", "label": "下一把武器"},
	{"id": &"weapon_prev", "label": "上一把武器"},
	{"id": &"reload", "label": "換彈"},
	{"id": &"use_item", "label": "使用醫療針"},
	{"id": &"ability", "label": "義體能力"},
	{"id": &"interact", "label": "搭乘／互動"},
	{"id": &"inventory", "label": "背包"},
	{"id": &"pause", "label": "暫停"},
	{"id": &"quests", "label": "任務目錄"},
	{"id": &"map", "label": "地圖"},
]

const DEFAULT_CODES: Dictionary[StringName, Array] = {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_down": [KEY_S, KEY_DOWN],
	&"jump": [KEY_SPACE, KEY_W],
	&"shoot": [-MOUSE_BUTTON_LEFT, KEY_J],
	&"block": [-MOUSE_BUTTON_RIGHT, KEY_K],
	&"dash": [KEY_SHIFT, KEY_L],
	&"melee": [KEY_F, NONE],
	&"weapon_next": [-MOUSE_BUTTON_WHEEL_DOWN, NONE],
	&"weapon_prev": [-MOUSE_BUTTON_WHEEL_UP, NONE],
	&"reload": [KEY_R, NONE],
	&"use_item": [KEY_Q, NONE],
	&"ability": [KEY_C, NONE],
	&"interact": [KEY_E, NONE],
	&"inventory": [KEY_TAB, KEY_I],
	&"pause": [KEY_ESCAPE, KEY_P],
	&"quests": [KEY_O, NONE],
	&"map": [KEY_M, NONE],
}

const DEFAULT_JOY_BUTTONS: Dictionary[StringName, int] = {
	&"move_left": JOY_BUTTON_DPAD_LEFT,
	&"move_right": JOY_BUTTON_DPAD_RIGHT,
	&"move_down": JOY_BUTTON_DPAD_DOWN,
	&"jump": JOY_BUTTON_A,
	&"shoot": -1,
	&"block": -1,
	&"dash": JOY_BUTTON_B,
	&"melee": JOY_BUTTON_Y,
	&"weapon_next": JOY_BUTTON_RIGHT_SHOULDER,
	&"weapon_prev": JOY_BUTTON_LEFT_SHOULDER,
	&"reload": JOY_BUTTON_RIGHT_STICK,
	&"use_item": JOY_BUTTON_DPAD_UP,
	&"ability": JOY_BUTTON_LEFT_STICK,
	&"interact": JOY_BUTTON_X,
	&"inventory": JOY_BUTTON_BACK,
	&"pause": JOY_BUTTON_START,
	&"quests": -1,
	&"map": -1,
}

## 固定的手把軸綁定。[軸, 方向]
const JOY_AXES: Dictionary[StringName, Array] = {
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"move_down": [JOY_AXIS_LEFT_Y, 1.0],
	&"shoot": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	&"block": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

## 不顯示在設定選單的固定動作（右搖桿瞄準、數字鍵直選武器、背包分頁切換）。
## 規格：[&"axis", 軸, 方向]、[&"key", 鍵碼]、[&"button", 手把按鈕]。
const FIXED_ACTIONS: Dictionary[StringName, Array] = {
	&"aim_left": [[&"axis", JOY_AXIS_RIGHT_X, -1.0]],
	&"aim_right": [[&"axis", JOY_AXIS_RIGHT_X, 1.0]],
	&"aim_up": [[&"axis", JOY_AXIS_RIGHT_Y, -1.0]],
	&"aim_down": [[&"axis", JOY_AXIS_RIGHT_Y, 1.0]],
	&"weapon_slot_1": [[&"key", KEY_1]],
	&"weapon_slot_2": [[&"key", KEY_2]],
	&"weapon_slot_3": [[&"key", KEY_3]],
	&"weapon_slot_4": [[&"key", KEY_4]],
	&"inventory_prev_tab": [[&"key", KEY_Q], [&"button", JOY_BUTTON_LEFT_SHOULDER]],
	&"inventory_next_tab": [[&"key", KEY_E], [&"button", JOY_BUTTON_RIGHT_SHOULDER]],
}

## 無法被綁定的鍵（Esc 用於取消設定；F 鍵保留給系統／除錯；數字鍵用於直選武器）。
const RESERVED_CODES: Array[int] = [KEY_ESCAPE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_F1, KEY_F2, KEY_F3, KEY_F4,
	KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12]

const MOUSE_LABELS: Dictionary[int, String] = {
	MOUSE_BUTTON_LEFT: "左鍵", MOUSE_BUTTON_RIGHT: "右鍵", MOUSE_BUTTON_MIDDLE: "中鍵",
	MOUSE_BUTTON_WHEEL_UP: "滾輪↑", MOUSE_BUTTON_WHEEL_DOWN: "滾輪↓",
	MOUSE_BUTTON_WHEEL_LEFT: "滾輪←", MOUSE_BUTTON_WHEEL_RIGHT: "滾輪→",
	MOUSE_BUTTON_XBUTTON1: "側鍵1", MOUSE_BUTTON_XBUTTON2: "側鍵2",
}

const JOY_BUTTON_LABELS: Dictionary[int, String] = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "十字↑", JOY_BUTTON_DPAD_DOWN: "十字↓",
	JOY_BUTTON_DPAD_LEFT: "十字←", JOY_BUTTON_DPAD_RIGHT: "十字→",
}

const JOY_AXIS_LABELS: Dictionary[int, String] = {
	JOY_AXIS_TRIGGER_RIGHT: "RT", JOY_AXIS_TRIGGER_LEFT: "LT",
}

## action -> [code, code]
var _codes: Dictionary[StringName, Array] = {}
## action -> JoyButton（-1 代表未綁定）
var _joy: Dictionary[StringName, int] = {}
var _placeholder_regex := RegEx.create_from_string("\\{([a-z_0-9]+)\\}")
var using_gamepad := false
var active_device := -1
var _axis_values: Dictionary[int, Dictionary] = {}
var _disconnect_token := 0
var _interrupted_player: WeakRef
var _aim_deadzone := AIM_DEADZONE_DEFAULT
var _invert_aim_y := false
var _vibration_strength := 1.0
var _navigation_action: StringName = &""
var _navigation_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_fixed_actions()
	_register_ui_controller()
	reload_from_settings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	get_window().focus_exited.connect(_on_focus_exited)
	get_tree().node_removed.connect(_on_node_removed)
	_navigation_timer = Timer.new()
	_navigation_timer.one_shot = true
	_navigation_timer.timeout.connect(_on_navigation_repeat)
	add_child(_navigation_timer)
	set_process(false)


func _input(event: InputEvent) -> void:
	observe_device(event)
	if is_controller_interrupted() and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"pause")):
		resume_after_disconnect()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] and _in_ui_context():
		_update_navigation(event.device)
		get_viewport().set_input_as_handled()


## 只處理有意義的事件。靜止搖桿的漂移、放開與鍵盤重複不切換提示。
func observe_device(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_set_device(true, event.device)
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var axes: Dictionary = _axis_values.get(event.device, {})
		var previous := float(axes.get(motion.axis, 0.0))
		axes[motion.axis] = motion.axis_value
		_axis_values[event.device] = axes
		var threshold := _aim_deadzone if motion.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y] else DEADZONE
		if motion.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			threshold = TRIGGER_DEADZONE
		if absf(motion.axis_value) > threshold and (absf(previous) <= threshold or absf(motion.axis_value - previous) >= AXIS_SWITCH_DELTA):
			_set_device(true, event.device)
	elif event is InputEventKey and event.pressed and not event.echo:
		_set_device(false)
	elif event is InputEventMouseButton and event.pressed:
		_set_device(false)
	elif event is InputEventMouseMotion and event.relative.length_squared() >= MOUSE_SWITCH_DISTANCE * MOUSE_SWITCH_DISTANCE:
		_set_device(false)


func _set_device(gamepad: bool, device := -1) -> void:
	AimInput.using_gamepad = gamepad
	if using_gamepad == gamepad and active_device == device:
		return
	_stop_navigation()
	using_gamepad = gamepad
	active_device = device
	device_changed.emit(gamepad, device)
	bindings_changed.emit()


# ---------------------------------------------------------------------------
# 查詢
# ---------------------------------------------------------------------------

func get_code(action: StringName, slot: int) -> int:
	var codes: Array = _codes.get(action, [])
	return int(codes[slot]) if slot >= 0 and slot < codes.size() else NONE


func get_joy_button(action: StringName) -> int:
	return _joy.get(action, -1)


func action_label(action: StringName) -> String:
	for entry in ACTIONS:
		if entry["id"] == action:
			return entry["label"]
	return String(action)


## 欄位代碼的顯示名稱（鍵盤依玩家實際鍵盤配置顯示，例如 AZERTY）。
func code_label(code: int) -> String:
	if code == NONE:
		return "—"
	if code < 0:
		return MOUSE_LABELS.get(-code, "滑鼠 %d" % -code)
	var display := code
	if DisplayServer.get_name() != "headless":
		var mapped := DisplayServer.keyboard_get_label_from_physical(code)
		if mapped != KEY_NONE:
			display = mapped
	var text := OS.get_keycode_string(display)
	return text if not text.is_empty() else "?"


## 手把欄位顯示名稱；沒有按鈕但有固定扳機時顯示扳機名稱。
func joy_label(action: StringName) -> String:
	if UI_ACTIONS.has(action):
		return _button_label(UI_ACTIONS[action][1])
	var button := get_joy_button(action)
	if button >= 0:
		return _button_label(button)
	if FIXED_ACTIONS.has(action):
		for spec: Array in FIXED_ACTIONS[action]:
			if spec[0] == &"button":
				return _button_label(spec[1])
			if spec[0] == &"axis":
				return _stick_label(spec[1], spec[2])
	if JOY_AXES.has(action):
		var axis: int = JOY_AXES[action][0]
		if JOY_AXIS_LABELS.has(axis):
			var name := Input.get_joy_name(active_device).to_lower() if active_device >= 0 else ""
			if name.contains("playstation") or name.contains("dualshock") or name.contains("dualsense") or name.contains("sony"):
				return "R2" if axis == JOY_AXIS_TRIGGER_RIGHT else "L2"
			if name.contains("nintendo") or name.contains("switch") or name.contains("joy-con"):
				return "ZR" if axis == JOY_AXIS_TRIGGER_RIGHT else "ZL"
			return JOY_AXIS_LABELS[axis]
		return _stick_label(axis, JOY_AXES[action][1])
	# 任務與地圖在暫停選單亦可完整操作，不虛構未綁定快捷鍵。
	if action == &"quests" or action == &"map":
		return "%s 選單" % joy_label(&"pause")
	return "—"


func _stick_label(axis: int, direction: float) -> String:
	var stick := "右搖桿" if axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y] else "左搖桿"
	if axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X]:
		return stick + ("→" if direction > 0.0 else "←")
	return stick + ("↓" if direction > 0.0 else "↑")


func _button_label(button: int) -> String:
	var name := Input.get_joy_name(active_device).to_lower() if active_device >= 0 else ""
	if name.contains("playstation") or name.contains("dualshock") or name.contains("dualsense") or name.contains("sony"):
		var labels := {JOY_BUTTON_A: "×", JOY_BUTTON_B: "○", JOY_BUTTON_X: "□", JOY_BUTTON_Y: "△", JOY_BUTTON_BACK: "Share", JOY_BUTTON_START: "Options", JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1"}
		return labels.get(button, JOY_BUTTON_LABELS.get(button, "按鈕 %d" % button))
	if name.contains("nintendo") or name.contains("switch") or name.contains("joy-con"):
		var labels := {JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X", JOY_BUTTON_BACK: "−", JOY_BUTTON_START: "+", JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R"}
		return labels.get(button, JOY_BUTTON_LABELS.get(button, "按鈕 %d" % button))
	# 未知控制器附上位置，避免把 A/B 名称當作所有手把的實體標示。
	if name.is_empty() or not (name.contains("xbox") or name.contains("xinput")):
		var positions := {JOY_BUTTON_A: "下", JOY_BUTTON_B: "右", JOY_BUTTON_X: "左", JOY_BUTTON_Y: "上"}
		if positions.has(button):
			return "%s（%s）" % [JOY_BUTTON_LABELS[button], positions[button]]
	return JOY_BUTTON_LABELS.get(button, "按鈕 %d" % button)


## 動作目前的主要輸入名稱（第一個非空欄位）。
func primary_label(action: StringName) -> String:
	if using_gamepad:
		return joy_label(action)
	if UI_ACTIONS.has(action):
		return code_label(UI_ACTIONS[action][0])
	if FIXED_ACTIONS.has(action):
		for spec: Array in FIXED_ACTIONS[action]:
			if spec[0] == &"key":
				return code_label(spec[1])
	for slot in KEY_SLOTS:
		var code := get_code(action, slot)
		if code != NONE:
			return code_label(code)
	return joy_label(action)


## 把文字中的 {action} 換成目前的按鍵名稱，例如 "{jump} 跳躍" → "Space 跳躍"。
func format(text: String) -> String:
	var result := text
	for found in _placeholder_regex.search_all(text):
		var action := StringName(found.get_string(1))
		if _codes.has(action) or FIXED_ACTIONS.has(action) or UI_ACTIONS.has(action):
			result = result.replace(found.get_string(), primary_label(action))
	return result


## 從輸入事件取得可綁定的代碼（不支援的事件回傳 NONE）。
func code_from_event(event: InputEvent) -> int:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if event is InputEventMouseButton:
		return -(event as InputEventMouseButton).button_index
	return NONE


func is_reserved(code: int) -> bool:
	return code in RESERVED_CODES


# ---------------------------------------------------------------------------
# 修改
# ---------------------------------------------------------------------------

## 綁定鍵盤／滑鼠欄位。若代碼已被其他欄位使用則互換。回傳被互換的動作（沒有則為 &""）。
func set_code(action: StringName, slot: int, code: int) -> StringName:
	if not _codes.has(action) or slot < 0 or slot >= KEY_SLOTS or is_reserved(code):
		return &""
	var previous := get_code(action, slot)
	var swapped: StringName = &""
	if code != NONE:
		for other: StringName in _codes.keys():
			for other_slot in KEY_SLOTS:
				if (other != action or other_slot != slot) and get_code(other, other_slot) == code:
					# 保留鍵（例如預設的 Esc）不會被換到其他動作上。
					_codes[other][other_slot] = NONE if is_reserved(previous) else previous
					swapped = other
					_apply(other)
					_ensure_bound(other)
	_codes[action][slot] = code
	_apply(action)
	_ensure_bound(action)
	_save()
	return swapped


## 綁定手把按鈕。若已被其他動作使用則互換。回傳被互換的動作。
func set_joy_button(action: StringName, button: int) -> StringName:
	if not joy_binding_error(action, button).is_empty():
		return &""
	var previous := get_joy_button(action)
	var swapped: StringName = &""
	for other: StringName in _joy.keys():
		if button >= 0 and other != action and _joy[other] == button:
			_joy[other] = previous
			swapped = other
			_apply(other)
	_joy[action] = button
	_apply(action)
	_save()
	return swapped


## 必要動作保留手把輸入。空欄位只能綁到空閒按鈕或有軸後備的動作。
func joy_binding_error(action: StringName, button: int) -> String:
	if not _codes.has(action) or button < -1 or button >= JOY_BUTTON_MAX:
		return "這個手把按鈕無法綁定。"
	if button == -1 and DEFAULT_JOY_BUTTONS.get(action, -1) >= 0 and not JOY_AXES.has(action):
		return "「%s」必須保留一個手把按鈕。" % action_label(action)
	if button >= 0 and get_joy_button(action) == -1:
		for other: StringName in _joy:
			if other != action and _joy[other] == button and not JOY_AXES.has(other):
				return "這是「%s」唯一的手把按鈕，請選擇空閒按鈕。" % action_label(other)
	return ""


func reset_to_defaults() -> void:
	_load_defaults()
	for entry in ACTIONS:
		_apply(entry["id"])
	Settings.erase_section(SETTINGS_SECTION)
	bindings_changed.emit()


## 從設定檔重新讀取（啟動時與切換設定檔時呼叫）。版本不符或資料損毀時退回預設值。
func reload_from_settings() -> void:
	_reload_controller_options()
	_load_defaults()
	var schema_value: Variant = Settings.get_value(SETTINGS_SECTION, SCHEMA_KEY, 1)
	var schema := 1
	if (schema_value is int or schema_value is float) and is_finite(float(schema_value)):
		schema = int(schema_value)
	else:
		push_warning("[InputBindings] input/_schema 不是有效版本號，使用預設按鍵。")
	var compatible := schema == SCHEMA_VERSION
	if not compatible and Settings.get_value(SETTINGS_SECTION, String(ACTIONS[0]["id"]), null) != null:
		push_warning("[InputBindings] 按鍵設定來自舊版操作，已改回新預設。")
		Settings.erase_section(SETTINGS_SECTION)
	for entry in ACTIONS:
		var action: StringName = entry["id"]
		if compatible:
			var saved: Variant = Settings.get_value(SETTINGS_SECTION, String(action), null)
			if typeof(saved) == TYPE_DICTIONARY:
				_restore_action(action, saved)
		_apply(action)
	_repair_controller_bindings()
	bindings_changed.emit()


# ---------------------------------------------------------------------------
# 內部
# ---------------------------------------------------------------------------

func _register_fixed_actions() -> void:
	for action: StringName in FIXED_ACTIONS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		InputMap.action_erase_events(action)
		for spec: Array in FIXED_ACTIONS[action]:
			match spec[0]:
				&"axis":
					var motion := InputEventJoypadMotion.new()
					motion.device = -1
					motion.axis = spec[1]
					motion.axis_value = spec[2]
					InputMap.action_add_event(action, motion)
				&"button":
					var button := InputEventJoypadButton.new()
					button.device = -1
					button.button_index = spec[1]
					InputMap.action_add_event(action, button)
				_:
					var key := InputEventKey.new()
					key.physical_keycode = spec[1]
					InputMap.action_add_event(action, key)


func _load_defaults() -> void:
	_codes.clear()
	_joy.clear()
	for entry in ACTIONS:
		var action: StringName = entry["id"]
		_codes[action] = (DEFAULT_CODES.get(action, [NONE, NONE]) as Array).duplicate()
		_joy[action] = DEFAULT_JOY_BUTTONS.get(action, -1)


func _restore_action(action: StringName, saved: Dictionary) -> void:
	var codes: Variant = saved.get("codes", null)
	if typeof(codes) == TYPE_ARRAY and (codes as Array).size() == KEY_SLOTS:
		var restored: Array = []
		for value in codes:
			if not (value is int or value is float) or not is_finite(float(value)):
				push_warning("[InputBindings] input/%s/codes 有非數值欄位，使用預設值。" % action)
				return
			var code := int(value)
			restored.append(NONE if is_reserved(code) and action != &"pause" else code)
		_codes[action] = restored
	else:
		push_warning("[InputBindings] %s 的按鍵設定格式錯誤，使用預設值。" % action)
	var joy: Variant = saved.get("joy", null)
	if (typeof(joy) == TYPE_INT or typeof(joy) == TYPE_FLOAT) and is_finite(float(joy)):
		var button := int(joy)
		if button >= -1 and button < JOY_BUTTON_MAX:
			_joy[action] = button
		else:
			push_warning("[InputBindings] input/%s/joy 超出手把按鈕範圍，使用預設值。" % action)
	_ensure_bound(action)


## 防呆：動作完全沒有鍵盤／滑鼠輸入時，補回預設的第一個。
func _ensure_bound(action: StringName) -> void:
	for slot in KEY_SLOTS:
		if get_code(action, slot) != NONE:
			return
	var defaults: Array = DEFAULT_CODES.get(action, [])
	if not defaults.is_empty():
		_codes[action][0] = defaults[0]
		_apply(action)


func _apply(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	InputMap.action_set_deadzone(action, TRIGGER_DEADZONE if action in [&"shoot", &"block"] else DEADZONE)
	InputMap.action_erase_events(action)
	for code: int in _codes.get(action, []):
		var event := _event_for_code(code)
		if event != null:
			InputMap.action_add_event(action, event)
	var button := get_joy_button(action)
	if button >= 0:
		var joy_event := InputEventJoypadButton.new()
		joy_event.device = -1
		joy_event.button_index = button
		InputMap.action_add_event(action, joy_event)
	if JOY_AXES.has(action):
		var axis: Array = JOY_AXES[action]
		var motion := InputEventJoypadMotion.new()
		motion.device = -1
		motion.axis = axis[0]
		motion.axis_value = axis[1]
		InputMap.action_add_event(action, motion)


func _event_for_code(code: int) -> InputEvent:
	if code > 0:
		var key := InputEventKey.new()
		key.physical_keycode = code
		return key
	if code < 0:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = -code
		return mouse
	return null


func _save() -> void:
	Settings.set_value(SETTINGS_SECTION, SCHEMA_KEY, SCHEMA_VERSION)
	for entry in ACTIONS:
		var action: StringName = entry["id"]
		Settings.set_value(SETTINGS_SECTION, String(action), {"codes": _codes[action].duplicate(), "joy": _joy[action]})
	bindings_changed.emit()


## Godot 的內建 UI 動作可能只有鍵盤事件；補上手把事件，不移除既有綁定。
func _register_ui_controller() -> void:
	for entry in [[&"ui_accept", JOY_BUTTON_A], [&"ui_cancel", JOY_BUTTON_B], [&"ui_up", JOY_BUTTON_DPAD_UP], [&"ui_down", JOY_BUTTON_DPAD_DOWN], [&"ui_left", JOY_BUTTON_DPAD_LEFT], [&"ui_right", JOY_BUTTON_DPAD_RIGHT]]:
		var action: StringName = entry[0]
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = entry[1]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	for entry in [[&"ui_up", JOY_AXIS_LEFT_Y, -1.0], [&"ui_down", JOY_AXIS_LEFT_Y, 1.0], [&"ui_left", JOY_AXIS_LEFT_X, -1.0], [&"ui_right", JOY_AXIS_LEFT_X, 1.0]]:
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = entry[1]
		event.axis_value = entry[2]
		if not InputMap.action_has_event(entry[0], event):
			InputMap.action_add_event(entry[0], event)
	for action: StringName in UI_ACTIONS:
		InputMap.action_set_deadzone(action, DEADZONE)


# Controller preferences share Settings storage without resetting keyboard binds.
func get_aim_deadzone() -> float:
	return _aim_deadzone


func set_aim_deadzone(value: float) -> void:
	_aim_deadzone = clampf(value, 0.1, 0.6) if is_finite(value) else AIM_DEADZONE_DEFAULT
	_apply_aim_deadzone()
	Settings.set_value(CONTROLLER_SECTION, "aim_deadzone", _aim_deadzone)
	controller_options_changed.emit()


func get_invert_aim_y() -> bool:
	return _invert_aim_y


func set_invert_aim_y(value: bool) -> void:
	_invert_aim_y = value
	Settings.set_value(CONTROLLER_SECTION, "invert_aim_y", value)
	controller_options_changed.emit()


func get_vibration_strength() -> float:
	return _vibration_strength


func set_vibration_strength(value: float) -> void:
	_vibration_strength = clampf(value, 0.0, 1.0) if is_finite(value) else 1.0
	Settings.set_value(CONTROLLER_SECTION, "vibration_strength", _vibration_strength)
	if is_zero_approx(_vibration_strength):
		_stop_vibration()
	controller_options_changed.emit()


func _reload_controller_options() -> void:
	_aim_deadzone = _number_option("aim_deadzone", AIM_DEADZONE_DEFAULT, 0.1, 0.6)
	_vibration_strength = _number_option("vibration_strength", 1.0, 0.0, 1.0)
	var invert: Variant = Settings.get_value(CONTROLLER_SECTION, "invert_aim_y", false)
	_invert_aim_y = invert if invert is bool else false
	if not invert is bool:
		push_warning("[InputBindings] controller/invert_aim_y 不是布林值，使用預設值。")
	_apply_aim_deadzone()
	controller_options_changed.emit()


func _number_option(key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: Variant = Settings.get_value(CONTROLLER_SECTION, key, fallback)
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), minimum, maximum)
	push_warning("[InputBindings] controller/%s 不是有效數值，使用預設值。" % key)
	return fallback


func _apply_aim_deadzone() -> void:
	for action in [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, _aim_deadzone)


## 純數學轉換與實際InputMap使用同一死區；可用合成輸入驗證，不需要硬體。
func filtered_aim(stick: Vector2) -> Vector2:
	var magnitude := minf(stick.length(), 1.0)
	if magnitude <= _aim_deadzone:
		return Vector2.ZERO
	var result := stick.normalized() * ((magnitude - _aim_deadzone) / (1.0 - _aim_deadzone))
	if _invert_aim_y:
		result.y *= -1.0
	return result


func vibration_for(weak: float, strong: float) -> Vector2:
	return Vector2(clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0)) * _vibration_strength


## 只有目前實體裝置接收回饋；數值設定完全不影響傷害、時間或防禦判定。
func vibrate(weak: float, strong: float, seconds := 0.08) -> void:
	if not using_gamepad or active_device not in Input.get_connected_joypads() or is_zero_approx(_vibration_strength):
		return
	var strength := vibration_for(weak, strong)
	Input.start_joy_vibration(active_device, strength.x, strength.y, clampf(seconds, 0.01, 0.4))


func _stop_vibration() -> void:
	for device in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)


func clear_held_inputs() -> void:
	_stop_navigation()
	for entry: Dictionary in ACTIONS:
		Input.action_release(entry["id"])
	for action: StringName in FIXED_ACTIONS:
		Input.action_release(action)
	for action: StringName in UI_ACTIONS:
		Input.action_release(action)
	_axis_values.clear()
	_stop_vibration()


func is_controller_interrupted() -> bool:
	return _disconnect_token != 0


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_axis_values.erase(device)
	if connected or not using_gamepad or active_device != device:
		return
	clear_held_inputs()
	_set_device(false)
	var player := get_tree().get_first_node_in_group(&"player")
	# Existing modal screens already protect gameplay; retain their pause/focus.
	if player != null and not get_tree().paused and not GameplayLock.is_locked():
		_disconnect_token = GameplayLock.acquire(self)
		_interrupted_player = weakref(player)
		controller_interrupted_changed.emit(true)
		EventBus.toast_requested.emit("手把已斷線，遊戲暫停。重新接上後按確認，或按 Enter 繼續。")
	else:
		EventBus.toast_requested.emit("手把已斷線，可使用鍵盤繼續操作。")


## 連線恢復本身不自動開跑；確認事件會被吞掉，避免同一次按鍵跳躍或射擊。
func resume_after_disconnect() -> void:
	if _disconnect_token == 0:
		return
	var token := _disconnect_token
	_disconnect_token = 0
	_interrupted_player = null
	clear_held_inputs()
	GameplayLock.release(token)
	controller_interrupted_changed.emit(false)


func _on_node_removed(node: Node) -> void:
	if _interrupted_player != null and _interrupted_player.get_ref() == node:
		resume_after_disconnect()


func _on_focus_exited() -> void:
	clear_held_inputs()


func _repair_controller_bindings() -> void:
	var seen: Dictionary[int, StringName] = {}
	for entry: Dictionary in ACTIONS:
		var action: StringName = entry["id"]
		var button := get_joy_button(action)
		var missing: bool = button == -1 and DEFAULT_JOY_BUTTONS.get(action, -1) >= 0 and not JOY_AXES.has(action)
		if missing or (button >= 0 and seen.has(button)):
			push_warning("[InputBindings] input/%s/joy 缺少必要手把按鈕或與其他動作重複，手把綁定改回預設。" % action)
			for default_entry: Dictionary in ACTIONS:
				var default_action: StringName = default_entry["id"]
				_joy[default_action] = DEFAULT_JOY_BUTTONS.get(default_action, -1)
				_apply(default_action)
			return
		if button >= 0:
			seen[button] = action


func _in_ui_context() -> bool:
	return get_tree().paused or get_tree().get_first_node_in_group(&"player") == null


## 搖桿導航只在UI事件與按住期間的計時器執行，不輪詢每幀的控制項。
func _update_navigation(device: int) -> void:
	var axes: Dictionary = _axis_values.get(device, {})
	var stick := Vector2(float(axes.get(JOY_AXIS_LEFT_X, 0.0)), float(axes.get(JOY_AXIS_LEFT_Y, 0.0)))
	var action: StringName = &""
	if stick.length() > DEADZONE:
		if absf(stick.x) > absf(stick.y):
			action = &"ui_right" if stick.x > 0.0 else &"ui_left"
		else:
			action = &"ui_down" if stick.y > 0.0 else &"ui_up"
	if action == _navigation_action:
		return
	_stop_navigation()
	_navigation_action = action
	if action != &"":
		_dispatch_navigation.call_deferred(action)
		_navigation_timer.start(NAVIGATION_REPEAT_DELAY)


func _stop_navigation() -> void:
	if _navigation_timer != null:
		_navigation_timer.stop()
	if _navigation_action != &"":
		Input.action_release(_navigation_action)
	_navigation_action = &""


func _dispatch_navigation(action: StringName) -> void:
	if action != _navigation_action or not _in_ui_context() or is_controller_interrupted():
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _on_navigation_repeat() -> void:
	if not _in_ui_context() or _navigation_action == &"" or is_controller_interrupted():
		_stop_navigation()
		return
	_dispatch_navigation(_navigation_action)
	_navigation_timer.start(NAVIGATION_REPEAT_INTERVAL)
