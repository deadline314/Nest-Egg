class_name InsulationInspector
extends Enemy
## 絕緣巡檢器（第三章泵室與夾層，NE-272）：掛在維修吊軌下的小型脈衝機，沿吊軌滑到玩家上方附近，
## 放下探頭充電，充飽後沿水平方向打出一束脈衝。
## 行為：待機（沿吊軌靠近）→ 充電（探頭降到玩家胸口的高度，前方畫出水平預兆線；最後 PULSE_LOCK 秒高度鎖定、線變亮）
##       → 脈衝（單發水平）→ 收探頭（喘息）→ 待機。
## 應對：預兆線鎖定後蹲下或跳起讓脈衝從身邊過去，也可以舉盾擋；站上上橋或照護步道（吊軌上方）牠就打不到。
## 探頭是看得到的部位，打得到（較痛）；充電時把牠打出硬直會取消這次脈衝。
## 數值：detect_range＝發現距離、telegraph_time＝充電秒數、ability_radius＝吊軌半長、ability_time＝收探頭秒數、
##       projectile＝脈衝；探頭最低降到離地 PROBE_FLOOR_GAP 像素。
## 外觀：目前是程式繪製的吊軌滑車、絕緣子與探頭（角色美術交付前的暫代，NE-272）；資料指定 creature_skin 後改用零件式外觀。

const PULSE_LOCK := 0.3
const RAIL_ACCEL := 260.0
const RAIL_ARRIVE := 6.0
## 探頭收起時在機身下方多遠；最低離地多高（不會鑽進地板）。
const PROBE_REST := 6.0
const PROBE_FLOOR_GAP := 12.0
const PROBE_SPEED := 160.0
const LINE_LENGTH := 360.0
## 玩家要在吊軌下方（腳比吊軌低這麼多）才會出招：站上吊軌上方的步道就安全。
const BELOW_RAIL := 24.0
const RAIL_HEIGHT := 4.0

var _cooldown := 0.6
var _rail_min := 0.0
var _rail_max := 0.0
## 探頭目前離機身底部多遠（向下為正），以及這次充電要降到的距離。
var _probe_drop := PROBE_REST
var _probe_goal := PROBE_REST
var _floor_y := INF
var _ray := PhysicsRayQueryParameters2D.new()


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"charge", _charge_tick, _charge_enter)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"idle")
	_rail_min = _home.x - data.ability_radius
	_rail_max = _home.x + data.ability_radius


func _ready() -> void:
	super._ready()
	if data != null:
		_add_probe_part()


## 探頭的受擊部位跟著探頭上下（看得到的地方就打得到）。
func _add_probe_part() -> void:
	for entry in _parts:
		if (entry["box"] as Hurtbox).part_id == &"probe":
			return
	var part := hurtbox.add_part(&"probe", Vector2(10, 8), _probe_local(), 1.5)
	_parts.append({"box": part, "bone": &"", "offset": Vector2.ZERO, "size": Vector2(10, 8), "mult": 1.5})


func _on_stunned() -> void:
	if fsm.is_in(&"charge"):
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"recover")


func _target_below() -> bool:
	var target := _target()
	return target != null and target.global_position.y > global_position.y + BELOW_RAIL


func _idle_tick(delta: float) -> void:
	if _floor_y == INF:
		_floor_y = _find_floor()  # 第一個物理影格才查：生成當下地形可能還沒登記進物理空間
	_cooldown = maxf(0.0, _cooldown - delta)
	_retract(delta)
	var target := _target()
	var goal := _home.x
	if target != null and _target_below() and _can_see_target(data.detect_range, 400.0):
		goal = clampf(target.global_position.x - signf(target.global_position.x - global_position.x) * 48.0, _rail_min, _rail_max)
		_face_target()
		if _cooldown <= 0.0 and _token_free() and absf(goal - global_position.x) < 24.0:
			fsm.transition(&"charge")
			return
	var dx := goal - global_position.x
	velocity.x = move_toward(velocity.x, signf(dx) * data.move_speed if absf(dx) > RAIL_ARRIVE else 0.0, RAIL_ACCEL * delta)
	velocity.y = 0.0
	global_position.x = clampf(global_position.x, _rail_min, _rail_max)


func _charge_enter() -> void:
	velocity = Vector2.ZERO
	_start_telegraph(data.telegraph_time)
	Sfx.play(&"zap", -10.0)


## 充電：探頭降到玩家胸口的高度；最後 PULSE_LOCK 秒高度鎖定。充飽就打出一束水平脈衝。
func _charge_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	if not is_locked():
		_face_target()
		var target := _target()
		if target != null:
			var chest := target.global_position.y - Player.BODY_SIZE.y * 0.8
			_probe_goal = clampf(chest - global_position.y, PROBE_REST, maxf(PROBE_REST, _floor_y - PROBE_FLOOR_GAP - global_position.y))
	_probe_drop = move_toward(_probe_drop, _probe_goal, PROBE_SPEED * delta)
	_sync_probe_part()
	if not is_telegraphing():
		_fire()


func _fire() -> void:
	_probe_drop = _probe_goal
	_shoot(data.projectile, Vector2(facing, 0), _probe_point())
	Fx.flash_light(_probe_point(), Palette.CYAN, 70.0, 1.6, 0.15)
	_cooldown = _scaled_cooldown(data.attack_cooldown)
	fsm.transition(&"recover")


func _recover_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	_retract(delta)
	if fsm.time_in_state >= data.ability_time:
		fsm.transition(&"idle")


func _retract(delta: float) -> void:
	_probe_drop = move_toward(_probe_drop, PROBE_REST, PROBE_SPEED * 0.6 * delta)
	_sync_probe_part()


## 預兆高度是否已鎖定（充電剩下 PULSE_LOCK 秒以內）。
func is_locked() -> bool:
	return fsm.is_in(&"charge") and _telegraph_left <= PULSE_LOCK


func probe_height_above_floor() -> float:
	return _floor_y - _probe_point().y


func _probe_local() -> Vector2:
	return Vector2(facing * 2.0, _probe_drop)


func _probe_point() -> Vector2:
	return global_position + _probe_local()


func _muzzle() -> Vector2:
	return _probe_point() + Vector2(facing * 6.0, 0)


func _sync_probe_part() -> void:
	for entry in _parts:
		var box := entry["box"] as Hurtbox
		if box.part_id == &"probe":
			hurtbox.move_part(box, _probe_local())


## 吊軌下方的地面高度（世界 y）；找不到就假設在下方 120 像素。
func _find_floor() -> float:
	_ray.from = global_position + Vector2(0, 4)
	_ray.to = global_position + Vector2(0, 400)
	_ray.collision_mask = Layers.WORLD
	var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
	return float((hit["position"] as Vector2).y) if not hit.is_empty() else global_position.y + 120.0


## 吊軌（一直畫）與充電預兆：水平的預兆線從探頭往前，碰到牆就截斷；鎖定時變亮變實。
func _draw_overlay() -> void:
	var top := -data.body_size.y - RAIL_HEIGHT
	var rail_color := Color(0.42, 0.45, 0.52, 0.95)
	draw_line(Vector2(_rail_min - global_position.x - 10.0, top), Vector2(_rail_max - global_position.x + 10.0, top), rail_color, 2.0)
	for x: float in [_rail_min - global_position.x - 10.0, _rail_max - global_position.x + 10.0]:
		draw_line(Vector2(x, top), Vector2(x, top - 10.0), rail_color, 1.0)
	if not fsm.is_in(&"charge"):
		return
	var locked := is_locked()
	var t := 1.0 - clampf(_telegraph_left / maxf(0.01, data.telegraph_time), 0.0, 1.0)
	var from := _probe_local() + Vector2(facing * 6.0, 0)
	var to := from + Vector2(facing * LINE_LENGTH, 0)
	_ray.from = global_position + from
	_ray.to = global_position + to
	_ray.collision_mask = Layers.SOLID
	var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		to = to_local(hit["position"])
	var color := Color(LightKit.glow(Palette.DANGER, 2.6 if locked else 0.9 + 0.8 * t), 0.9 if locked else 0.25 + 0.4 * t)
	draw_line(from, to, color, 2.0 if locked else 1.0)
	# 線上每 10 像素一個小刻度，蓋在主角身上也看得出那一條就是脈衝的高度。
	var tick := from
	while (to.x - tick.x) * facing > 0.0:
		draw_line(tick + Vector2(0, -2.0), tick + Vector2(0, 2.0), color, 1.0)
		tick.x += facing * 10.0
	# 探頭上的電弧越充越密：不用文字也看得出快打了。
	var coil := Color(LightKit.glow(Palette.CYAN, 1.5 + 2.0 * t), 0.5 + 0.5 * t)
	draw_arc(_probe_local(), 4.0 + 2.0 * t, 0.0, TAU, 12, coil, 1.0)


## 程式繪製的外觀（暫代）：吊軌滑車、三片絕緣子、往下垂的探頭線與探頭。
func _draw_body(color: Color) -> void:
	var w := data.body_size.x
	var h := data.body_size.y
	var top := -h
	draw_rect(Rect2(-w * 0.5, top, w, 5.0), color.darkened(0.25))
	for i in 2:
		draw_circle(Vector2(-w * 0.3 + i * w * 0.6, top - 1.0), 2.0, color.darkened(0.5))
	for i in 3:
		var y := top + 7.0 + i * 4.0
		draw_rect(Rect2(-w * 0.32, y, w * 0.64, 3.0), Color(0.55, 0.78, 0.82) if color != Palette.WHITE else color)
	draw_rect(Rect2(-w * 0.4, -5.0, w * 0.8, 5.0), color)
	var probe := _probe_local()
	draw_line(Vector2(0, 0), probe, Color(0.2, 0.22, 0.26), 1.0)
	draw_rect(Rect2(probe + Vector2(-4, -3), Vector2(8, 6)), color.lightened(0.15))
	var eye := LightKit.glow(Palette.CYAN, 3.0 if is_telegraphing() else 1.2)
	draw_circle(probe + Vector2(facing * 3.0, 0), 1.3, eye)
