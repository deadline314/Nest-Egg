extends ScenarioBase
## 監管者的核心砲（NE-89 專屬骨頭範例）：中性光影（看清楚胸甲與核心）下，第二階段的監管者依序拍下蓄力（胸甲掀開、瞄準線）、
## 發射、核心外露、胸甲收回。每個時間點一張，存成 <out>/warden_core_<序號>.png。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=warden_core

const SHOT_TIMES: Array[float] = [0.05, 0.25, 0.45, 0.62, 0.9, 1.3, 1.9]


func run() -> void:
	await open_arena("res://data/lighting/neutral.tres", 6.0)
	var warden := spawn_enemy("res://data/enemies/warden.tres", 16.0)
	warden.set("_phase", 2)
	await wait(0.4)
	player.global_position = Vector2(8.0 * 16.0, FLOOR_Y)
	snap_camera()
	warden.global_position = Vector2(16.0 * 16.0, FLOOR_Y)
	warden.fsm.transition(&"core_windup")
	var elapsed := 0.0
	for i in SHOT_TIMES.size():
		await wait(SHOT_TIMES[i] - elapsed)
		elapsed = SHOT_TIMES[i]
		capture("warden_core_%02d" % i)
	await finish()
