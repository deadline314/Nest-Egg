class_name Mimic
extends Enemy
## 偽裝箱（埋伏）
## 行為：平常就是一個貨箱，外殼緊閉，子彈與近戰都傷不了牠（只會讓牠震動、牙齒亮起而現形）；
##       玩家走到 ability_radius 內，箱子先劇烈震動、縫裡透出燈光（預兆），接著彈起來咬人。
##       現形後外殼打開、可以正常受傷，會守在原地：玩家進入 attack_range 就再震動一次、再撲咬。
## 應對：先用子彈試探可疑的箱子（現形但不會動）；爆炸無視外殼，可以直接炸掉；
##       現形後保持距離用槍打；撲咬前完美格擋會讓牠暈眩。
## 數值：ability_radius = 埋伏的觸發距離，attack_range = 現形後撲咬的距離，telegraph_time = 震動預兆，
##       ability_speed = 撲咬水平速度，ability_damage = 撲咬傷害，ability_time = 落地硬直。

const GROUP := &"mimics"
const LEAP_VELOCITY := 250.0
const MIN_AIR_TIME := 0.12
const LOCK_RATIO := 0.7
const TEETH_COLOR := Color(1.0, 0.78, 0.25)
const MAW_COLOR := Color(1.0, 0.2, 0.15)
## 現形的震動：被打到時的短暫震動秒數。
const RATTLE_TIME := 0.6

var _cooldown := 0.0
var _revealed := false
var _lunge_dir := 1.0
var _rattle_left := 0.0
var _light: PointLight2D


func _setup_states() -> void:
	fsm.add(&"dormant", _dormant_tick)
	fsm.add(&"shake", _shake_tick, _shake_enter)
	fsm.add(&"lunge", _lunge_tick, _lunge_enter, _lunge_exit)
	fsm.add(&"recover", _recover_tick)
	fsm.add(&"exposed", _exposed_tick)
	fsm.start(&"dormant")


func _ready() -> void:
	super._ready()
	if data == null:
		return
	add_to_group(GROUP)
	# 偽裝時和貨箱一樣受環境光影響（不自發光），否則會比旁邊的真貨箱亮、露出破綻；現形後才自發光。
	material = null
	if contact != null:
		contact.active = false
	_light = LightKit.create_point_light(TEETH_COLOR, 60.0, 0.0, false, false)
	_light.position = Vector2(0, -data.body_size.y * 0.6)
	_light.enabled = false
	add_child(_light)


func is_disguised() -> bool:
	return not _revealed


## 現形：外殼打開、可以受傷、接觸傷害啟用。
func reveal() -> void:
	if _revealed or is_dying():
		return
	_revealed = true
	if contact != null:
		contact.active = true
	Sfx.play(&"rattle", -4.0)
	Fx.burst(_center() + Vector2(0, -data.body_size.y * 0.3), TEETH_COLOR, 8, 70.0, 0.35)


func _on_stunned() -> void:
	if fsm.is_in(&"shake") or fsm.is_in(&"lunge"):
		fsm.transition(&"recover")


## 外殼緊閉時擋下一般攻擊（爆炸與終結技本來就無視 bypass_guard）；被擋下也會震動現形。
func _guard(_info: DamageInfo) -> Hurtbox.Guard:
	return Hurtbox.Guard.NONE if _revealed else Hurtbox.Guard.BLOCK


func _on_blocked(info: DamageInfo) -> void:
	super._on_blocked(info)
	_rattle_left = RATTLE_TIME
	reveal()


func _on_hit(_info: DamageInfo) -> void:
	_rattle_left = RATTLE_TIME
	reveal()


func _physics_process(delta: float) -> void:
	_rattle_left = maxf(0.0, _rattle_left - delta)
	# 偽裝時受環境光影響、和貨箱一樣暗；一開始震動（預兆）或現形就自發光，暗處也看得清楚。
	material = LightKit.emissive_material() if _revealed or fsm.is_in(&"shake") else null
	if _light != null:
		var glowing := _revealed or _rattle_left > 0.0 or fsm.is_in(&"shake")
		_light.enabled = glowing and not is_dying()
		_light.energy = (0.5 + 0.7 * float(is_telegraphing())) + 0.15 * sin(_anim_time * 25.0)
	super._physics_process(delta)


func _dormant_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	velocity.x = 0.0
	var target := _target()
	if target == null or _cooldown > 0.0:
		return
	var offset := target.global_position - global_position
	if absf(offset.x) <= data.ability_radius and absf(offset.y) <= data.ability_radius + data.body_size.y:
		fsm.transition(&"shake")
	elif _revealed:
		fsm.transition(&"exposed")


func _exposed_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	velocity.x = 0.0
	var target := _target()
	if target == null:
		return
	_face_target()
	var offset := target.global_position - global_position
	if _cooldown <= 0.0 and _token_free() and absf(offset.x) <= data.attack_range and absf(offset.y) <= data.attack_range:
		fsm.transition(&"shake")


func _shake_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_lunge_dir = float(facing)
	_start_telegraph(data.telegraph_time)
	Sfx.play(&"rattle", -2.0)


func _shake_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state < data.telegraph_time * LOCK_RATIO:
		_face_target()
		_lunge_dir = float(facing)
	if int(fsm.time_in_state * 20.0) % 4 == 0:
		Sfx.play(&"rattle", -8.0, 0.15)
	if not is_telegraphing():
		fsm.transition(&"lunge")


func _lunge_enter() -> void:
	reveal()
	if contact != null:
		contact.damage = maxi(data.contact_damage, data.ability_damage)
		contact.source_id = &"mimic_bite"
	velocity = Vector2(_lunge_dir * data.ability_speed, -LEAP_VELOCITY)
	Sfx.play(&"chomp", -2.0)
	Fx.dust(global_position, 5, 50.0)


func _lunge_exit() -> void:
	if contact != null:
		contact.damage = data.contact_damage
		contact.source_id = data.contact_source_id


func _lunge_tick(_delta: float) -> void:
	velocity.x = _lunge_dir * data.ability_speed
	if is_on_wall() or (is_on_floor() and fsm.time_in_state > MIN_AIR_TIME):
		fsm.transition(&"recover")


func _recover_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	if fsm.time_in_state >= data.ability_time:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"exposed")


# ---------------------------------------------------------------------------
# 外觀：和貨箱一模一樣（木板、對角線、鉚釘）；現形後箱蓋掀開，露出牙齒與紅色的口腔
# ---------------------------------------------------------------------------

func _draw_body(color: Color) -> void:
	var w := data.body_size.x
	var h := data.body_size.y
	var shake := 0.0
	if fsm.is_in(&"shake"):
		shake = sin(_anim_time * 70.0) * (1.0 + 2.0 * clampf(fsm.time_in_state / maxf(0.05, data.telegraph_time), 0.0, 1.0))
	elif _rattle_left > 0.0:
		shake = sin(_anim_time * 60.0) * 2.0 * (_rattle_left / RATTLE_TIME)
	var open := _open_amount()
	var rect := Rect2(Vector2(-w * 0.5 + shake, -h), Vector2(w, h))
	var base := color
	if open > 0.0:
		_draw_maw(rect, open)
	# 箱身（下半）
	var body_h := h * (1.0 - 0.3 * open)
	var body := Rect2(Vector2(rect.position.x, -body_h), Vector2(w, body_h))
	draw_rect(body, base.darkened(0.45))
	draw_rect(body.grow(-3.0), base.darkened(0.2))
	draw_rect(body, base.lightened(0.15), false, 1.0)
	var inner := body.grow(-3.0)
	draw_line(inner.position, inner.end, base.darkened(0.55), 2.0)
	draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), base.darkened(0.55), 2.0)
	for corner in [body.position + Vector2(3, 3), Vector2(body.end.x - 3, body.position.y + 3), Vector2(body.position.x + 3, body.end.y - 3), body.end - Vector2(3, 3)]:
		draw_circle(corner, 1.0, base.lightened(0.4))
	# 箱蓋：掀開時向後翻起。
	if open > 0.0:
		var lid_back := Vector2(-_facing_sign() * w * 0.5, -body_h)
		var lid_tip := lid_back + Vector2(-_facing_sign() * 2.0, -h * 0.55 * open)
		draw_line(lid_back + Vector2(shake, 0), lid_tip + Vector2(shake, 0), base.darkened(0.2), 5.0)
		draw_line(lid_back + Vector2(shake, 0), lid_tip + Vector2(shake, 0), base.lightened(0.2), 1.0)
	# 縫裡的光：震動時從縫隙透出，是唯一的破綻。
	if fsm.is_in(&"shake") or _rattle_left > 0.0:
		var seam := LightKit.glow(TEETH_COLOR, 2.4)
		draw_line(Vector2(rect.position.x + 2, -h * 0.5), Vector2(rect.end.x - 2, -h * 0.5), seam, 1.5)


## 零件動畫：現形後的待機與預兆都用張嘴的外觀，偽裝時用緊閉的貨箱。
func _creature_state() -> StringName:
	if fsm.is_in(&"shake") and _revealed:
		return &"shake_open"
	if fsm.is_in(&"dormant") and _revealed:
		return &"exposed"
	return super._creature_state()


func _facing_sign() -> float:
	return float(facing)


## 開口程度 0~1：被打到時震動中的縫隙、現形後完全打開（撲咬時張到最大）。
func _open_amount() -> float:
	if fsm.is_in(&"lunge"):
		return 1.0
	if _revealed:
		return 0.75
	return 0.0


## 口腔：深紅色的內部與上下兩排發光的牙齒。
func _draw_maw(rect: Rect2, open: float) -> void:
	var top := -rect.size.y * (1.0 - 0.3 * open)
	var inside := Rect2(Vector2(rect.position.x + 3.0, top - 2.0), Vector2(rect.size.x - 6.0, 6.0 + 9.0 * open))
	draw_rect(inside, Color("2a0a08"))
	draw_rect(Rect2(inside.position + Vector2(2, 3), Vector2(inside.size.x - 4, inside.size.y - 4)), Color(MAW_COLOR.darkened(0.3), 0.9))
	var teeth := LightKit.glow(TEETH_COLOR, 2.6 if is_telegraphing() or fsm.is_in(&"lunge") else 1.8)
	var count := int(inside.size.x / 5.0)
	for i in count:
		var x := inside.position.x + 2.5 + i * 5.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - 2, inside.position.y + 1), Vector2(x + 2, inside.position.y + 1), Vector2(x, inside.position.y + 5)]), teeth)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 2, inside.end.y - 1), Vector2(x + 2, inside.end.y - 1), Vector2(x, inside.end.y - 5)]), teeth)
