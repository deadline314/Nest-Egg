extends "res://tools/ch2_resume_probe.gd"
## 第三章死亡與跨程序讀檔探針（ST-21）：每個模式都在獨立的程序裡從真正的 Main 進入，存檔放在 --save-dir。
## 用法：godot --path . res://tools/ch3_resume_probe.tscn -- --mode=write|continue --save-dir=<絕對路徑> --out=<截圖資料夾>
##   write：新遊戲後帶著第二章章末的結果走進第三章：早飯出門、排水接電叫貨梯、在診所拿三份資料並核對（一百八十）；
##          在診所死一次，從檢查點重來後款項收據、文件與水電開關都不重算也不消失；最後像玩家一樣退出（會存檔）。
##   continue：另一個程序按「繼續遊戲」：回到存檔的區域，早飯、櫃檯與核對都不重播，一百八十只記一次，
##          文件還在手上、貨梯仍然接通；再到門禁大廳掃夾層證，證明讀檔後還能往下推。

const CH3_DONE_SCENES: Array[StringName] = [&"ch3_t_c00_breakfast", &"ch3_t_c04_counter", &"ch3_t_c08_result", &"ch3_t_c02_call"]
const CH3_RECEIPTS: Array[StringName] = [&"ch3.report_reconciled"]
const CH3_DOCUMENTS: Array[StringName] = [&"ch2_clinic_index", &"ch3_review_slip", &"ch3_report_p17", &"ch3_roster_n17", &"ch3_register_t17",
		&"ch3_petition_receipt", &"ch3_mezz_pass"]
const WORLD_FLAGS: Array[StringName] = [&"ch3_pump_low", &"ch3_wet_branch_isolated", &"ch3_lift_powered", &"ch3_freight_ready", &"ch3_report_reconciled"]


func _ready() -> void:
	super._ready()
	level_pattern = "res://data/levels/ch3_%s.tres"


func _holds_all() -> bool:
	return CH3_DOCUMENTS.all(func(id: StringName) -> bool: return StoryItems.holds(id))


func _flags_all() -> bool:
	return WORLD_FLAGS.all(func(id: StringName) -> bool: return GameState.has_flag(id))


func _write() -> void:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	var started := false
	while Time.get_ticks_msec() < deadline and _main_level() == null:
		if not started and not bool(_main.call("_route_pending")):
			_main.call("_on_start_requested", GameState.difficulties[1])
			started = _main.get("_active_run")
		await _settle(30)
	_check(_main_level() != null, "a new game from Main enters the first area")
	# 開場演出還在播時寫入的東西會在換區時跟著演出一起撤回：先像玩家一樣看完開場，再帶入前章的結果。
	for i in STEP_LIMIT:
		if not Story.is_cinematic_active():
			break
		Story.skip_cinematic()
		await _settle(4)
	# 第二章章末的真實結果（初次建檔已做過），診所索引在手。
	for done in [&"ch1_complete", &"ch2_heron_closed", &"ch2_audit_submitted", &"ch1_first_death_done"]:
		GameState.set_flag(done)
	GameState.set_flag(&"yong_link_choice", "keep")
	StoryItems.acquire(&"ch2_clinic_index")
	await _enter("pawnshop")
	await _talk(&"ch3_old_k", ["go"])
	await _enter("plaza")
	await _talk(&"ch3_control_box")
	await _enter("pump")
	await _talk(&"ch3_drain_wheel", ["drain"])
	await _talk(&"ch3_branch_panel", ["branch", "power"])
	await _enter("plaza")
	await _talk(&"ch3_control_box")
	await _enter("mezzanine")
	await _enter("clinic")
	await _talk(&"ch3_zhi", ["go"])
	await _talk(&"ch3_public_report", ["save"])
	await _talk(&"ch3_nursing_board", ["eleven"])
	await _talk(&"ch3_register_cabinet", ["save"])
	await _talk(&"ch3_reading_desk", ["hundred", "eleven", "tracked"])
	_check(_receipts() == CH3_RECEIPTS.map(func(id: StringName) -> String: return String(id)), "before dying the ledger holds the reconciliation payment (%s)" % [_receipts()])
	_check(_holds_all() and _flags_all(), "the documents and the water and power switches are all set before dying")
	var before := {"receipts": _receipts(), "deaths": GameState.deaths}
	# 診所裡死一次：死亡畫面上按「立即再挑戰」，Main 從檢查點重新載入。
	var dead_level := _level
	var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"probe")
	lethal.ignore_invulnerability = true
	_level.player.health.take_damage(lethal)
	var screen: DeathScreen = null
	for i in STEP_LIMIT:
		screen = _find_death_screen()
		if screen != null:
			break
		await get_tree().physics_frame
	_check(screen != null, "dying in the clinic shows the death screen")
	if screen != null:
		await _settle(30)
		screen.retry_requested.emit()
	var retry_path := GameState.checkpoint_level_path if GameState.has_checkpoint and not GameState.checkpoint_level_path.is_empty() else level_pattern % "clinic"
	_check(await _wait_level(retry_path, dead_level), "retry reloads the checkpoint area %s" % retry_path.get_file())
	_level = _main_level()
	await _settle(60)
	_check(GameState.deaths == int(before["deaths"]) + 1, "the death is counted once")
	_check(_receipts() == before["receipts"], "dying neither repeats nor drops the reconciliation payment (%s)" % [_receipts()])
	_check(_holds_all() and _flags_all(), "documents and world switches survive the death")
	_check(Story.resolve_dispatch(&"ch3_dispatch_reconcile") == &"ch3_t_c08_revisit", "the reading desk does not reopen the checks after the retry")
	print("CH3_RESUME_WRITE level=%s deaths=%d receipts=%s" % [_level.data.resource_path, GameState.deaths, _receipts()])


func _continue() -> void:
	var store := _main.get("_run_store") as RunSaveStore
	var data: Dictionary = store.read()
	_check(not data.is_empty(), "the previous process left a readable save")
	var saved_credits := int((data.get("progression", {}) as Dictionary).get("credits", -1))
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < deadline and bool(_main.call("_route_pending")):
		await _settle(10)
	_main.call("_on_continue_requested")
	var saved_level := str(data.get("level", ""))
	_check(await _wait_level(saved_level), "continue lands back in the saved area %s" % saved_level.get_file())
	_level = _main_level()
	await _settle(120)
	_check(Progression.credits == saved_credits, "credits come back exactly as saved (%d)" % Progression.credits)
	_check(_receipts() == CH3_RECEIPTS.map(func(id: StringName) -> String: return String(id)), "the reconciliation payment is recorded once (%s)" % [_receipts()])
	_check(_holds_all() and _flags_all(), "documents and world switches come back with the save")
	_check(GameState.deaths == 1, "the death from the previous process is remembered")
	_check(not _played.any(func(id: StringName) -> bool: return CH3_DONE_SCENES.has(id)), "no finished scene replays on continue (played %s)" % [_played])
	await _enter("clinic")
	var credits := Progression.credits
	await _talk(&"ch3_zhi")
	_check(Progression.credits == credits and _receipts().size() == 1, "Sister Zhi does not pay again after continue")
	await _enter("gate_hall")
	await _talk(&"ch3_scanner_gate")
	_check(GameState.has_flag(&"ch3_janus_intro_seen"), "the mezzanine pass still works at the gate after continue")
