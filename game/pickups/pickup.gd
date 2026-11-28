@abstract
class_name Pickup
extends Area2D
## 道具基底：玩家（或玩家駕駛的載具）碰到即觸發 _apply()；回傳 false 代表不需要（例如滿血），道具保留。
## 子類別覆寫：_apply(player)、_draw_icon()、hint_text()

const NOTICE_COPY := {
	"zh": {"picked": "取得 %s", "count": "（%d/%d）", "full": "%s 已達上限 %d", "separator": "："},
	"ja": {"picked": "%sを入手", "count": "（%d/%d）", "full": "%sは所持上限です（%d）。", "separator": "："},
	"en": {"picked": "Picked up %s", "count": " (%d/%d)", "full": "%s at carrying limit (%d).", "separator": ": "},
}

const BOB_SPEED := 3.0
const BOB_HEIGHT := 2.0
## 玩家停留在道具上時（例如原本滿血後受傷）重新嘗試拾取的間隔。
const RETRY_INTERVAL := 0.3

## 拾取物偶爾閃一下星芒：週期與閃爍秒數（每個拾取物的起始時間錯開）。
const GLINT_PERIOD := 2.8
const GLINT_TIME := 0.16
## 輪廓微光（NE-391）：玩家在這個距離內才變亮並脈動，平常低調，遠處看到的是物品本身。
const NOTICE_RADIUS := 56.0
const OUTLINE_REST := 0.72
const OUTLINE_NEAR := 1.0
const OUTLINE_PULSE := 0.18
const OUTLINE_FADE_SPEED := 5.0

var _time := 0.0
var _retry_left := RETRY_INTERVAL
var _glint_offset := randf() * GLINT_PERIOD
var _collection_finished := false
var _emission: _Emission
var _world_sprite: Dictionary = {}
var _near := 0.0
var _player_ref := PlayerRef.new()


## 延後交付不綁在可能先離場的父節點；已交給別人的物件不再接管。
static func add_deferred(parent: Node, child: Node) -> void:
	if not is_instance_valid(child) or child.get_parent() != null:
		return
	if not is_instance_valid(parent) or parent.is_queued_for_deletion() or not parent.is_inside_tree():
		child.free()
		return
	_attach_deferred.call_deferred(weakref(parent), weakref(child))


static func _attach_deferred(parent_ref: WeakRef, child_ref: WeakRef) -> void:
	var child := child_ref.get_ref() as Node
	if child == null or child.get_parent() != null or child.is_queued_for_deletion():
		return
	var parent := parent_ref.get_ref() as Node
	if parent == null or parent.is_queued_for_deletion() or not parent.is_inside_tree():
		child.free()
		return
	parent.add_child(child)


func _ready() -> void:
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
		# 拾取物的說明是「在講話」的文字（不是按鍵邀請，碰到就撿）：和氣泡輪流，有人講話時等講完（NE-493）。
		prompt.text_kind = &"pickup"
		prompt.voice = TextTraffic.Voice.PICKUP
		prompt.radius = 56.0
		prompt.offset = Vector2(0, -26)
		add_child(prompt)
	_emission = _Emission.new()
	_emission.name = "Emission"
	_emission.pickup = self
	LightKit.mark_emissive(_emission)
	add_child(_emission)


func hint_text() -> String:
	return ""


static func _pickup_text(key: String) -> String:
	return NOTICE_COPY.get(Story.language, NOTICE_COPY[StoryLocale.SOURCE_LANGUAGE])[key]


static func _describe(title: String, description: String) -> String:
	if description.is_empty():
		return title
	return title + _pickup_text("separator") + description


## 拾取特效的顏色與種類（PickupFx.KINDS）；子類別依道具覆寫。
func _fx_color() -> Color:
	return Palette.CYAN


func _fx_kind() -> StringName:
	return &"item"


## 回傳 false 代表玩家目前不需要（道具保留）。
@abstract func _apply(player: Player) -> bool


@abstract func _draw_icon() -> void


## Procedural missing-art warnings stay emissive while their panel/body remains reflective.
func _draw_fallback_emission(_canvas: Node2D) -> void:
	pass


## 畫場景小圖（art/items/world/<key>.png，24×24，腳底對齊，另有自發光層）；沒有這張圖回傳 false，呼叫端改用程式繪製。
func _draw_world_sprite(key: String) -> bool:
	var sprite := ItemIcons.world(key)
	_world_sprite = sprite
	if sprite.is_empty():
		return false
	draw_texture_rect(sprite["base"], Rect2(Vector2(-ItemIcons.WORLD_SIZE.x * 0.5, -ItemIcons.WORLD_SIZE.y * 0.5 - 4.0), ItemIcons.WORLD_SIZE), false)
	return true


func _process(delta: float) -> void:
	_time += delta
	_retry_left -= delta
	if _retry_left <= 0.0 and monitoring:
		_retry_left = RETRY_INTERVAL
		for body in get_overlapping_bodies():
			_on_body_entered(body)
	var player := _player_ref.get_player(get_tree())
	var close := player != null and player.global_position.distance_squared_to(global_position) <= NOTICE_RADIUS * NOTICE_RADIUS
	_near = move_toward(_near, 1.0 if close else 0.0, OUTLINE_FADE_SPEED * delta)
	queue_redraw()
	if _emission != null:
		_emission.queue_redraw()


## 輪廓微光目前的不透明度：平常低調，玩家靠近時變亮並緩慢脈動（「減少閃光」時不脈動）。
func outline_strength() -> float:
	var level := lerpf(OUTLINE_REST, OUTLINE_NEAR, _near)
	if _near > 0.0 and not Settings.get_reduce_flashes():
		level *= 1.0 - OUTLINE_PULSE * _near * (0.5 + 0.5 * sin(_time * 5.0))
	return level


func _draw() -> void:
	draw_set_transform(Vector2(0, -8 + sin(_time * BOB_SPEED) * BOB_HEIGHT))
	_draw_icon()
	draw_set_transform(Vector2.ZERO)


func _on_body_entered(body: Node2D) -> void:
	var player := resolve_player(body)
	if player == null or player.is_dead():
		return
	if _collection_finished or is_queued_for_deletion():
		return
	if _apply(player):
		complete_collection()


## The durable owner can complete a previously refused collection on retry.
func complete_collection() -> void:
	if _collection_finished or is_queued_for_deletion():
		return
	_collection_finished = true
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


## Emission never includes the reflective item body.
class _Emission:
	extends Node2D
	var pickup: Pickup

	func _draw() -> void:
		draw_set_transform(Vector2(0, -8 + sin(pickup._time * BOB_SPEED) * BOB_HEIGHT))
		var sprite := pickup._world_sprite
		if not sprite.is_empty():
			var base: Texture2D = sprite["base"]
			var size := ItemIcons.WORLD_SIZE
			var origin := Vector2(-size.x * 0.5, -size.y * 0.5 - 4.0)
			var outline: Texture2D = sprite.get("outline")
			if outline != null:
				var inner := ItemIcons.WORLD_SIZE * float(ItemIcons.WORLD_OUTLINE_SCALE)
				var pad := (Vector2(outline.get_size()) - inner) * 0.5 * size / inner
				# 顏色帶一點物品自己的色調，不是每件都同一圈淺藍白。
				var tint := Color(0.62, 0.85, 0.88).lerp(pickup._fx_color().lightened(0.4), 0.25)
				draw_texture_rect(outline, Rect2(origin - pad, size + pad * 2.0), false, Color(tint, pickup.outline_strength()))
			var glow: Texture2D = sprite["glow"]
			if glow != null:
				draw_texture_rect(glow, Rect2(origin, size), false, LightKit.glow(Color(1, 1, 1, 0.25), 1.1 + 0.1 * sin(pickup._time * 5.0)))
		else:
			pickup._draw_fallback_emission(self)
		_draw_glint()

	## 圖示上偶爾閃過的四芒星，提醒這裡有東西可以撿（很短、很小，不干擾閱讀）。
	func _draw_glint() -> void:
		var phase := fmod(pickup._time + pickup._glint_offset, GLINT_PERIOD)
		if phase > GLINT_TIME:
			return
		var t := phase / GLINT_TIME
		var strength := sin(t * PI)
		var color := Color(Fx.hdr(Palette.WHITE, 2.0), strength)
		var center := Vector2(3.0, -4.0)
		var reach := 2.0 + 3.5 * strength
		draw_line(center - Vector2(reach, 0.0), center + Vector2(reach, 0.0), color, 1.0)
		draw_line(center - Vector2(0.0, reach), center + Vector2(0.0, reach), color, 1.0)
