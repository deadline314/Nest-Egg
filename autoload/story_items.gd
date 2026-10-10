extends Node
## 劇情道具服務：道具種類從 data/story_items/ 讀取（新增道具不需改程式），記錄本輪取得了哪些。
## 取得時機由道具資料決定（開局、劇情場景結束、擊敗頭目、程式呼叫），這裡只負責監聽並發放。
## 道具跟著「本輪」進度，不隨檢查點回溯：劇情場景不會重播，回溯會讓道具永久遺失；
## 因此重開關卡或從檢查點重生都保留，只有開始新的一輪才會重置。

## 取得新道具時發出（背包、提示用）。
signal acquired(item: StoryItemData)
## 原件交出時發出；取得史、持有與交付已全部同步，這裡不發報酬。
signal transferred(item: StoryItemData)

const DATA_DIR := "res://data/story_items"
const CUSTODY_VERSION := 1

var _catalog: Array[StoryItemData] = []
var _catalog_loaded := false
var _owned: Dictionary[StringName, bool] = {}
var _held: Dictionary[StringName, bool] = {}
var _transferred: Dictionary[StringName, bool] = {}
## 某一章的收集總數（文件與錄音）。
func collectible_total(chapter: StringName) -> int:
	var total := 0
	for item in catalog():
		if item.is_collectible() and item.chapter == chapter:
			total += 1
	return total


## 某一章已收集的數量。
func collected_count(chapter: StringName) -> int:
	var count := 0
	for item in catalog():
		if item.is_collectible() and item.chapter == chapter and _owned.has(item.id):
			count += 1
	return count


## 有收集品的章節 id（依目錄順序，不重複）。
func collectible_chapters() -> Array[StringName]:
	var result: Array[StringName] = []
	for item in catalog():
		if item.is_collectible() and not result.has(item.chapter):
			result.append(item.chapter)
	return result


## 所有章節合計的收集進度：[已收集, 總數]。
func overall_collection() -> Vector2i:
	var collected := 0
	var total := 0
	for chapter in collectible_chapters():
		collected += collected_count(chapter)
		total += collectible_total(chapter)
	return Vector2i(collected, total)


## 取得後還沒在背包看過的道具（背包標記 NEW 用）。
var _unseen: Dictionary[StringName, bool] = {}


func _ready() -> void:
	Story.scene_finished.connect(_on_scene_finished)
	EventBus.boss_defeated.connect(_on_boss_defeated)


## 所有劇情道具定義（依 order 排序）。讀取失敗的檔案記錄錯誤並略過。
func catalog() -> Array[StoryItemData]:
	if not _catalog_loaded:
		_catalog_loaded = true
		for res in ResourceCatalog.load_dir(DATA_DIR, StoryItemData, "StoryItems"):
			_catalog.append(res as StoryItemData)
	return _catalog


## 道具文字（說明與內文）的劇本品質檢查（規則見 StoryLint），回傳錯誤與警告。
func lint() -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	for item in catalog():
		var lines: Array = []
		for text in [item.display_name, item.description, item.body]:
			if not str(text).is_empty():
				lines.append({"speaker": "", "text": str(text), "kind": "label" if text == item.display_name else "text"})
		units.append({"id": "道具 %s" % item.id, "lines": lines})
	return StoryLint.check_chapter("道具文字", units, {})


func find(id: StringName) -> StoryItemData:
	for item in catalog():
		if item.id == id:
			return item
	return null


func owns(id: StringName) -> bool:
	return _owned.has(id)


## 目前仍持有原件；owns 保留本輪曾取得的資料目錄語義。
func holds(id: StringName) -> bool:
	return _held.has(id)


func was_transferred(id: StringName) -> bool:
	return _transferred.has(id)


## 只有已知且目前持有的原件可交付一次；失敗沒有任何效果。
func transfer(id: StringName) -> bool:
	var item := find(id)
	if item == null:
		push_warning("[StoryItems] transfer/%s 未知道具，交付未生效" % id)
		return false
	if not _owned.has(id) or not _held.has(id) or _transferred.has(id):
		return false
	_held.erase(id)
	_transferred[id] = true
	GameState.request_story_save()
	transferred.emit(item)
	return true


## 已取得的道具（依 order 排序）。
func owned_items() -> Array[StoryItemData]:
	var result: Array[StoryItemData] = []
	for item in catalog():
		if _owned.has(item.id):
			result.append(item)
	return result


## 取得後還沒在背包看過。
func is_new(id: StringName) -> bool:
	return _unseen.has(id)


func new_count() -> int:
	return _unseen.size()


## 玩家在背包看過這個道具，移除 NEW 標記。
func mark_seen(id: StringName) -> void:
	_unseen.erase(id)


## 首次取得道具。已取得史即拒絕，交出後也不重新發放。
func acquire(id: StringName, announce := true) -> bool:
	var item := find(id)
	if item == null:
		push_warning("[StoryItems] 找不到劇情道具：%s" % id)
		return false
	if _owned.has(id):
		return false
	_owned[id] = true
	_held[id] = true
	_unseen[id] = true
	GameState.request_story_save()
	acquired.emit(item)
	if announce:
		EventBus.toast_requested.emit(acquire_message(item))
	return true


## 取得道具時的提示文字（人物給的獎勵也沿用）。
func acquire_message(item: StoryItemData) -> String:
	if not item.is_collectible():
		return "取得 %s" % item.display_name
	var kind := "錄音" if item.category == StoryItemData.Category.RECORDING else "文件"
	return "取得%s：%s（本章 %d／%d）" % [kind, item.display_name, collected_count(item.chapter), collectible_total(item.chapter)]


## 開始新的一輪：清空，並發放開局就持有的道具（不跳提示）。
func reset_run() -> void:
	_owned.clear()
	_unseen.clear()
	_held.clear()
	_transferred.clear()
	_grant(StoryItemData.Trigger.RUN_START, &"", false)


func _on_scene_finished(scene_id: StringName) -> void:
	_grant(StoryItemData.Trigger.SCENE_FINISHED, scene_id)


func _on_boss_defeated() -> void:
	_grant(StoryItemData.Trigger.BOSS_DEFEATED)


func _grant(trigger: StoryItemData.Trigger, scene_id := &"", announce := true) -> void:
	for item in catalog():
		if item.trigger != trigger:
			continue
		if trigger == StoryItemData.Trigger.SCENE_FINISHED and item.trigger_scene != scene_id:
			continue
		acquire(item.id, announce)


func snapshot() -> Dictionary:
	return {"owned": _owned.keys(), "unseen": _unseen.keys(), "custody_version": CUSTODY_VERSION,
		"held": _held.keys(), "transferred": _transferred.keys()}


## 先驗完整快照；直接 restore 與整輪 prepare 共用同一個拒絕邊界。
func prepare_snapshot(raw: Variant, where := "story/items") -> Dictionary:
	# 直接 restore 也可能收外來資料：轉 StringName 或複製前先擋長字串、深度、循環與物件。
	var tree_errors := RunSaveCodec.validate_tree(raw)
	if not tree_errors.is_empty():
		return {"error": RunSaveCodec._diagnostic_path(where, tree_errors[0].trim_prefix("run/"))}
	if not raw is Dictionary:
		return {"error": "%s 必須是完整物品物件，保留原資料" % where}
	var legacy: bool = not raw.has("custody_version") and not raw.has("held") and not raw.has("transferred")
	if not legacy:
		var version: Variant = raw.get("custody_version")
		if not RunSaveCodec.valid_version(version):
			return {"error": "%s/custody_version 缺漏或損毀，保留原資料" % where}
		if version != CUSTODY_VERSION:
			return {"error": "%s/custody_version 不支援，原檔保留" % where, "unknown_version": true}
	var keys: Array[String] = ["owned", "unseen"]
	if not legacy:
		keys.append_array(["held", "transferred"])
	var sets: Dictionary = {}
	var result: Dictionary = {"custody_version": CUSTODY_VERSION}
	var limit := catalog().size()
	for key: String in keys:
		var values: Variant = raw.get(key)
		if not values is Array or values.size() > limit:
			return {"error": "%s/%s 必須是有界物品陣列（上限 %d），保留原資料" % [where, key, limit]}
		var ids: Dictionary[StringName, bool] = {}
		for i in values.size():
			var value: Variant = values[i]
			if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return {"error": "%s/%s/%d 必須是物品 id，保留原資料" % [where, key, i]}
			var id := StringName(value)
			if find(id) == null or ids.has(id):
				return {"error": "%s/%s/%d 未知或重複物品 id，保留原資料" % [where, key, i]}
			ids[id] = true
		sets[key] = ids
		result[key] = ids.keys()
	if legacy:
		sets["held"] = sets["owned"].duplicate()
		sets["transferred"] = {}
		result["held"] = result["owned"].duplicate()
		result["transferred"] = []
	for key: String in ["unseen", "held", "transferred"]:
		for id: StringName in sets[key]:
			if not sets["owned"].has(id):
				return {"error": "%s/%s/%s 不在取得史，保留原資料" % [where, key, id]}
	for id: StringName in sets["owned"]:
		if sets["held"].has(id) == sets["transferred"].has(id):
			return {"error": "%s/held/%s 必須且只能屬於 held 或 transferred，保留原資料" % [where, id]}
	return {"data": result}


func restore(raw: Variant, where := "story/items") -> bool:
	var prepared := prepare_snapshot(raw, where)
	if prepared.has("error"):
		push_warning("[StoryItems] %s；目前物品保持" % prepared["error"])
		return false
	var state: Dictionary = prepared["data"]
	# 驗證完成後才替換，沒有訊號或保存可觀察到半份狀態。
	_owned.clear()
	_unseen.clear()
	_held.clear()
	_transferred.clear()
	for id: StringName in state["owned"]:
		_owned[id] = true
	for id: StringName in state["unseen"]:
		_unseen[id] = true
	for id: StringName in state["held"]:
		_held[id] = true
	for id: StringName in state["transferred"]:
		_transferred[id] = true
	return true
