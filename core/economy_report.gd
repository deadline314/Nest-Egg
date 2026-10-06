class_name EconomyReport
extends RefCounted
## 章節經濟對帳（NE-216，見 .claude/skills/continuity-qa 的貨幣與升級規則）：算出一個章節「可得的總金額」與「價目表」，
## 兩邊都來自資料（地圖、敵人、可破壞物、增援、補給與改裝的價格），改了任何一邊報表自動跟著變。
## 沒有算進去的：典當（週轉不是收入）、死亡扣款（單次有上限，不影響可得總額）、敵人掉落的隨機位置（金額固定）。

## 章節裡「必要」的補給：醫療針 2 支、護盾電池 1 個（打頭目前的最低準備）。
const REQUIRED_SUPPLIES: Dictionary = {&"med_injector": 2, &"shield_cell": 1}


## 第一章用到的區域（不含天亮的當舖，它和當舖共用同一張地圖，不重複算）。
static func ch1_paths() -> Array:
	var paths: Array = []
	for id in ["pawnshop", "rooftop", "street", "booth_alley", "warehouse", "vault", "lounge", "stall"]:
		paths.append("res://data/levels/ch1_%s.tres" % id)
	return paths


## 一個章節所有區域的收入：{ piles, crates, enemies, reinforcements, total }（信用點）。level_paths 是 LevelData 的 .tres 路徑。
static func chapter_income(level_paths: Array) -> Dictionary:
	var result := {"piles": 0, "crates": 0, "enemies": 0, "reinforcements": 0, "total": 0}
	for path: String in level_paths:
		var data := load(path) as LevelData
		if data == null:
			push_error("[EconomyReport] 讀不到區域：%s" % path)
			continue
		var layout := LevelBuilder.parse(data)
		for spawn in layout.spawns:
			var res: Resource = spawn["resource"]
			if res is CreditPileData:
				result["piles"] += (res as CreditPileData).value
			elif res is BreakableData:
				result["crates"] += (res as BreakableData).credit_drop
			elif res is EnemyData:
				result["enemies"] += (res as EnemyData).credit_value
			elif res is MechanismData and (res as MechanismData).kind == MechanismData.Kind.ENCOUNTER:
				for enemy in (res as MechanismData).reinforcements:
					if enemy != null:
						result["reinforcements"] += enemy.credit_value
		if layout.boss_spawn.has("resource") and layout.boss_spawn["resource"] is EnemyData:
			result["enemies"] += (layout.boss_spawn["resource"] as EnemyData).credit_value
	result["total"] = int(result["piles"]) + int(result["crates"]) + int(result["enemies"]) + int(result["reinforcements"])
	return result


## 價目表：{ upgrades（全部改裝合計）, supplies（必要補給合計）, required（兩者相加）, list（每項的名稱與價格，報表用） }。
static func price_list() -> Dictionary:
	var list: Array[String] = []
	var upgrades := 0
	for upgrade in Progression.upgrade_catalog():
		upgrades += upgrade.cost
		list.append("改裝・%s ¥%d" % [upgrade.display_name, upgrade.cost])
	var supplies := 0
	for id: StringName in REQUIRED_SUPPLIES:
		var item := ConsumableBag.find(id)
		if item == null:
			push_error("[EconomyReport] 找不到必要補給：%s" % id)
			continue
		supplies += item.price * int(REQUIRED_SUPPLIES[id])
		list.append("%s ×%d ¥%d" % [item.display_name, int(REQUIRED_SUPPLIES[id]), item.price * int(REQUIRED_SUPPLIES[id])])
	return {"upgrades": upgrades, "supplies": supplies, "required": upgrades + supplies, "list": list}


## 一段人看的對帳文字。
static func summary(level_paths: Array) -> String:
	var income := chapter_income(level_paths)
	var prices := price_list()
	var ratio := float(prices["required"]) / maxf(1.0, float(income["total"]))
	return "收入 ¥%d（地上 %d、箱子 %d、敵人 %d、增援 %d）／必要花費 ¥%d（%s）／比例 %d%%" % [
		income["total"], income["piles"], income["crates"], income["enemies"], income["reinforcements"],
		prices["required"], "、".join(prices["list"]), int(round(ratio * 100.0))]
