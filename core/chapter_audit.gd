class_name ChapterAudit
extends RefCounted
## 章節逐區稽核（NE-233～235 的自動部分）：每個區域的長度與估計時間、遭遇、復原點間距、出入口與上鎖條件、場景合理性問題、
## 程式暫代的物件（占位）；整章的區域連結圖（迴圈、死路、從入口走不到的區域）與「永遠解不開的鎖」。
## 全部從正式資料推算（LevelData、地圖、章節設計 JSON、故事來源），新章節只要資料就自動納入。
## 只產生報告與問題清單，不改任何資料；人工遊玩、畫面與手感仍要另外驗收。

const LEVEL_DIR := "res://data/levels"
## 復原點（含出入口與起點）之間超過這個格數，死掉要走很遠才回得來。
const MAX_CHECKPOINT_GAP_TILES := 160
## 沒有遭遇、對話或互動的連續時間超過這個秒數，節奏可能太空。
const MAX_QUIET_SECONDS := 120.0
## 程式還在用簡單畫法暫代的固定物件（design/20-campaign-experience/FIXTURE_ASSETS.md 的「沒有涵蓋的缺口」）。
const PLACEHOLDER_MECHANISMS := {MechanismData.Kind.LIFT: "升降平台（色塊加亮線）", MechanismData.Kind.POWER_SWITCH: "電源開關（舊畫法）"}
const PLACEHOLDER_BREAKABLES := {BreakableData.Look.CRATE: "木箱（程式畫的簡單造型）", BreakableData.Look.BARREL: "油桶（程式畫的簡單造型）", BreakableData.Look.GLASS: "玻璃（程式畫的簡單造型）"}


## 一章的稽核結果：{ id, entry, areas, graph, locked_exits, findings }。
static func audit(chapter: StringName, story_paths: Array[String] = Story.CHAPTER_PATHS) -> Dictionary:
	var index := QuestMapIndex.for_chapter(chapter)
	var paths: Array = index.areas.keys()
	paths.sort()
	var alias := CampaignLedger._layout_aliases(paths)
	var writers := flag_writers(story_paths)
	var areas: Array[Dictionary] = []
	var findings: Array[Dictionary] = []
	var locked: Array[Dictionary] = []
	var counted := {}
	for path: String in paths:
		var node: String = alias.get(path, path)
		var area := _area(index, path)
		area["shares_map_with"] = "" if node == path else node
		areas.append(area)
		for exit: Dictionary in area["exits"]:
			if exit["flag"] != "":
				var entry := {"area": path, "to": exit["to"], "flag": exit["flag"], "written": writers.has(exit["flag"])}
				locked.append(entry)
				if not entry["written"]:
					_find(findings, "error", path, "lock", "往 %s 的出入口要 %s，但沒有任何劇情、物品、機關或練習會寫入這個旗標，可能永遠打不開" % [_short(exit["to"]), exit["flag"]])
		if counted.has(node):
			continue  # 共用地圖的區域只檢查一次地圖本身的問題。
		counted[node] = true
		_area_findings(area, findings)
	var graph := _graph(index, paths, alias, CampaignLedger._entry(String(chapter), paths, _first_level(), _levels_by_chapter()))
	for path: String in graph["unreachable"]:
		_find(findings, "error", path, "unreachable", "從章節入口沿出入口走不到這個區域")
	for path: String in graph["dead_ends"]:
		var matches := areas.filter(func(a: Dictionary) -> bool: return a["path"] == path)
		if not matches.is_empty() and matches[0]["purpose"].is_empty():
			_find(findings, "warn", path, "dead_end", "只有一個出入口的死路，區域裡沒有拾取、人物、劇情或商店，走進去沒有收穫")
	var minutes := 0.0
	var encounters := 0
	for area: Dictionary in areas:
		if area["shares_map_with"] == "":
			minutes += float(area["minutes"])
			encounters += int(area["encounters"])
	var first_time := minutes * PacingEstimate.FIRST_TIME_FACTOR
	if first_time < PacingEstimate.TARGET_MINUTES.x:
		_find(findings, "warn", graph["entry"], "length", "整章第一次玩估計約 %.0f 分鐘（不含過場；目標 %.0f–%.0f），遭遇 %d 場" % [
				first_time, PacingEstimate.TARGET_MINUTES.x, PacingEstimate.TARGET_MINUTES.y, encounters])
	return {"id": String(chapter), "entry": graph["entry"], "areas": areas, "graph": graph, "locked_exits": locked, "findings": findings,
			"minutes": minutes, "first_time_minutes": first_time, "encounters": encounters}


## 全部會寫入旗標的來源：故事結果、衍生旗標、劇情物品、關卡的頻道／跳過旗標、練習完成或失敗。
static func flag_writers(story_paths: Array[String] = Story.CHAPTER_PATHS) -> Dictionary:
	var result := {}
	for path in story_paths:
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
			continue
		var results: Array = []
		CampaignLedger._collect_results(json.data.get("scenes", {}), results)
		for item: Variant in results:
			if item is Dictionary and item.get("kind") == "flag":
				result[str(item.get("id", ""))] = true
		if json.data.get("derived_flags") is Dictionary:
			for key: String in json.data["derived_flags"]:
				result[key] = true
	for resource in ResourceCatalog.load_dir("res://data/story_items", StoryItemData, "ChapterAudit"):
		var item := resource as StoryItemData
		if item.acquire_flag != &"":
			result[String(item.acquire_flag)] = true
	for resource in ResourceCatalog.load_dir(LEVEL_DIR, LevelData, "ChapterAudit"):
		var data := resource as LevelData
		for flag: StringName in data.channel_done_flags.values() + data.channel_cleared_flags.values():
			result[String(flag)] = true
		for flag in data.skip_flags:
			result[flag] = true
		for value: Resource in data.legend.values():
			if value is TrainingData:
				for flag: StringName in [(value as TrainingData).done_flag, (value as TrainingData).fail_flag]:
					if flag != &"":
						result[String(flag)] = true
	result.erase("")
	return result


## 人看的報表：每區一行，最後列問題。
static func report(result: Dictionary) -> String:
	var lines := PackedStringArray()
	var graph: Dictionary = result["graph"]
	lines.append("【%s】%d 區、%d 條連線、迴圈 %d、死路 %d、走不到 %d；入口 %s；估計 %.0f 分鐘（第一次玩約 %.0f，不含過場）、遭遇 %d 場" % [
			result["id"], graph["areas"], graph["links"], graph["loops"], graph["dead_ends"].size(), graph["unreachable"].size(),
			_short(graph["entry"]), result["minutes"], result["first_time_minutes"], result["encounters"]])
	lines.append("  %-18s %5s %6s %4s %4s %6s %4s %4s %s" % ["區域", "寬", "估分鐘", "遭遇", "復原", "最大間距", "鎖", "場景錯", "占位"])
	for area: Dictionary in result["areas"]:
		if area["shares_map_with"] != "":
			continue
		lines.append("  %-18s %5d %6.1f %4d %4d %6d %4d %4d %s" % [_short(area["path"]), area["width"], area["minutes"], area["encounters"], area["checkpoints"],
				area["checkpoint_gap"], area["exits"].filter(func(e: Dictionary) -> bool: return e["flag"] != "").size(), area["scene_errors"],
				str(area["placeholders"].values().reduce(func(a: int, b: int) -> int: return a + b, 0)) if not area["placeholders"].is_empty() else "—"])
	for finding: Dictionary in result["findings"]:
		lines.append("  [%s] %s：%s" % [{"error": "錯誤", "warn": "注意", "placeholder": "占位"}.get(finding["level"], finding["level"]), _short(finding["area"]), finding["text"]])
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# 內部
# ---------------------------------------------------------------------------

static func _area(index: QuestMapIndex, path: String) -> Dictionary:
	var entry: Dictionary = index.areas[path]
	var data: LevelData = entry["data"]
	var layout: LevelLayout = entry["layout"]
	var design := _design(path)
	var ranges: Array[Vector2] = []
	for e: Variant in design.get("encounters", []):
		if e is Dictionary and e.has("x0") and e.has("x1"):
			ranges.append(Vector2(float(e["x0"]), float(e["x1"])))
	var pacing := PacingEstimate.area(data, layout, func(scene: StringName) -> int: return Story.scene_lines(scene).size(), ranges)
	var seconds := 0.0
	for key in ["walk", "combat", "talk", "bubbles", "pickups", "puzzles", "shop", "practice"]:
		seconds += float(pacing.get(key, 0.0))
	var stops: Array[float] = []
	if layout.has_player_start:
		stops.append(layout.player_start.x)
	for point in layout.checkpoints:
		stops.append(point.x)
	var exits: Array[Dictionary] = []
	var purpose := PackedStringArray()
	var placeholders := {}
	for spawn: Dictionary in layout.spawns:
		var res: Resource = spawn["resource"]
		if res is PortalData:
			var portal := res as PortalData
			stops.append((spawn["position"] as Vector2).x)
			exits.append({"to": portal.target_level, "flag": String(portal.requires_flag), "style": portal.style, "cell": spawn["cell"]})
		elif res is CreditPileData or res is ConsumableData or res is StoryItemData or res is WeaponData:
			purpose.append("拾取")
		elif res is NpcData:
			purpose.append("人物")
			_npc_placeholder(res as NpcData, placeholders)
		elif res is ShopData:
			purpose.append("商店")
		elif res is EnemyData:
			_enemy_placeholder(res as EnemyData, placeholders)
		elif res is MechanismData and PLACEHOLDER_MECHANISMS.has((res as MechanismData).kind):
			_count(placeholders, PLACEHOLDER_MECHANISMS[(res as MechanismData).kind])
		elif res is BreakableData and PLACEHOLDER_BREAKABLES.has((res as BreakableData).look):
			_count(placeholders, PLACEHOLDER_BREAKABLES[(res as BreakableData).look])
	if not data.story_triggers.is_empty() or data.intro_scene != &"" or data.outro_scene != &"":
		purpose.append("劇情")
	if not layout.boss_spawn.is_empty():
		_enemy_placeholder(layout.boss_spawn["resource"] as EnemyData, placeholders)
	stops.sort()
	var gap := 0.0
	var previous := 0.0
	for x in stops + [float(layout.width * layout.tile_size)]:
		gap = maxf(gap, x - previous)
		previous = x
	var scene_issues := SceneAudit.audit(data, layout)
	var kinds := {}
	var errors := 0
	for issue: Dictionary in scene_issues:
		if issue.get("severity") == SceneAudit.ERROR:
			errors += 1
			kinds[issue.get("code", "")] = int(kinds.get(issue.get("code", ""), 0)) + 1
	return {"path": path, "width": layout.width, "height": layout.height, "minutes": seconds / 60.0,
			"encounters": int(pacing.get("encounters", 0)), "max_quiet": float(pacing.get("max_quiet", 0.0)),
			"checkpoints": layout.checkpoints.size(), "checkpoint_gap": int(round(gap / float(layout.tile_size))),
			"exits": exits, "purpose": purpose, "placeholders": placeholders, "features": design.get("features", {}),
			"scene_errors": errors, "scene_error_kinds": kinds, "has_boss": not layout.boss_spawn.is_empty()}


static func _area_findings(area: Dictionary, findings: Array[Dictionary]) -> void:
	var path: String = area["path"]
	if int(area["scene_errors"]) > 0:
		_find(findings, "error", path, "scene", "場景合理性有 %d 個錯誤（%s），細節跑 tools/scene_report.tscn -- --level=%s" % [
				area["scene_errors"], area["scene_error_kinds"], _short(path)])
	if int(area["checkpoint_gap"]) > MAX_CHECKPOINT_GAP_TILES:
		_find(findings, "warn", path, "checkpoint", "復原點、起點與出入口之間最遠相隔 %d 格（上限 %d），死掉要走很遠才回得來" % [area["checkpoint_gap"], MAX_CHECKPOINT_GAP_TILES])
	if float(area["max_quiet"]) > MAX_QUIET_SECONDS:
		_find(findings, "warn", path, "pacing", "最長 %.0f 秒沒有遭遇、對話或互動（上限 %.0f 秒）" % [area["max_quiet"], MAX_QUIET_SECONDS])
	if not area["placeholders"].is_empty():
		var items := PackedStringArray()
		for name: String in area["placeholders"]:
			items.append("%s ×%d" % [name, area["placeholders"][name]] if int(area["placeholders"][name]) > 1 else name)
		_find(findings, "placeholder", path, "placeholder", "；".join(items))


## 區域連結圖：出入口與 next_level 都算一條連線（共用地圖的區域視為同一個節點）。
static func _graph(index: QuestMapIndex, paths: Array, alias: Dictionary, entry: String) -> Dictionary:
	var links := {}
	var neighbours := {}
	for path: String in paths:
		var node: String = alias.get(path, path)
		neighbours[node] = neighbours.get(node, {})
	for path: String in paths:
		var node: String = alias.get(path, path)
		for next in CampaignLedger._neighbours(index, paths, alias, node):
			if next == node or not neighbours.has(next):
				continue
			var key := [node, next] if node < next else [next, node]
			links["%s|%s" % key] = true
			neighbours[node][next] = true
			neighbours[next][node] = true
	var start: String = alias.get(entry, entry)
	var seen := {start: true} if neighbours.has(start) else {}
	var queue: Array = seen.keys()
	while not queue.is_empty():
		for next: String in neighbours[queue.pop_front()]:
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	var components := 0
	var visited := {}
	for node: String in neighbours:
		if visited.has(node):
			continue
		components += 1
		var stack: Array = [node]
		while not stack.is_empty():
			var current: String = stack.pop_back()
			if visited.has(current):
				continue
			visited[current] = true
			stack.append_array(neighbours[current].keys())
	var dead_ends: Array[String] = []
	var unreachable: Array[String] = []
	for node: String in neighbours:
		if neighbours[node].size() == 1 and node != start:
			dead_ends.append(node)
		if not seen.has(node):
			unreachable.append(node)
	return {"entry": start, "areas": neighbours.size(), "links": links.size(), "loops": links.size() - neighbours.size() + components,
			"dead_ends": dead_ends, "unreachable": unreachable}


static func _npc_placeholder(npc: NpcData, placeholders: Dictionary) -> void:
	if npc.kind == NpcData.Kind.OBJECT:
		return  # 物件型互動點的外觀是旁邊的場景物件；缺口由場景組量距離盤點（CH2_CH3_SCENE_GAPS.md）。
	if npc.rig_id.is_empty() or not FileAccess.file_exists(RigLibrary.CHARACTER_PATH % npc.rig_id):
		_count(placeholders, "人物外觀缺檔（退回頭像剪影）：%s" % (npc.rig_id if not npc.rig_id.is_empty() else String(npc.id)))
	elif not RigLibrary.has_own_rig(npc.rig_id):
		_count(placeholders, "人物沿用共用 Q 版骨架：%s" % npc.rig_id)


static func _enemy_placeholder(enemy: EnemyData, placeholders: Dictionary) -> void:
	if enemy == null:
		return
	if not enemy.creature_skin.is_empty():
		if not FileAccess.file_exists("res://art/creatures/%s.json" % enemy.creature_skin):
			_count(placeholders, "敵人外觀缺檔：%s" % enemy.creature_skin)
	elif not enemy.rig_skin.is_empty() and not FileAccess.file_exists(RigLibrary.CHARACTER_PATH % enemy.rig_skin):
		_count(placeholders, "敵人外觀缺檔：%s" % enemy.rig_skin)


static func _count(into: Dictionary, key: String) -> void:
	into[key] = int(into.get(key, 0)) + 1


static func _find(findings: Array[Dictionary], level: String, area: String, kind: String, text: String) -> void:
	findings.append({"level": level, "area": area, "kind": kind, "text": text})


## 區域在章節設計 JSON 裡的條目（res://data/levels/ch2_market.tres → ch2_design.json 的 areas.market）。
static func _design(path: String) -> Dictionary:
	var name := path.get_file().get_basename()
	var prefix := name.get_slice("_", 0)
	var design_path := "%s/%s_design.json" % [LEVEL_DIR, prefix]
	if not FileAccess.file_exists(design_path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(design_path)) != OK or not json.data is Dictionary:
		push_error("[ChapterAudit] 讀不到章節設計：%s" % design_path)
		return {}
	var area: Variant = json.data.get("areas", {}).get(name.trim_prefix(prefix + "_"), {})
	return area if area is Dictionary else {}


static func _first_level() -> String:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CampaignLedger.CAMPAIGN_PATH)) == OK and json.data is Dictionary:
		return str(json.data.get("first_level", ""))
	return ""


static func _levels_by_chapter() -> Dictionary:
	return CampaignLedger._levels_by_chapter()


static func _short(path: String) -> String:
	return path.get_file().get_basename()
