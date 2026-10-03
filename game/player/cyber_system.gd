class_name CyberSystem
extends Node2D
## 玩家的義體能力：義體電量、冷卻、效果。裝備的能力由 Progression 決定，能力內容是資料（CyberAbilityData）。
## 電量隨時間回復，擊敗敵人額外回復；使用消耗電量並進入冷卻。
##   超頻：持續一段時間加快射速、換彈與移動（Player 讀 fire_rate_scale 等倍率）。
##   電磁脈衝：瞬間癱瘓範圍內的敵人並消除敵方子彈。
## 狀態透過 EventBus.player_cyber_changed 通知 HUD（HUD 不持有玩家參照）。

const MAX_CHARGE := 100.0
const START_CHARGE := 50.0
const CHARGE_PER_SECOND := 2.5
const CHARGE_PER_KILL := 12.0
## 超頻時移動速度的加成相對於射速加成的比例。
const MOVE_BONUS_RATIO := 0.375
## 回報給 HUD 的最小電量變化，避免每影格發訊號。
const REPORT_STEP := 0.5

signal activated(ability: CyberAbilityData)

var player: Player
var charge := START_CHARGE
var _ability: CyberAbilityData
var _cooldown_left := 0.0
var _active_left := 0.0
var _reported_charge := -1.0
var _reported_state := -1
var _time := 0.0


func _ready() -> void:
	LightKit.mark_emissive(self)
	position = Vector2(0, -22)
	_ability = Progression.equipped_ability()
	Progression.abilities_changed.connect(_on_abilities_changed)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	_report(true)


func _exit_tree() -> void:
	if Progression.abilities_changed.is_connected(_on_abilities_changed):
		Progression.abilities_changed.disconnect(_on_abilities_changed)
	if EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.disconnect(_on_enemy_killed)


func _physics_process(delta: float) -> void:
	_time += delta
	if _ability == null:
		return
	var was_ready := is_ready()
	charge = minf(MAX_CHARGE, charge + CHARGE_PER_SECOND * delta)
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _active_left > 0.0:
		_active_left = maxf(0.0, _active_left - delta)
		queue_redraw()
	if is_ready() and not was_ready:
		Sfx.play(&"ability_ready", -10.0)
	_report(false)


func ability() -> CyberAbilityData:
	return _ability


## 可以使用嗎（有能力、電量夠、不在冷卻中、玩家還活著）。
func is_ready() -> bool:
	return _ability != null and charge >= _ability.charge_cost and _cooldown_left <= 0.0


## 回傳不能使用的原因（空字串代表可以）。
func block_reason() -> String:
	if _ability == null:
		return "還沒有裝備義體能力（背包的「義體」分頁）"
	if player == null or player.is_dead() or player.state == Player.State.MOUNTED:
		return "現在不能使用"
	if _cooldown_left > 0.0:
		return "%s 冷卻中（%.1f 秒）" % [_ability.display_name, _cooldown_left]
	if charge < _ability.charge_cost:
		return "義體電量不足"
	return ""


func try_activate() -> bool:
	if not block_reason().is_empty():
		return false
	charge -= _ability.charge_cost
	_cooldown_left = _ability.cooldown
	match _ability.kind:
		CyberAbilityData.Kind.OVERCLOCK:
			_active_left = _ability.duration
		CyberAbilityData.Kind.EMP:
			_emit_pulse()
	Sfx.play(_ability.sound, -2.0)
	Fx.burst(global_position, _ability.color, 14, 140.0, 0.4)
	activated.emit(_ability)
	_report(true)
	queue_redraw()
	return true


func is_overclocked() -> bool:
	return _active_left > 0.0 and _ability != null and _ability.kind == CyberAbilityData.Kind.OVERCLOCK


## 射速與換彈速度倍率（超頻中 > 1）。
func fire_rate_scale() -> float:
	return 1.0 + _ability.magnitude if is_overclocked() else 1.0


func reload_speed_scale() -> float:
	return fire_rate_scale()


func move_speed_scale() -> float:
	return 1.0 + _ability.magnitude * MOVE_BONUS_RATIO if is_overclocked() else 1.0


## 電磁脈衝：範圍內的敵人暈眩、敵方子彈消除；頭目只消除彈幕。
func _emit_pulse() -> void:
	var center := global_position
	var stunned := 0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dying() or enemy.global_position.distance_to(center) > _ability.radius:
			continue
		if not enemy.data.is_boss:
			enemy.stun(_ability.duration)
			stunned += 1
	ProjectilePool.clear_in_radius(center, _ability.radius, Combat.Team.ENEMY)
	var pulse := EmpPulse.new()
	pulse.radius = _ability.radius
	pulse.color = _ability.color
	pulse.position = center
	if player != null and player.get_parent() != null:
		player.get_parent().add_child(pulse)
	Fx.shake(3.0, 0.2)
	Fx.flash_light(center, _ability.color, _ability.radius * 1.4, 2.0, 0.3)


func _on_enemy_killed(_enemy_id: StringName, _by_finisher: bool) -> void:
	charge = minf(MAX_CHARGE, charge + CHARGE_PER_KILL)


func _on_abilities_changed() -> void:
	_ability = Progression.equipped_ability()
	_cooldown_left = 0.0
	_active_left = 0.0
	_report(true)


## 讓 HUD 知道目前的電量與狀態。progress：超頻中為剩餘時間比例，冷卻中為冷卻進度，其餘為 1。
func _report(force: bool) -> void:
	var state := 0 if _ability == null else (1 if is_ready() else 2)
	if not force and absf(charge - _reported_charge) < REPORT_STEP and state == _reported_state and _active_left <= 0.0 and _cooldown_left <= 0.0:
		return
	_reported_charge = charge
	_reported_state = state
	var progress := 1.0
	if _ability != null:
		if _active_left > 0.0:
			progress = _active_left / maxf(0.01, _ability.duration)
		elif _cooldown_left > 0.0:
			progress = 1.0 - _cooldown_left / maxf(0.01, _ability.cooldown)
	EventBus.player_cyber_changed.emit(charge, is_ready(), _ability.display_name if _ability != null else "", progress)


func _draw() -> void:
	if not is_overclocked():
		return
	# 超頻中：身體外圍旋轉的洋紅光弧。
	var pulse := 0.6 + 0.4 * sin(_time * 12.0)
	var color := LightKit.glow(_ability.color, 1.4 + pulse)
	color.a = 0.8
	for i in 3:
		var start := _time * 6.0 + i * TAU / 3.0
		draw_arc(Vector2.ZERO, 22.0, start, start + 0.9, 8, color, 1.5)


## 電磁脈衝的視覺：向外擴散的圓環與內部填色。
class EmpPulse:
	extends Node2D

	const DURATION := 0.45

	var radius := 150.0
	var color := Color(0.35, 0.88, 1.0)
	var _age := 0.0

	func _ready() -> void:
		LightKit.mark_emissive(self)
		z_index = 6

	func _process(delta: float) -> void:
		_age += delta
		if _age >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := clampf(_age / DURATION, 0.0, 1.0)
		var r := radius * (0.2 + 0.8 * t)
		draw_circle(Vector2.ZERO, r, Color(color, 0.16 * (1.0 - t)))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(LightKit.glow(color, 2.2), 1.0 - t), 2.0)
		draw_arc(Vector2.ZERO, r * 0.7, 0.0, TAU, 40, Color(color, 0.5 * (1.0 - t)), 1.0)
