class_name Breakable
extends StaticBody2D
## 可破壞物件（木箱、油桶、玻璃牆）：擋路也擋敵人的子彈，被玩家的子彈、近戰或爆炸打破。
## 外觀、血量、爆炸與掉落都由 BreakableData 決定。破壞後節點保留但停用（狀態才能存進檢查點）。
## 原點在底邊中點。

## 破壞後發出，關卡負責生成掉落物。
signal broken(breakable: Breakable)

const FLASH_TIME := 0.12
## 爆炸比破壞慢一點點，連鎖的油桶才會一個接一個炸。
const EXPLOSION_DELAY := 0.12
const HURTBOX_PADDING := 4.0
const PROMPT_RADIUS := 72.0

var data: BreakableData
## 所在格（腳底那格），狀態 key 與掉落亂數的種子。
var cell := Vector2i.ZERO
var is_broken := false
var size_px := Vector2(32, 32)
var health: HealthComponent
var hurtbox: Hurtbox

var _flash := 0.0
var _shape_node: CollisionShape2D
var _rim: _Rim
var _prompt: WorldPrompt


func configure(p_data: BreakableData, p_cell: Vector2i, tile_size: int) -> void:
	data = p_data
	cell = p_cell
	size_px = Vector2(data.size_tiles) * tile_size


func _ready() -> void:
	if data == null:
		push_error("[Breakable] 未指定 BreakableData，已移除。")
		queue_free()
		return
	collision_layer = Layers.WORLD
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = size_px
	_shape_node = CollisionShape2D.new()
	_shape_node.shape = shape
	_shape_node.position = Vector2(0, -size_px.y * 0.5)
	add_child(_shape_node)

	health = HealthComponent.new()
	add_child(health)
	health.setup(data.max_health, 0.0)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.ENEMY, health, size_px + Vector2.ONE * HURTBOX_PADDING, Vector2(0, -size_px.y * 0.5))

	_rim = _Rim.new()
	_rim.owner_breakable = self
	add_child(_rim)
	LightKit.mark_emissive(_rim)
	if not data.hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = data.hint
		_prompt.radius = PROMPT_RADIUS
		_prompt.offset = Vector2(0, -size_px.y - 10.0)
		add_child(_prompt)
	add_to_group(WorldState.GROUP)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()


## 子彈撞上本體時由 Projectile 呼叫；回傳 Hurtbox.Result（敵方子彈會被忽略但仍被擋下）。
func hit_by_projectile(info: DamageInfo) -> int:
	return hurtbox.receive(info) if not is_broken else Hurtbox.Result.IGNORED


## 破壞時的掉落：回傳 { "resource": WeaponData/ConsumableData 或 null, "health": bool }。
## 以位置為種子，所以從檢查點重生後同一個箱子掉的東西一樣。
func roll_drop() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s@%d,%d" % [data.id, cell.x, cell.y])
	var result := {"resource": null, "health": false}
	if not data.drops.is_empty() and rng.randf() < data.drop_chance:
		result["resource"] = data.drops[rng.randi() % data.drops.size()]
	elif rng.randf() < data.health_drop_chance:
		result["health"] = true
	return result


func world_center() -> Vector2:
	return global_position + Vector2(0, -size_px.y * 0.5)


func _on_damaged(_info: DamageInfo) -> void:
	_flash = FLASH_TIME
	Fx.impact(world_center(), Vector2.UP, data.color.lightened(0.3), 4)
	Sfx.play(&"hit", -8.0)
	queue_redraw()


func _on_died(_info: DamageInfo) -> void:
	if is_broken:
		return
	is_broken = true
	_shatter.call_deferred()


## 破壞：停用碰撞、播放效果、爆炸、通知關卡生成掉落物。
func _shatter() -> void:
	if not is_inside_tree():
		return
	var center := world_center()
	var big := data.look == BreakableData.Look.GLASS
	Fx.burst(center, Palette.CYAN if big else data.color.lightened(0.2), 22 if big else 14, 150.0, 0.5)
	Fx.impact(center, Vector2.UP, data.color.lightened(0.3), 8)
	Fx.shake(2.5, 0.15)
	Sfx.play(&"glass_break" if big else &"crate_break", -2.0)
	_disable()
	broken.emit(self)
	if data.is_explosive():
		await get_tree().create_timer(EXPLOSION_DELAY, false).timeout
		if is_inside_tree():
			_explode(center)


## 同時傷害敵人（玩家陣營的爆炸）與玩家（敵人陣營的爆炸）。
func _explode(center: Vector2) -> void:
	Fx.explosion(center, data.explosion_radius, data.explosion_damage, Combat.Team.PLAYER, data.explosion_source_id, Palette.WARNING)
	Fx.explosion(center, data.explosion_radius, data.explosion_damage, Combat.Team.ENEMY, data.explosion_source_id, Palette.WARNING)


func _disable() -> void:
	visible = false
	set_process(false)
	_shape_node.set_deferred(&"disabled", true)
	hurtbox.enabled = false
	if _prompt != null:
		_prompt.enabled = false


# ---------------------------------------------------------------------------
# 檢查點狀態（WorldState）
# ---------------------------------------------------------------------------

func state_key() -> String:
	return "breakable@%d,%d" % [cell.x, cell.y]


func capture_state() -> Variant:
	return is_broken


## 還原成已破壞：不播放效果、不爆炸、不掉落（掉落物是一次性的，重生後不再出現）。
func restore_state(state: Variant) -> void:
	if state == true and not is_broken:
		is_broken = true
		health.kill(DamageInfo.create(0, Combat.Team.PLAYER, &"restore"))
		_disable()


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

func _draw() -> void:
	if data == null:
		return
	var rect := Rect2(Vector2(-size_px.x * 0.5, -size_px.y), size_px)
	match data.look:
		BreakableData.Look.CRATE:
			_draw_crate(rect)
		BreakableData.Look.BARREL:
			_draw_barrel(rect)
		BreakableData.Look.GLASS:
			_draw_glass(rect)
	_draw_cracks(rect)
	if _flash > 0.0:
		draw_rect(rect, Color(1, 1, 1, 0.55 * _flash / FLASH_TIME))


func _draw_crate(rect: Rect2) -> void:
	draw_rect(rect, data.color.darkened(0.45))
	draw_rect(rect.grow(-3.0), data.color.darkened(0.2))
	draw_rect(rect, data.color.lightened(0.15), false, 1.0)
	var inner := rect.grow(-3.0)
	draw_line(inner.position, inner.end, data.color.darkened(0.55), 2.0)
	draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), data.color.darkened(0.55), 2.0)
	for corner in [rect.position + Vector2(3, 3), Vector2(rect.end.x - 3, rect.position.y + 3), Vector2(rect.position.x + 3, rect.end.y - 3), rect.end - Vector2(3, 3)]:
		draw_circle(corner, 1.0, data.color.lightened(0.4))


func _draw_barrel(rect: Rect2) -> void:
	var body := Color(0.55, 0.16, 0.14)
	draw_rect(rect, body.darkened(0.3))
	draw_rect(Rect2(rect.position + Vector2(2, 0), Vector2(rect.size.x * 0.35, rect.size.y)), body)
	draw_rect(rect, Color(0.12, 0.05, 0.05), false, 1.0)
	for fraction in [0.2, 0.8]:
		var y: float = rect.position.y + rect.size.y * fraction
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), body.darkened(0.55), 2.0)
	# 易燃標誌：黃底三角。
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y) * 0.22
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, s * 0.8), c + Vector2(-s, s * 0.8)]), Palette.WARNING.darkened(0.15))
	draw_rect(Rect2(c + Vector2(-0.5, -s * 0.3), Vector2(1, s * 0.7)), Color(0.1, 0.05, 0.02))


func _draw_glass(rect: Rect2) -> void:
	draw_rect(rect, Color(0.25, 0.7, 0.85, 0.16))
	draw_rect(rect, Color(Palette.CYAN, 0.35), false, 1.0)
	var y := rect.position.y + 6.0
	while y < rect.end.y:
		draw_line(Vector2(rect.position.x + 2, y + 6), Vector2(rect.end.x - 2, y), Color(1, 1, 1, 0.10), 1.0)
		y += 18.0


func _draw_cracks(rect: Rect2) -> void:
	if health == null or data.max_health <= 1:
		return
	var ratio := health.ratio()
	var color := Color(0.03, 0.03, 0.05, 0.9) if data.look != BreakableData.Look.GLASS else Color(1, 1, 1, 0.7)
	if ratio < 0.7:
		var p := rect.get_center()
		draw_polyline(PackedVector2Array([p + Vector2(-5, -rect.size.y * 0.3), p + Vector2(0, -3), p + Vector2(4, 2), p + Vector2(1, rect.size.y * 0.3)]), color, 1.0)
	if ratio < 0.4:
		var p2 := rect.get_center()
		draw_polyline(PackedVector2Array([p2 + Vector2(rect.size.x * 0.3, -6), p2 + Vector2(2, 0), p2 + Vector2(-rect.size.x * 0.3, 7)]), color, 1.0)


## 自發光的輪廓：暗處也看得到「這個可以打」。
class _Rim:
	extends Node2D

	var owner_breakable: Breakable

	func _draw() -> void:
		if owner_breakable == null or owner_breakable.data == null:
			return
		var b := owner_breakable
		var rect := Rect2(Vector2(-b.size_px.x * 0.5, -b.size_px.y), b.size_px)
		match b.data.look:
			BreakableData.Look.GLASS:
				draw_rect(rect, Color(Palette.CYAN, 0.55), false, 1.0)
				draw_line(rect.position + Vector2(2, 2), rect.position + Vector2(2, minf(rect.size.y - 2.0, 14.0)), LightKit.glow(Palette.CYAN, 1.6), 1.0)
			BreakableData.Look.BARREL:
				draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(Palette.WARNING, 0.85), 1.0)
				draw_rect(Rect2(rect.get_center() + Vector2(-1, -1), Vector2(2, 2)), LightKit.glow(Palette.DANGER, 1.8))
			_:
				draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(Palette.TERRAIN_TOP, 0.8), 1.0)
