extends Node
## 第一章正式劇本流程探針（ST-9）：用真的關卡、真的人物／物件互動與真的選擇推進故事，沿途截圖並檢查旗標、帳務與物品。
## 用法：godot --path . res://tools/ch1_flow_probe.tscn -- --out=<絕對路徑資料夾> [--route=stay|leave]
## 戰鬥、機關與拾取由各自的測試驗收；這裡以真實事件入口（機關頻道、拾取取得）銜接，只驗故事流程與畫面，
## 不代表真人整章通關。

const LEVEL := "res://data/levels/ch1_%s.tres"
## 區域檔名的格式（第二章的探針沿用這份工具時改成 ch2）。
var level_pattern := LEVEL
const STEP_LIMIT := 2400

var _out_dir := ""
var _route := "stay"
var _level: Level
var _shots: Dictionary = {}
var _failures := 0
## 本次播出的場景（依開始的先後），結束時對照劇本主線事件的順序（SCRIPT_CH01 第 2.2 節）。
var _played: Array[String] = []
## 主線事件的代表場景：同一格裡任一個先播出就算到達這個事件。
const SCRIPT_ORDER: Array = [
	["ch1_b_dinner"], ["ch1_t_egret_1"], ["ch1_t_booth_recording"], ["ch1_c09_wake"], ["ch1_t_handoff_confirm"],
	["ch1_t_ali_meet_booth", "ch1_t_ali_meet_clinic", "ch1_t_ali_meet_no_death", "ch1_t_ali_meet_unknown"],
	["ch1_t_supper_choice_ordered", "ch1_t_supper_choice_none"], ["ch1_c14_home"],
]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--route="):
			_route = arg.trim_prefix("--route=")
		elif arg == "--victory-only":
			_route = "victory"
	if _out_dir.is_empty():
		push_error("[Ch1FlowProbe] 需要 --out=<資料夾>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	var path := _out_dir.path_join(name + ".png")
	print("saved %s (%s)" % [path, error_string(image.save_png(path))])


func _enter(area: String, near := Vector2.INF) -> void:
	if is_instance_valid(_level):
		Story.reset_active_presentation(&"route")
		_level.queue_free()
		await _settle(3)
	_level = Level.new()
	_level.configure(load(level_pattern % area) as LevelData)
	add_child(_level)
	await _settle(30)
	# 進場過場（例如開場）照常播放；探針讀完即略過，等同玩家看完。
	for i in STEP_LIMIT:
		if not Story.is_cinematic_active():
			break
		Story.skip_cinematic()
		await _settle(4)
	if near != Vector2.INF:
		_level.player.global_position = near
		await _settle(20)


func _object(id: StringName) -> NpcActor:
	for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		var npc := node as NpcActor
		if npc != null and npc.data != null and npc.data.id == id:
			return npc
	return null


## 走到人物旁邊按互動；依序選擇選項 id，第一次看到 shots 指定的場景或選擇時截圖。
func _talk(id: StringName, choices: Array = []) -> bool:
	var npc := _object(id)
	if npc == null or not npc.is_present():
		_check(false, "%s is present in %s" % [id, _level.data.id])
		return false
	_level.player.global_position = npc.global_position + Vector2(-28, 0)
	await _settle(12)
	var done := [false, false]
	var talk := func() -> void:
		done[1] = await npc._talk()
		done[0] = true
	talk.call()
	await _drive(choices, func() -> bool: return done[0])
	_check(done[0] and done[1], "talk with %s completes with choices %s" % [id, choices])
	return done[1]


## 推進進行中的演出：依序選擇、對話讀完略過、第一次看到 _shots 指定的場景或選擇時截圖，直到 finished 回傳 true。
func _drive(choices: Array, finished: Callable) -> void:
	var pending := choices.duplicate()
	var shown := {}
	for i in STEP_LIMIT:
		if finished.call():
			break
		var current := String(Story._current_cinematic)
		var player: CutscenePlayer = Story._player
		if Story._layer.is_radio_frozen():
			# 重要通訊（NE-246）凍結世界等確認：像玩家一樣按確認讀完。
			await _settle(8)
			Story._layer.advance_radio()
		elif player != null and player.choice_active():
			var key := current + ":choice"
			if _shots.has(key) and not shown.has(key):
				shown[key] = true
				await _settle(20)
				_capture(_shots[key])
			var wanted: String = pending.pop_front() if not pending.is_empty() else str(player._choice_step.get("default", ""))
			var index := player._choice_options.find_custom(func(o: Dictionary) -> bool: return str(o.get("id", "")) == wanted)
			_check(index >= 0, "%s offers option %s" % [current, wanted])
			player.choose(maxi(index, 0))
		elif current != "" and _shots.has(current) and not shown.has(current):
			shown[current] = true
			await _settle(70)
			_capture(_shots[current])
		elif current != "" and Story.scene_mode(StringName(current)) != Story.MODE_ANIMATED:
			await _settle(8)
			Story.skip_cinematic()
		elif player != null and player.is_running() and player._dialogue.visible:
			player._dialogue.complete()
			player._advance_requested = true
		await get_tree().physics_frame
	_check(pending.is_empty(), "every planned choice was offered %s" % [choices])


func _run() -> void:
	if _route == "victory":
		GameState.start_new_run(GameState.difficulties[1])
		var screen := VictoryScreen.new()
		screen.chapter = &"ch1_kasa"
		add_child(screen)
		await _settle(150)
		_capture("ST-9-victory")
		get_tree().quit()
		return
	_shots = {
		"ch1_t_label_watch": "ST-9-label-watch",
		"ch1_t_egret_1": "ST-9-roof-brief",
		"ch1_t_ali_name": "ST-9-lounge-name",
		"ch1_t_supper_stay_meal": "ST-9-stall-seated",
		"ch1_t_handoff_confirm:choice": "ST-9-handoff-confirm",
		"ch1_t_handoff_summary": "ST-9-handoff-summary",
		"ch1_t_ali_1:choice": "ST-9-ali-order-menu",
		"ch1_hub_ali_lounge:choice": "ST-9-ali-topics",
		"ch1_t_supper_choice_ordered:choice": "ST-9-supper-choice",
		"ch1_t_supper_leave_options:choice": "ST-9-supper-pay-or-tab",
		"ch1_t_supper_stay_address": "ST-9-supper-address",
		"ch1_c09_wake": "ST-9-first-clinic",
		"ch1_t_clinic_tray_prompt:choice": "ST-9-clinic-tray",
		"ch1_t_lamp_voice_prompt:choice": "ST-9-voice-prompt",
		"ch1_c14_home": "ST-9-home",
	}
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	Story.auto_skip = false
	Story.scene_started.connect(func(id: StringName, _mode: StringName) -> void: _played.append(String(id)))
	# 當舖：免費晚飯（真 0 元收據）→ 讀懷錶標籤 → 屋頂聽鷺的差事。
	await _enter("pawnshop", Vector2(86 * 16, 19 * 16))
	Story.play(&"ch1_b_dinner")
	for i in STEP_LIMIT:
		if GameState.has_flag(&"ch1_dinner_done"):
			break
		await get_tree().physics_frame
	_check(GameState.has_flag(&"ch1_dinner_done") and Progression.story_receipt_status(&"ch1.daily_dinner").get("status") == "recorded", "the free dinner finishes with its receipt")
	await _talk(&"ch1_label_watch")
	_check(GameState.has_flag(&"ch1_label_watch_seen") and GameState.has_flag(&"ch1_labels_started"), "reading the watch label records it and starts the label side quest")
	for label in [&"ch1_label_guitar", &"ch1_label_raincoat", &"ch1_label_fare"]:
		await _talk(label)
	_check(GameState.has_flag(&"sq8_first_labels_done"), "all four labels complete the label side quest")
	await _talk(&"ch1_label_watch")
	_check(GameState.has_flag(&"ch1_label_watch_seen"), "a read label offers its short revisit instead")
	await _enter("rooftop")
	await _talk(&"ch1_egret")
	_check(GameState.has_flag(&"ch1_heard_brief"), "the full briefing opens the front door")
	await _talk(&"ch1_egret", ["ask"])
	_check(GameState.has_flag(&"asked_egret_sunday"), "asking Egret about Sundays is an optional explicit choice")
	# 電話亭：第一次備份播出錄音，聽完才能在亭邊問燈那個聲音（不需要先死）。
	await _enter("booth_alley")
	_check(not _object(&"ch1_lamp_voice").is_present(), "the voice question is not offered before hearing the recording")
	GameState.set_checkpoint(_level.player.global_position, _level.player.checkpoint_snapshot())
	await _drive([], func() -> bool: return GameState.has_flag(&"ch1_recording_heard"))
	await _settle(60)
	_check(GameState.has_flag(&"ch1_recording_heard") and _object(&"ch1_lamp_voice").is_present(), "the first backup plays the recording and opens the voice question")
	await _talk(&"ch1_lamp_voice", ["ask", "ask"])
	_check(GameState.has_flag(&"sq5_lamp_voice_noticed") and GameState.deaths == 0, "the voice side quest completes without dying")
	# 碼頭：路障、看門狗、水閘以真實頻道事件銜接；保險箱的資料盤用真的取得入口。
	for pair in [["street", &"arena_street_blockade", false], ["warehouse", &"watchdog_gate", true], ["warehouse", &"flood_c", true]]:
		await _enter(pair[0])
		EventBus.mechanism_toggled.emit(pair[1], pair[2])
	# 倉庫裡第一次真正死亡：初次建檔（不經過死亡畫面），之後托盤上的灰布可以收起或留下。
	var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"probe")
	lethal.ignore_invulnerability = true
	_level.player.health.take_damage(lethal)
	await _drive(["look", "take"], func() -> bool: return GameState.has_flag(&"has_grey_cloth"))
	_check(GameState.has_flag(&"ch1_first_death_done") and StoryItems.holds(&"ch1_grey_cloth"), "the first real death plays the clinic registration and the cloth can be taken")
	await _settle(120)
	# 第二次死亡：已登記電話亭，走一般死亡畫面（錄音、燈、狀態列、記憶卡），並記下在亭子復原過。
	await _enter("warehouse")
	_level.player.health.take_damage(lethal)
	var screen: DeathScreen = null
	for i in STEP_LIMIT:
		screen = _find_death_screen()
		if screen != null and screen.sequence_index >= 1:
			break
		await get_tree().physics_frame
	await _settle(30)
	_capture("ST-9-death-sequence")
	_check(screen != null and screen.sequence.get("steps", []).size() == 4 and GameState.has_flag(&"ch1_booth_restoration_done"), "an ordinary death shows the full death sequence and records the booth restoration")
	_check(GameState.has_flag(&"ch1_street_route_open") and GameState.has_flag(&"watchdog_defeated") and GameState.has_flag(&"ch1_flood_gate_open"), "world events write the route, watchdog and flood flags")
	await _enter("vault")
	_check(StoryItems.acquire(&"ch1_data_disk") and GameState.has_flag(&"ledger_disk_obtained") and StoryItems.holds(&"ch1_data_disk"), "taking the disk records history and custody")
	# 館外交接櫃：交盤 → 取回執 → 保留摘要。
	await _enter("handoff")
	await _talk(&"ch1_handoff_cabinet", ["deliver"])
	_check(not StoryItems.holds(&"ch1_data_disk") and StoryItems.was_transferred(&"ch1_data_disk"), "the confirmed handoff transfers the original disk")
	await _talk(&"ch1_handoff_cabinet", ["take"])
	await _talk(&"ch1_handoff_cabinet", ["save"])
	_check(GameState.has_flag(&"ch1_handoff_done") and StoryItems.holds(&"ch1_delivery_receipt") and StoryItems.holds(&"ch1_market_summary"), "receipt and summary are kept and the lounge door opens")
	# 復原館：點餐 → 名字 → 下班前的話。
	await _enter("lounge")
	await _talk(&"ch1_ali_lounge", ["order"])
	_check(GameState.has_flag(&"ch1_met_ali") and Story.outcomes.account_state(&"ch1_lounge") == "open200" and StoryItems.holds(&"ch1_lounge_bill"), "ordering opens the 200 bill and gives the itemised receipt")
	await _talk(&"ch1_ali_lounge", ["evening"])
	await _settle(60)
	_check(GameState.has_flag(&"ch1_lounge_evening_done") and not _object(&"ch1_ali_lounge").is_present(), "after the evening talk Ali leaves the lounge for the stall")
	# 麵攤：留下吃麵（招待）或先付清回家。
	await _enter("stall")
	if _route == "leave":
		Progression.add_credits(250)
		await _talk(&"ch1_ali_stall", ["leave", "pay"])
		_check(Story.outcomes.account_state(&"ch1_lounge") == "paid200" and GameState.has_flag(&"ch1_supper_done") and not GameState.has_flag(&"knows_ali_address"), "paying and leaving settles the bill without the address")
	else:
		await _talk(&"ch1_ali_stall", ["stay", "accept"])
		_check(Story.outcomes.account_state(&"ch1_lounge") == "gifted200" and GameState.has_flag(&"knows_ali_address") and GameState.has_flag(&"sq1_first_supper_done"), "staying is a gift, and Ali tells her address")
	# 回家：天亮的當舖播完章末。
	var level_done := [false]
	if is_instance_valid(_level):
		_level.queue_free()
		await _settle(3)
	_level = Level.new()
	_level.configure(load(LEVEL % "pawnshop_dawn") as LevelData)
	_level.completed.connect(func() -> void: level_done[0] = true)
	add_child(_level)
	await _drive([], func() -> bool: return level_done[0])
	_check(GameState.has_flag(&"ch1_complete") and level_done[0], "coming home plays the chapter ending once and completes the chapter")
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var open_main := catalog.list_for("ch1_kasa", "main", false, GameState.world_flags)
	_check(catalog.issues.is_empty() and open_main.is_empty(), "all published chapter 1 main quests are complete (%d open)" % open_main.size())
	# 結算畫面：章末下一步與「進度已保存、收錄到第一章」的說明。
	_level.queue_free()
	var victory := VictoryScreen.new()
	victory.chapter = &"ch1_kasa"
	add_child(victory)
	await _settle(150)
	_capture("ST-9-victory")
	_check_script_order()
	print("CH1_FLOW_PROBE route=%s failures=%d" % [_route, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## 主線事件依劇本的先後播出，播出紀錄寫進輸出資料夾（scene_order.txt），可以和劇本逐場對照。
func _check_script_order() -> void:
	var file := FileAccess.open(_out_dir.path_join("scene_order.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_played) + "\n")
	var last := -1
	var order := PackedStringArray()
	for event: Array in SCRIPT_ORDER:
		var first := -1
		for id: String in event:
			var at := _played.find(id)
			if at >= 0 and (first < 0 or at < first):
				first = at
		order.append("%s@%d" % [event[0], first])
		_check(first > last, "script event %s plays after the previous one (%s)" % [event[0], ", ".join(order)])
		last = maxi(first, last)


func _find_death_screen() -> DeathScreen:
	for node in _level.find_children("*", "DeathScreen", true, false):
		return node as DeathScreen
	return null
