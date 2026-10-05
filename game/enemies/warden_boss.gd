extends Enemy
## 頭目「監管者 WARDEN」
## 所有招式都有明確預兆，讓玩家「學會就能贏」：
##   點射（眼睛發紅）      → 蹲下或跳躍閃避
##   跳躍震波（下蹲蓄力）  → 落地瞬間跳起避開地面震波；落地後核心外露 1.5 秒，受到雙倍傷害
##   扇形彈幕（雙臂張開）  → 找彈幕縫隙鑽過（第二階段）
##   召喚監視蜂（天線閃爍）→ 優先向上射擊清掉（第二階段）
##   核心砲（胸甲掀開）    → 胸口亮起一條瞄準線，閃開後核心外露、打核心受雙倍傷害（第二階段，NE-89 的專屬骨頭範例）
## 生命低於一半進入第二階段：節奏加快、招式增加。

const INTRO_TIME := 1.4
const BURST_INTERVAL := 0.12
const LEAP_VELOCITY := 400.0
const MAX_LEAP_SPEED := 280.0
const MIN_AIR_TIME := 0.2
const VULNERABLE_TIME := 1.5
const VULNERABLE_DAMAGE_SCALE := 2.0
const PHASE_SHIFT_TIME := 1.2
const MAX_SUMMONS := 2
const FAN_COUNT := 7
const FAN_SPREAD := 80.0
## 核心砲：3 發窄扇形從專屬骨頭 core_port 出去；發射後胸甲維持掀開，核心外露的時間內打核心受雙倍傷害。
const CORE_FIRE_COUNT := 3
const CORE_FIRE_SPREAD := 14.0
const CORE_EXPOSED_TIME := 1.1
const CORE_EXPOSED_SCALE := 2.0
const CORE_PART := &"core"

var _phase := 1
var _burst_left := 0
var _last_attack: StringName = &""
var _summons: Array[WeakRef] = []
var _vulnerable_left := 0.0


func _rig_aim() -> Vector2:
	return _direction_to_target() if _target() != null else Vector2(facing, 0.1).normalized()


func _uses_activation_culling() -> bool:
	return false


func can_be_finished() -> bool:
	return false


func _setup_states() -> void:
	collision_mask = Layers.WORLD  # 頭目不站單向平台，維持戰場節奏
	health.health_changed.connect(_on_boss_health_changed)
	fsm.add(&"intro", _intro_tick)
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"burst_windup", _burst_windup_tick, _windup_enter)
	fsm.add(&"burst", _burst_tick, _burst_enter)
	fsm.add(&"leap_windup", _leap_windup_tick, _windup_enter)
	fsm.add(&"leap", _leap_tick, _leap_enter)
	fsm.add(&"fan_windup", _fan_windup_tick, _windup_enter)
	fsm.add(&"summon_windup", _summon_windup_tick, _windup_enter)
	fsm.add(&"core_windup", _core_windup_tick, _windup_enter)
	fsm.add(&"core_recover", _core_recover_tick, Callable(), _core_recover_exit)
	fsm.add(&"phase_shift", _phase_shift_tick, _phase_shift_enter)
	fsm.start(_start_state())
	_announce()


## 起始狀態與開場宣告（血條、開場音效）；迷你頭目覆寫成「睡著等玩家靠近才宣告」。
func _start_state() -> StringName:
	return &"intro"


func _announce() -> void:
	EventBus.boss_started.emit(data.display_name, health.max_health)
	Feel.play(&"boss_intro")


func _physics_process(delta: float) -> void:
	if _vulnerable_left > 0.0:
		_vulnerable_left -= delta
		if _vulnerable_left <= 0.0:
			hurtbox.damage_scale = 1.0
	super._physics_process(delta)


# ---------------------------------------------------------------------------
# 狀態
# ---------------------------------------------------------------------------

func _intro_tick(_delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	if fsm.time_in_state >= INTRO_TIME:
		fsm.transition(&"idle")


func _idle_tick(delta: float) -> void:
	_face_target()
	var desired := facing * data.move_speed * (0.4 if _phase == 1 else 0.7)
	velocity.x = move_toward(velocity.x, desired, 400.0 * delta)
	var wait := _scaled_cooldown(data.attack_cooldown) * (1.0 if _phase == 1 else 0.7)
	if fsm.time_in_state >= wait:
		fsm.transition(_choose_attack())


func _choose_attack() -> StringName:
	var options: Array[StringName] = [&"burst_windup", &"leap_windup"]
	if _phase >= 2:
		options.append(&"fan_windup")
		options.append(&"core_windup")
		if _alive_summons() < MAX_SUMMONS:
			options.append(&"summon_windup")
	if options.size() > 1:
		options.erase(_last_attack)
	var choice: StringName = options.pick_random()
	_last_attack = choice
	return choice


func _windup_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_start_telegraph(data.telegraph_time * (1.0 if _phase == 1 else 0.8))


func _burst_windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	if not is_telegraphing():
		fsm.transition(&"burst")


func _burst_enter() -> void:
	_burst_left = 3 if _phase == 1 else 5


func _burst_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state < BURST_INTERVAL:
		return
	_face_target()
	_shoot(data.projectile, _direction_to_target())
	_burst_left -= 1
	fsm.time_in_state = 0.0
	if _burst_left <= 0:
		fsm.transition(&"idle")


func _leap_windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if not is_telegraphing():
		fsm.transition(&"leap")


func _leap_enter() -> void:
	var target := _target()
	var dx := (target.global_position.x - global_position.x) if target != null else 0.0
	var air_time := 2.0 * LEAP_VELOCITY / _gravity
	velocity = Vector2(clampf(dx / air_time, -MAX_LEAP_SPEED, MAX_LEAP_SPEED), -LEAP_VELOCITY)
	Fx.dust(global_position, 8, 80.0)


func _leap_tick(_delta: float) -> void:
	if fsm.time_in_state >= MIN_AIR_TIME and is_on_floor():
		_land()


func _land() -> void:
	velocity.x = 0.0
	Feel.play(&"boss_land")
	Fx.dust(global_position, 12, 120.0)
	Sfx.play(&"explosion", -6.0)
	var shockwave := data.find_projectile(&"boss_shockwave")
	var origin := global_position + Vector2(0, -6)
	for side: float in [-1.0, 1.0]:
		_shoot(shockwave, Vector2(side, 0), origin + Vector2(side * data.body_size.x * 0.5, 0))
	# 落地後核心外露：獎勵成功閃避的玩家。
	_vulnerable_left = VULNERABLE_TIME
	hurtbox.damage_scale = VULNERABLE_DAMAGE_SCALE
	fsm.transition(&"idle")


func _fan_windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	if not is_telegraphing():
		var spec := data.find_projectile(&"boss_fan")
		WeaponSystem.fire_spread(spec, _muzzle(), _direction_to_target(), FAN_COUNT, FAN_SPREAD, 0.0,
				Combat.Team.ENEMY, _projectile_speed_multiplier())
		_rig_input.recoil = 1.0
		Fx.flash_light(_muzzle(), Palette.DANGER, 90.0, 2.0, 0.15)
		Sfx.play(&"shot_spread", -4.0)
		fsm.transition(&"idle")


## 核心砲：預兆時胸甲掀開、胸口（core_port）亮起瞄準線；預兆結束從核心打出窄扇形，之後核心外露一小段時間。
func _core_windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	if is_telegraphing():
		return
	var origin := _core_point() + global_position
	WeaponSystem.fire_spread(data.find_projectile(&"boss_fan"), origin, _direction_to_target(), CORE_FIRE_COUNT, CORE_FIRE_SPREAD, 0.0,
			Combat.Team.ENEMY, _projectile_speed_multiplier())
	_rig_input.recoil = 1.0
	Fx.flash_light(origin, Palette.CYAN, 110.0, 2.2, 0.2)
	Sfx.play(&"shot_spread", -4.0)
	_set_core_exposed(true)
	fsm.transition(&"core_recover")


func _core_recover_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= CORE_EXPOSED_TIME:
		fsm.transition(&"idle")


func _core_recover_exit() -> void:
	_set_core_exposed(false)


## 核心部位判定的倍率：外露時雙倍（受擊回饋會標示為弱點），收起來回到一般。
func _set_core_exposed(exposed: bool) -> void:
	for part in hurtbox.parts:
		if part.part_id == CORE_PART:
			part.damage_scale = CORE_EXPOSED_SCALE if exposed else 1.0


func _summon_windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if not is_telegraphing():
		_summon()
		fsm.transition(&"idle")


func _summon() -> void:
	if data.summon == null or data.summon.behavior == null or get_parent() == null:
		return
	for side: float in [-1.0, 1.0]:
		if _alive_summons() >= MAX_SUMMONS:
			return
		var minion := data.summon.behavior.new() as Enemy
		if minion == null:
			push_error("[Warden] 召喚物的 behavior 不是 Enemy。")
			return
		minion.configure(data.summon)
		minion.position = position + Vector2(side * 70.0, -120.0)
		get_parent().add_child.call_deferred(minion)
		_summons.append(weakref(minion))
		Fx.burst(minion.position, data.summon.color, 10, 120.0)


func _alive_summons() -> int:
	var alive := 0
	var kept: Array[WeakRef] = []
	for ref in _summons:
		var minion := ref.get_ref() as Enemy
		if minion == null or minion.is_queued_for_deletion():
			continue
		if minion.health != null and minion.health.is_dead:
			continue
		alive += 1
		kept.append(ref)
	_summons = kept
	return alive


func _phase_shift_enter() -> void:
	velocity.x = 0.0
	_start_telegraph(PHASE_SHIFT_TIME)
	Feel.play(&"boss_phase_shift")
	Fx.flash_light(_center(), Palette.DANGER, 200.0, 2.5, 0.8)
	EventBus.toast_requested.emit("監管者進入暴走狀態")


func _phase_shift_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= PHASE_SHIFT_TIME:
		fsm.transition(&"idle")


# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------

func _on_boss_health_changed(current: int, maximum: int) -> void:
	EventBus.boss_health_changed.emit(current, maximum)
	if _phase == 1 and current > 0 and current <= maximum / 2:
		_phase = 2
		if rig != null:
			rig.modulate = Color(1.25, 0.8, 0.8)
		if not fsm.is_in(&"leap"):
			fsm.transition(&"phase_shift")


func _on_stunned() -> void:
	pass


func _play_death() -> void:
	# 連續爆炸演出，結束後通知關卡。
	var tween := create_tween()
	for i in 6:
		tween.tween_callback(_death_blast)
		tween.tween_interval(0.22)
	tween.tween_callback(_finish_death)


func _death_blast() -> void:
	var offset := Vector2(randf_range(-1.0, 1.0) * data.body_size.x * 0.6, -randf() * data.body_size.y)
	Fx.explosion(global_position + offset, 26.0, 0, Combat.Team.PLAYER, &"", Palette.WARNING)


func _finish_death() -> void:
	Fx.flash_light(_center(), Palette.WHITE, 260.0, 3.0, 0.8)
	Fx.burst(_center(), Palette.CYAN, 48, 320.0, 0.8)
	Feel.play(&"boss_death")
	EventBus.boss_defeated.emit()
	queue_free()


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

## 核心外露時在胸口畫出脈動的弱點光環（骨架外觀時使用）。
func _draw_overlay() -> void:
	if rig == null:
		return
	var core := _core_point()
	if fsm.is_in(&"core_windup"):
		# 預兆：從核心朝玩家的瞄準線，越接近發射越亮。
		var t := 1.0 - clampf(_telegraph_left / maxf(0.01, data.telegraph_time * 0.8), 0.0, 1.0)
		var color := LightKit.glow(Palette.CYAN, 1.0 + 1.5 * t)
		color.a = 0.25 + 0.55 * t
		draw_line(core, core + _direction_to_target() * 220.0, color, 1.0)
	if fsm.is_in(&"core_windup") or fsm.is_in(&"core_recover"):
		var glow := 0.5 + 0.5 * sin(_anim_time * 24.0)
		draw_circle(core, 5.0 + glow * 2.0, Color(LightKit.glow(Palette.CYAN, 3.0), 0.5))
		draw_arc(core, 8.0 + glow * 2.0, 0.0, TAU, 20, LightKit.glow(Palette.CYAN, 3.0), 1.5)
	if _vulnerable_left <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(_anim_time * 20.0)
	draw_circle(core, 7.0 + pulse * 2.0, Color(LightKit.glow(Palette.CYAN, 2.5), 0.35))
	draw_arc(core, 10.0 + pulse * 3.0, 0.0, TAU, 24, LightKit.glow(Palette.CYAN, 3.0), 2.0)


func _draw_body(color: Color) -> void:
	var w := data.body_size.x
	var h := data.body_size.y
	var f := float(facing)
	var body_color := color if _phase == 1 else color.lerp(Palette.DANGER, 0.35)
	var crouch := 6.0 if fsm.is_in(&"leap_windup") else 0.0
	# 腿
	draw_line(Vector2(-w * 0.3, -h * 0.35 + crouch), Vector2(-w * 0.35, 0), body_color.darkened(0.45), 5.0)
	draw_line(Vector2(w * 0.3, -h * 0.35 + crouch), Vector2(w * 0.35, 0), body_color.darkened(0.45), 5.0)
	# 軀幹與肩甲
	draw_rect(Rect2(-w * 0.5, -h + crouch, w, h * 0.65), body_color)
	draw_rect(Rect2(-w * 0.65, -h + crouch, w * 0.3, h * 0.2), body_color.lightened(0.2))
	draw_rect(Rect2(w * 0.35, -h + crouch, w * 0.3, h * 0.2), body_color.lightened(0.2))
	# 雙臂（扇形彈幕預兆時張開）
	var spread := 1.0 if fsm.is_in(&"fan_windup") else 0.0
	for side: float in [-1.0, 1.0]:
		var shoulder := Vector2(side * w * 0.55, -h * 0.75 + crouch)
		draw_line(shoulder, shoulder + Vector2(side * (6.0 + 8.0 * spread), 10.0 - 14.0 * spread), body_color.darkened(0.2), 4.0)
	# 天線（召喚預兆時閃爍）
	var antenna := LightKit.glow(Palette.WARNING, 3.0) if fsm.is_in(&"summon_windup") and int(_anim_time * 16.0) % 2 == 0 else Palette.TERRAIN_TOP
	draw_line(Vector2(0, -h + crouch), Vector2(0, -h - 8 + crouch), Palette.TERRAIN_TOP, 1.5)
	draw_circle(Vector2(0, -h - 8 + crouch), 2.0, antenna)
	# 核心：外露時發出強光
	var core := Vector2(0, -h * 0.62 + crouch)
	var exposed := _vulnerable_left > 0.0
	var core_color := LightKit.glow(Palette.CYAN, 3.0 + sin(_anim_time * 20.0)) if exposed else body_color.darkened(0.5)
	draw_circle(core, w * (0.22 if exposed else 0.15), core_color)
	# 眼睛
	var eye := LightKit.glow(Palette.DANGER, 3.5 if is_telegraphing() else 1.8)
	draw_line(Vector2(f * w * 0.05, -h * 0.85 + crouch), Vector2(f * w * 0.35, -h * 0.85 + crouch), eye, 2.5)
