class_name PlayerTuning
extends Resource
## 玩家手感參數。動作遊戲的手感全在這裡調，不必改程式。

@export var default_weapon: WeaponData

@export_group("Run")
@export var run_speed: float = 130.0
@export var ground_acceleration: float = 1400.0
@export var ground_deceleration: float = 1800.0
@export var air_acceleration: float = 900.0
@export var air_deceleration: float = 600.0
## 背對準星移動時的速度倍率。
@export var backpedal_multiplier: float = 0.85

@export_group("Jump")
@export var gravity: float = 900.0
@export var fall_gravity_multiplier: float = 1.35
@export var max_fall_speed: float = 480.0
@export var jump_velocity: float = 320.0
## 放開跳躍鍵時上升速度保留的比例（可變跳躍高度）。
@export var jump_cut: float = 0.45
@export var coyote_time: float = 0.1
@export var jump_buffer: float = 0.12
## 跳躍頂點附近（|垂直速度| 小於門檻）且按住跳躍鍵時降低重力，讓空中瞄準更從容。
@export var apex_speed_threshold: float = 45.0
@export var apex_gravity_multiplier: float = 0.5
## 頭頂撞到平台邊角時自動側移的最大像素（避免「差一點點就卡住」）。
@export var corner_correction: int = 5

@export_group("Dash")
@export var dash_speed: float = 300.0
@export var dash_time: float = 0.16
@export var dash_cooldown: float = 0.4

@export_group("Damage")
@export var hurt_invulnerability: float = 1.0
@export var hurt_knockback: Vector2 = Vector2(140, 160)
@export var pit_damage: int = 2

@export_group("Melee & Finisher")
@export var melee_damage: int = 2
@export var melee_range: float = 26.0
@export var melee_cooldown: float = 0.3
@export var finisher_range: float = 36.0
@export var finisher_duration: float = 0.25
@export var finisher_hitstop: float = 0.09
## 終結技回補特殊武器彈藥的比例（相對最大彈藥）。
@export var finisher_ammo_refund: float = 0.3

@export_group("Vehicle")
@export var mount_range: float = 26.0
@export var eject_invulnerability: float = 1.2
