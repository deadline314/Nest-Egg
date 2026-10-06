extends ChainEnemy
## 浮標蟲（第一章淹水通道）：背著浮標燈的圓胖蟲，六條短腿用波浪式步態在地上爬。
## 行為：巡邏；發現玩家後逼近，在中距離停下、身體鼓起發光（預兆 0.6 秒）然後噴出一團酸液（拋物線）。
## 應對：鼓起時離開落點、或貼近牠（近距離只會用身體撞）；被擊敗時會分裂成兩隻小的（小的不再分裂），
##       用範圍武器一次清掉。

const SPIT_RANGE := 150.0
const SPIT_MIN_RANGE := 40.0
const SPIT_TIME := 0.25
const RECOVER_TIME := 0.5
const SPLIT_COUNT := 2
const SPLIT_OFFSET := 8.0
const SPLIT_HOP := 140.0

var _cooldown := 0.0
var _fired := false


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"chase", _chase_tick)
	fsm.add(&"swell", _swell_tick, _swell_enter)
	fsm.add(&"spit", _spit_tick, _spit_enter)
	fsm.add(&"recover", _recover_tick, _recover_enter)
	fsm.start(&"patrol")


func _patrol_tick(_delta: float) -> void:
	_patrol(_move_speed() * 0.5)
	if _can_see_target(data.detect_range, 90.0):
		fsm.transition(&"chase")


func _chase_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_face_target()
	var distance := _distance_to_target()
	if distance > data.detect_range * 1.5:
		fsm.transition(&"patrol")
		return
	var blocked := is_on_floor() and (is_on_wall() or _is_ledge_ahead())
	var stop := _cooldown <= 0.0 and _token_free() and distance <= SPIT_RANGE and distance >= SPIT_MIN_RANGE and _has_line_of_sight()
	velocity.x = 0.0 if blocked or stop else facing * _move_speed()
	if stop:
		fsm.transition(&"swell")


func _swell_enter() -> void:
	velocity.x = 0.0
	_start_telegraph(data.telegraph_time)


func _swell_tick(_delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	if not is_telegraphing():
		fsm.transition(&"spit")


func _spit_enter() -> void:
	velocity.x = 0.0
	_fired = false


func _spit_tick(_delta: float) -> void:
	velocity.x = 0.0
	if not _fired:
		_fired = true
		_spit()
	if fsm.time_in_state >= SPIT_TIME:
		fsm.transition(&"recover")


## 拋物線酸液：依距離抬高發射角，落點大約在玩家腳邊。
func _spit() -> void:
	var spec := data.find_projectile(&"buoy_spit")
	if spec == null:
		return
	var from := _center() + Vector2(facing * data.body_size.x * 0.4, -2.0)
	var offset := _target_point() - from
	var lift := clampf(absf(offset.x) / SPIT_RANGE, 0.2, 1.0) * 0.55
	var direction := Vector2(signf(offset.x) if offset.x != 0.0 else float(facing), -lift).normalized()
	_shoot(spec, direction, from)


func _recover_enter() -> void:
	velocity.x = 0.0
	_cooldown = _scaled_cooldown(data.attack_cooldown)


func _recover_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= RECOVER_TIME:
		fsm.transition(&"chase")


## 被玩家擊敗：分裂成兩隻小的（summon 指定的資料；小的沒有 summon，所以不會一直分裂）。
func _on_defeated(info: DamageInfo) -> void:
	if data.summon == null or data.summon.behavior == null or get_parent() == null:
		return
	if info == null or info.team != Combat.Team.PLAYER:
		return
	for k in SPLIT_COUNT:
		var side := -1.0 if k == 0 else 1.0
		var minion := data.summon.behavior.new() as Enemy
		if minion == null:
			push_error("[BuoyWorm] 分裂物的 behavior 不是 Enemy：%s" % data.summon.id)
			return
		minion.configure(data.summon)
		minion.position = position + Vector2(side * SPLIT_OFFSET, -4.0)
		minion.velocity = Vector2(side * SPLIT_HOP * 0.5, -SPLIT_HOP)
		get_parent().add_child.call_deferred(minion)
	Fx.burst(_center(), data.color, 10, 110.0)


func _draw_overlay() -> void:
	if not fsm.is_in(&"swell"):
		return
	# 鼓起時浮標燈發亮：越接近噴出越亮。
	var progress := 1.0 - _telegraph_left / maxf(0.01, data.telegraph_time)
	var glow := Color(LightKit.glow(Color(0.72, 1.0, 0.15), 1.0 + 2.0 * progress), 0.5 + 0.4 * progress)
	draw_circle(Vector2(float(facing) * -1.0, -data.body_size.y - 1.0), 2.5 + 2.0 * progress, glow)
