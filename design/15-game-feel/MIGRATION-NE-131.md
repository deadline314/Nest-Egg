# NE-131 遷移對照表

舊呼叫（強度、秒）→ 新事件（px、秒）。強度換算：px = 強度 × 0.8（最小 1.0）。舊的震動實際只有 trauma²×18 px，
且持續時間不生效；新版持續時間生效，所以小強度震動比以前明顯。頓幀秒數不變。

| 來源 | 舊 | 新事件 | 新值 |
|---|---|---|---|
| 敵人畏縮 | freeze 0.03 | enemy_flinch | freeze 0.03 |
| 敵人硬直 | freeze 0.06 + shake 1.2/0.08 | enemy_stagger | freeze 0.06 + 1.0 px/0.08 |
| 敵人死亡 | shake 2.5/0.12 + freeze 0.07 | enemy_kill | 2.0 px/0.12 + freeze 0.07 |
| 盾衝者暈眩 | shake 3.0/0.15 | shield_dazed | 2.4 px/0.15 |
| 探照機警報 | shake 1.5/0.1 | alarm_raised | 1.2 px/0.1 |
| 頭目登場（兩隻） | shake 4.0/0.5 | boss_intro | 3.2 px/0.5 |
| 頭目戰場鎖定 | shake 4.0/0.4 | boss_arena_lock | 3.2 px/0.4 |
| 回收者衝刺後重落 | shake 3.0/0.15 | boss_recover_thud | 2.4 px/0.15 |
| 典獄長落地 | shake 6.0/0.3 | boss_land | 4.8 px/0.3 |
| 頭目階段轉換（兩隻） | shake 7.0/0.6 | boss_phase_shift | 5.6 px/0.6 |
| 義體脈衝 | shake 3.0/0.2 | cyber_pulse | 2.4 px/0.2 |
| 玩家近戰命中 | freeze 0.05 + shake 2.0/0.08 | player_melee_hit | freeze 0.05 + 1.6 px/0.08 |
| 玩家處決 | freeze（資料）+ shake 5.0/0.2 | player_finisher | freeze（傳入）+ 4.0 px/0.2 |
| 完美格擋 | hitstop 0.08 + shake 3.0/0.12 | player_parry | hitstop 0.08 + 2.4 px/0.12 |
| 破防 | shake 4.0/0.2 | player_guard_break | 3.2 px/0.2 |
| 玩家受傷 | hitstop 0.07 + shake 4.0/0.15 | player_hurt | hitstop 0.07 + 3.2 px/0.15 |
| 玩家死亡 | shake 6.0/0.3 + hitstop 0.14 | player_death | 4.8 px/0.3 + hitstop 0.14 |
| 箱子破碎 | shake 2.5/0.15 | breakable_break | 2.0 px/0.15 |
| 閘門開啟 | shake 1.5/0.2 | gate_open | 1.2 px/0.2 |
| 載具落地 | shake 3.0/0.15 | vehicle_stomp | 2.4 px/0.15 |
| 載具受傷 | shake 2.0/0.1 | vehicle_hurt | 1.6 px/0.1 |
| 武器開火、載具開火 | shake 武器資料/0.08～0.1 | Feel.shake_strength | 強度 × 0.8 px |
| 敵人特效資料（步驟、死亡、命中） | shake 資料 | Feel.shake_strength | 強度 × 0.8 px |
| 爆炸 | shake clamp(半徑/6, 2, 8)/0.25 | Feel.shake_strength | 同左 × 0.8 px |
