class_name HeavyGunner
extends Enemy
## 重裝機槍手（重火力）
## 行為：發現玩家後停下腳步，槍管旋轉加速（預兆：嗡嗡聲越來越尖、槍口光環越轉越亮，前搖很長）；
##       接著原地掃射，射速隨轉速一路加快、瞄準只能慢慢轉；掃射結束槍管過熱，噴出蒸汽並打開裝甲（空檔）。
##       正面裝甲會擋掉子彈，只有過熱的空檔或從背後才打得進去。
## 應對：在轉速拉高前拉開距離或躲到掩體後；掃射時橫向走位、跳過子彈；過熱空檔全力輸出，
##       或繞到背後；爆炸與終結技無視裝甲，隨時有效。
## 數值：telegraph_time = 槍管旋轉加速（前搖），ability_time = 掃射秒數（射速由慢到快），
##       ability_speed = 過熱空檔秒數，attack_cooldown = 兩輪掃射的間隔，projectile = 子彈。

const SLOW_INTERVAL := 0.34
const FAST_INTERVAL := 0.08
## 掃射時瞄準的轉速（弧度／秒）與最大偏角（相對面向）。
const AIM_TURN_SPEED := 0.75
const MAX_AIM_OFFSET := 1.15
const SPREAD := 0.045
const VENT_DAMAGE_SCALE := 1.5
const APPROACH_RATIO := 0.8
const SPIN_SOUND_SLOW := 0.3
const SPIN_SOUND_FAST := 0.07

## 這一輪掃射已經打出的子彈數（測試與難度調整用）。
var shots_fired := 0

var _aim := Vector2.LEFT
var _cooldown := 0.8
var _fire_left := 0.0
var _spin := 0.0
var _heat := 0.0
var _sound_left := 0.0
var _steam_left := 0.0
var _armor_open := false


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"spin_up", _spin_up_tick, _spin_up_enter)
	fsm.add(&"fire", _fire_tick, _fire_enter)
	fsm.add(&"vent", _vent_tick, _vent_enter, _vent_exit)
	fsm.start(&"patrol")


## 0~1：槍管轉速（預兆時隨時間上升，掃射中維持最高，空檔歸零）。
func spin() -> float:
	return _spin


## 0~1：槍管熱度（掃射中上升，過熱空檔下降）。
func heat() -> float:
	return _heat


func is_armor_open() -> bool:
	return _armor_open


func _on_stunned() -> void:
	if fsm.is_in(&"spin_up") or fsm.is_in(&"fire"):
		fsm.transition(&"vent")


## 正面裝甲：面向側來的攻擊被擋下；槍管過熱、暈眩時裝甲打開。爆炸與終結技本來就無視（bypass_guard）。
func _guard(info: DamageInfo) -> Hurtbox.Guard:
	if _armor_open or is_stunned():
		return Hurtbox.Guard.NONE
	var from_x := info.origin.x - global_position.x
	if info.origin == Vector2.ZERO and info.knockback.x != 0.0:
		from_x = -info.knockback.x
	return Hurtbox.Guard.BLOCK if signf(from_x) == float(facing) else Hurtbox.Guard.NONE


func _on_blocked(info: DamageInfo) -> void:
	super._on_blocked(info)
	Fx.impact(_center() + Vector2(facing * data.body_size.x * 0.55, -4.0), Vector2(facing, -0.3), Palette.WHITE, 4)


# ---------------------------------------------------------------------------
# 狀態
# ---------------------------------------------------------------------------

func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_spin = move_toward(_spin, 0.0, 2.0 * delta)
	_heat = move_toward(_heat, 0.0, 0.6 * delta)
	if not _can_see_target(data.detect_range, 90.0):
		_patrol(data.move_speed)
		return
	_face_target()
	var distance := _distance_to_target()
	if distance > data.attack_range * APPROACH_RATIO and not (is_on_floor() and _is_ledge_ahead()):
		velocity.x = facing * data.move_speed
	else:
		velocity.x = 0.0
	if _cooldown <= 0.0 and _token_free() and distance <= data.attack_range and _has_line_of_sight():
		fsm.transition(&"spin_up")


func _spin_up_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_aim = _direction_to_target()
	_sound_left = 0.0
	_start_telegraph(data.telegraph_time)


func _spin_up_tick(delta: float) -> void:
	velocity.x = 0.0
	_spin = clampf(fsm.time_in_state / maxf(0.05, data.telegraph_time), 0.0, 1.0)
	_aim_toward_target(delta)
	_sound_left -= delta
	if _sound_left <= 0.0:
		_sound_left = lerpf(SPIN_SOUND_SLOW, SPIN_SOUND_FAST, _spin)
		Sfx.play(&"spin", -10.0 + 6.0 * _spin, 0.04)
	if not is_telegraphing():
		fsm.transition(&"fire")


func _fire_enter() -> void:
	_fire_left = 0.0
	_spin = 1.0
	shots_fired = 0


func _fire_tick(delta: float) -> void:
	velocity.x = 0.0
	_aim_toward_target(delta)
	_fire_left -= delta
	if _fire_left <= 0.0 and _has_line_of_sight():
		_fire_left = FAST_INTERVAL + (SLOW_INTERVAL - FAST_INTERVAL) * (1.0 - _fire_progress())
		var spread := Vector2.RIGHT.rotated(_aim.angle() + randf_range(-SPREAD, SPREAD))
		_shoot(data.projectile, spread)
		shots_fired += 1
	_heat = _fire_progress()
	if fsm.time_in_state >= data.ability_time:
		fsm.transition(&"vent")


## 掃射進度 0~1：射速隨進度變快。
func _fire_progress() -> float:
	return clampf(fsm.time_in_state / maxf(0.1, data.ability_time), 0.0, 1.0)


func _vent_enter() -> void:
	_armor_open = true
	hurtbox.damage_scale = VENT_DAMAGE_SCALE
	_steam_left = 0.0
	Sfx.play(&"vent", -4.0)
	Fx.burst(_center(), Palette.WARNING, 10, 80.0, 0.5)


func _vent_exit() -> void:
	_armor_open = false
	hurtbox.damage_scale = 1.0
	_cooldown = _scaled_cooldown(data.attack_cooldown)
	_face_target()


func _vent_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_spin = move_toward(_spin, 0.0, 1.2 * delta)
	_heat = move_toward(_heat, 0.0, delta / maxf(0.5, data.ability_speed))
	_steam_left -= delta
	if _steam_left <= 0.0:
		_steam_left = 0.12
		var vent_at := _center() + Vector2(randf_range(-6.0, 6.0), -data.body_size.y * 0.25)
		Fx.steam(vent_at)
		Fx.burst(vent_at, Color(1.0, 0.75, 0.4), 2, 45.0, 0.5)
	if fsm.time_in_state >= data.ability_speed:
		fsm.transition(&"patrol")


## 瞄準慢慢轉向玩家，偏角限制在面向的前方，繞到背後就打不到。
func _aim_toward_target(delta: float) -> void:
	var desired := (_target_point() - _muzzle()).angle()
	var forward := 0.0 if facing > 0 else PI
	var offset := clampf(wrapf(desired - forward, -PI, PI), -MAX_AIM_OFFSET, MAX_AIM_OFFSET)
	var current := wrapf(_aim.angle() - forward, -PI, PI)
	var step := clampf(offset - current, -AIM_TURN_SPEED * delta, AIM_TURN_SPEED * delta)
	_aim = Vector2.RIGHT.rotated(forward + current + step)


func _rig_aim() -> Vector2:
	if fsm.is_in(&"spin_up") or fsm.is_in(&"fire") or fsm.is_in(&"vent"):
		return _aim
	return Vector2(facing, 0.05).normalized()


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

func _draw_overlay() -> void:
	var muzzle := to_local(_muzzle())
	if _spin > 0.02:
		# 槍管旋轉：槍口前三條轉動的短線與光環，轉速越高越亮越密。
		var color := LightKit.glow(Palette.MAGENTA, 1.2 + 2.0 * _spin)
		var turn := _anim_time * (10.0 + 50.0 * _spin)
		for i in 3:
			var angle := turn + TAU * float(i) / 3.0
			var offset := Vector2(0.0, sin(angle) * 5.0)
			draw_line(muzzle + offset + Vector2(-facing * 10.0, 0), muzzle + offset, Color(color, 0.55 + 0.4 * _spin), 1.0)
		draw_arc(muzzle, 5.0 + 3.0 * _spin, 0.0, TAU, 14, Color(color, 0.5 + 0.4 * _spin), 1.5)
	if fsm.is_in(&"fire"):
		draw_circle(muzzle + _aim * 4.0, 3.0 + 2.0 * randf(), LightKit.glow(Color(1.0, 0.8, 0.5), 3.0))
	if _heat > 0.02:
		# 過熱：槍口與胸口隨熱度由洋紅轉橘紅再轉白熱。
		var hot := Palette.MAGENTA.lerp(Color(1.0, 0.45, 0.1), clampf(_heat * 1.5, 0.0, 1.0)).lerp(Color(1.0, 0.95, 0.8), clampf(_heat * 3.0 - 2.0, 0.0, 1.0))
		draw_circle(muzzle, 4.0 + 3.0 * _heat, Color(LightKit.glow(hot, 2.0 + 2.0 * _heat), 0.6))
	if _armor_open:
		# 裝甲打開：胸口噴出橘色的散熱光，提示現在打得進去。
		var vent := LightKit.glow(Color(1.0, 0.5, 0.15), 3.0 + 0.8 * sin(_anim_time * 18.0))
		var chest := Vector2(0.0, -data.body_size.y * 0.55)
		draw_line(chest + Vector2(-5, -4), chest + Vector2(5, -4), vent, 2.0)
		draw_line(chest + Vector2(-5, 2), chest + Vector2(5, 2), vent, 2.0)


func _draw_body(color: Color) -> void:
	# 骨架載入失敗時的備用外觀：方正的身形與洋紅視窗。
	var f := float(facing)
	var h := data.body_size.y
	draw_line(Vector2(-5, -h * 0.4), Vector2(-5, 0), color.darkened(0.45), 4.0)
	draw_line(Vector2(5, -h * 0.4), Vector2(5, 0), color.darkened(0.45), 4.0)
	draw_rect(Rect2(-10, -h * 0.84, 20, h * 0.5), color.darkened(0.15))
	draw_rect(Rect2(-7, -h, 14, 11), color.darkened(0.3))
	draw_line(Vector2(f * 1.0, -h * 0.92), Vector2(f * 6.0, -h * 0.92), LightKit.glow(Palette.MAGENTA, 2.2), 2.0)
	var shoulder := Vector2(f * 2.0, -h * 0.65)
	draw_line(shoulder, shoulder + _aim * 16.0, Palette.TERRAIN_TOP, 3.0)
