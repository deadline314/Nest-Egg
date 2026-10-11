extends "res://tools/readability_check.gd"
## ST-21：第三章各區域的暗場可讀性與截圖，取樣點和門檻沿用第一章的工具（ContrastProbe）。
## 戰鬥區的敵人由戰鬥組配置；這裡用第一章的清掃兵當敵人取樣，只量光影下看不看得清楚。
const PROBES := {
	"ch3_pawnshop": [["櫃台", 50, 20], ["廚房", 93, 20]],
	"ch3_plaza": [["控制箱", 40, 20], ["高架維修盒", 75, 14]],
	"ch3_pump": [["排水輪", 30, 13], ["下槽戰區", 26, 20], ["配電盤", 64, 20]],
	"ch3_mezzanine": [["電話亭", 22, 20], ["維修帶", 48, 20]],
	"ch3_clinic": [["櫃檯", 24, 20], ["工作廊", 60, 20]],
	"ch3_gate_hall": [["門禁閘", 18, 20], ["大廳戰區", 36, 20]],
	"ch3_glass_edge": [["光斑", 20, 20]],
	"ch3_showroom": [["接待桌", 16, 20], ["B 靜窗", 46, 20]],
	"ch3_office_hall": [["等候臺", 28, 20]],
}
const COMBAT := ["ch3_pump", "ch3_mezzanine", "ch3_gate_hall"]


func targets() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in PROBES:
		entries.append({"path": "res://data/levels/%s.tres" % id, "spots": PROBES[id],
			"enemy_path": "res://data/enemies/sweeper.tres" if id in COMBAT else ""})
	return entries
