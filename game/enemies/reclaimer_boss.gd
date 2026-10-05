extends Enemy
## 頭目「回收員 RECLAIMER」（機動型＋場地機關型）
## 與監管者的重火力不同：靠位移與場地逼玩家移動。所有招式都有明確預兆：
##   衝刺斬（蹲低、刀刃亮起、地上畫出衝刺路線）→ 衝刺穿過去或跳過；衝完是硬直，傷害加成，趁機輸出
##   瞬移射擊（身體閃爍消失、新位置出現圓圈）→ 圈圈出現的位置就是牠現身的地方，離開並躲開瞄準線
##   電軌通電（舉起雙手、地面黃色虛線）→ 虛線的區段 1 秒後通電，跳上平台或移到沒標記的區段
## 生命低於一半進入第二階段：衝刺連續兩次、電軌多標記一段、節奏加快。
## 數值：ability_speed = 衝刺速度，ability_time = 衝刺後硬直秒數，ability_damage = 衝刺與電軌傷害，ability_radius = 電軌區段寬度。

const INTRO_TIME := 1.4
const PHASE_SHIFT_TIME := 1.2
const DASH_OVERSHOOT := 70.0
const DASH_MAX_TIME := 1.4
const BLINK_OUT_TIME := 0.55
const BLINK_AIM_TIME := 0.5
const BLINK_SHOTS := 3
const BLINK_SPREAD := 28.0
const VULNERABLE_SCALE := 1.5
const RAIL_WARN := 1.0
const RAIL_LIVE := 1.1
const MIN_STRAFE := 110.0
const MAX_STRAFE := 190.0
const WALL_MARGIN := 24.0
## 衝刺後的煞車減速度（越大停得越快，不會衝出場地）。
const BRAKE := 4200.0

var _phase := 1
var _arena := Rect2()
var _rails: Array[ElectricRail] = []
var _last_attack: StringName = &""
var _dash_dir := 1
var _dash_target := 0.0
var _dash_count := 0
var _blink_x := 0.0
var _alpha := 1.0
var _vulnerable := false
var _floor_y := 0.0


## 由關卡在頭目生成後呼叫：頭目只在這個範圍內移動，電軌也鋪在這個範圍。
func set_arena(rect: Rect2) -> void:
	_arena = rect


func is_vulnerable() -> bool:
	return _vulnerable


func _uses_activation_culling() -> bool:
	return false


func can_be_finished() -> bool:
	return false


func _setup_states() -> void:
	collision_mask = Layers.WORLD
	_floor_y = global_position.y
	health.health_changed.connect(_on_boss_health_changed)
	fsm.add(&"intro", _intro_tick)
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"dash_windup", _dash_windup_tick, _dash_windup_enter)
	fsm.add(&"dash", _dash_tick, _dash_enter, _dash_exit)
	fsm.add(&"dash_recover", _dash_recover_tick, _dash_recover_enter, _dash_recover_exit)
	fsm.add(&"blink_out", _blink_out_tick, _blink_out_enter)
	fsm.add(&"blink_aim", _blink_aim_tick, _blink_aim_enter)
	fsm.add(&"rail_windup", _rail_windup_tick, _rail_windup_enter)
	fsm.add(&"phase_shift", _phase_shift_tick, _phase_shift_enter)
	fsm.start(&"intro")
	EventBus.boss_started.emit(data.display_name, health.max_health)
	Feel.play(&"boss_intro")
	_build_rails.call_deferred()


## 在場地範圍內鋪好電軌（平時隱形，arm() 才會預警與通電）。
func _build_rails() -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var arena := _arena_rect()
	var width := maxf(32.0, data.ability_radius)
	var count := maxi(1, int(arena.size.x / width))
	var step := arena.size.x / count
	for i in count:
		var rail := ElectricRail.new()
		rail.setup(Rect2(arena.position.x + step * i, _floor_y - ElectricRail.HEIGHT, step, ElectricRail.HEIGHT))
		get_parent().add_child(rail)
		_rails.append(rail)


func _arena_rect() -> Rect2:
	if _arena.size.x > 0.0:
		return _arena
	return Rect2(global_position.x - 320.0, 0.0, 640.0, _floor_y)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# 保險：無論怎麼被擊退或衝刺，都不離開場地範圍。
	var arena := _arena_rect()
	global_position.x = clampf(global_position.x, arena.position.x, arena.end.x)


func _exit_tree() -> void:
	for rail in _rails:
		if is_instance_valid(rail):
			rail.queue_free()
	_rails.clear()


# ---------------------------------------------------------------------------
# 狀態
# ---------------------------------------------------------------------------

func _intro_tick(_delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	if fsm.time_in_state >= INTRO_TIME:
		fsm.transition(&"idle")


## 待機：在玩家附近橫移，保持中距離，時間到就選一個招式。
func _idle_tick(delta: float) -> void:
	_face_target()
	var target := _target()
	var desired := 0.0
	if target != null:
		var dx := target.global_position.x - global_position.x
		var distance := absf(dx)
		if distance < MIN_STRAFE:
			desired = -signf(dx) * data.move_speed
		elif distance > MAX_STRAFE:
			desired = signf(dx) * data.move_speed
		if _near_wall(desired):
			desired = 0.0
	velocity.x = move_toward(velocity.x, desired, 500.0 * delta)
	var wait := _scaled_cooldown(data.attack_cooldown) * (1.0 if _phase == 1 else 0.7)
	if fsm.time_in_state >= wait:
		fsm.transition(_choose_attack())


func _choose_attack() -> StringName:
	var options: Array[StringName] = [&"dash_windup", &"blink_out", &"rail_windup"]
	options.erase(_last_attack)
	var choice: StringName = options.pick_random()
	_last_attack = choice
	_dash_count = 0
	return choice


func _near_wall(direction: float) -> bool:
	var arena := _arena_rect()
	return (direction < 0.0 and global_position.x < arena.position.x + WALL_MARGIN) \
			or (direction > 0.0 and global_position.x > arena.end.x - WALL_MARGIN)


func _windup_time() -> float:
	return data.telegraph_time * (1.0 if _phase == 1 else 0.8)


# --- 衝刺斬 ---------------------------------------------------------------

func _dash_windup_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_start_telegraph(_windup_time() * (0.6 if _dash_count > 0 else 1.0))


func _dash_windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state < _windup_time() * 0.6:
		_face_target()
	if not is_telegraphing():
		fsm.transition(&"dash")


func _dash_enter() -> void:
	var target := _target()
	_dash_dir = facing
	var goal := (target.global_position.x if target != null else global_position.x) + _dash_dir * DASH_OVERSHOOT
	var arena := _arena_rect()
	_dash_target = clampf(goal, arena.position.x + WALL_MARGIN, arena.end.x - WALL_MARGIN)
	if contact != null:
		contact.damage = maxi(data.contact_damage, data.ability_damage)
		contact.source_id = &"reclaimer_dash"
	Fx.dust(global_position, 6, 70.0)
	Sfx.play(&"dash", -3.0, 0.1)


func _dash_exit() -> void:
	if contact != null:
		contact.damage = data.contact_damage
		contact.source_id = data.contact_source_id


func _dash_tick(_delta: float) -> void:
	velocity.x = _dash_dir * data.ability_speed
	if int(fsm.time_in_state * 40.0) % 2 == 0:
		Fx.dust(global_position, 1, 25.0)
	var passed := (_dash_dir > 0 and global_position.x >= _dash_target) or (_dash_dir < 0 and global_position.x <= _dash_target)
	if passed or is_on_wall() or fsm.time_in_state >= DASH_MAX_TIME:
		fsm.transition(&"dash_recover")


## 衝完是硬直：核心外露、受到加成傷害，是輸出的空檔。
func _dash_recover_enter() -> void:
	_vulnerable = true
	hurtbox.damage_scale = VULNERABLE_SCALE
	Feel.play(&"boss_recover_thud")


func _dash_recover_exit() -> void:
	_vulnerable = false
	hurtbox.damage_scale = 1.0


func _dash_recover_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, BRAKE * delta)
	var recover := data.ability_time * (1.0 if _phase == 1 else 0.7)
	if fsm.time_in_state < recover:
		return
	# 第二階段：有機率立刻再衝一次（預兆縮短，但仍有）。
	if _phase >= 2 and _dash_count == 0:
		_dash_count = 1
		fsm.transition(&"dash_windup")
	else:
		_dash_count = 0
		fsm.transition(&"idle")


# --- 瞬移射擊 -------------------------------------------------------------

func _blink_out_enter() -> void:
	velocity.x = 0.0
	_face_target()
	var target := _target()
	var arena := _arena_rect()
	var side := -facing if target != null else 1
	var distance := randf_range(MIN_STRAFE, MAX_STRAFE + 40.0)
	var base := target.global_position.x if target != null else global_position.x
	_blink_x = clampf(base + side * distance, arena.position.x + WALL_MARGIN * 2.0, arena.end.x - WALL_MARGIN * 2.0)
	_start_telegraph(BLINK_OUT_TIME)
	Sfx.play(&"emp", -10.0, 0.2)


func _blink_out_tick(_delta: float) -> void:
	velocity.x = 0.0
	_alpha = lerpf(1.0, 0.15, clampf(fsm.time_in_state / BLINK_OUT_TIME, 0.0, 1.0))
	if fsm.time_in_state >= BLINK_OUT_TIME:
		global_position.x = _blink_x
		Fx.burst(_center(), Palette.WARNING, 12, 130.0, 0.35)
		fsm.transition(&"blink_aim")


func _blink_aim_enter() -> void:
	_alpha = 1.0
	velocity.x = 0.0
	_face_target()
	_start_telegraph(BLINK_AIM_TIME * (1.0 if _phase == 1 else 0.8))


func _blink_aim_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state < BLINK_AIM_TIME * 0.6:
		_face_target()
	if is_telegraphing():
		return
	var spec := data.projectile
	WeaponSystem.fire_spread(spec, _muzzle(), _direction_to_target(), BLINK_SHOTS if _phase == 1 else BLINK_SHOTS + 2,
			BLINK_SPREAD, 0.0, Combat.Team.ENEMY, _projectile_speed_multiplier())
	_rig_input.recoil = 1.0
	Fx.flash_light(_muzzle(), Palette.WARNING, 80.0, 1.8, 0.12)
	Sfx.play(&"shot_spread", -6.0)
	fsm.transition(&"idle")


# --- 電軌通電 -------------------------------------------------------------

func _rail_windup_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_start_telegraph(_windup_time() + 0.2)


func _rail_windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if is_telegraphing():
		return
	_arm_rails()
	fsm.transition(&"idle")


## 標記玩家腳下那一段加上隨機幾段（總是留有安全的區段）。
func _arm_rails() -> void:
	if _rails.size() < 2:
		return
	var chosen: Array[int] = []
	var target := _target()
	if target != null:
		chosen.append(_rail_index_at(target.global_position.x))
	var wanted := mini(_rails.size() - 1, 2 if _phase == 1 else 3)
	var tries := 0
	while chosen.size() < wanted and tries < 24:
		tries += 1
		var index := randi() % _rails.size()
		if not chosen.has(index):
			chosen.append(index)
	for index in chosen:
		_rails[index].arm(RAIL_WARN, RAIL_LIVE)


func _rail_index_at(x: float) -> int:
	for i in _rails.size():
		var rect := _rails[i].rect
		if x >= rect.position.x and x < rect.end.x:
			return i
	return clampi(int((x - _arena_rect().position.x) / maxf(1.0, _arena_rect().size.x / _rails.size())), 0, _rails.size() - 1)


# --- 階段轉換 -------------------------------------------------------------

func _phase_shift_enter() -> void:
	velocity.x = 0.0
	_alpha = 1.0
	_start_telegraph(PHASE_SHIFT_TIME)
	Feel.play(&"boss_phase_shift")
	Fx.flash_light(_center(), Palette.WARNING, 200.0, 2.5, 0.8)
	EventBus.toast_requested.emit("回收員進入過載狀態")
	for rail in _rails:
		rail.disarm()


func _phase_shift_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= PHASE_SHIFT_TIME:
		fsm.transition(&"idle")


func _on_boss_health_changed(current: int, maximum: int) -> void:
	EventBus.boss_health_changed.emit(current, maximum)
	if _phase == 1 and current > 0 and current <= maximum / 2:
		_phase = 2
		if fsm.is_in(&"dash") or fsm.is_in(&"dash_recover"):
			_dash_exit()
			hurtbox.damage_scale = 1.0
			_vulnerable = false
		fsm.transition(&"phase_shift")


func _on_stunned() -> void:
	pass


func _play_death() -> void:
	for rail in _rails:
		if is_instance_valid(rail):
			rail.disarm()
	var tween := create_tween()
	for i in 6:
		tween.tween_callback(_death_blast)
		tween.tween_interval(0.22)
	tween.tween_callback(_finish_death)


func _death_blast() -> void:
	var offset := Vector2(randf_range(-1.0, 1.0) * data.body_size.x * 0.6, -randf() * data.body_size.y)
	Fx.explosion(global_position + offset, 24.0, 0, Combat.Team.PLAYER, &"", Palette.WARNING)


func _finish_death() -> void:
	Fx.flash_light(_center(), Palette.WHITE, 260.0, 3.0, 0.8)
	Fx.burst(_center(), Palette.WARNING, 48, 320.0, 0.8)
	Feel.play(&"boss_death")
	EventBus.boss_defeated.emit()
	queue_free()


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

func _draw_overlay() -> void:
	if rig != null:
		_draw_blade()
	# 瞬移前：在新位置畫出現身圓圈。
	if fsm.is_in(&"blink_out"):
		var t := clampf(fsm.time_in_state / BLINK_OUT_TIME, 0.0, 1.0)
		var center := to_local(Vector2(_blink_x, _floor_y - 2.0))
		var color := LightKit.glow(Palette.WARNING, 1.2 + 1.4 * t)
		color.a = 0.4 + 0.5 * t
		draw_arc(center, 14.0 - 6.0 * t, 0.0, TAU, 24, color, 2.0)
		draw_line(center + Vector2(-18, 0), center + Vector2(18, 0), Color(color, 0.5), 1.0)
	# 衝刺前：路線預告。
	elif fsm.is_in(&"dash_windup"):
		var t := clampf(fsm.time_in_state / maxf(0.01, _windup_time()), 0.0, 1.0)
		var color := LightKit.glow(Palette.DANGER, 1.0 + 1.2 * t)
		color.a = 0.25 + 0.5 * t
		var from := Vector2(facing * 12.0, -4.0)
		draw_line(from, from + Vector2(facing * 150.0, 0.0), color, 1.5)
		draw_colored_polygon(PackedVector2Array([from + Vector2(facing * 150.0, -4.0), from + Vector2(facing * 162.0, 0.0), from + Vector2(facing * 150.0, 4.0)]), color)
	elif fsm.is_in(&"blink_aim"):
		var color := LightKit.glow(Palette.DANGER, 1.4)
		color.a = 0.6
		var from := to_local(_muzzle())
		draw_line(from, from + _direction_to_target() * 240.0, color, 1.0)
	if _vulnerable:
		var core := _core_point()
		var pulse := 0.5 + 0.5 * sin(_anim_time * 20.0)
		draw_arc(core, 9.0 + pulse * 3.0, 0.0, TAU, 24, LightKit.glow(Palette.CYAN, 3.0), 2.0)


## 骨架外觀：衝刺蓄力時蹲低、刀臂舉到身後，衝刺時前伸；瞬移瞄準時舉槍，電軌預兆時高舉。
func _rig_aim() -> Vector2:
	if fsm.is_in(&"dash_windup"):
		return Vector2(-facing * 0.6, -0.8).normalized()
	if fsm.is_in(&"dash"):
		return Vector2(facing, 0.05).normalized()
	if fsm.is_in(&"blink_aim"):
		return _direction_to_target()
	if fsm.is_in(&"rail_windup"):
		return Vector2(0.0, -1.0)
	return _direction_to_target() if _target() != null else Vector2(facing, 0.9).normalized()


func _rig_state(input: RigInput) -> void:
	input.crouching = fsm.is_in(&"dash_windup")
	input.two_handed = false
	input.dashing = fsm.is_in(&"dash")
	if rig != null:
		var tint := Color.WHITE if _phase == 1 else Color(1.0, 0.88, 0.72)
		rig.modulate = Color(tint, _alpha)


## 刀刃接在骨架的前手上；衝刺蓄力與衝刺時發亮。
func _draw_blade() -> void:
	var hand := rig.bone(&"hand_front")
	var forearm := rig.bone(&"arm_front_lower")
	if hand == null or forearm == null:
		return
	var armed := fsm.is_in(&"dash_windup") or fsm.is_in(&"dash")
	var from := to_local(hand.global_position)
	var along := (hand.global_position - forearm.global_position).normalized()
	var blade := LightKit.glow(Palette.WARNING, 3.2 if armed else 1.4)
	blade.a = _alpha
	draw_line(from, from + along * 18.0, blade, 2.5)


func _draw_body(color: Color) -> void:
	var w := data.body_size.x
	var h := data.body_size.y
	var f := float(facing)
	var alpha := _alpha
	var base := color if _phase == 1 else color.lerp(Palette.WARNING, 0.3)
	var c := Color(base, base.a * alpha)
	var crouch := 8.0 if fsm.is_in(&"dash_windup") else 0.0
	var stride := sin(_anim_time * 14.0) * 3.0 if absf(velocity.x) > 20.0 else 0.0
	# 腿
	draw_line(Vector2(-4, -h * 0.4 + crouch), Vector2(-4 + stride, 0), c.darkened(0.5), 4.0)
	draw_line(Vector2(4, -h * 0.4 + crouch), Vector2(4 - stride, 0), c.darkened(0.5), 4.0)
	# 軀幹與長大衣（衝刺時往後飄）
	var coat_back := -f * (14.0 if fsm.is_in(&"dash") else 4.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.4, -h * 0.8 + crouch), Vector2(w * 0.4, -h * 0.8 + crouch),
			Vector2(w * 0.35 + coat_back, -h * 0.18), Vector2(-w * 0.35 + coat_back, -h * 0.18)]), c)
	draw_rect(Rect2(-w * 0.45, -h * 0.82 + crouch, w * 0.9, h * 0.12), c.lightened(0.2))
	# 頭盔與橘色單眼視窗
	draw_circle(Vector2(f * 1.0, -h * 0.9 + crouch), 6.0, c.darkened(0.25))
	var eye := LightKit.glow(Palette.WARNING, 3.5 if is_telegraphing() else 1.8)
	eye.a = alpha
	draw_line(Vector2(f * 1.0, -h * 0.91 + crouch), Vector2(f * 7.0, -h * 0.91 + crouch), eye, 2.0)
	# 刀臂：蓄力時舉到身後、衝刺時前伸。
	var shoulder := Vector2(f * 2.0, -h * 0.75 + crouch)
	var tip := shoulder + (Vector2(-f * 10.0, -9.0) if fsm.is_in(&"dash_windup") else (Vector2(f * 18.0, 0.0) if fsm.is_in(&"dash") else Vector2(f * 6.0, 10.0)))
	draw_line(shoulder, tip, Color(Palette.TERRAIN_TOP, alpha), 3.0)
	var blade := LightKit.glow(Palette.WARNING, 3.2 if fsm.is_in(&"dash_windup") or fsm.is_in(&"dash") else 1.4)
	blade.a = alpha
	draw_line(tip, tip + (tip - shoulder).normalized() * 12.0, blade, 2.5)
	# 另一隻手：瞬移瞄準時舉槍、電軌預兆時高舉。
	var off_shoulder := Vector2(-f * 2.0, -h * 0.75 + crouch)
	var off_tip := off_shoulder + (_direction_to_target() * 12.0 if fsm.is_in(&"blink_aim") else (Vector2(0, -14.0) if fsm.is_in(&"rail_windup") else Vector2(-f * 5.0, 9.0)))
	draw_line(off_shoulder, off_tip, Color(Palette.TERRAIN_TOP, alpha), 3.0)
	# 天線
	draw_line(Vector2(0, -h * 0.96 + crouch), Vector2(-f * 4.0, -h * 1.08 + crouch), Color(Palette.TERRAIN_TOP, alpha), 1.5)
	# 核心（硬直時外露）
	var core := Vector2(0, -h * 0.55 + crouch)
	var core_color := LightKit.glow(Palette.CYAN, 3.0 + sin(_anim_time * 20.0)) if _vulnerable else c.darkened(0.55)
	core_color.a = alpha
	draw_circle(core, w * (0.24 if _vulnerable else 0.14), core_color)
