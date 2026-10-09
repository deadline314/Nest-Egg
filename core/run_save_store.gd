class_name RunSaveStore
extends RefCounted
## 主流程擁有的整輪存檔槽；測試顯式指定隔離路徑，沒有額外 autoload。

const DEFAULT_PATH := "user://runs/demo-0.1/slot-1.json"
var path: String
var issues := PackedStringArray()
var unknown_version := false
var validator: Callable
var overwrite_authorized := false


func _init(p_path := DEFAULT_PATH) -> void:
	path = p_path


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".newrun")


func read() -> Dictionary:
	issues.clear()
	unknown_version = false
	if FileAccess.file_exists(path + ".newrun"):
		var recovery := _recover_new_run()
		unknown_version = recovery.get("unknown_version", false)
		if recovery.has("data"):
			issues.append("%s：恢復已確認但被中斷的新輪存檔。" % path)
			return recovery["data"]
		_failure(path + ".newrun", recovery.get("error", "新輪交易無法恢復，原件保留"))
		return {}
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var result := _read_file(candidate)
		unknown_version = unknown_version or result.get("unknown_version", false)
		if result.has("data"):
			if candidate != path:
				issues.append("%s：主檔無效，使用完整備份續玩。" % path)
			return result["data"]
		issues.append("%s：%s" % [candidate, result.get("error", "讀取失敗")])
		if result.get("unknown_version", false):
			return {}  # 較新主檔不降級到舊備份並持續覆寫。
	return {}


func _read_file(candidate: String) -> Dictionary:
	var file := FileAccess.open(candidate, FileAccess.READ)
	if file == null:
		return {"error": "無法開啟（%s）" % FileAccess.get_open_error()}
	if file.get_length() > RunSaveCodec.MAX_BYTES:
		file.close()
		return {"error": "檔案超過4 MiB上限"}
	var text := file.get_as_text()
	file.close()
	var decoded := RunSaveCodec.decode(text)
	if decoded.has("data") and validator.is_valid():
		return validator.call(decoded["data"])
	return decoded


func write(data: Dictionary, confirmed_overwrite := false) -> bool:
	issues.clear()
	# 一次明確新遊戲授權保留到首次成功；IO失敗不要求重新確認。
	overwrite_authorized = overwrite_authorized or confirmed_overwrite
	if FileAccess.file_exists(path + ".newrun"):
		var recovery := _recover_new_run()
		if not recovery.get("installed", false):
			unknown_version = recovery.get("unknown_version", false)
			if not confirmed_overwrite:
				return _failure(path + ".newrun", recovery.get("error", "尚未完成新輪恢復，原件保留"))
			var marker_path := ProjectSettings.globalize_path(path + ".newrun")
			if FileAccess.file_exists(path + ".newrun.previous"):
				var removal := DirAccess.remove_absolute(marker_path + ".previous")
				if removal != OK:
					return _failure(path + ".newrun.previous", "無法保留舊交易標記（%s）" % removal)
			var archival := DirAccess.rename_absolute(marker_path, marker_path + ".previous")
			if archival != OK:
				return _failure(path + ".newrun", "無法保留舊交易標記（%s）" % archival)
	var primary := _read_file(path) if FileAccess.file_exists(path) else {}
	if primary.get("unknown_version", false):
		unknown_version = true
	elif not primary.has("data") and FileAccess.file_exists(path + ".bak") and _read_file(path + ".bak").get("unknown_version", false):
		unknown_version = true
	if unknown_version and not overwrite_authorized:
		return _failure(path, "未知版本保留；請明確選擇新遊戲覆寫")
	var encoded := RunSaveCodec.encode(data)
	if encoded.is_empty() or encoded.to_utf8_buffer().size() > RunSaveCodec.MAX_BYTES:
		return _failure(path, "整輪資料無效或超過大小上限，原檔保留")
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		return _failure(path, "無法建立存檔目錄（%s）" % error)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _failure(temp, "無法寫入（%s）" % FileAccess.get_open_error())
	file.store_string(encoded)
	file.flush()
	error = file.get_error()
	file.close()
	var verified := _read_file(temp)
	if error != OK or not verified.has("data"):
		return _failure(temp, "寫入或驗證失敗（%s），原檔保留" % verified.get("error", error))
	if overwrite_authorized:
		return _install_new_run(absolute)
	# 只有完整有效的舊主檔能輪替備份；損毀主檔不污染可恢復備份。
	var old_valid := FileAccess.file_exists(path) and _read_file(path).has("data")
	if old_valid:
		if FileAccess.file_exists(path + ".bak"):
			error = DirAccess.remove_absolute(absolute + ".bak")
			if error != OK:
				return _failure(path + ".bak", "無法輪替備份（%s），原檔保留" % error)
		error = DirAccess.rename_absolute(absolute, absolute + ".bak")
		if error != OK:
			return _failure(path, "無法建立備份（%s），原檔保留" % error)
	elif FileAccess.file_exists(path):
		# 保留損毀原件以供診斷；已驗證的暫存寫好後才移動。
		if FileAccess.file_exists(path + ".invalid"):
			DirAccess.remove_absolute(absolute + ".invalid")
		error = DirAccess.rename_absolute(absolute, absolute + ".invalid")
		if error != OK:
			return _failure(path, "無法保留損毀原件（%s）" % error)
	error = DirAccess.rename_absolute(absolute + ".tmp", absolute)
	if error != OK:
		if old_valid:
			var rollback := DirAccess.rename_absolute(absolute + ".bak", absolute)
			if rollback != OK:
				_failure(path + ".bak", "回滾至%s失敗（%s）；備份保留，未刪除" % [path, rollback])
		return _failure(path, "無法替換存檔（%s），原件與暫存保留供恢復" % error)
	unknown_version = false
	overwrite_authorized = false
	_resolve_new_run()
	return true


## 新輪的恢復備份也是新輪；上一輪另外保留，不成為續玩候選。
func _install_new_run(absolute: String) -> bool:
	var error := DirAccess.copy_absolute(absolute + ".tmp", absolute + ".freshbak")
	if error != OK or not _read_file(path + ".freshbak").has("data"):
		return _failure(path + ".freshbak", "無法建立新輪備份，原檔保留")
	if not _begin_new_run(absolute):
		return false
	var moved: Array[String] = []
	for suffix: String in ["", ".bak"]:
		if not FileAccess.file_exists(path + suffix):
			continue
		var archive := absolute + ".previous" + suffix
		if FileAccess.file_exists(archive):
			error = DirAccess.remove_absolute(archive)
			if error != OK:
				var restored := _rollback_new_run(absolute, moved)
				return _failure(path, "無法保留上一輪；%s" % ("原存檔已回復" if restored else "回滾失敗，上一輪原件另保留，請查看錯誤紀錄"))
		error = DirAccess.rename_absolute(absolute + suffix, archive)
		if error != OK:
			var restored := _rollback_new_run(absolute, moved)
			return _failure(path, "無法保留上一輪；%s" % ("原存檔已回復" if restored else "回滾失敗，上一輪原件另保留，請查看錯誤紀錄"))
		moved.append(suffix)
	error = DirAccess.rename_absolute(absolute + ".tmp", absolute)
	if error == OK:
		error = DirAccess.rename_absolute(absolute + ".freshbak", absolute + ".bak")
	if error != OK:
		if FileAccess.file_exists(path):
			var cleanup := DirAccess.remove_absolute(absolute)
			if cleanup != OK:
				_failure(path, "新輪替換失敗後無法移除未完成主檔（%s），上一輪仍保留在.previous" % cleanup)
		var restored := _rollback_new_run(absolute, moved)
		return _failure(path, "新輪替換失敗；%s" % ("原存檔已回復" if restored else "回滾失敗，上一輪原件另保留，請查看錯誤紀錄"))
	unknown_version = false
	overwrite_authorized = false
	_resolve_new_run()
	return true


func _rollback_new_run(absolute: String, moved: Array[String]) -> bool:
	var restored := true
	for suffix: String in moved:
		var error := DirAccess.rename_absolute(absolute + ".previous" + suffix, absolute + suffix)
		if error != OK:
			restored = false
			_failure(path + ".previous" + suffix, "回滾至%s失敗（%s）；原件保留，未刪除" % [path + suffix, error])
	if restored:
		restored = _resolve_new_run()
	return restored


## 標記只在freshbak已完整驗證後建立；校驗內容，不接受外來路徑。
func _begin_new_run(absolute: String) -> bool:
	if not _read_file(path + ".freshbak").has("data"):
		return _failure(path + ".freshbak", "新輪備份無效，未建立交易標記")
	var marker := FileAccess.open(path + ".newrun.tmp", FileAccess.WRITE)
	if marker == null:
		return _failure(path + ".newrun.tmp", "無法建立交易標記（%s）" % FileAccess.get_open_error())
	marker.store_string(JSON.stringify({"version": 1, "checksum": _file_checksum(path + ".freshbak")}))
	marker.flush()
	var error := marker.get_error()
	marker.close()
	if error == OK:
		error = DirAccess.rename_absolute(absolute + ".newrun.tmp", absolute + ".newrun")
	return true if error == OK else _failure(path + ".newrun", "無法安裝交易標記（%s），原存檔保留" % error)


func _resolve_new_run() -> bool:
	if not FileAccess.file_exists(path + ".newrun"):
		return true
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".newrun"))
	return true if error == OK else _failure(path + ".newrun", "無法解除交易標記（%s），完整來源仍保留" % error)


func _recover_new_run() -> Dictionary:
	var marker := FileAccess.open(path + ".newrun", FileAccess.READ)
	if marker == null or marker.get_length() > 256:
		return {"error": "交易標記無法讀取或超過上限"}
	var parsed: Variant = JSON.parse_string(marker.get_as_text())
	marker.close()
	if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("checksum") is String or parsed["checksum"].length() != 64 or not parsed["checksum"].is_valid_hex_number():
		return {"error": "交易標記損毀，不讀回上一輪"}
	# 有新輪標記也不能默默覆寫較新格式；先檢查兩個正式候選。
	for suffix: String in ["", ".bak"]:
		var existing := _read_file(path + suffix) if FileAccess.file_exists(path + suffix) else {}
		if existing.get("unknown_version", false):
			return {"error": "%s版本較新，新輪恢復未覆寫原件" % [path + suffix], "unknown_version": true}
	var checksum: String = parsed["checksum"]
	var candidate := ""
	var recovered: Dictionary = {}
	for suffix: String in [".freshbak", "", ".bak"]:
		var result := _read_file(path + suffix) if FileAccess.file_exists(path + suffix) else {}
		if result.get("unknown_version", false):
			return result
		if result.has("data") and _file_checksum(path + suffix) == checksum:
			candidate = path + suffix
			recovered = result["data"]
			break
	if candidate.is_empty():
		return {"error": "已確認新輪缺少校驗有效的完整備份，不讀回上一輪"}
	var absolute := ProjectSettings.globalize_path(path)
	if candidate != path + ".freshbak":
		var error := DirAccess.copy_absolute(ProjectSettings.globalize_path(candidate), absolute + ".freshbak")
		if error != OK:
			_failure(path + ".freshbak", "無法保留恢復來源（%s）" % error)
			return {"data": recovered, "installed": false}
	# 保留固定完整來源直到主檔和備份均安裝，每個中斷窗口都有同一新輪。
	for suffix: String in ["", ".bak"]:
		if _file_checksum(path + suffix) == checksum:
			continue
		var error := DirAccess.copy_absolute(absolute + ".freshbak", absolute + ".recover")
		if error == OK and (not _read_file(path + ".recover").has("data") or _file_checksum(path + ".recover") != checksum):
			error = ERR_FILE_CORRUPT
		if error == OK and FileAccess.file_exists(path + suffix):
			var archive := absolute + ".previous" + suffix
			if FileAccess.file_exists(path + ".previous" + suffix):
				error = DirAccess.remove_absolute(archive)
			if error == OK:
				error = DirAccess.rename_absolute(absolute + suffix, archive)
		if error == OK:
			error = DirAccess.rename_absolute(absolute + ".recover", absolute + suffix)
		if error != OK:
			_failure(path + suffix, "新輪恢復替換失敗（%s）；%s完整來源保留" % [error, path + ".freshbak"])
			return {"data": recovered, "installed": false}
	return {"data": recovered, "installed": _resolve_new_run()}


func _file_checksum(candidate: String) -> String:
	var file := FileAccess.open(candidate, FileAccess.READ)
	if file == null or file.get_length() > RunSaveCodec.MAX_BYTES:
		return ""
	var checksum := file.get_as_text().sha256_text()
	file.close()
	return checksum


func _failure(where: String, reason: String) -> bool:
	issues.append("%s：%s" % [where, reason])
	push_warning("[RunSave] %s" % issues[-1])
	return false
