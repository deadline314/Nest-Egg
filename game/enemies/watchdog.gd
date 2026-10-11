extends PatternBoss
## 迷你頭目「看門狗 CERBERUS」（第一章碼頭倉庫前廳）：鍊子的長度就是牠的地盤，撲咬撲到鍊子盡頭會被扯回、背部電源露出。
## 招式、階段、習慣與部位開關都在 data/bosses/watchdog.json；部位的骨頭與大小在 EnemyData 的 hurt_parts。
## 睡著直到玩家靠近，不鎖場、可以逃回街道。擊敗後升起隔牆（頻道 watchdog_gate），不結束關卡。
## 受過的傷會保留（EnemyData.persists_damage），階段由血量推得，所以斷掉的砲塔與鍊子也保留。
## 外觀是四足機械犬（零件式生物 art/creatures/watchdog.json，NE-218）：子彈從背上的砲塔射出，砲塔跟著目標轉。
## 外觀載入失敗時退回程式繪製與身體側邊的槍口，不會崩潰。

const TURRET := "turret"
## 砲塔的俯仰範圍（弧度，負的往上）：轉不到的角度就停在邊界，不會穿過自己的背或頭。
const TURRET_UP := -0.9
const TURRET_DOWN := 0.35


func _muzzle() -> Vector2:
	if creature != null:
		return creature.muzzle_global(TURRET)
	return super._muzzle()


## 砲塔跟著目標轉（零件隨面向左右翻，所以水平取絕對值）。
func _creature_aim() -> float:
	var turret := creature.joint_of(TURRET) if creature != null else null
	if turret == null or _target() == null:
		return 0.0
	var to_target := _target_point() - turret.global_position
	return clampf(atan2(to_target.y, absf(to_target.x)), TURRET_UP, TURRET_DOWN)
