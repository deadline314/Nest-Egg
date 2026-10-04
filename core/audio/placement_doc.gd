class_name PlacementDoc
extends RefCounted
## 位置清單文件（design/16-audio/PLACEMENTS.md）的讀寫：音效實驗室與這份 md 雙向連動用。
## 文件是 markdown 表格，每個位置一列（`| P-WPN-001 | 名稱 | 說明 | 目前素材 | 預計使用 | 手動放入 | 備選 |`）。
## 寫回時只改那一格（預計使用、手動放入），其餘文字原樣保留；寫之前先重讀檔案，所以外部編輯器同時改了別的地方不會被蓋掉。
## has_changed_on_disk() 比對檔案修改時間，實驗室每秒問一次，被外部改過就重新載入。

const PATH := "res://design/16-audio/PLACEMENTS.md"
const COL_CURRENT := 3
const COL_PLANNED := 4
const COL_MANUAL := 5
const SLOT_PATTERN := "^\\|\\s*(P-[A-Z]+-\\d{3})\\s*\\|"
const ASSET_PATTERN := "[A-Z]{3}-\\d{4}"

var path := PATH
var _lines := PackedStringArray()
var _rows: Dictionary = {}  # 位置編號 -> 該列在 _lines 的索引
var _mtime := 0
var _slot_re := RegEx.create_from_string(SLOT_PATTERN)
var _asset_re := RegEx.create_from_string(ASSET_PATTERN)


func load_doc(p_path := PATH) -> bool:
	path = p_path
	return _reload()


func _reload() -> bool:
	_lines = PackedStringArray()
	_rows = {}
	if not FileAccess.file_exists(path):
		AudioData.report("placement:" + path, "[PlacementDoc] 找不到位置清單文件：%s（先執行 tools/audio/build_slots.py）" % path)
		return false
	_mtime = FileAccess.get_modified_time(path)
	var text := FileAccess.get_file_as_string(path)
	_lines = text.split("\n")
	for i in _lines.size():
		var match := _slot_re.search(_lines[i])
		if match != null:
			if _rows.has(match.get_string(1)):
				AudioData.report("placement_dup:" + match.get_string(1), "[PlacementDoc] %s 的位置「%s」出現不只一次（第 %d 列），以第一列為準" % [path, match.get_string(1), i + 1])
			else:
				_rows[match.get_string(1)] = i
	return true


func slot_ids() -> Array:
	return _rows.keys()


func has_slot(slot_id: String) -> bool:
	return _rows.has(slot_id)


func cells(slot_id: String) -> PackedStringArray:
	if not _rows.has(slot_id):
		return PackedStringArray()
	return _split(_lines[_rows[slot_id]])


## 預計使用的素材編號清單（沒填 = 空）。
func planned(slot_id: String) -> PackedStringArray:
	var result := PackedStringArray()
	var row := cells(slot_id)
	if row.size() > COL_PLANNED:
		for match in _asset_re.search_all(row[COL_PLANNED]):
			result.append(match.get_string())
	return result


## 預計使用欄的原始文字（含看不出編號的內容，檢查用）。
func planned_text(slot_id: String) -> String:
	var row := cells(slot_id)
	return row[COL_PLANNED] if row.size() > COL_PLANNED else ""


func is_manual(slot_id: String) -> bool:
	var row := cells(slot_id)
	return row.size() > COL_MANUAL and row[COL_MANUAL].to_lower().begins_with("[x")


func current(slot_id: String) -> PackedStringArray:
	var result := PackedStringArray()
	var row := cells(slot_id)
	if row.size() > COL_CURRENT:
		for match in _asset_re.search_all(row[COL_CURRENT]):
			result.append(match.get_string())
	return result


func set_planned(slot_id: String, ids: PackedStringArray) -> bool:
	return _write_cell(slot_id, COL_PLANNED, "、".join(ids))


func set_manual(slot_id: String, on: bool) -> bool:
	return _write_cell(slot_id, COL_MANUAL, "[x]" if on else "[ ]")


## 檔案在上次讀取之後被改過（外部編輯器、其他工具）。
func has_changed_on_disk() -> bool:
	return FileAccess.file_exists(path) and FileAccess.get_modified_time(path) != _mtime


## 外部改過就重新載入；回傳是否重新載入了。
func reload_if_changed() -> bool:
	if has_changed_on_disk():
		_reload()
		return true
	return false


## 資料檢查：回傳錯誤訊息清單。asset_ids 是素材目錄的全部編號，slot_ids 是位置登記的全部編號。
func validate(asset_ids: Dictionary, registered_slots: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for id: String in registered_slots:
		if not _rows.has(id):
			errors.append("%s 缺少位置「%s」" % [path, id])
	for id: String in _rows.keys():
		if not registered_slots.has(id):
			errors.append("%s 有位置登記裡沒有的位置「%s」" % [path, id])
		var text := planned_text(id).strip_edges()
		if not text.is_empty() and planned(id).is_empty():
			errors.append("%s 的「%s」預計使用「%s」看不出素材編號" % [path, id, text])
		for asset in planned(id):
			if not asset_ids.has(asset):
				errors.append("%s 的「%s」預計使用不存在的素材「%s」" % [path, id, asset])
		for asset in current(id):
			if not asset_ids.has(asset):
				errors.append("%s 的「%s」目前素材不存在：「%s」" % [path, id, asset])
	return errors


func _write_cell(slot_id: String, column: int, value: String) -> bool:
	reload_if_changed()
	if not _rows.has(slot_id):
		AudioData.report("placement_slot:" + slot_id, "[PlacementDoc] %s 沒有位置「%s」，無法寫入" % [path, slot_id])
		return false
	var line_index: int = _rows[slot_id]
	var row := _split(_lines[line_index])
	if row.size() <= column:
		AudioData.report("placement_cols:" + slot_id, "[PlacementDoc] %s 的位置「%s」欄位不足（%d 欄），無法寫入" % [path, slot_id, row.size()])
		return false
	row[column] = value.replace("|", "／")
	_lines[line_index] = "| " + " | ".join(row) + " |"
	return _save()


static func _split(line: String) -> PackedStringArray:
	var parts := line.strip_edges().trim_prefix("|").trim_suffix("|").split("|")
	var result := PackedStringArray()
	for part in parts:
		result.append(part.strip_edges())
	return result


## 先寫暫存檔再改名，寫到一半被中斷也不會留下半份文件。
func _save() -> bool:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		AudioData.report("placement_save:" + path, "[PlacementDoc] 無法寫入位置清單文件：%s（錯誤 %d）" % [temp, FileAccess.get_open_error()])
		return false
	file.store_string("\n".join(_lines))
	file.close()
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if error != OK:
		AudioData.report("placement_rename:" + path, "[PlacementDoc] 無法更新位置清單文件：%s（錯誤 %d）" % [path, error])
		return false
	_mtime = FileAccess.get_modified_time(path)
	return true
