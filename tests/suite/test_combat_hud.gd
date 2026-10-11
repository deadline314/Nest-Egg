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
	await _test_radio_card()


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


## 通訊對話框的外觀（NE-274）：名牌只有名字；講者的顏色用在頭像框與名牌；頭像格是固定的方格、沒有頭像也不留空框；
## 長句之後接短句會縮回去；看得出這一句還會停多久；字不超出面板。
func _test_radio_card() -> void:
	var level := await start_level(PropsSuite.level_data())
	var layer: DialogueLayer = Story._layer
	var old_skip := Story.auto_skip
	Story.auto_skip = false
	layer.cancel_radio()
	await frames(2)
	var card := layer._radio_root as RadioCard
	check(card != null, "通訊對話框是通訊卡片")
	if card == null:
		Story.auto_skip = old_skip
		await end_level(level)
		return
	var long_line: Array[Dictionary] = [{"name": "老K", "color": Color("ffd23f"), "portrait": "res://art/portraits/old_k.png",
		"text": "倉庫的電是從隔壁偷接的，燈會閃。看到快壞的燈就繞過去，別站在下面。"}]
	layer.enqueue_radio(&"test_card_long", long_line)
	# 卡片在自己的畫面更新裡跟上講者的顏色：等到它更新過（機器忙的時候幾個物理影格可能擠在同一個畫面影格）。
	for i in 60:
		await frames(1)
		if card._cell_box.border.is_equal_approx(Color("ffd23f")):
			break
	check(layer._radio_name.text == "老K", "名牌只寫講者的名字（%s）" % layer._radio_name.text)
	check(card._cell_box.border.is_equal_approx(Color("ffd23f")) and card._box.bracket.a > 0.0 and card._plate_box.border != RadioCard.EDGE,
			"頭像框、角標與名牌的邊用講者的顏色")
	check(card.radio_speaking(), "字還在出現時訊號格是「講話中」")
	var early := card.size.y
	check(layer.radio_hold_ratio() < 0.0, "字還在出現時不顯示停留線")
	for i in 600:
		if layer._radio_text.visible_ratio >= 1.0:
			break
		await frames(1)
	await frames(3)
	var tall := card.size.y
	var cell := card._cell.size
	check(layer._radio_text.get_line_count() >= 2, "長句排成兩行")
	check(is_equal_approx(early, tall), "面板一出現就是兩行的高度，逐字顯示時不會中途長高（%.0f → %.0f）" % [early, tall])
	check(is_equal_approx(cell.x, RadioCard.PORTRAIT_SIZE) and is_equal_approx(cell.y, RadioCard.PORTRAIT_SIZE), "頭像格是固定的方格，不跟著句子拉長（%s）" % cell)
	check(card.get_global_rect().grow(1.0).encloses(layer._radio_text.get_global_rect()), "字在面板裡面")
	var first := layer.radio_hold_ratio()
	await frames(30)
	var later := layer.radio_hold_ratio()
	check(first > 0.0 and first <= 1.0 and later < first and not card.radio_speaking(), "整句出現後停留線開始倒數（%.2f → %.2f）" % [first, later])
	# 接一句沒有頭像的短句：縮回一行、頭像格還在。
	layer.cancel_radio()
	var short_line: Array[Dictionary] = [{"name": "不明訊號", "color": Color("9aa7b4"), "portrait": "", "text": "有人嗎。"}]
	layer.enqueue_radio(&"test_card_short", short_line)
	for i in 60:
		await frames(1)
		if card._cell_box.border.is_equal_approx(Color("9aa7b4")) and card.size.y < tall - 4.0:
			break
	check(card.size.y < tall - 4.0, "長句之後接短句，面板縮回去（%.0f → %.0f）" % [tall, card.size.y])
	check(not card.portrait.visible and card._cell.visible and is_equal_approx(card._cell.size.x, RadioCard.PORTRAIT_SIZE),
			"沒有頭像的講者：頭像格還在（畫只有聲音的波形），不留空框")
	check(card._cell_box.border.is_equal_approx(Color("9aa7b4")), "換講者時顏色跟著換")
	layer.cancel_radio()
	Story.auto_skip = old_skip
	await end_level(level)
