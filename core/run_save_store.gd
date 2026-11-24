class_name RunSaveStore
extends RefCounted
## 主流程擁有的整輪存檔槽；測試顯式指定隔離路徑，沒有額外 autoload。

## 開發版的槽；實際預設槽依目前累積版本（CampaignEdition.slot_path），各版本各自一個目錄。
const DEFAULT_PATH := "user://runs/demo-0.1/slot-1.json"
const MAX_EDITION_DIRS := 32

enum ReadRecovery { NONE, BACKUP, NEW_RUN }
enum WriteStatus { SAVED, FAILED, CANCELLED }

class WritePlan extends RefCounted:
	var primary: Dictionary
	var absolute: String
	var temporary: String

var _write_generation := 0
var _deferred_draft := ""
var path: String
var issues := PackedStringArray()
var unknown_version := false
var read_recovery := ReadRecovery.NONE
var required_edition: CampaignEdition
var validator: Callable
var overwrite_authorized := false


func _init(p_path := "") -> void:
	path = p_path if not p_path.is_empty() else CampaignEdition.current().slot_path()


## 本槽沒有存檔時，找同一個存檔根目錄下其他累積版本的槽。只讀：
## 舊版本（收錄範圍較小）的有效存檔回傳 data／edition／path，之後由呼叫端寫進本槽；
## 較新版本的存檔只回報 newer，不讀進本版本。正在恢復新輪交易的槽不碰，以免改到別的版本的檔案。
func find_other_editions(edition: CampaignEdition) -> Dictionary:
	var result: Dictionary = {}
	var own := path.get_base_dir()
	var root := own.get_base_dir()
	var dir := DirAccess.open(root)
	if dir == null:
		return result
	var best_rank := -1
	var best_time := ""
	var names := dir.get_directories()
	for i in mini(names.size(), MAX_EDITION_DIRS):
		var name := names[i]
		if root.path_join(name) == own:
			continue
		var other := edition.describe(name)
		if other == null:
			continue
		var candidate := RunSaveStore.new(root.path_join(name).path_join(path.get_file()))
		candidate.validator = validator
		if not candidate.exists():
			continue
		if not edition.can_continue_from(other):
			if not result.has("newer") or other.rank() > (result["newer"] as CampaignEdition).rank():
				result["newer"] = other
			continue
		if FileAccess.file_exists(candidate.path + ".newrun"):
			push_warning("[RunSave] %s：新輪交易未完成，請先用「%s」開啟一次；不從本版本修改。" % [candidate.path, other.title()])
			continue
		var data := candidate.read()
		if data.is_empty():
			for issue in candidate.issues:
				push_warning("[RunSave] 其他版本存檔無法接續：%s" % issue)
			continue
		var saved_at: String = data.get("saved_at", "") if data.get("saved_at", "") is String else ""
		if other.rank() > best_rank or (other.rank() == best_rank and saved_at > best_time):
			best_rank = other.rank()
			best_time = saved_at
			result["data"] = data
			result["edition"] = other
			result["path"] = candidate.path
	return result


## 最近一個問題的原因（去掉檔案路徑），給主選單一句話說明；完整路徑留在 log。
func player_issue() -> String:
	if issues.is_empty():
		return ""
	var parts := issues[-1].split("：", true, 1)
	return (parts[1] if parts.size() == 2 else parts[0]).left(40)


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".newrun")


func read() -> Dictionary:
	issues.clear()
	unknown_version = false
	read_recovery = ReadRecovery.NONE
	required_edition = null
	if FileAccess.file_exists(path + ".newrun"):
		var recovery := _recover_new_run()
		unknown_version = recovery.get("unknown_version", false)
		required_edition = recovery.get("required_edition") as CampaignEdition
		if recovery.has("data"):
			read_recovery = ReadRecovery.NEW_RUN
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
				read_recovery = ReadRecovery.BACKUP
				issues.append("%s：主檔無效，使用完整備份續玩。" % path)
			return result["data"]
		issues.append("%s：%s" % [candidate, result.get("error", "讀取失敗")])
		if result.get("unknown_version", false):
			required_edition = result.get("required_edition") as CampaignEdition
			return {}  # 較新主檔不降級到舊備份並持續覆寫。
	return {}


func _read_file(candidate: String, fingerprint := false) -> Dictionary:
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
		decoded = validator.call(decoded["data"])
	if fingerprint:
		decoded["content_checksum"] = text.sha256_text()
	return decoded


func write(data: Dictionary, confirmed_overwrite := false) -> bool:
	cancel_deferred_write()
	var plan := _begin_write(confirmed_overwrite, path + ".tmp")
	if plan == null:
		return false
	var encoded := _encode_write(data)
	return not encoded.is_empty() and _write_draft(plan, encoded) and _verify_and_promote(plan)


## Gameplay autosaves yield between CPU/file phases. A critical write can discard
## the unpublished draft and commit immediately using the same write operations.
func write_in_frames(data: Dictionary, tree: SceneTree, may_write := Callable()) -> WriteStatus:
	if overwrite_authorized or FileAccess.file_exists(path + ".newrun"):
		return WriteStatus.SAVED if write(data) else WriteStatus.FAILED
	cancel_deferred_write()
	issues.clear()
	var encoded := _encode_write(data)
	if encoded.is_empty():
		return WriteStatus.FAILED
	var generation := _write_generation
	var slot := path
	await tree.process_frame
	if not _still_writing(generation, slot, may_write):
		return WriteStatus.CANCELLED
	_deferred_draft = "%s.autosave-%d-%d.tmp" % [path, OS.get_process_id(), get_instance_id()]
	var plan := _begin_write(false, _deferred_draft)
	if plan == null:
		return WriteStatus.FAILED
	await tree.process_frame
	if not _still_writing(generation, slot, may_write):
		return WriteStatus.CANCELLED
	if not _write_draft(plan, encoded):
		return WriteStatus.FAILED
	await tree.process_frame
	if not _still_writing(generation, slot, may_write):
		return WriteStatus.CANCELLED
	if not _verify_and_promote(plan):
		return WriteStatus.FAILED
	_deferred_draft = ""
	return WriteStatus.SAVED


func cancel_deferred_write() -> void:
	_write_generation += 1
	if not _deferred_draft.is_empty() and FileAccess.file_exists(_deferred_draft):
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(_deferred_draft))
		if error != OK:
			push_warning("[RunSave] 無法移除已取消的自動存檔 %s（%s）。" % [_deferred_draft, error])
	_deferred_draft = ""


func _still_writing(generation: int, slot: String, may_write: Callable) -> bool:
	if generation != _write_generation:
		return false
	if path == slot and (may_write.is_null() or (may_write.is_valid() and may_write.call())):
		return true
	cancel_deferred_write()
	return false


func _begin_write(confirmed_overwrite: bool, temporary: String) -> WritePlan:
	issues.clear()
	# The durable transaction still owns the slot's canonical draft path. An obstruction
	# there also blocks routine writes, even though each autosave has a private draft.
	var durable_draft := path + ".tmp"
	if temporary != durable_draft and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(durable_draft)):
		_failure(durable_draft, "暫存路徑是目錄，原存檔保留")
		return null
	# 一次明確新遊戲授權保留到首次成功；IO失敗不要求重新確認。
	overwrite_authorized = overwrite_authorized or confirmed_overwrite
	if FileAccess.file_exists(path + ".newrun"):
		var recovery := _recover_new_run()
		if not recovery.get("installed", false):
			unknown_version = recovery.get("unknown_version", false)
			if not confirmed_overwrite:
				_failure(path + ".newrun", recovery.get("error", "尚未完成新輪恢復，原件保留"))
				return null
			var marker_path := ProjectSettings.globalize_path(path + ".newrun")
			if FileAccess.file_exists(path + ".newrun.previous"):
				var removal := DirAccess.remove_absolute(marker_path + ".previous")
				if removal != OK:
					_failure(path + ".newrun.previous", "無法保留舊交易標記（%s）" % removal)
					return null
			var archival := DirAccess.rename_absolute(marker_path, marker_path + ".previous")
			if archival != OK:
				_failure(path + ".newrun", "無法保留舊交易標記（%s）" % archival)
				return null
	var primary := _read_file(path, true) if FileAccess.file_exists(path) else {}
	if primary.get("unknown_version", false):
		unknown_version = true
	elif not primary.has("data") and FileAccess.file_exists(path + ".bak") and _read_file(path + ".bak").get("unknown_version", false):
		unknown_version = true
	if unknown_version and not overwrite_authorized:
		_failure(path, "未知版本保留；請明確選擇新遊戲覆寫")
		return null
	var plan := WritePlan.new()
	plan.primary = primary
	plan.absolute = ProjectSettings.globalize_path(path)
	plan.temporary = temporary
	return plan


func _encode_write(data: Dictionary) -> String:
	var encoded := RunSaveCodec.encode(data)
	if encoded.is_empty() or encoded.to_utf8_buffer().size() > RunSaveCodec.MAX_BYTES:
		_failure(path, "整輪資料無效或超過大小上限，原檔保留")
		return ""
	return encoded


func _write_draft(plan: WritePlan, encoded: String) -> bool:
	var error := DirAccess.make_dir_recursive_absolute(plan.absolute.get_base_dir())
	if error != OK:
		return _failure(path, "無法建立存檔目錄（%s）" % error)
	var file := FileAccess.open(plan.temporary, FileAccess.WRITE)
	if file == null:
		return _failure(plan.temporary, "無法寫入（%s）" % FileAccess.get_open_error())
	file.store_string(encoded)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return _failure(plan.temporary, "寫入失敗（%s），原檔保留" % error)
	return true


func _verify_and_promote(plan: WritePlan) -> bool:
	var verified := _read_file(plan.temporary)
	if not verified.has("data"):
		return _failure(plan.temporary, "驗證失敗（%s），原檔保留" % verified.get("error", "未知錯誤"))
	var absolute := plan.absolute
	if overwrite_authorized:
		return _install_new_run(absolute)
	if FileAccess.file_exists(path + ".newrun"):
		return _failure(path, "偵測到其他新輪交易，保留原檔及暫存檔")
	var primary := plan.primary
	var error: Error
	# 只有完整有效的舊主檔能輪替備份。檔案相同時沿用本次校驗，
	# 另一程序若已換掉主檔，再檢查新檔及其版本。
	var old_valid := false
	if FileAccess.file_exists(path):
		if primary.get("content_checksum", "") != FileAccess.get_sha256(path):
			primary = _read_file(path)
			if primary.get("unknown_version", false):
				unknown_version = true
				return _failure(path, "存檔已另外更新為未知版本；新主檔及原備份保留")
		old_valid = primary.has("data")
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
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(plan.temporary), absolute)
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
			return {"error": "%s版本較新，新輪恢復未覆寫原件" % [path + suffix],
				"unknown_version": true, "required_edition": existing.get("required_edition")}
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


# Additive existing-run writer. The legacy methods above intentionally remain
# unchanged. Only a trusted synchronous coordinator may own this instance.
enum DurablePhase { TEMP_CLOSED, BACKUP_REMOVED, PRIMARY_ROTATED, PRIMARY_COMMITTED }

class PreparedExistingWrite extends RefCounted:
	var _owner_id: int
	var _path: String
	var _absolute: String
	var _profile: Dictionary
	var _snapshot: Dictionary
	var _encoded: String
	var _checksum: String
	var _seal: String
	var _consumed := false

	func snapshot() -> Dictionary:
		# The tree was bounded before allocation. No caller gets the stored alias.
		if not RunSaveCodec.validate_tree(_snapshot).is_empty():
			return {}
		return _snapshot.duplicate(true)


class DurableWriteOutcome extends RefCounted:
	enum Status { REJECTED, COMMITTED }
	var status: Status = Status.REJECTED
	var committed := false
	var stage := "preflight"
	var error: Error = OK
	var requires_recovery := false
	var checksum := ""
	var issues := PackedStringArray()

	func reject(where: String, reason: String, code: Error = ERR_INVALID_DATA) -> void:
		# A later diagnostic must never erase the durable commit fact.
		stage = where
		error = code
		if issues.size() < 8:
			issues.append((where + ": " + reason).left(RunSaveCodec.MAX_DIAGNOSTIC_PATH))


var _durable_busy := false


func _durable_declared_version(component: Dictionary, supported: int, where: String) -> Dictionary:
	if not component.has("version"):
		return {}  # Published versionless legacy defaults/repairs stay available.
	if not RunSaveCodec.valid_version(component["version"]):
		return {"error": "durable/" + where + "/version invalid"}
	if component["version"] != supported:
		return {"error": "durable/" + where + "/version unsupported", "unknown_version": true}
	return {}


## Fixed owner proofs; no arbitrary validator, producer registry or live install.
class _DurableProof:
	var catalog := Progression.InstallCatalog.new()
	var map_definitions := MapLayoutMigration.Definitions.new()
	var level: LevelData
	var layout: LevelLayout

	func _init(live: Level) -> void:
		if is_instance_valid(live) and live.is_initialized():
			level = live.data
			layout = live._layout


func _durable_prepare_snapshot(raw: Variant, proof: _DurableProof) -> Dictionary:
	var errors := RunSaveCodec.validate_tree(raw)
	if not errors.is_empty():
		return {"error": errors[0]}
	if not raw is Dictionary:
		return {"error": "durable/run must be an object"}
	# RunSnapshot normalization supplies mag=[], so it cannot preserve the
	# published Loadout.restore branch that consumes old total-ammo snapshots.
	# Refuse BEFORE normalization instead of silently overwriting that data.
	for entry: Array in [[raw.get("runtime", {}), "loadout", "runtime/loadout"], [raw.get("state", {}), "checkpoint_loadout", "state/checkpoint_loadout"], [raw.get("state", {}), "level_start_loadout", "state/level_start_loadout"]]:
		if entry[0] is Dictionary:
			var loadout: Variant = entry[0].get(entry[1], {})
			if loadout is Dictionary and loadout.has("ammo") and not loadout.has("mag"):
				return {"error": "durable/" + entry[2] + ": requires_legacy_loadout_migration"}
	var checked := RunSnapshot.prepare(raw, proof.level, proof.layout, proof.map_definitions)
	if checked.has("error"):
		return checked
	var data: Dictionary = checked["data"]
	var story: Dictionary = data["story"]
	var version := _durable_declared_version(story, 1, "story")
	if version.has("error"):
		return version
	version = _durable_declared_version(data["navigation"], QuestMapState.VERSION, "navigation")
	if version.has("error"):
		return version
	for entry: Array in [[data["runtime"]["loadout"], "runtime/loadout"], [data["state"]["checkpoint_loadout"], "state/checkpoint_loadout"], [data["state"]["level_start_loadout"], "state/level_start_loadout"]]:
		version = _durable_declared_version(entry[0], Loadout.SNAPSHOT_VERSION, entry[1])
		if version.has("error"):
			return version
	for component: Dictionary in [data["progression"], data["state"]["checkpoint_progress"], data["state"]["level_start_progress"]]:
		var progression := Progression.prepare_install(component, proof.catalog)
		if progression.has("error"):
			return progression
	var custody := StoryItems.prepare_install(story["items"])
	if custody.has("error"):
		return custody
	var game := GameState.prepare_install(data["state"], story["flags"], data["difficulty"], true)
	if game.has("error"):
		return game
	# Missing declared defaults and JSON integer flag types have one target for
	# disk and the future silent bundle. The owner only allocates local state.
	data["story"]["flags"] = game["data"].flags
	# Validate completion identities without any live request/reset operation.
	var seen: Dictionary = {}
	for id: Variant in story["seen"]:
		if not Story.has_scene(StringName(id)) or seen.has(StringName(id)):
			return {"error": "durable/story/seen unknown or repeated scene"}
		seen[StringName(id)] = true
	return {"data": data}


## At most three 4 MiB files; exact byte hashes and no directory enumeration.
func _durable_file_profile(candidate: String) -> Dictionary:
	var directory := DirAccess.open(candidate.get_base_dir())
	if directory == null:
		return {"error": "durable/source parent cannot open: " + candidate}
	# file_exists follows targets on Unix and can miss a dangling link. Reject the
	# directory entry first, including Windows reparse points, without writing it.
	if directory.is_link(candidate):
		return {"error": "durable/source symbolic/reparse entry refused: " + candidate}
	if DirAccess.dir_exists_absolute(candidate):
		return {"error": "durable/source is a directory: " + candidate}
	if not FileAccess.file_exists(candidate):
		return {"exists": false}
	var file := FileAccess.open(candidate, FileAccess.READ)
	if file == null:
		return {"error": "durable/source cannot open: " + candidate}
	var length := file.get_length()
	if length > RunSaveCodec.MAX_BYTES:
		file.close()
		return {"error": "durable/source exceeds size limit: " + candidate}
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if bytes.size() != length or error not in [OK, ERR_FILE_EOF]:
		return {"error": "durable/source short read: " + candidate}
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		return {"error": "durable/source is not canonical UTF-8: " + candidate}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return {"exists": true, "length": length, "checksum": hash.finish().hex_encode(), "text": text}


func _durable_profile(absolute: String, proof: _DurableProof = null) -> Dictionary:
	if overwrite_authorized or _durable_busy:
		return {"error": "durable/store overwrite-authorized or busy"}
	var directory := DirAccess.open(absolute.get_base_dir())
	if directory == null:
		return {"error": "durable/source parent cannot open"}
	if directory.is_link(absolute + ".newrun") or FileAccess.file_exists(absolute + ".newrun") or DirAccess.dir_exists_absolute(absolute + ".newrun"):
		return {"error": "durable/new-run marker requires legacy recovery"}
	if FileAccess.file_exists(absolute) and FileAccess.file_exists(absolute + ".bak") and directory.is_equivalent(absolute, absolute + ".bak"):
		return {"error": "durable/primary and backup alias the same filesystem object"}
	var profile: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp"]:
		var found := _durable_file_profile(absolute + suffix)
		if found.has("error"):
			return found
		if suffix.is_empty() and not found["exists"]:
			return {"error": "durable/base slot has no supported primary"}
		if proof != null and found["exists"]:
			var decoded := RunSaveCodec.decode(found["text"])
			if decoded.has("error"):
				return {"error": "durable/source " + suffix + ": " + decoded["error"], "unknown_version": decoded.get("unknown_version", false)}
			var prepared := _durable_prepare_snapshot(decoded["data"], proof)
			if prepared.has("error"):
				return {"error": "durable/source " + suffix + ": " + prepared["error"], "unknown_version": prepared.get("unknown_version", false)}
		found.erase("text")
		profile[suffix] = found
	return {"data": profile}


func prepare_existing_write(raw: Variant, level: Level = null) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not absolute.is_absolute_path() or absolute.get_file().is_empty():
		return {"error": "durable/path must resolve to an absolute slot"}
	# Saved snapshots only reuse this layout when the authored level matches.
	var proof := _DurableProof.new(level)
	var source := _durable_profile(absolute, proof)
	if source.has("error"):
		return source
	var checked := _durable_prepare_snapshot(raw, proof)
	if checked.has("error"):
		return checked
	# Normalize through the actual JSON boundary, then prove the exact returned
	# candidate; the later coordinator must use snapshot(), never the original raw.
	var encoded := RunSaveCodec.encode(checked["data"])
	var decoded := RunSaveCodec.decode(encoded)
	if decoded.has("error"):
		return decoded
	checked = _durable_prepare_snapshot(decoded["data"], proof)
	if checked.has("error"):
		return checked
	encoded = RunSaveCodec.encode(checked["data"])
	if encoded.is_empty() or encoded.to_utf8_buffer().size() > RunSaveCodec.MAX_BYTES:
		return {"error": "durable/candidate encoding exceeds budget"}
	var prepared := PreparedExistingWrite.new()
	prepared._owner_id = get_instance_id()
	prepared._path = path
	prepared._absolute = absolute
	prepared._profile = source["data"]
	prepared._snapshot = checked["data"]
	prepared._encoded = encoded
	prepared._checksum = encoded.sha256_text()
	prepared._seal = _durable_seal(prepared)
	return {"data": prepared}


func _durable_seal(prepared: PreparedExistingWrite) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes([prepared._owner_id, prepared._path, prepared._absolute,
		prepared._profile, prepared._snapshot, prepared._encoded, prepared._checksum]))
	return hash.finish().hex_encode()


func preflight_existing_write(prepared: PreparedExistingWrite) -> Dictionary:
	if prepared == null or prepared._owner_id != get_instance_id():
		return {"error": "durable/prepared belongs to another store"}
	if prepared._consumed:
		return {"error": "durable/prepared already consumed"}
	if path != prepared._path or ProjectSettings.globalize_path(path).simplify_path() != prepared._absolute:
		return {"error": "durable/prepared path changed"}
	if not RunSaveCodec.validate_tree(prepared._snapshot).is_empty() or not RunSaveCodec.validate_tree(prepared._profile).is_empty():
		return {"error": "durable/prepared data damaged"}
	if prepared._encoded.to_utf8_buffer().size() > RunSaveCodec.MAX_BYTES or _durable_seal(prepared) != prepared._seal:
		return {"error": "durable/prepared content changed"}
	var source := _durable_profile(prepared._absolute)
	if source.has("error"):
		return source
	if source["data"] != prepared._profile:
		return {"error": "durable/source stale; prepare from current slot"}
	return {"ready": true}


func commit_existing_write(prepared: PreparedExistingWrite) -> DurableWriteOutcome:
	cancel_deferred_write()
	var outcome := DurableWriteOutcome.new()
	var checked := preflight_existing_write(prepared)
	if prepared != null and prepared._owner_id == get_instance_id():
		prepared._consumed = true
		outcome.checksum = prepared._checksum
	if checked.has("error"):
		outcome.reject("preflight", checked["error"])
		return outcome
	_durable_busy = true
	var absolute := prepared._absolute
	var error := _durable_write_temp(absolute, prepared._encoded)
	if error == OK:
		_durable_phase(DurablePhase.TEMP_CLOSED, absolute)
		var verified := _durable_file_profile(absolute + ".tmp")
		if verified.has("error") or not verified.get("exists", false) or verified.get("checksum") != prepared._checksum:
			error = ERR_FILE_CORRUPT
	if error != OK:
		outcome.reject("temp", "temporary write or exact verification failed", error)
		_durable_busy = false
		return outcome
	# Recheck authoritative files before first rotation; tmp is our verified output.
	for suffix: String in ["", ".bak"]:
		var found := _durable_file_profile(absolute + suffix)
		found.erase("text")
		if found != prepared._profile[suffix]:
			outcome.reject("rotation_preflight", "authoritative file changed")
			_durable_busy = false
			return outcome
	var directory := DirAccess.open(absolute.get_base_dir())
	if directory == null or directory.is_link(absolute + ".newrun") or overwrite_authorized or FileAccess.file_exists(absolute + ".newrun") or DirAccess.dir_exists_absolute(absolute + ".newrun") or path != prepared._path:
		outcome.reject("rotation_preflight", "marker, authorization or path changed")
		_durable_busy = false
		return outcome
	if prepared._profile[".bak"]["exists"]:
		error = _durable_remove_backup(absolute)
		if error != OK:
			outcome.reject("backup_remove", "old backup could not be removed", error)
			_durable_busy = false
			return outcome
	_durable_phase(DurablePhase.BACKUP_REMOVED, absolute)
	error = _durable_rename(absolute, DurablePhase.PRIMARY_ROTATED)
	if error != OK:
		outcome.reject("primary_rotate", "primary could not rotate to backup", error)
		_durable_busy = false
		return outcome
	_durable_phase(DurablePhase.PRIMARY_ROTATED, absolute)
	error = _durable_rename(absolute, DurablePhase.PRIMARY_COMMITTED)
	if error != OK:
		outcome.reject("primary_commit", "candidate could not replace primary", error)
		var rollback := _durable_rollback(absolute)
		if rollback != OK:
			outcome.requires_recovery = true
			outcome.reject("rollback", "old complete backup retained; legacy read required", rollback)
		_durable_busy = false
		return outcome
	# The commit fact precedes every subsequent seam or diagnostic. No cleanup.
	outcome.committed = true
	outcome.status = DurableWriteOutcome.Status.COMMITTED
	outcome.stage = "primary_committed"
	_durable_phase(DurablePhase.PRIMARY_COMMITTED, absolute)
	_durable_busy = false
	return outcome


func _durable_detach_temp(absolute: String) -> Error:
	var directory := DirAccess.open(absolute.get_base_dir())
	if directory == null or directory.is_link(absolute + ".tmp"):
		return ERR_INVALID_DATA
	# A validated existing regular file can still be a hardlink to primary, bak,
	# or an unrelated file. Unlink this entry BEFORE opening WRITE; never truncate
	# the old inode. Failure here precedes every authoritative mutation.
	if FileAccess.file_exists(absolute + ".tmp"):
		var removal := DirAccess.remove_absolute(absolute + ".tmp")
		if removal != OK:
			return removal
		if FileAccess.file_exists(absolute + ".tmp") or directory.is_link(absolute + ".tmp"):
			return ERR_CANT_CREATE
	return OK


func _durable_write_temp(absolute: String, encoded: String) -> Error:
	var detached := _durable_detach_temp(absolute)
	if detached != OK:
		return detached
	var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(encoded)
	file.flush()
	var error := file.get_error()
	file.close()
	return error


func _durable_remove_backup(absolute: String) -> Error:
	return DirAccess.remove_absolute(absolute + ".bak")


func _durable_rename(absolute: String, phase: DurablePhase) -> Error:
	if phase == DurablePhase.PRIMARY_ROTATED:
		return DirAccess.rename_absolute(absolute, absolute + ".bak")
	if phase == DurablePhase.PRIMARY_COMMITTED:
		return DirAccess.rename_absolute(absolute + ".tmp", absolute)
	return ERR_INVALID_PARAMETER


func _durable_rollback(absolute: String) -> Error:
	return DirAccess.rename_absolute(absolute + ".bak", absolute)


## Trusted test subclasses only. Production never accepts a handler/stage input.
func _durable_phase(_phase: DurablePhase, _absolute: String) -> void:
	pass
