extends Node
## 敗北圖鑑：每種死因解鎖一張卡片並附上攻略提示，
## 取代原作「死亡獎勵」的動機設計，同時降低重複死亡的挫折感。

const CARDS_PATH := "res://data/codex/defeat_cards.json"
const SAVE_PATH := "user://codex.cfg"
const SAVE_SECTION := "unlocked"
const FALLBACK_ID := &"unknown"
const CARD_FIELDS := ["title", "text", "hint"]

var _cards: Dictionary[StringName, Dictionary] = {}
var _order: Array[StringName] = []
var _unlocked: Dictionary[StringName, bool] = {}


func _ready() -> void:
	_load_cards()
	_load_progress()


func _load_cards() -> void:
	var json: JSON = load(CARDS_PATH) as JSON if ResourceLoader.exists(CARDS_PATH) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		push_error("[DefeatCodex] 無法讀取卡片資料：%s" % CARDS_PATH)
	else:
		var entries: Variant = (json.data as Dictionary).get("cards", [])
		if typeof(entries) == TYPE_ARRAY:
			for entry in entries:
				_register_card(entry)
	if not _cards.has(FALLBACK_ID):
		_register_card({
			"id": FALLBACK_ID,
			"title": "未知的敗因", "text": "連自己都不知道發生了什麼事。", "hint": "保持移動，注意預兆。",
			"title_en": "Unknown Cause", "text_en": "Even you aren't sure what happened.",
			"hint_en": "Keep moving and watch for attack tells.",
			"title_ja": "不明な敗因", "text_ja": "自分でも何が起きたのかわからない。",
			"hint_ja": "動き続け、攻撃の前兆に気を配る。",
		})


func _register_card(entry: Variant) -> void:
	if typeof(entry) != TYPE_DICTIONARY or not (entry as Dictionary).has("id"):
		push_warning("[DefeatCodex] 略過格式錯誤的卡片：%s" % str(entry))
		return
	var dict := entry as Dictionary
	var id := StringName(str(dict["id"]))
	if _cards.has(id):
		push_warning("[DefeatCodex] 卡片 id 重複：%s" % id)
		return
	var card := {
		"id": id,
		"title": str(dict.get("title", "???")),
		"text": str(dict.get("text", "")),
		"hint": str(dict.get("hint", "")),
	}
	var translations: Dictionary = {}
	for field: String in CARD_FIELDS:
		var values: Dictionary[String, String] = {}
		for language: String in StoryLocale.LANGUAGES:
			if language == StoryLocale.SOURCE_LANGUAGE:
				continue
			var value: Variant = dict.get("%s_%s" % [field, language])
			if value is String and not value.strip_edges().is_empty():
				values[language] = value
		if not values.is_empty():
			translations[field] = values
	card["translations"] = translations
	_cards[id] = card
	_order.append(id)


func _display_card(id: StringName, language: String) -> Dictionary:
	var definition := _cards[id]
	var result := {"id": id}
	var translations: Dictionary = definition["translations"]
	for field: String in CARD_FIELDS:
		var source: String = definition[field]
		result[field] = StoryLocale.optional_text(translations[field], language, source) if translations.has(field) else source
	return result


func _load_progress() -> void:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err == ERR_FILE_NOT_FOUND:
		return
	if err != OK:
		push_warning("[DefeatCodex] 圖鑑存檔讀取失敗（%s），將從空白開始。" % error_string(err))
		return
	if not config.has_section(SAVE_SECTION):
		return
	for key in config.get_section_keys(SAVE_SECTION):
		var id := StringName(key)
		if _cards.has(id):
			_unlocked[id] = true


## 實驗室讓玩家死亡時不能寫進玩家的圖鑑存檔：persist 關掉就只改記憶體。
var persist := true


## 目前已解鎖的卡片 id（實驗室離開時還原用）。
func unlocked_ids() -> Array:
	return _unlocked.keys()


func restore_unlocked(ids: Array) -> void:
	_unlocked.clear()
	for id: Variant in ids:
		_unlocked[StringName(str(id))] = true


func _save_progress() -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	for id: StringName in _unlocked.keys():
		config.set_value(SAVE_SECTION, String(id), true)
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("[DefeatCodex] 圖鑑存檔寫入失敗：%s" % error_string(err))


func has_card(id: StringName) -> bool:
	return _cards.has(id)


## 解鎖死因對應的卡片並回傳卡片內容（附 is_new 欄位）。
func unlock(cause: StringName, language := StoryLocale.SOURCE_LANGUAGE) -> Dictionary:
	var id := cause if _cards.has(cause) else FALLBACK_ID
	var is_new := not _unlocked.has(id)
	if is_new:
		_unlocked[id] = true
		_save_progress()
	EventBus.codex_card_unlocked.emit(id, is_new)
	var card := _display_card(id, language)
	card["is_new"] = is_new
	card["number"] = _order.find(id) + 1
	return card


## 依定義順序回傳所有卡片（附 unlocked 與 number 欄位）。
func get_all_cards(language := StoryLocale.SOURCE_LANGUAGE) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in _order.size():
		var card := _display_card(_order[i], language)
		card["unlocked"] = _unlocked.has(_order[i])
		card["number"] = i + 1
		result.append(card)
	return result


func unlocked_count() -> int:
	return _unlocked.size()


func total_count() -> int:
	return _order.size()
