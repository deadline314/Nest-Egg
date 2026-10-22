extends Node
## 全域事件匯流排：跨系統溝通（HUD、圖鑑、統計、鏡頭）一律走這裡，
## 讓遊戲物件與 UI 互不持有參照，任一方被移除都不會出錯。

## Actual panel visibility/owner lifecycle, independent of Story completion.
signal radio_visibility_changed

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
## 準星上的命中標記種類：hit（命中）、weak（弱點）、kill（擊殺）、blocked（被擋）。
signal hit_marker(kind: StringName)
## 傷害數字：位置、傷害、種類（weak、crit、blocked）、目標 id（合併同目標用）；設定關閉時沒有人顯示。
signal damage_number(world_position: Vector2, amount: int, kind: StringName, target_id: int)
## 空槍（彈匣空了還扣扳機）與換彈完成：準星與彈藥提示做回饋用。
signal dry_fired
signal reload_completed

signal boss_started(display_name: String, max_health: int)
signal boss_health_changed(current: int, maximum: int)
signal boss_defeated
## 迷你頭目被擊敗：只收起頭目血條，不會結束關卡（boss_defeated 才會）。
signal boss_bar_closed

## 機關頻道切換（開關 → 同頻道的閘門與升降梯）。
signal mechanism_toggled(channel: StringName, active: bool)
## 世界裡的大聲響（開槍、爆炸、東西碎掉）：附近的場景人物會縮一下、轉頭看（NE-240）。loudness 1＝一聲槍響。
signal world_noise(world_position: Vector2, loudness: float)
signal checkpoint_reached(position: Vector2)
signal lives_changed(lives: int)
signal codex_card_unlocked(card_id: StringName, is_new: bool)

signal screen_shake(px: float, duration: float, direction: Vector2, origin: Vector2)
signal camera_zoom_pulse(amount: float, duration: float)
## 全螢幕效果（data/feel/screen_fx.json 的種類）；由 PostProcess 播放。
signal screen_pulse(kind: StringName)
signal camera_kick(offset: Vector2)
signal toast_requested(text: String)

## 玩家所在的光影區段換了（zone_id 是光影設定的 id）；離開關卡時送出空 id。環境音與背景音樂依此切換。
signal zone_changed(zone_id: StringName)
## 光影事件：暫時覆蓋區段光影（停電、警報…），id 相同的覆蓋會被取代；清除後平滑回到區段光影。
signal lighting_override_requested(id: StringName, profile: LightingProfile, fade_time: float)
signal lighting_override_cleared(id: StringName, fade_time: float)
## 環境光瞬間閃亮（爆炸、閃電）：顏色疊加到環境光上，strength 為峰值亮度，duration 秒內衰減回去。
signal ambient_flash_requested(color: Color, strength: float, duration: float)
