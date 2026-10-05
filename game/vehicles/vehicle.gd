class_name Vehicle
extends CharacterBody2D
## 可騎乘兵器：獨立血量與武器、完全不同的操作手感（重、慢、火力強）。
## 被擊毀時彈出駕駛並給予無敵時間；殘骸數秒後消失。原點位於腳底。

const MAX_FALL_SPEED := 520.0
## 剛上車的短暫時間內忽略互動鍵，避免同一次按鍵立刻下車。
const MOUNT_INPUT_GRACE := 0.25
const WRECK_LIFETIME := 4.0
const FLASH_TIME := 0.08
const STOMP_SHAKE_SPEED := 260.0
## 砲管最低可向下壓的角度（弧度）。
const MAX_DOWN_ANGLE := 0.35

var data: VehicleData
var driver: Player
var health: HealthComponent
var hurtbox: Hurtbox
var facing := 1
var aim_dir := Vector2.RIGHT
var destroyed := false
var fall_limit_y := INF

var _fire_cooldown := 0.0
var _flash_left := 0.0
var _mount_grace := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _anim_time := 0.0
var _muzzle_flash := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _light: PointLight2D
var _prompt: WorldPrompt


func configure(p_data: VehicleData) -> void:
	data = p_data


func _ready() -> void:
	LightKit.mark_emissive(self)
	if data == null:
		push_error("[Vehicle] 缺少 VehicleData，已移除。")
		queue_free()
		return
	add_to_group(&"vehicles")
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.SOLID
	var size := data.body_size
	var body := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	body.shape = shape
	body.position = Vector2(0, -size.y * 0.5)
	add_child(body)

	health = HealthComponent.new()
	health.setup(data.max_health, data.hurt_invulnerability)
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_destroyed)
	health.health_changed.connect(_on_health_changed)

	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.PLAYER, health, size * 0.9, Vector2(0, -size.y * 0.5))
	hurtbox.enabled = false

	_light = LightKit.create_point_light(Palette.CYAN, 70.0, 0.0)
	_light.position = Vector2(0, -size.y * 0.6)
	add_child(_light)

	_prompt = WorldPrompt.new()
	_prompt.text = "{interact} 搭乘 %s：重火力、可承受傷害" % data.display_name
	_prompt.radius = 40.0
	_prompt.offset = Vector2(0, -size.y - 14.0)
	add_child(_prompt)


func can_mount() -> bool:
	return not destroyed and driver == null


func mount(player: Player) -> void:
	driver = player
	_mount_grace = MOUNT_INPUT_GRACE
	collision_layer = Layers.PLAYER
	hurtbox.enabled = true
	_prompt.enabled = false
	_light.energy = 0.7
	EventBus.vehicle_mounted.emit(self)
	EventBus.vehicle_health_changed.emit(health.current, health.max_health)
	EventBus.toast_requested.emit(InputBindings.format("搭乘 %s（{interact} 離開）" % data.display_name))
	Sfx.play(&"pickup", -6.0)


## 由 Player.dismount_vehicle() 呼叫，只重置載具本身狀態。
func release_driver() -> void:
	driver = null
	collision_layer = 0 if destroyed else Layers.VEHICLE
	hurtbox.enabled = false
	_prompt.enabled = not destroyed
	_light.energy = 0.0
	EventBus.vehicle_dismounted.emit()


func seat_position() -> Vector2:
	return global_position + Vector2(0, -data.body_size.y * 0.35)


func _muzzle() -> Vector2:
	return global_position + Vector2(0, -data.body_size.y * 0.7) + aim_dir * 16.0


func _physics_process(delta: float) -> void:
	if GameplayLock.is_locked() or get_tree().paused:
		return
	_anim_time += delta
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_flash_left = maxf(0.0, _flash_left - delta)
	_mount_grace = maxf(0.0, _mount_grace - delta)
	_coyote = maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_muzzle_flash = maxf(0.0, _muzzle_flash - delta)
	if not is_on_floor():
		velocity.y = minf(velocity.y + data.gravity * delta, MAX_FALL_SPEED)
	if is_instance_valid(driver) and not destroyed:
		_drive(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, data.acceleration * delta)
	_fall_speed = velocity.y
	move_and_slide()
	_check_landing()
	if global_position.y > fall_limit_y and not destroyed:
		health.kill(DamageInfo.create(health.current, Combat.Team.ENEMY, &"pit"))
	queue_redraw()


func _drive(delta: float) -> void:
	var input_x := Input.get_axis(&"move_left", &"move_right")
	velocity.x = move_toward(velocity.x, input_x * data.move_speed, data.acceleration * delta)
	if is_on_floor():
		_coyote = 0.1
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer = 0.12
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = -data.jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		Fx.dust(global_position, 6, 60.0)
		Sfx.play(&"jump", -6.0, 0.02)
	if Input.is_action_just_released(&"jump") and velocity.y < 0.0:
		velocity.y *= 0.5
	# 機甲瞄準：跟隨滑鼠／右搖桿，但砲管最低只能壓到水平下方 MAX_DOWN_ANGLE（與步兵操作形成差異）。
	var pivot := global_position + Vector2(0, -data.body_size.y * 0.7)
	var wanted := AimInput.direction_from(self, pivot, aim_dir)
	if absf(wanted.x) > 0.05:
		facing = 1 if wanted.x > 0.0 else -1
	var angle := clampf(Vector2(absf(wanted.x), wanted.y).angle(), -PI * 0.5, MAX_DOWN_ANGLE)
	aim_dir = Vector2(cos(angle) * facing, sin(angle))
	if Input.is_action_pressed(&"shoot"):
		_try_fire()
	if _mount_grace <= 0.0 and Input.is_action_just_pressed(&"interact"):
		driver.dismount_vehicle(false)


func _try_fire() -> void:
	var weapon := data.weapon
	if _fire_cooldown > 0.0 or weapon == null or not weapon.is_valid():
		return
	_fire_cooldown = weapon.fire_interval
	var muzzle := _muzzle()
	WeaponSystem.fire(weapon, muzzle, aim_dir, Combat.Team.PLAYER)
	_muzzle_flash = 0.07
	WeaponSystem.muzzle_feedback(weapon, muzzle, aim_dir)
	Sfx.play(weapon.fire_sound, -5.0)
	if weapon.ejects_casing:
		Fx.casing(global_position + Vector2(0, -data.body_size.y * 0.7), facing)


func _check_landing() -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and _fall_speed > STOMP_SHAKE_SPEED:
		Feel.play(&"vehicle_stomp")
		Fx.dust(global_position, 8, 80.0)
		Sfx.play(&"land", -4.0)
	_was_on_floor = on_floor


func _on_damaged(_info: DamageInfo) -> void:
	_flash_left = FLASH_TIME
	Feel.play(&"vehicle_hurt")
	Sfx.play(&"block", -8.0)


func _on_health_changed(current: int, maximum: int) -> void:
	if driver != null:
		EventBus.vehicle_health_changed.emit(current, maximum)


func _on_destroyed(_info: DamageInfo) -> void:
	destroyed = true
	# 延後處理：可能在物理回呼中被擊毀。
	call_deferred(&"_explode_and_eject")


func _explode_and_eject() -> void:
	Fx.explosion(global_position + Vector2(0, -data.body_size.y * 0.5), 34.0, 0, Combat.Team.PLAYER, &"", Palette.WARNING)
	if is_instance_valid(driver):
		driver.dismount_vehicle(true)
	collision_layer = 0
	hurtbox.enabled = false
	_prompt.enabled = false
	EventBus.toast_requested.emit("%s 已損毀" % data.display_name)
	var tween := create_tween()
	tween.tween_interval(WRECK_LIFETIME)
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)


func _draw() -> void:
	if data == null:
		return
	var w := data.body_size.x
	var h := data.body_size.y
	var f := float(facing)
	var base := data.color.darkened(0.55) if destroyed else data.color
	if _flash_left > 0.0:
		base = LightKit.glow(Palette.WHITE, 2.0)
	var walking := is_on_floor() and absf(velocity.x) > 10.0
	var step := sin(_anim_time * 10.0) * 3.0 if walking else 0.0
	# 腿（反關節）
	for side: float in [-1.0, 1.0]:
		var hip := Vector2(side * w * 0.3, -h * 0.4)
		var knee := Vector2(side * w * 0.45 + step * side, -h * 0.2)
		draw_line(hip, knee, base.darkened(0.35), 4.0)
		draw_line(knee, Vector2(side * w * 0.35 - step * side, 0), base.darkened(0.35), 4.0)
	# 機身
	draw_rect(Rect2(-w * 0.5, -h * 0.85, w, h * 0.45), base)
	draw_rect(Rect2(-w * 0.5, -h * 0.85, w, 3), base.lightened(0.25))
	# 駕駛艙
	var occupied := driver != null and not destroyed
	var cockpit := LightKit.glow(Palette.CYAN, 2.0) if occupied else Palette.CYAN_DIM.darkened(0.4)
	draw_rect(Rect2(f * w * 0.05 - 4, -h * 0.8, 8, 6), cockpit)
	# 主砲
	var mount_point := Vector2(0, -h * 0.7)
	draw_line(mount_point, mount_point + aim_dir * 16.0, base.lightened(0.15), 5.0)
	if _muzzle_flash > 0.0:
		var tip := mount_point + aim_dir * 18.0
		draw_circle(tip, 5.0, LightKit.glow(Palette.WARNING, 3.0))
	if destroyed and int(_anim_time * 8.0) % 3 == 0:
		draw_circle(Vector2(randf_range(-w, w) * 0.3, -h * randf_range(0.4, 0.8)), 1.5, LightKit.glow(Palette.WARNING, 2.5))
