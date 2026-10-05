class_name TransitionSuite
extends TestSuite
## 畫面轉場（NE-37）：六種轉場都能完成、換內容只執行一次、輸入鎖定與暫停還原、
## 死亡重來不超過 1 秒、減少閃光時降級、不殘留節點。


func run() -> void:
	await _test_all_kinds()
	await _test_pause_state()
	await _test_cutscene_overlap()
	await _test_abort_during_swap()
	await _test_skip()
	await _test_retry_duration()
	await _test_reduced_flashes()
	await _test_busy_fallback()
	await _test_no_leaks()


func _enable() -> void:
	Transition.instant = false


func _disable() -> void:
	Transition.instant = DisplayServer.get_name() == "headless"
	Transition.abort()


func _test_all_kinds() -> void:
	_enable()
	for kind in Transition.Kind.values():
		var calls := [0]
		var state := {"active_inside": false}
		await Transition.play(kind, func() -> void:
			calls[0] += 1
			state["active_inside"] = Transition.is_active(), 0.06)
		check(calls[0] == 1, "轉場 %s 只執行一次內容切換" % Transition.Kind.keys()[kind])
		check(state["active_inside"], "轉場 %s 在換內容時仍是作用中" % Transition.Kind.keys()[kind])
		check(not Transition.is_active(), "轉場 %s 結束後解除" % Transition.Kind.keys()[kind])
	_disable()


func _test_pause_state() -> void:
	_enable()
	var tree := runner.get_tree()
	tree.paused = false
	var inside := [false]
	await Transition.play(Transition.Kind.FADE, func() -> void:
		inside[0] = tree.paused
		tree.paused = false, 0.05)
	check(inside[0], "轉場期間遊戲暫停")
	check(not tree.paused, "轉場結束後還原成未暫停")
	tree.paused = true
	await Transition.play(Transition.Kind.FADE, Callable(), 0.05)
	check(tree.paused, "原本暫停時，轉場結束後仍然暫停")
	tree.paused = false
	_disable()


func _test_skip() -> void:
	_enable()
	var start := Time.get_ticks_msec()
	var press := InputEventKey.new()
	press.pressed = true
	press.keycode = KEY_SPACE
	var task := func() -> void: await Transition.play(Transition.Kind.ELEVATOR, Callable(), 2.0)
	task.call()
	await runner.get_tree().process_frame
	Input.parse_input_event(press)
	await Transition.finished
	var elapsed := float(Time.get_ticks_msec() - start) / 1000.0
	check(elapsed < 3.0, "按鍵可以加速轉場（%.2f 秒，原本 4 秒）" % elapsed)
	_disable()


## 實際進場時，關卡的開場演出會在轉場尚未揭開時開始。
func _test_cutscene_overlap() -> void:
	_enable()
	var tree := runner.get_tree()
	tree.paused = false
	await Transition.cover(Transition.Kind.FADE, 0.03)
	var cinematic := CutscenePlayer.new()
	runner.add_child(cinematic)
	cinematic.play(&"test_overlap", {"overlay": true, "steps": [{"do": "wait", "time": 30.0}]})
	await Transition.reveal(Transition.Kind.FADE, 0.03)
	check(tree.paused, "揭開畫面後仍在演出的過場不能解除暫停")
	var done := [false]
	cinematic.finished.connect(func(_id: StringName) -> void: done[0] = true)
	cinematic.skip()
	for i in 60:
		if done[0]:
			break
		await tree.process_frame
	check(done[0] and not tree.paused, "重疊過場結束後立即恢復，不需要按 Esc")
	tree.paused = false
	# 相反順序：過場先結束，外層轉場還沒揭開。
	cinematic = CutscenePlayer.new()
	runner.add_child(cinematic)
	cinematic.play(&"test_reverse_overlap", {"overlay": true, "steps": [{"do": "wait", "time": 30.0}]})
	await Transition.cover(Transition.Kind.FADE, 0.03)
	done[0] = false
	cinematic.finished.connect(func(_id: StringName) -> void: done[0] = true)
	cinematic.skip()
	for i in 60:
		if done[0]:
			break
		await tree.process_frame
	check(done[0] and tree.paused, "過場先結束時，尚未揭開的轉場仍阻擋操作")
	await Transition.reveal(Transition.Kind.FADE, 0.03)
	check(not tree.paused and not GameplayLock.is_locked(), "反向結束重疊演出也不留下暫停或輸入鎖")
	_disable()


func _test_abort_during_swap() -> void:
	_enable()
	var old_done := [false]
	var play := func() -> void:
		await Transition.play(Transition.Kind.FADE, func() -> void:
			Transition.abort()
			await runner.get_tree().process_frame, 0.03)
		old_done[0] = true
	play.call()
	for i in 120:
		if old_done[0]:
			break
		await runner.get_tree().process_frame
	check(old_done[0] and not runner.get_tree().paused and not Transition.is_active(), "切換回呼中止轉場後，舊協程不會重新暫停遊戲")
	check(not GameplayLock.is_locked(), "中止轉場回收輸入鎖")
	_disable()


func _test_retry_duration() -> void:
	_enable()
	var start := Time.get_ticks_msec()
	await Transition.play(Transition.Kind.GLITCH, Callable(), -1.0, Vector2(0.5, 0.5), "回溯 #1", 0.22)
	var elapsed := float(Time.get_ticks_msec() - start) / 1000.0
	check(elapsed < 1.3, "死亡重來的轉場約 1 秒內結束（%.2f 秒；用實際時間量，機器忙時留 0.3 秒餘裕）" % elapsed)
	_disable()


func _test_reduced_flashes() -> void:
	_enable()
	var previous := Settings.get_reduce_flashes()
	Settings.set_reduce_flashes(true)
	check(Transition._resolve_kind(Transition.Kind.GLITCH) == Transition.Kind.FADE, "減少閃光時雜訊降級為淡入淡出")
	check(Transition._resolve_kind(Transition.Kind.FADE_WHITE) == Transition.Kind.FADE, "減少閃光時閃白降級為淡入淡出")
	check(Transition._resolve_kind(Transition.Kind.SCAN) == Transition.Kind.SCAN, "其他轉場不受影響")
	Settings.set_reduce_flashes(previous)
	_disable()


func _test_busy_fallback() -> void:
	_enable()
	var first := func() -> void: await Transition.play(Transition.Kind.FADE, Callable(), 0.15)
	first.call()
	await runner.get_tree().process_frame
	var ran := [false]
	await Transition.play(Transition.Kind.SCAN, func() -> void: ran[0] = true)
	check(ran[0], "轉場進行中再次呼叫時，內容仍會切換（不吞掉）")
	await Transition.finished
	_disable()


func _test_no_leaks() -> void:
	_enable()
	var before := runner.get_tree().get_node_count()
	for i in 6:
		await Transition.play(Transition.Kind.GLITCH, Callable(), 0.03, Vector2(0.5, 0.5), "回溯 #%d" % i)
	await runner.get_tree().process_frame
	var after := runner.get_tree().get_node_count()
	check(after <= before + 2, "重複轉場不累積節點（%d → %d）" % [before, after])
	_disable()
