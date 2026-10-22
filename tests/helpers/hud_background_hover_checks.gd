extends RefCounted
## NE-228：背景 HUD 的 Hover 說明不能蓋住暫停頁、人物交談或通訊。
## 用真的滑鼠移動事件走引擎的 Hover 與說明計時，量測引擎實際建立的說明視窗，不手造彈出框。

const WAIT_MS := 1600


static func run(suite: TestSuite) -> void:
	var level := await suite.start_level(PropsSuite.level_data())
	var hud := level.hud
	var target: Control = hud.credits_tag
	await suite.frames(3)
	var vp := target.get_viewport()
	var spot := target.get_global_rect().get_center()
	suite.check(hud.hover_guard != null and not hud.hover_guard.blocked, "一般遊玩時背景說明可以使用")

	# 1. 已顯示的說明：開暫停頁時當下收起，選單焦點不受影響。
	_park(vp)
	await suite.frames(2)
	_move(vp, spot)
	var shown := await _wait_tooltip(suite, target, true)
	suite.check(shown, "停住滑鼠時 HUD 說明真的出現（前置條件）")
	var pause: PauseMenu = level._pause_menu
	pause.open()
	await suite.frames(1)
	suite.check(hud.hover_guard.blocked, "暫停頁打開時守門啟動")
	suite.check(_tooltip(target) == null, "暫停頁打開時已顯示的背景說明立即收起")
	_move(vp, spot + Vector2(1, 0))
	suite.check(not await _wait_tooltip(suite, target, true), "暫停期間停在 HUD 上也不再冒出背景說明")
	suite.check(pause._resume_button.has_focus(), "暫停頁的焦點維持在「繼續」")
	suite.check(target.tooltip_text != "" and target.mouse_filter != Control.MOUSE_FILTER_IGNORE, "原本的說明文字與滑鼠設定沒有被改寫")
	pause.close()
	await suite.frames(2)
	suite.check(not hud.hover_guard.blocked, "關閉暫停頁後守門解除")
	_park(vp)
	await suite.frames(2)
	_move(vp, spot)
	suite.check(await _wait_tooltip(suite, target, true), "回到遊戲後重新停住滑鼠，說明可以再次出現")

	# 2. 等待中的說明：還沒出現就進入人物交談，之後也不能晚冒出來。
	_park(vp)
	await suite.frames(2)
	_move(vp, spot)
	await suite.frames(1)
	var layer: DialogueLayer = Story._layer
	layer.start_cinematic(&"ne228_hover_guard", [{"name": "測試", "color": Color.WHITE, "text": "背景說明不能蓋住這一句。", "portrait": ""}])
	await suite.frames(1)
	suite.check(hud.hover_guard.blocked, "人物交談期間守門啟動")
	suite.check(not await _wait_tooltip(suite, target, true), "交談開始前排程中的說明不會在交談時冒出來")
	layer.cancel_cinematic()
	await suite.frames(2)
	suite.check(not hud.hover_guard.blocked, "交談結束後守門解除")

	# 3. 通訊不暫停世界，面板可見期間也收起背景說明。
	_park(vp)
	await suite.frames(2)
	_move(vp, spot)
	suite.check(await _wait_tooltip(suite, target, true), "通訊前說明正常出現（前置條件）")
	Story._scenes["ne228_hover_radio"] = {"mode": "radio", "lines": [{"speaker": "mei", "text": "測試通訊。"}]}
	suite.check(Story.play(&"ne228_hover_radio", false), "可以播放通訊")
	suite.check(DialogueLayer.radio_visible() and hud.hover_guard.blocked, "通訊顯示的同次呼叫立即收起背景說明")
	suite.check(_tooltip(target) == null, "通訊入場不等下一格才取消真實說明視窗")
	await suite.frames(2)
	suite.check(DialogueLayer.radio_visible() and hud.hover_guard.blocked, "通訊面板出現時守門啟動")
	suite.check(_tooltip(target) == null, "通訊出現時已顯示的背景說明立即收起")
	Story._scenes.erase("ne228_hover_radio")
	layer.cancel_radio()
	suite.check(not hud.hover_guard.blocked, "通訊關閉的同次呼叫立即恢復背景說明")
	# 通訊收尾可能延後幾個影格（平行測試負載下觀察到），以上限等待取代固定影格數。
	for i in 30:
		await suite.frames(1)
		if not hud.hover_guard.blocked:
			break
	suite.check(not hud.hover_guard.blocked, "通訊結束後守門解除")
	_park(vp)

	# Additional real owners use visibility, including delay and leaving the tree.
	var other := DialogueLayer.new()
	suite.runner.get_tree().root.add_child(other)
	var delayed: Array[Dictionary] = [{"name": "測試", "color": Color.CYAN, "portrait": "", "text": "延遲通訊。", "delay": 0.2}]
	other.enqueue_radio(&"ne228_other_radio", delayed)
	suite.check(not DialogueLayer.radio_visible() and not hud.hover_guard.blocked, "延遲且尚未顯示的通訊不阻擋背景說明")
	other.cancel_radio()
	var line := delayed[0].duplicate()
	line.erase("delay")
	var immediate: Array[Dictionary] = [line]
	other.enqueue_radio(&"ne228_other_radio", immediate)
	suite.check(DialogueLayer.radio_visible() and hud.hover_guard.blocked, "第二個真通訊來源同次顯示也立即守門")
	layer.enqueue_radio(&"ne228_parallel_radio", immediate)
	layer.cancel_radio()
	suite.check(other._radio_root.visible and hud.hover_guard.blocked, "其中一個來源關閉不解除另一個可見來源的守門")
	other.cancel_radio()
	suite.check(not DialogueLayer.radio_visible() and not hud.hover_guard.blocked, "最後一個可見來源關閉立即解除守門")
	other.enqueue_radio(&"ne228_other_radio", immediate)
	suite.check(DialogueLayer.radio_visible() and hud.hover_guard.blocked, "離樹案例先見證真的可見來源與守門")
	other.get_parent().remove_child(other)
	suite.check(not DialogueLayer.radio_visible() and not hud.hover_guard.blocked, "可見來源離開場景樹立即解除守門")
	other.queue_free()

	# 4. 操作提示卡：暫停頁打開時收起，關閉後依情境回來，閱讀時間不被暫停吃掉。
	await suite.frames(2)
	suite.check(hud._controls_card.visible, "新遊戲的操作提示正常顯示（前置條件）")
	var read_left: float = hud._controls_read_time
	pause.open()
	await suite.frames(3)
	suite.check(not hud._controls_card.visible, "暫停頁打開時背景的操作提示收起")
	suite.check(is_equal_approx(hud._controls_read_time, read_left), "暫停期間不消耗提示的閱讀時間")
	pause.close()
	await suite.frames(2)
	suite.check(hud._controls_card.visible, "關閉暫停頁後操作提示回來")
	await suite.end_level(level)


static func _move(vp: Viewport, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	vp.push_input(ev, true)


## 移到畫面外的空白處，讓下一次移入重新開始說明計時。
static func _park(vp: Viewport) -> void:
	_move(vp, Vector2(-40, -40))


static func _tooltip(owner: Control) -> Window:
	for child in owner.get_children(true):
		var win := child as Window
		if win != null and win.visible and not win.is_queued_for_deletion():
			return win
	return null


## 等待說明出現（want=true），回傳期間內是否出現；說明延遲預設 0.5 秒，最多等 WAIT_MS。
static func _wait_tooltip(suite: TestSuite, owner: Control, want: bool) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		await suite.frames(1)
		if (_tooltip(owner) != null) == want:
			return true
	return false
