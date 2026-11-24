extends Enemy
## 天穹鎮暴員（盾牌衝鋒）
## 正面伸縮板會擋開子彈與近戰。發現玩家後原地蓄力，接著高速衝撞。
##       撞到牆會暈眩並「盾牌失效」；衝過頭則煞車轉身。
## 應對：跳過或用衝刺（無敵）穿越 → 從背後攻擊，或誘導牠撞牆再輸出；爆炸與終結技無視盾牌。

const SKID_TIME := 0.55
const DAZE_TIME := 1.8
const REST_TIME := 0.6

var _cooldown := 0.0
var _plate := ShieldSurface.new()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var active := _guard_active()
	_plate.update(delta, active, not active, Vector2(float(facing), 0.0), 180.0)
	if is_dying():
		queue_redraw()


func _rig_state(input: RigInput) -> void:
	input.shield_pose_weight = _plate.extension
	input.hand_grip_back = _plate.extension > 0.0


func _guard_active() -> bool:
	return not is_dying() and not is_stunned() and not fsm.is_in(&"dazed")


func _setup_states() -> void:
	if rig != null:
		var carried := rig.contact_surface(&"riot_shield")
		if carried != null:
			carried.hide()
	_plate.parts = [ShieldSurface.PART_EXTENSION, ShieldSurface.PART_DEFLECT]
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
	if not _guard_active():
		return Hurtbox.Guard.NONE
	var from_side := signf(info.origin.x - global_position.x)
	return Hurtbox.Guard.BLOCK if from_side == float(facing) else Hurtbox.Guard.NONE


func _on_blocked(info: DamageInfo) -> void:
	super._on_blocked(info)
	var origin := to_local(_center() + Vector2(facing * data.body_size.x * 0.6, 0))
	var elbow := anchor_node(&"arm_back_lower")
	var hand := anchor_node(&"hand_back")
	var wrist := _plate_wrist(hand, elbow)
	var axis := (wrist - to_local(elbow.global_position)) if elbow != null else Vector2(float(facing), 0.0)
	var mark := _plate.position_on_surface(origin, wrist, axis, facing, Settings.get_feel_scale("shake"))
	_plate.notify_impact(Vector2(float(facing), 0.0), mark)
	Fx.impact(to_global(mark), Vector2(facing, -0.3), Palette.WARNING, 5)


func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	if _cooldown <= 0.0 and _token_free() and _can_see_target(data.detect_range, 40.0):
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
	Feel.play(&"shield_dazed")
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


func _plate_wrist(hand: Node2D, elbow: Node2D) -> Vector2:
	if hand != null and elbow != null:
		return to_local(hand.global_position.lerp(elbow.global_position, 0.22))
	return Vector2(facing * data.body_size.x * 0.55, -data.body_size.y * 0.65)


func _draw_overlay() -> void:
	if _plate.extension <= 0.0:
		return
	var hand := anchor_node(&"hand_back")
	var elbow := anchor_node(&"arm_back_lower")
	var wrist := _plate_wrist(hand, elbow)
	var axis := (wrist - to_local(elbow.global_position)) if elbow != null else Vector2(float(facing), 0.0)
	_plate.paint_emitter(self, wrist, to_local(_center()), 1.0, axis, facing, Settings.get_feel_scale("shake"))
