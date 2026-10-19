extends "res://tools/quest_resume_probe.gd"
## NE-223：宣告的舊檔缺旗標樣本，走 Main 真正保存與獨立程序續玩；不冒充戰鬥清路或整章通關。

func _write() -> void:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while bool(_main.call("_route_pending")) and Time.get_ticks_msec() < deadline:
		await _settle(2)
	_main.call("_on_start_requested", GameState.difficulties[1])
	_check(await _wait_level(PROLOGUE), "Main starts a real new run")
	await _skip_cinematics()
	# 此處刻意安排可重跑的舊檔樣本；不把這些旗標當成玩家實際完成證據。
	StoryItems.acquire(&"ch1_data_disk", false)
	for flag in [&"ch1_prologue_exit", &"ch1_dinner_done", &"ch1_heard_brief", &"ledger_disk_obtained"]:
		GameState.set_flag(flag)
	Story.outcomes.refresh_derived()
	await _enter(PAWNSHOP)
	_verify_route()
	_completed = true


func _continue() -> void:
	await _press_continue(PAWNSHOP)
	await _skip_cinematics()
	_verify_route()
	_completed = true


func _verify_route() -> void:
	var catalog := _guidance().catalog
	var flags := GameState.world_flags
	_check(GameState.has_flag(&"ledger_disk_obtained"), "disk flag is preserved by the real save")
	_check(not GameState.has_flag(&"ch1_street_route_open") and not GameState.has_flag(&"watchdog_defeated") and not GameState.has_flag(&"ch1_flood_gate_open"), "save and continue do not fabricate missing route flags")
	var target := QuestMapState.for_run().target(catalog, "ch1_kasa", flags)
	_check(target.get("id") == "ch1_take_disk", "after real Main entry the incomplete route remains tracked")
	_check(QuestCatalog.current_step(target, flags).get("complete_flag") == "ch1_street_route_open", "next objective remains the actual first missing route step")
	_check(QuestCatalog.status(catalog.find("ch1_take_disk"), flags) == "active", "disk possession does not mark the route completed")
