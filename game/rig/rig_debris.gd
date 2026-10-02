class_name RigDebris
extends Node2D
## 脫落零件（裝甲片）：沿用原本的貼圖，帶重力、旋轉、彈地與淡出，短時間後自行釋放。

const LIFETIME := 1.4
const GRAVITY := 900.0
const FLOOR_BOUNCE := 0.35

var _velocity := Vector2.ZERO
var _spin := 0.0
var _age := 0.0
var _floor_y := INF
var _sprite: Sprite2D


func setup(texture: Texture2D, source: Transform2D, offset: Vector2, velocity: Vector2) -> void:
	transform = source
	_velocity = velocity
	_spin = randf_range(-12.0, 12.0)
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.centered = false
	_sprite.offset = offset
	add_child(_sprite)


func _ready() -> void:
	# 以出生點下方的地面作為彈跳高度（找不到就自由落下）。
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, 200), Layers.SOLID)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_floor_y = (hit["position"] as Vector2).y - 1.0


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
		queue_free()
