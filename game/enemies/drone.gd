extends Enemy
## 監視蜂（飛行俯衝）
## 行為：在玩家頭頂盤旋 → 停頓並閃爍鎖定 → 直線俯衝撞擊 → 緩慢爬升回到高空。
## 應對：用「上／斜上」射擊在牠盤旋時擊落；看到停頓閃爍就衝刺或橫移閃開俯衝路線。

const HOVER_HEIGHT := 90.0
const HOVER_SWAY := 50.0
const CLIMB_TIME := 0.8
const IDLE_BOB := 6.0

var _dive_dir := Vector2.DOWN
var _cooldown := 0.6


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"hover", _hover_tick)
	fsm.add(&"lock", _lock_tick, _lock_enter)
	fsm.add(&"dive", _dive_tick)
	fsm.add(&"climb", _climb_tick)
	fsm.start(&"idle")


func _on_stunned() -> void:
	fsm.transition(&"climb")


func _idle_tick(delta: float) -> void:
	var desired := _home + Vector2(0, sin(_anim_time * 2.0) * IDLE_BOB)
	velocity = velocity.move_toward((desired - global_position) * 3.0, 300.0 * delta)
	if _distance_to_target() <= data.detect_range:
		fsm.transition(&"hover")


func _hover_tick(delta: float) -> void:
	var target := _target()
	if target == null or _distance_to_target() > data.detect_range * 1.5:
		fsm.transition(&"idle")
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var desired := target.global_position + Vector2(sin(_anim_time * 1.6) * HOVER_SWAY, -HOVER_HEIGHT)
	var toward := (desired - global_position).limit_length(data.move_speed)
	velocity = velocity.move_toward(toward, 400.0 * delta)
	_face_target()
	if _cooldown <= 0.0 and _distance_to_target() <= data.attack_range and _has_line_of_sight():
		fsm.transition(&"lock")


func _lock_enter() -> void:
	_start_telegraph(data.telegraph_time)


func _lock_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	_dive_dir = (_target_point() - _center()).normalized()
	if not is_telegraphing():
		fsm.transition(&"dive")


func _dive_tick(_delta: float) -> void:
	velocity = _dive_dir * data.ability_speed
	if fsm.time_in_state >= data.ability_time or get_slide_collision_count() > 0:
		if get_slide_collision_count() > 0:
			Fx.impact(global_position, -_dive_dir, data.color, 6)
		fsm.transition(&"climb")


func _climb_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2(0, -60), 500.0 * delta)
	if fsm.time_in_state >= CLIMB_TIME:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"hover")


func _draw_overlay() -> void:
	if fsm.is_in(&"lock"):
		var color := LightKit.glow(Palette.DANGER, 1.5)
		color.a = 0.25 + 0.5 * (1.0 - _telegraph_left / maxf(0.01, data.telegraph_time))
		var from := to_local(_center())
		draw_line(from, from + _dive_dir * 140.0, color, 1.0)


func _draw_body(color: Color) -> void:
	# 霓虹機械風：鉻金屬機身、旋翼光暈、雙色導航燈。
	var h := data.body_size.y
	var w := data.body_size.x
	var c := Vector2(0, -h * 0.5)
	var blink := fsm.is_in(&"lock") and int(_anim_time * 18.0) % 2 == 0
	var chrome := Color("8d97ab") if not blink else LightKit.glow(Palette.WHITE, 1.8)
	var shell := PackedVector2Array([c + Vector2(-w * 0.5, 0), c + Vector2(-w * 0.3, -h * 0.35), c + Vector2(w * 0.35, -h * 0.35),
			c + Vector2(w * 0.5, 0), c + Vector2(w * 0.3, h * 0.35), c + Vector2(-w * 0.3, h * 0.35)])
	draw_colored_polygon(shell, chrome.darkened(0.35) if color != Palette.WHITE else chrome)
	draw_polyline(shell + PackedVector2Array([shell[0]]), Color("07080d"), 1.0)
	draw_line(c + Vector2(-w * 0.3, -h * 0.2), c + Vector2(w * 0.3, -h * 0.2), chrome.lightened(0.3), 1.0)
	# 旋翼
	var spin := absf(sin(_anim_time * 40.0)) * w * 0.7
	for side: float in [-1.0, 1.0]:
		var hub := c + Vector2(side * w * 0.45, -h * 0.55)
		draw_line(hub + Vector2(-spin * 0.5, 0), hub + Vector2(spin * 0.5, 0), Color(Palette.NEON_PURPLE, 0.7), 1.0)
		draw_arc(hub, w * 0.3, 0.0, TAU, 12, Color(LightKit.glow(Palette.NEON_PURPLE, 1.2), 0.25), 1.0)
	# 眼與導航燈
	var eye := LightKit.glow(Palette.DANGER, 3.2 if is_telegraphing() or fsm.is_in(&"dive") else 1.6)
	draw_circle(c + Vector2(facing * w * 0.22, 1), 2.2, eye)
	draw_circle(c + Vector2(-w * 0.45, 2), 1.0, LightKit.glow(Palette.MAGENTA, 1.6))
	draw_circle(c + Vector2(w * 0.45, 2), 1.0, LightKit.glow(Palette.CYAN, 1.6))
