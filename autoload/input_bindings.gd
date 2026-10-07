extends Node
## 按鍵綁定服務：預設配置、玩家自訂、衝突處理、存檔與按鍵名稱顯示。
##
## 每個動作有 2 個「鍵盤／滑鼠」欄位與 1 個手把按鈕欄位。
## 欄位以整數代碼儲存：正數 = 鍵盤實體鍵碼，負數 = 滑鼠按鈕（-1 左鍵、-4 滾輪上…），0 = 空。
## 搖桿方向、扳機與數字鍵選武器為固定綁定（避免玩家把移動或瞄準改壞）。
## 綁定到已被使用的按鍵時會「互換」，保證每個動作永遠有輸入可用。
## 文字中的 {動作} 佔位符（例如 "{jump} 跳躍"）可用 format() 換成目前的按鍵名稱。

signal bindings_changed

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


func _ready() -> void:
	_register_fixed_actions()
	_register_ui_controller()
	reload_from_settings()


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
	var button := get_joy_button(action)
	if button >= 0:
		return JOY_BUTTON_LABELS.get(button, "按鈕 %d" % button)
	if JOY_AXES.has(action):
		var axis: int = JOY_AXES[action][0]
		if JOY_AXIS_LABELS.has(axis):
			return JOY_AXIS_LABELS[axis]
	return "—"


## 動作目前的主要輸入名稱（第一個非空欄位）。
func primary_label(action: StringName) -> String:
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
		if _codes.has(action):
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
	if not _codes.has(action):
		return &""
	var previous := get_joy_button(action)
	var swapped: StringName = &""
	for other: StringName in _joy.keys():
		if other != action and _joy[other] == button:
			_joy[other] = previous
			swapped = other
			_apply(other)
	_joy[action] = button
	_apply(action)
	_save()
	return swapped


func reset_to_defaults() -> void:
	_load_defaults()
	for entry in ACTIONS:
		_apply(entry["id"])
	Settings.erase_section(SETTINGS_SECTION)
	bindings_changed.emit()


## 從設定檔重新讀取（啟動時與切換設定檔時呼叫）。版本不符或資料損毀時退回預設值。
func reload_from_settings() -> void:
	_load_defaults()
	var schema := int(Settings.get_value(SETTINGS_SECTION, SCHEMA_KEY, 1))
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
					motion.axis = spec[1]
					motion.axis_value = spec[2]
					InputMap.action_add_event(action, motion)
				&"button":
					var button := InputEventJoypadButton.new()
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
			var code := int(value)
			restored.append(NONE if is_reserved(code) and action != &"pause" else code)
		_codes[action] = restored
	else:
		push_warning("[InputBindings] %s 的按鍵設定格式錯誤，使用預設值。" % action)
	var joy: Variant = saved.get("joy", null)
	if typeof(joy) == TYPE_INT or typeof(joy) == TYPE_FLOAT:
		_joy[action] = int(joy)
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
	InputMap.action_erase_events(action)
	for code: int in _codes.get(action, []):
		var event := _event_for_code(code)
		if event != null:
			InputMap.action_add_event(action, event)
	var button := get_joy_button(action)
	if button >= 0:
		var joy_event := InputEventJoypadButton.new()
		joy_event.button_index = button
		InputMap.action_add_event(action, joy_event)
	if JOY_AXES.has(action):
		var axis: Array = JOY_AXES[action]
		var motion := InputEventJoypadMotion.new()
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
		event.button_index = entry[1]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	for entry in [[&"ui_up", JOY_AXIS_LEFT_Y, -1.0], [&"ui_down", JOY_AXIS_LEFT_Y, 1.0], [&"ui_left", JOY_AXIS_LEFT_X, -1.0], [&"ui_right", JOY_AXIS_LEFT_X, 1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = entry[1]
		event.axis_value = entry[2]
		if not InputMap.action_has_event(entry[0], event):
			InputMap.action_add_event(entry[0], event)
