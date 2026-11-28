extends Node
## 死亡與重來的實際流程（NE-472 補驗）：真正的 Main、真正的轉場（不是瞬間完成）、用按鍵事件操作。
## 情境：一般死亡 → 死亡畫面 → 確認鍵重來 → 回到可以操作（量時間）；連續死兩次；死亡畫面時按暫停；
## 換區域的轉場中死亡；第一章第一次死亡（診間劇情）。每段拍一格，最後確認沒有殘留的黑幕或轉場。
## 用法（原生視窗）：godot --path . res://tests/probes/retry_flow.tscn -- --out=<絕對資料夾>

const STREET := "res://data/levels/ch1_street.tres"
const WAREHOUSE := "res://data/levels/ch1_warehouse.tres"
## 從按下重來到可以操作，目標約 1 秒；超過這個上限算失敗。
const CONTROL_LIMIT := 1.6

var _main: Node
var _out := ""
var _checks := 0
var _issues: Array[String] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	Transition.instant = false
	Story.auto_skip = true
	_run.call_deferred()


func _run() -> void:
	var store := RunSaveStore.new("user://retry_flow_probe/slot.json")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(30)
	# 主選單的轉場還沒結束時 Main 會忽略開始，每半秒重按一次（同序章探針）。
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and (_level() == null or not _level().is_initialized()):
		if not bool(_main.call("_route_pending")) and not bool(_main.get("_active_run")):
			_main.call("_on_start_requested", GameState.difficulties[1])
		await _frames(30)
	_check(_level() != null, "Main 開始新遊戲並建立第一個區域")
	await _go_to(STREET, &"street_home")
	# 第一章最初的死亡是診間劇情：確認它結束後回到可以操作，且沒有殘留的黑幕。
	GameState.deaths = 0
	await _kill()
	var clinic_back := await _until(func() -> bool: return _controllable(), 1800)
	_check(clinic_back, "第一章第一次死亡（診間劇情）後回到可以操作")
	await _shot("clinic-back")
	# 一般死亡：死亡畫面 → 確認鍵重來 → 回到可以操作。
	GameState.deaths = 3
	await _ordinary_retry("first")
	# 連續死兩次。
	await _ordinary_retry("second")
	# 死亡畫面時按暫停：選單鎖住，不影響重來。
	await _kill()
	var screen := await _death_screen()
	_check(screen != null, "死亡畫面出現（暫停情境）")
	await _tap(&"pause")
	await _frames(10)
	_check(not _level()._pause_menu._root.visible, "死亡畫面時暫停選單不會打開")
	await _retry_and_measure("after-pause")
	# 換區域的轉場中死亡：轉場結束後一定在可以操作的區域，沒有殘留的黑幕。
	_level().area_requested.emit(WAREHOUSE)
	await _frames(3)
	var player := _player()
	if player != null and not player.is_dead():
		player.health.setup(1, 0.0)
		player.hurtbox.receive(DamageInfo.create(5, Combat.Team.ENEMY, &"retry_flow"))
	await _until(func() -> bool: return not Transition.is_active(), 600)
	var settled := await _until(func() -> bool: return _controllable() or _death_screen_now() != null or _covering_prompt() != null, 900)
	_check(settled, "換區域時死亡，轉場結束後是可以操作、死亡畫面或存檔提示，不是黑畫面")
	await _shot("during-route-settled")
	# 存檔系統拒絕保存「半份死亡」時會問要重試還是留下：選「留在目前區域」，之後應該接到死亡畫面或可以操作。
	if _covering_prompt() != null:
		print("RETRY_FLOW note: death during the route shows the save-refused prompt")
		await _tap(&"ui_down")
		await _tap(&"ui_accept")
		var resolved := await _until(func() -> bool: return _controllable() or _death_screen_now() != null, 900)
		_check(resolved, "選「留在目前區域」後接到死亡畫面或可以操作")
	if _death_screen_now() != null:
		await _retry_and_measure("during-route")
	await _shot("during-route-end")
	_check(not Transition.is_active() and not UiLayers.presentation_busy(get_tree()), "死亡情境之後沒有殘留的轉場或黑幕")
	# 第一章的結尾：章末畫面（黑底）→ Main 接手（結算或下一章）；不能停在黑畫面。
	# 直接走真的結尾流程（和天亮的當舖進場後結束同一條路），不靠劇情旗標走到那一區。
	var ending_level := _level()
	ending_level.set("_finished", true)
	ending_level.call("_run_ending")
	var card_seen := await _until(func() -> bool: return UiLayers.presentation_busy(get_tree()), 600)
	_check(card_seen, "章末畫面出現")
	await _shot("chapter-end-card")
	var reached := await _until(func() -> bool: return not Transition.is_active() and (_main.get("_screen") is VictoryScreen or (_level() != null and _level().data.chapter != &"ch1_kasa" and _controllable())), 3600)
	_check(reached, "第一章結尾從天亮的當舖走到結算畫面或下一章（目前在 %s）" % [_main.get("_screen")])
	await _frames(20)
	await _shot("chapter-end-results")
	_check(not UiLayers.presentation_busy(get_tree()), "結算畫面出現後沒有殘留的黑幕")
	print("RETRY_FLOW checks=%d issues=%d %s" % [_checks, _issues.size(), _issues])
	get_tree().quit(0 if _issues.is_empty() else 1)


func _ordinary_retry(tag: String) -> void:
	await _kill()
	var screen := await _death_screen()
	_check(screen != null, "一般死亡出現死亡畫面（%s）" % tag)
	await _shot("%s-death-screen" % tag)
	await _retry_and_measure(tag)


func _retry_and_measure(tag: String) -> void:
	await _until(func() -> bool: return get_viewport().gui_get_focus_owner() != null, 240)
	var start := Time.get_ticks_msec()
	await _tap(&"ui_accept")
	await _frames(2)
	if Transition.is_active():
		await _shot("%s-rewind" % tag)
	var back := await _until(func() -> bool: return _controllable(), 900)
	var seconds := float(Time.get_ticks_msec() - start) / 1000.0
	_check(back, "按下重來後回到可以操作（%s）" % tag)
	_check(seconds <= CONTROL_LIMIT, "從按下重來到可以操作 %.2f 秒，不超過 %.1f 秒（%s）" % [seconds, CONTROL_LIMIT, tag])
	print("RETRY_FLOW %s control_after=%.2fs" % [tag, seconds])
	await _shot("%s-back" % tag)
	var start_x := _player().global_position.x if _player() != null else 0.0
	await _hold(&"move_right", 20)
	_check(_player() != null and _player().global_position.x > start_x + 2.0, "重來後真的能移動（%s）" % tag)


func _go_to(path: String, portal: StringName) -> void:
	GameState.pending_portal = portal
	_level().area_requested.emit(path)
	await _until(func() -> bool: return _level() != null and _level().data.resource_path == path and _controllable(), 1200)
	_check(_level() != null and _level().data.resource_path == path, "走到 %s" % path)


func _kill() -> void:
	var player := _player()
	if player == null:
		return
	player.health.setup(1, 0.0)
	player.hurtbox.receive(DamageInfo.create(5, Combat.Team.ENEMY, &"retry_flow"))
	await _frames(2)


func _death_screen() -> DeathScreen:
	await _until(func() -> bool: return _death_screen_now() != null, 900)
	return _death_screen_now()


func _death_screen_now() -> DeathScreen:
	var level := _level()
	if level == null:
		return null
	for child in level.get_children():
		if child is DeathScreen:
			return child
	return null


func _controllable() -> bool:
	var level := _level()
	var player := _player()
	return level != null and level.is_initialized() and player != null and not player.is_dead() \
		and player.state == Player.State.NORMAL and not GameplayLock.is_locked() and not Transition.is_active() \
		and not get_tree().paused and not Story.is_cinematic_active()


## 蓋住遊戲的提示（例如存檔被拒絕時的重試提示），沒有就回傳 null。
func _covering_prompt() -> Node:
	for node in get_tree().get_nodes_in_group(UiLayers.COVER_GROUP):
		if node is Control and (node as Control).is_visible_in_tree() and not node is DeathScreen:
			return node
	return null


func _level() -> Level:
	return _main.get("_screen") as Level if is_instance_valid(_main) else null


func _player() -> Player:
	var level := _level()
	return level.player if level != null and is_instance_valid(level.player) else null


func _tap(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(2)
	var release := InputEventAction.new()
	release.action = action
	Input.parse_input_event(release)
	await _frames(2)


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


func _until(condition: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_issues.append(what)
	print("RETRY_FLOW %s %s" % ["PASS" if ok else "FAIL", what])


func _shot(tag: String) -> void:
	if _out.is_empty():
		return
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	image.save_png(_out.path_join("retry-%s.png" % tag))
