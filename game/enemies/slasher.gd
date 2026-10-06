extends Enemy
## 切割者（近戰突進）
## 行為：巡邏 → 發現玩家後蹲伏蓄力（刀刃亮起、頭上驚嘆號）→ 朝玩家所在位置撲出一記斬擊 → 落地後有一段硬直。
## 應對：撲出的瞬間用衝刺（無敵）穿過去、或跳起來閃開；在牠斬到你之前完美格擋會讓牠暈眩，可以直接終結；
##       落地硬直是輸出的空檔。數值：ability_speed = 水平速度，ability_time = 硬直秒數，ability_damage = 斬擊傷害。

const LEAP_VELOCITY := 210.0
## 蓄力期間前段追蹤玩家，最後這段比例鎖定方向（讓玩家有時間反應）。
const LOCK_RATIO := 0.65
const MIN_AIR_TIME := 0.12

var _cooldown := 0.4


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"windup", _windup_tick, _windup_enter)
	fsm.add(&"leap", _leap_tick, _leap_enter, _leap_exit)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"patrol")


func _on_stunned() -> void:
	if fsm.is_in(&"windup") or fsm.is_in(&"leap"):
		fsm.transition(&"recover")


func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	if _cooldown <= 0.0 and _token_free() and _can_see_target(data.detect_range, 70.0):
		fsm.transition(&"windup")


func _windup_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_start_telegraph(data.telegraph_time)


func _windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state < data.telegraph_time * LOCK_RATIO:
		_face_target()
	if not is_telegraphing():
		fsm.transition(&"leap")


func _leap_enter() -> void:
	if contact != null:
		contact.damage = maxi(data.contact_damage, data.ability_damage)
		contact.source_id = &"slasher_lunge"
	velocity = Vector2(facing * data.ability_speed, -LEAP_VELOCITY)
	Fx.dust(global_position, 5, 60.0)
	Sfx.play(&"dash", -6.0, 0.15)


func _leap_exit() -> void:
	if contact != null:
		contact.damage = data.contact_damage
		contact.source_id = data.contact_source_id


func _leap_tick(_delta: float) -> void:
	velocity.x = facing * data.ability_speed
	if is_on_wall() or (is_on_floor() and fsm.time_in_state > MIN_AIR_TIME):
		fsm.transition(&"recover")


func _recover_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	if fsm.time_in_state >= data.ability_time:
		_face_target()
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"patrol")


## 骨架外觀：蓄力時蹲伏、刀臂朝後上方；撲出時刀臂朝前。
func _rig_aim() -> Vector2:
	if fsm.is_in(&"windup"):
		return Vector2(-facing * 0.6, -0.8).normalized()
	if fsm.is_in(&"leap"):
		return Vector2(facing, 0.1).normalized()
	return Vector2(facing, 0.9).normalized()


func _rig_state(input: RigInput) -> void:
	input.crouching = fsm.is_in(&"windup")
	input.two_handed = false


func _draw_overlay() -> void:
	if rig != null:
		_draw_blade()
	# 預兆：斬擊軌跡的預告線（蓄力越久越亮）。
	if fsm.is_in(&"windup"):
		var t := clampf(fsm.time_in_state / maxf(0.01, data.telegraph_time), 0.0, 1.0)
		var color := LightKit.glow(Palette.DANGER, 1.0 + 1.2 * t)
		color.a = 0.25 + 0.5 * t
		var from := Vector2(facing * 8.0, -data.body_size.y * 0.55)
		draw_line(from, from + Vector2(facing * 90.0, -30.0), color, 1.0)


## 刀刃：接在骨架的前手上，沿前臂方向延伸；蓄力與撲出時發亮。
func _draw_blade() -> void:
	var armed := fsm.is_in(&"windup") or fsm.is_in(&"leap")
	var hand := rig.bone(&"hand_front")
	var forearm := rig.bone(&"arm_front_lower")
	if hand == null or forearm == null:
		return
	var from := to_local(hand.global_position)
	var along := (hand.global_position - forearm.global_position).normalized()
	var blade := LightKit.glow(Palette.DANGER if armed else Palette.WARNING, 3.0 if armed else 1.2)
	draw_line(from, from + along * 16.0, blade, 2.0)


func _draw_body(color: Color) -> void:
	var f := float(facing)
	var h := data.body_size.y
	var crouch := 6.0 if fsm.is_in(&"windup") else 0.0
	var stride := sin(_anim_time * 12.0) * 3.0 if absf(velocity.x) > 5.0 and is_on_floor() else 0.0
	draw_line(Vector2(-3, -h * 0.4 + crouch), Vector2(-3 + stride, 0), color.darkened(0.45), 3.0)
	draw_line(Vector2(3, -h * 0.4 + crouch), Vector2(3 - stride, 0), color.darkened(0.45), 3.0)
	var torso := Rect2(-5, -h * 0.78 + crouch, 10, h * 0.4)
	draw_rect(torso, color)
	draw_rect(Rect2(torso.position, Vector2(10, 3)), color.lightened(0.2))
	draw_circle(Vector2(f * 1.0, -h * 0.86 + crouch), 4.0, color.darkened(0.3))
	var eye := LightKit.glow(Palette.DANGER, 3.0 if is_telegraphing() else 1.6)
	draw_line(Vector2(f * 1.0, -h * 0.87 + crouch), Vector2(f * 4.5, -h * 0.87 + crouch), eye, 1.5)
	# 刀臂：平時垂在身側；蓄力時舉到身後，撲出時前伸，刀刃發光。
	var shoulder := Vector2(f * 1.0, -h * 0.72 + crouch)
	var armed := fsm.is_in(&"windup") or fsm.is_in(&"leap")
	var tip := shoulder + (Vector2(-f * 8.0, -9.0) if fsm.is_in(&"windup") else (Vector2(f * 15.0, 2.0) if fsm.is_in(&"leap") else Vector2(f * 5.0, 9.0)))
	draw_line(shoulder, tip, Palette.TERRAIN_TOP, 2.0)
	var blade := LightKit.glow(Palette.DANGER if armed else Palette.WARNING, 3.0 if armed else 1.2)
	draw_line(tip, tip + (tip - shoulder).normalized() * 9.0, blade, 2.0)
