class_name StoryLocale
extends RefCounted
## 劇本的三語欄位（ST-2）：中文寫在「text」等原欄位，日文與英文在同一個字典的 ja／en（text 以外的欄位 K 用 K_ja／K_en）。
## 產生器（tools/story/story_i18n.py）負責把對照表的譯文補進輸出；這裡在載入時換成玩家選的語言。
## 缺譯時退回英文，再退回中文，並記下具體檔案、路徑與缺的語言（不讓遊戲壞掉，也不默默吞掉）。

const LANGUAGES: PackedStringArray = ["zh", "ja", "en"]
const SOURCE_LANGUAGE := "zh"
## 退回順序：要的語言 → 英文 → 中文原文。
const FALLBACK := "en"
## 玩家看得到的欄位（和產生器的 VISIBLE_FIELDS 一致）。
const VISIBLE_FIELDS: PackedStringArray = ["text", "explanation", "title", "subtitle", "end_title", "teaser", "release_note",
		"end_card", "background", "reward", "blocked_reason", "suggestion", "prompt"]
## 不是玩家看的子樹（條件、旗標、舞台參數）。
const SKIP_KEYS: PackedStringArray = ["when", "set_flags", "results", "routes", "flag_defaults", "derived_flags", "transactions",
		"runtime_facts", "speakers", "stages"]
## 一份劇本最多列出幾個缺譯位置（其餘只算數量，避免記錄洗版）。
const MAX_REPORTED := 8


static func is_supported(language: String) -> bool:
	return LANGUAGES.has(language)


static func field_key(field: String, language: String) -> String:
	return language if field == "text" else "%s_%s" % [field, language]


## 把 data 裡玩家看得到的中文換成 language（原地修改，呼叫端先 duplicate）。回傳缺譯的位置（含退回了哪一種）。
static func localize(data: Variant, language: String) -> PackedStringArray:
	var missing := PackedStringArray()
	if language == SOURCE_LANGUAGE or not is_supported(language):
		return missing
	_localize_node(data, "", language, missing)
	if data is Dictionary:
		_localize_speakers(data, language, missing)
	return missing


## 宣告了三語的章節裡，還沒有 ja／en 的位置（不改資料）。
static func audit(data: Variant) -> PackedStringArray:
	var missing := PackedStringArray()
	_audit_node(data, "", missing)
	if data is Dictionary:
		for ident: Variant in (data as Dictionary).get("speakers", {}):
			var speaker: Variant = data["speakers"][ident]
			if speaker is Dictionary and str(speaker.get("name", "")) != "" and _is_source_text(str(speaker["name"])):
				for language in ["ja", "en"]:
					if str(speaker.get("name_" + language, "")).strip_edges().is_empty():
						missing.append("/speakers/%s/name（缺%s）" % [ident, "日文" if language == "ja" else "英文"])
	return missing


## 缺譯的紀錄：檔案、數量與前幾個位置。
static func report(source: String, missing: PackedStringArray, what: String) -> String:
	var shown := missing.slice(0, MAX_REPORTED)
	var more := missing.size() - shown.size()
	return "%s：%d 處%s%s%s" % [source, missing.size(), what, "：" + "；".join(shown), "（另 %d 處省略）" % more if more > 0 else ""]


## 講者名牌（speakers.<id>.name）：譯名在 name_ja／name_en，缺了一樣退回英文再退回中文。
static func _localize_speakers(data: Dictionary, language: String, missing: PackedStringArray) -> void:
	var speakers: Variant = data.get("speakers", {})
	if not speakers is Dictionary:
		return
	for ident: Variant in speakers:
		var speaker: Variant = speakers[ident]
		if not speaker is Dictionary or not _is_source_text(str(speaker.get("name", ""))):
			continue
		var wanted := str(speaker.get("name_" + language, ""))
		if wanted.strip_edges().is_empty():
			wanted = str(speaker.get("name_" + FALLBACK, "")) if language != FALLBACK else ""
			missing.append("/speakers/%s/name（%s%s）" % [ident, language, "，改用英文" if not wanted.is_empty() else "，保留中文"])
		if not wanted.strip_edges().is_empty():
			speaker["name"] = wanted


static func _localize_node(node: Variant, path: String, language: String, missing: PackedStringArray) -> void:
	if node is Dictionary:
		var dict := node as Dictionary
		for key: Variant in dict.keys():
			var name := str(key)
			if SKIP_KEYS.has(name):
				continue
			var value: Variant = dict[key]
			if VISIBLE_FIELDS.has(name) and value is String and _is_source_text(value):
				var wanted := str(dict.get(field_key(name, language), ""))
				if wanted.strip_edges().is_empty():
					var fallback := str(dict.get(field_key(name, FALLBACK), "")) if language != FALLBACK else ""
					missing.append("%s/%s（%s%s）" % [path, name, language, "，改用英文" if not fallback.is_empty() else "，保留中文"])
					wanted = fallback
				if not wanted.strip_edges().is_empty():
					dict[key] = wanted
			elif value is Dictionary or value is Array:
				_localize_node(value, "%s/%s" % [path, name], language, missing)
	elif node is Array:
		var list := node as Array
		for index in list.size():
			if list[index] is Dictionary or list[index] is Array:
				_localize_node(list[index], "%s/%d" % [path, index], language, missing)


static func _audit_node(node: Variant, path: String, missing: PackedStringArray) -> void:
	if node is Dictionary:
		var dict := node as Dictionary
		for key: Variant in dict.keys():
			var name := str(key)
			if SKIP_KEYS.has(name):
				continue
			var value: Variant = dict[key]
			if VISIBLE_FIELDS.has(name) and value is String and _is_source_text(value):
				for language in ["ja", "en"]:
					if str(dict.get(field_key(name, language), "")).strip_edges().is_empty():
						missing.append("%s/%s（缺%s）" % [path, name, "日文" if language == "ja" else "英文"])
			elif value is Dictionary or value is Array:
				_audit_node(value, "%s/%s" % [path, name], missing)
	elif node is Array:
		var list := node as Array
		for index in list.size():
			if list[index] is Dictionary or list[index] is Array:
				_audit_node(list[index], "%s/%d" % [path, index], missing)


## 有中日文字（中文原文）的欄位才需要譯文；純符號、數字或已是英文的欄位不算。
static func _is_source_text(text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 0x3400 and code <= 0x9fff:
			return true
	return false
