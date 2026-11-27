extends Enemy
## 清掃兵（基礎遠程）
## 行為：巡邏 → 發現玩家 → 紅色瞄準線預兆（前 70% 追蹤、後 30% 鎖定）→ 單發射擊。
## 附近有落地的貨箱隔在自己和玩家之間時（NE-415），先跑到貨箱後面蹲下，冷卻好了才站起來越過箱頂瞄準。
## 應對：瞄準線變亮＝已鎖定，此時蹲下、跳躍或衝刺即可閃開；殘血時近身終結。躲在貨箱後的趁它探頭時打，或繞到同一側。

const RECOVER_TIME := 0.35
const TRACK_RATIO := 0.7
const AIM_LINE_LENGTH := 240.0
## 找掩體的距離（像素）、跑過去的速度倍率、到位的容許誤差。
const COVER_REACH := 150.0
const COVER_RUN_SCALE := 2.2
const COVER_ARRIVE := 4.0
## 探頭時槍口至少高出箱頂多少（像素）；玩家離開這個距離倍率就不躲了。
const PEEK_CLEARANCE := 6.0
const COVER_LEAVE_RANGE_SCALE := 1.6
## 蹲下時身體判定剩下的高度比例：和站姿一樣按骨架外觀縮放，跪姿的身體判定剛好到箱頂，
## 越過箱頂只打得到跟著骨架的頭部判定（打頭或等它探頭）。
const DUCK_HEIGHT_RATIO := 0.72

var _aim := Vector2.LEFT
var _cooldown := 0.0
var _cover := {}
var _ducked := false


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick, _patrol_enter)
	fsm.add(&"cover", _cover_tick, _cover_enter, _cover_exit)
	fsm.add(&"aim", _aim_tick, _aim_enter)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"patrol")


func _on_stunned() -> void:
	fsm.transition(&"recover")


## 回到巡邏就忘掉上一個掩體，之後的射擊從原本的槍口出去。
func _patrol_enter() -> void:
	_cover = {}


func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	# 沒有任何落地貨箱時和原本完全一樣（冷卻好、有令牌才看，不多打射線）。
	if not CoverSpots.is_empty() and (is_alerted() or _can_see_target(data.attack_range, 90.0)) and _find_cover():
		fsm.transition(&"cover")
	elif _cooldown <= 0.0 and _token_free() and _can_see_target(data.attack_range, 90.0):
		fsm.transition(&"aim")


## 有沒有能躲的落地貨箱；找到就記在 _cover。
func _find_cover() -> bool:
	_cover = {}
	var target := _target()
	if target == null or CoverSpots.is_empty() or not is_on_floor():
		return false
	_cover = CoverSpots.spot_behind(global_position, target.global_position.x, COVER_REACH)
	return not _cover.is_empty()


func _cover_enter() -> void:
	_face_target()


func _cover_exit() -> void:
	_set_ducked(false)


func _cover_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var target := _target()
	# 貨箱沒了、玩家繞到同一側、或玩家走遠了：回去照常巡邏與射擊。
	if target == null or not _find_cover() or global_position.distance_to(target.global_position) > data.attack_range * COVER_LEAVE_RANGE_SCALE:
		fsm.transition(&"patrol")
		return
	var to_spot := float(_cover["x"]) - global_position.x
	if absf(to_spot) > COVER_ARRIVE:
		_set_ducked(false)
		facing = 1 if to_spot > 0.0 else -1
		velocity.x = facing * minf(data.move_speed * COVER_RUN_SCALE, absf(to_spot) / maxf(delta, 0.001))
		return
	velocity.x = 0.0
	_face_target()
	_set_ducked(true)
	if _cooldown <= 0.0 and _token_free() and _peek_sees_target():
		fsm.transition(&"aim")


## 從箱頂上方看不看得到玩家。
func _peek_sees_target() -> bool:
	var target := _target()
	if target == null:
		return false
	var eye := _peek_origin()
	if eye.distance_to(_target_point()) > data.attack_range * ALERT_RANGE_SCALE:
		return false
	var query := PhysicsRayQueryParameters2D.create(eye, _target_point(), Layers.WORLD)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## 槍口；在掩體後面時抬到箱頂上方（越過箱子開槍，不會打到自己的掩體）。
func _peek_origin() -> Vector2:
	var muzzle := _muzzle()
	if _cover.is_empty():
		return muzzle
	return Vector2(muzzle.x, minf(muzzle.y, float(_cover["top"]) - PEEK_CLEARANCE))


func _set_ducked(value: bool) -> void:
	if _ducked == value:
		return
	_ducked = value
	if not value:
		_rig_input.crouching = false
	var size := data.body_size
	var height := size.y * (DUCK_HEIGHT_RATIO if value else 1.0)
	hurtbox.resize(Vector2(size.x, height), Vector2(0.0, -height * 0.5))


func _rig_state(input: RigInput) -> void:
	if _ducked:
		input.crouching = true


func _aim_enter() -> void:
	velocity.x = 0.0
	_set_ducked(false)
	_face_target()
	_aim = (_target_point() - _peek_origin()).normalized()
	_start_telegraph(data.telegraph_time)


func _aim_tick(_delta: float) -> void:
	velocity.x = 0.0
	if not _is_locked():
		_face_target()
		_aim = (_target_point() - _peek_origin()).normalized()
	if not is_telegraphing():
		_shoot(data.projectile, _aim, _peek_origin())
		fsm.transition(&"recover")


func _recover_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= RECOVER_TIME:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"cover" if _find_cover() else &"patrol")


func _rig_aim() -> Vector2:
	if _ducked:
		return Vector2(facing, 0.8).normalized()  # 蹲在掩體後槍口朝下，不露出槍身
	return _aim if fsm.is_in(&"aim") or fsm.is_in(&"recover") else Vector2(facing, 0.1).normalized()


func _is_locked() -> bool:
	return fsm.time_in_state >= data.telegraph_time * TRACK_RATIO


func _draw_overlay() -> void:
	if not fsm.is_in(&"aim"):
		return
	var locked := _is_locked()
	var color := LightKit.glow(Palette.DANGER, 2.2 if locked else 1.0)
	color.a = 0.85 if locked else 0.3
	var from := to_local(_peek_origin())
	draw_line(from, from + _aim * AIM_LINE_LENGTH, color, 1.5 if locked else 1.0)


func _draw_body(color: Color) -> void:
	var f := float(facing)
	var stride := sin(_anim_time * 10.0) * 2.0 if absf(velocity.x) > 5.0 else 0.0
	draw_line(Vector2(-3, -8), Vector2(-3 + stride, 0), color.darkened(0.4), 3.0)
	draw_line(Vector2(3, -8), Vector2(3 - stride, 0), color.darkened(0.4), 3.0)
	draw_rect(Rect2(-6, -19, 12, 11), color)
	draw_rect(Rect2(-6, -19, 12, 3), color.lightened(0.2))
	draw_circle(Vector2(0, -22), 4.0, color.darkened(0.3))
	var eye := LightKit.glow(Palette.DANGER, 3.0 if is_telegraphing() else 1.6)
	draw_line(Vector2(f * 0.5, -22.5), Vector2(f * 4.0, -22.5), eye, 1.5)
	var shoulder := Vector2(f * 2.0, -15)
	draw_line(shoulder, shoulder + _aim * 9.0 if fsm.is_in(&"aim") else shoulder + Vector2(f * 9.0, 2.0), Palette.TERRAIN_TOP, 3.0)
