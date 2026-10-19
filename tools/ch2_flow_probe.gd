extends "res://tools/ch1_flow_probe.gd"
## 第二章正式劇本流程探針（ST-19）：用真的區域、真的人物／物件互動與真的選擇，從第一章收尾後的早上推到第二章章末。
## 用法：godot --path . res://tools/ch2_flow_probe.tscn -- --out=<絕對路徑資料夾> [--route=cut|keep] [--supper=stay|leave] [--pay]
## 阿勇戰（NE-265）與市集遭遇（NE-266）由戰鬥組製作：這裡在頭目戰的血量門檻播真的選擇場景，
## 再以頭目戰交出的結果旗標（制伏、隔離）銜接，只驗故事流程與畫面，不代表真人整章通關。

var _supper := "stay"
var _pay := false
var _guest_book_only := false


func _ready() -> void:
	level_pattern = "res://data/levels/ch2_%s.tres"
	_route = "cut"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--supper="):
			_supper = arg.trim_prefix("--supper=")
		elif arg == "--guest-book-only":
			_guest_book_only = true
		elif arg == "--pay":
			_pay = true
	super._ready()


func _run() -> void:
	_shots = {
		"ch2_t_s17_book": "BG-46-book", "ch2_t_s17_open:choice": "BG-46-reservations", "ch2_t_s21_close": "BG-46-close",
		"ch2_t_s01_settle:choice": "ST-19-s01-settle", "ch2_t_s02_power:choice": "ST-19-s02-radio",
		"ch2_t_s03_brief": "ST-19-s03-brief", "ch2_t_s06_open:choice": "ST-19-s06-ask-or-pay",
		"ch2_t_s07_bowls:choice": "ST-19-s07-bowls", "ch2_t_s10_principal:choice": "ST-19-s10-reconcile",
		"ch2_t_s11_xiaowei": "ST-19-s11-xiaowei", "ch2_t_s12_choice:choice": "ST-19-s12-choice",
		"ch2_t_s14_return": "ST-19-s14-214", "ch2_t_s15_upload": "ST-19-s15-ye",
		"ch2_t_s16_page:choice": "ST-19-s16-page", "ch2_t_s18_name:choice": "ST-19-s18-zheng", "ch2_t_s22_tea:choice": "ST-19-s22-tea",
	}
	if _guest_book_only:
		await _run_guest_book_only()
		return
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	Story.auto_skip = false
	# 第一章收尾的真實結果：資料盤已交、回執與摘要在手、宵夜照選擇（留下才知道地址）。
	for done in [&"ch1_complete", &"ch1_handoff_done", &"ch1_supper_done", &"ledger_disk_obtained"]:
		GameState.set_flag(done)
	if _supper == "stay":
		GameState.set_flag(&"knows_ali_address")
	var credits := Progression.credits
	# H1 當舖：進場的一句話，老 K 結算七百二十，修收音機（先接錯一次）。
	await _enter("pawnshop")
	_check(_object(&"ch2_old_k") != null and _object(&"ch2_old_k").is_present(), "Old K waits at the counter in the morning")
	await _talk(&"ch2_old_k", ["settle"])
	_check(GameState.has_flag(&"ch2_morning_settled") and Progression.credits == credits + 720, "the morning settlement pays 720 once (%d)" % (Progression.credits - credits))
	await _talk(&"ch2_old_k")
	_check(Progression.credits == credits + 720, "talking to Old K again does not pay twice")
	await _talk(&"ch2_radio", ["antenna", "power", "antenna", "speaker", "middle", "save"])
	_check(GameState.has_flag(&"ch2_radio_repaired") and GameState.has_flag(&"sq4_broadcast_heard") and StoryItems.holds(&"ch2_radio_clip"),
			"a wrong hole only buzzes; the repaired radio plays the broadcast and saves the clip")
	# H7 屋頂：簡報拿查核證，再問週日。
	await _enter("rooftop")
	await _talk(&"ch2_egret")
	_check(GameState.has_flag(&"ch2_brief_done") and StoryItems.holds(&"ch2_check_card"), "the rooftop brief hands over the check card")
	await _talk(&"ch2_egret", ["sunday"])
	_check(GameState.has_flag(&"sq2_sunday_heard"), "asking about Sunday is an optional explicit topic")
	# H12a 入口與 H12b 代收處。
	await _enter("market_gate")
	await _talk(&"ch2_patroller")
	_check(GameState.has_flag(&"ch2_gate_checked"), "the patroller checks the card")
	await _enter("market")
	var before := Progression.credits
	if _pay:
		await _talk(&"ch2_vig", ["pay", "confirm"])
		_check(Progression.credits == before - 40 and int(GameState.get_flag(&"ali_advance_40")) == 40, "paying advances exactly 40")
		await _talk(&"ch2_ali_market", ["ask"])
		_check(GameState.has_flag(&"ch2_ali_need_asked"), "after paying, Pear can still be asked what she needs")
	else:
		await _talk(&"ch2_vig", ["ask"])
		_check(GameState.has_flag(&"ch2_ali_need_asked") and Progression.credits == before + 20, "asking first gives the need node reward")
	_check(GameState.has_flag(&"ch2_market_contact_done") and StoryItems.holds(&"ch2_evidence_receipt"), "both routes keep the receipt copy")
	await _talk(&"ch2_rent_window")
	await _talk(&"ch2_banyan")
	await _talk(&"ch2_notice_screen")
	await _talk(&"ch2_hawker")
	_check(GameState.has_flag(&"ch2_evidence_contract") and GameState.has_flag(&"ch2_banyan_heard"), "the contract copy and Banyan's story")
	# H21 阿梨家：先放錯架子一次。
	await _enter("ali_home")
	await _talk(&"ch2_ali_home", ["wash", "right", "left"])
	_check(GameState.has_flag(&"sq1_soup_practice_done") and GameState.has_flag(&"knows_ali_address"), "washing and tasting completes the soup node and leaves the address known")
	# H12c 貨道：守衛、橋梯、代收簿、對帳（先犯兩種錯）。
	await _enter("loading")
	await _talk(&"ch2_guard")
	await _talk(&"ch2_sc1_lever")
	await _talk(&"ch2_drying_desk")
	_check(not GameState.has_flag(&"ch2_market_reconciled"), "the desk points to the missing collection book first")
	await _talk(&"ch2_collection_book")
	await _talk(&"ch2_drying_desk", ["total", "principal", "contract", "collection", "north"])
	_check(GameState.has_flag(&"ch2_sc1_open") and GameState.has_flag(&"ch2_market_reconciled"), "the shortcut opens and the reconciliation proves the double 20")
	# H13 前室與帳房：登場、頭目戰的選擇（頭目戰呼叫）、制伏結果（頭目戰交出的旗標）。
	await _enter("ledger_front")
	await _talk(&"ch2_isolation_diagram")
	await _talk(&"ch2_ledger_door")
	_check(GameState.has_flag(&"ch2_yong_intro_seen"), "Yong's introduction opens the office door")
	await _enter("ledger_office")
	await _talk(&"ch2_ledger_cabinet")
	_check(not GameState.has_flag(&"ch2_original_ledger_taken"), "the cabinet stays locked before Yong is subdued")
	var played := [false]
	var choose := func() -> void:
		played[0] = await Story.play_and_wait(&"ch2_t_s12_choice", false)
	choose.call()
	await _drive(["back", _route], func() -> bool: return played[0])
	_check(str(GameState.get_flag(&"yong_link_choice")) == _route, "the boss-fight choice records the intent (%s)" % GameState.get_flag(&"yong_link_choice"))
	if _route == "keep":
		for scene in [&"ch2_t_s12_keep_revival", &"ch2_t_s12_keep_pause"]:
			var finished := [false]
			var run := func() -> void:
				finished[0] = await Story.play_and_wait(scene, false)
			run.call()
			await _drive([], func() -> bool: return finished[0])
		_check(int(GameState.get_flag(&"xiaowei_read_count")) == 1 and not GameState.has_flag(&"xiaowei_yellow_umbrella_recognized"), "the keep route reads Vee exactly once")
	else:
		GameState.set_flag(&"yong_link_isolated")
		GameState.set_flag(&"yong_link_revoked")
	GameState.set_flag(&"ch2_yong_subdued")
	before = Progression.credits
	await _talk(&"ch2_ledger_cabinet")
	_check(StoryItems.holds(&"ch2_original_ledger") and StoryItems.holds(&"ch2_clinic_index") and StoryItems.holds(&"ch2_ali_page") and Progression.credits == before + 120,
			"subduing Yong pays 120 once and the cabinet gives the ledger, index and Pear's page")
	_check(GameState.has_flag(&"ch2_egret_transport_done"), "Egret is carried out through the family exit")
	# B3 電話亭：鷺的第 214 次。
	await _enter("market_gate")
	await _talk(&"ch2_egret_booth")
	_check(GameState.has_flag(&"ch2_egret_returned") and int(GameState.get_flag(&"egret_restoration_count")) == 214, "Egret returns once: 213 becomes 214")
	await _talk(&"ch2_egret_booth")
	_check(int(GameState.get_flag(&"egret_restoration_count")) == 214, "revisiting does not count 215")
	# H10 復原館外：上傳、私人帳、客人簿（每位客人先答錯一次）。
	await _enter("lounge_front")
	before = Progression.credits
	await _talk(&"ch2_terminal")
	_check(GameState.has_flag(&"ch2_audit_submitted") and Progression.credits == before + 250, "uploading the evidence pays 250 once")
	await _settle(30)
	await _talk(&"ch2_ali_lounge", ["correct"])
	_check(str(GameState.get_flag(&"ali_ledger_action")) == "correct" and not StoryItems.holds(&"ch2_ali_page"), "Pear decides her own page; the copy goes to her")
	await _talk(&"ch2_guest_entry", ["watch", "zheng", "dad", "ask", "meat", "fish", "chen", "death", "today", "scallion", "soup", "hong", "forgive", "listen", "fine", "heard"])
	_check(GameState.has_flag(&"guest_book_completed"), "the guest book completes after three guests, wrong answers only cost a retry")
	# 章末：屋頂的茶，章節結束。
	var level_done := [false]
	await _enter("rooftop")
	_level.completed.connect(func() -> void: level_done[0] = true)
	await _talk(&"ch2_egret", ["go"])
	for i in STEP_LIMIT:
		if level_done[0]:
			break
		await _settle(2)
	_check(GameState.has_flag(&"ch2_heron_closed") and level_done[0], "the rooftop tea ends the chapter")
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var open_main := catalog.list_for("ch2_heron", "main", false, GameState.world_flags)
	_check(catalog.issues.is_empty() and open_main.is_empty(), "all chapter 2 main quests are complete (%d open: %s)" % [open_main.size(), open_main.map(func(q: Dictionary) -> String: return str(q.get("id")))])
	var open_side := catalog.list_for("ch2_heron", "side", false, GameState.world_flags)
	_check(open_side.is_empty(), "every side quest this route touched is complete (%s)" % [open_side.map(func(q: Dictionary) -> String: return str(q.get("id")))])
	print("CH2_FLOW_PROBE route=%s supper=%s pay=%s failures=%d" % [_route, _supper, _pay, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## BG-46：安排在已上傳查帳的館外，專驗客人簿退出、重入、重試、一次性獎勵；不代稱真人章節通關。
func _run_guest_book_only() -> void:
	_shots.merge({"ch2_t_s18_wrong": "BG-46-zheng-seated", "ch2_t_s19_wrong_death": "BG-46-chen-seated", "ch2_t_s20_wrong": "BG-46-hong-seated"})
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	Story.auto_skip = false
	GameState.set_flag(&"ch2_audit_submitted")
	await _enter("lounge_front")
	var credits := Progression.credits
	await _talk(&"ch2_guest_entry", ["watch", "back"])
	_check(Progression.credits == credits and not GameState.has_flag(&"guest_book_completed"), "leaving before a guest pays nothing")
	# 真正送出略過：未選客人的正確回應前，不能把一串安全預設一路走成發獎。
	_check(Story.play(&"ch2_t_s18_ticket", false), "the guest's first question starts")
	await _settle(4)
	Story.skip_cinematic()
	for tick in 300:
		if not Story.is_cinematic_active():
			break
		await _settle(1)
	_check(not Story.is_cinematic_active(), "skip returns from an unfinished guest")
	_check(Progression.credits == credits and not GameState.has_flag(&"guest_ticket_answered"), "skip does not invent a completed guest or payment")
	if Story.is_cinematic_active():
		Story.reset_active_presentation(&"route")
	await _talk(&"ch2_guest_entry", ["watch", "zheng", "dad", "ask", "meat", "fish", "back"])
	_check(GameState.has_flag(&"guest_ticket_answered") and not GameState.has_flag(&"guest_band_answered") and not GameState.has_flag(&"guest_letter_answered"), "one guest remains complete after returning to Rin")
	_check(Progression.credits == credits + 20, "one completed guest pays exactly twenty")
	await _talk(&"ch2_guest_entry", ["watch", "chen", "death", "today", "scallion", "soup", "back"])
	_check(GameState.has_flag(&"guest_band_answered") and not GameState.has_flag(&"guest_letter_answered"), "re-entry resumes the remaining appointments")
	_check(Progression.credits == credits + 40, "the completed first guest is not paid twice")
	await _talk(&"ch2_guest_entry", ["watch", "hong", "forgive", "listen", "fine", "heard"])
	_check(GameState.has_flag(&"guest_book_completed") and Progression.credits == credits + 100, "three guests plus closing pay one hundred total")
	await _talk(&"ch2_guest_entry")
	_check(Progression.credits == credits + 100, "the finished book revisit never pays again")
	_check(not get_tree().paused and not Story.is_cinematic_active(), "returning to Rin releases the story pause")
	var file := FileAccess.open(_out_dir.path_join("guest-book-result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"kind": "arranged real interaction fixture, not a human playthrough", "engine": Engine.get_version_info().string,
			"credit_delta": Progression.credits - credits, "failures": _failures, "book_complete": GameState.has_flag(&"guest_book_completed"), "paused": get_tree().paused}, "\t") + "\n")
	print("CH2_GUEST_BOOK_PROBE failures=", _failures)
	if is_instance_valid(_level):
		_level.queue_free()
		await _settle(3)
	get_tree().quit(1 if _failures > 0 else 0)
