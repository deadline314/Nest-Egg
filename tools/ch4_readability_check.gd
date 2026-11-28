extends "res://tools/readability_check.gd"
## 第四章各區域的暗場可讀性（NE-423、NE-451），取樣點和門檻沿用第一章的工具（ContrastProbe）。
## 取樣點 [名稱, 欄, 地面列]；地圖線改了哪一區就把新路線的取樣點加在這裡。

const PROBES := {
	"ch4_nursing_ward": [["床位", 26, 20], ["收音座", 42, 16], ["備品頂架", 53, 12]],
	"ch4_factory_roof": [["收訊箱", 28, 20], ["維修平台", 45, 13]],
	"ch4_factory_approach": [["外門守衛", 50, 20], ["維修架", 55, 14]],
	"ch4_factory_relay": [["上層走道", 66, 14], ["出口積水", 87, 20]],
}


func targets() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in PROBES:
		entries.append({"path": "res://data/levels/%s.tres" % id, "spots": PROBES[id], "enemy_path": ""})
	return entries
