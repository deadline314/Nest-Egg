extends ChainEnemy
## 打撈臂（第一章貨運站淹水區的迷你頭目）：六條觸手交替落腳步行的水下起重機。
## 行為：發現玩家後緩慢逼近；進入範圍時前面兩條觸手放開步態出招——
##   掃地：觸手往後捲起（預兆），然後貼地橫掃；砸地：觸手高舉，落點畫出預告圈，0.7 秒後砸下並震出衝擊。
## 應對：掃地時跳起，砸地時離開圈；每條觸手有自己的生命，打斷越多牠越慢、越低、能出的招越少；
##       六條全斷後洋紅核心露出（傷害加倍、出現弱點標記）並硬直。
## 打斷觸手時優先打前面兩條，可以先拆掉牠的攻擊。

const SWEEP_RANGE := 58.0
const SLAM_RANGE := 140.0
const SWEEP_TIME := 0.6
const SLAM_TIME := 0.5
const SLAM_IMPACT_AT := 0.28
const SLAM_RADIUS := 32.0
const RECOVER_TIME := 0.7
const ARM_COUNT := 2

var _cooldown := 0.0
var _arms := PackedInt32Array()
var _slam_point := Vector2.ZERO
var _slam_done := false
var _use_slam_next := false


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"chase", _chase_tick)
	fsm.add(&"sweep_windup", _windup_tick.bind(&"sweep"), _windup_enter)
	fsm.add(&"sweep", _sweep_tick, _sweep_enter, _attack_exit)
	fsm.add(&"slam_windup", _windup_tick.bind(&"slam"), _slam_windup_enter)
	fsm.add(&"slam", _slam_tick, _slam_enter, _attack_exit)
	fsm.add(&"recover", _recover_tick, _recover_enter)
	fsm.add(&"exposed", _exposed_tick)
	fsm.start(&"idle")


func _idle_tick(_delta: float) -> void:
	velocity.x = 0.0
	if _can_see_target(data.detect_range, 100.0):
		fsm.transition(&"chase")


func _chase_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_face_target()
	velocity.x = facing * _move_speed()
	if is_on_floor() and is_on_wall():
		velocity.x = 0.0
	if chain == null or _cooldown > 0.0 or _front_arms().is_empty():
		return
	var distance := absf(_target_point().x - global_position.x)
	if distance <= SWEEP_RANGE and not _use_slam_next:
		fsm.transition(&"sweep_windup")
	elif distance <= SLAM_RANGE:
		fsm.transition(&"slam_windup")


## 前面的觸手中還活著的前 ARM_COUNT 條（資料裡編號大的在前面；外觀朝左時整個翻過來，所以不用看面向）。
func _front_arms() -> PackedInt32Array:
	var out := PackedInt32Array()
	var count := chain.tentacle_count()
	for k in count:
		var index := count - 1 - k
		if chain.is_alive(index) and out.size() < ARM_COUNT:
			out.append(index)
	return out


func _windup_enter() -> void:
	velocity.x = 0.0
	_arms = _front_arms()
	for index in _arms:
		chain.set_free(index, true)
	_start_telegraph(data.telegraph_time)


func _slam_windup_enter() -> void:
	_windup_enter()
	_slam_done = false
	_slam_point = Vector2(_target_point().x, global_position.y)


func _windup_tick(_delta: float, next: StringName) -> void:
	velocity.x = 0.0
	_face_target()
	if next == &"slam" and is_telegraphing():
		# 預告圈跟著玩家到最後 0.25 秒才鎖定，之後固定在原地（可以閃）。
		if _telegraph_left > 0.25:
			_slam_point = Vector2(_target_point().x, global_position.y)
	if not is_telegraphing():
		fsm.transition(next)


func _sweep_enter() -> void:
	_strike_begin(_arms)
	Fx.flash_light(_center(), data.color, 60.0, 0.8, 0.2)


func _sweep_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= SWEEP_TIME:
		fsm.transition(&"recover")


func _slam_enter() -> void:
	chain.set_aim_point(_slam_point)
	_strike_begin(_arms)


func _slam_tick(_delta: float) -> void:
	velocity.x = 0.0
	chain.set_aim_point(_slam_point)
	if not _slam_done and fsm.time_in_state >= SLAM_IMPACT_AT:
		_slam_done = true
		Fx.explosion(_slam_point + Vector2(0, -4), SLAM_RADIUS, maxi(1, data.ability_damage), Combat.Team.ENEMY, &"salvage_slam", data.color)
		Feel.shake_strength(2.5, 0.15)
	if fsm.time_in_state >= SLAM_TIME:
		fsm.transition(&"recover")


func _attack_exit() -> void:
	_strike_end()


func _recover_enter() -> void:
	velocity.x = 0.0
	for index in _arms:
		chain.set_free(index, false)
	_arms = PackedInt32Array()
	_cooldown = _scaled_cooldown(data.attack_cooldown)
	_use_slam_next = not _use_slam_next


func _recover_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= RECOVER_TIME:
		fsm.transition(&"chase")


func _exposed_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= data.stagger_duration:
		fsm.transition(&"chase")


func _on_tentacle_lost(_index: int) -> void:
	# 出招中被打斷的觸手：判定自動少一條；若前面兩條都沒了，這一招直接結束。
	if (fsm.is_in(&"sweep") or fsm.is_in(&"slam")) and chain.alive_tentacles() == 0:
		fsm.transition(&"recover")


func _on_core_exposed() -> void:
	super()
	_strike_end()
	fsm.transition(&"exposed")


func _on_stunned() -> void:
	_strike_end()
	for index in _arms:
		if chain != null:
			chain.set_free(index, false)
	_arms = PackedInt32Array()
	if fsm.current in [&"sweep_windup", &"slam_windup", &"sweep", &"slam"]:
		fsm.transition(&"recover")


## 砸地預告圈：落點的紅圈，越接近砸下越亮。
func _draw_overlay() -> void:
	if not fsm.is_in(&"slam_windup") and not fsm.is_in(&"slam"):
		return
	var at := to_local(_slam_point) + Vector2(0, -2)
	var progress := 1.0 if fsm.is_in(&"slam") else 1.0 - _telegraph_left / maxf(0.01, data.telegraph_time)
	var color := LightKit.glow(Palette.DANGER, 1.2 + progress)
	color.a = 0.35 + 0.5 * progress
	draw_arc(at, SLAM_RADIUS, 0.0, TAU, 28, color, 1.5)
	draw_arc(at, SLAM_RADIUS * progress, 0.0, TAU, 24, color, 1.0)
