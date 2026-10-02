extends Enemy
## 哨戒砲台（固定狙擊）
## 行為：雷射瞄準線以有限轉速追蹤玩家 → 變粗變亮＝鎖定 → 發射高速子彈。
## 應對：鎖定瞬間立刻換位，或躲到掩體後切斷視線；本體耐打，也可以直接繞過。

const TURN_SPEED := 2.4
const LOCK_TIME := 0.35
const COOLDOWN_AFTER_FIRE := 0.4
const LASER_LENGTH := 400.0

var _aim := Vector2.LEFT
var _cooldown := 0.5


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"track", _track_tick, _track_enter)
	fsm.add(&"lock", _lock_tick)
	fsm.start(&"idle")


func _ready() -> void:
	super._ready()
	if data != null:
		_aim = Vector2(facing, 0)


func _on_stunned() -> void:
	fsm.transition(&"idle")


func _muzzle() -> Vector2:
	return _pivot() + _aim * 10.0


func _pivot() -> Vector2:
	return global_position + Vector2(0, -data.body_size.y * 0.7)


func _idle_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown <= 0.0 and _can_see_target(data.detect_range, 260.0):
		fsm.transition(&"track")


func _track_enter() -> void:
	_start_telegraph(data.telegraph_time + LOCK_TIME)


func _track_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	if not _has_line_of_sight():
		fsm.transition(&"idle")
		return
	_rotate_aim_toward(_target_point(), delta)
	if fsm.time_in_state >= data.telegraph_time:
		fsm.transition(&"lock")


func _lock_tick(_delta: float) -> void:
	velocity = Vector2.ZERO
	if fsm.time_in_state >= LOCK_TIME:
		_shoot(data.projectile, _aim)
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"idle")


func _rotate_aim_toward(point: Vector2, delta: float) -> void:
	var desired := (point - _pivot()).angle()
	var current := _aim.angle()
	var diff := wrapf(desired - current, -PI, PI)
	var step := clampf(diff, -TURN_SPEED * delta, TURN_SPEED * delta)
	_aim = Vector2.RIGHT.rotated(current + step)
	facing = 1 if _aim.x >= 0.0 else -1


func _draw_overlay() -> void:
	if not (fsm.is_in(&"track") or fsm.is_in(&"lock")):
		return
	var locked := fsm.is_in(&"lock")
	var color := LightKit.glow(Palette.DANGER, 2.8 if locked else 1.2)
	color.a = 0.9 if locked else 0.4
	var from := to_local(_muzzle())
	var to := from + _aim * LASER_LENGTH
	# 雷射被牆擋住時截斷，讓玩家清楚看到掩體有效。
	var query := PhysicsRayQueryParameters2D.create(_muzzle(), _muzzle() + _aim * LASER_LENGTH, Layers.WORLD)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		to = to_local(hit["position"])
	draw_line(from, to, color, 2.0 if locked else 1.0)


func _draw_body(color: Color) -> void:
	var w := data.body_size.x
	var h := data.body_size.y
	draw_rect(Rect2(-w * 0.6, -h * 0.45, w * 1.2, h * 0.45), Palette.TERRAIN_EDGE)
	var pivot := Vector2(0, -h * 0.7)
	draw_circle(pivot, w * 0.45, color)
	draw_line(pivot, pivot + _aim * 12.0, color.lightened(0.3), 3.0)
	var eye := LightKit.glow(Palette.DANGER, 3.0 if fsm.is_in(&"lock") else 1.4)
	draw_circle(pivot, 2.0, eye)
