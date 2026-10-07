extends Node
## 劇情道具服務：道具種類從 data/story_items/ 讀取（新增道具不需改程式），記錄本輪取得了哪些。
## 取得時機由道具資料決定（開局、劇情場景結束、擊敗頭目、程式呼叫），這裡只負責監聽並發放。
## 道具跟著「本輪」進度，不隨檢查點回溯：劇情場景不會重播，回溯會讓道具永久遺失；
## 因此重開關卡或從檢查點重生都保留，只有開始新的一輪才會重置。

## 取得新道具時發出（背包、提示用）。
signal acquired(item: StoryItemData)

const DATA_DIR := "res://data/story_items"

var _catalog: Array[StoryItemData] = []
var _catalog_loaded := false
var _owned: Dictionary[StringName, bool] = {}
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
				lines.append({"speaker": "", "text": str(text)})
		units.append({"id": "道具 %s" % item.id, "lines": lines})
	return StoryLint.check_chapter("道具文字", units, {})


func find(id: StringName) -> StoryItemData:
	for item in catalog():
		if item.id == id:
			return item
	return null


func owns(id: StringName) -> bool:
	return _owned.has(id)


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


## 取得道具。announce = true 時跳出提示。未知或已持有的道具回傳 false。
func acquire(id: StringName, announce := true) -> bool:
	var item := find(id)
	if item == null:
		push_warning("[StoryItems] 找不到劇情道具：%s" % id)
		return false
	if _owned.has(id):
		return false
	_owned[id] = true
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
	return {"owned": _owned.keys(), "unseen": _unseen.keys()}


func restore(raw: Variant, where := "story/items") -> void:
	_owned.clear()
	_unseen.clear()
	if not raw is Dictionary:
		push_warning("[StoryItems] %s 損毀，退回空清單" % where)
		return
	for key in ["owned", "unseen"]:
		var values: Variant = raw.get(key, [])
		if not values is Array:
			push_warning("[StoryItems] %s/%s 不是清單，已略過" % [where, key])
			continue
		for value: Variant in values:
			var id := StringName(str(value))
			if find(id) == null:
				push_warning("[StoryItems] %s/%s/%s 未知道具，已略過" % [where, key, id])
				continue
			if key == "owned":
				_owned[id] = true
			elif _owned.has(id):
				_unseen[id] = true
