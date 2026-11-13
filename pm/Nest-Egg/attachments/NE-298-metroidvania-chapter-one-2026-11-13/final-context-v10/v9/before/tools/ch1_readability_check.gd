extends "res://tools/readability_check.gd"
## ST-6: current campaign geometry, including ST-14's warehouse split and dawn reuse, the prologue (ST-16) and the handoff (ST-9).
## Shares ContrastProbe, sample count and thresholds with the existing chapter checker.
## Safe areas have no enemy probe; combat areas use the chapter's existing sweeper.
## 取樣的主角與敵人要站在同一側：閘門廳原本的敵人位置在關著的閘門另一邊，槍燈被閘門擋住（子彈也打不到），不算可讀性的樣本。
const PROBES := {
	"ch1_prologue": [["工作桌", 24, 20], ["射擊線", 50, 20], ["訓練器", 85, 20]],
	"ch1_pawnshop": [["後空地", 18, 20], ["店面", 55, 20], ["廚房", 88, 20]],
	"ch1_rooftop": [["屋頂水塔", 42, 18]],
	"ch1_street": [["市集", 60, 20], ["碼頭入口", 200, 20]],
	"ch1_booth_alley": [["電話亭", 26, 20]],
	"ch1_warehouse": [["看門狗前廳", 54, 17], ["閘門廳", 78, 17]],
	"ch1_vault": [["倉庫深處", 22, 17], ["上層走道", 83, 9]],
	"ch1_handoff": [["交接櫃", 18, 20]],
	"ch1_lounge": [["復原館", 25, 20]],
	"ch1_stall": [["宵夜麵攤", 25, 20]],
	"ch1_pawnshop_dawn": [["天亮店面", 55, 20]],
}


func targets() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/chapter_rosters.json"))
	for id: String in roster["chapters"]["ch1_kasa"]["levels"]:
		if not PROBES.has(id):
			printerr("[ch1_readability_check] No sampling baseline for %s" % id)
			_failed = true
			continue
		entries.append({"path": "res://data/levels/%s.tres" % id, "spots": PROBES[id],
			"enemy_path": "res://data/enemies/sweeper.tres" if id in ["ch1_street", "ch1_warehouse", "ch1_vault"] else ""})
	return entries
