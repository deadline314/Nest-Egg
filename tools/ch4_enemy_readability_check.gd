extends "res://tools/readability_check.gd"
## 第四章敵人在牠實際出現位置的輪廓對比（NE-424 起）：同一套 ContrastProbe 與門檻，敵人站在主角前方。
## 取樣點 [名稱, 欄, 地面列]，主角站在取樣點、敵人在右邊 ENEMY_DISTANCE 像素。
## 用法（原生 Forward+）：godot --path . res://tools/ch4_enemy_readability_check.tscn [-- --detail]

const TARGETS := [
	["res://data/levels/ch4_factory_relay.tres", "res://data/enemies/slasher.tres",
		[["原位", 36, 20], ["中段", 58, 20], ["東端", 84, 20]]],
	["res://data/levels/ch4_factory_relay.tres", "res://data/enemies/sweeper.tres",
		[["原位", 36, 20], ["中段", 58, 20], ["東端", 84, 20]]],
]


func targets() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for target: Array in TARGETS:
		entries.append({"path": target[0], "spots": target[2], "enemy_path": target[1]})
	return entries
