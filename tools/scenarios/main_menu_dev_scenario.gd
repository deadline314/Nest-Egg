class_name MainMenuDevScenario
extends ScenarioBase
## 截圖情境（NE-171）：除錯版主選單右下角的「開發工具」按鈕，按下後開出開發工具選單。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=main_menu_dev

func run() -> void:
	var menu := MainMenu.new()
	add_child(menu)
	await wait(1.6)
	capture("main_menu_dev_button")
	menu._dev_button.pressed.emit()
	await wait(0.3)
	capture("main_menu_dev_open")
	DevMenu.close()
	await finish()
