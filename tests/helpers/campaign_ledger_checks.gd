extends RefCounted
## NE-231：跨章帳本（CampaignLedger）。既有 EconomySuite 負責註冊及執行。
## 守住的設計：不刷錢、不做支線也買得起每章頭目前的補給；每章都有可選的成長；
## 不刷錢買不完全部成長（選擇有意義）；任務獎勵文字和實際入帳一致；主線路線沿真實出入口連通。


static func run(suite: TestSuite) -> void:
	_test_mapping_rules(suite)
	var ledger := CampaignLedger.build()
	_test_routes(suite, ledger)
	_test_rewards_match_text(suite, ledger)
	_test_no_grind_plan(suite, ledger)
	_test_growth_catalog(suite, ledger)


## 款項歸屬規則：用小型故事資料驗證，不依賴正式章節的內容。
static func _test_mapping_rules(s: TestSuite) -> void:
	var soup := "res://data/story_transactions/ch2_sq1_soup.tres"  # +40
	var advance := "res://data/story_transactions/ch2_market_advance.tres"  # -40
	var story := {
		"chapter": {"id": "fixture"},
		"transactions": {"t.side": {"resource": soup}, "t.pay": {"resource": advance}, "t.prereq": {"resource": soup}},
		"quests": [
			{"id": "q_main", "kind": "main", "complete_flag": "main_done", "reward_en": "Nothing paid.", "steps": [{"complete_flag": "main_step"}]},
			{"id": "q_side", "kind": "side", "complete_flag": "side_done", "reward_en": "40 credits.", "steps": []},
			{"id": "q_book", "kind": "side", "complete_flag": "book_done", "reward_en": "40 credits.", "steps": []},
		],
		"scenes": {
			"pay": {"when": {"not": {"flag": "main_step", "equals": true}}, "results": [{"kind": "transaction", "id": "t.pay"}]},
			"side": {"results": [{"kind": "flag", "id": "side_done", "value": true}, {"kind": "transaction", "id": "t.side"}]},
			"side_again": {"results": [{"kind": "flag", "id": "side_done", "value": true}, {"kind": "transaction", "id": "t.side"}]},
			"guest": {"results": [{"kind": "flag", "id": "guest_answered", "value": true}, {"kind": "transaction", "id": "t.prereq"}]},
			"book": {"when": {"flag": "guest_answered", "equals": true}, "results": [{"kind": "flag", "id": "book_done", "value": true}]},
		},
	}
	var money := CampaignLedger._quest_money(story, PackedStringArray())
	var by_id := {}
	for tx: Dictionary in money["transactions"]:
		by_id[tx["id"]] = tx
	s.check(by_id.get("t.side", {}).get("quest") == "q_side" and int(money["side"]) == 80, "a payout in the scene that finishes a side quest is side income, counted once across branches (%s)" % [money])
	s.check(by_id.get("t.pay", {}).get("quest") == "q_main" and int(money["payments"]) == -40, "a payment is attributed through the scene's trigger condition (%s)" % [by_id.get("t.pay")])
	s.check(by_id.get("t.prereq", {}).get("quest") == "q_book", "a payout for a prerequisite flag belongs to the quest whose finishing scene needs it (%s)" % [by_id.get("t.prereq")])
	s.check(CampaignLedger.reward_mismatches(story).is_empty(), "matching reward texts raise nothing: %s" % [CampaignLedger.reward_mismatches(story)])
	story["quests"][1]["reward_en"] = "60 credits."
	var mismatches := CampaignLedger.reward_mismatches(story)
	s.check(mismatches.size() == 2 and mismatches[0].contains("q_side"), "a reward text that disagrees with the payout is reported with the quest id: %s" % [mismatches])
	var broken := {"transactions": {}, "quests": [], "scenes": {"x": {"results": [{"kind": "transaction", "id": "t.missing"}]}}}
	var issues := PackedStringArray()
	var fallback := CampaignLedger._quest_money(broken, issues)
	s.check(int(fallback["main"]) == 0 and issues.size() == 1 and issues[0].contains("t.missing"), "an unregistered payout counts as zero and names the id: %s" % [issues])


static func _test_routes(s: TestSuite, ledger: Dictionary) -> void:
	var chapters: Array = ledger["chapters"]
	s.check(chapters.size() >= 3, "the ledger covers every campaign chapter that has areas (%d)" % chapters.size())
	s.check(ledger["issues"].is_empty(), "the ledger has no broken routes or unregistered payouts: %s" % [ledger["issues"]])
	for c: Dictionary in chapters:
		var route: Array = c["route"]
		s.check(not c["entry"].is_empty() and not route.is_empty() and route[0] == c["entry"], "%s: the main route starts at the chapter entry (%s)" % [c["id"], c["entry"]])
		s.check(not c["terminal"].is_empty(), "%s: the chapter has an end area" % c["id"])
		var areas := 0
		for area: Dictionary in c["areas"]:
			areas += 1
			s.check(int(area["income"]["total"]) >= 0, "%s: %s pays a non-negative amount" % [c["id"], area["path"]])
		s.check(route.size() <= areas, "%s: the route only uses the chapter's own areas" % c["id"])


static func _test_rewards_match_text(s: TestSuite, ledger: Dictionary) -> void:
	for c: Dictionary in ledger["chapters"]:
		var story := _story(c["id"])
		s.check(not story.is_empty(), "%s: the story source is loaded" % c["id"])
		var mismatches := CampaignLedger.reward_mismatches(story)
		s.check(mismatches.is_empty(), "%s: every quest reward text matches its payouts: %s" % [c["id"], mismatches])


static func _test_no_grind_plan(s: TestSuite, ledger: Dictionary) -> void:
	var growth: Array[Dictionary] = []
	growth.assign(ledger["growth"])
	var total := 0
	for item in growth:
		total += int(item["price"])
	var plan: Array = ledger["plan"]
	for p: Dictionary in plan:
		s.check(int(p["short_before_supplies"]) == 0, "%s: main route and main quests alone pay for the pre-boss supplies (short by %d)" % [p["id"], p["short_before_supplies"]])
		s.check(int(p["spare"]) >= 0, "%s: deaths never push the no-grind wallet into debt (%d)" % [p["id"], p["spare"]])
		s.check(not p["affordable"].is_empty(), "%s: after supplies and deaths there is money for at least one growth choice (spare %d)" % [p["id"], p["spare"]])
	if not plan.is_empty():
		var first: Dictionary = plan[0]
		for category in [CampaignLedger.GROWTH_GUN, CampaignLedger.GROWTH_MELEE, CampaignLedger.GROWTH_DEFENSE]:
			s.check(first["affordable"].has(category), "after the first chapter any one %s growth is affordable, so trying it is not a gamble (spare %d, cheapest %d)" % [category, first["spare"], CampaignLedger.cheapest_in(growth, category)])
		var last: Dictionary = plan[plan.size() - 1]
		s.check(int(last["spare"]) < total, "without grinding the player cannot buy every growth for one weapon, so choices matter (spare %d of %d)" % [last["spare"], total])


static func _test_growth_catalog(s: TestSuite, ledger: Dictionary) -> void:
	var growth: Array = ledger["growth"]
	for category in [CampaignLedger.GROWTH_GUN, CampaignLedger.GROWTH_MELEE, CampaignLedger.GROWTH_DEFENSE]:
		s.check(growth.any(func(item: Dictionary) -> bool: return item["category"] == category), "the %s growth line has something to buy" % category)
	for item: Dictionary in growth:
		s.check(int(item["price"]) > 0 and not str(item["note"]).strip_edges().is_empty(), "%s has a price and a one-line effect shown before buying" % item["name"])
	var costs := CampaignLedger.pawn_round_trip_costs()
	for id: String in costs:
		s.check(int(costs[id]) > 0, "pawning and redeeming %s always loses money, so pawning is never income" % id)


static func _story(id: String) -> Dictionary:
	for path in Story.CHAPTER_PATHS:
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary and json.data.get("chapter") is Dictionary and json.data["chapter"].get("id") == id:
			return json.data
	return {}
