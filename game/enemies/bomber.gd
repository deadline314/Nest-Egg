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


## 零件外觀：引信點燃後核心隨倒數越閃越快（和程式繪製版同一個節奏）。
func _draw_creature_extras() -> void:
	if not fsm.is_in(&"fuse"):
		return
	var rate := 10.0 + 30.0 * (1.0 - _telegraph_left / maxf(0.01, data.ability_time))
	if int(_anim_time * rate) % 2 == 0:
		draw_circle(Vector2(float(facing) * 2.0, -9.0), 3.0, Color(LightKit.glow(Palette.WARNING, 3.0), 0.8))


func _draw_body(color: Color) -> void:
	# 霓虹機械風：蜘蛛型自爆機，黃黑警示環、內部核心光隨引信加速閃爍。
	var w := data.body_size.x
	var h := data.body_size.y
	var fusing := fsm.is_in(&"fuse")
	var rate := 10.0 + 30.0 * (1.0 - _telegraph_left / maxf(0.01, data.ability_time))
	var blink := fusing and int(_anim_time * rate) % 2 == 0
	var center := Vector2(0, -h * 0.55)
	var leg := sin(_anim_time * 26.0) * 2.0
	for side: float in [-1.0, 1.0]:
		for i in 2:
			var root := center + Vector2(side * w * 0.2, 2)
			var knee := root + Vector2(side * (w * 0.35 + i * 2.0), -3.0 + leg * (1 if i == 0 else -1))
			var foot := Vector2(side * (w * 0.55 + i * 3.0), 0)
			draw_polyline(PackedVector2Array([root, knee, foot]), Color("3b4256"), 1.5)
	var shell := Color("8d97ab") if color != Palette.WHITE else color
	draw_circle(center, w * 0.45, shell.darkened(0.35))
	draw_arc(center, w * 0.45, 0.0, TAU, 20, Color("07080d"), 1.0)
	draw_arc(center, w * 0.32, 0.0, TAU, 16, Color(Palette.NEON_YELLOW, 0.9), 2.0)
	var core := LightKit.glow(Palette.WARNING, 3.0) if blink else LightKit.glow(Palette.WARNING, 1.4)
	draw_circle(center, w * 0.18, core)
