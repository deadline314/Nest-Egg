class_name Chapter2StorySuite
extends TestSuite
## 第二章「鷺」（ST-19）：區域之間的出入口兩端相通、每個人物入口接得到劇本、任務標記落在真的人物或物件上、
## 主要的劇情關卡依進度挑對段落、第一章接第二章、屋頂章末寫入旗標就結束本章。
## 整章依序推進用 tools/ch2_flow_probe.tscn（兩條阿勇路線）驗；這裡只放快速、穩定的資料與規則檢查。

const AREAS: PackedStringArray = ["pawnshop", "rooftop", "harbor_street", "market_gate", "market", "ali_home", "loading",
		"ledger_front", "ledger_office", "lounge_front"]
const LEVEL := "res://data/levels/ch2_%s.tres"

const Checks := preload("res://tests/helpers/chapter_story_checks.gd")

class ClosingMain extends "res://game/main.gd":
	func _ready() -> void:
		Story.scene_started.connect(_on_scene_started)
		Story.presentation_cancelled.connect(_on_presentation_cancelled)

var _datas: Dictionary = {}


func run() -> void:
	_datas = Checks.load_areas(self, "ch2", &"ch2_heron", AREAS)
	Checks.check_portals(self, "chapter 2", _datas)
	Checks.check_entries(self, "chapter 2", _datas, 20)
	Checks.check_quest_markers(self, "chapter 2", "ch2", "res://data/story/ch2_heron.json", _datas, 18)
	_test_story_gates()
	await _test_reconcile_documents()
	_test_audit_terminal_contact()
	_test_rooftop_props()
	await _test_rooftop_combo_station()
	await _test_loading_guard()
	_test_ali_kitchen_revisit()
	_test_ali_soup_healing()
	_test_ledger_install()
	_test_street_line()
	_test_guest_book_stage()
	await _test_guest_book_closing()
	await _test_market_tea_stall()
	preload("res://tests/helpers/radio_tune_checks.gd").run(self)
	await preload("res://tests/helpers/radio_tune_lifecycle_checks.gd").run(self)
	Checks.check_staging(self, "chapter 2", "ch2", 26)
	await _test_chapter_link()


## 劇情依進度挑段落：鷺（簡報→話題→章末）、對帳桌（缺什麼說什麼→對帳→回訪）、早上的反應依昨晚的宵夜。
func _test_story_gates() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	check(Story.resolve_dispatch(&"ch2_dispatch_egret") == &"ch2_t_s03_tea", "Egret starts with the rooftop tea")
	GameState.set_flag(&"ch2_brief_done")
	check(Story.resolve_dispatch(&"ch2_dispatch_egret") == &"ch2_t_egret_hub", "after the brief Egret offers topics")
	GameState.set_flag(&"ch2_audit_submitted")
	GameState.set_flag(&"ch2_egret_returned")
	check(Story.resolve_dispatch(&"ch2_dispatch_egret") == &"ch2_t_s22_tea", "after the audit the rooftop tea ends the chapter")
	check(Story.resolve_dispatch(&"ch2_dispatch_reconcile") == &"ch2_t_s10_missing_receipt", "the desk first asks for the paid receipt")
	GameState.set_flag(&"ch2_evidence_receipt")
	check(Story.resolve_dispatch(&"ch2_dispatch_reconcile") == &"ch2_t_s10_missing_collection", "then for the collection book")
	GameState.set_flag(&"ch2_evidence_collection")
	GameState.set_flag(&"ch2_evidence_contract")
	check(Story.resolve_dispatch(&"ch2_dispatch_reconcile") == &"ch2_t_s10_principal", "with all three papers the reconciliation starts")
	GameState.set_flag(&"ch2_market_reconciled")
	check(Story.resolve_dispatch(&"ch2_dispatch_reconcile") == &"ch2_t_s10_revisit", "a finished reconciliation only has a short revisit")
	check(Story.resolve_dispatch(&"ch2_dispatch_s01_reaction") == &"ch2_t_s01_reaction_left", "without last night's address Old K mentions the receipt")
	GameState.set_flag(&"knows_ali_address")
	check(Story.resolve_dispatch(&"ch2_dispatch_s01_reaction") == &"ch2_t_s01_reaction", "after staying for noodles Old K mentions the noodles")
	check(Story.resolve_dispatch(&"ch2_dispatch_cabinet") == &"ch2_t_s13_locked", "the ledger cabinet stays locked before Yong is subdued")
	var cabinet := load("res://data/npcs/ch2_ledger_cabinet.tres") as NpcData
	check(cabinet != null and cabinet.prompt_text() == "{interact} 查看帳櫃", "the cabinet prompt offers inspection even while the lock is active")
	check(Story.validate().is_empty(), "the merged story passes validation")
	GameState.start_new_run(GameState.difficulties[1])


func _test_reconcile_documents() -> void:
	const SCENE := &"ch2_t_s10_principal"
	const IDS := [&"ch2_evidence_contract", &"ch2_evidence_receipt", &"ch2_evidence_collection"]
	const MARKET := "res://data/levels/ch2_market.tres"
	const LOADING := "res://data/levels/ch2_loading.tres"
	var steps: Array = Story._scenes[SCENE].get("steps", [])
	var step: Dictionary = steps.back()
	check(step.get("reference_items", []) == Array(IDS).map(func(id: StringName) -> String: return str(id)),
		"the actual reconciliation choice references the three acquired records in author order")
	var origin := QuestMapIndex.for_chapter(&"ch2_heron")
	var locations := [
		{"level": MARKET, "cell": [53, 35]},
		{"level": MARKET, "cell": [30, 35]},
		{"level": LOADING, "cell": [112, 35]},
	]
	for i in IDS.size():
		var id: StringName = IDS[i]
		check(StoryItems.acquire(id, false), "test fixture owns the real reconciliation record %s" % id)
		var item := StoryItems.find(id)
		check(item != null and origin.source_location(item.source_actor) == locations[i],
			"%s points to its original map actor" % id)
	var stored := StoryItems.snapshot()
	var cutscene := CutscenePlayer.new()
	runner.get_tree().root.add_child(cutscene)
	cutscene.play(SCENE, {"mode": "animated", "overlay": true, "steps": [step]})
	for _frame in 12:
		if cutscene.choice_active():
			break
		await frames(1)
	check(cutscene.choice_active(), "the actual choice shows the reconciliation actions")
	if cutscene.choice_active():
		var receipt := StoryItems.find(IDS[1])
		var anchor: Button
		for child in cutscene._choice.get_children():
			if child is Button and child.text == receipt.title_text():
				anchor = child
				break
		check(anchor != null and anchor.tooltip_text == receipt.description_text(), "the receipt uses the registered title and short guidance")
		if anchor != null:
			anchor.pressed.emit()
			check(is_instance_valid(cutscene._choice_reader) and cutscene._choice_reader._text.text == receipt.body_text(),
				"reviewing the receipt opens the full existing document reader")
			check(not cutscene.choose(0), "decision controls are inactive while reading")
			var back := InputEventAction.new()
			back.action = &"ui_cancel"
			back.pressed = true
			cutscene._input(back)
			check(cutscene.choice_active() and anchor.has_focus() and cutscene._chosen == -1,
				"Back from the document restores focus to the receipt without making a choice")
	check(StoryItems.snapshot() == stored and not GameState.has_flag(&"ch2_market_reconciled"),
		"reviewing evidence never consumes a document or commits the reconciliation")
	cutscene.cancel()
	await frames(1)
	GameState.start_new_run(GameState.difficulties[1])


func _test_audit_terminal_contact() -> void:
	var steps: Array = Story._scenes["ch2_t_s15_upload"].get("steps", [])
	var first: Dictionary = {} if steps.is_empty() else steps.front()
	var action := "audit_terminal_submit"
	var spec := WorldPropAction.definition(action)
	var button: Array = spec.get("button", [])
	check(first.get("id") == action and WorldPropAction.is_presentation_only(action),
		"the original audit upload opens with an optional physical confirmation")
	check(WorldPropAction.problem(action, "ch2_t_s15_upload", true).is_empty()
		and not WorldPropAction.problem(action, "ch2_t_s15_revisit", true).is_empty(), "the terminal press belongs only to the first audit")
	var terminal := load("res://data/environment/scene_props/revival_lounge/revival_lounge__commission_terminal.tres") as PropData
	check(terminal != null and button.size() == 2 and Rect2(Vector2.ZERO, terminal.size).has_point(Vector2(button[0], button[1])),
		"the contact lies on the real terminal image")


func _test_loading_guard() -> void:
	const ACTION := "loading_guard_inspect"
	const SCENE := "ch2_t_s09_guard"
	var steps: Array = Story._scenes[SCENE].get("steps", [])
	check(not steps.is_empty() and steps[0] == {"do": "world_action", "id": ACTION}
			and WorldPropAction.is_presentation_only(ACTION), "the first inspection can lower Rin without owning story results")
	check(WorldPropAction.problem(ACTION, SCENE, true).is_empty()
			and not WorldPropAction.problem(ACTION, "ch2_t_s09_guard_revisit", true).is_empty(),
			"the first guard reading owns the optional inspection, and the revisit stays short")
	var level := await start_level(_datas["loading"] as LevelData)
	var guard: NpcActor
	for node in level._entities.get_children():
		if node is NpcActor and node.data.id == &"ch2_guard":
			guard = node
			break
	check(guard != null and guard.cell == Vector2i(84, 35) and guard.data.kind == NpcData.Kind.OBJECT,
			"the resting guard keeps the original inspect-only world source")
	if guard == null:
		await end_level(level)
		return
	check(guard._actor != null and guard._actor.rig != null and guard._actor.pose == &"rest",
			"the guard displays an authored breathing pose instead of the object marker")
	if guard._actor != null and guard._actor.rig != null:
		var rig := guard._actor.rig
		var front := rig.bone(&"foot_front")
		var back := rig.bone(&"foot_back")
		var chest := rig.bone(&"chest")
		for step in 36:
			guard._actor._process(1.0 / 60.0)
		var feet := [front.global_position, back.global_position]
		var initial_breath := chest.rotation
		level.player.global_position = guard.global_position + Vector2(-28, 0)
		guard._face_player()
		for step in 80:
			guard._actor._process(1.0 / 60.0)
		check(guard._actor.facing == guard.data.facing and guard.awareness == null,
				"a resting guard does not greet, turn or react to the player")
		check(absf(chest.rotation - initial_breath) > 0.0001
				and front.global_position.distance_to(feet[0]) < 0.01 and back.global_position.distance_to(feet[1]) < 0.01,
				"the chest breathes while both boots stay planted")
	var supported := false
	for prop in level.find_children("*", "PropNode", true, false):
		if prop.data.id == &"dock_warehouse__wrapped_pallets" and absf(prop.position.x - guard.position.x) < 52.0:
			supported = is_equal_approx(prop.global_position.y + prop.data.size.y, guard.global_position.y) \
					and absf(guard.global_position.x - prop.global_position.x - prop.data.size.x - 5.5) < 0.05
	check(supported, "the authored backrest touches the guard's floor at its seat")
	check(Story.resolve_dispatch(guard.data.talks[0].scene) == &"ch2_t_s09_guard" and not GameState.has_flag(&"ch2_guard_seen"),
			"the visible guard keeps the original unread inspection and grants no progress")
	await end_level(level)


func _test_rooftop_props() -> void:
	const CUP := "rin_roof_cup"
	var card_layer := func(layer: Dictionary) -> bool: return layer.get("id") == "public_aisle_pass"
	var roof_layers: Array = StageLibrary.definition(&"ch2_rooftop_tea").get("layers", [])
	var roof := roof_layers.filter(card_layer)
	var market: Array = StageLibrary.definition(&"ch2_market_pass").get("layers", []).filter(card_layer)
	check(roof.size() == 1 and market.size() == 1 and roof[0].get("path") == market[0].get("path")
			and not roof[0].get("visible", true), "only the briefing reveals the same card that Rin shows at the market")
	var brief: Dictionary = Story._scenes["ch2_t_s03_brief"]
	var holders: Array[String] = []
	for step: Dictionary in brief["steps"]:
		if step.get("do") == "prop_hold" and step.get("id") == "public_aisle_pass":
			holders.append(step["actor"])
	check(holders == ["egret", "rin"], "the actual visual card passes from Egret to Rin once")
	var terminal: Dictionary = Story._scenes["ch2_t_s03_rain"]
	check(not brief.has("results") and terminal.get("results", []).has({"kind": "item_acquire", "id": "ch2_check_card"}),
			"the physical card cannot grant inventory until the original briefing completes")
	var cup_layers := roof_layers.filter(func(layer: Dictionary) -> bool: return layer.get("id") == CUP)
	var start: Array = cup_layers[0].get("pos", []) if cup_layers.size() == 1 else []
	var shifted: Array = brief["steps"][0].get("props", {}).get(CUP, {}).get("pos", [])
	check(start.size() == 2 and shifted.size() == 2 and shifted[0] > start[0] and shifted[1] == start[1]
			and terminal["steps"][0].get("props", {}).get(CUP, {}).get("pos", []) == shifted,
			"the next two briefing shots retain the shifted cup at tabletop height")
	var evening: Dictionary = Story._scenes["ch2_t_s22_tea"]
	check(not evening["steps"][0].get("props", {}).has(CUP), "the evening cup starts at its own original placement")


func _test_rooftop_combo_station() -> void:
	var level := await start_level(_datas["rooftop"] as LevelData)
	var station := level._training_stations.front() as TrainingStation if level._training_stations.size() == 1 else null
	check(station != null and station.data.id == &"ch2_roof_combo_target", "the actual rooftop spawns one practice target")
	if station == null:
		await end_level(level)
		return
	var info := DamageInfo.create(1, Combat.Team.PLAYER, &"melee")
	info.attacker = weakref(level.player)
	info.stagger = 3
	level.player.melee.index = 2
	station._hurtbox.receive(info)
	check(not station.is_active() and not station.is_done(), "heavy practice waits for the rooftop briefing")
	GameState.set_flag(&"ch2_brief_done")
	station._refresh()
	check(station.is_active() and station.data.done_scene == &"", "roof practice is optional and never starts a cutscene")
	info.is_projectile = true
	station._hurtbox.receive(info)
	check(not station.is_done(), "a projectile cannot finish combo practice")
	info.is_projectile = false
	info.stagger = 2
	station._hurtbox.receive(info)
	check(not station.is_done(), "the light follow-up cannot finish combo practice")
	info.stagger = 3
	level.player.melee.index = 0
	station._hurtbox.receive(info)
	check(not station.is_done(), "a heavy opener cannot finish combo practice")
	level.player.melee.index = 2
	station._hurtbox.receive(info)
	check(station.is_done() and GameState.has_flag(&"ch2_roof_combo_practiced") and not station._prompt.enabled,
		"a heavy follow-through completes once and hides the prompt")
	await end_level(level)
	var reopened := await spawn_level(_datas["rooftop"] as LevelData)
	check(reopened._training_stations.size() == 1 and reopened._training_stations.front().is_done(),
		"returning to the roof restores the completed target")
	await end_level(reopened)
	GameState.start_new_run(GameState.difficulties[1])


func _test_ali_soup_healing() -> void:
	var amount := (_datas["ali_home"] as LevelData).story_health_reward(&"ch2.sq1_soup")
	check(amount == 2 and (_datas["market"] as LevelData).story_health_reward(&"ch2.sq1_soup") == 0,
			"only the real kitchen adds a two-point reward to the soup receipt")
	var health := HealthComponent.new()
	health.setup(6, 0.0)
	health.current = 5
	check(health.preview_heal(amount) == 1 and health.current == 5, "planning the capped gain never changes live health")
	check(health.heal(amount) == 1 and health.current == 6, "the live health path uses the same capped gain")
	health.is_dead = true
	check(health.preview_heal(amount) == 0, "a story reward cannot resurrect the player")
	health.free()


func _test_guest_book_closing() -> void:
	const CLOSE := &"ch2_t_s21_close"
	const RECEIPT := &"ch2.guest_book"
	var level := await start_level(_datas["lounge_front"])
	var main := ClosingMain.new()
	main._active_run = true
	main._screen = level
	main._level_path = level.data.resource_path
	main._run_store = RunSaveStore.new("user://test-ch2-guest-closing-%s.json" % OS.get_process_id())
	runner.get_tree().root.add_child(main)
	var entry := load("res://data/npcs/ch2_guest_entry.tres") as NpcData
	check(entry != null and entry.talks[0].resume_scene == CLOSE and Story.cancels_on_skip(CLOSE),
			"the original guest book can resume a skippable closing without changing its story entry")
	check(not Story.scene_available(CLOSE), "the closing cannot start before all three guests finish")
	for id: StringName in [&"ch2_audit_submitted", &"guest_ticket_answered", &"guest_band_answered", &"guest_letter_answered"]:
		GameState.set_flag(id)
	check(Story.scene_available(CLOSE) and Story.is_npc_presentation(entry, 0, CLOSE),
			"all three answers make the original closing reachable from the real guest book")
	var auto := Story.auto_skip
	Story.auto_skip = false
	var credits := Progression.credits
	check(Story.play(CLOSE, false), "the unfinished closing begins")
	await frames(8)
	check(main._run_store.read().get("cinematic") == String(CLOSE), "the run saves the active closing until the player decides")
	Story.skip_cinematic()
	await frames(8)
	check(not Story.is_cinematic_active() and not Story.was_seen(CLOSE) and not GameState.has_flag(&"guest_book_completed")
			and Progression.credits == credits and Progression.story_receipt_status(RECEIPT)["status"] == "missing",
			"leaving the closing keeps the ending, payment and watching record pending")
	var after_leave := main._run_store.read()
	check(after_leave.get("cinematic") == "" and after_leave.get("progression", {}).get("credits") == credits,
			"explicitly leaving clears the saved playback without changing prior guest payments")
	Story.auto_skip = true
	check(await Story.play_and_wait(CLOSE, false) and GameState.has_flag(&"guest_book_completed")
			and Progression.credits == credits + 40 and Progression.story_receipt_status(RECEIPT)["status"] == "recorded",
			"the original closing pays forty once and makes the resume unavailable")
	check(not Story.scene_available(CLOSE), "the completed book returns to the existing revisit")
	DirAccess.remove_absolute(main._run_store.path)
	DirAccess.remove_absolute(main._run_store.path + ".bak")
	main._screen = null
	main.queue_free()
	await end_level(level)
	Story.auto_skip = auto
	GameState.start_new_run(GameState.difficulties[1])


func _test_ali_kitchen_revisit() -> void:
	var ali := load("res://data/npcs/ch2_ali_home.tres") as NpcData
	var catalog := QuestCatalog.new()
	catalog.load_story_sources(["res://data/story/ch2_heron.json"])
	var quest: Dictionary = catalog.quests.filter(func(row: Dictionary) -> bool: return row["id"] == "sq1_ali_soup")[0]
	var flags := {"ch2_market_contact_done": true, "ch2_ali_home_visit": false, "sq1_soup_practice_done": false}
	var has_flag := func(flag: StringName) -> bool: return flags.get(String(flag), false)
	check(ali.pick_talk(0, Story.was_seen, 0, has_flag) == 0, "Ali uses her original first visit")
	flags["ch2_ali_home_visit"] = true
	check(ali.pick_talk(1, Story.was_seen, 0, has_flag) == 1 and QuestCatalog.status(quest, flags) == "active",
			"recording only the address preserves the washing interaction and active quest")
	flags["sq1_soup_practice_done"] = true
	check(ali.pick_talk(2, Story.was_seen, 0, has_flag) == 0 and QuestCatalog.status(quest, flags) == "completed",
			"tasting ends the quest and leaves the original revisit")


## 第二章的交易收據存進存檔後讀得回來（存檔驗證認得之後章節的交易，不只第一章的七筆）；不認識的收據照樣拒絕。
func _test_ledger_install() -> void:
	var definitions: Dictionary = {}
	for resource: StoryTransactionData in ResourceCatalog.load_dir("res://data/story_transactions", StoryTransactionData, "Chapter2StorySuite"):
		definitions[String(resource.id)] = resource
	var ledger := StoryTransactionLedger.new()
	var wallet := 500
	for id in ["ch1.commission.settled", "ch2.market_advance", "ch2.yong_subdued"]:
		var result := ledger.commit(definitions[id], wallet, Progression.MAX_CREDITS) if definitions.has(id) else {"applied": false}
		check(bool(result["applied"]), "chapter 2 ledger commits %s" % id)
		wallet = int(result.get("credits_after", wallet))
	var raw := Progression.snapshot()
	raw["credits"] = wallet
	raw["story_transactions"] = ledger.snapshot()
	var prepared := Progression.prepare_install(raw)
	check(prepared.has("data"), "a save holding chapter 2 receipts installs: %s" % prepared.get("error", ""))
	raw["story_transactions"]["receipts"]["ch2.unknown"] = raw["story_transactions"]["receipts"]["ch2.market_advance"]
	check(not Progression.prepare_install(raw).has("data"), "an unknown chapter receipt is still refused")


## 雨棚背面的雨棚（單向平台）比地面還寬：街道地面線仍是真正的地面，前景欄杆才不會蓋住下層貨道的腳下；雨棚本身仍是那幾欄的最上層表面。
func _test_street_line() -> void:
	var data: LevelData = _datas.get("loading")
	if data == null:
		return
	var layout := LevelBuilder.parse(data)
	# NE-299 加高 16 格：地面第 36 列、雨棚第 29 列。
	check(is_equal_approx(layout.ground_y, 36.0 * layout.tile_size), "the street line ignores the wide canopy (%.0f)" % layout.ground_y)
	check(is_equal_approx(layout.surface_heights[40], 29.0 * layout.tile_size), "the canopy is still the top surface of its columns")


func _test_market_tea_stall() -> void:
	var level := await start_level(_datas["market"] as LevelData)
	var vendors := level.get_tree().get_nodes_in_group(NpcActor.GROUP).filter(
		func(node: NpcActor) -> bool: return node.data.id == &"ch2_banyan")
	var tea_urns := level.get_tree().get_nodes_in_group(PropNode.GROUP).filter(
		func(node: PropNode) -> bool: return node.data.id == &"neon_market__tea_urn")
	var banyan := (vendors[0] as NpcActor) if not vendors.is_empty() else null
	var urn := (tea_urns[0] as PropNode) if not tea_urns.is_empty() else null
	if banyan != null and banyan._actor != null and urn != null:
		var lid := urn.steam_world_position() - banyan.global_position
		check(lid.x > 6.0 and lid.x < 16.0 and lid.y < -30.0 and lid.y > -42.0,
			"the lid is in reach in front of Banyan")
		check(is_equal_approx(urn.global_position.y + urn.data.size.y, banyan.global_position.y), "the tea stand still rests on the market floor")
		level.player.global_position = banyan.global_position - Vector2(12, 0)
		await physics_frames(8)
		check(banyan._actor.facing == -1 and banyan._actor._input.npc_loop == &"", "Banyan pauses work and faces the approaching player")
		level.player.global_position = banyan.global_position - Vector2(96, 0)
		await physics_frames(8)
		check(banyan._actor.facing == 1 and banyan._actor._input.npc_loop == &"stir", "Banyan returns to the tea stand when the player leaves")
	else:
		check(false, "the market contains the original tea stand and Banyan rig")
	await end_level(level)


## 夜班的開本、三客（含錯誤重試）與收本都留在同一個房間；回到凜才結束舞台。
func _test_guest_book_stage() -> void:
	var count := 0
	for id: String in Story.scene_ids():
		if not id.begins_with("ch2_t_s") or id in ["ch2_t_s17_offer", "ch2_t_s17_revisit"]:
			continue
		var section := int(id.substr(7, 2))
		if section < 17 or section > 21:
			continue
		count += 1
		var scene: Dictionary = Story._scenes[id]
		check(scene.get("mode") == "animated" and not scene.get("overlay", false), "%s stays in the guest-book room" % id)
		var steps: Array = scene.get("steps", [])
		if steps.size() < 2:
			check(false, "%s has a stage and Ali" % id)
			continue
		check(steps[0].get("id") == "ch2_guest_book_room", "%s opens the authored room" % id)
		var actor: Dictionary = steps[1]
		var at: Array = actor.get("pos", [])
		check(actor.get("id") == "ali" and at.size() == 2, "%s has Ali with a position" % id)
		if at.size() != 2:
			continue
		var feet := Vector2(float(at[0]), float(at[1]))
		var seated := section in [18, 19, 20]
		check(actor.get("pose") == ("sit" if seated else "idle"), "%s uses the intended supported posture" % id)
		check(is_equal_approx(feet.y, 265.5), "%s keeps feet on the room floor" % id)
		if seated:
			check(is_equal_approx(float(actor.get("seat_sag", -1)), 0.50), "%s calibrates the seat without moving the floor" % id)
			if (steps[-1] as Dictionary).get("do") == "choice":
				check((steps[-1] as Dictionary).get("default") == "back", "%s can return to Rin or skip without choosing an answer" % id)
		var issues := StageFitAudit.contact_issues(id, "ch2_guest_book_room", StageLibrary.definition(&"ch2_guest_book_room"), "ali", str(actor.get("pose")), feet, float(actor.get("scale", 1.0)))
		check(issues.is_empty(), "%s has supported geometry: %s" % [id, issues])
	check(count >= 18, "all guest-book segments, including retries, use the room (%d)" % count)
	var offer: Dictionary = Story._scenes["ch2_t_s17_offer"]
	check(bool(offer.get("overlay", false)), "the offer stays with Rin outside the room")
	var open: Dictionary = Story._scenes["ch2_t_s17_open"]
	check(not open.has("results"), "opening the reservation menu grants no completion or money")
	var choice: Dictionary = open["steps"][-1]
	check(choice.get("default") == "back", "skipping the menu returns without choosing an unplayed guest")
	var negative := StageFitAudit.contact_issues("guest_book_negative", "ch2_guest_book_room", StageLibrary.definition(&"ch2_guest_book_room"), "ali", "idle", Vector2(320, 265.5), 3.9)
	check(not negative.is_empty(), "standing inside the tea table is rejected")
	for bad: Variant in [-0.1, 1.0, NAN, INF, "0.43", null]:
		var broken: Dictionary = Story._scenes["ch2_t_s18_ticket"].duplicate(true)
		broken["steps"][1]["seat_sag"] = bad
		check("\n".join(CutsceneChecker.validate("seat_negative", broken, Story._speakers)).contains("seat_sag"), "invalid seat_sag is rejected: %s" % str(bad))


## 第一章的天亮章末接第二章的早上；屋頂的章末對話寫下旗標就結束本章。
func _test_chapter_link() -> void:
	var dawn := load("res://data/levels/ch1_pawnshop_dawn.tres") as LevelData
	check(dawn != null and dawn.next_level == LEVEL % "pawnshop", "chapter 1 ends into the chapter 2 morning")
	var rooftop: LevelData = _datas.get("rooftop")
	check(rooftop != null and rooftop.complete_on_flag == &"ch2_heron_closed", "the rooftop ends chapter 2 on its flag")
	check(rooftop != null and rooftop.next_level == "res://data/levels/ch3_pawnshop.tres", "the end of chapter 2 leads into the chapter 3 morning")
	if rooftop == null:
		return
	GameState.start_new_run(GameState.difficulties[1])
	var level := await start_level(rooftop)
	var done := [false]
	level.completed.connect(func() -> void: done[0] = true)
	GameState.set_flag(&"ch2_heron_closed")
	for i in 600:
		if done[0]:
			break
		await frames(2)
	check(done[0], "setting the chapter flag plays the end card and completes the chapter")
	await end_level(level)
	GameState.start_new_run(GameState.difficulties[1])
