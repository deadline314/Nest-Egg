class_name AudioCatalog
extends RefCounted
## 素材目錄與位置登記的讀取介面（音效實驗室與測試用）：
##   assets_src/audio/catalog.json  素材編號 → 素材包、檔案、時長（不進遊戲匯出，開發機才有）
##   data/audio/slots.json          位置編號 → 名稱、用在哪裡、目前素材、備選素材
## 預聽檔 assets_src/audition/<編號>.ogg 由 tools/audio/build_candidates.py 產生；沒有就回傳 null，由呼叫端提示怎麼產生。

const CATALOG_PATH := "res://assets_src/audio/catalog.json"
const CLIPS_PATH := "res://assets_src/audio/clips.json"
const SLOTS_PATH := "res://data/audio/slots.json"
const AUDITION_DIR := "res://assets_src/audition/"
const ASSET_ID_PATTERN := "^[A-Z]{3}-\\d{4}$"
const SLOT_ID_PATTERN := "^P-[A-Z]+-\\d{3}$"

## 預聽檔資料夾；測試改指到自己的暫存資料夾，平行跑的測試才不會在共用資料夾裡互相看到對方補的假預聽檔。
var audition_dir := AUDITION_DIR
var assets: Dictionary = {}
var categories: Dictionary = {}
var slots: Array = []
var domains: Dictionary = {}
var _slot_index: Dictionary = {}
var _loaded := false


func load_all() -> bool:
	assets = {}
	categories = {}
	slots = []
	domains = {}
	_slot_index = {}
	var catalog := _read_json(CATALOG_PATH)
	if typeof(catalog.get("assets")) == TYPE_DICTIONARY:
		assets = catalog["assets"]
		categories = catalog.get("categories", {})
	var slot_root := AudioData.read_root(SLOTS_PATH, "AudioCatalog", PackedStringArray(), true)
	if typeof(slot_root.get("slots")) == TYPE_ARRAY:
		slots = slot_root["slots"]
		domains = slot_root.get("domains", {})
		# 依域的順序（武器、命中、角色…）再依編號排列，清單讀起來和位置清單文件一致。
		var order := domains.keys()
		slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var da := order.find(a["domain"])
			var db := order.find(b["domain"])
			return da < db if da != db else str(a["id"]) < str(b["id"]))
		for slot: Dictionary in slots:
			_slot_index[str(slot["id"])] = slot
	_loaded = not assets.is_empty() and not slots.is_empty()
	return _loaded


func is_loaded() -> bool:
	return _loaded


func slot(slot_id: String) -> Dictionary:
	return _slot_index.get(slot_id, {})


func slots_in(domain: String) -> Array:
	return slots.filter(func(s: Dictionary) -> bool: return domain.is_empty() or s["domain"] == domain)


func asset(asset_id: String) -> Dictionary:
	return assets.get(asset_id, {})


func ids_in(category: String) -> Array:
	var result: Array = []
	for id: String in assets.keys():
		if category.is_empty() or id.begins_with(category + "-"):
			result.append(id)
	result.sort()
	return result


## 依編號、素材包、檔名或說明搜尋（不分大小寫，空白分隔的每個詞都要符合）。
func search(query: String, category := "", limit := 200) -> Array:
	var words := query.to_lower().split(" ", false)
	var result: Array = []
	for id: String in ids_in(category):
		var a: Dictionary = assets[id]
		var haystack := ("%s %s %s %s" % [id, a["pack"], a["file"], a.get("desc", "")]).to_lower()
		var match_all := true
		for word in words:
			if not haystack.contains(word):
				match_all = false
				break
		if match_all:
			result.append(id)
			if result.size() >= limit:
				break
	return result


func preview_path(asset_id: String) -> String:
	return audition_dir + asset_id + ".ogg"


func has_preview(asset_id: String) -> bool:
	return FileAccess.file_exists(preview_path(asset_id))


## 把素材編號依有沒有預聽檔分開：{"shown": 有預聽檔的編號（保持原順序）, "hidden": 沒有預聽檔的個數}。
## 實驗室清單只列 shown，避免點了才發現沒有聲音。
func split_by_preview(ids: Array) -> Dictionary:
	var shown: Array = []
	var hidden := 0
	for id: String in ids:
		if has_preview(id):
			shown.append(id)
		else:
			hidden += 1
	return {"shown": shown, "hidden": hidden}


## 載入預聽檔；沒有或讀不了回傳 null（不會崩潰）。
func load_preview(asset_id: String) -> AudioStream:
	var path := preview_path(asset_id)
	if not FileAccess.file_exists(path):
		return null
	var stream := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	if stream == null:
		AudioData.report("preview:" + asset_id, "[AudioCatalog] 預聽檔無法載入：%s（重做：python tools/audio/build_candidates.py --force --only %s）" % [path, asset_id])
	return stream


## 片段清單（clips.json，clip_tool.py 維護）的資料檢查：編號唯一、都在素材目錄、起訖合理、原檔素材包存在。回傳錯誤訊息清單。
static func validate_clips(doc: Dictionary, asset_ids: Dictionary, pack_ids: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(doc.get("clips")) != TYPE_ARRAY:
		errors.append("%s 缺少 clips 陣列" % CLIPS_PATH)
		return errors
	var seen: Dictionary = {}
	var index := 0
	for clip: Variant in doc["clips"]:
		index += 1
		if typeof(clip) != TYPE_DICTIONARY:
			errors.append("%s 的第 %d 個片段不是物件" % [CLIPS_PATH, index])
			continue
		var id := str((clip as Dictionary).get("id", ""))
		var where := "%s 的片段 %s（第 %d 個）" % [CLIPS_PATH, id if not id.is_empty() else "?", index]
		if seen.has(id):
			errors.append("%s 的編號重複" % where)
		seen[id] = true
		if not asset_ids.has(id):
			errors.append("%s 不在素材目錄" % where)
		for key in ["parent", "parent_pack", "parent_file"]:
			if str((clip as Dictionary).get(key, "")).is_empty():
				errors.append("%s 缺少 %s" % [where, key])
		if str((clip as Dictionary).get("parent_pack", "")) != "" and not pack_ids.has(str((clip as Dictionary)["parent_pack"])):
			errors.append("%s 的原檔素材包「%s」不在來源目錄" % [where, (clip as Dictionary)["parent_pack"]])
		var start := float((clip as Dictionary).get("start", -1.0))
		var end := float((clip as Dictionary).get("end", -1.0))
		if start < 0.0 or end <= start:
			errors.append("%s 的起訖 %.3f–%.3f 秒不合理" % [where, start, end])
	return errors


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。
func validate(min_candidates := 1) -> PackedStringArray:
	var errors := PackedStringArray()
	var id_re := RegEx.create_from_string(ASSET_ID_PATTERN)
	var slot_re := RegEx.create_from_string(SLOT_ID_PATTERN)
	for id: String in assets.keys():
		if id_re.search(id) == null or not categories.has(id.split("-")[0]):
			errors.append("%s 的素材編號「%s」格式不對或類別未登記" % [CATALOG_PATH, id])
		var a: Variant = assets[id]
		if typeof(a) != TYPE_DICTIONARY or not (a as Dictionary).has("pack") or not (a as Dictionary).has("file"):
			errors.append("%s 的素材「%s」缺少 pack 或 file" % [CATALOG_PATH, id])
	var seen: Dictionary = {}
	for s: Dictionary in slots:
		var sid := str(s.get("id", ""))
		if slot_re.search(sid) == null or not domains.has(sid.split("-")[1]) or sid.split("-")[1] != str(s.get("domain", "")):
			errors.append("%s 的位置編號「%s」格式不對或域不符" % [SLOTS_PATH, sid])
		if seen.has(sid):
			errors.append("%s 的位置編號「%s」重複" % [SLOTS_PATH, sid])
		seen[sid] = true
		for key in ["current", "candidates"]:
			var ids: Array = s.get(key, [])
			var dup: Dictionary = {}
			for aid: String in ids:
				if not assets.has(aid):
					errors.append("%s 的位置「%s」的 %s 引用不存在的素材「%s」" % [SLOTS_PATH, sid, key, aid])
				if dup.has(aid):
					errors.append("%s 的位置「%s」的 %s 有重複的素材「%s」" % [SLOTS_PATH, sid, key, aid])
				dup[aid] = true
		for aid: String in s.get("current", []):
			if not (s.get("candidates", []) as Array).has(aid):
				errors.append("%s 的位置「%s」目前用的素材「%s」不在備選裡" % [SLOTS_PATH, sid, aid])
		if (s.get("candidates", []) as Array).size() < min_candidates:
			errors.append("%s 的位置「%s」備選少於 %d 個（%d）" % [SLOTS_PATH, sid, min_candidates, (s.get("candidates", []) as Array).size()])
	return errors


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		AudioData.report("catalog:" + path, "[AudioCatalog] 找不到 %s（素材目錄只在開發機上：python tools/audio/build_catalog.py）" % path, false)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		AudioData.report("catalog_format:" + path, "[AudioCatalog] %s 格式錯誤（最上層要是字典）" % path)
		return {}
	return parsed
