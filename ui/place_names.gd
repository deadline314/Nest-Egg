class_name PlaceNames
extends RefCounted
## 章節名與地名放在介面上的寫法（暫停畫面、主選單的接續存檔）。章節名只出現在這些整理內容的地方，不疊在遊戲畫面上。

const RESUME_COPY := {
	"zh": "從%s的%s繼續。",
	"ja": "%sの%sから再開します。",
	"en": "Continue from %s, %s.",
}
const RESUME_FALLBACK := {
	"zh": "恢復上次保存的整輪進度",
	"ja": "最後に保存した進行状況を再開",
	"en": "Restore your last campaign save.",
}


## 區域資料；路徑空白、找不到或不是區域時回傳 null（呼叫端退回不帶地名的寫法）。
static func level_data(path: String) -> LevelData:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as LevelData


## 「第一章　傘」：章節資訊找不到時回傳空字串。
static func chapter_title(data: LevelData) -> String:
	if data == null or data.chapter == &"":
		return ""
	return str(Story.chapter_info(data.chapter).get("title", ""))


## 地名（不含括號註記，例如「當舖（天亮）」只取「當舖」）。
static func place(data: LevelData, language: String) -> String:
	if data == null:
		return ""
	return LocationMarker.split_note(data.display_name_for(language).strip_edges())[0]


## 暫停畫面的進度第一行：「第一章　傘・港區街道」；缺哪一段就只顯示另一段。
static func progress_line(data: LevelData, language: String, fallback_title := "") -> String:
	var title := chapter_title(data)
	if title.is_empty():
		title = fallback_title
	var where := place(data, language)
	if title.is_empty() or where.is_empty():
		return title + where
	return "%s・%s" % [title, where]


## 主選單「繼續遊戲」的說明：一句話講會回到哪一章、哪個地點。
static func resume_line(path: String, language: String) -> String:
	var lang := language if RESUME_COPY.has(language) else "zh"
	var data := level_data(path)
	var title := chapter_title(data)
	var where := place(data, lang)
	if title.is_empty() or where.is_empty():
		return RESUME_FALLBACK[lang]
	var quoted := "「%s」" % title if lang != "en" else title
	var order := [where, title] if lang == "en" else [quoted, where]
	return RESUME_COPY[lang] % order
