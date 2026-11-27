class_name CollageUiScenario
extends ScenarioBase
## 拼貼版面的動畫（NE-403、NE-412）：主選單與背包的開啟、移動選取、確認、待機呼吸、信用點滾動，各拍開始、中間、結束三格。
## 用真的時間等（不是固定影格數），存檔很慢，所以每拍完一張先等兩格再觸發下一個動畫。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=collage_ui

const MID := 0.07
const END := 0.32
## 拍動畫時的時間倍率。
const SLOW := 0.1


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	await _menu()
	await _inventory()
	await finish()


func _menu() -> void:
	var menu := MainMenu.new()
	add_child(menu)
	# 開場：等動畫真的開始（立繪第一個影格很長），再用慢速時間拍開始、中間、結束（存檔會卡住主執行緒，慢速才不會一格跳到底）。
	var tags := menu._tags
	for i in 60:
		if tags[0]._intro_tween != null:
			break
		await get_tree().process_frame
	Engine.time_scale = SLOW
	capture("NE-412-menu-open-0")
	# 中間：等第一個選項彈到一半（看實際進度，不靠固定時間）。
	for i in 600:
		if tags[0]._intro >= 0.5:
			break
		await get_tree().process_frame
	capture("NE-412-menu-open-1")
	await wait(END)
	capture("NE-412-menu-open-2")
	await settle(2)
	# 移動選取：焦點往下一格。
	tags[1].grab_focus()
	await wait(MID)
	capture("NE-412-menu-move-1")
	await wait(END)
	capture("NE-412-menu-move-2")
	await settle(2)
	# 確認：壓下再彈回（只播回饋，不真的進下一頁）。
	tags[1]._press_feedback()
	await wait(0.05)
	capture("NE-412-menu-press-1")
	await wait(END)
	capture("NE-412-menu-press-2")
	Engine.time_scale = 1.0
	# 待機呼吸：半個週期前後各一張。
	await wait(0.4)
	capture("NE-412-menu-idle-0")
	await wait(TagButton.BREATH_PERIOD * 0.5)
	capture("NE-412-menu-idle-1")
	print("COLLAGE menu sizes=%s min=%s" % [tags.map(func(t: TagButton) -> Vector2: return t.size), tags.map(func(t: TagButton) -> Vector2: return t.get_combined_minimum_size())])
	print("COLLAGE menu tags=%d active=%s tilts=%s" % [tags.size(), tags.map(func(t: TagButton) -> String: return "%.2f" % t.active_amount()), tags.map(func(t: TagButton) -> String: return "%.1f" % rad_to_deg(t.current_tilt()))])
	menu.queue_free()
	await settle(3)


func _inventory() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(NewEnemiesSuite.arena_data())
	add_child(level)
	await settle(20)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	await wait(TITLE_CARD_TIME)
	var inventory: InventoryScreen = level._inventory
	Engine.time_scale = SLOW
	inventory.open()
	await get_tree().process_frame
	capture("NE-412-bag-open-0")
	await settle(2)
	await wait(0.1)
	capture("NE-412-bag-open-1")
	await wait(END)
	capture("NE-412-bag-open-2")
	await settle(2)
	# 換分頁：吊牌轉正往前、上一張退回。
	inventory.select_tab(inventory.page_index(ConsumablesPage))
	await wait(MID)
	capture("NE-412-bag-tab-1")
	await wait(END)
	capture("NE-412-bag-tab-2")
	await settle(2)
	# 信用點滾動。
	var credits := Progression.credits
	Progression.add_credits(240)
	await wait(0.12)
	capture("NE-412-bag-credits-1")
	await wait(END)
	capture("NE-412-bag-credits-2")
	Engine.time_scale = 1.0
	print("COLLAGE credits %d -> %d label=%s" % [credits, Progression.credits, inventory._credits.text])
	inventory.close()
	await settle(3)
