extends RefCounted
## 第二章起各章共用的劇本與地圖檢查（ST-19、ST-21）：出入口兩端相通、人物入口接得到劇本、任務標記落在真的人物或物件上、
## 正式過場的構圖。各章的套件只放自己的劇情規則，共同規則寫在這裡，新章節加一行就能沿用。


## 讀進本章的區域：{區域 id: LevelData}。讀不到或章節不對就記一筆失敗。
static func load_areas(s: TestSuite, prefix: String, chapter: StringName, areas: PackedStringArray) -> Dictionary:
	var datas: Dictionary = {}
	for id in areas:
		var data := load("res://data/levels/%s_%s.tres" % [prefix, id]) as LevelData
		s.check(data != null and data.chapter == chapter, "%s_%s loads and belongs to %s" % [prefix, id, chapter])
		if data != null:
			datas[id] = data
	return datas


## 每個有目標的出入口：目標區域存在，而且那一頭有同名的回程出入口指回來。
static func check_portals(s: TestSuite, label: String, datas: Dictionary) -> void:
	var broken := PackedStringArray()
	for id: String in datas:
		var data := datas[id] as LevelData
		for key: String in data.legend:
			var portal := data.legend[key] as PortalData
			if portal == null or portal.target_level.is_empty():
				continue
			var target := load(portal.target_level) as LevelData if ResourceLoader.exists(portal.target_level) else null
			var back := portal_by_id(target, portal.target_portal) if target != null else null
			if back == null or back.target_level != data.resource_path or back.target_portal != portal.id:
				broken.append("%s/%s→%s/%s" % [id, portal.id, portal.target_level.get_file(), portal.target_portal])
	s.check(broken.is_empty(), "every %s portal has a matching way back: %s" % [label, broken])


static func portal_by_id(data: LevelData, id: StringName) -> PortalData:
	for key: String in data.legend:
		var portal := data.legend[key] as PortalData
		if portal != null and portal.id == id:
			return portal
	return null


## 每個人物與物件的入口都是劇本裡的分派場景，而且每條路線都接到存在的段落。
static func check_entries(s: TestSuite, label: String, datas: Dictionary, minimum: int) -> void:
	var problems := PackedStringArray()
	var count := 0
	for id: String in datas:
		for key: String in (datas[id] as LevelData).legend:
			var npc := (datas[id] as LevelData).legend[key] as NpcData
			if npc == null:
				continue
			count += 1
			for talk in npc.talks:
				if not Story.has_scene(talk.scene) or Story.scene_mode(talk.scene) == &"":
					problems.append("%s:%s" % [npc.id, talk.scene])
				for route: Variant in (Story._scenes.get(String(talk.scene), {}) as Dictionary).get("routes", []):
					if not Story.has_scene(StringName(str((route as Dictionary).get("target", "")))):
						problems.append("%s→%s" % [talk.scene, route])
	s.check(count >= minimum and problems.is_empty(), "all %d %s people and objects lead into the script: %s" % [count, label, problems])


## 任務步驟的地圖位置就是那個人物或物件站的格子（地圖與任務頁讀的是同一份資料）。
static func check_quest_markers(s: TestSuite, label: String, prefix: String, story_path: String, datas: Dictionary, minimum: int) -> void:
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	s.check(catalog.issues.is_empty(), "the %s quests load without issues: %s" % [label, catalog.issues])
	var misplaced := PackedStringArray()
	var steps := 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(story_path))
	var quests: Array = (parsed as Dictionary).get("quests", []) if parsed is Dictionary else []
	for quest: Dictionary in quests:
		for step: Dictionary in quest.get("steps", []):
			steps += 1
			var location: Dictionary = step.get("location", {})
			var level := str(location.get("level", ""))
			var area := level.get_file().get_basename().trim_prefix(prefix + "_")
			var cell: Array = location.get("cell", [])
			if not datas.has(area) or cell.size() != 2:
				misplaced.append("%s：%s" % [quest.get("id"), level])
				continue
			var data := datas[area] as LevelData
			var glyph := LevelBuilder.parse(data).cell(int(cell[0]), int(cell[1]))
			if not data.legend.has(glyph) or not data.legend[glyph] is NpcData:
				misplaced.append("%s 的「%s」在 %s (%d,%d) 是 %s" % [quest.get("id"), step.get("title"), area, cell[0], cell[1], glyph])
	s.check(steps >= minimum and misplaced.is_empty(), "every %s quest step points at its person or object (%d steps): %s" % [label, steps, misplaced])


## 本章的正式過場（不疊在地圖上的動畫過場）：演員腳底在對話框之上、頭不進黑邊、場景資料通過檢查。
static func check_staging(s: TestSuite, label: String, prefix: String, minimum: int) -> void:
	var checked := 0
	var problems := PackedStringArray()
	for id in Story.scene_ids():
		var scene: Dictionary = Story._scenes[id]
		if not str(id).begins_with(prefix + "_") or str(scene.get("mode", "")) != "animated" or bool(scene.get("overlay", false)):
			continue
		checked += 1
		problems.append_array(CutsceneChecker.validate(String(id), scene, Story._speakers))
		problems.append_array(CutsceneChecker.staging_problems(String(id), scene))
	s.check(checked >= minimum and problems.is_empty(), "the %d staged %s scenes pass the cutscene and framing checks: %s" % [checked, label, problems])
