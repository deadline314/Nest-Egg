class_name Player
extends CharacterBody2D
## 玩家「七號」：移動、跳躍、衝刺、8 方向射擊、近戰／終結技、騎乘載具。
## 所有手感參數集中在 PlayerTuning 資源；原點位於腳底。

enum State { NORMAL, DASH, FINISHER, MOUNTED, STAGGERED, DEAD }

const BODY_SIZE := Vector2(12, 44)
const CROUCH_HEIGHT := 30.0
## 瞄準基準點（肩膀）的高度：站姿／蹲姿。
const SHOULDER_HEIGHT := 35.0
const CROUCH_SHOULDER_HEIGHT := 27.0
const SAFE_GROUND_DELAY := 0.25
const DROP_THROUGH_TIME := 0.25
const MELEE_VISUAL_TIME := 0.12
## 下車後短暫禁止再次上車（避免同一次按鍵下車又立刻上車）。
const REMOUNT_COOLDOWN := 0.3
## 準星擴散每秒回復量與最大額外散佈角度。
const AIM_BLOOM_RECOVERY := 2.5
const AIM_BLOOM_MAX_DEGREES := 4.0
## 同一接觸攻擊重複格擋時的最短計費間隔。
const CONTACT_BLOCK_INTERVAL := 0.35

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
var _dash_left := 0.0
var _dash_cooldown_left := 0.0
var _air_dash_used := false
var _fire_cooldown_left := 0.0
var _melee_cooldown_left := 0.0
var _melee_visual_left := 0.0
var _finisher_left := 0.0
var _drop_through_left := 0.0
var _safe_ground_time := 0.0
var _remount_cooldown_left := 0.0
var _dash_dir := 1
var _block_time := 0.0
var _guard_regen_delay_left := 0.0
var _guard_lockout_left := 0.0
var _stagger_left := 0.0
var _contact_block_left := 0.0
var _last_health := 0
var _last_safe_position := Vector2.ZERO
var _query_shape := RectangleShape2D.new()


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
	loadout.reload_started.connect(func() -> void: Sfx.play(&"reload_start", -4.0))
	loadout.reload_finished.connect(func() -> void: Sfx.play(&"reload_done", -3.0))
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
	var height := CROUCH_SHOULDER_HEIGHT if is_crouching else SHOULDER_HEIGHT
	return global_position + Vector2(0, -height)


## 子彈從手上武器的槍口射出（與畫面上的槍管一致）。
func muzzle_position() -> Vector2:
	return _visual.muzzle_global() if _visual != null else aim_origin() + aim_dir * 12.0


# ---------------------------------------------------------------------------
# 主迴圈
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	AimInput.observe(event)


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
	_apply_corner_correction(delta)
	move_and_slide()
	_after_move(delta)


func _tick_timers(delta: float) -> void:
	_coyote_left = maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	_fire_cooldown_left = maxf(0.0, _fire_cooldown_left - delta)
	_melee_cooldown_left = maxf(0.0, _melee_cooldown_left - delta)
	_melee_visual_left = maxf(0.0, _melee_visual_left - delta)
	_remount_cooldown_left = maxf(0.0, _remount_cooldown_left - delta)
	aim_bloom = move_toward(aim_bloom, 0.0, AIM_BLOOM_RECOVERY * delta)
	if state != State.DEAD and state != State.MOUNTED:
		loadout.tick(delta * cyber.reload_speed_scale())
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
		target_speed = input_x * tuning.run_speed * cyber.move_speed_scale()
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

	if on_floor:
		_coyote_left = tuning.coyote_time
		_air_dash_used = false
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_left = tuning.jump_buffer
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
		Sfx.play(&"land", lerpf(-16.0, -6.0, impact))
	_was_on_floor = on_floor
	if state == State.NORMAL and is_on_floor() and not health.is_invulnerable():
		_safe_ground_time += delta
		if _safe_ground_time >= SAFE_GROUND_DELAY:
			_last_safe_position = global_position
	else:
		_safe_ground_time = 0.0


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
	if absf(aim_dir.x) > 0.05 and state != State.DASH and state != State.MOUNTED:
		facing = 1 if aim_dir.x > 0.0 else -1


func _update_hurtbox_shape() -> void:
	var height := CROUCH_HEIGHT if is_crouching else BODY_SIZE.y
	hurtbox.resize(Vector2(BODY_SIZE.x * 0.8, height * 0.9), Vector2(0, -height * 0.5))


# ---------------------------------------------------------------------------
# 動作
# ---------------------------------------------------------------------------

func _try_fire() -> void:
	if _fire_cooldown_left > 0.0:
		return
	var weapon := loadout.active_weapon()
	if weapon == null or not weapon.is_valid():
		return
	if not loadout.consume_ammo():
		return
	_fire_cooldown_left = weapon.fire_interval / cyber.fire_rate_scale()
	var muzzle := muzzle_position()
	WeaponSystem.fire(weapon, muzzle, aim_dir, Combat.Team.PLAYER, 1.0, aim_bloom * AIM_BLOOM_MAX_DEGREES)
	aim_bloom = minf(1.0, aim_bloom + weapon.bloom_per_shot)
	# 射擊手感：槍口閃光 + 光源 + 鏡頭反向後座 + 彈殼 + 音效。
	Fx.flash_light(muzzle, weapon.color, 56.0, weapon.muzzle_light_energy, 0.08)
	Fx.kick(-aim_dir, weapon.camera_kick)
	Fx.shake(weapon.screen_shake, 0.08)
	if weapon.ejects_casing:
		Fx.casing(aim_origin(), facing)
	Sfx.play(weapon.fire_sound, -6.0)
	if weapon.recoil > 0.0:
		velocity -= aim_dir * weapon.recoil * (1.0 if not is_on_floor() else 0.3)
	_visual.notify_fired(weapon.color)


func _try_dash(input_x: float) -> void:
	if _dash_cooldown_left > 0.0 or (not is_on_floor() and _air_dash_used):
		return
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


## 近戰鍵：附近有破防敵人時發動終結技，否則普通斬擊。成功出招回傳 true。
func _try_melee() -> bool:
	if _melee_cooldown_left > 0.0:
		return false
	var target := _find_finisher_target()
	if target != null:
		_start_finisher(target)
		return true
	_melee_cooldown_left = tuning.melee_cooldown
	_melee_visual_left = MELEE_VISUAL_TIME
	var center := global_position + Vector2(facing * tuning.melee_range * 0.5, -BODY_SIZE.y * 0.55)
	var landed := false
	for target_hurtbox in _query_hurtboxes(center, Vector2(tuning.melee_range, BODY_SIZE.y)):
		var info := DamageInfo.create(tuning.melee_damage, Combat.Team.PLAYER, &"melee", Vector2(facing * 180.0, -60.0))
		info.stagger = 2
		info.origin = global_position
		if target_hurtbox.receive(info) != Hurtbox.Result.IGNORED:
			landed = true
			EventBus.hit_confirmed.emit(target_hurtbox.global_position, target_hurtbox.health.is_dead)
			Fx.burst(target_hurtbox.global_position, Palette.CYAN, 6, 120.0, 0.2)
	if landed:
		Fx.hitstop(0.05)
		Fx.shake(2.0, 0.08)
		Sfx.play(&"hit", -3.0)
	return true


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
	Fx.hitstop(tuning.finisher_hitstop)
	Fx.shake(5.0, 0.2)
	Fx.flash_light(target.global_position + Vector2(0, -10), Palette.CYAN, 120.0, 2.5, 0.3)
	Sfx.play(&"finisher")
	loadout.refill_ratio(tuning.finisher_ammo_refund)


func _process_finisher(delta: float) -> void:
	_finisher_left -= delta
	velocity = Vector2.ZERO
	if _finisher_left <= 0.0:
		state = State.NORMAL


func _query_hurtboxes(center: Vector2, size: Vector2) -> Array[Hurtbox]:
	var result: Array[Hurtbox] = []
	_query_shape.size = size
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _query_shape
	params.transform = Transform2D(0.0, center)
	params.collision_mask = Layers.ENEMY_HURTBOX
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 16):
		var found := hit.get("collider") as Hurtbox
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
	is_blocking = wants
	hurtbox.reflect_direction = aim_dir


func _tick_guard(delta: float) -> void:
	_guard_lockout_left = maxf(0.0, _guard_lockout_left - delta)
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
	return is_blocking and _block_time <= tuning.parry_window


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
	Fx.hitstop(0.08)
	Fx.shake(3.0, 0.12)
	Fx.impact(at, aim_dir, Palette.CYAN, 14)
	Fx.flash_light(at, Palette.CYAN, 110.0, 2.6, 0.25)
	Sfx.play(&"parry", -2.0, 0.03)
	_visual.notify_parry()
	EventBus.player_parried.emit(at)


func _on_block(info: DamageInfo, at: Vector2) -> void:
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
	Fx.shake(4.0, 0.2)
	Fx.burst(aim_origin(), Palette.CYAN, 18, 160.0, 0.4)
	Sfx.play(&"hurt", -6.0, 0.0)
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
	Fx.hitstop(0.07)
	Fx.shake(4.0, 0.15)
	Fx.flash_light(global_position + Vector2(0, -24), Palette.DANGER, 70.0, 1.5, 0.2)
	Sfx.play(&"hurt", -2.0)
	_visual.notify_hurt()


func _on_died(info: DamageInfo) -> void:
	state = State.DEAD
	hurtbox.enabled = false
	is_crouching = false
	Fx.burst(global_position + Vector2(0, -24), Palette.CYAN, 24, 200.0, 0.6)
	Fx.burst(global_position + Vector2(0, -24), Palette.ARMOR, 12, 160.0, 0.5)
	Fx.shake(6.0, 0.3)
	Fx.hitstop(0.14)
	Fx.flash_light(global_position + Vector2(0, -24), Palette.CYAN, 160.0, 3.0, 0.6)
	Sfx.play(&"explosion", -4.0)
	_light.enabled = false
	var cause: StringName = info.source_id if info != null and info.source_id != &"" else &"unknown"
	EventBus.player_died.emit(cause)


func _on_health_changed(current: int, maximum: int) -> void:
	_visual.on_health_changed(float(current) / float(maxi(1, maximum)), current < _last_health)
	_last_health = current
	EventBus.player_health_changed.emit(current, maximum)


func _on_loadout_changed() -> void:
	var weapon := loadout.active_weapon()
	_visual.set_weapon_visual(weapon.visual_id if weapon != null else "")
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
