class_name Chapter2StorySuite
extends TestSuite
## 第二章「鷺」（ST-19）：區域之間的出入口兩端相通、每個人物入口接得到劇本、任務標記落在真的人物或物件上、
## 主要的劇情關卡依進度挑對段落、第一章接第二章、屋頂章末寫入旗標就結束本章。
## 整章依序推進用 tools/ch2_flow_probe.tscn（兩條阿勇路線）驗；這裡只放快速、穩定的資料與規則檢查。

const AREAS: PackedStringArray = ["pawnshop", "rooftop", "harbor_street", "market_gate", "market", "ali_home", "loading",
		"ledger_front", "ledger_office", "lounge_front"]
const LEVEL := "res://data/levels/ch2_%s.tres"

var _datas: Dictionary[String, LevelData] = {}


func run() -> void:
	for id in AREAS:
		var data := load(LEVEL % id) as LevelData
		check(data != null and data.chapter == &"ch2_heron", "ch2_%s loads and belongs to chapter 2" % id)
		if data != null:
			_datas[id] = data
	_test_portals()
	_test_entries()
	_test_quest_markers()
	_test_story_gates()
	_test_ledger_install()
	_test_street_line()
	await _test_chapter_link()


## 每個有目標的出入口：目標區域存在，而且那一頭有同名的回程出入口指回來。
func _test_portals() -> void:
	var broken := PackedStringArray()
	for id in _datas:
		for key: String in _datas[id].legend:
			var portal := _datas[id].legend[key] as PortalData
			if portal == null or portal.target_level.is_empty():
				continue
			var target := load(portal.target_level) as LevelData if ResourceLoader.exists(portal.target_level) else null
			var back := _portal(target, portal.target_portal) if target != null else null
			if back == null or back.target_level != _datas[id].resource_path or back.target_portal != portal.id:
				broken.append("%s/%s→%s/%s" % [id, portal.id, portal.target_level.get_file(), portal.target_portal])
	check(broken.is_empty(), "every chapter 2 portal has a matching way back: %s" % [broken])


func _portal(data: LevelData, id: StringName) -> PortalData:
	for key: String in data.legend:
		var portal := data.legend[key] as PortalData
		if portal != null and portal.id == id:
			return portal
	return null


## 每個人物與物件的入口都是劇本裡的分派場景，而且每條路線都接到存在的段落。
func _test_entries() -> void:
	var problems := PackedStringArray()
	var count := 0
	for id in _datas:
		for key: String in _datas[id].legend:
			var npc := _datas[id].legend[key] as NpcData
			if npc == null:
				continue
			count += 1
			for talk in npc.talks:
				if not Story.has_scene(talk.scene) or Story.scene_mode(talk.scene) == &"":
					problems.append("%s:%s" % [npc.id, talk.scene])
				for route: Variant in (Story._scenes.get(String(talk.scene), {}) as Dictionary).get("routes", []):
					if not Story.has_scene(StringName(str((route as Dictionary).get("target", "")))):
						problems.append("%s→%s" % [talk.scene, route])
	check(count >= 20 and problems.is_empty(), "all %d chapter 2 people and objects lead into the script: %s" % [count, problems])


## 任務步驟的地圖位置就是那個人物或物件站的格子（地圖與任務頁讀的是同一份資料）。
func _test_quest_markers() -> void:
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	check(catalog.issues.is_empty(), "the chapter 2 quests load without issues: %s" % [catalog.issues])
	var misplaced := PackedStringArray()
	var steps := 0
	for quest: Dictionary in _raw_quests():
		for step: Dictionary in quest.get("steps", []):
			steps += 1
			var location: Dictionary = step.get("location", {})
			var level := str(location.get("level", ""))
			var area := level.get_file().get_basename().trim_prefix("ch2_")
			var cell: Array = location.get("cell", [])
			if not _datas.has(area) or cell.size() != 2:
				misplaced.append("%s：%s" % [quest.get("id"), level])
				continue
			var layout := LevelBuilder.parse(_datas[area])
			var glyph := layout.cell(int(cell[0]), int(cell[1]))
			if not _datas[area].legend.has(glyph) or not _datas[area].legend[glyph] is NpcData:
				misplaced.append("%s 的「%s」在 %s (%d,%d) 是 %s" % [quest.get("id"), step.get("title"), area, cell[0], cell[1], glyph])
	check(steps >= 18 and misplaced.is_empty(), "every chapter 2 quest step points at its person or object (%d steps): %s" % [steps, misplaced])


func _raw_quests() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/ch2_heron.json"))
	return (data as Dictionary).get("quests", []) if data is Dictionary else []


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
	check(Story.validate().is_empty(), "the merged story passes validation")
	GameState.start_new_run(GameState.difficulties[1])


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
	check(is_equal_approx(layout.ground_y, 20.0 * layout.tile_size), "the street line ignores the wide canopy (%.0f)" % layout.ground_y)
	check(is_equal_approx(layout.surface_heights[40], 13.0 * layout.tile_size), "the canopy is still the top surface of its columns")


## 第一章的天亮章末接第二章的早上；屋頂的章末對話寫下旗標就結束本章。
func _test_chapter_link() -> void:
	var dawn := load("res://data/levels/ch1_pawnshop_dawn.tres") as LevelData
	check(dawn != null and dawn.next_level == LEVEL % "pawnshop", "chapter 1 ends into the chapter 2 morning")
	var rooftop: LevelData = _datas.get("rooftop")
	check(rooftop != null and rooftop.complete_on_flag == &"ch2_heron_closed", "the rooftop ends chapter 2 on its flag")
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
