extends "res://game/enemies/turret.gd"
## 吊軌砲（第二章轉運站，軌道）：夾在天花板軌道上的砲，沿軌道滑動換位，比哨戒砲台更快、更會移動。
## 行為：雷射線追蹤玩家（預兆）→ 停住鎖定（線變粗、滑座顫動）→ 開火 → 沿軌道滑向另一個位置（加速、減速有慣性）。
## 應對：鎖定瞬間離開雷射線或躲到掩體後；牠開火後滑向新位置的途中不會瞄準，是反擊的空檔。
## 軌道範圍是以出生點為中心左右各 ability_radius 像素；軌道在滑座上方約 28 像素（畫在 _draw_overlay）。

const SLIDE_ACCEL := 220.0
const SLIDE_ARRIVE := 6.0
const RAIL_HEIGHT := 28.0
const SPARK_INTERVAL := 0.09
const SLIDE_TURN_SPEED := 4.5

var _slide_to := 0.0
var _spark_left := 0.0
var _rail_min := 0.0
var _rail_max := 0.0


func _setup_states() -> void:
	super()
	fsm.add(&"slide", _slide_tick, _slide_enter)
	_rail_min = _home.x - data.ability_radius
	_rail_max = _home.x + data.ability_radius


func _pivot() -> Vector2:
	if creature != null:
		var barrel := creature.joint_of("barrel")
		if barrel != null:
			return barrel.global_position
	return global_position + Vector2(0, -data.body_size.y * 0.3)


func _muzzle() -> Vector2:
	return creature.muzzle_global("barrel") if creature != null else _pivot() + _aim * 12.0


func _lock_tick(_delta: float) -> void:
	velocity = Vector2.ZERO
	if not PowerGrid.is_powered(self):
		fsm.transition(&"idle")
		return
	if fsm.time_in_state >= LOCK_TIME:
		_shoot(data.projectile, _aim)
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"slide")


## 滑向軌道上離現在位置遠的另一個點（至少隔半條軌道，朝玩家的另一側偏好）。
func _slide_enter() -> void:
	var span := _rail_max - _rail_min
	var target := _target()
	var away := _rail_min if target == null or target.global_position.x > _home.x else _rail_max
	_slide_to = clampf(lerpf(away, global_position.x, randf_range(0.0, 0.35)), _rail_min, _rail_max)
	if absf(_slide_to - global_position.x) < span * 0.3:
		_slide_to = _rail_max if global_position.x < _home.x else _rail_min
	_spark_left = 0.0


func _slide_tick(delta: float) -> void:
	var remaining := _slide_to - global_position.x
	var direction := signf(remaining)
	# 還沒到就加速；進入減速距離就減速（v² = 2ad），到了停住。
	var brake_distance := velocity.x * velocity.x / (2.0 * SLIDE_ACCEL)
	var wanted := 0.0 if absf(remaining) <= maxf(SLIDE_ARRIVE, 1.0) or brake_distance >= absf(remaining) and direction * velocity.x > 0.0 else direction * data.move_speed
	velocity.x = move_toward(velocity.x, wanted, SLIDE_ACCEL * delta)
	velocity.y = 0.0
	global_position.x = clampf(global_position.x, _rail_min, _rail_max)
	_spark_left -= delta
	if absf(velocity.x) > 25.0 and _spark_left <= 0.0:
		_spark_left = SPARK_INTERVAL
		Fx.sparks(Vector2(global_position.x, global_position.y - RAIL_HEIGHT), Palette.WARNING, 2, 90.0, 0.2, Vector2(-signf(velocity.x), 0.5), 1.0)
	# 滑動中砲管慢慢轉回面向前方，不瞄準。
	var rest := Vector2(float(facing), 0.35).normalized()
	_aim = _aim.slerp(rest, minf(1.0, SLIDE_TURN_SPEED * delta))
	if absf(remaining) <= SLIDE_ARRIVE and absf(velocity.x) < 3.0:
		velocity.x = 0.0
		fsm.transition(&"idle")


func _on_stunned() -> void:
	velocity.x = 0.0
	fsm.transition(&"idle")


## 軌道本身：滑座上方的一條橫線，滑動時亮起火花。
func _draw_overlay() -> void:
	var y := -RAIL_HEIGHT
	var left := to_local(Vector2(_rail_min, global_position.y)).x - 8.0
	var right := to_local(Vector2(_rail_max, global_position.y)).x + 8.0
	draw_line(Vector2(left, y), Vector2(right, y), Color("5c6578"), 2.0)
	draw_line(Vector2(left, y - 1.5), Vector2(right, y - 1.5), Color("98a3ba", 0.6), 1.0)
	super()
