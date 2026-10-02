class_name AimInput
extends RefCounted
## 瞄準輸入：滑鼠（360°）與手把右搖桿自動切換。
## 最後操作的裝置決定瞄準來源：動滑鼠就用滑鼠、推右搖桿就用搖桿。
## 玩家與載具共用，確保兩者瞄準手感一致。

const STICK_DEADZONE := 0.3

static var using_gamepad := false
static var _last_stick_dir := Vector2.RIGHT


## 由擁有輸入的節點在 _input 中呼叫，偵測目前使用的裝置。
static func observe(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		using_gamepad = false
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > STICK_DEADZONE:
		var axis := (event as InputEventJoypadMotion).axis
		if axis == JOY_AXIS_RIGHT_X or axis == JOY_AXIS_RIGHT_Y:
			using_gamepad = true


## 從 origin（世界座標）指向瞄準點的單位向量。沒有有效輸入時回傳 fallback。
static func direction_from(node: Node2D, origin: Vector2, fallback: Vector2) -> Vector2:
	var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down", STICK_DEADZONE)
	if stick != Vector2.ZERO:
		using_gamepad = true
		_last_stick_dir = stick.normalized()
	if using_gamepad:
		return _last_stick_dir
	var offset := node.get_global_mouse_position() - origin
	return offset.normalized() if offset.length_squared() > 4.0 else fallback


## 準星應顯示的世界座標（手把時放在角色前方固定距離）。
static func target_point(node: Node2D, origin: Vector2, direction: Vector2, gamepad_distance := 72.0) -> Vector2:
	if using_gamepad:
		return origin + direction * gamepad_distance
	return node.get_global_mouse_position()
