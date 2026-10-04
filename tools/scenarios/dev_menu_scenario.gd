class_name DevMenuScenario
extends ScenarioBase
## 截圖情境（NE-168）：在關卡裡按 F5 開出開發工具選單（遊戲暫停、列出實驗室與回主選單）。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=dev_menu

func run() -> void:
	await open_arena("res://data/lighting/neutral.tres", 10.0)
	spawn_enemy("res://data/enemies/grunt.tres", 18.0)
	await wait(0.6)
	var event := InputEventKey.new()
	event.keycode = DevMenu.TOGGLE_KEY
	event.pressed = true
	DevMenu._input(event)
	await wait(0.3)
	capture("dev_menu")
	DevMenu.close()
	await finish()
