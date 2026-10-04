extends ChainEnemy
## 雲母（第三章，懸浮）：漂浮的水母形機器，鐘罩一縮一放地推進，下面拖著六條帶電的觸鬚。
## 行為：緩緩漂向玩家，停在頭頂上方 → 鐘罩收緊發亮、觸鬚展開（預兆 0.9 秒）→ 放電，觸鬚朝下鞭打一圈 → 繼續漂浮。
## 應對：看到鐘罩收緊就離開正下方；打斷觸鬚能削弱放電範圍，六條全斷後鐘罩核心露出（傷害提高並硬直）。
## 觸鬚只在放電時有傷害，平常漂浮時碰到只有鐘罩的接觸傷害。

const HOVER_HEIGHT := 70.0
const PULSE_PERIOD := 1.25
const PULSE_KICK := 34.0
const DISCHARGE_TIME := 0.6
const RECOVER_TIME := 0.6
const DRAG := 60.0

var _cooldown := 1.0
var _pulse_left := 0.0


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"drift", _drift_tick)
	fsm.add(&"charge", _charge_tick, _charge_enter)
	fsm.add(&"discharge", _discharge_tick, _discharge_enter, _discharge_exit)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"idle")


func _idle_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2(0.0, sin(_anim_time * 1.2) * 6.0), DRAG * delta)
	if _distance_to_target() <= data.detect_range:
		fsm.transition(&"drift")


func _drift_tick(delta: float) -> void:
	var target := _target()
	if target == null or _distance_to_target() > data.detect_range * 1.5:
		fsm.transition(&"idle")
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	# 每個脈動週期鐘罩收縮一次，往目標方向推一下，之間被阻力慢下來。
	_pulse_left -= delta
	var goal := target.global_position + Vector2(0.0, -HOVER_HEIGHT) - global_position
	if _pulse_left <= 0.0:
		_pulse_left = PULSE_PERIOD
		velocity += goal.normalized() * PULSE_KICK
	velocity = velocity.limit_length(_move_speed() * 1.6).move_toward(Vector2.ZERO, DRAG * delta)
	_face_target()
	if _cooldown <= 0.0 and absf(goal.x) < 40.0 and _distance_to_target() <= data.attack_range:
		fsm.transition(&"charge")


func _charge_enter() -> void:
	_start_telegraph(data.telegraph_time)


func _charge_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 200.0 * delta)
	if not is_telegraphing():
		fsm.transition(&"discharge")


func _discharge_enter() -> void:
	var all := PackedInt32Array()
	for i in chain.tentacle_count():
		if chain.is_alive(i):
			all.append(i)
	_strike_begin(all)
	Fx.flash_light(_center(), Palette.CYAN, 70.0, 1.0, 0.2)
	Fx.sparks(_center(), Palette.CYAN, 8, 160.0, 0.3)


func _discharge_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 200.0 * delta)
	if fsm.time_in_state >= DISCHARGE_TIME:
		fsm.transition(&"recover")


func _discharge_exit() -> void:
	_strike_end()


func _recover_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 200.0 * delta)
	if fsm.time_in_state >= RECOVER_TIME:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"drift")


func _on_stunned() -> void:
	_strike_end()
	fsm.transition(&"drift")


## 充電時鐘罩下緣一圈青光越來越亮。
func _draw_overlay() -> void:
	if not fsm.is_in(&"charge"):
		return
	var progress := 1.0 - _telegraph_left / maxf(0.01, data.telegraph_time)
	var glow := LightKit.glow(Palette.CYAN, 1.0 + 2.0 * progress)
	glow.a = 0.3 + 0.5 * progress
	draw_arc(Vector2(0.0, -data.body_size.y * 0.15), data.body_size.x * 0.55, 0.0, PI, 14, glow, 1.5)
