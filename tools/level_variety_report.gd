extends Node
## 關卡多樣性盤點（地圖線第 1 項）：每章每區「除了開槍還做了什麼」，全部從 LevelData 與地圖算出。
## godot --headless --path . res://tools/level_variety_report.tscn -- --out=<絕對路徑.md> [--json=<絕對路徑.json>] [--chapter=ch2_heron]
## 只讀資料、不改任何東西。高低差與路線用 SceneAudit 的可達格（走、跳、落、升降梯）推算，不是遊測。

## 可達的站立列要被這麼多欄用到才算一層（排除單格突出的台階）。
const TIER_MIN_COLUMNS := 6
## 同一欄兩個可站高度至少差這麼多列才算上下兩條路（角色身高約 3.5 格）。
const LAYER_GAP_ROWS := 4
## 整區可站高度的落差到這麼多列（約兩個身高）才算有爬升或下潛；只差一次跳躍的台階不算。
const MOVE_SPAN_ROWS := 6
## 上下兩層連續至少這麼多欄才算一段第二路線（允許中間斷 2 欄）。
const ROUTE_MIN_COLUMNS := 12
## 一個「畫面」的寬度（格）：1280 像素寬、鏡頭 2 倍。
const SCREEN_TILES := 40
## 連續這麼多個只有戰鬥的畫面就列出來。
const COMBAT_RUN := 3
## 舊示範關卡（level_01、level_02），不在正式章節裡。
const OUT_OF_CAMPAIGN := ["chapter_01", "chapter_02"]

var _out := ""
var _json := ""
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--json="):
			_json = arg.trim_prefix("--json=")
		elif arg.begins_with("--chapter="):
			_only = arg.trim_prefix("--chapter=")
	_run.call_deferred()


func _run() -> void:
	var levels := CampaignLedger._levels_by_chapter()
	var issues := PackedStringArray()
	var stories := CampaignLedger._stories_by_chapter(Story.CHAPTER_PATHS, issues)
	var first := ChapterAudit._first_level()
	var ids: Array = levels.keys()
	ids.sort()
	var chapters: Array[Dictionary] = []
	for id: String in ids:
		if OUT_OF_CAMPAIGN.has(id) or (not _only.is_empty() and id != _only):
			continue
		chapters.append(_chapter(id, levels[id], stories.get(id, {}), first, levels))
	var text := _markdown(chapters)
	print(text)
	if not _out.is_empty():
		_write(_out, text)
	if not _json.is_empty():
		_write(_json, JSON.stringify(chapters, "  "))
	get_tree().quit()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[LevelVariety] 無法寫入 %s（%s）" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)


func _chapter(id: String, paths: Array, story: Dictionary, first: String, levels: Dictionary) -> Dictionary:
	var ledger := CampaignLedger.chapter(id, paths, story, first, levels)
	var audit := ChapterAudit.audit(StringName(id))
	var minutes := {}
	for area: Dictionary in audit["areas"]:
		minutes[area["path"]] = area
	var index := QuestMapIndex.for_chapter(StringName(id))
	var alias := CampaignLedger._layout_aliases(paths)
	# 主線順序：照章節設計資料（<章>_design.json）裡區域的順序，那是產生器依劇情排的遊玩順序；
	# 設計資料沒列到的區域排在後面，照經濟帳本的路線。
	var route: Array = (ledger["route"] as Array).duplicate()
	var authored := _design_order(id)
	var order: Array[String] = []
	var sorted := paths.duplicate()
	sorted.sort()
	for path: String in sorted:
		var node: String = alias.get(path, path)
		if not order.has(node):
			order.append(node)
	order.sort_custom(func(x: String, y: String) -> bool:
		var ax := authored.find(x.get_file().get_basename())
		var ay := authored.find(y.get_file().get_basename())
		if ax != ay:
			return (ax if ax >= 0 else 999) < (ay if ay >= 0 else 999)
		return (route.find(x) if route.has(x) else 999) < (route.find(y) if route.has(y) else 999))
	# 帳本的路線會走鎖著的員工捷徑；連著兩個主線區域的通道（第一次必經）也算主線。
	for node in order:
		if route.has(node):
			continue
		var linked := {}
		for next: String in CampaignLedger._neighbours(index, paths, alias, node):
			if route.has(next):
				linked[next] = true
		if linked.size() >= 2:
			route.append(node)
	var areas: Array[Dictionary] = []
	for path in order:
		if not index.areas.has(path):
			continue
		var area := _area(index.areas[path]["data"], index.areas[path]["layout"])
		area["route"] = route.has(path)
		var pacing: Dictionary = minutes.get(path, {})
		area["minutes"] = float(pacing.get("minutes", 0.0))
		area["encounters"] = int(pacing.get("encounters", 0))
		area["main"] = _main_activity(area)
		areas.append(area)
	return {"id": id, "areas": areas, "combat_area_runs": _combat_area_runs(areas), "same_runs": _same_runs(areas), "enemy_runs": _enemy_runs(areas)}


func _area(data: LevelData, layout: LevelLayout) -> Dictionary:
	var w := layout.width
	var area := {"path": data.resource_path, "name": data.resource_path.get_file().get_basename(), "display": data.display_name,
			"width": w, "enemies": 0, "enemy_kinds": {}, "boss": not layout.boss_spawn.is_empty(), "locked_fights": 0, "npcs": 0, "objects": 0,
			"shops": 0, "credits": 0, "elevated_credits": 0, "pickups": 0, "secret_walls": 0,
			"ladders": 0, "lifts": 0, "exits": 0, "locked_exits": 0, "mechanisms": {}, "hazards": {}, "stealth": [],
			"timed": [], "challenges": [], "training": 0}
	# 每欄一份標記，給「只有戰鬥的畫面」用。
	var credit_cells: Array[Vector2i] = []
	var enemy_cols := PackedByteArray()
	var other_cols := PackedByteArray()
	enemy_cols.resize(w)
	other_cols.resize(w)
	if not layout.boss_spawn.is_empty():
		area["enemies"] += 1
		_count(area["enemy_kinds"], (layout.boss_spawn["resource"] as EnemyData).display_name)
		enemy_cols[clampi(layout.boss_spawn["cell"].x, 0, w - 1)] = 1
	for spawn: Dictionary in layout.spawns:
		var res: Resource = spawn["resource"]
		var x := clampi((spawn["cell"] as Vector2i).x, 0, w - 1)
		var other := true
		if res is EnemyData:
			area["enemies"] += 1
			_count(area["enemy_kinds"], (res as EnemyData).display_name)
			enemy_cols[x] = 1
			other = false
		elif res is PortalData:
			var portal := res as PortalData
			area["exits"] += 1
			if portal.requires_flag != &"":
				area["locked_exits"] += 1
			if portal.style == "ladder":
				area["ladders"] += 1
			else:
				other = false  # 一般門與路口不算「做了什麼」。
		elif res is NpcData:
			if (res as NpcData).kind == NpcData.Kind.PERSON:
				area["npcs"] += 1
			else:
				area["objects"] += 1
		elif res is ShopData:
			area["shops"] += 1
		elif res is CreditPileData:
			area["credits"] += 1
			other = false  # 路上的信用點不算另一種玩法；看得到拿不到的才算（見 climb_credits）。
			if spawn.get("elevated_credit", false):
				area["elevated_credits"] += 1
				other = true
			else:
				credit_cells.append(spawn["cell"])
		elif res is ConsumableData or res is StoryItemData or res is WeaponData:
			area["pickups"] += 1
			other = false
		elif res is BreakableData:
			if (res as BreakableData).look == BreakableData.Look.WALL:
				area["secret_walls"] += 1
			else:
				_count(area["mechanisms"], "可破壞物")
				other = false  # 貨箱、油桶是戰鬥裡的掩體與爆點，不是另一種玩法。
		elif res is MechanismData:
			var mech := res as MechanismData
			match mech.kind:
				MechanismData.Kind.ENCOUNTER:
					other = false
					if mech.lock_combat_area:
						area["locked_fights"] += 1
				MechanismData.Kind.LIFT:
					area["lifts"] += 1
				MechanismData.Kind.SWEEP_LANE:
					(area["timed"] as Array).append("掃描通道")
				_:
					_count(area["mechanisms"], MechanismData.Kind.keys()[mech.kind])
		elif res is TrainingData:
			area["training"] += 1
		elif res is ChaseData:
			(area["timed"] as Array).append("追逐光幕")
		elif res is VehicleData:
			(area["timed"] as Array).append("載具")
		elif res is DecoyRadioData:
			(area["stealth"] as Array).append("誘餌收音機")
		elif res is SuspendedLoadData:
			_count(area["mechanisms"], "吊掛貨箱")
		elif res is SteamValveData:
			_count(area["mechanisms"], "蒸汽閥")
		elif res is LiveCableData:
			_count(area["mechanisms"], "通電纜線")
		elif res is ConveyorData:
			_count(area["mechanisms"], "輸送帶")
		elif res is CrumblingWalkwayData:
			_count(area["mechanisms"], "會塌的走道")
		elif res is ThrowableData:
			_count(area["mechanisms"], "可投擲物")
			other = false
		else:
			other = false  # 純擺設。
		if other:
			other_cols[x] = 1
	for kind in [["尖刺", layout.spike_rects], ["雷射", layout.laser_rects], ["光橋", layout.ghost_rects]]:
		if not kind[1].is_empty():
			area["hazards"][kind[0]] = kind[1].size()
			for rect: Rect2i in kind[1]:
				for x in range(rect.position.x, mini(w, rect.end.x)):
					other_cols[x] = 1
	if data.shootable_lamps:
		(area["stealth"] as Array).append("可射暗的燈")
	if data.avoidance_encounter != null:
		(area["stealth"] as Array).append("避開遭遇")
	if data.traversal_trial != null:
		(area["timed"] as Array).append("移動試煉")
	for challenge: AreaChallengeData in data.challenges:
		if challenge != null:
			(area["challenges"] as Array).append(AreaChallengeData.Kind.keys()[challenge.kind])
	# 嚴格版：只看會互動的東西，不把上下兩層的地形當成另一種玩法。
	area["strict_combat_screens"] = _combat_screens(enemy_cols, other_cols.duplicate())
	area["screens"] = ceili(w / float(SCREEN_TILES))
	area["fight_screens"] = _count_screens(enemy_cols, other_cols, false)
	area["bare_fight_screens"] = _count_screens(enemy_cols, other_cols, true)
	var floors := _terrain(layout, area, other_cols)
	area["climb_credits"] = 0
	for cell in credit_cells:
		# 比那一欄最低的可站高度高出兩個身高以上：要爬上去才拿得到。
		if floors.has(cell.x) and int(floors[cell.x]) - cell.y >= MOVE_SPAN_ROWS:
			area["climb_credits"] += 1
			other_cols[cell.x] = 1
	area["kinds"] = _kinds(area)
	area["combat_only"] = area["enemies"] > 0 and (area["kinds"] as PackedStringArray).is_empty()
	area["combat_screens"] = _combat_screens(enemy_cols, other_cols)
	return area


## 高低差與第二路線：用可達的站立格算每欄有幾層、整區用到幾個高度。
## 回傳每欄最低的可站列（地面）。
func _terrain(layout: LevelLayout, area: Dictionary, other_cols: PackedByteArray) -> Dictionary:
	var reach := SceneAudit.reachable_cells(layout, SceneAudit._mechanism_platforms(layout))
	var by_column := {}
	var row_use := {}
	for cell: Vector2i in reach:
		if not by_column.has(cell.x):
			by_column[cell.x] = []
		(by_column[cell.x] as Array).append(cell.y)
		row_use[cell.y] = int(row_use.get(cell.y, 0)) + 1
	var tiers: Array[int] = []
	for row: int in row_use:
		if row_use[row] >= TIER_MIN_COLUMNS:
			tiers.append(row)
	tiers.sort()
	var tier_count := 0
	var last := -100
	for row in tiers:
		if row - last >= 2:
			tier_count += 1
		last = row
	var multi := PackedByteArray()
	multi.resize(layout.width)
	var walkable := 0
	var layered := 0
	for x: int in by_column:
		var rows: Array = by_column[x]
		rows.sort()
		walkable += 1
		if int(rows[-1]) - int(rows[0]) >= LAYER_GAP_ROWS:
			layered += 1
			multi[x] = 1
	var routes := 0
	var run := 0
	var gap := 0
	for x in layout.width:
		if multi[x] == 1:
			run += 1 + gap
			gap = 0
		elif run > 0 and gap < 2:
			gap += 1
		else:
			if run >= ROUTE_MIN_COLUMNS:
				routes += 1
			run = 0
			gap = 0
	if run >= ROUTE_MIN_COLUMNS:
		routes += 1
	area["reachable_cells"] = reach.size()
	area["tiers"] = tier_count
	area["span_rows"] = (tiers[-1] - tiers[0]) if tiers.size() > 1 else 0
	area["layered_share"] = layered / float(maxi(1, walkable))
	area["second_routes"] = routes
	# 上下兩層的欄位本身就是「不只是開槍」：玩家可以選高低路。
	var floors := {}
	for x in layout.width:
		if multi[x] == 1:
			other_cols[x] = 1
	for x: int in by_column:
		floors[x] = (by_column[x] as Array).max()
	return floors


func _kinds(a: Dictionary) -> PackedStringArray:
	var kinds := PackedStringArray()
	if a["second_routes"] > 0 or a["ladders"] > 0 or a["lifts"] > 0 or a["span_rows"] >= MOVE_SPAN_ROWS:
		kinds.append("移動／高低差")
	if not (a["mechanisms"] as Dictionary).is_empty() or not (a["hazards"] as Dictionary).is_empty():
		kinds.append("機關或危險地形")
	if not (a["stealth"] as Array).is_empty() or (a["challenges"] as Array).has("UNSEEN_PASS"):
		kinds.append("潛行／繞路")
	if not (a["timed"] as Array).is_empty():
		kinds.append("追逐／限時")
	if a["secret_walls"] > 0 or a["elevated_credits"] > 0 or a["climb_credits"] > 0 or not (a["challenges"] as Array).is_empty():
		kinds.append("秘密／可選")
	if a["npcs"] > 0 or a["objects"] > 0:
		kinds.append("對話／調查")
	if a["shops"] > 0:
		kinds.append("商店")
	if a["training"] > 0:
		kinds.append("練習")
	return kinds


## 畫面寬的窗格：有敵人、而且沒有任何機關、人物、拾取、秘密、梯子或上下兩層的窗格算「只有戰鬥」；連續 COMBAT_RUN 個以上列出。
func _combat_screens(enemy_cols: PackedByteArray, other_cols: PackedByteArray) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	var start := -1
	var screens := ceili(enemy_cols.size() / float(SCREEN_TILES))
	for s in screens + 1:
		var only := false
		if s < screens:
			var has_enemy := false
			var has_other := false
			for x in range(s * SCREEN_TILES, mini(enemy_cols.size(), (s + 1) * SCREEN_TILES)):
				has_enemy = has_enemy or enemy_cols[x] == 1
				has_other = has_other or other_cols[x] == 1
			only = has_enemy and not has_other
		if only and start < 0:
			start = s
		elif not only and start >= 0:
			if s - start >= COMBAT_RUN:
				runs.append({"from": start * SCREEN_TILES, "to": mini(enemy_cols.size(), s * SCREEN_TILES) - 1, "screens": s - start})
			start = -1
	return runs


## 有敵人的畫面數；bare 時只算其中沒有任何會互動的東西（機關、人物、秘密、梯子、危險地形）的畫面。
func _count_screens(enemy_cols: PackedByteArray, other_cols: PackedByteArray, bare: bool) -> int:
	var count := 0
	for s in ceili(enemy_cols.size() / float(SCREEN_TILES)):
		var has_enemy := false
		var has_other := false
		for x in range(s * SCREEN_TILES, mini(enemy_cols.size(), (s + 1) * SCREEN_TILES)):
			has_enemy = has_enemy or enemy_cols[x] == 1
			has_other = has_other or other_cols[x] == 1
		if has_enemy and (not bare or not has_other):
			count += 1
	return count


## 沿主線順序，連續 COMBAT_RUN 個以上「有戰鬥但沒有別的事」的區域。
func _combat_area_runs(areas: Array[Dictionary]) -> Array:
	var runs := []
	var current := []
	for area in areas + [{}]:
		if not area.is_empty() and area["route"] and area["combat_only"]:
			current.append(area["name"])
			continue
		if area.is_empty() or area["route"]:
			if current.size() >= COMBAT_RUN:
				runs.append(current.duplicate())
			current.clear()
	return runs


## 章節設計資料裡區域的順序（區域 id 加上章節前綴）。
func _design_order(chapter: String) -> Array:
	var prefix := chapter.get_slice("_", 0)
	var path := "res://data/levels/%s_design.json" % prefix
	if not FileAccess.file_exists(path):
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary or not json.data.get("areas") is Dictionary:
		push_error("[LevelVariety] 讀不到章節設計的區域順序：%s" % path)
		return []
	var result := []
	for key: String in json.data["areas"]:
		result.append("%s_%s" % [prefix, key])
	return result


## 這一區最主要的事（依序取第一個成立的）：給「同一種連續不超過兩個區域」用。
func _main_activity(a: Dictionary) -> String:
	var kinds: PackedStringArray = a["kinds"]
	if kinds.has("追逐／限時"):
		return "追逐／限時"
	if kinds.has("潛行／繞路"):
		return "潛行"
	var puzzle := false
	for key: String in a["mechanisms"]:
		puzzle = puzzle or not ["可破壞物", "可投擲物"].has(key)
	if a["encounters"] >= 1:  # 有遭遇（含小頭目）就是一場戰鬥。
		return "戰鬥＋機關" if puzzle else "戰鬥"
	if puzzle:
		return "機關"
	if kinds.has("移動／高低差") and a["second_routes"] > 0:
		return "移動"
	if kinds.has("商店") or a["npcs"] + a["objects"] > 0:
		return "對話（平地）"
	return "走路（平地）"


## 沿主線連續 COMBAT_RUN 個以上主要內容相同的區域。
## 同一種敵人在主線上連續 COMBAT_RUN 個以上「有敵人的區域」都出現（沒有敵人的區域不打斷，也不算進去）。
func _enemy_runs(areas: Array[Dictionary]) -> Array:
	var fights := areas.filter(func(a: Dictionary) -> bool: return a["route"] and a["enemies"] > 0)
	var kinds := {}
	for a: Dictionary in fights:
		for kind: String in a["enemy_kinds"]:
			kinds[kind] = true
	var runs := []
	for kind: String in kinds:
		var current := []
		for a: Dictionary in fights + [{"enemy_kinds": {}, "name": ""}]:
			if (a["enemy_kinds"] as Dictionary).has(kind):
				current.append(a["name"])
				continue
			if current.size() >= COMBAT_RUN:
				runs.append({"kind": kind, "areas": current.duplicate()})
			current.clear()
	return runs


func _same_runs(areas: Array[Dictionary]) -> Array:
	var runs := []
	var current := []
	var label := ""
	for area in areas.filter(func(a: Dictionary) -> bool: return a["route"]) + [{"main": ""}]:
		if area["main"] == label and not label.is_empty():
			current.append(area["name"])
			continue
		if current.size() >= COMBAT_RUN:
			runs.append({"main": label, "areas": current.duplicate()})
		label = area["main"]
		current = [area.get("name", "")]
	return runs


func _count(into: Dictionary, key: String) -> void:
	into[key] = int(into.get(key, 0)) + 1


## 單調分數：越長、越多敵人、越少種類越單調。只是排序用，不是品質分數。
static func monotony(a: Dictionary) -> float:
	var kinds := (a["kinds"] as PackedStringArray).size()
	return float(a["width"]) / 40.0 * (1.0 + 0.15 * float(a["enemies"])) / float(1 + kinds)


func _markdown(chapters: Array[Dictionary]) -> String:
	var lines := PackedStringArray()
	lines.append("<!-- 由 tools/level_variety_report.tscn 產生；改地圖後重跑 -->")
	for chapter in chapters:
		lines.append("")
		lines.append("### %s" % chapter["id"])
		lines.append("")
		lines.append("| 順序 | 區域 | 主線 | 長（格） | 估計分鐘 | 高低差（層／列） | 上下兩層比例 | 第二路線段 | 梯／升降 | 機關與危險地形 | 潛行 | 追逐限時 | 遭遇（場／敵） | 敵人種類 | 有敵人的畫面／其中只有戰鬥 | 鎖場 | 秘密與可選 | 人物／調查／商店 | 主要內容 | 除了開槍還做了什麼 |")
		lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
		var n := 0
		for a: Dictionary in chapter["areas"]:
			n += 1
			var mech := PackedStringArray()
			for key: String in a["mechanisms"]:
				mech.append("%s×%d" % [_mechanism_label(key), a["mechanisms"][key]])
			for key: String in a["hazards"]:
				mech.append("%s×%d" % [key, a["hazards"][key]])
			var secret := PackedStringArray()
			if a["secret_walls"] > 0:
				secret.append("裂牆×%d" % a["secret_walls"])
			if a["elevated_credits"] > 0:
				secret.append("要空中再躍的信用點×%d" % a["elevated_credits"])
			if a["climb_credits"] > 0:
				secret.append("要爬上去的信用點×%d" % a["climb_credits"])
			for c: String in a["challenges"]:
				secret.append({"ENVIRONMENT_KILLS": "挑戰：環境擊倒", "UNSEEN_PASS": "挑戰：不被發現"}.get(c, c))
			var kinds := ", ".join(a["kinds"]) if not (a["kinds"] as PackedStringArray).is_empty() else ("**只有戰鬥**" if a["enemies"] > 0 else "只有走路")
			for run: Dictionary in a["combat_screens"]:
				kinds += "；第 %d–%d 欄連續 %d 個畫面只有戰鬥" % [run["from"], run["to"], run["screens"]]
			for run: Dictionary in a["strict_combat_screens"]:
				kinds += "；第 %d–%d 欄連續 %d 個畫面除了地形高低沒有別的事" % [run["from"], run["to"], run["screens"]]
			lines.append("| %d | %s %s | %s | %d | %.1f | %d／%d | %d%% | %d | %d／%d | %s | %s | %s | %d／%d%s | %s | %d／%d（共 %d） | %d | %s | %d／%d／%d | %s | %s |" % [
					n, a["name"], a["display"], "是" if a["route"] else "支線", a["width"], a["minutes"], a["tiers"], a["span_rows"],
					roundi(a["layered_share"] * 100.0), a["second_routes"], a["ladders"], a["lifts"], _or_none(", ".join(mech)),
					_or_none(", ".join(PackedStringArray(a["stealth"]))), _or_none(", ".join(PackedStringArray(a["timed"]))), a["encounters"], a["enemies"], "（頭目）" if a["boss"] else "", _kinds_text(a["enemy_kinds"]), a["fight_screens"], a["bare_fight_screens"], a["screens"],
					a["locked_fights"], _or_none(", ".join(secret)), a["npcs"], a["objects"], a["shops"], a["main"], kinds])
		for run: Dictionary in chapter["enemy_runs"]:
			lines.append("")
			lines.append("- 「%s」連續出現在 %d 個有敵人的主線區域：%s" % [run["kind"], run["areas"].size(), " → ".join(PackedStringArray(run["areas"]))])
		for run: Dictionary in chapter["same_runs"]:
			lines.append("")
			lines.append("- 主線上連續 %d 個區域都是「%s」：%s" % [run["areas"].size(), run["main"], " → ".join(PackedStringArray(run["areas"]))])
		if not (chapter["combat_area_runs"] as Array).is_empty():
			for run: Array in chapter["combat_area_runs"]:
				lines.append("")
				lines.append("- 主線上連續 %d 個區域只有戰鬥：%s" % [run.size(), " → ".join(run)])
		var ranked: Array = (chapter["areas"] as Array).duplicate()
		ranked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return monotony(x) > monotony(y))
		var top := PackedStringArray()
		for a: Dictionary in ranked.slice(0, 3):
			top.append("%s（%.1f）" % [a["name"], monotony(a)])
		lines.append("")
		lines.append("- 單調分數最高的三區：%s" % "、".join(top))
	return "\n".join(lines) + "\n"


func _kinds_text(kinds: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind: String in kinds:
		parts.append("%s×%d" % [kind, kinds[kind]])
	return _or_none(", ".join(parts))


func _mechanism_label(key: String) -> String:
	return {"GATE": "閘門", "SWITCH": "開關", "POWER_SWITCH": "電源開關", "FLOOD_PIT": "水坑"}.get(key, key)


func _or_none(text: String) -> String:
	return text if not text.is_empty() else "—"
