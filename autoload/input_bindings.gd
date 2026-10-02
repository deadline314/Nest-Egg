extends Node
## 按鍵綁定服務：預設配置、玩家自訂、衝突處理、存檔與按鍵名稱顯示。
##
## 每個動作有 2 個鍵盤欄位與 1 個手把按鈕欄位；搖桿方向固定不可改（避免玩家把移動改壞）。
## 綁定到已被使用的按鍵時會「互換」，保證每個動作永遠有鍵可用。
## 文字中的 {動作} 佔位符（例如 "{jump} 跳躍"）可用 format() 換成目前的按鍵名稱，
## 讓教學提示永遠與實際按鍵一致。

signal bindings_changed

const DEADZONE := 0.4
const KEY_SLOTS := 2
const SETTINGS_SECTION := "input"

## 動作的顯示順序與名稱（設定選單依此排列）。
const ACTIONS: Array[Dictionary] = [
	{"id": &"move_left", "label": "左移"},
	{"id": &"move_right", "label": "右移"},
	{"id": &"move_up", "label": "上（瞄準上方）"},
	{"id": &"move_down", "label": "下（蹲下）"},
	{"id": &"jump", "label": "跳躍"},
	{"id": &"shoot", "label": "射擊"},
	{"id": &"dash", "label": "衝刺"},
	{"id": &"melee", "label": "近戰／終結"},
	{"id": &"swap_weapon", "label": "切換武器"},
	{"id": &"aim_lock", "label": "定點瞄準"},
	{"id": &"interact", "label": "搭乘／互動"},
	{"id": &"pause", "label": "暫停"},
]

const DEFAULT_KEYS: Dictionary[StringName, Array] = {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"jump": [KEY_K, KEY_SPACE],
	&"shoot": [KEY_J, KEY_NONE],
	&"dash": [KEY_L, KEY_SHIFT],
	&"melee": [KEY_I, KEY_NONE],
	&"swap_weapon": [KEY_U, KEY_NONE],
	&"aim_lock": [KEY_O, KEY_NONE],
	&"interact": [KEY_E, KEY_NONE],
	&"pause": [KEY_ESCAPE, KEY_P],
}

const DEFAULT_JOY_BUTTONS: Dictionary[StringName, int] = {
	&"move_left": JOY_BUTTON_DPAD_LEFT,
	&"move_right": JOY_BUTTON_DPAD_RIGHT,
	&"move_up": JOY_BUTTON_DPAD_UP,
	&"move_down": JOY_BUTTON_DPAD_DOWN,
	&"jump": JOY_BUTTON_A,
	&"shoot": JOY_BUTTON_X,
	&"dash": JOY_BUTTON_B,
	&"melee": JOY_BUTTON_Y,
	&"swap_weapon": JOY_BUTTON_LEFT_SHOULDER,
	&"aim_lock": JOY_BUTTON_RIGHT_SHOULDER,
	&"interact": JOY_BUTTON_BACK,
	&"pause": JOY_BUTTON_START,
}

## 左搖桿方向（固定）。[軸, 方向]
const JOY_AXES: Dictionary[StringName, Array] = {
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}

## 無法被綁定的鍵（Esc 用於取消設定；F 鍵保留給系統／除錯）。
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8,
	KEY_F9, KEY_F10, KEY_F11, KEY_F12]

const JOY_BUTTON_LABELS: Dictionary[int, String] = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "十字↑", JOY_BUTTON_DPAD_DOWN: "十字↓",
	JOY_BUTTON_DPAD_LEFT: "十字←", JOY_BUTTON_DPAD_RIGHT: "十字→",
}

## action -> [Key, Key]（KEY_NONE 代表空欄位）
var _keys: Dictionary[StringName, Array] = {}
## action -> JoyButton（-1 代表未綁定）
var _joy: Dictionary[StringName, int] = {}
var _placeholder_regex := RegEx.create_from_string("\\{([a-z_]+)\\}")


func _ready() -> void:
	reload_from_settings()


# ---------------------------------------------------------------------------
# 查詢
# ---------------------------------------------------------------------------

func get_key(action: StringName, slot: int) -> Key:
	var keys: Array = _keys.get(action, [])
	return keys[slot] if slot >= 0 and slot < keys.size() else KEY_NONE


func get_joy_button(action: StringName) -> int:
	return _joy.get(action, -1)


func action_label(action: StringName) -> String:
	for entry in ACTIONS:
		if entry["id"] == action:
			return entry["label"]
	return String(action)


## 鍵盤按鍵名稱（依玩家實際鍵盤配置顯示，例如 AZERTY）。
func key_label(keycode: Key) -> String:
	if keycode == KEY_NONE:
		return "—"
	var display := keycode
	if DisplayServer.get_name() != "headless":
		var mapped := DisplayServer.keyboard_get_label_from_physical(keycode)
		if mapped != KEY_NONE:
			display = mapped
	var text := OS.get_keycode_string(display)
	return text if not text.is_empty() else "?"


func joy_label(button: int) -> String:
	if button < 0:
		return "—"
	return JOY_BUTTON_LABELS.get(button, "按鈕 %d" % button)


## 動作目前的主要按鍵名稱（鍵盤第一欄；沒有則用第二欄）。
func primary_label(action: StringName) -> String:
	for slot in KEY_SLOTS:
		var key := get_key(action, slot)
		if key != KEY_NONE:
			return key_label(key)
	return joy_label(get_joy_button(action))


## 把文字中的 {action} 換成目前的按鍵名稱，例如 "{jump} 跳躍" → "K 跳躍"。
func format(text: String) -> String:
	var result := text
	for found in _placeholder_regex.search_all(text):
		var action := StringName(found.get_string(1))
		if _keys.has(action):
			result = result.replace(found.get_string(), primary_label(action))
	return result


# ---------------------------------------------------------------------------
# 修改
# ---------------------------------------------------------------------------

## 綁定鍵盤按鍵。若該鍵已被其他欄位使用則互換。回傳被互換的動作（沒有則為 &""）。
func set_key(action: StringName, slot: int, keycode: Key) -> StringName:
	if not _keys.has(action) or slot < 0 or slot >= KEY_SLOTS or keycode in RESERVED_KEYS:
		return &""
	var previous := get_key(action, slot)
	var swapped: StringName = &""
	if keycode != KEY_NONE:
		for other: StringName in _keys.keys():
			for other_slot in KEY_SLOTS:
				if (other != action or other_slot != slot) and get_key(other, other_slot) == keycode:
					# 保留鍵（例如預設的 Esc）不會被換到其他動作上。
					_keys[other][other_slot] = KEY_NONE if previous in RESERVED_KEYS else previous
					swapped = other
					_apply(other)
					_ensure_bound(other)
	_keys[action][slot] = keycode
	_apply(action)
	_ensure_bound(action)
	_save()
	return swapped


## 綁定手把按鈕。若已被其他動作使用則互換。回傳被互換的動作。
func set_joy_button(action: StringName, button: int) -> StringName:
	if not _keys.has(action):
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


## 從設定檔重新讀取（啟動時與切換設定檔時呼叫）。資料損毀的動作會退回預設值。
func reload_from_settings() -> void:
	_load_defaults()
	for entry in ACTIONS:
		var action: StringName = entry["id"]
		var saved: Variant = Settings.get_value(SETTINGS_SECTION, String(action), null)
		if typeof(saved) == TYPE_DICTIONARY:
			_restore_action(action, saved)
		_apply(action)
	bindings_changed.emit()


# ---------------------------------------------------------------------------
# 內部
# ---------------------------------------------------------------------------

func _load_defaults() -> void:
	_keys.clear()
	_joy.clear()
	for entry in ACTIONS:
		var action: StringName = entry["id"]
		_keys[action] = (DEFAULT_KEYS.get(action, [KEY_NONE, KEY_NONE]) as Array).duplicate()
		_joy[action] = DEFAULT_JOY_BUTTONS.get(action, -1)


func _restore_action(action: StringName, saved: Dictionary) -> void:
	var keys: Variant = saved.get("keys", null)
	if typeof(keys) == TYPE_ARRAY and (keys as Array).size() == KEY_SLOTS:
		var restored: Array = []
		for value in keys:
			var key := int(value)
			restored.append(KEY_NONE if key in RESERVED_KEYS and action != &"pause" else key)
		_keys[action] = restored
	else:
		push_warning("[InputBindings] %s 的鍵盤設定格式錯誤，使用預設值。" % action)
	var joy: Variant = saved.get("joy", null)
	if typeof(joy) == TYPE_INT or typeof(joy) == TYPE_FLOAT:
		_joy[action] = int(joy)
	_ensure_bound(action)


## 防呆：動作完全沒有鍵盤按鍵時，補回預設的第一個鍵。
func _ensure_bound(action: StringName) -> void:
	for slot in KEY_SLOTS:
		if get_key(action, slot) != KEY_NONE:
			return
	var defaults: Array = DEFAULT_KEYS.get(action, [])
	if not defaults.is_empty():
		_keys[action][0] = defaults[0]
		_apply(action)


func _apply(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	InputMap.action_erase_events(action)
	for key: int in _keys.get(action, []):
		if key == KEY_NONE:
			continue
		var key_event := InputEventKey.new()
		key_event.physical_keycode = key
		InputMap.action_add_event(action, key_event)
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


func _save() -> void:
	for entry in ACTIONS:
		var action: StringName = entry["id"]
		Settings.set_value(SETTINGS_SECTION, String(action), {"keys": _keys[action].duplicate(), "joy": _joy[action]})
	bindings_changed.emit()
