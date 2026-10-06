extends Enemy
## 攀牆者（第二章夾層區、電力室，攀附）：貼著地面、牆壁與天花板爬行的壁虎，攻擊角度從四面八方來。
## 行為：沿著表面巡邏（繞過牆角、轉到牆上和天花板）→ 發現玩家後停住蹲伏、尾巴甩動（預兆 0.6 秒）→ 朝玩家撲出（拋物線）→ 落在任何碰到的表面上，緩衝一下。
## 應對：看到蹲伏就移動；撲空落地後有硬直，是輸出空檔。倒掛在天花板時最危險，要先看頭頂。
## 移動不走物理引擎的碰撞，而是 SurfaceWalker 的貼附幾何；身體整個隨表面旋轉。

const RADIUS := 5.0
const LEAP_TIME := 0.38
const LAND_TIME := 0.5
const RETURN_PATROL := 3.5
const MAX_AIR_TIME := 1.2

var _surface := SurfaceWalker.new()
var _cooldown := 0.8
var _patrol_left := 3.0
var _leap_velocity := Vector2.ZERO
var _attached := false
var _moving := false


func _setup_states() -> void:
	collision_mask = 0  # 自己用射線貼表面移動，不和地形做碰撞推擠
	_surface.radius = RADIUS
	fsm.add(&"patrol", _patrol_tick, _patrol_enter)
	fsm.add(&"windup", _windup_tick, _windup_enter)
	fsm.add(&"leap", _leap_tick, _leap_enter)
	fsm.add(&"land", _land_tick, _land_enter)
	fsm.start(&"patrol")
	hurtbox.resize(data.body_size, Vector2.ZERO)
	if contact != null:
		contact.resize(data.body_size * 0.8, Vector2.ZERO)


## 原點就是身體中心（不是腳底）。
func _center() -> Vector2:
	return global_position


func _muzzle() -> Vector2:
	return global_position


func _creature_state() -> StringName:
	if _dying:
		return &"dead"
	if fsm.is_in(&"patrol"):
		return &"crawl" if velocity.length() > 4.0 or _moving else &"idle"
	return super()


func _ensure_attached() -> void:
	if _attached:
		return
	var hit := _surface.attach(get_world_2d().direct_space_state, global_position, 40.0)
	if not hit.is_empty():
		global_position = hit["position"]
		_surface.normal = hit["normal"]
		_attached = true


func _patrol_enter() -> void:
	_patrol_left = RETURN_PATROL * randf_range(0.7, 1.3)


func _patrol_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	_ensure_attached()
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol_left -= delta
	if _attached:
		var before := global_position
		global_position = _surface.advance(get_world_2d().direct_space_state, global_position, data.move_speed * delta)
		_moving = global_position.distance_to(before) > 0.01
		if _patrol_left <= 0.0:
			_surface.reverse()
			_patrol_left = RETURN_PATROL * randf_range(0.7, 1.3)
	facing = _surface.dir
	if _attached and _cooldown <= 0.0 and _token_free() and _distance_to_target() <= data.attack_range and _has_line_of_sight():
		fsm.transition(&"windup")


func _windup_enter() -> void:
	_moving = false
	_start_telegraph(data.telegraph_time)


func _windup_tick(_delta: float) -> void:
	velocity = Vector2.ZERO
	if not is_telegraphing():
		fsm.transition(&"leap")


## 拋物線撲向玩家：在 LEAP_TIME 內從現在的位置飛到玩家身上，重力 900。
func _leap_enter() -> void:
	var offset := _target_point() - global_position
	_leap_velocity = Vector2(offset.x / LEAP_TIME, offset.y / LEAP_TIME - 0.5 * _gravity * LEAP_TIME)
	_leap_velocity = _leap_velocity.limit_length(data.ability_speed * 1.6)
	_attached = false
	facing = 1 if _leap_velocity.x >= 0.0 else -1
	_surface.dir = facing


func _leap_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	_leap_velocity.y += _gravity * delta
	var next := global_position + _leap_velocity * delta
	var hit := _surface.land(get_world_2d().direct_space_state, global_position, next + _leap_velocity.normalized() * RADIUS)
	if not hit.is_empty():
		global_position = hit["position"]
		_surface.normal = hit["normal"]
		_attached = true
		Fx.dust(global_position - _surface.normal * RADIUS, 3, 8.0)
		fsm.transition(&"land")
		return
	global_position = next
	if fsm.time_in_state >= MAX_AIR_TIME:
		fsm.transition(&"land")


func _land_enter() -> void:
	_cooldown = _scaled_cooldown(data.attack_cooldown)
	_ensure_attached()


func _land_tick(_delta: float) -> void:
	velocity = Vector2.ZERO
	if fsm.time_in_state >= LAND_TIME:
		fsm.transition(&"patrol")


func _on_stunned() -> void:
	if fsm.is_in(&"windup"):
		fsm.transition(&"patrol")


## 身體整個隨表面旋轉（背朝外）：樣式在零件動畫器上疊一個旋轉；面向翻轉時旋轉方向跟著翻。
func _drive_creature(delta: float) -> void:
	if creature == null:
		return
	var angle := _surface.angle() if _attached else 0.0
	var params := _body_kick_params()
	creature.extra_position = params[0]
	creature.extra_rotation = angle * float(facing) + float(params[1])
	creature.extra_scale = params[2]
	creature.set_wear(data.color.lerp(Color.WHITE, 1.0))
	creature.animate(delta, _creature_state(), Vector2(float(_moving) * data.move_speed, 0.0), facing, 0.0)
	# 判定框的長邊跟著表面：在牆上時寬高對調。
	var vertical := absf(_surface.normal.x) > 0.5
	var size := Vector2(data.body_size.y, data.body_size.x) if vertical else data.body_size
	hurtbox.resize(size, Vector2.ZERO)


func _draw_overlay() -> void:
	if fsm.is_in(&"windup"):
		var color := LightKit.glow(Palette.DANGER, 1.4)
		color.a = 0.3 + 0.5 * (1.0 - _telegraph_left / maxf(0.01, data.telegraph_time))
		var to := to_local(_target_point())
		draw_dashed_line(Vector2.ZERO, to, color, 1.0, 3.0)


func _draw_body(color: Color) -> void:
	draw_rect(Rect2(-data.body_size * 0.5, data.body_size), color)
