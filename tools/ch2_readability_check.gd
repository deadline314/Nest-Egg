extends "res://tools/readability_check.gd"
## ST-19：第二章各區域的暗場可讀性與截圖，取樣點和門檻沿用第一章的工具（ContrastProbe）。
## 戰鬥區的敵人由戰鬥組配置（NE-266）；這裡用第一章的清掃兵當敵人取樣，只量光影下看不看得清楚。
const PROBES := {
	"ch2_pawnshop": [["櫃台", 50, 20], ["工作檯", 61, 20], ["廚房", 92, 20]],
	"ch2_rooftop": [["茶座", 40, 18]],
	"ch2_harbor_street": [["B1 電話亭", 30, 20]],
	"ch2_market_gate": [["巡帳員", 18, 20], ["地面戰區", 40, 20], ["上層攤道", 52, 14], ["B3 電話亭", 92, 20]],
	"ch2_market": [["代收處", 28, 20], ["租攤視窗", 53, 20], ["公告屏", 90, 20]],
	"ch2_ali_home": [["小廚房", 30, 20]],
	"ch2_loading": [["下層貨道", 40, 20], ["電線橋", 50, 13], ["裝卸間", 120, 20]],
	"ch2_ledger_front": [["前室", 28, 20]],
	"ch2_ledger_office": [["帳房戰區", 30, 20], ["帳櫃", 54, 20]],
	"ch2_lounge_front": [["委託終端", 16, 20]],
}
const COMBAT := ["ch2_market_gate", "ch2_loading", "ch2_ledger_office"]


func targets() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in PROBES:
		entries.append({"path": "res://data/levels/%s.tres" % id, "spots": PROBES[id],
			"enemy_path": "res://data/enemies/sweeper.tres" if id in COMBAT else ""})
	return entries
