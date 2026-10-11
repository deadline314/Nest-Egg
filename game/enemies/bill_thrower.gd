extends Enemy
## 票據投手（第二章市集，NE-266）：收帳人的開單員，站定後把一疊收帳單扇形甩出去。
## 行為：巡邏 → 看到玩家就停下保持距離（太近會往後退一步）→ 預兆（舉起一疊單子、扇形兩條邊線，最後一段鎖定方向）→
##       丟出一排慢速紙頁（張與張之間有縫）→ 收招（輸出空檔）。
## 應對：紙頁很慢，從縫裡跳過或蹲過，趁他收招靠近；他不擅長近身，貼上去他只會後退。
## 參數在 EnemyData：projectile（紙頁）、telegraph_time、ability_time（收招）、attack_cooldown、attack_range（開始丟的距離）、
## behavior_params 的 count（一次幾張）、spread（扇形角度）、lock（最後幾秒鎖定）、keep_away（太近時往後退的距離）。
## 外觀：暫用收帳人槍手的骨架，紙疊用程式畫；角色組交付專屬外觀後只改資料。

const DEFAULTS := {"count": 5, "spread": 46.0, "lock": 0.25, "keep_away": 56.0}
const BACKSTEP_SPEED := 70.0
## 看得到多高的玩家：上層的繞道（高五格）在視線外，照劇本可以繞過。
const SIGHT_HEIGHT := 60.0

var _cooldown := 0.6
var _aim := Vector2.RIGHT


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"aim", _aim_tick)
	fsm.add(&"windup", _windup_tick, _windup_enter)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"patrol")


func _param(key: String) -> float:
	return float(data.behavior_params.get(key, DEFAULTS[key]))


func _on_stunned() -> void:
	if fsm.is_in(&"windup"):
		fsm.transition(&"recover")


func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	if _can_see_target(data.detect_range, SIGHT_HEIGHT):
		fsm.transition(&"aim")


## 站定瞄準：太近就往後退一步；冷卻好了、而且有攻擊權杖就開始預兆。
func _aim_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_face_target()
	var gap := _distance_to_target()
	if gap > data.detect_range * 1.4 or not _has_line_of_sight():
		fsm.transition(&"patrol")
		return
	var too_close := gap < _param("keep_away")
	var blocked := is_on_floor() and (is_on_wall() or _is_ledge_behind())
	velocity.x = -facing * BACKSTEP_SPEED if too_close and not blocked else 0.0
	if _cooldown <= 0.0 and gap <= data.attack_range and _token_free():
		fsm.transition(&"windup")


func _is_ledge_behind() -> bool:
	facing = -facing
	var ledge := _is_ledge_ahead()
	facing = -facing
	return ledge


func _windup_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_aim = _direction_to_target()
	_start_telegraph(data.telegraph_time)


func _windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if _telegraph_left > _param("lock"):
		_face_target()
		_aim = _direction_to_target()
	if not is_telegraphing():
		WeaponSystem.fire_spread(data.projectile, _muzzle(), _aim, clampi(int(_param("count")), 1, 9), clampf(_param("spread"), 0.0, 120.0),
				0.0, Combat.Team.ENEMY, _projectile_speed_multiplier())
		_rig_input.recoil = 1.0
		Sfx.play(&"shot_spread", -10.0)
		fsm.transition(&"recover")


func _recover_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= data.ability_time:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"aim")


func _rig_aim() -> Vector2:
	if fsm.is_in(&"windup"):
		return Vector2(facing * 0.3, -0.9).normalized()
	return _aim if fsm.is_in(&"recover") else Vector2(facing, 0.3).normalized()


## 預兆：舉起的紙疊與扇形兩條邊線（鎖定後變亮）。
func _draw_overlay() -> void:
	var hand := _hand_local()
	draw_rect(Rect2(hand + Vector2(-3, -4), Vector2(6, 5)), Color(0.93, 0.9, 0.8))
	draw_rect(Rect2(hand + Vector2(-3, -4), Vector2(6, 5)), Color(0.3, 0.28, 0.25), false, 1.0)
	if not fsm.is_in(&"windup"):
		return
	var t := clampf(fsm.time_in_state / maxf(0.01, data.telegraph_time), 0.0, 1.0)
	var locked := _telegraph_left <= _param("lock")
	var color := Color(LightKit.glow(Palette.DANGER, 1.6 if locked else 0.8 + 0.6 * t), 0.7 if locked else 0.2 + 0.35 * t)
	var spread := deg_to_rad(clampf(_param("spread"), 0.0, 120.0))
	var origin := to_local(_muzzle())
	for side: float in [-0.5, 0.5]:
		draw_line(origin, origin + _aim.rotated(spread * side) * 60.0, color, 1.0)


## 骨架載入失敗時的程式繪製：瘦長的人形、手上一疊單子。
func _draw_body(color: Color) -> void:
	var f := float(facing)
	draw_line(Vector2(-3, -10), Vector2(-3, 0), color.darkened(0.4), 3.0)
	draw_line(Vector2(3, -10), Vector2(3, 0), color.darkened(0.4), 3.0)
	draw_rect(Rect2(-6, -26, 12, 16), color)
	draw_circle(Vector2(0, -30), 4.0, color.darkened(0.3))
	var eye := LightKit.glow(Palette.DANGER, 3.0 if is_telegraphing() else 1.6)
	draw_line(Vector2(f * 0.5, -30.5), Vector2(f * 4.0, -30.5), eye, 1.5)


func _hand_local() -> Vector2:
	var hand := anchor_node(&"hand_front")
	return to_local(hand.global_position) if hand != null else Vector2(facing * 6.0, -data.body_size.y * 0.6)
