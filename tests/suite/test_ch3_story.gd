class_name Chapter3StorySuite
extends TestSuite
## 第三章「晴岸」（ST-21）：共同的地圖與劇本規則（出入口、人物入口、任務標記、正式過場），加上本章的劇情規則：
## 診所要索引才開始、閱覽桌缺什麼說什麼、守門人停機由機關頻道寫入、傍晚老 K 換到廚房、章末旗標結束本章。
## 整章依序推進用 tools/ch3_flow_probe.tscn（完整路線與只走主線兩種）驗；這裡只放快速、穩定的資料與規則檢查。

const AREAS: PackedStringArray = ["pawnshop", "plaza", "pump", "mezzanine", "clinic", "gate_hall", "glass_edge", "showroom", "office_hall"]
const Checks := preload("res://tests/helpers/chapter_story_checks.gd")

var _datas: Dictionary = {}


func run() -> void:
	_datas = Checks.load_areas(self, "ch3", &"ch3_clearwater", AREAS)
	Checks.check_portals(self, "chapter 3", _datas)
	Checks.check_entries(self, "chapter 3", _datas, 24)
	Checks.check_quest_markers(self, "chapter 3", "ch3", "res://data/story/ch3_clearwater.json", _datas, 20)
	_test_story_gates()
	_test_level_hooks()
	Checks.check_staging(self, "chapter 3", "ch3", 9)
	await _test_chapter_end()


## 劇情依進度挑段落。
func _test_story_gates() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	check(str(GameState.get_flag(&"room_choice")) == "unset", "a new run has no room proposal")
	check(Story.resolve_dispatch(&"ch3_dispatch_old_k") == &"ch3_t_c00_breakfast", "the chapter opens with breakfast at the counter")
	check(Story.resolve_dispatch(&"ch3_dispatch_zhi") == &"ch3_t_c04_no_index", "without the clinic index Sister Zhi says where to get it")
	StoryItems.acquire(&"ch2_clinic_index")
	check(Story.resolve_dispatch(&"ch3_dispatch_zhi") == &"ch3_t_c04_counter", "with the index the public check starts")
	check(Story.resolve_dispatch(&"ch3_dispatch_reconcile") == &"ch3_t_c05_locked", "the reading desk needs the review number first")
	GameState.set_flag(&"ch3_clinic_access")
	check(Story.resolve_dispatch(&"ch3_dispatch_reconcile") == &"ch3_t_c08_missing_report", "the desk first asks for the public report")
	GameState.set_flag(&"ch3_public_report_taken")
	check(Story.resolve_dispatch(&"ch3_dispatch_reconcile") == &"ch3_t_c08_missing_roster", "then for the nursing roster")
	GameState.set_flag(&"ch3_nursing_roster_taken")
	check(Story.resolve_dispatch(&"ch3_dispatch_reconcile") == &"ch3_t_c08_missing_register", "then for the follow-up register")
	GameState.set_flag(&"ch3_followup_register_taken")
	check(Story.resolve_dispatch(&"ch3_dispatch_reconcile") == &"ch3_t_c08_population", "with all three papers the three checks start")
	check(Story.resolve_dispatch(&"ch3_dispatch_control_box") == &"ch3_t_c01_box", "the lift box first explains the interlock")
	GameState.set_flag(&"ch3_interlock_seen")
	check(Story.resolve_dispatch(&"ch3_dispatch_control_box") == &"ch3_t_c02_call_early", "calling before draining only explains what is missing")
	for done in [&"ch3_pump_low", &"ch3_wet_branch_isolated", &"ch3_lift_powered"]:
		GameState.set_flag(done)
	check(Story.resolve_dispatch(&"ch3_dispatch_control_box") == &"ch3_t_c02_call", "all three water and power steps let the lift come down")
	check(Story.resolve_dispatch(&"ch3_dispatch_call") == &"ch3_t_c23_quiet_day", "Egret does not call before supper")
	check(Story.validate().is_empty(), "the merged story passes validation")
	GameState.start_new_run(GameState.difficulties[1])


## 關卡接點：守門人停機的頻道、要扶他坐好才開的電梯、傍晚換到廚房的老 K、診所門要核對完成。
func _test_level_hooks() -> void:
	var gate: LevelData = _datas.get("gate_hall")
	check(gate != null and gate.channel_done_flags.get(&"ch3_janus_down", &"") == &"ch3_janus_disabled", "the gatekeeper fight writes the disabled flag through a level channel")
	var lift := Checks.portal_by_id(gate, &"gate_lift") if gate != null else null
	check(lift != null and lift.requires_flag == &"ch3_janus_aftercare_done", "the edge lift opens only after the gatekeeper is helped back to his chair")
	var clinic: LevelData = _datas.get("clinic")
	var door := Checks.portal_by_id(clinic, &"clinic_gate") if clinic != null else null
	check(door != null and door.requires_flag == &"ch3_report_reconciled", "the gate hall needs the reconciled report")
	var shop: LevelData = _datas.get("pawnshop")
	var counter: NpcData = null
	var kitchen: NpcData = null
	var legend: Dictionary = shop.legend if shop != null else {}
	for key: String in legend:
		var npc := legend[key] as NpcData
		if npc != null and npc.id == &"ch3_old_k":
			counter = npc
		elif npc != null and npc.id == &"ch3_old_k_kitchen":
			kitchen = npc
	check(counter != null and kitchen != null and counter.spawn_unless_flag == &"ch3_trade_overheard" and kitchen.spawn_requires_flag == &"ch3_trade_overheard",
			"Old K moves from the counter to the kitchen once Rin has heard the trade")


## 當舖的章末：接受下一個週日的邀約寫下旗標就結束本章（第四章尚未收錄，沒有下一關）。
func _test_chapter_end() -> void:
	var shop: LevelData = _datas.get("pawnshop")
	check(shop != null and shop.complete_on_flag == &"ch3_shore_closed" and shop.next_level.is_empty(), "the pawnshop ends chapter 3 on its flag without loading a chapter 4 level")
	if shop == null:
		return
	GameState.start_new_run(GameState.difficulties[1])
	var level := await start_level(shop)
	var done := [false]
	level.completed.connect(func() -> void: done[0] = true)
	GameState.set_flag(&"ch3_shore_closed")
	for i in 600:
		if done[0]:
			break
		await frames(2)
	check(done[0], "setting the chapter flag plays the end card and completes the chapter")
	await end_level(level)
	GameState.start_new_run(GameState.difficulties[1])
