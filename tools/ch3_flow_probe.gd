extends "res://tools/ch1_flow_probe.gd"
## 第三章正式劇本流程探針（ST-21）：用真的區域、真的人物／物件互動與真的選擇，從第二章章末之後的週日早上推到第三章章末。
## 用法：godot --path . res://tools/ch3_flow_probe.tscn -- --out=<絕對路徑資料夾> [--route=full|minimal] [--yong=cut|keep] [--skip-cutscenes]
##   --skip-cutscenes：開著設定的「略過過場動畫」整章推一次（要做決定的場景仍要照常讓玩家選），結束時還原設定。
##   full：三份資料先犯錯再改、借出錄音、量窗記提案、看清手背的字、告訴鷺交易。
##   minimal：只走主線（不借錄音、不提案、不讀手背的字、只跟鷺說報表），證明支線都不是主線的門。
## 守門人戰（戰鬥組）以機關頻道交出的停機結果銜接，只驗故事流程與畫面，不代表真人整章通關。

var _yong := "cut"
var _skip_setting := false
var _previous_skip := false


func _ready() -> void:
	level_pattern = "res://data/levels/ch3_%s.tres"
	_route = "full"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--yong="):
			_yong = arg.trim_prefix("--yong=")
		elif arg == "--skip-cutscenes":
			_skip_setting = true
	super._ready()


func _full() -> bool:
	return _route == "full"


func _wait_flag(flag: StringName, frames := 900) -> bool:
	for i in frames:
		if GameState.has_flag(flag):
			return true
		await _settle(2)
	return GameState.has_flag(flag)


func _run() -> void:
	_shots = {
		"ch3_t_c00_choice:choice": "ST-21-c00-breakfast", "ch3_t_c02_wheel:choice": "ST-21-c02-wheel",
		"ch3_t_c04_counter": "ST-21-c04-zhi", "ch3_t_c08_population:choice": "ST-21-c08-reconcile",
		"ch3_t_c10_scan": "ST-21-c10-gatekeeper", "ch3_t_c12_aftercare": "ST-21-c12-aftercare",
		"ch3_t_c15_welcome:choice": "ST-21-c15-lin", "ch3_t_c16_propose:choice": "ST-21-c16-proposal",
		"ch3_t_c18_box": "ST-21-c18-wide", "ch3_t_c19_watch": "ST-21-c19-glass", "ch3_t_c20_trade": "ST-21-c20-trade",
		"ch3_t_c20_middle:choice": "ST-21-c20-middle", "ch3_t_c20_rest": "ST-21-c20-rest", "ch3_t_c22_door": "ST-21-c22-supper", "ch3_t_c23_invite:choice": "ST-21-c23-sunday",
	}
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	Story.auto_skip = false
	_previous_skip = Settings.get_skip_cutscenes()
	Settings.set_skip_cutscenes(_skip_setting)
	# 第二章章末的真實結果：章末已過、診所索引在手、阿勇父女依路線（兩路都活著）。
	for done in [&"ch1_complete", &"ch2_heron_closed", &"ch2_audit_submitted", &"ch2_original_ledger_taken", &"harbor_walk_ready"]:
		GameState.set_flag(done)
	GameState.set_flag(&"yong_link_choice", _yong)
	StoryItems.acquire(&"ch2_clinic_index")
	var credits := Progression.credits
	# C00 當舖：早飯、追問一次、確認出門。
	await _enter("pawnshop")
	await _talk(&"ch3_old_k", ["ask", "go"] if _full() else ["go"])
	_check(GameState.has_flag(&"ch3_departure_done"), "breakfast ends with Rin choosing to leave")
	await _talk(&"ch3_old_k")
	_check(GameState.has_flag(&"ch3_departure_done"), "Old K only has a short line after breakfast")
	# C01／C02 廣場與泵室：控制箱、水尺、排水（先轉錯）、隔離（先關錯）、主路、叫車廂、外梯。
	await _enter("plaza")
	await _talk(&"ch3_control_box")
	await _talk(&"ch3_water_gauge")
	await _talk(&"ch3_control_box")
	_check(GameState.has_flag(&"ch3_interlock_seen") and not GameState.has_flag(&"ch3_freight_ready"), "calling the lift too early only explains the interlock")
	await _enter("pump")
	await _talk(&"ch3_branch_panel")
	_check(not GameState.has_flag(&"ch3_wet_branch_isolated"), "the panel is still under water before draining")
	await _talk(&"ch3_drain_wheel", ["back", "drain"])
	_check(GameState.has_flag(&"ch3_pump_low"), "turning the wheel the wrong way only stalls; the right way drains the tank")
	await _talk(&"ch3_branch_panel", ["main", "branch", "power"])
	_check(GameState.has_flag(&"ch3_wet_branch_isolated") and GameState.has_flag(&"ch3_lift_powered"), "the wet branch is isolated and the main line powered")
	await _enter("plaza")
	await _talk(&"ch3_control_box")
	_check(GameState.has_flag(&"ch3_freight_ready"), "the lift comes down only after all three water and power steps")
	await _talk(&"ch3_outer_ladder")
	_check(GameState.has_flag(&"ch3_outer_ladder_down"), "the outer ladder shortcut opens")
	# C03 夾層：進場的兩句話、父女狀態的通知（可選）。
	await _enter("mezzanine")
	_check(await _wait_flag(&"ch3_mezzanine_reached"), "arriving on the mezzanine records the arrival")
	if _full():
		await _talk(&"ch3_notice_terminal")
	# C04～C09 診所。
	await _enter("clinic")
	await _talk(&"ch3_zhi", ["disease"] if _full() else ["go"])
	_check(GameState.has_flag(&"ch3_clinic_access") and StoryItems.holds(&"ch3_review_slip") and StoryItems.holds(&"ch2_clinic_index"),
			"showing the index gives the review number and keeps the index")
	await _talk(&"ch3_reading_desk")
	_check(not GameState.has_flag(&"ch3_report_reconciled"), "the desk names the missing paper first")
	await _talk(&"ch3_public_report", ["save"])
	await _talk(&"ch3_nursing_board", ["twentytwo", "eleven"] if _full() else ["eleven"])
	await _talk(&"ch3_register_cabinet", ["ask", "save"] if _full() else ["save"])
	_check(GameState.has_flag(&"ch3_public_report_taken") and GameState.has_flag(&"ch3_nursing_roster_taken") and GameState.has_flag(&"ch3_followup_register_taken"),
			"the three public papers are saved in any order, a wrong count only costs a retry")
	if _full():
		await _talk(&"ch3_deposit_drawer", ["play", "lend"])
		_check(GameState.has_flag(&"sq7_ahan_recording_held") and StoryItems.holds(&"ch3_ahan_tape"), "Ahan's tape is lent with its slip")
	var before := Progression.credits
	var answers := ["ninetytwo", "hundred", "three", "eleven", "cured", "tracked"] if _full() else ["hundred", "eleven", "tracked"]
	await _talk(&"ch3_reading_desk", answers)
	_check(GameState.has_flag(&"ch3_report_reconciled") and Progression.credits == before + 180 and StoryItems.holds(&"ch3_mezz_pass"),
			"three confirmed facts file the objection, pay 180 once and give the mezzanine pass")
	await _talk(&"ch3_zhi")
	_check(Progression.credits == before + 180, "talking to Sister Zhi again pays nothing more")
	# C10～C12 門禁大廳：登場、停機（戰鬥組的機關頻道）、扶守門人坐回櫃檯。
	await _enter("gate_hall")
	await _talk(&"ch3_scanner_gate")
	_check(GameState.has_flag(&"ch3_janus_intro_seen") and not GameState.has_flag(&"ch3_janus_disabled"), "the gatekeeper introduction does not open the gate")
	EventBus.mechanism_toggled.emit(&"ch3_janus_down", true)
	await _settle(4)
	_check(GameState.has_flag(&"ch3_janus_disabled"), "the boss fight's stop channel writes the disabled flag")
	await _enter("clinic")
	await _enter("gate_hall")
	before = Progression.credits
	await _talk(&"ch3_gatekeeper")
	_check(GameState.has_flag(&"ch3_janus_aftercare_done") and GameState.has_flag(&"ch3_care_passage_open") and Progression.credits == before + 100,
			"helping the gatekeeper back to his chair pays 100 once and opens the care passage")
	# C13／C14 玻璃邊緣。
	await _enter("glass_edge")
	_check(await _wait_flag(&"ch3_sunlight_reached"), "reaching the glass edge records the first sunlight")
	await _talk(&"ch3_light_spot")
	await _talk(&"ch3_telescope")
	# C15～C17 樣品房。
	await _enter("showroom")
	await _talk(&"ch3_lin", ["post"])
	_check(GameState.has_flag(&"ch3_clearwater_tour_started") and StoryItems.holds(&"ch3_tour_card"), "the objection is posted and the tour card given, no deposit")
	await _talk(&"ch3_window_morning")
	if _full():
		await _talk(&"ch3_window_quiet")
		await _talk(&"ch3_window_late")
		before = Progression.credits
		await _talk(&"ch3_lin", ["propose", "late"])
		_check(str(GameState.get_flag(&"room_choice")) == "late" and GameState.has_flag(&"sq3_room_proposal_done") and Progression.credits == before + 20,
				"proposing a measured window records the choice and pays 20 once")
		await _talk(&"ch3_lin", ["ask"])
	await _talk(&"ch3_lin", ["finish"])
	_check(GameState.has_flag(&"ch3_clearwater_tour_done"), "the tour ends after at least one window")
	if not _full():
		_check(str(GameState.get_flag(&"room_choice")) == "unset", "skipping the proposal keeps the room unset")
	# C18～C21 辦公接待廊。
	await _enter("office_hall")
	# 取回執後一路接到手背的字與等候臺的選擇（不走一段看一段）。完整路線在談話中段先退開，回等候臺從中段接著聽；
	# 最短路線在中段伸手推門，被燈叫住後聽完。
	await _talk(&"ch3_petition_box", ["read", "listen", "leave"] if _full() else ["listen", "door", "record"])
	_check(GameState.has_flag(&"ch3_petition_receipt_taken") and GameState.has_flag(&"ch3_k_at_office_seen"), "taking the receipt shows Old K at the office")
	if _full():
		_check(GameState.has_flag(&"ch3_trade_half_heard") and not GameState.has_flag(&"ch3_trade_listened"), "stepping away mid-conversation keeps the first half heard")
		_check(Story.resolve_dispatch(&"ch3_dispatch_bench") == &"ch3_t_c20_middle", "the waiting bench resumes at the middle of the conversation")
		await _talk(&"ch3_waiting_bench", ["stay", "record"])
	_check(GameState.has_flag(&"ch3_trade_overheard") and StoryItems.holds(&"ch3_trade_note"), "the trade is recorded only after Rin confirms the note")
	_check(GameState.has_flag(&"sq7_ye_name_seen") == _full(), "reading the name on Folio's hand is optional")
	_check(await _wait_flag(&"ch3_l2_route_announced"), "Wick announces the walking route home")
	# C22／C23 回家。
	await _enter("pawnshop")
	_check(_object(&"ch3_old_k_kitchen") != null and _object(&"ch3_old_k_kitchen").is_present(), "Old K waits in the kitchen in the evening")
	await _talk(&"ch3_old_k_kitchen", ["note"])
	_check(GameState.has_flag(&"ch3_home_supper_done") and GameState.has_flag(&"ch3_umbrella_asked_twice"), "supper asks about the umbrella twice and ends with the note put away")
	await _talk(&"ch3_old_k_kitchen")
	if GameState.has_flag(&"m3_available"):
		await _talk(&"ch3_unsigned_record")
		_check(GameState.has_flag(&"m3_seen"), "the unsigned record can be read once the gate is down")
	var level_done := [false]
	_level.completed.connect(func() -> void: level_done[0] = true)
	await _talk(&"ch3_shop_radio", ["tell", "agree"] if _full() else ["report", "agree"])
	for i in STEP_LIMIT:
		if level_done[0]:
			break
		await _settle(2)
	_check(GameState.has_flag(&"ch3_shore_closed") and level_done[0], "agreeing to next Sunday ends the chapter")
	_check(GameState.has_flag(&"ch3_told_egret_trade") == _full(), "whether Egret hears about the trade follows the choice")
	_check(Progression.credits - credits == (340 if _full() else 280), "chapter 3 pays %d credits on this route" % (Progression.credits - credits))
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var open_main := catalog.list_for("ch3_clearwater", "main", false, GameState.world_flags)
	_check(catalog.issues.is_empty() and open_main.is_empty(), "all chapter 3 main quests are complete (%d open: %s)" % [open_main.size(), open_main.map(func(q: Dictionary) -> String: return str(q.get("id")))])
	if _full():
		var open_side := catalog.list_for("ch3_clearwater", "side", false, GameState.world_flags)
		_check(open_side.is_empty(), "every side quest is complete on the full route (%s)" % [open_side.map(func(q: Dictionary) -> String: return str(q.get("id")))])
	Settings.set_skip_cutscenes(_previous_skip)
	print("CH3_FLOW_PROBE route=%s yong=%s skip=%s failures=%d" % [_route, _yong, _skip_setting, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
