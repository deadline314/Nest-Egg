extends Enemy
## 迫擊兵（拋射範圍）
## 行為：從遠處拋射砲彈，砲彈飛行期間地面會顯示「落點警示圈」；玩家太近時會後退拉開距離。
## 應對：看到警示圈就離開；最有效的打法是貼近壓制（近距離牠無法開砲，只能後退）。

const RETREAT_TIME := 0.7
const MARKER_RADIUS := 22.0

var _landing := Vector2.ZERO
var _marker_left := 0.0
var _cooldown := 0.8


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"aim", _aim_tick, _aim_enter)
	fsm.add(&"retreat", _retreat_tick)
	fsm.start(&"idle")


func _on_stunned() -> void:
	fsm.transition(&"idle")


func _physics_process(delta: float) -> void:
	_marker_left = maxf(0.0, _marker_left - delta)
	super._physics_process(delta)


## 開砲前把發射器往上舉成拋射角度。
func _rig_aim() -> Vector2:
	if fsm.is_in(&"aim"):
		return Vector2(facing * 0.6, -0.8).normalized()
	return Vector2(facing, 0.15).normalized()


func _min_range() -> float:
	return data.ability_radius


func _idle_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	var distance := _distance_to_target()
	if distance < _min_range() and _target() != null:
		fsm.transition(&"retreat")
	elif _cooldown <= 0.0 and distance <= data.attack_range and _target() != null:
		fsm.transition(&"aim")


func _aim_enter() -> void:
	_face_target()
	var target := _target()
	_landing = target.global_position if target != null else global_position
	_marker_left = data.telegraph_time + data.ability_time
	_start_telegraph(data.telegraph_time)


func _aim_tick(_delta: float) -> void:
	velocity.x = 0.0
	if _distance_to_target() < _min_range():
		_marker_left = 0.0
		fsm.transition(&"retreat")
		return
	if not is_telegraphing():
		_fire_lob()
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"idle")


## 依固定飛行時間計算拋物線初速，讓砲彈準確落在警示圈中心。
func _fire_lob() -> void:
	var spec := data.projectile
	if spec == null or spec.gravity <= 0.0:
		push_warning("[Mortar] 拋射彈需要 gravity > 0")
		return
	var origin := _center() + Vector2(facing * 4.0, -8.0)
	var flight := maxf(0.3, data.ability_time)
	var offset := _landing + Vector2(0, -4) - origin
	var launch := Vector2(offset.x / flight, (offset.y - 0.5 * spec.gravity * flight * flight) / flight)
	ProjectilePool.spawn(spec, origin, launch, Combat.Team.ENEMY, launch.length() / maxf(1.0, spec.speed))
	_rig_input.recoil = 1.0
	Fx.flash_light(origin, Palette.WARNING, 50.0, 1.2, 0.1)
	Fx.dust(global_position, 3, 30.0)
	Sfx.play(&"shot_cannon", -12.0)


func _retreat_tick(_delta: float) -> void:
	var target := _target()
	if target != null:
		facing = -1 if target.global_position.x > global_position.x else 1
	velocity.x = 0.0 if _is_ledge_ahead() or is_on_wall() else facing * data.move_speed
	if fsm.time_in_state >= RETREAT_TIME:
		_face_target()
		fsm.transition(&"idle")


func _draw_overlay() -> void:
	if _marker_left <= 0.0:
		return
	var local := to_local(_landing)
	var pulse := 0.5 + 0.5 * sin(_anim_time * 16.0)
	var color := LightKit.glow(Palette.DANGER, 1.5 + pulse)
	color.a = 0.6
	draw_arc(local + Vector2(0, -2), MARKER_RADIUS, PI, TAU, 16, color, 1.5)
	draw_line(local + Vector2(-MARKER_RADIUS, -1), local + Vector2(MARKER_RADIUS, -1), color, 1.5)


func _draw_body(color: Color) -> void:
	var f := float(facing)
	var w := data.body_size.x
	var h := data.body_size.y
	draw_rect(Rect2(-w * 0.5, -h * 0.75, w, h * 0.75), color)
	draw_rect(Rect2(-w * 0.5, -h * 0.75, w, 2), color.lightened(0.25))
	var barrel_base := Vector2(f * 2.0, -h * 0.75)
	draw_line(barrel_base, barrel_base + Vector2(f * 6.0, -9.0), Palette.TERRAIN_TOP, 4.0)
	var eye := LightKit.glow(Palette.WARNING, 3.0 if is_telegraphing() else 1.4)
	draw_circle(Vector2(f * w * 0.25, -h * 0.55), 1.5, eye)
