class_name StoryItemText
extends RefCounted
## 劇情道具與文件的三語文字（ST-21）：中文原文在各道具的 .tres，日文與英文在 data/story_items/i18n.json。
## 介面一律透過 StoryItemData 的 title_text()／description_text()／body_text() 取字，依 Story.language 換語言。
## 缺譯時退回英文、再退回中文，並記錄道具 id、欄位與語言（同一處只記一次）；譯文檔壞掉時整份退回中文，不讓遊戲壞掉。

const PATH := "res://data/story_items/i18n.json"
const FIELDS: PackedStringArray = ["display_name", "description", "body"]

static var _table: Dictionary = {}
static var _loaded := false
static var _reported: Dictionary = {}


## 道具 item 的 field 在 language 下的文字；source 是中文原文（缺譯時的最後退路）。
static func lookup(item_id: StringName, field: String, source: String, language: String, required_marker := "") -> String:
	if source.is_empty() or language == StoryLocale.SOURCE_LANGUAGE or not StoryLocale.is_supported(language):
		return source
	var wanted := _entry(item_id, language, field, required_marker)
	if not wanted.is_empty():
		return wanted
	var fallback := _entry(item_id, StoryLocale.FALLBACK, field, required_marker) if language != StoryLocale.FALLBACK else ""
	var marker_hint := "，內文需有一個 %s" % required_marker if not required_marker.is_empty() else ""
	_report("%s/%s/%s" % [item_id, field, language], "[StoryItemText] %s 的 %s 沒有可用的 %s 譯文，%s%s（補在 %s）" % [
			item_id, field, language, "改用英文" if not fallback.is_empty() else "保留中文", marker_hint, PATH])
	return fallback if not fallback.is_empty() else source


## 缺譯清單（道具 id／欄位／語言）：原文存在，但譯文缺少文字或必要標記。
static func missing(items: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value: Variant in items:
		var item := value as StoryItemData
		if item == null:
			continue
		for field in FIELDS:
			if str(item.get(field)).is_empty():
				continue
			var marker := StoryItemData.RUN_RESTORATIONS_MARKER if field == "body" and item.show_run_restorations else ""
			for language in ["ja", "en"]:
				if _entry(item.id, language, field, marker).is_empty():
					result.append("%s/%s/%s" % [item.id, field, language])
	return result


## 重新讀譯文檔（測試用）。
static func reload() -> void:
	_loaded = false
	_table.clear()
	_reported.clear()


static func _entry(item_id: StringName, language: String, field: String, required_marker: String) -> String:
	_ensure_loaded()
	var item: Variant = _table.get(String(item_id))
	if not item is Dictionary:
		return ""
	var texts: Variant = (item as Dictionary).get(language)
	if not texts is Dictionary:
		return ""
	var text: Variant = (texts as Dictionary).get(field)
	if not text is String or (not required_marker.is_empty() and (text as String).count(required_marker) != 1):
		return ""
	return (text as String).strip_edges()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_warning("[StoryItemText] 找不到譯文檔 %s，道具文字一律用中文" % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_error("[StoryItemText] 譯文檔 %s 不是有效的 JSON 物件，道具文字一律用中文" % PATH)
		return
	_table = parsed


static func _report(key: String, message: String) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	push_warning(message)
