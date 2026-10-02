class_name DifficultyData
extends Resource
## 難度設定。全年齡客群的關鍵：同一套關卡用參數涵蓋新手到硬核玩家。

@export var id: StringName = &"standard"
@export var display_name: String = "標準"
@export_multiline var description: String = ""
@export var player_max_health: int = 6
## -1 代表無限接關；大於 0 時用盡會從關卡開頭重來。
@export var lives: int = -1
## 敵人攻擊冷卻倍率（越大越慢）。
@export var enemy_cooldown_multiplier: float = 1.0
@export var enemy_projectile_speed_multiplier: float = 1.0
@export var checkpoint_heals: bool = true


func has_limited_lives() -> bool:
	return lives > 0
