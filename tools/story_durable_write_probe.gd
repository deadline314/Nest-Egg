extends Node
## Independent process persistence probe. Never creates or quits through Main.
## Root owns process allocation and kills the writer after barrier.json appears.

const Checks = preload("res://tests/helpers/story_durable_write_checks.gd")
const PHASES := ["temp_closed", "backup_removed", "primary_rotated", "primary_committed"]
var _directory := ""
var _mode := ""
var _phase := ""
var _expect := ""
var _alias := ""
var _timeout := 15000
var _failures := 0

class BarrierStore extends RunSaveStore:
	var scope := ""
	var stop_phase: DurablePhase = DurablePhase.TEMP_CLOSED
	var timeout_msec := 15000
	var timed_out := false
	var reached := false

	func _durable_phase(phase: DurablePhase, absolute: String) -> void:
		if absolute != scope or phase != stop_phase:
			return
		reached = true
		var barrier := FileAccess.open(absolute.get_base_dir().path_join("barrier.json"), FileAccess.WRITE)
		if barrier == null:
			timed_out = true
			return
		barrier.store_string(JSON.stringify({"version": 1, "pid": OS.get_process_id(), "phase": phase, "slot": absolute}))
		barrier.flush()
		barrier.close()
		# Intentional bounded test-only block at the precise disk instruction.
		# External controller force-terminates this process, then starts fresh read.
		var until := Time.get_ticks_msec() + timeout_msec
		while Time.get_ticks_msec() < until:
			OS.delay_msec(10)
		timed_out = true


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-dir="):
			_directory = argument.trim_prefix("--save-dir=").replace("\\", "/")
		elif argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--phase="):
			_phase = argument.trim_prefix("--phase=")
		elif argument.begins_with("--expect="):
			_expect = argument.trim_prefix("--expect=")
		elif argument.begins_with("--alias="):
			_alias = argument.trim_prefix("--alias=")
		elif argument.begins_with("--barrier-timeout-ms="):
			var text := argument.trim_prefix("--barrier-timeout-ms=")
			if not text.is_valid_int() or int(text) < 1000 or int(text) > 30000:
				_finish(2, "timeout must be integer 1000..30000")
				return
			_timeout = int(text)
	var canonical := _directory.simplify_path().trim_suffix("/")
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var user := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	if not _directory.is_absolute_path() or canonical != _directory or not canonical.get_file().begins_with("ne-story-durable-") or canonical.to_lower().begins_with(project.to_lower()) or canonical.to_lower().begins_with(user.to_lower()) or canonical.get_base_dir().is_empty():
		_finish(2, "--save-dir must be canonical absolute isolated ne-story-durable-* directory outside project/user")
		return
	if _mode not in ["seed", "write", "read", "alias_check"] or (_mode == "write" and _phase not in PHASES) or (_mode == "read" and _expect not in ["old", "new"]) or (_mode == "alias_check" and _alias.is_empty()):
		_finish(2, "mode=seed/write/read/alias_check; write phase/read expect/alias kind required")
		return
	_run.call_deferred()


func _run() -> void:
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	var slot := _directory.path_join("slot.json")
	var owner_path := _directory.path_join("probe-owner.json")
	if _mode == "seed":
		if DirAccess.dir_exists_absolute(_directory) or FileAccess.file_exists(_directory):
			_finish(2, "seed requires a new absent isolated directory; no cleanup of existing data")
			return
		if DirAccess.make_dir_recursive_absolute(_directory) != OK:
			_finish(2, "cannot create isolated directory")
			return
		var fixture := Checks.fixture()
		if not fixture.has("data"):
			_finish(2, "canonical fixture preparation failed")
			return
		var old := RunSnapshot.capture(Checks.FIRST, {"position": [80, 160], "health": 3, "world": {}, "loadout": {}})
		var store := RunSaveStore.new(slot)
		store.validator = RunSnapshot.prepare
		if not store.write(old, true):
			_finish(2, "cannot seed real legacy slot")
			return
		var candidate := store.prepare_existing_write(fixture["data"])
		if not candidate.has("data"):
			_finish(2, "prepared existing writer rejected canonical candidate: " + candidate.get("error", "unknown"))
			return
		var prepared: RunSaveStore.PreparedExistingWrite = candidate["data"]
		if not _write(_directory.path_join("expected-old.json"), RunSaveCodec.encode(store.read())) or not _write(_directory.path_join("expected-new.json"), RunSaveCodec.encode(prepared.snapshot())) or not _write(owner_path, JSON.stringify({"version": 1, "directory": _directory})):
			_finish(2, "cannot write fixed probe manifests")
			return
		print("[StoryDurableProbe] Hardlink crash variant: after seed EOF, root os.link(%s, %s) and verifies os.path.samefile; then normal write phase/external kill/fresh read." % [slot, slot + ".tmp"])
		_finish(0, "seed complete; seven canonical transactions/custody persistence fixture only")
		return
	var owner := _read_text(owner_path, 2048)
	var parsed: Variant = JSON.parse_string(owner)
	if not parsed is Dictionary or parsed.get("version") != 1 or parsed.get("directory") != _directory:
		_finish(2, "missing matching probe-owner manifest; no slot mutation")
		return
	if _mode == "alias_check":
		var candidate := RunSaveCodec.decode(_read_text(_directory.path_join("expected-new.json"), RunSaveCodec.MAX_BYTES))
		if not candidate.has("data"):
			_finish(2, "alias new manifest invalid")
			return
		var result := Checks.check_external_alias(slot, _alias, candidate["data"])
		_finish(0 if result.get("valid", false) else 1, "REAL alias result " + JSON.stringify(result))
		return
	if _mode == "write":
		if FileAccess.file_exists(_directory.path_join("barrier.json")):
			_finish(2, "barrier already exists; use a new seed directory")
			return
		var data := RunSaveCodec.decode(_read_text(_directory.path_join("expected-new.json"), RunSaveCodec.MAX_BYTES))
		if not data.has("data"):
			_finish(2, "new candidate manifest invalid")
			return
		var store := BarrierStore.new(slot)
		store.scope = slot
		match _phase:
			"temp_closed": store.stop_phase = RunSaveStore.DurablePhase.TEMP_CLOSED
			"backup_removed": store.stop_phase = RunSaveStore.DurablePhase.BACKUP_REMOVED
			"primary_rotated": store.stop_phase = RunSaveStore.DurablePhase.PRIMARY_ROTATED
			"primary_committed": store.stop_phase = RunSaveStore.DurablePhase.PRIMARY_COMMITTED
		store.timeout_msec = _timeout
		var ready := store.prepare_existing_write(data["data"])
		if not ready.has("data"):
			_finish(2, "write preparation rejected: " + ready.get("error", "unknown"))
			return
		var outcome := store.commit_existing_write(ready["data"])
		# A successfully completed process is not a crash-window test.
		_finish(3, "external kill did not occur; reached=%s timed_out=%s committed=%s" % [store.reached, store.timed_out, outcome.committed])
		return
	var expected := RunSaveCodec.decode(_read_text(_directory.path_join("expected-" + _expect + ".json"), RunSaveCodec.MAX_BYTES))
	if not expected.has("data"):
		_finish(2, "expected manifest invalid")
		return
	var reader := RunSaveStore.new(slot)
	reader.validator = RunSnapshot.prepare
	var actual := reader.read()
	var normalized := RunSnapshot.prepare(expected["data"])
	_check(normalized.has("data") and not actual.is_empty(), "fresh process reads supported whole run")
	if normalized.has("data") and not actual.is_empty():
		for key: String in ["state", "progression", "story", "navigation", "runtime", "cinematic", "cinematic_context", "chapter_complete", "level", "difficulty", "release", "saved_at", "version"]:
			_check(JSON.stringify(actual.get(key)) == JSON.stringify(normalized["data"].get(key)), "all-component field matches expected " + key)
		_check(not Progression.prepare_install(actual["progression"]).has("error"), "fresh canonical ledger/progression proof")
		_check(not StoryItems.prepare_install(actual["story"]["items"]).has("error"), "fresh custody proof")
		_check(RunSaveCodec.encode(actual) == RunSaveCodec.encode(normalized["data"]), "entire normalized snapshot matches, including compatible fields")
	_finish(0 if _failures == 0 else 1, "fresh read checks failures=%d expected=%s; no Main/save/live install" % [_failures, _expect])


func _read_text(path: String, limit: int) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	if file.get_length() > limit:
		file.close()
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("[StoryDurableProbe] %s %s" % ["PASS" if ok else "FAIL", label])


func _finish(code: int, message: String) -> void:
	print("[StoryDurableProbe] " + message)
	get_tree().quit(code)
