class_name CampaignLedger
extends RefCounted
## 跨章經濟對帳（NE-231）：每章的主路收入、支線與探索收入、補給、死亡、典當與成長價格，全部由正式資料推算，改資料報表自動跟著變。
## 路線：章節入口 → 主線任務每個步驟標示的地點 → 章末，沿真實出入口找最短路（鎖住的門也算，因為主線會解開它）；
## 路線經過的區域是「主路」，章節其他區域是「探索」。共用同一張地圖的區域（例如天亮的當舖）只算一次。
## 「不刷錢」計畫：每個區域的敵人、地上與箱子只拿一次，只領主線任務報酬，所有付款都照最壞情況付，
## 每章扣掉打頭目前的必要補給與預估的死亡扣款，剩下的錢就是玩家自己選成長的預算。

const CAMPAIGN_PATH := "res://data/release/campaign.json"
const LEVEL_DIR := "res://data/levels"
## 成長的分類（玩家在改裝與義體頁看到的用途）。
const GROWTH_GUN := "槍械"
const GROWTH_MELEE := "近戰"
const GROWTH_DEFENSE := "防禦"
const GROWTH_CYBER := "義體"
const GROWTH_ORDER: Array[String] = [GROWTH_GUN, GROWTH_MELEE, GROWTH_DEFENSE, GROWTH_CYBER]
## 預估每章死在哪種扣款上限的次數（與節奏估計同一個假設）。
const EXPECTED_DEATHS := PacingEstimate.EXPECTED_DEATHS
## 任務獎勵文字裡的金額（取英文版的阿拉伯數字，中文版用國字）。
const _AMOUNT_PATTERN := "\\d+"


## 整份帳本：{ chapters, plan, growth, issues }。story_paths 可換成測試資料。
static func build(story_paths: Array[String] = Story.CHAPTER_PATHS) -> Dictionary:
	var issues := PackedStringArray()
	var campaign := _read_json(CAMPAIGN_PATH, issues)
	var stories := _stories_by_chapter(story_paths, issues)
	var levels := _levels_by_chapter()
	var chapters: Array[Dictionary] = []
	var raw_chapters: Variant = campaign.get("chapters", [])
	if not raw_chapters is Array:
		issues.append("%s.chapters：必須是陣列。" % CAMPAIGN_PATH)
		raw_chapters = []
	for entry: Variant in raw_chapters:
		var id := str(entry.get("id", "")) if entry is Dictionary else ""
		if id.is_empty():
			issues.append("%s：章節缺少 id。" % CAMPAIGN_PATH)
			continue
		if not levels.has(id):
			continue  # 沒有自己關卡的章節（序章的區域歸在第一章）不單獨對帳。
		chapters.append(chapter(id, levels[id], stories.get(id, {}), str(campaign.get("first_level", "")), levels))
	for c in chapters:
		for issue: String in c["issues"]:
			issues.append("%s：%s" % [c["id"], issue])
	var growth := growth_catalog()
	return {"chapters": chapters, "plan": no_grind_plan(chapters, growth), "growth": growth, "issues": issues}


## 一章的帳：路線、收入、付款、補給與死亡扣款。all_levels 用來找從前一章接進來的入口。
static func chapter(id: String, paths: Array, story: Dictionary, first_level: String, all_levels: Dictionary) -> Dictionary:
	var issues := PackedStringArray()
	var index := QuestMapIndex.for_chapter(StringName(id))
	var alias := _layout_aliases(paths)
	var entry := _entry(id, paths, first_level, all_levels)
	var terminal := _terminal(paths, story)
	var waypoints: Array[String] = []
	if not entry.is_empty():
		waypoints.append(entry)
	for quest: Dictionary in _quests(story, "main"):
		for step: Variant in quest.get("steps", []):
			var level := str(step.get("location", {}).get("level", "")) if step is Dictionary and step.get("location") is Dictionary else ""
			if not level.is_empty():
				waypoints.append(level)
	if not terminal.is_empty():
		waypoints.append(terminal)
	var route: Array[String] = []
	var breaks := PackedStringArray()
	for i in waypoints.size():
		var leg := [waypoints[i]] if i == 0 else _shortest(index, paths, alias, waypoints[i - 1], waypoints[i])
		if leg.is_empty():
			breaks.append("%s → %s" % [_short(waypoints[i - 1]), _short(waypoints[i])])
			leg = [waypoints[i]]
		for path: String in leg:
			var node: String = alias.get(path, path)
			if not route.has(node):
				route.append(node)
	for b in breaks:
		issues.append("主線路線斷開：%s 之間沒有出入口連通。" % b)
	var main := _empty_income()
	var explore := _empty_income()
	var areas: Array[Dictionary] = []
	var counted := {}
	for path: String in paths:
		var node: String = alias.get(path, path)
		if counted.has(node):
			continue
		counted[node] = true
		var area: Dictionary = index.areas.get(node, {})
		if area.is_empty():
			issues.append("讀不到區域：%s" % node)
			continue
		var income := EconomyReport.area_income(area["layout"])
		var on_route := route.has(node)
		_add_income(main if on_route else explore, income)
		areas.append({"path": node, "route": on_route, "income": income})
	var quests := _quest_money(story, issues)
	return {
		"id": id, "title": str(story.get("chapter", {}).get("title", id)), "entry": entry, "terminal": terminal,
		"route": route, "areas": areas, "map_main": main, "map_explore": explore,
		"quest_main": quests["main"], "quest_side": quests["side"], "payments": quests["payments"],
		"transactions": quests["transactions"], "supplies": int(EconomyReport.price_list()["supplies"]),
		"death_cap": _death_cap(paths), "death_ratio": _death_ratio(paths), "issues": issues,
	}


## 不刷錢的跨章累計：每章只拿主路與主線報酬、照最壞情況付款、買必要補給、死 EXPECTED_DEATHS 次；剩下的是成長預算。
static func no_grind_plan(chapters: Array[Dictionary], growth: Array[Dictionary]) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var wallet := 0
	for c in chapters:
		var income := int(c["map_main"]["total"]) + int(c["quest_main"])
		wallet += income + int(c["payments"])
		var short_before_supplies := maxi(0, int(c["supplies"]) - wallet)
		wallet -= int(c["supplies"])
		var deaths := 0
		for i in EXPECTED_DEATHS:
			var lost := int(floor(float(maxi(0, wallet)) * float(c["death_ratio"])))
			if int(c["death_cap"]) > 0:
				lost = mini(lost, int(c["death_cap"]))
			deaths += lost
			wallet -= lost
		var affordable := PackedStringArray()
		for category in GROWTH_ORDER:
			var cheapest := cheapest_in(growth, category)
			if cheapest > 0 and wallet >= cheapest:
				affordable.append(category)
		plan.append({"id": c["id"], "income": income, "payments": int(c["payments"]), "supplies": int(c["supplies"]),
				"short_before_supplies": short_before_supplies, "deaths": deaths, "spare": wallet,
				"side_and_explore": int(c["quest_side"]) + int(c["map_explore"]["total"]), "affordable": affordable})
	return plan


## 所有可以花錢的成長：槍械改裝（每把槍各自購買）、近戰招式、義體能力。防禦類目前只有電磁脈衝（NE-269 的臂盾零件落地後加入同一類）。
static func growth_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for upgrade in Progression.upgrade_catalog():
		var melee := upgrade.effect == WeaponUpgradeData.Effect.MELEE_TECHNIQUE
		result.append({"id": String(upgrade.id), "name": upgrade.display_name, "price": upgrade.cost,
				"category": GROWTH_MELEE if melee else GROWTH_GUN, "note": upgrade.description})
	for ability in Progression.ability_catalog():
		var defense := ability.kind == CyberAbilityData.Kind.EMP
		result.append({"id": String(ability.id), "name": ability.display_name, "price": ability.unlock_cost,
				"category": GROWTH_DEFENSE if defense else GROWTH_CYBER, "note": ability.description})
	return result


static func cheapest_in(growth: Array[Dictionary], category: String) -> int:
	var best := 0
	for item in growth:
		if item["category"] == category and int(item["price"]) > 0 and (best == 0 or int(item["price"]) < best):
			best = int(item["price"])
	return best


## 典當的週轉成本：當了再贖回，每件淨虧的利息（週轉不是收入）。
static func pawn_round_trip_costs() -> Dictionary:
	var result := {}
	for id: StringName in EconomyReport.REQUIRED_SUPPLIES:
		var item := ConsumableBag.find(id)
		if item != null:
			result[String(id)] = Progression.redeem_cost(item) - Progression.pawn_value(item)
	return result


## 任務獎勵文字與實際入帳一致：文字寫的每個金額都有對應的入帳，入帳的金額也都寫在任務獎勵裡。
## 回傳不一致的清單（空陣列＝一致）。延後結算（例如次晨才付的委託款）由實際付款那章的任務負責寫出淨額。
static func reward_mismatches(story: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	var money := _quest_money(story, issues)
	var by_quest: Dictionary = money["by_quest"]
	var regex := RegEx.create_from_string(_AMOUNT_PATTERN)
	for quest: Dictionary in _quests(story, ""):
		var id := str(quest.get("id", ""))
		var written := {}
		for m in regex.search_all(str(quest.get("reward_en", ""))):
			written[int(m.get_string())] = true
		var paid: Array = by_quest.get(id, [])
		var paid_set := {}
		for amount: int in paid:
			if amount > 0:  # 付款與 0 元收據（只記錄有沒有發生）不是獎勵，另在付款欄對帳。
				paid_set[amount] = true
		for amount: int in written:
			if paid_set.is_empty():
				continue  # 只寫金額、不在本章入帳：延後結算，由付款那章核對。
			if not paid_set.has(amount):
				issues.append("任務 %s 的獎勵寫 %d，實際入帳 %s" % [id, amount, paid])
		for amount: int in paid_set:
			if not written.has(amount):
				issues.append("任務 %s 實際入帳 %d，獎勵文字沒寫（%s）" % [id, amount, quest.get("reward", "")])
	return issues


## 一段人看的報表。
static func report(ledger: Dictionary) -> String:
	var lines := PackedStringArray()
	for c: Dictionary in ledger["chapters"]:
		var main: Dictionary = c["map_main"]
		var explore: Dictionary = c["map_explore"]
		lines.append("%s｜主路 %d 區：地圖 ¥%d（地上 %d、箱子 %d、敵人 %d、增援 %d）＋主線 ¥%d；探索 %d 區 ¥%d＋支線 ¥%d；付款 ¥%d；必要補給 ¥%d" % [
				c["title"], c["route"].size(), main["total"], main["piles"], main["crates"], main["enemies"], main["reinforcements"],
				c["quest_main"], c["areas"].size() - c["route"].size(), explore["total"], c["quest_side"], c["payments"], c["supplies"]])
		lines.append("    路線：%s" % " → ".join(c["route"].map(_short)))
	lines.append("不刷錢計畫（只走主路、只領主線、付款照最壞、每章死 %d 次）：" % EXPECTED_DEATHS)
	for p: Dictionary in ledger["plan"]:
		lines.append("  %s：入帳 ¥%d、付款 ¥%d、補給 ¥%d、死亡 ¥%d → 餘額 ¥%d，買得起：%s；另有支線與探索 ¥%d" % [
				p["id"], p["income"], p["payments"], p["supplies"], p["deaths"], p["spare"],
				"、".join(p["affordable"]) if not p["affordable"].is_empty() else "（無）", p["side_and_explore"]])
	var pawn := PackedStringArray()
	var costs := pawn_round_trip_costs()
	for id: String in costs:
		var item := ConsumableBag.find(StringName(id))
		pawn.append("%s 淨虧 ¥%d" % [item.display_name if item != null else id, costs[id]])
	lines.append("典當週轉（當了再贖回）：%s；週轉不算收入。" % "、".join(pawn))
	var groups := {}
	for item: Dictionary in ledger["growth"]:
		groups[item["category"]] = groups.get(item["category"], PackedStringArray()) + PackedStringArray(["%s ¥%d" % [item["name"], item["price"]]])
	for category in GROWTH_ORDER:
		lines.append("成長・%s：%s" % [category, "、".join(groups.get(category, PackedStringArray(["（無）"])))])
	for issue: String in ledger["issues"]:
		lines.append("問題：%s" % issue)
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# 內部
# ---------------------------------------------------------------------------

static func _empty_income() -> Dictionary:
	return {"piles": 0, "crates": 0, "enemies": 0, "reinforcements": 0, "total": 0}


static func _add_income(into: Dictionary, income: Dictionary) -> void:
	for key: String in into:
		into[key] = int(into[key]) + int(income.get(key, 0))


static func _short(path: String) -> String:
	return path.get_file().get_basename()


static func _read_json(path: String, issues: PackedStringArray) -> Dictionary:
	var json := JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		issues.append("%s：無法讀取。" % path)
		return {}
	return json.data


## 章節 id → 故事資料（只收有 quests 的新故事來源）。
static func _stories_by_chapter(paths: Array[String], issues: PackedStringArray) -> Dictionary:
	var result := {}
	for path in paths:
		var source := _read_json(path, issues)
		var id: Variant = source.get("chapter", {}).get("id") if source.get("chapter") is Dictionary else null
		if id is String and source.get("quests") is Array:
			result[id] = source
	return result


## 章節 id → 該章全部區域的路徑（依 LevelData.chapter）。
static func _levels_by_chapter() -> Dictionary:
	var result := {}
	for resource in ResourceCatalog.load_dir(LEVEL_DIR, LevelData, "CampaignLedger"):
		var data := resource as LevelData
		var id := String(data.chapter)
		if not result.has(id):
			result[id] = []
		(result[id] as Array).append(data.resource_path)
	return result


## 共用同一張地圖的區域視為同一個節點（以排序後第一個為代表）。
static func _layout_aliases(paths: Array) -> Dictionary:
	var by_layout := {}
	var sorted := paths.duplicate()
	sorted.sort()
	var alias := {}
	for path: String in sorted:
		var data := load(path) as LevelData
		var key := data.layout_path if data != null and not data.layout_path.is_empty() else path
		if not by_layout.has(key):
			by_layout[key] = path
		alias[path] = by_layout[key]
	return alias


## 入口：從其他章的 next_level 接進來的區域；第一章用 campaign 的新遊戲起點。
static func _entry(id: String, paths: Array, first_level: String, all_levels: Dictionary) -> String:
	if paths.has(first_level):
		return first_level
	for other: String in all_levels:
		if other == id:
			continue
		for path: String in all_levels[other]:
			var data := load(path) as LevelData
			if data != null and paths.has(data.next_level):
				return data.next_level
	return ""


## 章末：next_level 接到其他章的區域；最後一章沒有下一章，取最後一個主線步驟的地點。
static func _terminal(paths: Array, story: Dictionary) -> String:
	for path: String in paths:
		var data := load(path) as LevelData
		if data != null and not data.next_level.is_empty() and not paths.has(data.next_level):
			return path
	var last := ""
	for quest: Dictionary in _quests(story, "main"):
		for step: Variant in quest.get("steps", []):
			if step is Dictionary and step.get("location") is Dictionary:
				last = str(step["location"].get("level", last))
	return last


## 兩區之間的最短路（出入口與 next_level 都算，鎖住的門也算）。找不到回傳空陣列。
static func _shortest(index: QuestMapIndex, paths: Array, alias: Dictionary, from: String, to: String) -> Array:
	var start: String = alias.get(from, from)
	var goal: String = alias.get(to, to)
	if start == goal:
		return [start]
	var previous := {start: ""}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var node: String = queue.pop_front()
		for next in _neighbours(index, paths, alias, node):
			if previous.has(next):
				continue
			previous[next] = node
			if next == goal:
				var path := [goal]
				while previous[path[0]] != "":
					path.push_front(previous[path[0]])
				return path
			queue.append(next)
	return []


static func _neighbours(index: QuestMapIndex, paths: Array, alias: Dictionary, node: String) -> Array[String]:
	var result: Array[String] = []
	for path: String in paths:
		if alias.get(path, path) != node:
			continue
		for marker in index.edges(path):
			var target: String = (marker["resource"] as PortalData).target_level
			result.append(alias.get(target, target))
		var data := load(path) as LevelData
		if data != null and paths.has(data.next_level):
			result.append(alias.get(data.next_level, data.next_level))
	return result


static func _quests(story: Dictionary, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest: Variant in story.get("quests", []):
		if quest is Dictionary and (kind.is_empty() or str(quest.get("kind", "main")) == kind):
			result.append(quest)
	return result


## 依場景結果把每筆故事款項歸到任務：同一個場景寫入的旗標屬於哪個任務（完成旗標或步驟旗標），款項就屬於那個任務。
## 寫入的旗標不是任務旗標時，看場景的觸發條件；條件也不是任務旗標（例如逐位客人答完），再看哪個任務的完成場景以這些旗標為條件。
static func _quest_money(story: Dictionary, issues: PackedStringArray) -> Dictionary:
	var scenes: Dictionary = story.get("scenes", {}) if story.get("scenes") is Dictionary else {}
	var flag_quest := _flag_quests(story, scenes)
	var registered: Dictionary = story.get("transactions", {}) if story.get("transactions") is Dictionary else {}
	var seen := {}
	var main := 0
	var side := 0
	var payments := 0
	var by_quest := {}
	var transactions: Array[Dictionary] = []
	for scene_id: String in scenes:
		var effects := _scene_effects(scenes[scene_id])
		for tx_id: String in effects["transactions"]:
			if seen.has(tx_id):
				continue  # 同一筆款項在多個分支場景出現（例如兩種選擇都付同一筆），只入帳一次。
			seen[tx_id] = true
			var delta := _transaction_delta(registered, tx_id, issues)
			var quest: Dictionary = {}
			var conditions: Array[String] = []
			_collect_condition_flags(scenes[scene_id].get("when") if scenes[scene_id] is Dictionary else null, conditions)
			# 先看這個場景寫入的旗標，再看它的觸發條件（例如「制伏後、還沒拿帳本」）屬於哪個任務。
			for flag: String in effects["flags"] + conditions:
				if flag_quest.has(flag):
					quest = flag_quest[flag]
					break
			var kind := str(quest.get("kind", "main")) if not quest.is_empty() else "story"
			var quest_id := str(quest.get("id", ""))
			transactions.append({"id": tx_id, "delta": delta, "quest": quest_id, "kind": kind, "scene": scene_id})
			if not quest_id.is_empty():
				by_quest[quest_id] = by_quest.get(quest_id, []) + [delta]
			if delta < 0:
				payments += delta
			elif kind == "side":
				side += delta
			else:
				main += delta
	return {"main": main, "side": side, "payments": payments, "by_quest": by_quest, "transactions": transactions}


## 旗標 → 任務：任務的完成與步驟旗標；以及「設定任務旗標的場景」條件裡用到的旗標（前置步驟）。
static func _flag_quests(story: Dictionary, scenes: Dictionary) -> Dictionary:
	var result := {}
	for quest: Dictionary in _quests(story, ""):
		result[str(quest.get("complete_flag", ""))] = quest
		for step: Variant in quest.get("steps", []):
			if step is Dictionary:
				result[str(step.get("complete_flag", ""))] = quest
	var prerequisites := {}
	for scene_id: String in scenes:
		var effects := _scene_effects(scenes[scene_id])
		for flag: String in effects["flags"]:
			if result.has(flag):
				var conditions: Array[String] = []
				_collect_condition_flags(scenes[scene_id].get("when") if scenes[scene_id] is Dictionary else null, conditions)
				for condition in conditions:
					if not result.has(condition) and not prerequisites.has(condition):
						prerequisites[condition] = result[flag]
				break
	result.merge(prerequisites)
	return result


## 一個場景會寫入的旗標與款項（含分支裡的結果）。
static func _scene_effects(scene: Variant) -> Dictionary:
	var results: Array = []
	_collect_results(scene, results)
	var flags: Array[String] = []
	var paid: Array[String] = []
	for result: Variant in results:
		if not result is Dictionary:
			continue
		if result.get("kind") == "flag":
			flags.append(str(result.get("id", "")))
		elif result.get("kind") == "transaction":
			paid.append(str(result.get("id", "")))
	return {"flags": flags, "transactions": paid}


static func _collect_condition_flags(node: Variant, into: Array[String]) -> void:
	if node is Dictionary:
		if node.get("flag") is String:
			into.append(node["flag"])
		for key: Variant in node:
			_collect_condition_flags(node[key], into)
	elif node is Array:
		for item: Variant in node:
			_collect_condition_flags(item, into)


static func _collect_results(node: Variant, into: Array) -> void:
	if node is Dictionary:
		for key: Variant in node:
			if key == "results" and node[key] is Array:
				into.append_array(node[key])
			else:
				_collect_results(node[key], into)
	elif node is Array:
		for item: Variant in node:
			_collect_results(item, into)


static func _transaction_delta(registered: Dictionary, id: String, issues: PackedStringArray) -> int:
	var entry: Variant = registered.get(id)
	var path := str(entry.get("resource", "")) if entry is Dictionary else ""
	var data := load(path) as StoryTransactionData if not path.is_empty() and ResourceLoader.exists(path) else null
	if data == null:
		issues.append("款項 %s 沒有登記或讀不到資源（%s），以 0 計" % [id, path])
		return 0
	return data.credits_delta


static func _death_cap(paths: Array) -> int:
	var cap := 0
	for path: String in paths:
		var data := load(path) as LevelData
		if data != null:
			cap = maxi(cap, data.death_credit_cap)
	return cap


static func _death_ratio(paths: Array) -> float:
	var ratio := 0.0
	for path: String in paths:
		var data := load(path) as LevelData
		if data != null:
			ratio = maxf(ratio, data.death_credit_penalty)
	return ratio
