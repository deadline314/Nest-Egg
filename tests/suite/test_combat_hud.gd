class_name CombatHudSuite
extends TestSuite
## 戰鬥介面（NE-43）：頭目血條（登場展開、階段刻度閃光）、信用點讀數、義體電量、橫幅分類、
## 通訊對話框滑入，以及每個元素都有一句說明。


func run() -> void:
	await _test_boss_bar()
	await _test_credits_tag()
	await _test_banner_kinds()
	await _test_tooltips()
	await _test_radio_panel()


func _test_boss_bar() -> void:
	var level := await start_level(PropsSuite.level_data())
	var bar := level.hud.boss_bar
	check(not bar.is_open(), "沒有頭目時血條不顯示")
	EventBus.boss_started.emit("測試頭目", 100)
	await frames(2)
	check(bar.is_open() and bar.scale.x < 1.0, "頭目登場時血條從中間開始展開")
	for i in 90:
		await runner.get_tree().physics_frame
		if bar.scale.x >= 0.99:
			break
	check(bar.scale.x >= 0.99, "展開完成後是完整寬度")
	EventBus.boss_health_changed.emit(70, 100)
	check(is_equal_approx(bar.ratio(), 0.7) and bar._flash == 0.0, "還沒跨過刻度時不閃")
	EventBus.boss_health_changed.emit(49, 100)
	check(bar._flash > 0.5, "跨過階段刻度時閃一下")
	EventBus.boss_health_changed.emit(30, 100)
	check(is_equal_approx(bar.ratio(), 0.3), "血條跟著血量")
	EventBus.boss_defeated.emit()
	for i in 60:
		await runner.get_tree().physics_frame
		if not bar.is_open():
			break
	check(not bar.is_open(), "頭目擊敗後血條收起")
	await end_level(level)


func _test_credits_tag() -> void:
	var level := await start_level(PropsSuite.level_data())
	var tag := level.hud.credits_tag
	Progression.add_credits(50)
	await frames(2)
	check(tag.value() == 50 and tag._flash > 0.0 and tag._shown < 50.0, "增加信用點時數字往上跳動並閃白")
	for i in 90:
		await runner.get_tree().physics_frame
	check(is_equal_approx(tag._shown, 50.0), "跳動結束後顯示正確數字")
	Progression.credits = 50
	Progression.credits_changed.emit(20, -30)
	await frames(1)
	check(tag.value() == 20 and tag._flash_color == Palette.DANGER, "花費時閃紅")
	await end_level(level)


func _test_banner_kinds() -> void:
	check(Hud._toast_kind("取得 醫療針") == UiBanner.Kind.ITEM, "取得類提示是物品橫幅")
	check(Hud._toast_kind("警告：回收部接近") == UiBanner.Kind.WARNING, "警告類提示是警告橫幅")
	check(Hud._toast_kind("檢查點") == UiBanner.Kind.INFO, "其他是一般橫幅")
	var level := await start_level(PropsSuite.level_data())
	level.hud.show_toast("取得 測試")
	await frames(10)
	check(level.hud.toast_banner.is_showing(), "提示用橫幅顯示")
	check(absf(level.hud.toast_banner.position.x + level.hud.toast_banner.size.x * 0.5 - 320.0) < 3.0, "橫幅水平置中")
	await end_level(level)


func _test_tooltips() -> void:
	var level := await start_level(PropsSuite.level_data())
	var hud := level.hud
	await frames(3)
	check(hud.credits_tag.tooltip_text != "", "信用點有說明")
	check(hud.boss_bar.tooltip_text != "", "頭目血條有說明")
	check(hud.cyber_gauge.mouse_filter == Control.MOUSE_FILTER_PASS, "義體電量可以顯示說明")
	for slot in hud.weapon_bar.row_count():
		check(hud.weapon_bar.get_child(slot).tooltip_text != "", "武器欄第 %d 列有說明" % (slot + 1))
	await end_level(level)


func _test_radio_panel() -> void:
	Story._scenes["test_radio_panel"] = {"mode": "radio", "lines": [{"speaker": "mei", "text": "測試通訊。"}]}
	var layer: DialogueLayer = Story._layer
	# 清掉前面測試留下的通訊佇列與面板，才看得到滑入。
	layer._radio_queue.clear()
	layer._radio_active = false
	layer._radio_root.visible = false
	layer._radio_root.modulate.a = 0.0
	check(Story.play(&"test_radio_panel", false), "可以播放通訊")
	# 播放會同步設定滑入起點；等三個影格可能已超過 0.15 秒，不能代表「剛出現」。
	check(layer._radio_root.visible and layer._radio_root.modulate.a < 1.0, "通訊面板從側邊滑入（剛出現時還沒完全不透明）")
	for i in 40:
		await runner.get_tree().physics_frame
	check(layer._radio_root.modulate.a > 0.95 and layer._radio_root.position.is_equal_approx(DialogueLayer.RADIO_HOME), "滑入後停在定位")
	check(layer._radio_bar.color != Color.BLACK, "講者名字旁有顏色條")
	Story._scenes.erase("test_radio_panel")
	for i in 400:
		await runner.get_tree().physics_frame
		if not layer._radio_active:
			break
