class_name Stalker
extends Enemy
## 迷彩獵手（光學迷彩）
## 行為：隱形潛行靠近玩家；只在「被燈照到」、貼近玩家、開火、受傷時現形。
##       進入射程後現形瞄準（紅色瞄準線，最後鎖定）→ 兩連發 → 後退拉開距離。
## 應對：留意空氣中閃爍的輪廓；站在路燈下或貼身就逼牠現形，鎖定時蹲下／跳躍／衝刺閃避；
##       切斷電力會讓燈熄滅，牠就更難找（代價自負）。
## 數值：ability_time = 兩連發的間隔，ability_radius = 貼近到這個距離會被發現，ability_speed = 現形停留秒數。

const HIDDEN_ALPHA := 0.05
const FADE_IN_SPEED := 10.0
const FADE_OUT_SPEED := 2.0
## 受光判定：場景燈照亮程度超過此值就現形。
const LIT_THRESHOLD := 0.18
const LIT_CHECK_INTERVAL := 0.12
const TRACK_RATIO := 0.7
const AIM_LINE_LENGTH := 260.0
const RETREAT_TIME := 0.9
const BURST_SHOTS := 2
const HURT_REVEAL := 2.0
const SHIMMER_PERIOD := 0.9

var _aim := Vector2.LEFT
var _cooldown := 0.6
var _visibility := HIDDEN_ALPHA
var _reveal_left := 0.0
var _lit := false
var _lit_check := 0.0
var _shots_left := 0
var _shot_timer := 0.0


func _setup_states() -> void:
	fsm.add(&"stalk", _stalk_tick)
	fsm.add(&"aim", _aim_tick, _aim_enter)
	fsm.add(&"burst", _burst_tick, _burst_enter)
	fsm.add(&"retreat", _retreat_tick)
	fsm.start(&"stalk")


func is_cloaked() -> bool:
	return _visibility < 0.5


func _on_stunned() -> void:
	_reveal_left = maxf(_reveal_left, data.ability_speed)
	fsm.transition(&"retreat")


func _on_hit(_info: DamageInfo) -> void:
	_reveal_left = maxf(_reveal_left, HURT_REVEAL)


func _physics_process(delta: float) -> void:
	_update_visibility(delta)
	super._physics_process(delta)


## 現形條件：預兆／開火中、剛被打到或開火過、被燈照到、貼近玩家。
func _update_visibility(delta: float) -> void:
	_reveal_left = maxf(0.0, _reveal_left - delta)
	_lit_check -= delta
	if _lit_check <= 0.0:
		_lit_check = LIT_CHECK_INTERVAL
		var level := LightKit.light_level_at(get_tree(), _center())
		var near := data.ability_radius > 0.0 and _distance_to_target() <= data.ability_radius
		_lit = level >= LIT_THRESHOLD or near
	var revealed := _lit or _reveal_left > 0.0 or is_telegraphing() or fsm.is_in(&"aim") or fsm.is_in(&"burst") or can_be_finished()
	var goal := 1.0 if revealed else HIDDEN_ALPHA
	_visibility = move_toward(_visibility, goal, (FADE_IN_SPEED if revealed else FADE_OUT_SPEED) * delta)


func _stalk_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _distance_to_target() > data.detect_range:
		_patrol(data.move_speed * 0.6)
		return
	_face_target()
	# 在射程邊緣停下，避免貼臉（貼臉會被燈或身體發現）。
	var wanted := data.attack_range * 0.75
	velocity.x = facing * data.move_speed if _distance_to_target() > wanted else 0.0
	if is_on_floor() and is_on_wall():
		velocity.y = -200.0
	if _cooldown <= 0.0 and _token_free() and _can_see_target(data.attack_range, 80.0):
		fsm.transition(&"aim")


func _aim_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_aim = _direction_to_target()
	_start_telegraph(data.telegraph_time)


func _aim_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state < data.telegraph_time * TRACK_RATIO:
		_face_target()
		_aim = _direction_to_target()
	if not is_telegraphing():
		fsm.transition(&"burst")


func _burst_enter() -> void:
	_shots_left = BURST_SHOTS
	_shot_timer = 0.0
	_reveal_left = maxf(_reveal_left, data.ability_speed)


func _burst_tick(delta: float) -> void:
	velocity.x = 0.0
	_shot_timer -= delta
	if _shot_timer <= 0.0 and _shots_left > 0:
		_shoot(data.projectile, _aim)
		_shots_left -= 1
		_shot_timer = data.ability_time
	if _shots_left <= 0 and _shot_timer <= 0.0:
		fsm.transition(&"retreat")


func _retreat_tick(_delta: float) -> void:
	_face_target()
	velocity.x = -facing * data.move_speed * 1.3 if not is_on_wall() and not _is_ledge_behind() else 0.0
	if fsm.time_in_state >= RETREAT_TIME:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"stalk")


func _is_ledge_behind() -> bool:
	var from := global_position + Vector2(-facing * (data.body_size.x * 0.5 + 2.0), -2.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 18), Layers.SOLID)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _rig_aim() -> Vector2:
	return _aim


## 骨架外觀整隻一起淡入淡出（隱形時只剩微弱的輪廓）。
func _rig_state(_input: RigInput) -> void:
	if rig != null:
		rig.modulate.a = _visibility


func _draw_overlay() -> void:
	if fsm.is_in(&"aim"):
		var locked := fsm.time_in_state >= data.telegraph_time * TRACK_RATIO
		var color := LightKit.glow(Palette.DANGER, 2.2 if locked else 1.0)
		color.a = 0.85 if locked else 0.3
		var from := to_local(_muzzle())
		draw_line(from, from + _aim * AIM_LINE_LENGTH, color, 1.5 if locked else 1.0)
	elif is_cloaked():
		# 隱形時只剩空氣的閃爍：幾條淡淡的水平亮線在身體輪廓附近明滅。
		var phase := fmod(_anim_time, SHIMMER_PERIOD) / SHIMMER_PERIOD
		var alpha := 0.35 * sin(phase * PI)
		if alpha > 0.02:
			var color := Color(Palette.CYAN, alpha)
			var h := data.body_size.y
			for i in 3:
				var y := -h * (0.2 + 0.28 * i) + sin(_anim_time * 3.0 + i) * 2.0
				draw_line(Vector2(-5.0, y), Vector2(5.0, y), color, 1.0)


func _draw_body(color: Color) -> void:
	var f := float(facing)
	var h := data.body_size.y
	var c := Color(color, color.a * _visibility)
	var stride := sin(_anim_time * 10.0) * 2.0 if absf(velocity.x) > 5.0 else 0.0
	draw_line(Vector2(-3, -h * 0.4), Vector2(-3 + stride, 0), c.darkened(0.4), 3.0)
	draw_line(Vector2(3, -h * 0.4), Vector2(3 - stride, 0), c.darkened(0.4), 3.0)
	draw_rect(Rect2(-5, -h * 0.78, 10, h * 0.4), c)
	draw_circle(Vector2(0, -h * 0.86), 4.0, c.darkened(0.3))
	var eye := LightKit.glow(Palette.MAGENTA, 3.0 if is_telegraphing() else 1.6)
	eye.a *= _visibility
	draw_line(Vector2(f * 0.5, -h * 0.87), Vector2(f * 4.0, -h * 0.87), eye, 1.5)
	var shoulder := Vector2(f * 2.0, -h * 0.7)
	var tip := shoulder + (_aim * 9.0 if fsm.is_in(&"aim") or fsm.is_in(&"burst") else Vector2(f * 9.0, 2.0))
	draw_line(shoulder, tip, Color(Palette.TERRAIN_TOP, _visibility), 3.0)
