@abstract
class_name Enemy
extends CharacterBody2D
## 敵人基底類別（框架）。
##
## 基底負責：元件組裝（生命／受擊框／接觸傷害）、受擊回饋、破防與終結技、
##           死亡與掉落、畫面外自動休眠、常用感知與攻擊輔助函式。
## 子類別負責：
##   _setup_states()      註冊狀態機（fsm）的各狀態並 start
##   _draw_body(color)    繪製外觀（color 已處理受擊閃白）；有骨架外觀（data.rig_skin）時改用骨架，僅在骨架載入失敗時使用
##   _rig_aim()           （可選）骨架手持武器的瞄準方向（世界座標單位向量）
##   _draw_overlay()      （可選）繪製預兆，如瞄準線、落點圈
##   _guard(info) -> Hurtbox.Guard （可選）格擋判定，例如盾牌（支援型敵人給的護盾由基底處理，不需要寫在這裡）
##   _on_stunned()        （可選）被暈眩時切回安全狀態
##   _on_defeated(info)   （可選）死亡時的特殊效果，例如連鎖爆炸
##   _play_death()        （可選）自訂死亡演出
## 原點位於腳底。

const FLASH_TIME := 0.08
## 受擊分層：累積的衝擊力每秒回復多少；單次衝擊達韌性的 STAGGER_RATIO 倍就硬直（出招中要 BREAK_RATIO 倍）；反應完有 REACTION_GRACE 秒不會再被畏縮或硬直（避免被連續射擊鎖死）。
const POISE_RECOVER := 2.0
const STAGGER_RATIO := 1.5
const BREAK_RATIO := 2.5
const REACTION_GRACE := 0.5
## 各層的命中頓幀（只凍結攻擊方與被打方的秒數）與退縮幅度；輕擊沒有頓幀。
const FLINCH_FREEZE := 0.03
const STAGGER_FREEZE := 0.06
## 擊殺的頓幀：比畏縮與硬直都長。
const KILL_FREEZE := 0.07
const LIGHT_HURT_SCALE := 0.4
const FLINCH_HURT_SCALE := 1.2
const STAGGER_HURT_SCALE := 2.2
## 受擊反應的種類。
enum HitTier { LIGHT, FLINCH, STAGGER }
const MAX_FALL_SPEED := 520.0
## 畫面外此距離內仍保持運作，避免敵人在鏡頭邊緣卡住。
const ACTIVATION_MARGIN := 80.0
## 瞄準玩家身體中心的高度偏移。
const TARGET_HEIGHT := 24.0
const RIG_DEATH_TIME := 0.9
## 護盾最多疊幾層（每層擋掉一次攻擊；爆炸與終結技無視護盾）。
const MAX_SHIELD := 3
## 被警報引來（raise_alert）時：偵測範圍的倍率與巡邏移動的速度倍率；抵達警報地點附近就停止聚集。
const ALERT_RANGE_SCALE := 1.5
const ALERT_SPEED_SCALE := 1.5
const ALERT_ARRIVE_DISTANCE := 28.0

## 畫面外休眠的總開關（無頭測試等沒有畫面的環境會關閉）。
static var activation_culling_enabled := true

var data: EnemyData
var health: HealthComponent
var hurtbox: Hurtbox
var contact: ContactHitbox
var fsm := StateMachine.new()
var facing: int = -1
## 護盾層數（支援型敵人給的）：每層擋掉一次攻擊。
var shield := 0
## 骨架外觀（人形敵人）；機械類敵人為 null，改用 _draw_body 程式繪製。
var rig: CharacterRig

var _rig_input := RigInput.new()
## 專屬特效（art/vfx/enemies/<id>.json）：腳步、受擊、死亡、招式狀態切換。
var vfx: EnemyVfx
var _vfx_state: StringName = &""

var _gravity: float = 900.0
var _flash_left := 0.0
var _stun_left := 0.0
## 畏縮剩餘秒數、累積的衝擊力（韌性條），以及剛反應完不再被打斷的保護時間。
var _flinch_left := 0.0
var _poise_load := 0.0
var _reaction_grace_left := 0.0
const TELEGRAPH_LIGHT_RADIUS := 90.0
var _telegraph_left := 0.0
## 攻擊預兆的紅光（第一次預兆時才建立；不受預算管理，數量少、只在預兆期間亮）。
var _telegraph_light: PointLight2D
var _telegraph_time := 0.0
var _anim_time := 0.0
var _is_finishable := false
var _dying := false
## 戒備：被探照無人機等警報引來，剩餘秒數與聚集的地點（世界座標）。
var _alert_left := 0.0
var _alert_point := Vector2.ZERO
var _home := Vector2.ZERO
var _target_ref: WeakRef


func configure(p_data: EnemyData) -> void:
	data = p_data


func _ready() -> void:
	LightKit.mark_emissive(self)
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
	vfx = EnemyVfx.load_for(String(data.id))
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
	hurtbox.guard = _guard_with_shield
	hurtbox.hit_blocked.connect(_on_blocked)

	if not data.rig_skin.is_empty():
		_build_rig()

	if data.contact_damage > 0:
		contact = ContactHitbox.new()
		add_child(contact)
		contact.setup(Combat.Team.ENEMY, data.contact_damage, data.contact_source_id, size * 0.8, center)


func _build_rig() -> void:
	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	if not rig.setup(data.rig_skin):
		push_error("[Enemy] %s 的骨架外觀載入失敗：%s，改用程式繪製。" % [data.id, data.rig_skin])
		rig.queue_free()
		rig = null
		return
	rig.set_weapon(data.rig_weapon)
	# 骨架畫在敵人自身的疊加圖層（預兆線、標記）之下。
	rig.show_behind_parent = true
	_rig_input.two_handed = data.rig_two_handed
	_rig_input.shield_forward = data.rig_shield
	_rig_input.run_speed = maxf(40.0, data.move_speed * 2.0)


func _drive_rig(delta: float) -> void:
	if rig == null:
		return
	_rig_input.velocity = velocity
	_rig_input.on_floor = is_on_floor() or not data.uses_gravity
	_rig_input.facing = facing
	_rig_input.aim_dir = _rig_aim()
	_rig_input.staggered = _stun_left > 0.0
	_rig_input.dead = _dying
	_update_rig_action()
	_rig_state(_rig_input)
	rig.animate(delta, _rig_input)
	_rig_input.recoil = 0.0
	_rig_input.hurt = false


# ---------------------------------------------------------------------------
# 可覆寫的掛鉤
# ---------------------------------------------------------------------------

@abstract func _setup_states() -> void


func _uses_activation_culling() -> bool:
	return true


func _guard(_info: DamageInfo) -> Hurtbox.Guard:
	return Hurtbox.Guard.NONE


## 專屬特效：狀態一變就播進入特效、依移動距離播腳步。
func _tick_vfx() -> void:
	if vfx == null or vfx.is_empty():
		return
	if fsm.current != _vfx_state:
		_vfx_state = fsm.current
		vfx.play_state(_vfx_state, global_position, _center(), _muzzle())
	vfx.tick_step(global_position, is_on_floor() and absf(velocity.x) > 8.0)


## 目前狀態有沒有對應的專屬動作（EnemyData.rig_actions）：有就依停留時間播放進度，沒有就清掉。
func _update_rig_action() -> void:
	var action := StringName(str(data.rig_actions.get(String(fsm.current), "")))
	_rig_input.action = action
	if action == &"":
		_rig_input.action_t = 0.0
		return
	var actions: Variant = RigLibrary.load_json(HumanoidAnimator.ACTIONS_PATH).get("actions", {})
	var duration := 0.5
	if typeof(actions) == TYPE_DICTIONARY and (actions as Dictionary).has(String(action)):
		duration = maxf(0.05, float(((actions as Dictionary)[String(action)] as Dictionary).get("duration", 0.5)))
	_rig_input.action_t = clampf(fsm.time_in_state / duration, 0.0, 1.0)


## （可選）骨架動畫輸入的補充（例如蓄力時蹲下），每影格在播放動畫前呼叫。
func _rig_state(_input: RigInput) -> void:
	pass


## 先扣護盾，再交給子類別的格擋判定。
func _guard_with_shield(info: DamageInfo) -> Hurtbox.Guard:
	if shield > 0:
		shield -= 1
		Fx.impact(_center(), Vector2(-signf(info.knockback.x) if info.knockback.x != 0.0 else -facing, -0.3), Palette.CYAN, 6)
		Sfx.play(&"block", -4.0)
		return Hurtbox.Guard.BLOCK
	return _guard(info)


@abstract func _draw_body(color: Color) -> void


func _rig_aim() -> Vector2:
	return Vector2(facing, 0.05).normalized()


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
	if rig != null:
		# 骨架角色：倒地動畫播完後淡出。
		tween.tween_interval(RIG_DEATH_TIME)
		tween.tween_property(self, "modulate:a", 0.0, 0.4)
	else:
		tween.tween_property(self, "scale", Vector2(1.4, 0.1), 0.12)
	tween.tween_callback(queue_free)


# ---------------------------------------------------------------------------
# 主迴圈
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dying:
		if rig != null:
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
			if data.uses_gravity and not is_on_floor():
				velocity.y = minf(velocity.y + _gravity * delta, MAX_FALL_SPEED)
			move_and_slide()
			_drive_rig(delta)
		return
	_anim_time += delta
	_flash_left = maxf(0.0, _flash_left - delta)
	_alert_left = maxf(0.0, _alert_left - delta)
	_poise_load = maxf(0.0, _poise_load - POISE_RECOVER * delta)
	_reaction_grace_left = maxf(0.0, _reaction_grace_left - delta)
	if data.uses_gravity and not is_on_floor():
		velocity.y = minf(velocity.y + _gravity * delta, MAX_FALL_SPEED)
	if _stun_left > 0.0:
		_stun_left -= delta
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		if not data.uses_gravity:
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	elif _flinch_left > 0.0:
		# 畏縮：動作暫停（預兆與狀態計時一起停），之後從原處繼續。
		_flinch_left -= delta
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		if not data.uses_gravity:
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	else:
		_telegraph_left = maxf(0.0, _telegraph_left - delta)
		fsm.tick(delta)
	_tick_vfx()
	_update_telegraph_light(delta)
	move_and_slide()
	_drive_rig(delta)
	queue_redraw()


func _draw() -> void:
	if data == null:
		return
	if rig == null:
		var color := LightKit.glow(Palette.WHITE, 2.0) if _flash_left > 0.0 else data.color
		_draw_body(color)
	_draw_overlay()
	var top := -data.body_size.y - 8.0
	if shield > 0:
		_draw_shield()
	if is_telegraphing():
		# 攻擊預兆：發光驚嘆號。
		var red := LightKit.glow(Palette.DANGER, 2.5)
		draw_line(Vector2(0, top - 6), Vector2(0, top - 1), red, 2.0)
		draw_circle(Vector2(0, top + 2), 1.2, red)
	if _alert_left > 0.0 and not _dying and not is_telegraphing():
		# 戒備標記：頭上的黃色三角，提醒玩家這隻已經被引來。
		var alert_color := LightKit.glow(Palette.WARNING, 1.4)
		var tip := Vector2(0, top - 1)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-3, -5), tip + Vector2(3, -5), tip]), alert_color)
	if _is_finishable and not _dying:
		# 可終結標記：閃爍的青色菱形。
		var pulse := 0.6 + 0.4 * sin(_anim_time * 14.0)
		var c := LightKit.glow(Palette.CYAN, 1.5 + pulse)
		var p := Vector2(0, top - 2)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(3, 0), p + Vector2(0, 4), p + Vector2(-3, 0)]), c)


## 護盾外觀：身體外圍的青色六角形，層數越多越亮。
func _draw_shield() -> void:
	var radius := maxf(data.body_size.x, data.body_size.y) * 0.62
	var center := Vector2(0, -data.body_size.y * 0.5)
	var color := LightKit.glow(Palette.CYAN, 1.0 + 0.5 * shield + 0.3 * sin(_anim_time * 6.0))
	color.a = 0.55 + 0.1 * shield
	var points := PackedVector2Array()
	for i in 7:
		points.append(center + Vector2.RIGHT.rotated(TAU * i / 6.0 + PI / 6.0) * radius)
	draw_polyline(points, color, 1.5)


# ---------------------------------------------------------------------------
# 受擊、破防、死亡
# ---------------------------------------------------------------------------

func is_dying() -> bool:
	return _dying


## 被警報引來：seconds 秒內偵測範圍變大、巡邏改為往 point 聚集（取較長的戒備時間）。
func raise_alert(point: Vector2, seconds: float) -> void:
	if _dying:
		return
	_alert_left = maxf(_alert_left, seconds)
	_alert_point = point


func is_alerted() -> bool:
	return _alert_left > 0.0


## 支援型敵人替這個敵人加護盾（上限 MAX_SHIELD 層）。
func add_shield(layers: int) -> void:
	if _dying:
		return
	shield = mini(MAX_SHIELD, shield + maxi(0, layers))


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
	var tier := _resolve_hit_tier(info) if health.current > 0 else HitTier.LIGHT
	_flash_left = FLASH_TIME
	if vfx != null:
		vfx.play_hit(_center(), -info.knockback.normalized() if info.knockback != Vector2.ZERO else Vector2.UP)
	if rig != null:
		rig.flash(0.5 if tier == HitTier.LIGHT else 1.0)
		rig.set_armor_ratio(health.ratio())
		_rig_input.hurt = true
		_rig_input.hurt_scale = [LIGHT_HURT_SCALE, FLINCH_HURT_SCALE, STAGGER_HURT_SCALE][tier]
	if info.knockback != Vector2.ZERO and data.knockback_scale > 0.0:
		velocity += info.knockback * data.knockback_scale
	if not _is_finishable and data.finish_health_ratio > 0.0 and health.current > 0 \
			and health.current <= ceili(health.max_health * data.finish_health_ratio):
		_is_finishable = true
		stun(data.stagger_duration)
		Fx.burst(_center(), Palette.CYAN, 8, 90.0)
	elif health.current > 0:
		_apply_hit_tier(tier, info)
	_on_hit(info)


## 出招中（資料的 armor_states）：輕擊與累積都打不斷。
func _is_armored() -> bool:
	return data.armor_states.has(String(fsm.current))


## 這一擊造成哪一層反應：單次重擊 → 硬直；累積夠了 → 畏縮；其餘只有閃白。反應後有保護時間，不會被連續射擊鎖死。
func _resolve_hit_tier(info: DamageInfo) -> HitTier:
	var impact := info.get_impact()
	var poise := maxf(0.1, data.poise)
	var armored := _is_armored()
	var stagger_at := poise * (BREAK_RATIO if armored else STAGGER_RATIO)
	if impact >= stagger_at:
		return HitTier.STAGGER
	if _reaction_grace_left > 0.0:
		return HitTier.LIGHT
	_poise_load += impact
	if not armored and _poise_load >= poise:
		return HitTier.FLINCH
	return HitTier.LIGHT


func _apply_hit_tier(tier: HitTier, info: DamageInfo) -> void:
	if tier == HitTier.LIGHT:
		return
	_poise_load = 0.0
	if tier == HitTier.FLINCH:
		_flinch_left = data.flinch_time
		_reaction_grace_left = REACTION_GRACE + data.flinch_time
		Fx.freeze([self, info.get_attacker()], FLINCH_FREEZE)
		return
	stun(data.stagger_time)
	_reaction_grace_left = REACTION_GRACE + data.stagger_time
	Fx.freeze([self, info.get_attacker()], STAGGER_FREEZE)
	Fx.shake(1.2, 0.08)


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
	if vfx != null and not vfx.is_empty():
		vfx.play_death(center, global_position, self, rig)  # 這個敵人自己的死亡演出
	else:
		Fx.burst(center, data.color, 16, 170.0, 0.45)
		Fx.flash_light(center, data.color, 70.0, 1.2, 0.25)
	if by_finisher:
		Fx.burst(center, Palette.CYAN, 24, 240.0, 0.5)
	Fx.shake(2.5, 0.12)
	Fx.freeze([self, info.get_attacker() if info != null else null], KILL_FREEZE)
	Sfx.play(&"kill", -4.0)
	if by_player:
		EventBus.enemy_killed.emit(data.id, by_finisher)
		_try_drop(by_finisher)
	_on_defeated(info)
	_play_death()


func _try_drop(by_finisher: bool) -> void:
	_drop_credits()
	var chance := data.health_drop_chance + (0.25 if by_finisher else 0.0)
	if randf() >= chance or get_parent() == null:
		return
	var pickup := HealthPickup.new()
	pickup.position = position + Vector2(0, -4)
	get_parent().add_child.call_deferred(pickup)


func _drop_credits() -> void:
	if data.credit_value <= 0 or get_parent() == null:
		return
	var credits := CreditPickup.new()
	credits.value = data.credit_value
	credits.position = position + Vector2(randf_range(-6.0, 6.0), -4)
	get_parent().add_child.call_deferred(credits)


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
	if rig != null and not data.rig_weapon.is_empty():
		return rig.muzzle_global()
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
	if _alert_left > 0.0:
		max_range *= ALERT_RANGE_SCALE
		max_height_diff *= ALERT_RANGE_SCALE
	var offset := target.global_position - global_position
	return offset.length() <= max_range and absf(offset.y) <= max_height_diff and _has_line_of_sight()


## 前方腳下是否為懸崖（巡邏時避免掉落）。
func _is_ledge_ahead() -> bool:
	var from := global_position + Vector2(facing * (data.body_size.x * 0.5 + 2.0), -2.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 18), Layers.SOLID)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _start_telegraph(seconds: float) -> void:
	_telegraph_left = seconds
	_ensure_telegraph_light()
	Sfx.play(&"telegraph", -10.0)


func _ensure_telegraph_light() -> void:
	if _telegraph_light != null:
		return
	_telegraph_light = LightKit.create_point_light(Palette.DANGER, TELEGRAPH_LIGHT_RADIUS, 0.0, false, false)
	_telegraph_light.position = Vector2(0, -data.body_size.y * 0.5)
	_telegraph_light.enabled = false
	add_child(_telegraph_light)


## 預兆期間的紅光脈動，讓暗處也看得到「要出招了」。
func _update_telegraph_light(delta: float) -> void:
	if _telegraph_light == null:
		return
	if _telegraph_left > 0.0:
		_telegraph_time += delta
		_telegraph_light.enabled = true
		_telegraph_light.energy = 1.1 + 0.5 * sin(_telegraph_time * 22.0)
	elif _telegraph_light.enabled:
		_telegraph_light.enabled = false


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
	_rig_input.recoil = 1.0
	if ProjectilePool.spawn(spec, from, direction, Combat.Team.ENEMY, _projectile_speed_multiplier()) != null:
		Fx.flash_light(from, spec.color, 40.0, 0.9, 0.08)
		Fx.flare(from, spec.color, 12.0, 0.05)
		Fx.sparks(from, spec.color, 2, 220.0, 0.12, direction, 0.7, 200.0)
		Sfx.play(&"shot_enemy", -10.0)


## 巡邏移動：碰牆或遇到懸崖就回頭。戒備中改為往警報地點聚集（遇到懸崖或牆就停下）。
func _patrol(speed: float) -> void:
	if _alert_left > 0.0 and absf(_alert_point.x - global_position.x) > ALERT_ARRIVE_DISTANCE:
		facing = 1 if _alert_point.x > global_position.x else -1
		var blocked := is_on_floor() and (is_on_wall() or _is_ledge_ahead())
		velocity.x = 0.0 if blocked else facing * speed * ALERT_SPEED_SCALE
		return
	if is_on_floor() and (is_on_wall() or _is_ledge_ahead()):
		facing = -facing
	velocity.x = facing * speed
