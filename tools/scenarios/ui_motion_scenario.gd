class_name UiMotionScenario
extends ScenarioBase
## 介面動效（NE-389）：換武器時選取框滑動、設定頁切分頁時內容滑入。各拍「切換前、動畫中間、到位後」三張，
## 並印出中間那一格的位置與不透明度；中間那一格已經到位（沒有動畫）或結束時沒到位都記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=ui_motion

const WEAPONS := ["smg", "rifle", "railgun"]
## 動畫開始後幾個影格拍中間那一張。
const MID_FRAMES := 2


func run() -> void:
	# 改用獨立的設定檔並關掉「減少動態」：不讀也不寫玩家自己的設定。
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(false)
	await open_arena("")
	level.hud.visible = true
	for id: String in WEAPONS:
		player.loadout.equip(load("res://data/weapons/%s.tres" % id) as WeaponData)
	player.loadout.refill_all()
	player.loadout.select(0)
	await wait(0.5)
	capture("NE-389-weapon-0-before")
	# 存截圖很慢，下一格的時間差會很大；等兩格再切換，動畫才不會被那一格一次吃掉。
	await settle(2)
	var bar := level.hud.weapon_bar
	player.loadout.select(3)
	await settle(MID_FRAMES)
	var mid_y := bar.selection_y()
	print("UI_MOTION weapon mid y=%.1f moving=%s" % [mid_y, bar.is_selection_moving()])
	capture("NE-389-weapon-1-mid")
	await wait(0.4)
	print("UI_MOTION weapon end y=%.1f moving=%s" % [bar.selection_y(), bar.is_selection_moving()])
	capture("NE-389-weapon-2-after")
	if bar.is_selection_moving() or is_equal_approx(mid_y, bar.selection_y()):
		failures += 1
		push_error("[UiMotionScenario] 選取框沒有滑動或沒有到位")
	level.queue_free()
	level = null
	await settle(4)

	var settings := SettingsScreen.new()
	add_child(settings)
	await settle(20)
	capture("NE-389-tabs-0-before")
	await settle(2)
	settings._tabs.current_tab = 2
	await settle(MID_FRAMES)
	var page := settings._tabs.get_tab_control(2)
	var mid_alpha := page.modulate.a
	print("UI_MOTION tab mid alpha=%.2f" % mid_alpha)
	capture("NE-389-tabs-1-mid")
	await wait(0.4)
	print("UI_MOTION tab end alpha=%.2f" % page.modulate.a)
	capture("NE-389-tabs-2-after")
	if not is_equal_approx(page.modulate.a, 1.0) or is_equal_approx(mid_alpha, 1.0):
		failures += 1
		push_error("[UiMotionScenario] 分頁內容沒有滑入或沒有完全顯示")
	settings.queue_free()
	await finish()
