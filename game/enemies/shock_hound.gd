class_name ShockHound
extends Enemy
## 電擊犬（成群突襲）
## 行為：成群巡邏；第一隻發現玩家就低吼、前爪刨地（身體壓低、電弧在身上亂竄）並呼喚同伴；
##       蓄力結束朝玩家所在位置撲咬（接觸電擊），落地後硬直。同伴的蓄力會錯開，不會同時撲上來。
##       牠們跳不高：玩家站得比 ability_radius 更高（站上平台）就撲不到，只會在底下低吼打轉。
## 應對：站上平台；用範圍武器（霰彈、榴彈）一次清一群；撲出的瞬間完美格擋會讓牠暈眩，
##       或用衝刺穿過去；落地硬直是輸出的空檔。
## 數值：detect_range = 發現距離，attack_range = 開始蓄力的距離，telegraph_time = 低吼蓄力，
##       ability_speed = 撲咬的水平速度，ability_time = 落地硬直，ability_damage = 撲咬傷害，
##       ability_radius = 撲得到的最大高度（玩家腳比牠的腳高過這個值就不撲）。

const GROUP := &"shock_hounds"
const LEAP_VELOCITY := 190.0
const MIN_AIR_TIME := 0.1
## 同伴的蓄力錯開的時間（秒）、呼喚同伴的距離與戒備秒數。
const PACK_STAGGER := 0.45
const PACK_RADIUS := 260.0
const PACK_ALERT_TIME := 4.0
const LOCK_RATIO := 0.7
const BARK_INTERVAL := 1.6
const ARC_COLOR := Color(0.55, 0.9, 1.0)

var _cooldown := 0.3
var _lunge_dir := 1.0
var _bark_left := 0.0
var _arcs: Array[PackedVector2Array] = []


func _setup_states() -> void:
	fsm.add(&"prowl", _prowl_tick)
	fsm.add(&"growl", _growl_tick, _growl_enter)
	fsm.add(&"pounce", _pounce_tick, _pounce_enter, _pounce_exit)
	fsm.add(&"recover", _recover_tick)
	fsm.add(&"circle", _circle_tick)
	fsm.start(&"prowl")


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)


## 玩家現在撲不撲得到：腳的高度差不超過 ability_radius。
func can_reach_target() -> bool:
	var target := _target()
	return target != null and global_position.y - target.global_position.y <= data.ability_radius


func _on_stunned() -> void:
	if fsm.is_in(&"growl") or fsm.is_in(&"pounce"):
		fsm.transition(&"recover")


func _on_defeated(_info: DamageInfo) -> void:
	remove_from_group(GROUP)


func _prowl_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not _can_see_target(data.detect_range, 160.0):
		_patrol(data.move_speed * 0.7)
		return
	_face_target()
	if not can_reach_target():
		fsm.transition(&"circle")
		return
	var distance := _distance_to_target()
	if distance > data.attack_range and not (is_on_floor() and _is_ledge_ahead()):
		velocity.x = facing * data.move_speed
	else:
		velocity.x = 0.0
	if _cooldown <= 0.0 and distance <= data.attack_range:
		fsm.transition(&"growl")


## 玩家站得太高：在底下來回踱步、低吼，不撲。玩家下來或離開就回到巡邏。
func _circle_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not _can_see_target(data.detect_range, 260.0) or can_reach_target():
		fsm.transition(&"prowl")
		return
	_face_target()
	var distance_x := absf(_target().global_position.x - global_position.x)
	velocity.x = facing * data.move_speed * 0.6 if distance_x > 24.0 else sin(_anim_time * 4.0) * 14.0
	_bark_left -= delta
	if _bark_left <= 0.0:
		_bark_left = BARK_INTERVAL
		Sfx.play(&"growl", -10.0, 0.1)


func _growl_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_lunge_dir = float(facing)
	_start_telegraph(data.telegraph_time)
	Sfx.play(&"growl", -4.0)
	_call_pack()
	_build_arcs()


## 呼喚同伴：附近還在巡邏的同伴進入戒備，蓄力的時間依序錯開。
func _call_pack() -> void:
	var rank := 0
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as ShockHound
		if other == null or other == self or other.is_dying() or other.global_position.distance_to(global_position) > PACK_RADIUS:
			continue
		other.raise_alert(_target_point(), PACK_ALERT_TIME)
		if other.fsm.is_in(&"prowl") or other.fsm.is_in(&"circle"):
			rank += 1
			other._cooldown = maxf(other._cooldown, PACK_STAGGER * rank)


func _growl_tick(_delta: float) -> void:
	velocity.x = 0.0
	# 前段追蹤玩家，後段鎖定方向（給玩家反應時間）。
	if fsm.time_in_state < data.telegraph_time * LOCK_RATIO:
		_face_target()
		_lunge_dir = float(facing)
	if int(fsm.time_in_state * 24.0) % 2 == 0:
		_build_arcs()
	if not is_telegraphing():
		fsm.transition(&"pounce")


func _pounce_enter() -> void:
	if contact != null:
		contact.damage = maxi(data.contact_damage, data.ability_damage)
		contact.source_id = &"shock_hound_pounce"
	velocity = Vector2(_lunge_dir * data.ability_speed, -LEAP_VELOCITY)
	Fx.dust(global_position, 4, 40.0)
	Sfx.play(&"zap", -6.0, 0.1)


func _pounce_exit() -> void:
	if contact != null:
		contact.damage = data.contact_damage
		contact.source_id = data.contact_source_id


func _pounce_tick(_delta: float) -> void:
	velocity.x = _lunge_dir * data.ability_speed
	if is_on_wall() or (is_on_floor() and fsm.time_in_state > MIN_AIR_TIME):
		fsm.transition(&"recover")


func _recover_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	if fsm.time_in_state >= data.ability_time:
		_face_target()
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"prowl")


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

func _build_arcs() -> void:
	_arcs.clear()
	var w := data.body_size.x
	var h := data.body_size.y
	for i in 3:
		var points := PackedVector2Array()
		var at := Vector2(randf_range(-w * 0.5, w * 0.5), -randf_range(h * 0.2, h))
		points.append(at)
		for k in 3:
			at += Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 3.0))
			points.append(at)
		_arcs.append(points)


func _draw_overlay() -> void:
	if fsm.is_in(&"growl"):
		# 電弧在身上亂竄，蓄力越久越亮。
		var t := clampf(fsm.time_in_state / maxf(0.05, data.telegraph_time), 0.0, 1.0)
		var color := LightKit.glow(ARC_COLOR, 1.5 + 2.0 * t)
		for points in _arcs:
			draw_polyline(points, color, 1.0)
	elif fsm.is_in(&"pounce"):
		var trail := LightKit.glow(ARC_COLOR, 2.0)
		trail.a = 0.6
		draw_line(Vector2(-_lunge_dir * 14.0, -data.body_size.y * 0.5), Vector2(-_lunge_dir * 26.0, -data.body_size.y * 0.5), trail, 1.5)


func _draw_body(color: Color) -> void:
	# 機械犬：低伏的長身、四條腿、頭與電極尾；蓄力時身體壓低、前爪刨地。
	var f := float(facing)
	var w := data.body_size.x
	var h := data.body_size.y
	var growl := fsm.is_in(&"growl")
	var airborne := fsm.is_in(&"pounce")
	var crouch := 3.0 if growl else 0.0
	var run := sin(_anim_time * (16.0 if absf(velocity.x) > 20.0 else 4.0)) * (3.0 if absf(velocity.x) > 5.0 else 0.0)
	var leg := color.darkened(0.5)
	# 後腿、前腿（蓄力時前腿來回刨地）。
	var scrape := sin(_anim_time * 28.0) * 3.5 if growl else run
	draw_line(Vector2(-f * w * 0.32, -h * 0.5 + crouch), Vector2(-f * w * 0.32 - run, 0), leg, 2.5)
	draw_line(Vector2(-f * w * 0.1, -h * 0.5 + crouch), Vector2(-f * w * 0.1 + run, 0), leg, 2.5)
	draw_line(Vector2(f * w * 0.2, -h * 0.5 + crouch), Vector2(f * w * 0.2 + (f * 4.0 if airborne else scrape), 0 if not airborne else -3.0), leg, 2.5)
	draw_line(Vector2(f * w * 0.38, -h * 0.5 + crouch), Vector2(f * w * 0.38 + (f * 5.0 if airborne else -scrape), 0 if not airborne else -3.0), leg, 2.5)
	# 身體與頭。
	var body := Rect2(-w * 0.5, -h * 0.95 + crouch, w * 0.8, h * 0.55)
	draw_rect(body, color.darkened(0.15))
	draw_rect(Rect2(body.position, Vector2(body.size.x, 2.0)), color.lightened(0.25))
	var head_c := Vector2(f * w * 0.42, -h * 0.78 + crouch + (2.0 if growl else 0.0))
	draw_circle(head_c, h * 0.36, color)
	draw_rect(Rect2(head_c.x + (f * h * 0.1 if f > 0.0 else -h * 0.4), head_c.y - 1.0, h * 0.3, 4.0), color.darkened(0.3))
	# 眼睛（自發光）與電極尾。
	draw_circle(head_c + Vector2(f * 3.0, -2.0), 1.5, LightKit.glow(Palette.NEON_YELLOW, 3.4 if is_telegraphing() else 2.0))
	var tail := Vector2(-f * w * 0.5, -h * 0.85 + crouch)
	draw_line(tail, tail + Vector2(-f * 5.0, -5.0), leg, 1.5)
	draw_circle(tail + Vector2(-f * 5.0, -5.0), 1.4, LightKit.glow(ARC_COLOR, 2.4 if growl else 1.4))
	if growl or airborne:
		# 張開的嘴：牙齒閃光。
		draw_line(head_c + Vector2(f * 5.0, 2.0), head_c + Vector2(f * 9.0, 3.0), LightKit.glow(Palette.WHITE, 2.6), 1.5)
