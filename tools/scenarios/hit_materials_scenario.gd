class_name HitMaterialsScenario
extends ScenarioBase
## 截圖情境（NE-140）：把每種命中材質（含弱點與跳彈）各打一發在一排靶位上，命中後 0.06 與 0.2 秒各拍一張。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=hit_materials

const LIGHTING := "res://data/lighting/neutral.tres"
const CASES: Array = [["flesh", {}], ["armor", {}], ["metal", {}], ["glass", {}], ["wood", {}], ["concrete", {}], ["energy", {}], ["armor", {"weak": true}], ["metal", {"ricochet": true}]]


func run() -> void:
	await open_arena(LIGHTING, 8.0)
	place_player(4.0)
	await wait(0.5)
	HitFeedback.reset_budget()
	for n in 2:
		for i in CASES.size():
			var origin := Vector2((8.0 + float(i) * 2.2) * 16.0, FLOOR_Y - 18.0)
			HitFeedback.reset_budget()
			HitFeedback.play(StringName(CASES[i][0]), origin, Vector2.LEFT, Palette.CYAN, CASES[i][1])
		await wait(0.06 if n == 0 else 0.14)
		capture("materials_%d" % n)
	await finish()
