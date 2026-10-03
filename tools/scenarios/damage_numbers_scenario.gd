class_name DamageNumbersScenario
extends ScenarioBase
## 截圖情境（NE-148）：開啟傷害數字，弱點、重擊、被擋各打一發，連續兩發同目標合併。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=damage_numbers

const LIGHTING := "res://data/lighting/neutral.tres"


func run() -> void:
	await open_arena(LIGHTING, 12.0)
	Settings.set_damage_numbers(true)
	await wait(0.4)
	var base := player.global_position
	EventBus.damage_number.emit(base + Vector2(60, -40), 3, &"weak", 11)
	EventBus.damage_number.emit(base + Vector2(60, -40), 2, &"weak", 11)  # 合併成 5
	EventBus.damage_number.emit(base + Vector2(100, -30), 4, &"crit", 12)
	EventBus.damage_number.emit(base + Vector2(140, -40), 0, &"blocked", 13)
	await wait(0.18)
	capture("numbers")
	Settings.set_damage_numbers(false)
	await finish()
