extends "res://game/enemies/warden_boss.gd"
## 迷你頭目「看守長」（第二章電力室尾，監管者的舊部下）：用監管者的招式，但規模小一號——
## 沒有召喚與扇形彈幕，生命少，沒有過場；玩家靠近前一直睡著，靠近時才出現血條。
## 擊敗後不結束關卡，而是解開通往轉運站的閘門（頻道 GATE_CHANNEL）並收起血條。
## 應對同監管者：點射看眼睛發紅、跳躍震波看下蹲、落地後核心外露時輸出。

const GATE_CHANNEL := &"custodian_gate"
const WAKE_RANGE := 260.0

var _awake := false


func _setup_states() -> void:
	fsm.add(&"dormant", _dormant_tick)
	super()


func _start_state() -> StringName:
	return &"dormant"


## 沒有開場宣告：等玩家靠近才亮血條（見 _wake）。
func _announce() -> void:
	pass


func _uses_activation_culling() -> bool:
	return true


func _dormant_tick(_delta: float) -> void:
	velocity.x = 0.0
	if _can_see_target(WAKE_RANGE, 140.0):
		_wake()


func _wake() -> void:
	if _awake:
		return
	_awake = true
	super._announce()
	EventBus.boss_health_changed.emit(health.current, health.max_health)
	fsm.transition(&"intro")


## 從遠處被打到也會醒（不然遠程武器可以白打一個睡著的頭目）。
func _on_hit(_info: DamageInfo) -> void:
	if not _awake and not _dying:
		_wake()


func _choose_attack() -> StringName:
	var options: Array[StringName] = [&"burst_windup", &"leap_windup"]
	if _phase >= 2:
		options.append(&"fan_windup")
	if options.size() > 1:
		options.erase(_last_attack)
	var choice: StringName = options.pick_random()
	_last_attack = choice
	return choice


func _on_boss_health_changed(current: int, maximum: int) -> void:
	if _awake:
		super._on_boss_health_changed(current, maximum)


func _phase_shift_enter() -> void:
	velocity.x = 0.0
	_start_telegraph(PHASE_SHIFT_TIME)
	Fx.flash_light(_center(), Palette.DANGER, 120.0, 1.6, 0.6)
	EventBus.toast_requested.emit("%s進入暴走狀態" % data.display_name)


## 擊敗：連續小爆炸，然後解開閘門、收起血條（不發出 boss_defeated，關卡繼續）。
func _finish_death() -> void:
	Fx.flash_light(_center(), Palette.WHITE, 160.0, 2.0, 0.5)
	Fx.burst(_center(), Palette.CYAN, 28, 260.0, 0.6)
	Feel.play(&"boss_death")
	EventBus.boss_bar_closed.emit()
	EventBus.mechanism_toggled.emit(_gate_channel(), true)
	EventBus.toast_requested.emit(_unlock_text())
	queue_free()


## 擊敗後解開的閘門頻道與提示；同樣模式的迷你頭目（看門狗）覆寫它們。
func _gate_channel() -> StringName:
	return GATE_CHANNEL


func _unlock_text() -> String:
	return "通往轉運站的閘門已解鎖"
