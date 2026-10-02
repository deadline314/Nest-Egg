extends Enemy
## 清掃兵（基礎遠程）
## 行為：巡邏 → 發現玩家 → 紅色瞄準線預兆（前 70% 追蹤、後 30% 鎖定）→ 單發射擊。
## 應對：瞄準線變亮＝已鎖定，此時蹲下、跳躍或衝刺即可閃開；殘血時近身終結。

const RECOVER_TIME := 0.35
const TRACK_RATIO := 0.7
const AIM_LINE_LENGTH := 240.0

var _aim := Vector2.LEFT
var _cooldown := 0.0


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"aim", _aim_tick, _aim_enter)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"patrol")


func _on_stunned() -> void:
	fsm.transition(&"recover")


func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	if _cooldown <= 0.0 and _can_see_target(data.attack_range, 90.0):
		fsm.transition(&"aim")


func _aim_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_aim = _direction_to_target()
	_start_telegraph(data.telegraph_time)


func _aim_tick(_delta: float) -> void:
	velocity.x = 0.0
	if not _is_locked():
		_face_target()
		_aim = _direction_to_target()
	if not is_telegraphing():
		_shoot(data.projectile, _aim)
		fsm.transition(&"recover")


func _recover_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= RECOVER_TIME:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"patrol")


func _is_locked() -> bool:
	return fsm.time_in_state >= data.telegraph_time * TRACK_RATIO


func _draw_overlay() -> void:
	if not fsm.is_in(&"aim"):
		return
	var locked := _is_locked()
	var color := LightKit.glow(Palette.DANGER, 2.2 if locked else 1.0)
	color.a = 0.85 if locked else 0.3
	var from := to_local(_muzzle())
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
