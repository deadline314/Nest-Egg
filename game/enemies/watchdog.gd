extends "res://game/enemies/custodian.gd"
## 迷你頭目「看門狗」（第一章碼頭倉庫前廳，教學頭目）：招式與看守長相同（點射、跳躍震波、後期扇形彈幕），
## 睡著直到玩家靠近，不鎖場、可以逃回街道。擊敗後升起隔牆（頻道 watchdog_gate），不結束關卡。
## 受過的傷會保留（EnemyData.persists_damage）：死亡後回來，牠仍然帶傷。
## 外觀暫用監管者的人形骨架；之後換成兩腿一尾的看門狗機甲時，只需換 EnemyData 的外觀欄位。

const WATCHDOG_GATE := &"watchdog_gate"


func _gate_channel() -> StringName:
	return WATCHDOG_GATE


func _unlock_text() -> String:
	return "隔牆升起了"
