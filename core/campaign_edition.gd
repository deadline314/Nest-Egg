class_name CampaignEdition
extends RefCounted
## 累積章節版本的身分：這份程式收錄到哪一章、存檔放哪裡、能接續哪些版本的存檔。
## 章節順序與名稱來自 data/release/campaign.json，目前版本來自 data/release/edition.json；
## 新增章節只改資料。資料缺漏或損毀時記錄具體位置並退回開發版（收錄全部章節），不讓遊戲無法啟動。

const CAMPAIGN_PATH := "res://data/release/campaign.json"
const EDITION_PATH := "res://data/release/edition.json"
const RELEASE_PREFIX := "through-"
const SLOT_ROOT := "user://runs"
const SLOT_FILE := "slot-1.json"
const FALLBACK_DEVELOPMENT_ID := "demo-0.1"
const MAX_ID_LENGTH := 64
const DEFAULT_FIRST_LEVEL := "res://data/levels/ch1_prologue.tres"

## 存檔目錄與存檔 release 欄位使用的識別；開發版沿用舊的 demo-0.1，既有開發存檔不需搬移。
var id := FALLBACK_DEVELOPMENT_ID
## 收錄的最後一章；開發版為空字串（全部章節與不在正式順序內的舊示範關卡）。
var through: StringName = &""
var development := true
var order: Array[StringName] = []
var titles: Dictionary = {}
var development_id := FALLBACK_DEVELOPMENT_ID
## 新遊戲的第一個區域；所有累積版本相同。
var first_level := DEFAULT_FIRST_LEVEL
## 發行工具寫入的版本號（例如 2026.10.12-ch1-candidate）；開發版與沒寫的情況為空字串。只用來顯示與記錄，不影響存檔相容。
var version := ""
var issues := PackedStringArray()

static var _current: CampaignEdition


static func current() -> CampaignEdition:
	if _current == null:
		_current = load_from(CAMPAIGN_PATH, EDITION_PATH)
	return _current


## 測試與發行驗證用：換掉目前版本；傳 null 恢復成資料檔的版本。
static func override_current(edition: CampaignEdition) -> void:
	_current = edition


## report=false 只收進 issues 不印錯誤（驗證工具與測試自行核對 issues）。
static func load_from(campaign_path: String, edition_path: String, report := true) -> CampaignEdition:
	var edition := CampaignEdition.new()
	var campaign := _read_json(campaign_path, edition.issues)
	var chapters: Variant = campaign.get("chapters", [])
	if not chapters is Array:
		edition.issues.append("%s/chapters：必須是陣列，改用空的章節順序。" % campaign_path)
		chapters = []
	for i in chapters.size():
		var entry: Variant = chapters[i]
		var chapter_id: Variant = entry.get("id") if entry is Dictionary else null
		if not _valid_id(chapter_id) or edition.order.has(StringName(chapter_id)):
			edition.issues.append("%s/chapters[%d]/id：缺漏、格式不符或重複，已略過。" % [campaign_path, i])
			continue
		edition.order.append(StringName(chapter_id))
		var title: Variant = entry.get("title", chapter_id)
		edition.titles[StringName(chapter_id)] = title if title is String and not title.is_empty() else String(chapter_id)
	var dev_id: Variant = campaign.get("development_id", FALLBACK_DEVELOPMENT_ID)
	if _valid_id(dev_id) and not String(dev_id).begins_with(RELEASE_PREFIX):
		edition.development_id = dev_id
	elif campaign.has("development_id"):
		edition.issues.append("%s/development_id：格式不符，改用 %s。" % [campaign_path, FALLBACK_DEVELOPMENT_ID])
	edition.id = edition.development_id
	var first: Variant = campaign.get("first_level", DEFAULT_FIRST_LEVEL)
	if RunSaveCodec.resource(first, "level", "res://data/levels/") != null:
		edition.first_level = first
	else:
		edition.issues.append("%s/first_level：%s 不是有效關卡，改用 %s。" % [campaign_path, str(first).left(RunSaveCodec.MAX_DIAGNOSTIC_PATH), DEFAULT_FIRST_LEVEL])
	var config := _read_json(edition_path, edition.issues)
	var through_value: Variant = config.get("through", "")
	if through_value is String and not through_value.is_empty():
		if edition.order.has(StringName(through_value)):
			edition._set_through(StringName(through_value))
		else:
			edition.issues.append("%s/through：%s 不在正式章節順序內，改用開發版。" % [edition_path, through_value])
	elif not through_value is String:
		edition.issues.append("%s/through：必須是文字，改用開發版。" % edition_path)
	var version_value: Variant = config.get("version", "")
	if version_value is String and (version_value.is_empty() or _valid_id(version_value)):
		edition.version = version_value
	else:
		edition.issues.append("%s/version：格式不符，不顯示版本號。" % edition_path)
	for issue in edition.issues if report else PackedStringArray():
		push_error("[CampaignEdition] %s" % issue)
	return edition


## 依存檔記錄的 release 描述另一個版本（同一份章節順序）；無法辨識時回傳 null。
func describe(release: Variant) -> CampaignEdition:
	if not release is String or release.length() > MAX_ID_LENGTH:
		return null
	var other := CampaignEdition.new()
	other.order = order
	other.titles = titles
	other.development_id = development_id
	other.first_level = first_level
	if release == development_id:
		other.id = development_id
		return other
	if release.begins_with(RELEASE_PREFIX) and order.has(StringName(release.trim_prefix(RELEASE_PREFIX))):
		other._set_through(StringName(release.trim_prefix(RELEASE_PREFIX)))
		return other
	return null


## 收錄範圍的大小；開發版大於任何發行版。用來判斷「較舊／較新」。
func rank() -> int:
	return order.size() if development else order.find(through)


func includes_chapter(chapter: StringName) -> bool:
	var index := order.find(chapter)
	if index < 0:
		return development  # 舊示範與未列入正式順序的章節只在開發版可進入。
	return development or index <= order.find(through)


func includes_level(level: LevelData) -> bool:
	return level != null and includes_chapter(level.chapter)


## 這份程式能不能接續 other 版本寫的存檔：同版本或收錄範圍較小的舊版本。
func can_continue_from(other: CampaignEdition) -> bool:
	return other != null and (other.id == id or other.rank() <= rank())


func is_last_chapter(chapter: StringName) -> bool:
	return not development and chapter == through


func title() -> String:
	if development:
		return "開發版"
	var first: String = titles.get(order[0], String(order[0])) if not order.is_empty() else ""
	var last: String = titles.get(through, String(through))
	return last if first == last else "%s至%s" % [first, last]


## 這份程式實際收錄的範圍（發行檢查與乾淨目錄啟動用）：哪些章節與區域收錄、哪些區域是章末（下一區不在本版本，停在完成卡）、
## 有幾個出入口通往未收錄的章節（進入時只提示，不載入）。只讀關卡資料，不解析地圖、不建立節點。
func scope_report(level_dir := "res://data/levels") -> Dictionary:
	var chapters: Array[Dictionary] = []
	for chapter in order:
		chapters.append({"id": String(chapter), "title": chapter_title(chapter), "included": includes_chapter(chapter)})
	var included := {}
	var excluded := {}
	var endings: Array[String] = []
	var blocked_exits := 0
	for resource in ResourceCatalog.load_dir(level_dir, LevelData, "CampaignEdition"):
		var level := resource as LevelData
		var bucket := included if includes_level(level) else excluded
		bucket[String(level.chapter)] = int(bucket.get(String(level.chapter), 0)) + 1
		if bucket == excluded:
			continue
		var next := load(level.next_level) as LevelData if not level.next_level.is_empty() and ResourceLoader.exists(level.next_level) else null
		if next != null and not includes_level(next):
			endings.append(level.resource_path)
		for value: Resource in level.legend.values():
			var portal := value as PortalData
			if portal != null and not portal.target_level.is_empty() and ResourceLoader.exists(portal.target_level) and not includes_level(load(portal.target_level) as LevelData):
				blocked_exits += 1
	var first := load(first_level) as LevelData if ResourceLoader.exists(first_level) else null
	return {"id": id, "title": title(), "version": version, "through": String(through), "development": development, "chapters": chapters,
			"included_levels": included, "excluded_levels": excluded, "endings": endings, "blocked_exits": blocked_exits,
			"first_level": first_level, "first_level_included": includes_level(first), "slot": slot_path(), "issues": issues}


func chapter_title(chapter: StringName) -> String:
	return titles.get(chapter, String(chapter))


func slot_path() -> String:
	return SLOT_ROOT.path_join(id).path_join(SLOT_FILE)


func _set_through(chapter: StringName) -> void:
	through = chapter
	development = false
	id = RELEASE_PREFIX + String(chapter)


static func _valid_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= MAX_ID_LENGTH and value.is_valid_filename() and value == value.strip_edges()


static func _read_json(path: String, issues: PackedStringArray) -> Dictionary:
	if not FileAccess.file_exists(path):
		issues.append("%s：找不到檔案，使用預設值。" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		issues.append("%s：第%d行 %s，使用預設值。" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	var data: Dictionary = json.data
	if data.get("schema", 1) != 1:
		issues.append("%s/schema：不支援的格式，使用預設值。" % path)
		return {}
	return data
