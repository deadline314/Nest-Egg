class_name InventoryPortraitScenario
extends ScenarioBase
## 背包立繪（NE-393）：背包右側的凜是遊戲內同一個角色骨架。拍一張背包開著的全畫面（左邊看得到關卡裡的主角），
## 再讓立繪依序做「撥頭髮」與「思考」，各拍準備、最高點、收回三格。骨架沒建立或手勢播不出來就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=inventory_portrait

const GESTURES: Array[StringName] = [&"hair_sweep", &"think"]
## 手勢開始後幾秒各拍一張（準備中、重音附近、收回中）。
const SHOT_TIMES := [0.35, 0.9, 1.5]


func run() -> void:
	# 改用獨立的設定檔並關掉「減少動態」：不讀也不寫玩家自己的設定。
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(false)
	await open_arena("")
	var inventory: InventoryScreen = level._inventory
	inventory.open()
	await wait(1.2)
	var portrait: SidePortrait = inventory._portrait
	if not portrait.has_texture():
		failures += 1
		push_error("[InventoryPortraitScenario] 背包立繪沒有建立角色骨架")
		await finish()
		return
	capture("NE-393-inventory-idle")
	for gesture in GESTURES:
		await wait(0.6)
		if not portrait.play_gesture(gesture):
			failures += 1
			push_error("[InventoryPortraitScenario] 手勢播不出來：%s" % gesture)
			continue
		var elapsed := 0.0
		for i in SHOT_TIMES.size():
			await wait(float(SHOT_TIMES[i]) - elapsed)
			elapsed = float(SHOT_TIMES[i])
			capture("NE-393-%s-%d" % [gesture, i])
		await wait(2.5)
	inventory.close()
	await wait(0.6)
	print("INVENTORY_PORTRAIT released=%s" % (not portrait.has_texture()))
	await finish()
