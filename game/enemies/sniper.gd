class_name Sniper
extends Enemy
## 狙擊手（遠程狙擊）
## 行為：看見玩家後舉槍，一條很長的紅色雷射以有限的轉速慢慢掃向玩家（掃描）；
##       掃描結束雷射停住，閃三下，然後沿著停住的那條線開火（高速、高傷害）。
## 應對：雷射停住之前離開那條線——橫移、衝刺（無敵）、跳起來，或躲到牆後（雷射被牆截斷就打不到）；
##       開槍後有一段收槍的空檔，是輸出的機會；殘血時近身終結。
## 數值：attack_range = 開始掃描的最遠距離，ability_speed = 雷射轉速（弧度／秒），ability_time = 掃描最長秒數，
##       telegraph_time = 雷射停住後到開火的時間（三次閃爍均分，任何難度不變），attack_cooldown = 兩次射擊的間隔。

const FLASHES := 3
## 閃爍週期中雷射點亮的比例。
const FLASH_ON_RATIO := 0.6
const RECOVER_TIME := 0.7
const SWEEP_THIN_ALPHA := 0.6
const LASER_EXTRA := 80.0
const LOSE_SIGHT_COOLDOWN := 0.8

var _aim := Vector2.LEFT
var _cooldown := 0.6
var _flash_index := -1


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"sweep", _sweep_tick, _sweep_enter)
	fsm.add(&"lock", _lock_tick, _lock_enter)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"idle")


func _on_stunned() -> void:
	_cooldown = 1.0
	fsm.transition(&"idle")


## 目前雷射的方向（世界座標單位向量）。
func aim_direction() -> Vector2:
	return _aim


## 雷射有沒有鎖定（停住並進入閃爍倒數）。
func is_locked() -> bool:
	return fsm.is_in(&"lock")


func _laser_length() -> float:
	return data.attack_range + LASER_EXTRA


func _idle_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	if _cooldown <= 0.0 and _can_see_target(data.attack_range, 260.0):
		fsm.transition(&"sweep")


func _sweep_enter() -> void:
	velocity.x = 0.0
	_face_target()
	# 雷射先從槍口前方水平出發，再慢慢轉向玩家。
	_aim = Vector2(facing, 0.15).normalized()


func _sweep_tick(delta: float) -> void:
	velocity.x = 0.0
	if not _has_line_of_sight():
		_cooldown = LOSE_SIGHT_COOLDOWN
		fsm.transition(&"idle")
		return
	_face_target()
	var desired := (_target_point() - _muzzle()).angle()
	var current := _aim.angle()
	var diff := wrapf(desired - current, -PI, PI)
	var step := clampf(diff, -data.ability_speed * delta, data.ability_speed * delta)
	_aim = Vector2.RIGHT.rotated(current + step)
	if fsm.time_in_state >= data.ability_time:
		fsm.transition(&"lock")


func _lock_enter() -> void:
	velocity.x = 0.0
	_flash_index = -1
	_start_telegraph(data.telegraph_time)


func _lock_tick(_delta: float) -> void:
	velocity.x = 0.0
	# 雷射停住：閃爍三次，每次點亮時嗶一聲。
	var period := data.telegraph_time / float(FLASHES)
	var index := mini(FLASHES - 1, int(fsm.time_in_state / period))
	if index != _flash_index:
		_flash_index = index
		Sfx.play(&"laser_flash", -6.0, 0.02)
	if fsm.time_in_state >= data.telegraph_time:
		_shoot(data.projectile, _aim)
		Fx.kick(-_aim, 3.0)
		fsm.transition(&"recover")


func _recover_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= RECOVER_TIME:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"idle")


func _rig_aim() -> Vector2:
	if fsm.is_in(&"sweep") or fsm.is_in(&"lock") or fsm.is_in(&"recover"):
		return _aim
	return Vector2(facing, 0.05).normalized()


## 這一刻雷射是不是亮著：掃描時一直微亮，鎖定後依閃爍週期明滅。
func laser_phase() -> float:
	if fsm.is_in(&"sweep"):
		return SWEEP_THIN_ALPHA
	if fsm.is_in(&"lock"):
		var period := data.telegraph_time / float(FLASHES)
		var within := fmod(fsm.time_in_state, period) / period
		return 1.0 if within < FLASH_ON_RATIO else 0.12
	return 0.0


func _draw_overlay() -> void:
	var phase := laser_phase()
	if phase <= 0.0:
		return
	var from_world := _muzzle()
	var to_world := from_world + _aim * _laser_length()
	# 雷射被牆擋住就截斷，掩體有沒有效一眼看得出來。
	var query := PhysicsRayQueryParameters2D.create(from_world, to_world, Layers.WORLD)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		to_world = hit["position"]
	var locked := fsm.is_in(&"lock")
	var color := LightKit.glow(Palette.DANGER, 3.0 if locked else 1.8)
	color.a = phase if locked else SWEEP_THIN_ALPHA
	var from := to_local(from_world)
	var to := to_local(to_world)
	draw_line(from, to, color, 2.0 if locked and phase > 0.5 else 1.0)
	if locked and phase > 0.5:
		# 鎖定點：雷射打到的地方亮一顆光點。
		draw_circle(to, 3.0, LightKit.glow(Palette.DANGER, 3.0))
		draw_circle(to, 6.0, Color(Palette.DANGER, 0.25))


func _draw_body(color: Color) -> void:
	# 骨架載入失敗時的備用外觀：披斗篷的細長身形與紅色鏡片。
	var f := float(facing)
	var h := data.body_size.y
	draw_line(Vector2(-3, -h * 0.4), Vector2(-3, 0), color.darkened(0.45), 3.0)
	draw_line(Vector2(3, -h * 0.4), Vector2(3, 0), color.darkened(0.45), 3.0)
	draw_rect(Rect2(-6, -h * 0.82, 12, h * 0.45), color.darkened(0.2))
	draw_circle(Vector2(0, -h * 0.9), 4.5, color.darkened(0.35))
	draw_circle(Vector2(f * 2.5, -h * 0.9), 1.8, LightKit.glow(Palette.DANGER, 2.5))
	var shoulder := Vector2(f * 2.0, -h * 0.7)
	draw_line(shoulder, shoulder + _aim * 14.0, Palette.TERRAIN_TOP, 2.5)
