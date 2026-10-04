extends Enemy
## 井道蝙蝠機（第二章升降井，翼式飛行）：在井道裡上下盤旋，伺機俯衝掠過。
## 行為：倒掛待機 → 發現玩家後在頭頂盤旋（拍翼，轉向時近側翼收攏）→ 雙翼張開顫動、紅眼閃爍（預兆 0.6 秒）→ 沿鎖定方向俯衝（翼向後收攏）→ 滑翔 → 爬升。
##       俯衝撞到牆會暈眩，翼不規則抽動、緩緩下墜。
## 應對：看到翼張開顫動就橫移或衝刺；牠俯衝撞牆暈眩的時候是輸出空檔；被擊落時打轉墜落。

const HOVER_HEIGHT := 80.0
const ORBIT := 110.0
const TURN_TIME := 0.25
const GLIDE_TIME := 0.35
const DIZZY_TIME := 1.0
const CLIMB_TIME := 0.9
const IDLE_BOB := 3.0

var _cooldown := 1.0
var _dive_dir := Vector2.DOWN
var _turn_left := 0.0
var _last_facing := -1


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"hover", _hover_tick)
	fsm.add(&"lock", _lock_tick, _lock_enter)
	fsm.add(&"dive", _dive_tick)
	fsm.add(&"glide", _glide_tick)
	fsm.add(&"dizzy", _dizzy_tick)
	fsm.add(&"climb", _climb_tick)
	fsm.start(&"idle")
	_last_facing = facing


func _on_stunned() -> void:
	fsm.transition(&"climb")


## 轉向時近側翼收攏一下（動畫狀態 turn），其餘狀態用狀態機同名的動畫。
func _creature_state() -> StringName:
	return &"turn" if _turn_left > 0.0 and fsm.is_in(&"hover") else super()


func _creature_aim() -> float:
	return 0.0


func _idle_tick(delta: float) -> void:
	var desired := _home + Vector2(0, sin(_anim_time * 1.4) * IDLE_BOB)
	velocity = velocity.move_toward((desired - global_position) * 3.0, 300.0 * delta)
	if _distance_to_target() <= data.detect_range:
		fsm.transition(&"hover")


func _hover_tick(delta: float) -> void:
	var target := _target()
	if target == null or _distance_to_target() > data.detect_range * 1.5:
		fsm.transition(&"idle")
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_turn_left = maxf(0.0, _turn_left - delta)
	var desired := target.global_position + Vector2(sin(_anim_time * 0.9) * ORBIT, -HOVER_HEIGHT + sin(_anim_time * 2.1) * 14.0)
	var toward := (desired - global_position).limit_length(data.move_speed)
	velocity = velocity.move_toward(toward, 320.0 * delta)
	if absf(velocity.x) > 12.0:
		var heading := 1 if velocity.x > 0.0 else -1
		if heading != facing:
			facing = heading
			_turn_left = TURN_TIME
	if _cooldown <= 0.0 and _distance_to_target() <= data.attack_range and _has_line_of_sight():
		fsm.transition(&"lock")


func _lock_enter() -> void:
	_start_telegraph(data.telegraph_time)


func _lock_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
	_dive_dir = (_target_point() - _center()).normalized()
	_face_target()
	if not is_telegraphing():
		fsm.transition(&"dive")


func _dive_tick(_delta: float) -> void:
	velocity = _dive_dir * data.ability_speed
	facing = 1 if _dive_dir.x >= 0.0 else -1
	if get_slide_collision_count() > 0:
		Fx.impact(global_position, -_dive_dir, data.color, 6)
		velocity = -_dive_dir * 40.0
		fsm.transition(&"dizzy")
	elif fsm.time_in_state >= data.ability_time:
		fsm.transition(&"glide")


func _glide_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2(velocity.x * 0.6, -20.0), 260.0 * delta)
	if fsm.time_in_state >= GLIDE_TIME:
		fsm.transition(&"climb")


func _dizzy_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2(0.0, 60.0), 200.0 * delta)
	if fsm.time_in_state >= DIZZY_TIME:
		fsm.transition(&"climb")


func _climb_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2(velocity.x * 0.5, -data.move_speed), 420.0 * delta)
	if fsm.time_in_state >= CLIMB_TIME:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"hover")


func _draw_overlay() -> void:
	if fsm.is_in(&"lock"):
		var color := LightKit.glow(Palette.DANGER, 1.5)
		color.a = 0.25 + 0.5 * (1.0 - _telegraph_left / maxf(0.01, data.telegraph_time))
		var from := to_local(_center())
		draw_line(from, from + _dive_dir * 150.0, color, 1.0)


## 紅色發光眼：預兆與俯衝時變亮，鎖定時閃白。
func _draw_creature_extras() -> void:
	var blink := fsm.is_in(&"lock") and int(_anim_time * 18.0) % 2 == 0
	var strong := is_telegraphing() or fsm.is_in(&"dive")
	var eye := LightKit.glow(Palette.WHITE if blink else Palette.DANGER, 2.2 if blink else (3.2 if strong else 1.6))
	draw_circle(to_local(creature.muzzle_global("body")), 1.5, eye)


func _draw_body(color: Color) -> void:
	var w := data.body_size.x
	var c := Vector2(0, -data.body_size.y * 0.5)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w * 0.5, 0), c + Vector2(w * 0.2, -3), c + Vector2(w * 0.5, 0), c + Vector2(w * 0.2, 3)]), color)
	draw_circle(c + Vector2(facing * w * 0.35, -1), 1.5, LightKit.glow(Palette.DANGER, 2.0))
