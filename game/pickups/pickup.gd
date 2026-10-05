@abstract
class_name Pickup
extends Area2D
## 道具基底：玩家（或玩家駕駛的載具）碰到即觸發 _apply()；回傳 false 代表不需要（例如滿血），道具保留。
## 子類別覆寫：_apply(player)、_draw_icon()、hint_text()

const BOB_SPEED := 3.0
const BOB_HEIGHT := 2.0
## 玩家停留在道具上時（例如原本滿血後受傷）重新嘗試拾取的間隔。
const RETRY_INTERVAL := 0.3

## 拾取物偶爾閃一下星芒：週期與閃爍秒數（每個拾取物的起始時間錯開）。
const GLINT_PERIOD := 2.8
const GLINT_TIME := 0.16

var _time := 0.0
var _retry_left := RETRY_INTERVAL
var _glint_offset := randf() * GLINT_PERIOD


func _ready() -> void:
	LightKit.mark_emissive(self)
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -8)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	var hint := hint_text()
	if not hint.is_empty():
		var prompt := WorldPrompt.new()
		prompt.text = hint
		prompt.radius = 56.0
		prompt.offset = Vector2(0, -26)
		add_child(prompt)


func hint_text() -> String:
	return ""


## 拾取特效的顏色與種類（PickupFx.KINDS）；子類別依道具覆寫。
func _fx_color() -> Color:
	return Palette.CYAN


func _fx_kind() -> StringName:
	return &"item"


## 回傳 false 代表玩家目前不需要（道具保留）。
@abstract func _apply(player: Player) -> bool


@abstract func _draw_icon() -> void


## 畫場景小圖（art/items/world/<key>.png，24×24，腳底對齊，另有自發光層）；沒有這張圖回傳 false，呼叫端改用程式繪製。
func _draw_world_sprite(key: String) -> bool:
	var sprite := ItemIcons.world(key)
	if sprite.is_empty():
		return false
	var base: Texture2D = sprite["base"]
	var origin := Vector2(-base.get_width() * 0.5, -base.get_height() * 0.5 - 4.0)
	draw_texture(base, origin)
	var glow: Texture2D = sprite["glow"]
	if glow != null:
		draw_texture(glow, origin, LightKit.glow(Color.WHITE, 1.4 + 0.4 * sin(_time * 5.0)))
	return true


func _process(delta: float) -> void:
	_time += delta
	_retry_left -= delta
	if _retry_left <= 0.0 and monitoring:
		_retry_left = RETRY_INTERVAL
		for body in get_overlapping_bodies():
			_on_body_entered(body)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, -8 + sin(_time * BOB_SPEED) * BOB_HEIGHT))
	_draw_icon()
	_draw_glint()
	draw_set_transform(Vector2.ZERO)


func _on_body_entered(body: Node2D) -> void:
	var player := resolve_player(body)
	if player == null or player.is_dead():
		return
	if is_queued_for_deletion():
		return
	if _apply(player):
		PickupFx.collect(global_position + Vector2(0, -8), _fx_color(), _fx_kind())
		Sfx.play(&"pickup", -6.0)
		set_deferred(&"monitoring", false)
		_consume()


## 撿起後的處理（預設移除）。需要保留節點的道具（例如要存進檢查點）可以覆寫。
func _consume() -> void:
	queue_free()


## 碰到的可能是玩家本人，或玩家正在駕駛的載具。
static func resolve_player(body: Node) -> Player:
	if body is Player:
		return body as Player
	if body is Vehicle:
		return (body as Vehicle).driver
	return null


## 圖示上偶爾閃過的四芒星，提醒這裡有東西可以撿（很短、很小，不干擾閱讀）。
func _draw_glint() -> void:
	var phase := fmod(_time + _glint_offset, GLINT_PERIOD)
	if phase > GLINT_TIME:
		return
	var t := phase / GLINT_TIME
	var strength := sin(t * PI)
	var color := Color(Fx.hdr(Palette.WHITE, 2.0), strength)
	var center := Vector2(3.0, -4.0)
	var reach := 2.0 + 3.5 * strength
	draw_line(center - Vector2(reach, 0.0), center + Vector2(reach, 0.0), color, 1.0)
	draw_line(center - Vector2(0.0, reach), center + Vector2(0.0, reach), color, 1.0)
