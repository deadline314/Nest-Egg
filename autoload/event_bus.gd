extends Node
## 全域事件匯流排：跨系統溝通（HUD、圖鑑、統計、鏡頭）一律走這裡，
## 讓遊戲物件與 UI 互不持有參照，任一方被移除都不會出錯。

signal player_spawned(player: Node2D)
signal player_health_changed(current: int, maximum: int)
signal player_loadout_changed(loadout: Loadout)
signal player_died(cause_id: StringName)

signal vehicle_mounted(vehicle: Node2D)
signal vehicle_dismounted
signal vehicle_health_changed(current: int, maximum: int)

signal enemy_killed(enemy_id: StringName, by_finisher: bool)
## 玩家的攻擊命中（準星命中標記用）。
signal hit_confirmed(world_position: Vector2, killed: bool)

signal boss_started(display_name: String, max_health: int)
signal boss_health_changed(current: int, maximum: int)
signal boss_defeated

signal checkpoint_reached(position: Vector2)
signal lives_changed(lives: int)
signal codex_card_unlocked(card_id: StringName, is_new: bool)

signal screen_shake(strength: float, duration: float)
signal camera_kick(offset: Vector2)
signal toast_requested(text: String)
