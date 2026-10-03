extends Node
## 全域事件匯流排：跨系統溝通（HUD、圖鑑、統計、鏡頭）一律走這裡，
## 讓遊戲物件與 UI 互不持有參照，任一方被移除都不會出錯。

signal player_spawned(player: Node2D)
signal player_health_changed(current: int, maximum: int)
signal player_loadout_changed(loadout: Loadout)
signal player_consumables_changed(bag: ConsumableBag)
signal player_died(cause_id: StringName)
signal player_guard_changed(current: float, maximum: float, broken: bool)
## 義體能力狀態：電量 0~100、是否可用、能力名稱（空字串 = 沒有裝備）、冷卻或持續的進度 0~1。
signal player_cyber_changed(charge: float, ready: bool, ability_name: String, progress: float)
signal player_parried(world_position: Vector2)

signal vehicle_mounted(vehicle: Node2D)
signal vehicle_dismounted
signal vehicle_health_changed(current: int, maximum: int)

signal enemy_killed(enemy_id: StringName, by_finisher: bool)
## 玩家的攻擊命中（準星命中標記用）。
signal hit_confirmed(world_position: Vector2, killed: bool)

signal boss_started(display_name: String, max_health: int)
signal boss_health_changed(current: int, maximum: int)
signal boss_defeated

## 機關頻道切換（開關 → 同頻道的閘門與升降梯）。
signal mechanism_toggled(channel: StringName, active: bool)
signal checkpoint_reached(position: Vector2)
signal lives_changed(lives: int)
signal codex_card_unlocked(card_id: StringName, is_new: bool)

signal screen_shake(px: float, duration: float)
signal camera_kick(offset: Vector2)
signal toast_requested(text: String)

## 光影事件：暫時覆蓋區段光影（停電、警報…），id 相同的覆蓋會被取代；清除後平滑回到區段光影。
signal lighting_override_requested(id: StringName, profile: LightingProfile, fade_time: float)
signal lighting_override_cleared(id: StringName, fade_time: float)
## 環境光瞬間閃亮（爆炸、閃電）：顏色疊加到環境光上，strength 為峰值亮度，duration 秒內衰減回去。
signal ambient_flash_requested(color: Color, strength: float, duration: float)
