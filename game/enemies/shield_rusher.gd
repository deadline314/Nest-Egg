extends Enemy
## 盾衛犬（盾牌衝鋒）
## 行為：正面能量盾會彈開子彈與近戰。發現玩家後原地蓄力，接著高速衝撞。
##       撞到牆會暈眩並「盾牌失效」；衝過頭則煞車轉身。
## 應對：跳過或用衝刺（無敵）穿越 → 從背後攻擊，或誘導牠撞牆再輸出；爆炸與終結技無視盾牌。

const SKID_TIME := 0.55
const DAZE_TIME := 1.8
const REST_TIME := 0.6

var _cooldown := 0.0


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"windup", _windup_tick, _windup_enter)
	fsm.add(&"charge", _charge_tick, _charge_enter, _charge_exit)
	fsm.add(&"skid", _skid_tick)
	fsm.add(&"dazed", _dazed_tick, _dazed_enter)
	fsm.start(&"patrol")


func _on_stunned() -> void:
	if fsm.is_in(&"charge") or fsm.is_in(&"windup"):
		fsm.transition(&"skid")


## 正面（面向方向）來的攻擊會被格擋；暈眩時盾牌失效。
func _guard(info: DamageInfo) -> Hurtbox.Guard:
	if fsm.is_in(&"dazed") or is_stunned():
		return Hurtbox.Guard.NONE
	var from_side := signf(info.origin.x - global_position.x)
	return Hurtbox.Guard.BLOCK if from_side == float(facing) else Hurtbox.Guard.NONE


func _on_blocked(info: DamageInfo) -> void:
	super._on_blocked(info)
	Fx.impact(_center() + Vector2(facing * data.body_size.x * 0.6, 0), Vector2(facing, -0.3), Palette.CYAN, 5)


func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	if _cooldown <= 0.0 and _can_see_target(data.detect_range, 40.0):
		fsm.transition(&"windup")


func _windup_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_start_telegraph(data.telegraph_time)


func _windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if not is_telegraphing():
		fsm.transition(&"charge")


func _charge_enter() -> void:
	if contact != null:
		contact.damage = maxi(data.contact_damage, data.ability_damage)
		contact.source_id = &"rusher_charge"
	Fx.dust(global_position, 6, 60.0)


func _charge_exit() -> void:
	if contact != null:
		contact.damage = data.contact_damage
		contact.source_id = data.contact_source_id


func _charge_tick(_delta: float) -> void:
	velocity.x = facing * data.ability_speed
	if int(fsm.time_in_state * 30.0) % 3 == 0:
		Fx.dust(global_position, 1, 20.0)
	if is_on_wall():
		fsm.transition(&"dazed")
	elif fsm.time_in_state >= data.ability_time or (is_on_floor() and _is_ledge_ahead()):
		fsm.transition(&"skid")


func _skid_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, data.ability_speed * 2.0 * delta)
	if fsm.time_in_state >= SKID_TIME:
		_face_target()
		_cooldown = _scaled_cooldown(REST_TIME)
		fsm.transition(&"patrol")


func _dazed_enter() -> void:
	velocity.x = -facing * 80.0
	velocity.y = -120.0
	Fx.shake(3.0, 0.15)
	Fx.impact(_center() + Vector2(facing * 10.0, 0), Vector2(-facing, -0.5), Palette.WARNING, 10)
	Sfx.play(&"block", -2.0, 0.2)


func _dazed_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	if fsm.time_in_state >= DAZE_TIME:
		_face_target()
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"patrol")


func _draw_body(color: Color) -> void:
	var f := float(facing)
	var w := data.body_size.x
	var h := data.body_size.y
	var gait := sin(_anim_time * (22.0 if fsm.is_in(&"charge") else 9.0)) * 2.0
	for x: float in [-w * 0.35, w * 0.3]:
		draw_line(Vector2(x, -4), Vector2(x + gait, 0), color.darkened(0.45), 3.0)
	draw_rect(Rect2(-w * 0.5, -h, w, h - 4), color)
	draw_rect(Rect2(-w * 0.5, -h, w, 3), color.lightened(0.25))
	var eye := LightKit.glow(Palette.DANGER, 3.0 if is_telegraphing() else 1.5)
	draw_circle(Vector2(f * (w * 0.3), -h + 5), 1.6, eye)
	# 能量盾：面向側的發光弧形；暈眩時閃爍熄滅。
	var dazed := fsm.is_in(&"dazed")
	if not dazed or int(_anim_time * 12.0) % 2 == 0:
		var shield := LightKit.glow(Palette.CYAN, 0.6 if dazed else 2.2)
		shield.a = 0.35 if dazed else 0.9
		var center := Vector2(f * (w * 0.5 + 2.0), -h * 0.5)
		var start := -PI * 0.5 if f > 0.0 else PI * 0.5
		draw_arc(center, h * 0.6, start, start + PI * f, 10, shield, 2.0)
