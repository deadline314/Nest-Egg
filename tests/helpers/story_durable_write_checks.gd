extends RefCounted
## Real filesystem and actual autoload/resource proofs. No production producer.

const FIRST := "res://data/levels/ch1_pawnshop.tres"

class FaultStore extends RunSaveStore:
	enum Fault { NONE, TEMP_OPEN, TEMP_CORRUPT, BACKUP_REMOVE, ROTATE, COMMIT, ROLLBACK, AFTER_UNLINK_OPEN }
	var fault: Fault = Fault.NONE
	var scope := ""

	func _durable_detach_temp(absolute: String) -> Error:
		if absolute != scope:
			return ERR_INVALID_PARAMETER
		var detached := super._durable_detach_temp(absolute)
		if detached == OK and fault == Fault.AFTER_UNLINK_OPEN:
			DirAccess.make_dir_absolute(absolute + ".tmp")
		return detached

	func _durable_write_temp(absolute: String, encoded: String) -> Error:
		if absolute != scope:
			return ERR_INVALID_PARAMETER
		if fault == Fault.TEMP_OPEN:
			DirAccess.make_dir_absolute(absolute + ".tmp")
		return super._durable_write_temp(absolute, encoded)

	func _durable_phase(phase: DurablePhase, absolute: String) -> void:
		if absolute == scope and phase == DurablePhase.TEMP_CLOSED and fault == Fault.TEMP_CORRUPT:
			var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
			file.store_string("{}")
			file.close()

	func _durable_remove_backup(absolute: String) -> Error:
		if absolute != scope:
			return ERR_INVALID_PARAMETER
		if fault == Fault.BACKUP_REMOVE:
			DirAccess.rename_absolute(absolute + ".bak", absolute + ".fault-bak")
			DirAccess.make_dir_absolute(absolute + ".bak")
			var file := FileAccess.open(absolute + ".bak/blocker", FileAccess.WRITE)
			file.store_string("block")
			file.close()
		return super._durable_remove_backup(absolute)

	func _durable_rename(absolute: String, phase: DurablePhase) -> Error:
		if absolute != scope:
			return ERR_INVALID_PARAMETER
		if phase == DurablePhase.PRIMARY_ROTATED and fault == Fault.ROTATE:
			DirAccess.make_dir_absolute(absolute + ".bak")
		if phase == DurablePhase.PRIMARY_COMMITTED and fault in [Fault.COMMIT, Fault.ROLLBACK]:
			DirAccess.rename_absolute(absolute + ".tmp", absolute + ".fault-tmp")
			if fault == Fault.ROLLBACK:
				DirAccess.make_dir_absolute(absolute)
		return super._durable_rename(absolute, phase)


class AliasStore extends RunSaveStore:
	var scope := ""
	var old_primary := ""
	var old_backup := ""
	var external := ""
	var old_external := ""
	var temp_checked := false
	var temp_safe := false
	var block_after_unlink := false

	func _durable_detach_temp(absolute: String) -> Error:
		if absolute != scope:
			return ERR_INVALID_PARAMETER
		var detached := super._durable_detach_temp(absolute)
		if detached == OK and block_after_unlink:
			DirAccess.make_dir_absolute(absolute + ".tmp")
		return detached

	func _durable_phase(phase: DurablePhase, absolute: String) -> void:
		if absolute != scope or phase != DurablePhase.TEMP_CLOSED:
			return
		temp_checked = true
		temp_safe = FileAccess.get_file_as_string(absolute) == old_primary and FileAccess.get_file_as_string(absolute + ".bak") == old_backup
		if not external.is_empty():
			temp_safe = temp_safe and FileAccess.get_file_as_string(external) == old_external


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


static func _cleanup(path: String) -> void:
	# Only known single files/empty dirs under this helper's fixed slot. No recursion.
	for suffix: String in [".bak/blocker", "", ".bak", ".tmp", ".newrun", ".newrun.tmp", ".freshbak", ".previous", ".previous.bak", ".fault-bak", ".fault-tmp", ".external"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


static func _live() -> PackedByteArray:
	return var_to_bytes([GameState._install_source(), Progression.snapshot(), StoryItems.snapshot(), Story._install_source()])


## Shared actual resource fixture for suite and independent-process probe.
## This supplies persistence facts, not an admitted producer or story capability.
static func fixture() -> Dictionary:
	var data := RunSnapshot.capture(FIRST, {"position": [100, 160], "health": 4, "world": {}, "loadout": {}})
	var definitions: Dictionary = {}
	# 固定用第一章的七筆交易當夾具（之後章節新增的交易不影響這組檢查）。
	for resource: StoryTransactionData in ResourceCatalog.load_dir("res://data/story_transactions", StoryTransactionData, "DurableChecks"):
		if String(resource.id).begins_with("ch1."):
			definitions[String(resource.id)] = resource
	if definitions.size() != 7 or StoryItems.find(&"ch1_data_disk") == null or StoryItems.find(&"ch1_grey_cloth") == null:
		return {"error": "canonical fixture resources missing"}
	var ledger := StoryTransactionLedger.new()
	var wallet := 1000
	for id: String in ["ch1.revival_meal.order", "ch1.revival_meal.paid"]:
		if not definitions.has(id):
			return {"error": "canonical fixture transaction missing"}
		var result := ledger.commit(definitions[id], wallet, Progression.MAX_CREDITS)
		if not result["applied"]:
			return {"error": result["status"]}
		wallet = result["credits_after"]
	data["progression"]["credits"] = wallet
	data["progression"]["story_transactions"] = ledger.snapshot()
	data["progression"]["upgrades"] = {"pistol": ["quick_reload"]}
	data["progression"]["abilities"] = ["emp_pulse", "overclock"]
	data["progression"]["equipped"] = "overclock"
	data["progression"]["pawned"] = {"med_injector": 2}
	data["story"]["items"] = {"custody_version": StoryItems.CUSTODY_VERSION,
		"owned": ["ch1_data_disk", "ch1_grey_cloth"], "held": ["ch1_data_disk"], "transferred": ["ch1_grey_cloth"], "unseen": ["ch1_data_disk"]}
	for id: String in Story._scenes:
		data["story"]["seen"] = [id]
		break
	data["state"]["kills"] = 19
	data["runtime"]["loadout"] = {"version": Loadout.SNAPSHOT_VERSION, "weapons": ["res://data/weapons/pistol.tres"], "mag": [7], "reserve": [-1], "active": 0, "consumables": {"med_injector": 1}}
	data["runtime"]["facing"] = -1
	return {"data": data}


static func _reject(s: TestSuite, store: RunSaveStore, raw: Variant, label: String) -> void:
	var before := _live()
	var disk := _files(store.path)
	var input := var_to_bytes(raw)
	var result := store.prepare_existing_write(raw)
	s.check(result.has("error"), "durable refuses " + label)
	s.check(_live() == before and var_to_bytes(raw) == input and _files(store.path) == disk, "durable refusal preserves owners/input/all source files: " + label)


static func _files(path: String) -> PackedByteArray:
	var files: Array = []
	var directory := DirAccess.open(ProjectSettings.globalize_path(path).get_base_dir())
	for suffix: String in ["", ".bak", ".tmp", ".newrun"]:
		var absolute := ProjectSettings.globalize_path(path + suffix)
		var linked: bool = directory != null and directory.is_link(absolute)
		files.append([linked, directory.read_link(absolute) if linked else "", DirAccess.dir_exists_absolute(absolute), FileAccess.file_exists(absolute), FileAccess.get_file_as_bytes(absolute) if not linked and FileAccess.file_exists(absolute) else PackedByteArray()])
	return var_to_bytes(files)


## Root creates REAL hardlinks before this independent-process probe enters.
## No fake equality bool; source topology must be recognized by native DirAccess.
static func check_external_alias(path: String, kind: String, candidate: Dictionary) -> Dictionary:
	if kind not in ["tmp_primary", "tmp_backup", "tmp_external", "primary_backup", "tmp_dangling", "tmp_symlink", "tmp_primary_open_fail"]:
		return {"error": "unknown fixed alias test"}
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	var directory := DirAccess.open(absolute.get_base_dir())
	if directory == null:
		return {"error": "alias test parent cannot open"}
	var external := absolute.get_base_dir().path_join("external.json")
	var rejected: bool = kind in ["primary_backup", "tmp_dangling", "tmp_symlink"]
	var paired := absolute
	if kind == "tmp_backup":
		paired += ".bak"
	elif kind == "tmp_external":
		paired = external
	if kind == "primary_backup":
		if not directory.is_equivalent(absolute, absolute + ".bak"):
			return {"error": "required real primary/backup hardlink not recognized"}
	elif kind in ["tmp_dangling", "tmp_symlink"]:
		if not directory.is_link(absolute + ".tmp"):
			return {"error": "required real symbolic/reparse tmp not recognized"}
		if kind == "tmp_dangling":
			# Windows file_exists reports attributes of the link entry itself.
			var target := FileAccess.open(absolute + ".tmp", FileAccess.READ)
			if target != null:
				target.close()
				return {"error": "dangling-link fixture unexpectedly has a readable target"}
	elif directory.is_link(absolute + ".tmp") or not directory.is_equivalent(paired, absolute + ".tmp"):
		return {"error": "required real tmp hardlink not recognized"}
	var old_files := _files(absolute)
	var live := _live()
	var raw := var_to_bytes(candidate)
	var store := AliasStore.new(path)
	store.scope = absolute
	store.old_primary = FileAccess.get_file_as_string(absolute)
	store.old_backup = FileAccess.get_file_as_string(absolute + ".bak")
	if kind == "tmp_external":
		store.external = external
		store.old_external = FileAccess.get_file_as_string(external)
	var ready := store.prepare_existing_write(candidate)
	if rejected:
		if not ready.has("error") or old_files != _files(absolute) or live != _live() or raw != var_to_bytes(candidate):
			return {"error": "rejected filesystem alias changed source or live data"}
		return {"valid": true, "committed": false, "kind": kind}
	if not ready.has("data"):
		return {"error": "safe hardlink preparation rejected: " + ready.get("error", "unknown")}
	store.block_after_unlink = kind == "tmp_primary_open_fail"
	var outcome := store.commit_existing_write(ready["data"])
	if kind == "tmp_primary_open_fail":
		if outcome.committed or outcome.error == OK or FileAccess.get_file_as_string(absolute) != store.old_primary or FileAccess.get_file_as_string(absolute + ".bak") != store.old_backup or live != _live() or raw != var_to_bytes(candidate):
			return {"error": "temp open failure after unlink changed primary or backup"}
		return {"valid": true, "committed": false, "kind": kind}
	if not outcome.committed or not store.temp_checked or not store.temp_safe or live != _live() or raw != var_to_bytes(candidate):
		return {"error": "hardlink temp detach failed exact precommit old-state invariant"}
	if not store.external.is_empty() and FileAccess.get_file_as_string(external) != store.old_external:
		return {"error": "hardlink write changed unrelated external file"}
	var reader := RunSaveStore.new(path)
	reader.validator = RunSnapshot.prepare
	if RunSaveCodec.encode(reader.read()) != RunSaveCodec.encode(ready["data"].snapshot()) or FileAccess.get_file_as_string(absolute + ".bak") != store.old_primary:
		return {"error": "hardlink write did not preserve complete old backup/new primary"}
	return {"valid": true, "committed": true, "kind": kind}


static func run(s: TestSuite) -> void:
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	var captured := fixture()
	s.check(captured.has("data"), "durable fixtures use canonical seven resources, actual custody and scene")
	if not captured.has("data"):
		return
	var next: Dictionary = captured["data"]
	var old := RunSnapshot.capture(FIRST, {"position": [80, 160], "health": 3, "world": {}, "loadout": {}})
	var directory := String(s.get("directory")).path_join("durable")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join("slot.json")
	_cleanup(path)
	var store := RunSaveStore.new(path)
	store.validator = RunSnapshot.prepare
	s.check(store.write(old, true), "durable base uses real established supported primary and backup")
	var before := _live()
	var calls := {"count": 0}
	store.validator = func(_raw: Dictionary) -> Dictionary:
		calls["count"] += 1
		return {"error": "arbitrary validator must never run"}
	var events := {"count": 0}
	var on_simple := func() -> void: events["count"] += 1
	var on_credits := func(_credits: int, _delta: int) -> void: events["count"] += 1
	var on_item := func(_item: StoryItemData) -> void: events["count"] += 1
	var on_id := func(_id: StringName) -> void: events["count"] += 1
	var on_request := func(_request: int, _completed: bool) -> void: events["count"] += 1
	var on_lives := func(_lives: int) -> void: events["count"] += 1
	GameState.run_save_requested.connect(on_simple)
	Progression.credits_changed.connect(on_credits)
	Progression.story_transaction_committed.connect(on_id)
	StoryItems.acquired.connect(on_item)
	StoryItems.transferred.connect(on_item)
	Story.scene_finished.connect(on_id)
	Story.request_settled.connect(on_request)
	EventBus.lives_changed.connect(on_lives)
	var input_before := var_to_bytes(next)
	var prepared := store.prepare_existing_write(next)
	s.check(prepared.has("data"), "durable prepares normalized all-component candidate without arbitrary validator")
	if prepared.has("data"):
		var candidate: RunSaveStore.PreparedExistingWrite = prepared["data"]
		var snapshot := candidate.snapshot()
		snapshot["progression"]["credits"] = 0
		snapshot["story"]["items"]["held"].clear()
		s.check(candidate.snapshot()["progression"]["credits"] == next["progression"]["credits"] and candidate.snapshot()["story"]["items"]["held"].size() == 1, "durable getter aliases never touch stored candidate or caller input")
		s.check(var_to_bytes(next) == input_before, "durable preparation and returned alias edits leave source bytes unchanged")
		var foreign := RunSaveStore.new(path)
		s.check(not foreign.commit_existing_write(candidate).committed and store.preflight_existing_write(candidate).has("ready"), "wrong owner cannot use or consume preparation")
		var outcome := store.commit_existing_write(candidate)
		s.check(outcome.committed and outcome.status == RunSaveStore.DurableWriteOutcome.Status.COMMITTED and outcome.error == OK and not outcome.requires_recovery, "successful primary rename returns sticky typed commit fact")
		outcome.reject("later_diagnostic", "does not reverse a commit")
		s.check(outcome.committed, "later diagnostic cannot demote committed outcome")
		s.check(not store.commit_existing_write(candidate).committed, "same prepared write is one-shot without rotating again")
		var reader := RunSaveStore.new(path)
		reader.validator = RunSnapshot.prepare
		var read := reader.read()
		s.check(RunSaveCodec.encode(read) == RunSaveCodec.encode(candidate.snapshot()), "actual fresh store reads complete normalized candidate, not receipt-only delta")
		s.check(FileAccess.get_file_as_string(path + ".bak") == RunSaveCodec.encode(old), "backup rotation retains exact previous whole run")
	s.check(calls["count"] == 0 and events["count"] == 0 and _live() == before, "prepare/commit/reject never invoke arbitrary validator, live mutation, signals or save requests")
	store.validator = RunSnapshot.prepare
	var repaired_raw := old.duplicate(true)
	repaired_raw["progression"]["credits"] = "legacy bad scalar"
	repaired_raw["progression"]["abilities"] = ["overclock", 99]
	var repaired := store.prepare_existing_write(repaired_raw)
	s.check(repaired.has("data"), "durable candidate keeps published raw scalar/filter repair policy")
	if repaired.has("data"):
		var snapshot: Dictionary = repaired["data"].snapshot()
		s.check(snapshot["progression"]["credits"] == 0 and snapshot["progression"]["abilities"] == ["overclock"], "owner proof applies to normalized zero credits and filtered ability list")
	var legacy := old.duplicate(true)
	legacy["progression"].erase("version")
	legacy["navigation"].erase("version")
	legacy["story"]["items"] = {"owned": ["ch1_data_disk"], "unseen": []}
	var migrated := store.prepare_existing_write(legacy)
	s.check(migrated.has("data"), "versionless legacy progression and custody still prepare")
	if migrated.has("data"):
		var snapshot: Dictionary = migrated["data"].snapshot()
		s.check(snapshot["story"]["items"]["custody_version"] == StoryItems.CUSTODY_VERSION and String(snapshot["story"]["items"]["held"][0]) == "ch1_data_disk" and snapshot["story"]["items"]["transferred"].is_empty(), "legacy acquisition history migrates to held/current canonical custody")
	for component: String in ["runtime", "checkpoint", "entry"]:
		var legacy_ammo := old.duplicate(true)
		var ammo_loadout := {"weapons": ["res://data/weapons/pistol.tres"], "ammo": [17], "active": 0}
		match component:
			"runtime": legacy_ammo["runtime"]["loadout"] = ammo_loadout
			"checkpoint": legacy_ammo["state"]["checkpoint_loadout"] = ammo_loadout
			"entry": legacy_ammo["state"]["level_start_loadout"] = ammo_loadout
		_reject(s, store, legacy_ammo, "candidate total-ammo migration required: " + component)
		var refused := store.prepare_existing_write(legacy_ammo)
		s.check(String(refused.get("error", "")).contains("requires_legacy_loadout_migration"), "legacy ammo refusal identifies missing migration: " + component)
		for suffix: String in ["", ".bak", ".tmp"]:
			var ammo_path := directory.path_join("ammo_%s_%d.json" % [component, suffix.length()])
			_cleanup(ammo_path)
			var ammo_store := RunSaveStore.new(ammo_path)
			ammo_store.write(old, true)
			_write(ammo_path + suffix, RunSaveCodec.encode(legacy_ammo))
			_reject(s, ammo_store, next, "source total-ammo migration required: %s/%s" % [component, suffix])
			s.check(FileAccess.get_file_as_string(ammo_path + suffix) == RunSaveCodec.encode(legacy_ammo), "raw legacy ammo source is not normalized or consumed: %s/%s" % [component, suffix])
			_cleanup(ammo_path)
	var mutable := next.duplicate(true)
	var detached := store.prepare_existing_write(mutable)
	if detached.has("data"):
		var candidate: RunSaveStore.PreparedExistingWrite = detached["data"]
		var expected := candidate.snapshot()
		mutable["progression"]["credits"] = 0
		mutable["story"]["seen"].clear()
		mutable["story"]["items"]["held"].clear()
		mutable["runtime"]["loadout"]["mag"].clear()
		s.check(store.commit_existing_write(candidate).committed and RunSaveCodec.encode(store.read()) == RunSaveCodec.encode(expected), "post-prepare raw alias mutation cannot change disk candidate")
	var changed_path := store.prepare_existing_write(next)
	store.path = path + ".other"
	if changed_path.has("data"):
		s.check(not store.commit_existing_write(changed_path["data"]).committed and not FileAccess.file_exists(store.path), "prepared path bound rejects before writing foreign slot")
	store.path = path
	for field: String in ["version", "progression", "story", "custody", "ledger", "checkpoint", "entry", "navigation", "runtime_loadout", "checkpoint_loadout", "entry_loadout"]:
		var bad := next.duplicate(true)
		match field:
			"version": bad["version"] = 999
			"progression": bad["progression"]["version"] = 999
			"story": bad["story"]["version"] = 999
			"custody": bad["story"]["items"]["custody_version"] = 999
			"ledger": bad["progression"]["story_transactions"]["version"] = 999
			"checkpoint": bad["state"]["checkpoint_progress"]["version"] = 999
			"entry": bad["state"]["level_start_progress"]["version"] = 999
			"navigation": bad["navigation"]["version"] = 999
			"runtime_loadout": bad["runtime"]["loadout"]["version"] = 999
			"checkpoint_loadout": bad["state"]["checkpoint_loadout"]["version"] = 999
			"entry_loadout": bad["state"]["level_start_loadout"]["version"] = 999
		_reject(s, store, bad, "future " + field)
	for malformed: Variant in [null, "1", 1.5]:
		var bad := next.duplicate(true)
		bad["progression"]["version"] = malformed
		_reject(s, store, bad, "malformed declared nested version")
		bad = next.duplicate(true)
		bad["navigation"]["version"] = malformed
		_reject(s, store, bad, "malformed declared navigation version")
		bad = next.duplicate(true)
		bad["runtime"]["loadout"]["version"] = malformed
		_reject(s, store, bad, "malformed declared loadout version")
	for flag: String in GameState.flag_defaults:
		if GameState.flag_defaults[flag] is bool:
			var wrong_flags := next.duplicate(true)
			wrong_flags["story"]["flags"][flag] = "wrong type"
			_reject(s, store, wrong_flags, "wrong declared flag type")
			break
	var corrupt := next.duplicate(true)
	corrupt["progression"]["story_transactions"]["receipts"]["ch1.revival_meal.paid"]["credits_delta"] += 1
	_reject(s, store, corrupt, "canonical receipt delta mismatch")
	corrupt = next.duplicate(true)
	corrupt["story"]["items"]["held"] = ["unknown"]
	_reject(s, store, corrupt, "unknown custody item")
	_reject(s, store, {"bad": s}, "object input")
	var bytes_before := _files(path)
	var damaged := store.prepare_existing_write(next)
	if damaged.has("data"):
		var candidate: RunSaveStore.PreparedExistingWrite = damaged["data"]
		candidate._snapshot["progression"]["credits"] -= 1
		s.check(not store.commit_existing_write(candidate).committed and _files(path) == bytes_before, "damaged opaque preparation seal rejects before filesystem mutation")
	var stale := store.prepare_existing_write(next)
	var stale_old := next.duplicate(true)
	stale_old["progression"]["credits"] -= 1
	s.check(RunSaveStore.new(path).write(stale_old), "real second store replaces source after preparation")
	if stale.has("data"):
		s.check(not store.commit_existing_write(stale["data"]).committed and not store.preflight_existing_write(stale["data"]).has("ready"), "stale same-owner attempt rejects and consumes preparation")
	for suffix: String in ["", ".bak", ".tmp"]:
		var protected_path := directory.path_join("future_%d.json" % suffix.length())
		_cleanup(protected_path)
		var protected_store := RunSaveStore.new(protected_path)
		protected_store.write(old, true)
		_write(protected_path + suffix, '{"version":999}')
		_reject(s, protected_store, next, "future source " + suffix)
		s.check(FileAccess.get_file_as_string(protected_path + suffix) == '{"version":999}', "future primary/bak/tmp bytes remain untouched: " + suffix)
		_cleanup(protected_path)
	for suffix: String in [".bak", ".tmp"]:
		var nested_future := next.duplicate(true)
		nested_future["progression"]["story_transactions"]["version"] = 999
		_write(path + suffix, RunSaveCodec.encode(nested_future))
		_reject(s, store, next, "future nested source ledger " + suffix)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	for suffix: String in ["", ".bak", ".tmp"]:
		for component: String in ["navigation", "runtime_loadout", "checkpoint_loadout", "entry_loadout"]:
			var guard_path := directory.path_join("guard_%d_%s.json" % [suffix.length(), component])
			_cleanup(guard_path)
			var guarded := RunSaveStore.new(guard_path)
			guarded.write(old, true)
			var future := old.duplicate(true)
			match component:
				"navigation": future["navigation"]["version"] = 999
				"runtime_loadout": future["runtime"]["loadout"]["version"] = 999
				"checkpoint_loadout": future["state"]["checkpoint_loadout"]["version"] = 999
				"entry_loadout": future["state"]["level_start_loadout"]["version"] = 999
			_write(guard_path + suffix, RunSaveCodec.encode(future))
			_reject(s, guarded, next, "future source %s at %s" % [component, suffix])
			_cleanup(guard_path)
	for suffix: String in [".bak", ".tmp"]:
		_write(path + suffix, "{broken")
		_reject(s, store, next, "unreadable source " + suffix)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var base_bytes := FileAccess.get_file_as_string(path)
	_write(path + ".bak", base_bytes)
	_write(path, "{broken")
	_reject(s, store, next, "corrupt primary despite supported backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_reject(s, store, next, "missing primary despite supported backup")
	_write(path, base_bytes)
	_write(path + ".newrun", "marker")
	_reject(s, store, next, "unresolved new-run marker")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".newrun"))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".newrun"))
	_reject(s, store, next, "new-run marker directory")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".newrun"))
	store.overwrite_authorized = true
	_reject(s, store, next, "pending overwrite authorization")
	store.overwrite_authorized = false
	for suffix: String in ["", ".bak", ".tmp", ".newrun", ".dangling"]:
		var link_path := directory.path_join("link_%d.json" % suffix.length())
		_cleanup(link_path)
		var linked := RunSaveStore.new(link_path)
		linked.write(old, true)
		var absolute := ProjectSettings.globalize_path(link_path)
		var links := DirAccess.open(absolute.get_base_dir())
		_write(absolute + ".external", RunSaveCodec.encode(old))
		var source := absolute + ".external"
		var target := absolute + suffix
		if suffix == ".dangling":
			source = absolute + ".external-missing"
			target = absolute + ".tmp"
		DirAccess.remove_absolute(target)
		var creation := links.create_link(source, target)
		if creation != OK:
			print("[StoryDurableChecks] SKIP symbolic/reparse case %s: platform permission/API %s; not validated" % [suffix, creation])
		else:
			s.check(links.is_link(target), "real symbolic/reparse directory entry recognized: " + suffix)
			_reject(s, linked, next, "symbolic/reparse source including dangling " + suffix)
			s.check(FileAccess.get_file_as_string(absolute + ".external") == RunSaveCodec.encode(old) and not FileAccess.file_exists(absolute + ".external-missing"), "symbolic rejection never writes real or dangling target: " + suffix)
		_cleanup(link_path)
	for fault: FaultStore.Fault in [FaultStore.Fault.TEMP_OPEN, FaultStore.Fault.TEMP_CORRUPT, FaultStore.Fault.BACKUP_REMOVE, FaultStore.Fault.ROTATE, FaultStore.Fault.COMMIT, FaultStore.Fault.ROLLBACK, FaultStore.Fault.AFTER_UNLINK_OPEN]:
		var fault_path := directory.path_join("fault_%d.json" % fault)
		_cleanup(fault_path)
		var broken := FaultStore.new(fault_path)
		broken.scope = ProjectSettings.globalize_path(fault_path).simplify_path()
		# Derive the expected whole OLD run from the independently captured seed,
		# through the same published JSON boundary a fresh reader must consume.
		# A raw-memory prepare skips JSON numeric conversion (notably zero flags).
		var old_encoded := RunSaveCodec.encode(old)
		var old_decoded := RunSaveCodec.decode(old_encoded)
		var expected_old: Dictionary = RunSnapshot.prepare(old_decoded["data"])["data"]
		s.check(broken.write(old, true) and FileAccess.get_file_as_string(fault_path) == old_encoded, "fault seed preserves independent complete old envelope: %d" % fault)
		if fault == FaultStore.Fault.TEMP_OPEN:
			var raw_expected: Dictionary = RunSnapshot.prepare(old)["data"]
			for key: String in expected_old:
				if JSON.stringify(expected_old[key]) != JSON.stringify(raw_expected.get(key)):
					print("[StoryDurableChecks] old seed JSON boundary changes encoding of component: " + key)
		if fault == FaultStore.Fault.AFTER_UNLINK_OPEN:
			_write(fault_path + ".tmp", RunSaveCodec.encode(old))
		var ready := broken.prepare_existing_write(next)
		s.check(ready.has("data"), "fault injection starts after valid preparation: %d" % fault)
		if ready.has("data"):
			var live_before := _live()
			var input_bytes := var_to_bytes(next)
			broken.fault = fault
			var outcome := broken.commit_existing_write(ready["data"])
			s.check(not outcome.committed and outcome.error != OK and outcome.requires_recovery == (fault == FaultStore.Fault.ROLLBACK), "real filesystem fault has precise precommit/recovery outcome: %d" % fault)
			s.check(_live() == live_before and var_to_bytes(next) == input_bytes, "disk fault leaves live owners and input bytes unchanged: %d" % fault)
			if fault == FaultStore.Fault.ROLLBACK:
				DirAccess.remove_absolute(broken.scope)
			var reader := RunSaveStore.new(fault_path)
			reader.validator = RunSnapshot.prepare
			var recovered := reader.read()
			var preserved := false
			for suffix: String in ["", ".bak"]:
				if not DirAccess.dir_exists_absolute(broken.scope + suffix) and FileAccess.file_exists(fault_path + suffix):
					preserved = preserved or FileAccess.get_file_as_string(fault_path + suffix) == old_encoded
			s.check(preserved, "failed disk stage retains exact independent old envelope in primary or backup: %d" % fault)
			s.check(RunSaveCodec.encode(recovered) == RunSaveCodec.encode(expected_old), "new store recovers whole old state at failed disk stage: %d" % fault)
			if RunSaveCodec.encode(recovered) != RunSaveCodec.encode(expected_old):
				for key: String in expected_old:
					if JSON.stringify(recovered.get(key)) != JSON.stringify(expected_old[key]):
						print("[StoryDurableChecks] recovery mismatch at fault %d component %s" % [fault, key])
		_cleanup(fault_path)
	s.check(events["count"] == 0 and _live() == before and var_to_bytes(next) == input_before, "all success/future/stale/IO failure paths keep live owners, source input and observers unchanged")
	GameState.run_save_requested.disconnect(on_simple)
	Progression.credits_changed.disconnect(on_credits)
	Progression.story_transaction_committed.disconnect(on_id)
	StoryItems.acquired.disconnect(on_item)
	StoryItems.transferred.disconnect(on_item)
	Story.scene_finished.disconnect(on_id)
	Story.request_settled.disconnect(on_request)
	EventBus.lives_changed.disconnect(on_lives)
	_cleanup(path)
