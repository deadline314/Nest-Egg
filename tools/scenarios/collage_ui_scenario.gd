class_name CollageUiScenario
extends ScenarioBase
## 拼貼版面的動畫（NE-403）：主選單與背包的開啟、移動選取、確認、待機呼吸、信用點滾動，各拍開始、中間、結束三格。
## 用真的時間等（不是固定影格數），存檔很慢，所以每拍完一張先等兩格再觸發下一個動畫。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=collage_ui

const MID := 0.07
const END := 0.32


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
	# 開場：開始（動畫等兩個影格才開始）、中間、結束。
	await settle(3)
	capture("NE-403-menu-open-0")
	await settle(2)
	await wait(0.09)
	capture("NE-403-menu-open-1")
	await wait(END)
	capture("NE-403-menu-open-2")
	await settle(2)
	# 移動選取：焦點往下一格。
	var tags := menu._tags
	tags[1].grab_focus()
	await wait(MID * 0.6)
	capture("NE-403-menu-move-1")
	await wait(END)
	capture("NE-403-menu-move-2")
	await settle(2)
	# 確認：壓下再彈回（只播回饋，不真的進下一頁）。
	tags[1]._press_feedback()
	await wait(0.05)
	capture("NE-403-menu-press-1")
	await wait(END)
	capture("NE-403-menu-press-2")
	# 待機呼吸：半個週期前後各一張。
	await wait(0.4)
	capture("NE-403-menu-idle-0")
	await wait(TagButton.BREATH_PERIOD * 0.5)
	capture("NE-403-menu-idle-1")
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
	inventory.open()
	await get_tree().process_frame
	capture("NE-403-bag-open-0")
	await settle(2)
	await wait(0.1)
	capture("NE-403-bag-open-1")
	await wait(END)
	capture("NE-403-bag-open-2")
	await settle(2)
	# 換分頁：吊牌轉正往前、上一張退回。
	inventory.select_tab(inventory.page_index(ConsumablesPage))
	await wait(MID)
	capture("NE-403-bag-tab-1")
	await wait(END)
	capture("NE-403-bag-tab-2")
	await settle(2)
	# 信用點滾動。
	var credits := Progression.credits
	Progression.add_credits(240)
	await wait(0.12)
	capture("NE-403-bag-credits-1")
	await wait(END)
	capture("NE-403-bag-credits-2")
	print("COLLAGE credits %d -> %d label=%s" % [credits, Progression.credits, inventory._credits.text])
	inventory.close()
	await settle(3)
