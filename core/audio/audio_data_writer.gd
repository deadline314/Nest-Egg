class_name AudioDataWriter
extends RefCounted
## 把實驗室調整後的數值寫回音訊資料檔（音效庫的 volume_db、音樂 cue 的音量與淡化秒數）：
## 寫之前重讀檔案、套用變更、驗證數值範圍；預覽只列差異不寫入；真的寫入前先備份成 `<檔名>.bak`，用暫存檔改名避免寫到一半損毀。
## changes 是 [{path: ["sounds","shot_pistol","volume_db"], value: -2.0}, ...]；路徑上不存在的字典會報錯，不會憑空建立。

const LIMITS := {"volume_db": Vector2(-40.0, 12.0), "fade_in": Vector2(0.0, 10.0), "fade_out": Vector2(0.0, 10.0)}


## 回傳 {errors: PackedStringArray, diff: PackedStringArray, backup: String}；dry_run 為 true 時不寫入。
static func apply(path: String, changes: Array, dry_run := false) -> Dictionary:
	var result := {"errors": PackedStringArray(), "diff": PackedStringArray(), "backup": ""}
	if not FileAccess.file_exists(path):
		result["errors"].append("找不到資料檔：%s" % path)
		return result
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		result["errors"].append("%s 格式錯誤（最上層要是字典），不會寫入" % path)
		return result
	for change: Dictionary in changes:
		var node: Variant = parsed
		var keys: Array = change["path"]
		for i in keys.size() - 1:
			node = (node as Dictionary).get(keys[i]) if typeof(node) == TYPE_DICTIONARY else null
		var leaf := str(keys[keys.size() - 1])
		if typeof(node) != TYPE_DICTIONARY:
			result["errors"].append("%s 沒有 %s" % [path, "／".join(PackedStringArray(keys.map(func(k: Variant) -> String: return str(k))))])
			continue
		var value: Variant = change["value"]
		if LIMITS.has(leaf):
			var limits: Vector2 = LIMITS[leaf]
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT or float(value) < limits.x or float(value) > limits.y:
				result["errors"].append("%s 的 %s 要在 %s 到 %s 之間（%s）" % ["／".join(PackedStringArray(keys.map(func(k: Variant) -> String: return str(k)))), leaf, limits.x, limits.y, value])
				continue
		var old: Variant = (node as Dictionary).get(leaf)
		if old != value:
			(node as Dictionary)[leaf] = value
			result["diff"].append("%s：%s → %s" % ["／".join(PackedStringArray(keys.map(func(k: Variant) -> String: return str(k)))), old, value])
	if not (result["errors"] as PackedStringArray).is_empty() or dry_run or (result["diff"] as PackedStringArray).is_empty():
		return result
	var backup := path + ".bak"
	var backup_file := FileAccess.open(backup, FileAccess.WRITE)
	if backup_file == null:
		result["errors"].append("無法建立備份：%s" % backup)
		return result
	backup_file.store_string(text)
	backup_file.close()
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		result["errors"].append("無法寫入：%s" % temp)
		return result
	file.store_string(JSON.stringify(parsed, " ", false) + "\n")
	file.close()
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if error != OK:
		result["errors"].append("無法更新 %s（錯誤 %d）" % [path, error])
		return result
	result["backup"] = backup
	return result
