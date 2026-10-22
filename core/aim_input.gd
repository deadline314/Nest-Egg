class_name AimInput
extends RefCounted
## 瞄準輸入：滑鼠（360°）與手把右搖桿自動切換。
## 最後操作的裝置決定瞄準來源：動滑鼠就用滑鼠、推右搖桿就用搖桿。
## 玩家與載具共用，確保兩者瞄準手感一致。

static var using_gamepad := false
static var _last_stick_dir := Vector2.RIGHT
static var _last_stick_msec := 0
const VIRTUAL_GAMEPAD_META := &"aim_input_virtual_gamepad"
static var _assist_ray := PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2.RIGHT, Layers.WORLD | Layers.ENEMY_HURTBOX)


## 主流程恢復朝向；不改變目前輸入裝置或操作提示。
static func restore_direction(direction: Vector2) -> void:
	if not direction.is_finite() or direction.length_squared() < 0.000001:
		return
	_last_stick_dir = direction.normalized()
	_last_stick_msec = Time.get_ticks_msec()


## Scripted tool actors choose a source locally; real device history stays intact.
static func set_virtual_gamepad(node: Node2D, enabled: bool) -> void:
	if enabled:
		node.set_meta(VIRTUAL_GAMEPAD_META, true)
	elif node.has_meta(VIRTUAL_GAMEPAD_META):
		node.remove_meta(VIRTUAL_GAMEPAD_META)


static func uses_gamepad(node: Node2D) -> bool:
	return using_gamepad or node.get_meta(VIRTUAL_GAMEPAD_META, false) == true


static func _can_read_mouse(node: Node2D) -> bool:
	var determinant := node.get_canvas_transform().determinant()
	return is_finite(determinant) and absf(determinant) > 0.000001


## 由擁有輸入的節點在 _input 中呼叫，偵測目前使用的裝置。
static func observe(event: InputEvent) -> void:
	InputBindings.observe_device(event)


## 從 origin（世界座標）指向瞄準點的單位向量。沒有有效輸入時回傳 fallback。
static func direction_from(node: Node2D, origin: Vector2, fallback: Vector2) -> Vector2:
	var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down", InputBindings.get_aim_deadzone())
	if InputBindings.get_invert_aim_y():
		stick.y *= -1.0
	# A held stick must not seize aim back after a deliberate mouse/key event.
	if uses_gamepad(node) and stick != Vector2.ZERO:
		var now := Time.get_ticks_msec()
		var dt := maxf(0.001, float(now - _last_stick_msec) * 0.001)
		var turn_rate := absf(_last_stick_dir.angle_to(stick.normalized())) / dt if now - _last_stick_msec < 200 else 0.0
		_last_stick_msec = now
		_last_stick_dir = stick.normalized()
		# 手把才有瞄準輔助；搖桿正在大幅轉動時輔助關閉（玩家輸入優先）。
		var targets := node.get_tree().get_nodes_in_group(&"enemies")
		var assisted := InputFeel.assist(origin, _last_stick_dir, targets, turn_rate, true)
		if assisted.is_equal_approx(_last_stick_dir):
			return assisted
		# No physics query when assistance is off, there is no candidate, or a fast
		# turn already gave the player full control.
		var protected_distance := _protected_explosive_distance(node, origin, _last_stick_dir)
		return InputFeel.assist(origin, _last_stick_dir, targets, turn_rate, true, protected_distance) if is_finite(protected_distance) else assisted
	if uses_gamepad(node):
		return _last_stick_dir
	if not _can_read_mouse(node):
		return fallback
	var offset := node.get_global_mouse_position() - origin
	return offset.normalized() if offset.length_squared() > 4.0 else fallback


## The first actual hit on the raw ray wins. Walls, enemies and held props cannot
## make an obscured barrel take priority; the ray uses the projectile terrain mask.
static func _protected_explosive_distance(node: Node2D, origin: Vector2, direction: Vector2) -> float:
	_assist_ray.from = origin
	_assist_ray.to = origin + direction * InputFeel.assist_max_distance()
	_assist_ray.collide_with_areas = true
	var hit := node.get_world_2d().direct_space_state.intersect_ray(_assist_ray)
	var box := hit.get("collider") as Hurtbox
	if box == null or not box.can_receive():
		return INF
	var prop := box.get_parent() as Throwable
	if prop == null or prop.state != Throwable.State.REST or not prop.data.is_explosive():
		return INF
	return origin.distance_to(hit["position"])


## 準星應顯示的世界座標（手把時放在角色前方固定距離）。
static func target_point(node: Node2D, origin: Vector2, direction: Vector2, gamepad_distance := 72.0) -> Vector2:
	if uses_gamepad(node) or not _can_read_mouse(node):
		return origin + direction * gamepad_distance
	return node.get_global_mouse_position()
