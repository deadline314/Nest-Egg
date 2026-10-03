class_name RigDebris
extends Node2D
## 脫落零件（裝甲片）：沿用原本的貼圖，帶重力、旋轉、彈地與淡出，時間到就回收到物件池重複使用。
## 用 RigDebris.spawn() 取得；同時在場上的數量有上限，超過就不產生（避免大量擊殺時節點暴增）。

const LIFETIME := 1.4
const GRAVITY := 900.0
const FLOOR_BOUNCE := 0.35
## 同時在場上的上限，也是池子的容量。
const MAX_ACTIVE := 24

static var _pool: Array[RigDebris] = []
static var _active := 0

var _velocity := Vector2.ZERO
var _spin := 0.0
var _age := 0.0
var _floor_y := INF
var _sprite: Sprite2D
var _live := false


## 取得一片脫落零件（從池子拿，沒有才新建）；場上已滿時回傳 null。
static func spawn(texture: Texture2D, source: Transform2D, offset: Vector2, velocity: Vector2) -> RigDebris:
	if _active >= MAX_ACTIVE:
		return null
	var debris: RigDebris = null
	while debris == null and not _pool.is_empty():
		var candidate: RigDebris = _pool.pop_back()
		if is_instance_valid(candidate):
			debris = candidate
	if debris == null:
		debris = RigDebris.new()
	debris.setup(texture, source, offset, velocity)
	return debris


func setup(texture: Texture2D, source: Transform2D, offset: Vector2, velocity: Vector2) -> void:
	transform = source
	_velocity = velocity
	_spin = randf_range(-12.0, 12.0)
	_age = 0.0
	_floor_y = INF
	modulate.a = 1.0
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		add_child(_sprite)
	_sprite.texture = texture
	_sprite.offset = offset
	set_physics_process(true)
	_live = true
	_active += 1


func _enter_tree() -> void:
	# 以出生點下方的地面作為彈跳高度（找不到就自由落下）。
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, 200), Layers.SOLID)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_floor_y = (hit["position"] as Vector2).y - 1.0


func _exit_tree() -> void:
	# 被容器一起釋放（換關）時也要把場上數量扣掉。
	if _live:
		_live = false
		_active = maxi(0, _active - 1)


func _physics_process(delta: float) -> void:
	_age += delta
	_velocity.y += GRAVITY * delta
	global_position += _velocity * delta
	rotation += _spin * delta
	if global_position.y > _floor_y and _velocity.y > 0.0:
		global_position.y = _floor_y
		_velocity = Vector2(_velocity.x * 0.6, -_velocity.y * FLOOR_BOUNCE)
		_spin *= 0.5
	modulate.a = clampf((LIFETIME - _age) / 0.4, 0.0, 1.0)
	if _age >= LIFETIME:
		_recycle()


## 沒能放進場景（沒有綁定關卡，Fx 已經把它釋放）：撤銷這次取用。
func cancel() -> void:
	if _live:
		_live = false
		_active = maxi(0, _active - 1)


## 放回池子：離開場景樹、停止運算，下次 spawn 再用。
func _recycle() -> void:
	set_physics_process(false)
	if _live:
		_live = false
		_active = maxi(0, _active - 1)
	if _pool.size() < MAX_ACTIVE:
		_pool.append(self)
		var parent := get_parent()
		if parent != null:
			parent.remove_child.call_deferred(self)
	else:
		queue_free()
