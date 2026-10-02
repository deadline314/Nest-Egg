extends Enemy
## 自爆蟲（突進自爆）
## 行為：發現玩家後高速追擊（遇到矮牆會跳），貼近後閃爍引爆。
## 應對：在牠靠近前擊破；牠被擊破時的爆炸會傷害「周圍的敵人」，可以拿來清場。

const TRIGGER_DISTANCE := 26.0
const HOP_VELOCITY := 230.0
const CHAIN_DAMAGE := 3

var _detonated := false


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"chase", _chase_tick)
	fsm.add(&"fuse", _fuse_tick, _fuse_enter)
	fsm.start(&"idle")


func _idle_tick(_delta: float) -> void:
	velocity.x = 0.0
	if _can_see_target(data.detect_range, 100.0):
		fsm.transition(&"chase")


func _chase_tick(_delta: float) -> void:
	_face_target()
	velocity.x = facing * data.move_speed
	if is_on_floor() and is_on_wall():
		velocity.y = -HOP_VELOCITY
	if _distance_to_target() <= TRIGGER_DISTANCE:
		fsm.transition(&"fuse")


func _fuse_enter() -> void:
	velocity.x = 0.0
	_start_telegraph(data.ability_time)


func _fuse_tick(_delta: float) -> void:
	velocity.x = 0.0
	if not is_telegraphing():
		_detonate()


func _detonate() -> void:
	_detonated = true
	Fx.explosion(_center(), data.ability_radius, data.ability_damage, Combat.Team.ENEMY, &"bomber_blast", data.color)
	health.kill(DamageInfo.create(health.current, Combat.Team.ENEMY, &"self"))


func _on_defeated(_info: DamageInfo) -> void:
	if not _detonated:
		# 被玩家擊破：爆炸只傷害敵人（連鎖清場）。
		Fx.explosion(_center(), data.ability_radius * 1.1, CHAIN_DAMAGE, Combat.Team.PLAYER, &"bomber_chain", Palette.CYAN)


func _draw_body(color: Color) -> void:
	var w := data.body_size.x
	var h := data.body_size.y
	var fusing := fsm.is_in(&"fuse")
	var blink := fusing and int(_anim_time * (10.0 + 30.0 * (1.0 - _telegraph_left / maxf(0.01, data.ability_time)))) % 2 == 0
	var body_color := LightKit.glow(Palette.WARNING, 2.5) if blink else color
	var squish := 1.0 + (sin(_anim_time * 24.0) * 0.1 if fsm.is_in(&"chase") else 0.0)
	draw_circle(Vector2(0, -h * 0.5), w * 0.5 * squish, body_color)
	draw_circle(Vector2(0, -h * 0.5), w * 0.25, LightKit.glow(Palette.WARNING, 1.6))
	var leg := sin(_anim_time * 26.0) * 2.0
	draw_line(Vector2(-w * 0.3, -2), Vector2(-w * 0.5 + leg, 0), color.darkened(0.4), 1.5)
	draw_line(Vector2(w * 0.3, -2), Vector2(w * 0.5 - leg, 0), color.darkened(0.4), 1.5)
