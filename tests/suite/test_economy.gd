class_name EconomySuite
extends TestSuite
## 第一章的貨幣與升級（NE-216）：典當與贖回（當價、利息、當票上限、失敗不白花錢、存檔還原與壞資料）、
## 老 K 的櫃台（買補給、典當、改裝三個分頁）、死亡扣款上限與不負債、老 K 對死亡的反應、
## 章節收入與必要花費的對帳（必要花費約為可得總額的六到八成）、跨章不刷錢帳本（NE-231）。

const PAWN_SHOP := "res://data/shops/ch1_pawn.tres"
const ARENA_MAP := "res://tests/fixtures/arena_map.json"
const FLOOR_Y := 20 * 16.0
const MIN_RATIO := 0.60
const MAX_RATIO := 0.80


func run() -> void:
	preload("res://tests/helpers/story_transaction_checks.gd").run(self)
	preload("res://tests/helpers/story_result_plan_checks.gd").run(self)
	preload("res://tests/helpers/campaign_ledger_checks.gd").run(self)
	_test_pawn_rules()
	_test_pawn_snapshot()
	_test_death_cap()
	_test_old_k_reacts_to_deaths()
	_test_income_matches_prices()
	await _test_counter_and_pages()
	Progression.reset_run()


func _med() -> ConsumableData:
	return ConsumableBag.find(&"med_injector")


func _cell() -> ConsumableData:
	return ConsumableBag.find(&"shield_cell")


# ---------------------------------------------------------------------------
# 典當與贖回
# ---------------------------------------------------------------------------

func _test_pawn_rules() -> void:
	Progression.reset_run()
	var med := _med()
	check(Progression.pawn_value(med) == med.price / 2 and Progression.pawn_value(med) > 0, "the pawn value is half the price (%d of %d)" % [Progression.pawn_value(med), med.price])
	check(Progression.redeem_cost(med) > Progression.pawn_value(med), "redeeming costs the loan plus interest (%d)" % Progression.redeem_cost(med))
	check(Progression.redeem_cost(med) == int(ceil(float(Progression.pawn_value(med)) * 1.2)), "the interest is twenty percent, rounded up")
	var gained := Progression.pawn(med)
	check(gained == Progression.pawn_value(med) and Progression.credits == gained and Progression.pawned_count(med.id) == 1, "pawning pays the loan and keeps one ticket")
	check(not Progression.redeem_block_reason(med).is_empty() and not Progression.redeem(med), "redeeming without enough credits is refused")
	check(Progression.credits == gained and Progression.pawned_count(med.id) == 1, "a refused redeem charges nothing and keeps the ticket")
	Progression.add_credits(100)
	var before := Progression.credits
	check(Progression.redeem(med) and Progression.credits == before - Progression.redeem_cost(med) and Progression.pawned_count(med.id) == 0, "redeeming pays the interest and returns the ticket")
	check(Progression.pawn_value(null) == 0 and not Progression.redeem(null) and Progression.pawn(null) == 0, "nothing in, nothing out")
	var free_item := ConsumableData.new()
	free_item.id = &"test_free_item"
	free_item.price = 0
	check(Progression.pawn_value(free_item) == 0 and not Progression.pawn_block_reason(free_item).is_empty(), "an item the shop does not sell cannot be pawned")
	# 當票有上限：週轉不是無限換錢。
	Progression.reset_run()
	for i in Progression.MAX_PAWNED:
		check(Progression.pawn(med) > 0, "ticket %d is accepted" % (i + 1))
	check(Progression.pawn(med) == 0 and Progression.total_pawned() == Progression.MAX_PAWNED, "the ticket limit is enforced")
	check(Progression.pawn_block_reason(med).contains("%d" % Progression.MAX_PAWNED), "the refusal names the limit")
	# 當了再贖不賺錢：每個來回都淨虧利息。
	Progression.reset_run()
	var start := 500
	Progression.add_credits(start)
	Progression.pawn(med)
	Progression.redeem(med)
	check(Progression.credits < start, "pawn and redeem loses the interest, never gains (%d)" % Progression.credits)


func _test_pawn_snapshot() -> void:
	Progression.reset_run()
	var med := _med()
	var cell := _cell()
	Progression.pawn(med)
	Progression.pawn(med)
	Progression.pawn(cell)
	var snapshot := Progression.snapshot()
	Progression.reset_run()
	check(Progression.total_pawned() == 0, "a new run has no tickets")
	Progression.restore(snapshot)
	check(Progression.pawned_count(med.id) == 2 and Progression.pawned_count(cell.id) == 1, "tickets come back with the checkpoint (the same snapshot as the credits)")
	# 舊存檔沒有這個欄位、或資料壞掉：安全預設，不崩潰。
	var old := snapshot.duplicate(true)
	old.erase("pawned")
	Progression.restore(old)
	check(Progression.total_pawned() == 0, "an old snapshot without tickets restores with none")
	var broken := snapshot.duplicate(true)
	broken["pawned"] = {"med_injector": -3, "test_no_such_item": 2, "shield_cell": "x", "bad": null}
	Progression.restore(broken)
	check(Progression.total_pawned() == 0, "bad ticket data is ignored")
	var greedy := snapshot.duplicate(true)
	greedy["pawned"] = {"med_injector": 50}
	Progression.restore(greedy)
	check(Progression.total_pawned() == Progression.MAX_PAWNED, "restored tickets never exceed the limit")
	Progression.restore({"pawned": "oops"})
	check(Progression.total_pawned() == 0, "a wrong-typed field is ignored")
	Progression.reset_run()


# ---------------------------------------------------------------------------
# 死亡扣款
# ---------------------------------------------------------------------------

func _test_death_cap() -> void:
	Progression.reset_run()
	Progression.add_credits(10000)
	check(Progression.lose_credits_fraction(0.05, 250) == 250 and Progression.credits == 9750, "a death takes five percent but never more than the cap")
	check(Progression.lose_credits_fraction(0.05, 0) == 487, "no cap means the plain fraction")
	Progression.reset_run()
	Progression.add_credits(100)
	check(Progression.lose_credits_fraction(0.05, 250) == 5 and Progression.credits == 95, "a small purse loses its five percent")
	check(Progression.lose_credits_fraction(5.0, 0) == 95 and Progression.credits == 0, "never more than what you carry")
	check(Progression.lose_credits_fraction(0.05, 250) == 0 and Progression.credits == 0, "no debt: nothing to lose, nothing lost")
	var chapter_levels := EconomyReport.ch1_paths()
	for path: String in chapter_levels:
		var data := load(path) as LevelData
		check(data != null and data.death_credit_cap > 0 and data.death_credit_penalty > 0.0, "%s sets a death penalty with a cap" % path)
	Progression.reset_run()


# ---------------------------------------------------------------------------
# 老 K
# ---------------------------------------------------------------------------

func _test_old_k_reacts_to_deaths() -> void:
	var old_k := load("res://data/npcs/ch1_old_k.tres") as NpcData
	check(old_k != null and old_k.validate().is_empty(), "Old K is valid data %s" % [old_k.validate() if old_k != null else "missing"])
	var seen_nothing := func(_id: StringName) -> bool: return false
	check(old_k.pick_talk(0, seen_nothing, 0) == 0, "the first visit is the dinner talk, whatever the death count")
	check(old_k.pick_talk(0, seen_nothing, 7) == 0, "even after many deaths the first conversation comes first")
	var calm := old_k.pick_talk(1, seen_nothing, 0)
	var after_one := old_k.pick_talk(1, seen_nothing, 1)
	var after_many := old_k.pick_talk(1, seen_nothing, 5)
	check(old_k.talks[calm].scene == &"ch1_t_oldk_2", "later visits without deaths use the calm line (%s)" % old_k.talks[calm].scene)
	check(old_k.talks[after_one].scene == &"ch1_t_oldk_d1", "after a death Old K reacts (%s)" % old_k.talks[after_one].scene)
	check(old_k.talks[after_many].scene == &"ch1_t_oldk_d4", "after several deaths he counts them (%s)" % old_k.talks[after_many].scene)
	for talk in old_k.talks:
		check(Story.has_scene(talk.scene), "Old K's talk exists: %s" % talk.scene)
	var bad := NpcTalk.new()
	bad.scene = &"x"
	bad.min_deaths = -1
	check(not bad.validate(&"test").is_empty(), "a negative death threshold is reported")


# ---------------------------------------------------------------------------
# 收入與價目
# ---------------------------------------------------------------------------

func _test_income_matches_prices() -> void:
	var income := EconomyReport.chapter_income(EconomyReport.ch1_paths())
	var prices := EconomyReport.price_list()
	check(int(income["total"]) > 0 and int(income["piles"]) > 0 and int(income["enemies"]) > 0, "the chapter pays out (%s)" % [income])
	var ratio := float(prices["required"]) / float(income["total"])
	check(ratio >= MIN_RATIO and ratio <= MAX_RATIO, "the required purchases cost %d%% of the chapter's income (want %d–%d%%): %s" % [
			int(round(ratio * 100.0)), int(MIN_RATIO * 100.0), int(MAX_RATIO * 100.0), EconomyReport.summary(EconomyReport.ch1_paths())])
	check(int(prices["upgrades"]) > 0 and int(prices["supplies"]) > 0, "the price list has upgrades and supplies")
	# 第一個錢來得夠早：街道第一場遭遇之前地上就有錢可撿（教學區的零錢與箱子）。
	var pawnshop := LevelBuilder.parse(load("res://data/levels/ch1_pawnshop.tres") as LevelData)
	var early := 0
	for spawn in pawnshop.spawns:
		var res: Resource = spawn["resource"]
		if res is CreditPileData:
			early += (res as CreditPileData).value
		elif res is BreakableData:
			early += (res as BreakableData).credit_drop
	check(early >= 30, "the first minutes already pay something (%d)" % early)
	for item in Progression.upgrade_catalog():
		check(item.validate().is_empty(), "upgrade data is valid: %s" % item.id)


# ---------------------------------------------------------------------------
# 櫃台：三個分頁
# ---------------------------------------------------------------------------

func _arena() -> Level:
	var data := LevelData.new()
	data.id = &"test_economy"
	data.layout_path = ARENA_MAP
	return await start_level(data)


func _test_counter_and_pages() -> void:
	Progression.reset_run()
	var shop := load(PAWN_SHOP) as ShopData
	check(shop != null and shop.validate().is_empty() and shop.pawn and shop.workbench and not shop.stock.is_empty(), "the counter sells, pawns and modifies")
	check(shop.prompt_text().contains("典當") and shop.prompt_text().contains("改裝"), "the prompt tells what the counter does")
	var generated := ShopData.new()
	generated.pawn = true
	generated.display_name = "測試櫃台"
	check(generated.prompt_text().contains("典當") and generated.validate().is_empty(), "a pawn-only counter is valid and gets a generated prompt")
	var level := await _arena()
	var player := level.player
	var screen := ShopScreen.new()
	screen.configure_shop(player, shop)
	runner.get_tree().root.add_child(screen)
	await frames(3)
	check(screen._pages.size() == 3 and screen._pages[0] is ShopPage and screen._pages[1] is PawnPage and screen._pages[2] is UpgradesPage, "the counter has shelf, pawn and workbench tabs")
	var pawn_page: PawnPage = screen._pages[1]
	var med := _med()
	var bag := player.consumables
	while bag.count(med.id) > 0:
		bag.take(med.id)
	check(pawn_page._build_entries().is_empty(), "with nothing to pawn and no tickets the page is empty")
	bag.add(med)
	var entries := pawn_page._build_entries()
	check(entries.size() == 1 and entries[0].title.contains("典當") and entries[0].action_enabled, "a carried item can be pawned")
	check(pawn_page._activate_entry(0), "pawning works")
	check(bag.count(med.id) == 0 and Progression.credits == Progression.pawn_value(med) and Progression.pawned_count(med.id) == 1, "the item leaves the bag and the credits arrive together")
	entries = pawn_page._build_entries()
	check(entries.size() == 1 and entries[0].title.contains("贖回") and not entries[0].action_enabled, "the ticket appears as a redeem entry, disabled while too poor")
	var credits := Progression.credits
	check(not pawn_page._activate_entry(0) and Progression.credits == credits and bag.count(med.id) == 0, "a refused redeem changes nothing")
	Progression.add_credits(200)
	while bag.count(med.id) < med.max_carry:
		bag.add(med)
	check(not pawn_page._activate_entry(0), "redeeming into a full bag is refused (no payment, no lost ticket)")
	check(Progression.pawned_count(med.id) == 1, "the ticket is still there after the refusal")
	bag.take(med.id)
	var before := Progression.credits
	check(pawn_page._activate_entry(0) and bag.count(med.id) == med.max_carry and Progression.credits == before - Progression.redeem_cost(med), "redeeming returns the item and charges the interest")
	check(Progression.total_pawned() == 0, "the ticket is gone after redeeming")
	check(not pawn_page._activate_entry(9) and not pawn_page._activate_entry(-1), "out-of-range actions are ignored")
	screen.queue_free()
	await end_level(level)
	Progression.reset_run()
