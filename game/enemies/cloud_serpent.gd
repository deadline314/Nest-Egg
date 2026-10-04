extends Enemy
## 雲蛇（第三章，蠕行的長蟲）：穿過整個場景的蛇，平常藏在地底。
## 行為：地底潛行靠近玩家 → 地面隆起、碎石飛濺（預兆 0.9 秒，圈出冒出的位置，最後 0.3 秒鎖定）→ 從地裡躍出拋過一道弧，
##       身體整條跟著掠過（頭與身體都有傷害判定）→ 落回地裡。
## 應對：看到隆起就離開；躍出的空中是牠最脆弱的時候，打頭有兩倍傷害；牠沒入地面後打不到。

const GRAVITY := 700.0
const BURROW_DEPTH := 16.0
const ERUPT_SPEED := Vector2(80.0, -300.0)
const RUMBLE_LOCK := 0.3
const LURK_TIME := 1.2
const DIVE_TIME := 0.55
const SPOT_RADIUS := 18.0
const STRIKE_STRIDE := 2
const MAX_STRIKE_POINTS := 16
const BODY_PARTS := 3
const DEATH_FADE := 0.8
const PROBE_UP := 24.0
const PROBE_DOWN := 90.0

var worm: WormCreature

var _ground := GroundProbe.new()
var _ground_y := 0.0
var _spot := Vector2.ZERO
var _strike: BoneHitbox
var _points := PackedVector2Array()
var _body_parts: Array[Hurtbox] = []
var _underground := true


func _build_creature() -> void:
	worm = WormCreature.new()
	worm.name = "Worm"
	worm.position = Vector2(0.0, -data.body_size.y * 0.5)
	add_child(worm)
	if not worm.setup(data.creature_skin):
		push_error("[CloudSerpent] %s 的外觀載入失敗：%s" % [data.id, data.creature_skin])
		worm.queue_free()
		worm = null
		return
	worm.show_behind_parent = true
	_strike = BoneHitbox.new()
	_strike.name = "Strike"
	add_child(_strike)
	_strike.setup_bones(Combat.Team.ENEMY, maxi(1, data.contact_damage), data.contact_source_id, MAX_STRIKE_POINTS)
	_strike.active = false


func _build_hurt_parts() -> void:
	super()
	if worm == null:
		return
	for i in BODY_PARTS:
		_body_parts.append(hurtbox.add_part(StringName("body_%d" % i), Vector2(9, 9), Vector2.ZERO, 1.0))


func _setup_states() -> void:
	collision_mask = 0  # 自己控制移動（地底穿行、拋物線躍出），不和地形碰撞
	_ground_y = global_position.y
	fsm.add(&"lurk", _lurk_tick, _lurk_enter)
	fsm.add(&"rumble", _rumble_tick, _rumble_enter)
	fsm.add(&"erupt", _erupt_tick, _erupt_enter, _erupt_exit)
	fsm.add(&"dive", _dive_tick)
	fsm.start(&"lurk")
	_set_underground(true)


func _creature_state() -> StringName:
	return &"dead" if _dying else fsm.current


func _set_underground(value: bool) -> void:
	_underground = value
	hurtbox.enabled = not value
	if _strike != null:
		_strike.active = not value
	if contact != null:
		contact.active = not value


func _surface_y(world_x: float) -> float:
	return _ground.ground_y(get_world_2d().direct_space_state, world_x, _target_point().y - PROBE_UP, _ground_y, PROBE_DOWN)


# --- 潛行 ---

func _lurk_enter() -> void:
	_set_underground(true)


func _lurk_tick(_delta: float) -> void:
	_ground_y = _surface_y(global_position.x)
	global_position.y = _ground_y + BURROW_DEPTH
	var target := _target()
	if target == null:
		velocity = Vector2.ZERO
		return
	var dx := target.global_position.x - global_position.x
	facing = 1 if dx > 0.0 else -1
	velocity = Vector2(signf(dx) * data.move_speed if absf(dx) > 12.0 else 0.0, 0.0)
	if fsm.time_in_state >= LURK_TIME and absf(dx) <= data.detect_range:
		fsm.transition(&"rumble")


# --- 預兆：地面隆起 ---

func _rumble_enter() -> void:
	velocity = Vector2.ZERO
	_start_telegraph(data.telegraph_time)
	_spot = Vector2(_target_point().x, _surface_y(_target_point().x))
	_ground_y = _spot.y


func _rumble_tick(_delta: float) -> void:
	velocity = Vector2.ZERO
	if _telegraph_left > RUMBLE_LOCK:
		_spot = Vector2(_target_point().x, _surface_y(_target_point().x))  # 到最後一刻才鎖定落點
		_ground_y = _spot.y
	global_position = Vector2(_spot.x, _ground_y + BURROW_DEPTH)
	if randf() < 0.35:
		Fx.dust(_spot, 1, SPOT_RADIUS)
	if not is_telegraphing():
		fsm.transition(&"erupt")


# --- 躍出 ---

func _erupt_enter() -> void:
	_set_underground(false)
	global_position = Vector2(_spot.x, _ground_y)
	var target := _target()
	var dir := 1.0 if target == null or target.global_position.x >= _spot.x else -1.0
	facing = int(dir)
	velocity = Vector2(dir * ERUPT_SPEED.x, ERUPT_SPEED.y)
	Fx.dust(_spot, 6, SPOT_RADIUS * 2.0)
	Feel.shake_strength(1.5, 0.12)
	worm.reset_trail(Vector2.UP)  # 身體還在地底：排在頭的正下方，頭往上衝時被拉出來
	worm.global_position = global_position + Vector2(0.0, -data.body_size.y * 0.5)


func _erupt_tick(delta: float) -> void:
	velocity.y += GRAVITY * delta
	if velocity.y > 0.0 and global_position.y >= _ground_y:
		fsm.transition(&"dive")


func _erupt_exit() -> void:
	Fx.dust(Vector2(global_position.x, _ground_y), 5, SPOT_RADIUS * 2.0)


func _dive_tick(delta: float) -> void:
	velocity.y += GRAVITY * delta
	if global_position.y > _ground_y + 2.0:
		_set_underground(true)  # 沒入地面：打不到、也不再造成傷害
	if fsm.time_in_state >= DIVE_TIME:
		fsm.transition(&"lurk")


# --- 每影格 ---

func _physics_process(delta: float) -> void:
	if _dying:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
		if global_position.y >= _ground_y:
			velocity = Vector2.ZERO
		move_and_slide()
		_drive_worm(delta)
		return
	super(delta)


func _drive_creature(delta: float) -> void:
	_drive_worm(delta)


func _drive_worm(delta: float) -> void:
	if worm == null:
		return
	worm.clip_y = _ground_y
	worm.slack = _dying
	worm.animate(delta, _creature_state())
	if _strike != null and _strike.active and not _underground:
		worm.fill_hit_points(STRIKE_STRIDE, _points)
		_strike.set_points(_points, worm.hit_radius())
	elif _strike != null:
		_strike.clear_points()


func _update_hurt_parts() -> void:
	super()
	if worm == null:
		return
	for i in _body_parts.size():
		var joint := worm.joint_position((i + 1) * worm.joint_count() / (BODY_PARTS + 1))
		var visible_part := not _underground and joint.y <= _ground_y
		if _body_parts[i].enabled != visible_part:
			_body_parts[i].enabled = visible_part
		hurtbox.move_part(_body_parts[i], joint - global_position)


func _on_stunned() -> void:
	if fsm.is_in(&"rumble"):
		fsm.transition(&"lurk")


func _play_death() -> void:
	_set_underground(true)
	_death_tween = create_tween()
	_death_tween.tween_interval(DEATH_FADE)
	_death_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	_death_tween.tween_callback(queue_free)
	_register_corpse()


## 地面隆起預告：落點的土堆越來越高，並畫出冒出的範圍。
func _draw_overlay() -> void:
	if not fsm.is_in(&"rumble"):
		return
	var progress := 1.0 - _telegraph_left / maxf(0.01, data.telegraph_time)
	var at := to_local(_spot)
	var color := LightKit.glow(Palette.DANGER, 1.0 + progress)
	color.a = 0.4 + 0.5 * progress
	draw_arc(at + Vector2(0, 1), SPOT_RADIUS * (0.6 + 0.4 * progress), PI, TAU, 14, color, 1.5)
	draw_line(at + Vector2(-SPOT_RADIUS, 1), at + Vector2(SPOT_RADIUS, 1), color, 1.0)


func _draw_body(_color: Color) -> void:
	if worm != null:
		return
	draw_circle(Vector2(0, -data.body_size.y * 0.5), data.body_size.x * 0.5, data.color)
