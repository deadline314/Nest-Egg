class_name FuelTank
extends Node2D
## 敵人背後的燃料罐（火焰兵）：有自己的生命與受擊框，被打中夠多次就爆炸。
## 爆炸同時傷害敵人（含背著它的火焰兵與旁邊的燃料罐、油桶）與玩家，規格取自 ProjectileSpec：
## explosion_radius = 半徑，explosion_damage = 對敵人的傷害，damage = 對玩家的傷害，source_id = 敗北圖鑑死因。
## 原點在罐子中心；由持有者每影格呼叫 follow() 擺到背後（面向相反側）。

signal exploded(tank: FuelTank)

const SIZE := Vector2(10, 24)
const FLASH_TIME := 0.1
const EXPLOSION_DELAY := 0.1
const GAUGE_COLOR := Color("ffb020")

var health: HealthComponent
var hurtbox: Hurtbox
var spec: ProjectileSpec
var is_exploded := false

var _flash := 0.0
var _time := randf() * TAU
var _facing := 1


## hits：能承受幾次攻擊；blast：爆炸規格（缺少時只會消失，不爆炸，並記錄錯誤）。
func setup(hits: int, blast: ProjectileSpec) -> void:
	spec = blast
	if blast == null:
		push_error("[FuelTank] 沒有爆炸規格（EnemyData.projectile），燃料罐被打爆時不會爆炸。")
	health = HealthComponent.new()
	add_child(health)
	health.setup(maxi(1, hits), 0.0)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.ENEMY, health, SIZE, Vector2.ZERO)
	LightKit.mark_emissive(self)


func _process(delta: float) -> void:
	_time += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	queue_redraw()


## 擺到持有者背後：facing 是持有者面向（1 右、-1 左）。
func follow(facing: int, offset: Vector2) -> void:
	_facing = facing
	position = Vector2(-facing * offset.x, offset.y)


func world_center() -> Vector2:
	return global_position


func _on_damaged(_info: DamageInfo) -> void:
	_flash = FLASH_TIME
	Fx.impact(global_position, Vector2(-_facing, -0.3), Palette.WARNING, 5)
	Sfx.play(&"hit", -6.0)


func _on_died(_info: DamageInfo) -> void:
	if is_exploded:
		return
	is_exploded = true
	hurtbox.enabled = false
	_explode.call_deferred()


func _explode() -> void:
	if not is_inside_tree():
		return
	var center := global_position
	visible = false
	Fx.burst(center, Palette.WARNING, 24, 170.0, 0.5)
	exploded.emit(self)
	if spec == null:
		return
	# 爆炸比破壞慢一點點，旁邊的燃料罐與油桶才會一顆接一顆炸。
	await get_tree().create_timer(EXPLOSION_DELAY, false).timeout
	if not is_inside_tree():
		return
	Fx.explosion(center, spec.explosion_radius, spec.explosion_damage, Combat.Team.PLAYER, spec.source_id, Palette.WARNING)
	Fx.explosion(center, spec.explosion_radius, spec.damage, Combat.Team.ENEMY, spec.source_id, Palette.WARNING)


func _draw() -> void:
	if is_exploded:
		return
	var rect := Rect2(-SIZE * 0.5, SIZE)
	# 固定在背上的支架：連到持有者的身體（持有者在面向的那一側）。
	for y: float in [-7.0, 6.0]:
		draw_line(Vector2(_facing * SIZE.x * 0.5, y), Vector2(_facing * (SIZE.x * 0.5 + 4.0), y), Color("2a160c"), 2.0)
	var hurt := health != null and health.current < health.max_health
	var base := Color("6b3a22")
	draw_rect(rect, base.darkened(0.35))
	draw_rect(rect.grow(-1.0), base)
	draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(2, rect.size.y - 2)), base.lightened(0.35))
	draw_rect(rect, Color("07080d"), false, 1.0)
	for y: float in [-6.0, 5.0]:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color("2a160c"), 1.5)
	# 壓力表：自帶光，暗處也看得到「這是燃料罐」；受損後閃得更急、帶紅。
	var pulse := 0.6 + 0.4 * sin(_time * (14.0 if hurt else 4.0))
	var gauge := LightKit.glow(Palette.DANGER if hurt else GAUGE_COLOR, 1.4 + 1.6 * pulse)
	draw_circle(Vector2(0, -rect.size.y * 0.5 + 4.0), 1.8, gauge)
	if hurt:
		# 漏油與火花。
		draw_line(Vector2(rect.end.x, 2), Vector2(rect.end.x + 2.5, 6.0 + 2.0 * sin(_time * 20.0)), LightKit.glow(Palette.WARNING, 1.6), 1.0)
	if _flash > 0.0:
		draw_rect(rect, Color(1, 1, 1, 0.6 * _flash / FLASH_TIME))
