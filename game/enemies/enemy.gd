@abstract
class_name Enemy
extends CharacterBody2D
## 敵人基底類別（框架）。
##
## 基底負責：元件組裝（生命／受擊框／接觸傷害）、受擊回饋、破防與終結技、
##           死亡與掉落、畫面外自動休眠、常用感知與攻擊輔助函式。
## 子類別負責：
##   _setup_states()      註冊狀態機（fsm）的各狀態並 start
##   _draw_body(color)    繪製外觀（color 已處理受擊閃白）
##   _draw_overlay()      （可選）繪製預兆，如瞄準線、落點圈
##   _guard(info) -> Hurtbox.Guard （可選）格擋判定，例如盾牌
##   _on_stunned()        （可選）被暈眩時切回安全狀態
##   _on_defeated(info)   （可選）死亡時的特殊效果，例如連鎖爆炸
##   _play_death()        （可選）自訂死亡演出
## 原點位於腳底。

const FLASH_TIME := 0.08
const MAX_FALL_SPEED := 520.0
## 畫面外此距離內仍保持運作，避免敵人在鏡頭邊緣卡住。
const ACTIVATION_MARGIN := 80.0
## 瞄準玩家身體中心的高度偏移。
const TARGET_HEIGHT := 11.0

## 畫面外休眠的總開關（無頭測試等沒有畫面的環境會關閉）。
static var activation_culling_enabled := true

var data: EnemyData
var health: HealthComponent
var hurtbox: Hurtbox
var contact: ContactHitbox
var fsm := StateMachine.new()
var facing: int = -1

var _gravity: float = 900.0
var _flash_left := 0.0
var _stun_left := 0.0
var _telegraph_left := 0.0
var _anim_time := 0.0
var _is_finishable := false
var _dying := false
var _home := Vector2.ZERO
var _target_ref: WeakRef


func configure(p_data: EnemyData) -> void:
	data = p_data


func _ready() -> void:
	if data == null:
		push_error("[Enemy] %s 缺少 EnemyData，已移除。" % name)
		queue_free()
		return
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 900.0))
	_home = global_position
	add_to_group(&"enemies")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.SOLID if data.uses_gravity else Layers.WORLD
	_build_components()
	if activation_culling_enabled and _uses_activation_culling():
		var enabler := VisibleOnScreenEnabler2D.new()
		var size := data.body_size
		enabler.rect = Rect2(-size.x * 0.5 - ACTIVATION_MARGIN, -size.y - ACTIVATION_MARGIN,
				size.x + ACTIVATION_MARGIN * 2.0, size.y + ACTIVATION_MARGIN * 2.0)
		add_child(enabler)
	_setup_states()
	if fsm.current == &"":
		push_warning("[Enemy] %s 沒有啟動狀態機。" % data.id)


func _build_components() -> void:
	var size := data.body_size
	var center := Vector2(0, -size.y * 0.5)
	var body := CollisionShape2D.new()
	var body_shape := RectangleShape2D.new()
	body_shape.size = size
	body.shape = body_shape
	body.position = center
	add_child(body)

	health = HealthComponent.new()
	health.setup(data.max_health, 0.0)
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.ENEMY, health, size, center)
	hurtbox.guard = _guard
	hurtbox.hit_blocked.connect(_on_blocked)

	if data.contact_damage > 0:
		contact = ContactHitbox.new()
		add_child(contact)
		contact.setup(Combat.Team.ENEMY, data.contact_damage, data.contact_source_id, size * 0.8, center)


# ---------------------------------------------------------------------------
# 可覆寫的掛鉤
# ---------------------------------------------------------------------------

@abstract func _setup_states() -> void


func _uses_activation_culling() -> bool:
	return true


func _guard(_info: DamageInfo) -> Hurtbox.Guard:
	return Hurtbox.Guard.NONE


@abstract func _draw_body(color: Color) -> void


func _draw_overlay() -> void:
	pass


func _on_hit(_info: DamageInfo) -> void:
	pass


## 被暈眩時呼叫：子類別應切回安全狀態，避免暈眩結束後立刻出手。
func _on_stunned() -> void:
	pass


func _on_defeated(_info: DamageInfo) -> void:
	pass


func _play_death() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.4, 0.1), 0.12)
	tween.tween_callback(queue_free)


# ---------------------------------------------------------------------------
# 主迴圈
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dying:
		return
	_anim_time += delta
	_flash_left = maxf(0.0, _flash_left - delta)
	if data.uses_gravity and not is_on_floor():
		velocity.y = minf(velocity.y + _gravity * delta, MAX_FALL_SPEED)
	if _stun_left > 0.0:
		_stun_left -= delta
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		if not data.uses_gravity:
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	else:
		_telegraph_left = maxf(0.0, _telegraph_left - delta)
		fsm.tick(delta)
	move_and_slide()
	queue_redraw()


func _draw() -> void:
	if data == null:
		return
	var color := LightKit.glow(Palette.WHITE, 2.0) if _flash_left > 0.0 else data.color
	_draw_body(color)
	_draw_overlay()
	var top := -data.body_size.y - 8.0
	if is_telegraphing():
		# 攻擊預兆：發光驚嘆號。
		var red := LightKit.glow(Palette.DANGER, 2.5)
		draw_line(Vector2(0, top - 6), Vector2(0, top - 1), red, 2.0)
		draw_circle(Vector2(0, top + 2), 1.2, red)
	if _is_finishable and not _dying:
		# 可終結標記：閃爍的青色菱形。
		var pulse := 0.6 + 0.4 * sin(_anim_time * 14.0)
		var c := LightKit.glow(Palette.CYAN, 1.5 + pulse)
		var p := Vector2(0, top - 2)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(3, 0), p + Vector2(0, 4), p + Vector2(-3, 0)]), c)


# ---------------------------------------------------------------------------
# 受擊、破防、死亡
# ---------------------------------------------------------------------------

func can_be_finished() -> bool:
	return _is_finishable and not _dying


func is_stunned() -> bool:
	return _stun_left > 0.0


## 由玩家終結技呼叫：直接擊殺並計為終結。
func execute_finisher() -> void:
	if not can_be_finished():
		return
	var info := DamageInfo.create(health.current, Combat.Team.PLAYER, &"finisher")
	info.is_finisher = true
	info.ignore_invulnerability = true
	info.bypass_guard = true
	info.origin = global_position
	health.take_damage(info)


## 讓敵人暈眩（停止 AI）。
func stun(seconds: float) -> void:
	_stun_left = maxf(_stun_left, seconds)
	_telegraph_left = 0.0
	_on_stunned()


func _on_damaged(info: DamageInfo) -> void:
	_flash_left = FLASH_TIME
	if info.knockback != Vector2.ZERO and data.knockback_scale > 0.0:
		velocity += info.knockback * data.knockback_scale
	if not _is_finishable and data.finish_health_ratio > 0.0 and health.current > 0 \
			and health.current <= ceili(health.max_health * data.finish_health_ratio):
		_is_finishable = true
		stun(data.stagger_duration)
		Fx.burst(_center(), Palette.CYAN, 8, 90.0)
	_on_hit(info)


func _on_blocked(_info: DamageInfo) -> void:
	_flash_left = FLASH_TIME * 0.5


func _on_died(info: DamageInfo) -> void:
	if _dying:
		return
	_dying = true
	set_deferred(&"collision_layer", 0)
	hurtbox.enabled = false
	if contact != null:
		contact.active = false
	velocity = Vector2.ZERO
	var by_player := info != null and info.team == Combat.Team.PLAYER
	var by_finisher := info != null and info.is_finisher
	var center := _center()
	Fx.burst(center, data.color, 16, 170.0, 0.45)
	Fx.flash_light(center, data.color, 70.0, 1.2, 0.25)
	if by_finisher:
		Fx.burst(center, Palette.CYAN, 24, 240.0, 0.5)
	Fx.shake(2.5, 0.12)
	Fx.hitstop(0.03)
	Sfx.play(&"kill", -4.0)
	if by_player:
		EventBus.enemy_killed.emit(data.id, by_finisher)
		_try_drop(by_finisher)
	_on_defeated(info)
	_play_death()


func _try_drop(by_finisher: bool) -> void:
	var chance := data.health_drop_chance + (0.25 if by_finisher else 0.0)
	if randf() >= chance or get_parent() == null:
		return
	var pickup := HealthPickup.new()
	pickup.position = position + Vector2(0, -4)
	get_parent().add_child.call_deferred(pickup)


# ---------------------------------------------------------------------------
# 感知與攻擊輔助
# ---------------------------------------------------------------------------

func _target() -> Node2D:
	var target: Node2D = null
	if _target_ref != null:
		target = _target_ref.get_ref() as Node2D
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Node2D
		_target_ref = weakref(target) if target != null else null
	if target is Player and not (target as Player).is_targetable():
		return null
	return target


func _target_point() -> Vector2:
	var target := _target()
	return target.global_position + Vector2(0, -TARGET_HEIGHT) if target != null else global_position


func _center() -> Vector2:
	return global_position + Vector2(0, -data.body_size.y * 0.5)


func _muzzle() -> Vector2:
	return _center() + Vector2(facing * data.body_size.x * 0.5, 0)


func _distance_to_target() -> float:
	var target := _target()
	return global_position.distance_to(target.global_position) if target != null else INF


func _face_target() -> void:
	var target := _target()
	if target != null and absf(target.global_position.x - global_position.x) > 2.0:
		facing = 1 if target.global_position.x > global_position.x else -1


func _direction_to_target() -> Vector2:
	return (_target_point() - _muzzle()).normalized()


## 與目標之間是否沒有牆壁阻擋。
func _has_line_of_sight() -> bool:
	if _target() == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(_center(), _target_point(), Layers.WORLD)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## 目標在偵測範圍內、高度差可接受、且視線未被阻擋。
func _can_see_target(max_range: float, max_height_diff := 120.0) -> bool:
	var target := _target()
	if target == null:
		return false
	var offset := target.global_position - global_position
	return offset.length() <= max_range and absf(offset.y) <= max_height_diff and _has_line_of_sight()


## 前方腳下是否為懸崖（巡邏時避免掉落）。
func _is_ledge_ahead() -> bool:
	var from := global_position + Vector2(facing * (data.body_size.x * 0.5 + 2.0), -2.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 18), Layers.SOLID)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _start_telegraph(seconds: float) -> void:
	_telegraph_left = seconds
	Sfx.play(&"telegraph", -10.0)


func is_telegraphing() -> bool:
	return _telegraph_left > 0.0


func _scaled_cooldown(base: float) -> float:
	return base * GameState.difficulty.enemy_cooldown_multiplier


func _projectile_speed_multiplier() -> float:
	return GameState.difficulty.enemy_projectile_speed_multiplier


func _shoot(spec: ProjectileSpec, direction: Vector2, origin := Vector2.INF) -> void:
	if spec == null:
		return
	var from := _muzzle() if origin == Vector2.INF else origin
	if ProjectilePool.spawn(spec, from, direction, Combat.Team.ENEMY, _projectile_speed_multiplier()) != null:
		Fx.flash_light(from, spec.color, 40.0, 0.9, 0.08)
		Sfx.play(&"shot_enemy", -10.0)


## 巡邏移動：碰牆或遇到懸崖就回頭。
func _patrol(speed: float) -> void:
	if is_on_floor() and (is_on_wall() or _is_ledge_ahead()):
		facing = -facing
	velocity.x = facing * speed
