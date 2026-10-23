class_name RequiredItemRepair
extends RefCounted
## 存檔讀取時保住推進主線必需的故事物品（NE-230）。規則在 data/save/required_items.json：
## 旗標記得已取得、還沒交出，物品容器卻缺件 → 依旗標補回為持有並說明；旗標與物品互相矛盾 → 回報錯誤，
## 由呼叫端整份改用備份。只讀寫傳入的存檔資料，不碰目前遊戲狀態。

const RULES_PATH := "res://data/save/required_items.json"

static var _rules: Array[Dictionary] = []
static var _loaded := false


## items：StoryItems.prepare_snapshot 的結果（會就地補回）；flags：存檔的故事旗標。
## 回傳 {"notices": [...]} 或 {"error": "..."}。
static func apply(items: Dictionary, flags: Dictionary, where := "run/story/items") -> Dictionary:
	var notices: Array[String] = []
	for rule in rules():
		var id := StringName(rule["item"])
		var item := StoryItems.find(id)
		if item == null:
			continue  # 這件物品屬於尚未收錄的內容。
		var obtained: bool = flags.get(rule["obtained_flag"], false) == true
		var delivered: bool = rule["delivered_flag"] != "" and flags.get(rule["delivered_flag"], false) == true
		var held: bool = items["held"].has(id)
		var transferred: bool = items["transferred"].has(id)
		if delivered and held:
			return {"error": "%s/held/%s 與旗標 %s 矛盾（已交出卻仍持有）" % [where, id, rule["delivered_flag"]]}
		if obtained and not delivered and transferred:
			return {"error": "%s/transferred/%s 與旗標 %s 矛盾（已轉移卻沒有交出紀錄）" % [where, id, rule["delivered_flag"]]}
		if obtained and not delivered and not held:
			if not items["owned"].has(id):
				items["owned"].append(id)
			items["held"].append(id)
			push_warning("[RunSave] %s/held 缺少 %s，依旗標 %s 補回" % [where, id, rule["obtained_flag"]])
			notices.append("已依故事進度補回「%s」。" % item.title_text())
	return {"notices": notices}


static func rules() -> Array[Dictionary]:
	if not _loaded:
		_loaded = true
		_rules = load_rules(RULES_PATH)
	return _rules


## 規則檔損毀或缺欄位時記錄具體位置並略過該條，不讓讀檔失敗。
## report=false 時只略過不印錯誤（測試自行核對結果）。
static func load_rules(path: String, report := true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var json := JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("[RequiredItemRepair] %s 無法讀取，必要物品不會自動補回" % path)
		return result
	var entries: Variant = json.data.get("items", [])
	if not entries is Array:
		push_error("[RequiredItemRepair] %s/items 必須是陣列" % path)
		return result
	for i in entries.size():
		var entry: Variant = entries[i]
		var valid: bool = entry is Dictionary and entry.get("item") is String and entry.get("obtained_flag") is String \
			and entry.get("delivered_flag", "") is String and not entry["item"].is_empty() and not entry["obtained_flag"].is_empty()
		if not valid:
			if report:
				push_error("[RequiredItemRepair] %s/items[%d] 缺 item 或 obtained_flag，已略過" % [path, i])
			continue
		result.append({"item": entry["item"], "obtained_flag": entry["obtained_flag"], "delivered_flag": entry.get("delivered_flag", "")})
	return result
