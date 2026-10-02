class_name VehicleData
extends Resource
## 可騎乘兵器定義。

@export var id: StringName = &"vehicle"
@export var display_name: String = "載具"
@export var weapon: WeaponData
@export var color: Color = Color(0.56, 0.72, 0.78)
@export var body_size: Vector2 = Vector2(26, 30)
@export var max_health: int = 12
@export var hurt_invulnerability: float = 0.4
@export var move_speed: float = 105.0
@export var acceleration: float = 900.0
@export var jump_velocity: float = 280.0
@export var gravity: float = 900.0
