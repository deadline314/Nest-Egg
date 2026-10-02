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

@export_group("Block & Parry")
## 格擋中的移動速度倍率。
@export var block_speed_multiplier: float = 0.35
## 可格擋的扇形角度（以準星方向為中心）。
@export var block_arc_degrees: float = 120.0
## 剛按下格擋後的「完美格擋」時間窗（秒）。
@export var parry_window: float = 0.16
@export var guard_max: float = 100.0
## 每點傷害消耗的護盾能量。
@export var guard_cost_per_damage: float = 24.0
@export var guard_regen_per_second: float = 40.0
@export var guard_regen_delay: float = 0.6
## 破防後的硬直時間與無法再格擋的時間。
@export var guard_break_stun: float = 0.6
@export var guard_break_lockout: float = 1.6
## 完美格擋接觸攻擊時，攻擊者被暈眩的秒數。
@export var parry_stun: float = 1.4

@export_group("Vehicle")
@export var mount_range: float = 26.0
@export var eject_invulnerability: float = 1.2
