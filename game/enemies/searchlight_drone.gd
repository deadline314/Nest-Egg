class_name SearchlightDrone
extends Enemy
## 探照無人機（偵察）
## 行為：在巡邏範圍內來回飛行，探照燈的光束左右掃過；玩家被光束照到就進入「鎖定」：
##       光束追著玩家、嗶聲越來越急、身上的圓環逐漸填滿；填滿就拉警報，附近的敵人全部被引來。
##       警報後有一段冷卻，期間光束照到也不會再拉。本身沒有攻擊，只有接觸傷害。
## 應對：躲進陰影（牆、平台下、貨箱後面擋住光束）讓圓環退回去；打掉它（脆弱、會飛）；
##       切斷電力：失去動力墜落，光束熄滅，電力恢復後才重新啟動。
## 數值：move_speed = 巡邏速度，detect_range = 巡邏半寬，attack_range = 光束長度，
##       telegraph_time = 站在光束裡到拉警報的時間（任何難度不變），attack_cooldown = 警報後的冷卻，
##       ability_speed = 光束掃動的角速度，ability_radius = 警報影響半徑，ability_time = 被警報引來的敵人保持戒備的秒數。

## 光束半角（弧度）與掃動的幅度（朝正下方左右各一半）。
const BEAM_HALF_ANGLE := 0.2
const SWEEP_AMPLITUDE := 0.9
const BEAM_PADDING := 8.0
## 鎖定時光束追玩家的最高轉速（弧度／秒）；玩家跑得夠快就能甩開。
const TRACK_TURN_SPEED := 1.6
## 離開光束時圓環退回的速度倍率（比填滿快，躲開才有獎勵）。
const DRAIN_SCALE := 1.6
const ALARM_HOLD := 1.4
const BOB := 4.0
const POWER_CHECK_INTERVAL := 0.25
const REBOOT_MAX_TIME := 2.0
const BEEP_SLOW := 0.55
const BEEP_FAST := 0.09
const LAMP_OFFSET := Vector2(0, 3)
const COLOR_PATROL := Color(0.78, 0.93, 1.0)
const COLOR_SPOT := Color(1.0, 0.82, 0.3)
const COLOR_ALARM := Color(1.0, 0.18, 0.2)

var _angle := PI * 0.5
var _charge := 0.0
var _cooldown := 0.0
var _beam_length := 0.0
var _beam_end := Vector2.ZERO
var _beep_left := 0.0
var _power_check := 0.0
var _powered := true
var _shaft: LightShaft
var _pool: PointLight2D
var _sweep_time := 0.0


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"spot", _spot_tick, _spot_enter)
	fsm.add(&"alarm", _alarm_tick, _alarm_enter)
	fsm.add(&"unpowered", _unpowered_tick, _unpowered_enter, _unpowered_exit)
	fsm.add(&"reboot", _reboot_tick)
	fsm.start(&"patrol")


func _ready() -> void:
	super._ready()
	if data == null:
		return
	_angle = PI * 0.5
	# 光束從掃動範圍的最左邊開始，玩家第一次看到時它還沒掃到自己。
	_sweep_time = -PI * 0.5 / maxf(0.1, data.ability_speed)
	_beam_length = data.attack_range
	_shaft = LightShaft.new()
	_shaft.length = data.attack_range
	_shaft.half_width = data.attack_range * tan(BEAM_HALF_ANGLE)
	_shaft.halo_radius = 9.0
	_shaft.intensity = 0.0
	add_child(_shaft)
	# 光束末端的光池：受預算管理的場景光，所以迷彩獵手站進光裡會現形。
	_pool = LightKit.create_point_light(COLOR_PATROL, 70.0, 1.2, false)
	_pool.enabled = false
	add_child(_pool)


func is_powered_on() -> bool:
	return _powered


## 目前的警戒程度 0~1（圓環填滿的比例）。
func charge() -> float:
	return _charge


## 光束方向（世界座標單位向量）。
func beam_direction() -> Vector2:
	return Vector2.RIGHT.rotated(_angle)


func _beam_origin() -> Vector2:
	return global_position + Vector2(0, -data.body_size.y * 0.5) + LAMP_OFFSET


func _on_stunned() -> void:
	_charge = 0.0
	if fsm.is_in(&"spot") or fsm.is_in(&"alarm"):
		fsm.transition(&"patrol")


func _on_defeated(_info: DamageInfo) -> void:
	_set_beam_visible(false)


func _physics_process(delta: float) -> void:
	if data != null and not is_dying():
		_check_power(delta)
		if is_stunned():
			_set_beam_visible(false)
		else:
			_update_beam()
	super._physics_process(delta)


# ---------------------------------------------------------------------------
# 供電
# ---------------------------------------------------------------------------

func _check_power(delta: float) -> void:
	_power_check -= delta
	if _power_check > 0.0:
		return
	_power_check = POWER_CHECK_INTERVAL
	var powered := PowerGrid.is_powered(self)
	if powered == _powered:
		return
	_powered = powered
	if not powered:
		fsm.transition(&"unpowered")
	elif fsm.is_in(&"unpowered"):
		fsm.transition(&"reboot")


func _unpowered_enter() -> void:
	_charge = 0.0
	if contact != null:
		contact.active = false
	Fx.burst(_center(), Palette.WARNING, 8, 90.0, 0.35)
	Sfx.play(&"power_down", -8.0)


func _unpowered_exit() -> void:
	if contact != null:
		contact.active = true


func _unpowered_tick(delta: float) -> void:
	# 沒有動力：墜落到地面後躺著，偶爾冒火花。
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	velocity.y = minf(velocity.y + _gravity * delta, MAX_FALL_SPEED)
	if is_on_floor():
		velocity.y = 0.0
		if int(fsm.time_in_state * 10.0) % 11 == 0:
			Fx.burst(_center(), Palette.CYAN, 2, 40.0, 0.2)


func _reboot_tick(delta: float) -> void:
	# 重新啟動：緩緩升回巡邏高度。
	velocity = velocity.move_toward(Vector2(0, clampf((_home.y - global_position.y) * 3.0, -70.0, 0.0)), 300.0 * delta)
	if global_position.y <= _home.y + 4.0 or fsm.time_in_state >= REBOOT_MAX_TIME:
		fsm.transition(&"patrol")


# ---------------------------------------------------------------------------
# 巡邏、鎖定、警報
# ---------------------------------------------------------------------------

func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_charge = maxf(0.0, _charge - delta)
	_sweep_time += delta
	# 光束在正下方左右掃動。
	_angle = PI * 0.5 + sin(_sweep_time * data.ability_speed) * SWEEP_AMPLITUDE
	_fly(delta, data.move_speed)
	if _cooldown <= 0.0 and _player_in_beam():
		fsm.transition(&"spot")


func _spot_enter() -> void:
	_beep_left = 0.0
	_ensure_telegraph_light()
	_telegraph_left = 0.1


func _spot_tick(delta: float) -> void:
	_telegraph_left = maxf(_telegraph_left, 0.1)
	# 鎖定時停下來，光束追著玩家（轉速有限）。
	velocity = velocity.move_toward(Vector2(0, sin(_anim_time * 2.0) * BOB), 500.0 * delta)
	_turn_toward(_target_point(), delta)
	if _player_in_beam():
		_charge += delta / maxf(0.05, data.telegraph_time)
	else:
		_charge -= delta * DRAIN_SCALE / maxf(0.05, data.telegraph_time)
	_beep_left -= delta
	if _beep_left <= 0.0:
		_beep_left = lerpf(BEEP_SLOW, BEEP_FAST, clampf(_charge, 0.0, 1.0))
		Sfx.play(&"beep", -8.0, 0.02)
	if _charge <= 0.0:
		_charge = 0.0
		_telegraph_left = 0.0
		fsm.transition(&"patrol")
	elif _charge >= 1.0:
		_charge = 1.0
		fsm.transition(&"alarm")


func _alarm_enter() -> void:
	_cooldown = _scaled_cooldown(data.attack_cooldown)
	_telegraph_left = 0.0
	raise_alarm()
	Sfx.play(&"alarm", -4.0, 0.02)
	Fx.flash_light(_center(), COLOR_ALARM, data.ability_radius * 0.5, 1.6, 0.4)
	Feel.play(&"alarm_raised")


func _alarm_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
	_turn_toward(_target_point(), delta)
	if fsm.time_in_state >= ALARM_HOLD:
		_charge = 0.0
		fsm.transition(&"patrol")


## 通知半徑內的敵人：保持戒備、往玩家所在的位置聚集。回傳被通知的數量。
func raise_alarm() -> int:
	var count := 0
	var point := _target_point()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var other := node as Enemy
		if other == null or other == self or other.is_dying() or other.data.is_boss:
			continue
		if other.global_position.distance_to(global_position) <= data.ability_radius:
			other.raise_alert(point, data.ability_time)
			count += 1
	return count


## 水平來回巡邏並維持高度；碰牆或超出範圍就回頭。
func _fly(delta: float, speed: float) -> void:
	var offset := global_position.x - _home.x
	if (offset > data.detect_range and facing > 0) or (offset < -data.detect_range and facing < 0) or is_on_wall():
		facing = -facing
	var desired := Vector2(facing * speed, (_home.y + sin(_anim_time * 2.0) * BOB - global_position.y) * 3.0)
	velocity = velocity.move_toward(desired, 400.0 * delta)


func _turn_toward(point: Vector2, delta: float) -> void:
	var desired := (point - _beam_origin()).angle()
	var diff := wrapf(desired - _angle, -PI, PI)
	_angle += clampf(diff, -TRACK_TURN_SPEED * delta, TRACK_TURN_SPEED * delta)


## 玩家是否在光束裡：在光束長度內、夾角在半角（隨距離變寬的錐形）內、中間沒有牆。
func _player_in_beam() -> bool:
	var target := _target()
	if target == null:
		return false
	var origin := _beam_origin()
	var to_target := _target_point() - origin
	var distance := to_target.length()
	if distance > _beam_length or distance < 1.0:
		return false
	var half_width := distance * tan(BEAM_HALF_ANGLE) + BEAM_PADDING
	var along := to_target.dot(beam_direction())
	if along <= 0.0 or absf(to_target.cross(beam_direction())) > half_width:
		return false
	var query := PhysicsRayQueryParameters2D.create(origin, _target_point(), Layers.WORLD)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# ---------------------------------------------------------------------------
# 光束（光錐與光池）
# ---------------------------------------------------------------------------

func _beam_color() -> Color:
	if fsm.is_in(&"alarm"):
		return COLOR_ALARM
	return COLOR_PATROL.lerp(COLOR_SPOT, clampf(_charge * 2.0, 0.0, 1.0)).lerp(COLOR_ALARM, clampf(_charge * 2.0 - 1.0, 0.0, 1.0))


func _beam_active() -> bool:
	return _powered and not is_dying() and not is_stunned() and not fsm.is_in(&"unpowered") and not fsm.is_in(&"reboot")


func _update_beam() -> void:
	if _shaft == null:
		return
	if not _beam_active():
		_set_beam_visible(false)
		return
	var origin := _beam_origin()
	var dir := beam_direction()
	# 光束被牆或地面擋住就截斷：躲在掩體後面一眼看得出來有效。
	var end := origin + dir * data.attack_range
	var query := PhysicsRayQueryParameters2D.create(origin, end, Layers.WORLD)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit["position"]
	_beam_end = end
	_beam_length = maxf(8.0, origin.distance_to(end))
	var color := _beam_color()
	var flash := 1.0
	if fsm.is_in(&"alarm"):
		flash = 0.65 + 0.35 * sin(fsm.time_in_state * 26.0)
	_shaft.position = to_local(origin)
	_shaft.direction = dir
	_shaft.length = _beam_length
	_shaft.half_width = _beam_length * tan(BEAM_HALF_ANGLE)
	_shaft.color = color
	_shaft.intensity = (1.25 + 0.25 * _charge) * flash
	_shaft.visible = true
	_pool.enabled = true
	_pool.global_position = end - dir * 6.0
	_pool.color = color
	_pool.energy = 1.2 * flash


## 熄滅光束（停電、暈眩、死亡）。
func _set_beam_visible(on: bool) -> void:
	if _shaft != null and not on:
		_shaft.intensity = 0.0
	if _pool != null and not on:
		_pool.enabled = false


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

func _draw_overlay() -> void:
	if not _beam_active():
		return
	var color := _beam_color()
	var from := to_local(_beam_origin())
	var dir := beam_direction()
	var perp := dir.orthogonal()
	var spread := tan(BEAM_HALF_ANGLE) * _beam_length
	# 光錐的邊線：就算光影品質調低也看得出危險範圍。
	var edge := LightKit.glow(color, 1.6)
	edge.a = 0.35 + 0.3 * _charge
	var tip := from + dir * _beam_length
	draw_line(from, tip + perp * spread, edge, 1.0)
	draw_line(from, tip - perp * spread, edge, 1.0)
	# 警戒圓環：隨站在光束裡的時間填滿。
	if _charge > 0.0:
		var center := Vector2(0, -data.body_size.y * 0.5)
		var ring := LightKit.glow(color, 2.6)
		draw_arc(center, data.body_size.x * 0.75, -PI * 0.5, -PI * 0.5 + TAU * _charge, 24, ring, 2.0)


func _draw_body(color: Color) -> void:
	# 探照燈機身：鉻色扁圓機身、朝向光束的燈筒、頂部的旋翼與狀態燈。
	var h := data.body_size.y
	var w := data.body_size.x
	var c := Vector2(0, -h * 0.5)
	var chrome := Color("8d97ab") if color != Palette.WHITE else Palette.WHITE
	var powered := _powered and not fsm.is_in(&"unpowered")
	draw_circle(c, w * 0.42, chrome.darkened(0.4))
	draw_arc(c, w * 0.42, 0.0, TAU, 14, Color("07080d"), 1.0)
	draw_line(c + Vector2(-w * 0.3, -h * 0.15), c + Vector2(w * 0.3, -h * 0.15), chrome.lightened(0.25), 1.0)
	if powered:
		var spin := absf(sin(_anim_time * 38.0)) * w * 0.7
		for side: float in [-1.0, 1.0]:
			var hub := c + Vector2(side * w * 0.42, -h * 0.5)
			draw_line(hub + Vector2(-spin * 0.5, 0), hub + Vector2(spin * 0.5, 0), Color(Palette.CYAN, 0.7), 1.0)
	# 燈筒：指向光束方向。
	var lamp := c + LAMP_OFFSET
	var dir := beam_direction() if powered else Vector2.DOWN
	draw_line(lamp, lamp + dir * 7.0, Color("2b3140"), 4.0)
	var lens := _beam_color() if powered else Color("3a2f2f")
	draw_circle(lamp + dir * 7.0, 2.4, LightKit.glow(lens, 3.0 if powered else 0.4))
	# 狀態燈：巡邏綠、鎖定黃、警報紅（閃）、無電熄滅。
	var led := Palette.NEON_GREEN if _charge <= 0.0 else (COLOR_ALARM if fsm.is_in(&"alarm") and int(_anim_time * 12.0) % 2 == 0 else COLOR_SPOT)
	draw_circle(c + Vector2(-w * 0.3, -h * 0.05), 1.2, LightKit.glow(led, 2.2) if powered else Color("2a2020"))
