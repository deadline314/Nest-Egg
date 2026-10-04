class_name Player
extends CharacterBody2D
## 玩家「七號」：移動、跳躍、衝刺、8 方向射擊、近戰／終結技、騎乘載具。
## 所有手感參數集中在 PlayerTuning 資源；原點位於腳底。

enum State { NORMAL, DASH, FINISHER, MOUNTED, STAGGERED, DEAD, PHONE }
## 在電話亭撥號備份的整段動作時間（秒），與專屬動作 rin.phone_call 的長度一致。
const PHONE_DURATION := 1.1
## 角色聲音設定（data/audio/character_sounds.json）裡玩家的 id。
const PLAYER_SOUND_ID := &"player"
## 腳步：每走多少像素一步、低於多慢不算走路、音量範圍（dB）與蹲著再減多少。
const STEP_DISTANCE := 24.0
const STEP_MIN_SPEED := 30.0
const STEP_QUIET_DB := -24.0
const STEP_LOUD_DB := -14.0
const STEP_CROUCH_DB := -8.0

const BODY_SIZE := Vector2(12, 44)
const CROUCH_HEIGHT := 30.0
## 瞄準基準點（肩膀）的高度：站姿／蹲姿。
## 外觀載入失敗時才用的後備值；平常肩膀高度由骨架量出（PlayerVisual.shoulder_height）。
const SHOULDER_HEIGHT := 35.0
const CROUCH_SHOULDER_HEIGHT := 27.0
const SAFE_GROUND_DELAY := 0.25
const DROP_THROUGH_TIME := 0.25
const MELEE_VISUAL_TIME := 0.12
## 近戰的衝擊力（重擊，打得普通敵人硬直）與命中時玩家自己的頓幀。
const MELEE_IMPACT := 6.0
## 下車後短暫禁止再次上車（避免同一次按鍵下車又立刻上車）。
const REMOUNT_COOLDOWN := 0.3
## 準星擴散每秒回復量與最大額外散佈角度。
const AIM_BLOOM_RECOVERY := 2.5
const AIM_BLOOM_MAX_DEGREES := 4.0
## 同一接觸攻擊重複格擋時的最短計費間隔。
const CONTACT_BLOCK_INTERVAL := 0.35
## 近戰武器跟著準星揮擊時，離水平方向最多偏幾度（弧度）。
const MELEE_AIM_LIMIT := 1.2

## 彈匣低於這個比例時開火音高降低；空槍連按的最短間隔。
const LOW_AMMO_RATIO := 0.25
const LOW_AMMO_PITCH := 0.88
const DRY_FIRE_INTERVAL := 0.3
## 這次換彈的聲音時間軸（資料見 ReloadCues）；實驗室讀它來標示游標經過的聲音。
var reload_track := ReloadCueTrack.new()
var _dry_fire_left := 0.0
var tuning: PlayerTuning
var health: HealthComponent
var hurtbox: Hurtbox
var loadout := Loadout.new()
## 義體能力（電量、冷卻、效果）。
var cyber: CyberSystem
var consumables := ConsumableBag.new()
var state: State = State.NORMAL
var facing := 1
var aim_dir := Vector2.RIGHT
## 準星所在的世界座標（HUD 準星與動畫用）。
var aim_point := Vector2.ZERO
## 連射造成的準星擴散（0~1），隨時間回復。
var aim_bloom := 0.0
var is_crouching := false
var is_blocking := false
## 護盾能量（格擋消耗、放開後回復）。
var guard := 100.0
var mounted_vehicle: Vehicle
## 低於此高度視為掉入深淵（由關卡設定）。
var fall_limit_y := INF

var _visual: PlayerVisual
var _light: PointLight2D
var _was_on_floor := true
var _fall_speed_before_move := 0.0
var _max_health := 6
var _loadout_snapshot: Dictionary = {}
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _dash_buffer_left := 0.0
var _dash_buffer_x := 0.0
const LATENCY_ACTIONS: Array[StringName] = [&"shoot", &"melee", &"jump", &"dash"]
var _dash_left := 0.0
var _dash_cooldown_left := 0.0
var _air_dash_used := false
var _fire_cooldown_left := 0.0
var _melee_cooldown_left := 0.0
enum MeleePhase { NONE, WINDUP, ACTIVE, RECOVERY }
var _melee_phase := MeleePhase.NONE
var _melee_time := 0.0
var _melee_attack: Dictionary = {}
## 這一段連段用的招式組：沒拿近戰武器是預設近戰，拿著近戰武器是那把武器的組；中途換武器就從第一招重新開始。
var _melee_set: MeleeSet = MeleeData.default_set()
## 這一揮的命中回饋（頓幀、命中聲）是否已經播過；持續判定的招式只在第一個命中時播一次。
var _melee_feedback_done := false
## 被鎖鏈拉扯：拉向哪個節點（弱參照）、速度、剩餘秒數；衝刺、受擊硬直、撞牆或對方消失都會解除。
var _pull_source: WeakRef
var _pull_speed := 0.0
var _pull_left := 0.0
var _step_travel := 0.0
var _terrain: Terrain
var _melee_index := -1
var _melee_landed := false
var _melee_hit_ids: Dictionary = {}
var _melee_buffer_left := 0.0
var _melee_combo_left := 0.0
var _melee_visual_left := 0.0
var _finisher_left := 0.0
var _drop_through_left := 0.0
var _safe_ground_time := 0.0
var _remount_cooldown_left := 0.0
var _dash_dir := 1
var _block_time := 0.0
var _since_block_release := 10.0
var _window_scale := 1.0
static var _block_hint_shown := false
const PARRY_WINDOW_MIN := 0.14
const PARRY_WINDOW_MAX := 0.22
var _guard_regen_delay_left := 0.0
var _guard_lockout_left := 0.0
var _phone_left := 0.0
var _stagger_left := 0.0
var _contact_block_left := 0.0
var _last_health := 0
var _last_safe_position := Vector2.ZERO
var _query_shape := RectangleShape2D.new()
var _query_circle := CircleShape2D.new()


## 加入場景樹前呼叫。
func configure(p_tuning: PlayerTuning, max_health: int, loadout_snapshot: Dictionary) -> void:
	tuning = p_tuning
	_max_health = max_health
	_loadout_snapshot = loadout_snapshot


func _ready() -> void:
	if tuning == null:
		push_warning("[Player] 未指定 PlayerTuning，使用預設值。")
		tuning = PlayerTuning.new()
	add_to_group(&"player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID

	var body := CollisionShape2D.new()
	var body_shape := RectangleShape2D.new()
	body_shape.size = BODY_SIZE
	body.shape = body_shape
	body.position = Vector2(0, -BODY_SIZE.y * 0.5)
	add_child(body)

	health = HealthComponent.new()
	health.setup(_max_health, tuning.hurt_invulnerability)
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)

	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.PLAYER, health, Vector2.ZERO)
	hurtbox.guard = _guard
	_update_hurtbox_shape()
	guard = tuning.guard_max

	_visual = PlayerVisual.new()
	_visual.player = self
	add_child(_visual)
	_last_health = health.current

	# 角色自帶柔光（含陰影），在暗處維持可讀性。
	_light = LightKit.create_point_light(Palette.CYAN, 150.0, 0.75, true, false)
	_light.position = Vector2(0, -30)
	add_child(_light)

	loadout.changed.connect(_on_loadout_changed)
	loadout.reload_started.connect(func() -> void:
		var weapon := loadout.active_weapon()
		reload_track.begin(weapon.id if weapon != null else &""))
	loadout.reload_cancelled.connect(reload_track.cancel)
	loadout.weapon_switched.connect(func() -> void: WeaponSounds.play(loadout.active_weapon(), &"equip", -6.0))
	loadout.reload_finished.connect(_on_reload_finished)
	loadout.restore(_loadout_snapshot, tuning.default_weapon)
	cyber = CyberSystem.new()
	cyber.player = self
	add_child(cyber)
	# 武器改裝後重新計算實際數值；離開場景時解除（武器欄是 RefCounted，不解除會一直被單例持有）。
	Progression.upgrades_changed.connect(loadout.retune)
	tree_exiting.connect(func() -> void:
		if Progression.upgrades_changed.is_connected(loadout.retune):
			Progression.upgrades_changed.disconnect(loadout.retune))
	consumables.changed.connect(func() -> void: EventBus.player_consumables_changed.emit(consumables))
	consumables.restore(_loadout_snapshot.get("consumables", {}))
	_last_safe_position = global_position
	EventBus.player_spawned.emit(self)
	_on_health_changed(health.current, health.max_health)
	_emit_guard()


func is_targetable() -> bool:
	return state != State.DEAD


func is_dead() -> bool:
	return state == State.DEAD


## 瞄準的基準點（肩膀高度）。
func aim_origin() -> Vector2:
	var fallback := CROUCH_SHOULDER_HEIGHT if is_crouching else SHOULDER_HEIGHT
	var height := _visual.shoulder_height(is_crouching, fallback) if _visual != null else fallback
	return global_position + Vector2(0, -height)


## 子彈從手上武器的槍口射出（與畫面上的槍管一致）。
func muzzle_position() -> Vector2:
	return _visual.muzzle_global() if _visual != null else aim_origin() + aim_dir * 12.0


# ---------------------------------------------------------------------------
# 主迴圈
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	AimInput.observe(event)
	# 輸入延遲量測：記下按下的時間，效果發生時再結算。
	for action: StringName in LATENCY_ACTIONS:
		if event.is_action_pressed(action):
			InputFeel.mark(action)


## 換武器用事件處理：滾輪的按下與放開發生在同一影格，用輪詢會漏掉。
func _unhandled_input(event: InputEvent) -> void:
	if state == State.DEAD or state == State.MOUNTED:
		return
	if event.is_action_pressed(&"weapon_next"):
		loadout.cycle(1)
	elif event.is_action_pressed(&"weapon_prev"):
		loadout.cycle(-1)
	elif event.is_action_pressed(&"reload"):
		loadout.start_reload()
	elif event.is_action_pressed(&"ability"):
		if not cyber.try_activate():
			EventBus.toast_requested.emit(cyber.block_reason())
	elif event.is_action_pressed(&"use_item"):
		var quick := consumables.quick_use_item()
		if quick != null and not use_consumable(quick.id):
			EventBus.toast_requested.emit("沒有%s" % quick.display_name if consumables.count(quick.id) <= 0 else "生命已滿")
	else:
		for slot in Loadout.MAX_SLOTS:
			if event.is_action_pressed(StringName("weapon_slot_%d" % (slot + 1))):
				loadout.select(slot)
				break


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_update_aim(delta)
	match state:
		State.MOUNTED:
			_process_mounted()
			return
		State.FINISHER:
			_process_finisher(delta)
			return
		State.PHONE:
			_process_phone(delta)
			return
		State.STAGGERED:
			_stagger_left -= delta
			velocity.x = move_toward(velocity.x, 0.0, tuning.ground_deceleration * delta)
			_apply_gravity(delta)
			move_and_slide()
			if _stagger_left <= 0.0:
				state = State.NORMAL
			return
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, tuning.ground_deceleration * delta)
			_apply_gravity(delta)
			move_and_slide()
			return
		State.DASH:
			_process_dash(delta)
		State.NORMAL:
			_process_normal(delta)
	_fall_speed_before_move = velocity.y
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return  # 這一步中途被頓幀停用（受擊回饋凍結攻擊方）：這影格不再移動
	_apply_corner_correction(delta)
	move_and_slide()
	_after_move(delta)


func _tick_timers(delta: float) -> void:
	_coyote_left = maxf(0.0, _coyote_left - delta)
	_dash_buffer_left = maxf(0.0, _dash_buffer_left - delta)
	if _dash_buffer_left > 0.0 and _dash_cooldown_left <= 0.0 and not is_melee_locked() and (is_on_floor() or not _air_dash_used):
		_dash_buffer_left = 0.0
		_try_dash(_dash_buffer_x)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	_fire_cooldown_left = maxf(0.0, _fire_cooldown_left - delta)
	_melee_cooldown_left = maxf(0.0, _melee_cooldown_left - delta)
	_tick_melee(delta)
	_tick_pull(delta)
	_melee_visual_left = maxf(0.0, _melee_visual_left - delta)
	_remount_cooldown_left = maxf(0.0, _remount_cooldown_left - delta)
	aim_bloom = move_toward(aim_bloom, 0.0, AIM_BLOOM_RECOVERY * delta)
	_dry_fire_left = maxf(0.0, _dry_fire_left - delta)
	if state != State.DEAD and state != State.MOUNTED:
		loadout.tick(delta * cyber.reload_speed_scale())
		if loadout.is_reloading():
			reload_track.advance(loadout.reload_progress())
		elif reload_track.is_active():
			reload_track.cancel()
	_tick_guard(delta)
	if _drop_through_left > 0.0:
		_drop_through_left -= delta
		if _drop_through_left <= 0.0 and state != State.MOUNTED and state != State.DEAD:
			collision_mask |= Layers.PLATFORM


func _process_normal(delta: float) -> void:
	var input_x := Input.get_axis(&"move_left", &"move_right")
	var down := Input.is_action_pressed(&"move_down")
	var on_floor := is_on_floor()

	_update_blocking()
	var was_crouching := is_crouching
	is_crouching = on_floor and down and not is_blocking
	if was_crouching != is_crouching:
		_update_hurtbox_shape()

	var target_speed := 0.0
	if not is_crouching:
		target_speed = input_x * tuning.run_speed * cyber.move_speed_scale() * melee_move_scale()
		# 背對準星移動（倒退）時稍慢，維持射擊時的控制感。
		if signf(input_x) != 0.0 and signf(input_x) != float(facing):
			target_speed *= tuning.backpedal_multiplier
		if is_blocking:
			target_speed *= tuning.block_speed_multiplier
	var accel: float
	if absf(target_speed) > 1.0:
		accel = tuning.ground_acceleration if on_floor else tuning.air_acceleration
	else:
		accel = tuning.ground_deceleration if on_floor else tuning.air_deceleration
	velocity.x = move_toward(velocity.x, target_speed, accel * delta)
	var pulled_x := _pull_velocity_x()
	if not is_nan(pulled_x):
		velocity.x = pulled_x

	if on_floor:
		_coyote_left = InputFeel.window("coyote", tuning.coyote_time)
		_air_dash_used = false
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_left = InputFeel.window("jump_buffer", tuning.jump_buffer)
	if _jump_buffer_left > 0.0:
		if on_floor and down and _is_standing_on_platform():
			_start_drop_through()
			_jump_buffer_left = 0.0
		elif _coyote_left > 0.0:
			velocity.y = -tuning.jump_velocity
			_coyote_left = 0.0
			_jump_buffer_left = 0.0
			_visual.notify_jump()
			Fx.dust(global_position, 4, 40.0)
			Sfx.play(&"jump", -8.0)
			InputFeel.resolve(&"jump")
	if Input.is_action_just_released(&"jump") and velocity.y < 0.0:
		velocity.y *= tuning.jump_cut
	_apply_gravity(delta)

	if Input.is_action_just_pressed(&"interact") and _try_mount():
		return
	if Input.is_action_just_pressed(&"melee") and _try_melee():
		return
	if Input.is_action_just_pressed(&"dash"):
		_try_dash(input_x)
	if Input.is_action_pressed(&"shoot") and not is_blocking:
		if holds_melee_weapon():
			# 近戰武器：按住射擊鍵＝連續揮擊；出招中按下會緩衝，收招結束接下一段。
			if Input.is_action_just_pressed(&"shoot") or _melee_phase == MeleePhase.NONE:
				_try_melee()
		elif not is_melee_locked():
			_try_fire()


func _after_move(delta: float) -> void:
	if global_position.y > fall_limit_y:
		_handle_pit()
		return
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and _fall_speed_before_move > 140.0:
		var impact := clampf(_fall_speed_before_move / tuning.max_fall_speed, 0.0, 1.0)
		_visual.notify_land(impact)
		Fx.dust(global_position, 3 + int(impact * 5.0), 60.0)
		Footsteps.play(_ground_surface(), &"land", lerpf(-16.0, -6.0, impact))
	_was_on_floor = on_floor
	_tick_footsteps(delta)
	if state == State.NORMAL and is_on_floor() and not health.is_invulnerable():
		_safe_ground_time += delta
		if _safe_ground_time >= SAFE_GROUND_DELAY:
			_last_safe_position = global_position
	else:
		_safe_ground_time = 0.0


## 腳步聲：站在地上走動時，每走 STEP_DISTANCE 像素一步，音量隨速度、蹲著更輕；停下、在空中、騎載具或被打斷時重新計步。
func _tick_footsteps(delta: float) -> void:
	var speed := absf(velocity.x)
	if state != State.NORMAL or not is_on_floor() or speed < STEP_MIN_SPEED:
		_step_travel = 0.0
		return
	_step_travel += speed * delta
	if _step_travel < STEP_DISTANCE:
		return
	_step_travel -= STEP_DISTANCE
	var loudness := clampf(speed / maxf(1.0, tuning.run_speed), 0.0, 1.0)
	var volume := lerpf(STEP_QUIET_DB, STEP_LOUD_DB, loudness) + (STEP_CROUCH_DB if is_crouching else 0.0)
	Footsteps.play(_ground_surface(), &"step", volume)


## 腳下的地面種類（金屬、混凝土、潮濕…）；找不到地形時用預設。
## 實驗室與測試用：指定腳下的地面種類（空字串 = 照真實地形）。
var surface_override: StringName = &""


func _ground_surface() -> StringName:
	if surface_override != &"":
		return surface_override
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group(&"terrain") as Terrain
	var material: StringName = _terrain.material_id_at(global_position + Vector2(0.0, 4.0)) if _terrain != null else &""
	return Footsteps.surface_for_material(material)


func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y >= 0.0:
		return
	var multiplier := tuning.fall_gravity_multiplier if velocity.y > 0.0 else 1.0
	if absf(velocity.y) < tuning.apex_speed_threshold and Input.is_action_pressed(&"jump") and state == State.NORMAL:
		multiplier = tuning.apex_gravity_multiplier
	velocity.y = minf(velocity.y + tuning.gravity * multiplier * delta, tuning.max_fall_speed)


## 上升時若只差幾像素撞到天花板邊角，自動側移讓玩家順利通過。
func _apply_corner_correction(delta: float) -> void:
	if velocity.y >= 0.0 or tuning.corner_correction <= 0:
		return
	var motion := Vector2(0.0, velocity.y * delta)
	if not test_move(global_transform, motion):
		return
	for offset in range(1, tuning.corner_correction + 1):
		for side: int in [1, -1]:
			var shifted := global_transform.translated(Vector2(offset * side, 0.0))
			if not test_move(global_transform, Vector2(offset * side, 0.0)) and not test_move(shifted, motion):
				global_position.x += offset * side
				return


## 滑鼠／右搖桿 360° 瞄準；角色永遠面向準星。
func _update_aim(_delta: float) -> void:
	if state == State.DEAD:
		return
	var origin := aim_origin()
	aim_dir = AimInput.direction_from(self, origin, aim_dir)
	aim_point = AimInput.target_point(self, origin, aim_dir)
	if absf(aim_dir.x) > 0.05 and state != State.DASH and state != State.MOUNTED and state != State.PHONE:
		facing = 1 if aim_dir.x > 0.0 else -1


func _update_hurtbox_shape() -> void:
	var height := CROUCH_HEIGHT if is_crouching else BODY_SIZE.y
	hurtbox.resize(Vector2(BODY_SIZE.x * 0.8, height * 0.9), Vector2(0, -height * 0.5))


# ---------------------------------------------------------------------------
# 動作
# ---------------------------------------------------------------------------

## 空槍：喀一聲、準星抖一下，連按有節流。
func _dry_fire() -> void:
	if _dry_fire_left > 0.0:
		return
	_dry_fire_left = DRY_FIRE_INTERVAL
	WeaponSounds.play(loadout.active_weapon(), &"empty", -4.0)
	aim_bloom = minf(1.0, aim_bloom + 0.2)
	EventBus.dry_fired.emit()


## 換彈完成：槍口一個小閃光與準星提示（取消換彈時不會走到這裡）。
func _on_reload_finished() -> void:
	var weapon := loadout.active_weapon()
	reload_track.finish()
	if weapon != null:
		Fx.flare(muzzle_position(), weapon.color, 18.0, 0.08)
	EventBus.reload_completed.emit()


## 彈匣剩不到四分之一（還沒空）：開火聲音音高降低，提醒快沒子彈。
func _is_low_ammo(weapon: WeaponData) -> bool:
	if not weapon.has_magazine():
		return false
	var mag := loadout.mag_in(loadout.active_slot)
	return mag > 0 and float(mag) / float(weapon.magazine_size) <= LOW_AMMO_RATIO


func _try_fire() -> void:
	if _fire_cooldown_left > 0.0:
		return
	var weapon := loadout.active_weapon()
	if weapon == null or not weapon.is_valid() or weapon.is_melee():
		return
	var dry := loadout.is_dry() and loadout.reserve_in(loadout.active_slot) == 0
	if not loadout.consume_ammo():
		if dry:
			_dry_fire()
		return
	_fire_cooldown_left = weapon.fire_interval / cyber.fire_rate_scale()
	InputFeel.resolve(&"shoot")
	var muzzle := muzzle_position()
	WeaponSystem.fire(weapon, muzzle, aim_dir, Combat.Team.PLAYER, 1.0, aim_bloom * AIM_BLOOM_MAX_DEGREES)
	aim_bloom = minf(1.0, aim_bloom + weapon.bloom_per_shot)
	# 射擊手感：槍口閃光 + 光源 + 鏡頭反向後座 + 彈殼 + 音效。
	WeaponSystem.muzzle_feedback(weapon, muzzle, aim_dir)
	if weapon.ejects_casing:
		Fx.casing(aim_origin(), facing)
	Sfx.play(weapon.fire_sound, -6.0, 0.06, 0, LOW_AMMO_PITCH if _is_low_ammo(weapon) else 1.0)
	if weapon.recoil > 0.0:
		velocity -= aim_dir * weapon.recoil * (1.0 if not is_on_floor() else 0.3)
	_visual.notify_fired(weapon.color)


func _try_dash(input_x: float) -> void:
	if _dash_cooldown_left > 0.0 or (not is_on_floor() and _air_dash_used) or is_melee_locked():
		# 提前按：冷卻或收招結束的瞬間自動衝刺。
		_dash_buffer_left = InputFeel.window("dash_buffer", 0.12)
		_dash_buffer_x = input_x
		return
	InputFeel.resolve(&"dash")
	end_pull()  # 衝刺能掙脫鎖鏈
	if _melee_phase != MeleePhase.NONE:
		_end_melee()
	loadout.cancel_reload()
	# 衝刺方向以移動輸入為準（可往後閃），沒有輸入時朝面向。
	_dash_dir = (1 if input_x > 0.0 else -1) if absf(input_x) > 0.2 else facing
	if not is_on_floor():
		_air_dash_used = true
	state = State.DASH
	_dash_left = tuning.dash_time
	velocity = Vector2(_dash_dir * tuning.dash_speed, 0.0)
	health.grant_invulnerability(tuning.dash_time + 0.05)
	_visual.notify_dash()
	Fx.dust(global_position, 4, 30.0)
	Sfx.play(&"dash", -8.0)
	if is_crouching:
		is_crouching = false
		_update_hurtbox_shape()


func _process_dash(delta: float) -> void:
	_dash_left -= delta
	velocity.y = 0.0
	if Input.is_action_pressed(&"shoot"):
		_try_fire()
	if _dash_left <= 0.0 or is_on_wall():
		state = State.NORMAL
		_dash_cooldown_left = tuning.dash_cooldown
		velocity.x *= 0.5


## 開始被拉向 source（鎖鏈鐵鉤）：每影格往它的方向以 speed 移動，最多 seconds 秒；碰到牆就停，不會被拖進牆裡。
func begin_pull(source: Node2D, speed: float, seconds: float) -> void:
	_pull_source = weakref(source)
	_pull_speed = speed
	_pull_left = seconds


func end_pull() -> void:
	_pull_left = 0.0
	_pull_source = null


func is_pulled() -> bool:
	return _pull_left > 0.0


## 拉扯中的水平速度；沒有被拉時回傳 NAN。
func _pull_velocity_x() -> float:
	if _pull_left <= 0.0 or _pull_source == null:
		return NAN
	var source := _pull_source.get_ref() as Node2D
	if source == null:
		return NAN
	return signf(source.global_position.x - global_position.x) * _pull_speed


func _tick_pull(delta: float) -> void:
	if _pull_left <= 0.0:
		return
	var source := _pull_source.get_ref() as Node2D if _pull_source != null else null
	if source == null or state != State.NORMAL or is_on_wall():
		end_pull()
		return
	_pull_left -= delta
	if _pull_left <= 0.0:
		end_pull()


## 手上武器在骨架上的貼圖 id：近戰武器是程式繪製的（PlayerVisual），骨架手上不放貼圖。
func _visual_id_of(weapon: WeaponData) -> String:
	return "" if weapon == null or weapon.is_melee() else weapon.visual_id


## 手上是不是近戰武器（近戰武器用射擊鍵與近戰鍵揮擊，不發射子彈）。
func holds_melee_weapon() -> bool:
	var weapon := loadout.active_weapon()
	return weapon != null and weapon.is_melee()


## 近戰鍵：附近有破防敵人時發動終結技，否則進入連段斬擊（前搖、出招、收招；預設連段輕、輕、重，近戰武器用自己的連段）。
## 出招中再按會緩衝，收招可取消的時間點到了就接下一段。回傳是否吃掉這次按鍵。
func _try_melee() -> bool:
	if _melee_phase != MeleePhase.NONE:
		_melee_buffer_left = MeleeData.buffer_time()
		return true
	if _melee_cooldown_left > 0.0:
		return false
	var armed := holds_melee_weapon()
	if not armed:
		loadout.cancel_reload()  # 近戰武器的「換彈」是充電，揮擊不取消它
	var target := _find_finisher_target()
	if target != null:
		_start_finisher(target)
		return true
	_start_melee_attack(_melee_combo_left > 0.0)
	return true


## 開始一段揮擊；近戰武器每揮消耗電量，電量不足（充電中）揮不出去並回傳 false。
func _start_melee_attack(continue_combo: bool) -> bool:
	var weapon := loadout.active_weapon()
	var set := MeleeData.set_of(weapon)
	if weapon != null and weapon.is_melee() and not _spend_melee_charge(weapon):
		return false
	InputFeel.resolve(&"melee")
	if set != _melee_set:
		_melee_set = set
		continue_combo = false
	var combo := set.combo()
	_melee_index = (_melee_index + 1) % combo.size() if continue_combo and _melee_index >= 0 else 0
	_melee_attack = set.attack(str(combo[_melee_index]))
	_melee_phase = MeleePhase.WINDUP
	_melee_time = 0.0
	_melee_landed = false
	_melee_feedback_done = false
	_melee_hit_ids.clear()
	_melee_buffer_left = 0.0
	_melee_combo_left = 0.0
	_melee_visual_left = float(_melee_attack["windup"]) + float(_melee_attack["active"]) + 0.04
	return true


## 近戰武器的電量（沿用彈匣）：沒有電量限制的武器直接通過；電量不足時喀一聲、不揮擊。
func _spend_melee_charge(weapon: WeaponData) -> bool:
	if not weapon.has_magazine() or loadout.consume_ammo():
		return true
	_dry_fire()
	return false


## 每個物理影格推進近戰三段。
func _tick_melee(delta: float) -> void:
	if _melee_phase == MeleePhase.NONE:
		_melee_buffer_left = maxf(0.0, _melee_buffer_left - delta)
		_melee_combo_left = maxf(0.0, _melee_combo_left - delta)
		if _melee_combo_left <= 0.0:
			_melee_index = -1
		return
	if state == State.DEAD or state == State.FINISHER or state == State.STAGGERED or state == State.MOUNTED:
		_end_melee()
		return
	_melee_time += delta
	_melee_buffer_left = maxf(0.0, _melee_buffer_left - delta)
	match _melee_phase:
		MeleePhase.WINDUP:
			if _melee_time >= float(_melee_attack["windup"]):
				_melee_phase = MeleePhase.ACTIVE
				_melee_time = 0.0
				_melee_strike()
		MeleePhase.ACTIVE:
			if bool(_melee_attack["sweep"]):
				_melee_hit_pass()
			if _melee_time >= float(_melee_attack["active"]):
				_melee_phase = MeleePhase.RECOVERY
				_melee_time = 0.0
		MeleePhase.RECOVERY:
			if _melee_buffer_left > 0.0 and is_melee_cancellable():
				if not _start_melee_attack(true):
					_end_melee()
			elif _melee_time >= float(_melee_attack["recovery"]):
				_end_melee()


## 命中後收招只要等 cancel_after 秒就能取消（接下一招、衝刺、射擊）；揮空要吃滿收招。
func is_melee_cancellable() -> bool:
	if _melee_phase == MeleePhase.NONE:
		return true
	return _melee_phase == MeleePhase.RECOVERY and _melee_landed and _melee_time >= float(_melee_attack["cancel_after"])


func is_melee_locked() -> bool:
	return not is_melee_cancellable()


## 近戰期間的移動倍率（前搖與收招比較慢，出招時往前衝）。
func melee_move_scale() -> float:
	return 1.0 if _melee_phase == MeleePhase.NONE else float(_melee_attack["move_scale"])


func _end_melee() -> void:
	var was_active := _melee_phase != MeleePhase.NONE
	_melee_phase = MeleePhase.NONE
	_melee_visual_left = 0.0
	if was_active:
		_melee_combo_left = _melee_set.combo_window() if _melee_landed or _melee_buffer_left > 0.0 else _melee_set.combo_window() * 0.5
		_melee_cooldown_left = 0.0


## 出招的瞬間：往前衝、判定一次；同一揮對同一目標只命中一次。有 sweep 的招式在出招區間內每個影格再判定。
func _melee_strike() -> void:
	var attack := _melee_attack
	velocity.x += float(facing) * float(attack["advance"])
	if _visual != null:
		_visual.notify_melee_swing(attack.get("trail", {}), facing, _melee_direction(attack))
	_melee_hit_pass()
	if not _melee_landed:
		var heavy := int(attack["stagger"]) >= 3
		Sfx.play_named(StringName(str(_melee_sounds(attack)["swing"])), -10.0 if not heavy else -6.0)


## 揮擊的方向：預設朝面向水平揮；aim_follow 的招式（長柄的刺擊、鞭）跟著準星，但限制在水平上下約 70 度內。
func _melee_direction(attack: Dictionary) -> Vector2:
	if not bool(attack["aim_follow"]):
		return Vector2(facing, 0.0)
	var angle := clampf(Vector2(aim_dir.x * facing, aim_dir.y).angle(), -MELEE_AIM_LIMIT, MELEE_AIM_LIMIT)
	return Vector2(cos(angle) * facing, sin(angle))


## 這一瞬間判定範圍內、還沒被這一揮打過的目標；命中時給傷害、衝擊與回饋。
func _melee_hit_pass() -> void:
	var attack := _melee_attack
	var knock: Array = attack["knockback"]
	var heavy := int(attack["stagger"]) >= 3
	var landed_now := false
	for target_hurtbox in _melee_targets(attack):
		var id := target_hurtbox.health.get_instance_id() if target_hurtbox.health != null else target_hurtbox.get_instance_id()
		if _melee_hit_ids.has(id):
			continue
		var info := DamageInfo.create(int(attack["damage"]), Combat.Team.PLAYER, &"melee", Vector2(facing * float(knock[0]), float(knock[1])))
		info.stagger = int(attack["stagger"])
		info.impact = float(attack["impact"])
		info.attacker = weakref(self)
		info.origin = global_position
		if target_hurtbox.receive(info) != Hurtbox.Result.IGNORED:
			_melee_hit_ids[id] = true
			_melee_landed = true
			landed_now = true
			EventBus.hit_confirmed.emit(target_hurtbox.global_position, target_hurtbox.health.is_dead)
			EventBus.hit_marker.emit(&"kill" if target_hurtbox.health.is_dead else (&"weak" if info.weak_hit else &"hit"))
			if info.weak_hit or int(attack["stagger"]) >= 3:
				EventBus.damage_number.emit(target_hurtbox.global_position + Vector2(0.0, -24.0), info.amount, &"weak" if info.weak_hit else &"crit", target_hurtbox.health.get_instance_id())
			Fx.burst(target_hurtbox.global_position, Palette.CYAN, 9 if heavy else 6, 120.0, 0.2)
			HitFeedback.play(target_hurtbox.material_id(), target_hurtbox.global_position, Vector2(-facing, -0.2), Palette.CYAN, {"weak": info.weak_hit})
	if landed_now and not _melee_feedback_done:
		_melee_feedback_done = true
		# 延後到物理步驟之後：頓幀會停用自己，不能在自己的物理處理中途做。被打到的敵人在 Enemy 裡依受擊層級自己凍結。
		var ctx := {"targets": [self], "dir": aim_dir, "origin": global_position}
		if float(attack["hitstop"]) > 0.0:
			ctx["freeze"] = float(attack["hitstop"])
		Feel.play.call_deferred(StringName(str(attack["event"])), ctx)
		Sfx.play_named(StringName(str(_melee_sounds(attack)["hit"])), -3.0 if not heavy else 0.0)


## 這一招判定範圍裡的受擊框：box 是面前的矩形（可朝準星旋轉），arc 是以身體為圓心的扇形；min_range 內是死角打不到。
func _melee_targets(attack: Dictionary) -> Array[Hurtbox]:
	var reach := float(attack["range"])
	var dir := _melee_direction(attack)
	var origin := global_position + Vector2(0.0, -BODY_SIZE.y * 0.55)
	var candidates: Array[Hurtbox]
	var half := PI
	if str(attack["shape"]) == "arc":
		candidates = _query_hurtboxes(origin, Vector2.ZERO, 0.0, reach)
		half = deg_to_rad(float(attack["arc_degrees"])) * 0.5
	else:
		var height := float(attack["height"]) if float(attack["height"]) > 0.0 else BODY_SIZE.y
		candidates = _query_hurtboxes(origin + dir * reach * 0.5, Vector2(reach, height), dir.angle() if bool(attack["aim_follow"]) else 0.0)
	var min_range := float(attack["min_range"])
	if min_range <= 0.0 and half >= PI - 0.01:
		return candidates
	var result: Array[Hurtbox] = []
	for target in candidates:
		var offset := target.center() - origin
		if offset.length() >= min_range and absf(dir.angle_to(offset)) <= half:
			result.append(target)
	return result


## 目前這一招的動作進度 0~1（前搖 0~0.4、出招 0.4~0.7、收招 0.7~1），不在近戰中回傳 -1；角色揮砍動作依它播放。
func melee_pose_progress() -> float:
	var attack := _melee_attack
	match _melee_phase:
		MeleePhase.WINDUP:
			return clampf(_melee_time / maxf(0.001, float(attack["windup"])), 0.0, 1.0) * 0.4
		MeleePhase.ACTIVE:
			return 0.4 + clampf(_melee_time / maxf(0.001, float(attack["active"])), 0.0, 1.0) * 0.3
		MeleePhase.RECOVERY:
			return 0.7 + clampf(_melee_time / maxf(0.001, float(attack["recovery"])), 0.0, 1.0) * 0.3
	return -1.0


## 目前這一招的動作名稱（資料的 pose：slash 斜斬、overhead 劈砍、thrust 刺擊、sweep 橫掃）。
func melee_pose() -> String:
	return str(_melee_attack.get("pose", "slash")) if _melee_phase != MeleePhase.NONE else ""


## 這一招的出手聲與命中聲（資料缺漏時用內建預設）。
func _melee_sounds(attack: Dictionary) -> Dictionary:
	var sounds: Variant = attack.get("sounds")
	var result := {"swing": "melee_swing", "hit": "melee_hit"}
	if typeof(sounds) == TYPE_DICTIONARY:
		result.merge(sounds as Dictionary, true)
	return result


func _find_finisher_target() -> Enemy:
	var best: Enemy = null
	var best_distance := tuning.finisher_range
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or not enemy.can_be_finished():
			continue
		var distance := enemy.global_position.distance_to(global_position)
		if distance <= best_distance:
			best = enemy
			best_distance = distance
	return best


func _start_finisher(target: Enemy) -> void:
	state = State.FINISHER
	_finisher_left = tuning.finisher_duration
	_melee_cooldown_left = tuning.melee_cooldown
	health.grant_invulnerability(tuning.finisher_duration + 0.3)
	velocity = Vector2.ZERO
	facing = 1 if target.global_position.x >= global_position.x else -1
	# 瞬移到目標身旁；被牆擋住就留在原地。
	var destination := target.global_position + Vector2(-facing * 14.0, 0.0)
	if not test_move(global_transform, destination - global_position):
		global_position = destination
	target.execute_finisher()
	_visual.notify_finisher()
	Feel.play(&"player_finisher", {"targets": [self, target], "freeze": tuning.finisher_hitstop})
	Fx.flash_light(target.global_position + Vector2(0, -10), Palette.CYAN, 120.0, 2.5, 0.3)
	Sfx.play(&"finisher")
	loadout.refill_ratio(tuning.finisher_ammo_refund)


## 開始在電話亭撥號：站定、面向亭子、收起武器拿話筒；期間不會被打斷（短暫無敵）。不能開始時回傳 false。
func begin_phone_call(face: int) -> bool:
	if state != State.NORMAL or is_dead() or not is_on_floor():
		return false
	state = State.PHONE
	_phone_left = PHONE_DURATION
	velocity = Vector2.ZERO
	facing = face
	is_crouching = false
	is_blocking = false
	health.grant_invulnerability(PHONE_DURATION + 0.15)
	_visual.begin_phone()
	return true


func is_on_phone() -> bool:
	return state == State.PHONE


## 撥號動作的進度 0~1（不在撥號時回傳 1）。電話亭的聲音與備份都跟著這條進度走，幀率再低也不會錯開。
func phone_progress() -> float:
	return clampf(1.0 - _phone_left / PHONE_DURATION, 0.0, 1.0) if state == State.PHONE else 1.0


func _process_phone(delta: float) -> void:
	_phone_left -= delta
	velocity.x = 0.0
	_apply_gravity(delta)
	move_and_slide()
	if _phone_left <= 0.0:
		state = State.NORMAL
		var weapon := loadout.active_weapon()
		_visual.end_phone(_visual_id_of(weapon))


func _process_finisher(delta: float) -> void:
	_finisher_left -= delta
	velocity = Vector2.ZERO
	if _finisher_left <= 0.0:
		state = State.NORMAL


## 範圍內的敵方受擊框（整體，不分部位）：radius > 0 用圓形，否則用 size 的矩形（可旋轉）。
func _query_hurtboxes(center: Vector2, size: Vector2, rotation := 0.0, radius := 0.0) -> Array[Hurtbox]:
	var result: Array[Hurtbox] = []
	var params := PhysicsShapeQueryParameters2D.new()
	if radius > 0.0:
		_query_circle.radius = radius
		params.shape = _query_circle
	else:
		_query_shape.size = size
		params.shape = _query_shape
	params.transform = Transform2D(rotation, center)
	params.collision_mask = Layers.ENEMY_HURTBOX
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 16):
		var found := hit.get("collider") as Hurtbox
		found = found.root() if found != null else null  # 近戰打整體，不分部位
		if found != null and not result.has(found):
			result.append(found)
	return result


func _is_standing_on_platform() -> bool:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider() as CollisionObject2D
		if collider != null and collision.get_normal().y < -0.5 and (collider.collision_layer & Layers.PLATFORM) != 0:
			return true
	return false


func _start_drop_through() -> void:
	collision_mask &= ~Layers.PLATFORM
	_drop_through_left = DROP_THROUGH_TIME
	position.y += 2.0


func _handle_pit() -> void:
	var info := DamageInfo.create(tuning.pit_damage, Combat.Team.ENEMY, &"pit")
	info.ignore_invulnerability = true
	info.origin = global_position
	health.take_damage(info)
	if state != State.DEAD:
		global_position = _last_safe_position
		velocity = Vector2.ZERO
		health.grant_invulnerability(tuning.hurt_invulnerability)


# ---------------------------------------------------------------------------
# 載具
# ---------------------------------------------------------------------------

func _try_mount() -> bool:
	if _remount_cooldown_left > 0.0:
		return false
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var vehicle := node as Vehicle
		if vehicle != null and vehicle.can_mount() and vehicle.global_position.distance_to(global_position) <= tuning.mount_range:
			mount_vehicle(vehicle)
			return true
	return false


func mount_vehicle(vehicle: Vehicle) -> void:
	if vehicle == null or state == State.DEAD:
		return
	state = State.MOUNTED
	mounted_vehicle = vehicle
	velocity = Vector2.ZERO
	is_crouching = false
	collision_layer = 0
	collision_mask = 0
	hurtbox.enabled = false
	_visual.visible = false
	vehicle.mount(self)


## 離開載具。ejected = true 代表載具被擊毀而彈出，會給予無敵時間。
func dismount_vehicle(ejected: bool) -> void:
	if state != State.MOUNTED:
		return
	var vehicle := mounted_vehicle
	mounted_vehicle = null
	if is_instance_valid(vehicle):
		vehicle.release_driver()
		global_position = vehicle.global_position
	state = State.NORMAL
	_remount_cooldown_left = REMOUNT_COOLDOWN
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID
	hurtbox.enabled = true
	_visual.visible = true
	velocity = Vector2(-facing * 60.0, -tuning.jump_velocity * 0.8)
	_update_hurtbox_shape()
	if ejected:
		health.grant_invulnerability(tuning.eject_invulnerability)


func _process_mounted() -> void:
	if not is_instance_valid(mounted_vehicle):
		dismount_vehicle(true)
		return
	global_position = mounted_vehicle.seat_position()
	facing = mounted_vehicle.facing
	if mounted_vehicle.is_on_floor():
		_last_safe_position = mounted_vehicle.global_position


# ---------------------------------------------------------------------------
# 受傷與死亡
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 格擋與完美反彈
# ---------------------------------------------------------------------------

func _update_blocking() -> void:
	var pressed := Input.is_action_pressed(&"block") and _guard_lockout_left <= 0.0
	# 舉盾需要最低能量；已經舉著的盾可以一直撐到能量耗盡。
	var wants := pressed and (guard >= tuning.guard_min_to_raise if not is_blocking else guard > 0.0)
	if wants and not is_blocking:
		_block_time = 0.0
		# 放開後很快又舉盾：完美格擋窗口縮短，不能狂按亂彈。
		_window_scale = tuning.parry_window_repeat_scale if _since_block_release < tuning.parry_repeat_time else 1.0
	if is_blocking and not wants:
		_since_block_release = 0.0
	is_blocking = wants
	hurtbox.reflect_direction = aim_dir


func _tick_guard(delta: float) -> void:
	_guard_lockout_left = maxf(0.0, _guard_lockout_left - delta)
	_since_block_release += delta
	_contact_block_left = maxf(0.0, _contact_block_left - delta)
	if is_blocking:
		_block_time += delta
	if state != State.NORMAL:
		is_blocking = false
	if _guard_regen_delay_left > 0.0:
		_guard_regen_delay_left -= delta
	elif not is_blocking and guard < tuning.guard_max:
		guard = minf(tuning.guard_max, guard + tuning.guard_regen_per_second * delta)
		_emit_guard()


func is_parry_window() -> bool:
	return is_blocking and _block_time <= parry_window_length()


## 目前有效的完美格擋窗口秒數（夾在 0.14～0.22，連按時縮短）。
func parry_window_length() -> float:
	return clampf(tuning.parry_window, PARRY_WINDOW_MIN, PARRY_WINDOW_MAX) * _window_scale


## 受擊框的格擋判定：只擋準星方向扇形內的攻擊；剛舉盾的瞬間為完美格擋。
func _guard(info: DamageInfo) -> Hurtbox.Guard:
	if not is_blocking or state != State.NORMAL:
		return Hurtbox.Guard.NONE
	# 來襲方向：子彈用飛行方向（反向），接觸攻擊用相對身體中心的位置。
	var incoming := info.origin - (global_position + Vector2(0, -BODY_SIZE.y * 0.5))
	if info.is_projectile and info.knockback.length_squared() > 0.0001:
		incoming = -info.knockback
	if incoming.length_squared() > 1.0 and rad_to_deg(absf(incoming.angle_to(aim_dir))) > tuning.block_arc_degrees * 0.5:
		return Hurtbox.Guard.NONE
	# 接觸攻擊每影格都會判定：短時間內重複的接觸只算一次，不會瞬間耗光能量。
	if not info.is_projectile and _contact_block_left > 0.0:
		return Hurtbox.Guard.BLOCK
	if not info.is_projectile:
		_contact_block_left = CONTACT_BLOCK_INTERVAL
	var shield_point := aim_origin() + aim_dir * 12.0
	if is_parry_window():
		_on_parry(info, shield_point)
		return Hurtbox.Guard.REFLECT if info.is_projectile else Hurtbox.Guard.BLOCK
	_on_block(info, shield_point)
	return Hurtbox.Guard.BLOCK


func _on_parry(info: DamageInfo, at: Vector2) -> void:
	# 接觸攻擊無法反彈，改為讓攻擊者暈眩（例如盾衛犬的衝撞）。
	if not info.is_projectile:
		var enemy := info.get_attacker() as Enemy
		if enemy != null:
			enemy.stun(tuning.parry_stun)
			enemy.velocity.x = signf(enemy.global_position.x - global_position.x) * 160.0
	Feel.play(&"player_parry")
	Fx.impact(at, aim_dir, Palette.CYAN, 14)
	Fx.flash_light(at, Palette.CYAN, 110.0, 2.6, 0.25)
	Sfx.play(&"parry", -2.0, 0.03)
	_visual.notify_parry()
	EventBus.player_parried.emit(at)


func _on_block(info: DamageInfo, at: Vector2) -> void:
	Feel.play(&"player_block", {"dir": Vector2(-aim_dir.x, 0.0), "origin": at})
	if not _block_hint_shown:
		_block_hint_shown = true
		EventBus.toast_requested.emit("剛舉盾的一瞬間被打中＝完美格擋，可反彈子彈")
	guard -= maxf(1.0, float(info.amount)) * tuning.guard_cost_per_damage
	_guard_regen_delay_left = tuning.guard_regen_delay
	velocity.x -= aim_dir.x * 90.0
	Fx.impact(at, aim_dir, Palette.WHITE, 6)
	Sfx.play(&"block", -4.0)
	_visual.notify_block()
	if guard <= 0.0:
		_guard_break()
	_emit_guard()


## 破防：短暫硬直且一段時間無法格擋。
func _guard_break() -> void:
	guard = 0.0
	is_blocking = false
	_guard_lockout_left = tuning.guard_break_lockout
	_guard_regen_delay_left = tuning.guard_break_lockout
	state = State.STAGGERED
	_stagger_left = tuning.guard_break_stun
	Feel.play(&"player_guard_break")
	Fx.burst(aim_origin(), Palette.CYAN, 18, 160.0, 0.4)
	Sfx.play(&"guard_break", -3.0, 0.03)
	EventBus.toast_requested.emit("護盾破防")


func _emit_guard() -> void:
	EventBus.player_guard_changed.emit(guard, tuning.guard_max, _guard_lockout_left > 0.0)


func _on_damaged(info: DamageInfo) -> void:
	if state == State.DASH:
		state = State.NORMAL
	var side := signf(global_position.x - info.origin.x)
	if side == 0.0:
		side = -facing
	velocity = Vector2(side * tuning.hurt_knockback.x, -tuning.hurt_knockback.y)
	Feel.play(&"player_hurt", {"dir": Vector2(side, 0.0), "origin": info.origin if info.origin != Vector2.ZERO else Vector2.INF})
	Fx.flash_light(global_position + Vector2(0, -24), Palette.DANGER, 70.0, 1.5, 0.2)
	CharacterSounds.play(PLAYER_SOUND_ID, &"hurt", -2.0)
	_visual.notify_hurt()


func _on_died(info: DamageInfo) -> void:
	state = State.DEAD
	hurtbox.enabled = false
	is_crouching = false
	Fx.burst(global_position + Vector2(0, -24), Palette.CYAN, 24, 200.0, 0.6)
	Fx.burst(global_position + Vector2(0, -24), Palette.ARMOR, 12, 160.0, 0.5)
	Feel.play(&"player_death")
	Fx.flash_light(global_position + Vector2(0, -24), Palette.CYAN, 160.0, 3.0, 0.6)
	CharacterSounds.play(PLAYER_SOUND_ID, &"death", -4.0)
	_light.enabled = false
	var cause: StringName = info.source_id if info != null and info.source_id != &"" else &"unknown"
	EventBus.player_died.emit(cause)


func _on_health_changed(current: int, maximum: int) -> void:
	_visual.on_health_changed(float(current) / float(maxi(1, maximum)), current < _last_health)
	_last_health = current
	EventBus.player_health_changed.emit(current, maximum)


func _on_loadout_changed() -> void:
	var weapon := loadout.active_weapon()
	_visual.set_weapon_visual(_visual_id_of(weapon))
	EventBus.player_loadout_changed.emit(loadout)


## 檢查點存檔：武器欄＋消耗品。
func checkpoint_snapshot() -> Dictionary:
	var snapshot := loadout.snapshot()
	snapshot["consumables"] = consumables.snapshot()
	return snapshot


## 使用一個消耗品。沒有存貨、或效果用不上（滿血、護盾已滿）時回傳 false，不會浪費。
func use_consumable(id: StringName) -> bool:
	var item := ConsumableBag.find(id)
	if item == null or consumables.count(id) <= 0 or state == State.DEAD:
		return false
	var useful := false
	if item.heal_amount > 0 and health.current < health.max_health:
		useful = true
	if item.restores_guard and (guard < tuning.guard_max or _guard_lockout_left > 0.0):
		useful = true
	if not useful:
		return false
	consumables.take(id)
	if item.heal_amount > 0:
		health.heal(item.heal_amount)
	if item.restores_guard:
		guard = tuning.guard_max
		_guard_lockout_left = 0.0
		_guard_regen_delay_left = 0.0
		_emit_guard()
	Fx.burst(global_position + Vector2(0, -24), item.color, 14, 90.0, 0.45)
	Fx.flash_light(global_position + Vector2(0, -24), item.color, 70.0, 1.4, 0.25)
	Sfx.play(&"pickup", -4.0)
	return true


func is_reloading() -> bool:
	return loadout.is_reloading()


## 護盾是否處於破防鎖定（暫時不能格擋）。
func is_guard_broken() -> bool:
	return _guard_lockout_left > 0.0


## 給視覺元件讀取（避免公開內部計時器）。
func is_melee_swinging() -> bool:
	return _melee_visual_left > 0.0
