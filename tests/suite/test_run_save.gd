class_name RunSaveSuite
extends TestSuite
## 整輪格式／磁碟故障回歸；工具 probe 另驗兩個真正獨立程序。

const FIRST := "res://data/levels/ch1_pawnshop.tres"
var directory := "user://ne230-suite"


func run() -> void:
	var previous_gamepad := AimInput.using_gamepad
	var previous_direction := AimInput._last_stick_dir
	var previous_msec := AimInput._last_stick_msec
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	var valid := RunSnapshot.capture(FIRST, {"position": [100, 160], "health": 4, "world": {}, "loadout": {}})
	print("[RunSaveSuite] initial preparation: %s" % RunSnapshot.prepare(valid).get("error", "OK"))
	check(RunSnapshot.prepare(valid).has("data"), "valid whole-run schema prepares before applying")
	var detached_main: Node = load("res://game/main.gd").new()
	var freed_level := Level.new()
	detached_main.set("_screen", freed_level)
	detached_main.set("_active_run", true)
	detached_main.set("_cinematic", "st22_freed_owner")
	detached_main.set("_cinematic_request", 23)
	detached_main.set("_cinematic_entry", valid.duplicate(true))
	freed_level.free()
	detached_main.call("_on_presentation_cancelled", &"st22_freed_owner", {}, &"leave", 23)
	check(detached_main.get("_cinematic") == "" and detached_main.get("_cinematic_entry").is_empty(), "matching delayed cancellation safely clears entry after screen owner was freed")
	detached_main.free()
	var legacy_context := valid.duplicate(true)
	legacy_context.erase("cinematic_context")
	legacy_context["future_same_version"] = {"retained": true}
	var legacy_prepared: Dictionary = RunSnapshot.prepare(legacy_context)["data"]
	check(legacy_prepared["cinematic_context"].is_empty() and legacy_prepared["future_same_version"]["retained"], "legacy context absent and unknown same-version fields remain compatible")
	var context := {"framing_source": "person", "source_id": "npc:fixture@1,2", "talk_index": 2, "request": 500, "bar_pose": 0.8}
	var context_roundtrip: Dictionary = JSON.parse_string(JSON.stringify(Story.presentation_context(context)))
	var sanitized := Story.presentation_context(context_roundtrip)
	check(sanitized.get("talk_index") == 2 and sanitized.size() == 3, "JSON numeric NPC index becomes pure int while runtime handle and bar pose are excluded")
	check(Story.presentation_context({"framing_source": "object", "talk_index": -1}).is_empty(), "negative NPC index cannot enter resume context")
	check(Story.presentation_context({"framing_source": "radio"}).is_empty(), "only three declared presentation sources can enter snapshot")
	var older := valid.duplicate(true)
	older["runtime"]["facing"] = -1
	check(RunSaveCodec.vector(RunSnapshot.prepare(older)["data"]["runtime"]["aim_dir"]) == Vector2.LEFT, "missing legacy aim falls back to saved facing")
	AimInput.using_gamepad = false
	AimInput.restore_direction(Vector2(-4, 0))
	check(AimInput._last_stick_dir == Vector2.LEFT and not AimInput.using_gamepad, "restore aim normalizes without switching device")
	AimInput.restore_direction(Vector2(NAN, 0))
	check(AimInput._last_stick_dir == Vector2.LEFT, "nonfinite restore direction leaves existing input unchanged")
	var encoded := RunSaveCodec.encode(valid)
	check(RunSaveCodec.decode(encoded).has("data"), "checksum envelope round-trips JSON data")
	check(not RunSaveCodec.decode(encoded.left(encoded.length() / 2)).has("data"), "truncated envelope rejected")
	check(not RunSaveCodec.decode(encoded.replace("demo-0.1", "demo-0.2")).has("data"), "payload edits invalidate checksum")
	for malformed: String in ['{}', '{"version":null}', '{"version":"1"}', '{"version":1.5}']:
		var rejected := RunSaveCodec.decode(malformed)
		check(rejected.has("error") and not rejected.get("unknown_version", false), "malformed envelope version allows recovery: " + malformed)
	var malformed_snapshot := valid.duplicate(true)
	malformed_snapshot.erase("version")
	check(not RunSnapshot.prepare(malformed_snapshot).get("unknown_version", false), "missing snapshot version is corruption rather than future format")
	malformed_snapshot = valid.duplicate(true)
	malformed_snapshot["release"] = null
	check(not RunSnapshot.prepare(malformed_snapshot).get("unknown_version", false), "malformed release is corruption rather than future format")
	check(not RunSaveCodec.validate_tree({"hp": NAN}).is_empty(), "NaN rejected before serialization")
	check(not RunSaveCodec.validate_tree({"hp": INF}).is_empty(), "infinite values rejected before serialization")
	check(not RunSaveCodec.validate_tree({"node": runner}).is_empty(), "objects cannot enter save data")
	var cyclic: Array = []
	cyclic.append(cyclic)
	check(RunSaveCodec.encode({"cycle": cyclic}).is_empty(), "cyclic raw data rejects before JSON serialization")
	cyclic.clear()
	var shared := range(16)
	var fanout: Array = []
	for i in 16:
		fanout.append(shared)
	check(not RunSaveCodec.validate_tree({"fanout": fanout}, 32).is_empty(), "high fanout rejects before pending nodes exceed tightened budget")
	var long_path := "run"
	for i in 16:
		long_path = RunSaveCodec._diagnostic_path(long_path, "x".repeat(1020) + "tail")
	check(long_path.length() <= RunSaveCodec.MAX_DIAGNOSTIC_PATH and long_path.ends_with("tail"), "diagnostic paths stay bounded and retain latest key suffix")
	check(not RunSaveCodec.nesting_safe("[".repeat(17) + "0" + "]".repeat(17)), "deep JSON rejected before parser")
	check(RunSaveCodec.nesting_safe('{"text":"[\\\"{}]"}'), "quoted escaped brackets do not count as nesting")
	check(not RunSaveCodec.decode(" ".repeat(RunSaveCodec.MAX_BYTES + 1)).has("data"), "oversized files rejected")
	var bad := valid.duplicate(true)
	bad["progression"] = []
	check(RunSnapshot.prepare(bad).has("error"), "missing component cannot partially overwrite current run")
	bad = valid.duplicate(true)
	bad["story"]["items"].erase("owned")
	check(RunSnapshot.prepare(bad).has("error"), "missing owned-item container cannot silently erase mainline items")
	bad = valid.duplicate(true)
	bad["level"] = "user://foreign.tres"
	var foreign := RunSnapshot.prepare(bad)
	check(foreign.has("data") and foreign["data"]["level"] == CampaignEdition.current().first_level and not foreign["data"].get("notices", []).is_empty(), "level paths restricted to project level resources; foreign path falls back to start with notice")
	bad = valid.duplicate(true)
	bad["runtime"]["loadout"] = {"weapons": ["res://autoload/story.gd"], "mag": ["bad"], "consumables": {"med_injector": []}}
	var repaired: Dictionary = RunSnapshot.prepare(bad)["data"]
	check(repaired["runtime"]["loadout"]["weapons"][0] == "", "wrong weapon type cannot load script")
	check(repaired["runtime"]["loadout"]["mag"][0] == 0, "invalid ammo repairs to bounded number")
	bad = valid.duplicate(true)
	bad["runtime"]["area"] = []
	check(RunSnapshot.prepare(bad).has("error"), "invalid current-area container rejected")
	bad = valid.duplicate(true)
	bad["runtime"]["health"] = 0
	check(RunSnapshot.prepare(bad).has("error"), "unsettled zero-health state cannot become live player")
	Progression.restore({"credits": NAN, "pawned": {"med_injector": INF}})
	check(Progression.credits == 0 and Progression.total_pawned() == 0, "standalone progression restore handles nonfinite scalars")
	GameState.restore_story_progress({"deaths": INF})
	check(GameState.deaths == 0, "standalone story death count handles infinity")
	var store := RunSaveStore.new(directory.path_join("unit.json"))
	store.validator = RunSnapshot.prepare
	check(store.write(valid, true), "first complete snapshot writes")
	valid["progression"]["credits"] = 123
	check(store.write(valid), "second snapshot rotates valid backup")
	check(store.read()["progression"]["credits"] == 123, "primary is latest complete transaction")
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	check(store.read()["progression"]["credits"] == 0 and not store.unknown_version, "valid JSON corrupted primary falls back to healthy backup")
	check(store.write(valid), "corrupt empty object primary repairs without future-format authorization")
	file = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(store.read()["progression"]["credits"] == 0, "corrupt primary restores previous complete backup")
	check(not store.issues.is_empty() and store.issues[-1].contains(store.path), "backup recovery names real path")
	check(store.write(valid), "repair keeps valid backup and writes complete primary")
	file = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string('{"version":999}')
	file.close()
	check(not store.write(valid), "unknown-version primary is protected even without prior read")
	check(FileAccess.get_file_as_string(store.path).contains("999"), "unknown original remains untouched")
	var backup_only := RunSaveStore.new(directory.path_join("unknown_backup.json"))
	if FileAccess.file_exists(backup_only.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_only.path))
	file = FileAccess.open(backup_only.path + ".bak", FileAccess.WRITE)
	file.store_string('{"version":999}')
	file.close()
	check(not backup_only.write(valid), "unknown-version backup is protected without prior read or primary")
	check(FileAccess.get_file_as_string(backup_only.path + ".bak").contains("999"), "unknown backup remains unchanged")
	file = FileAccess.open(backup_only.path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(not backup_only.write(valid), "corrupt primary cannot overwrite its unknown-version backup")
	check(FileAccess.get_file_as_string(backup_only.path) == "{broken", "failed unknown-backup write also retains corrupt original")
	check(store.write(valid, true), "explicit new-game overwrite can replace unknown format")
	file = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string('{"version":999}')
	file.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(store.path + ".tmp"))
	check(not store.write(valid, true) and store.overwrite_authorized, "confirmed overwrite authorization survives first IO failure")
	check(FileAccess.get_file_as_string(store.path).contains("999"), "failed confirmed overwrite retains unknown original")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path + ".tmp"))
	check(store.write(valid) and not store.overwrite_authorized, "automatic retry uses prior authorization until first successful write")
	var failing := RunSaveStore.new(directory.path_join("unit.json/blocked.json"))
	check(not failing.write(valid), "write failure reports false, not fake success")
	check(store.read()["progression"]["credits"] == 123, "failed unrelated write does not mutate prior slot")
	valid["progression"]["credits"] = 7
	check(store.write(valid, true), "new run replaces current slot explicitly")
	file = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(store.read()["progression"]["credits"] == 7, "fresh-run backup cannot resurrect previous run")
	var rollback := RunSaveStore.new(directory.path_join("rollback.json"))
	rollback.validator = RunSnapshot.prepare
	valid["progression"]["credits"] = 41
	check(rollback.write(valid, true), "rollback fixture establishes a valid old run")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(rollback.path + ".bak"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(rollback.path + ".bak"))
	valid["progression"]["credits"] = 52
	check(not rollback.write(valid, true), "backup replacement failure is not reported as saved")
	check(rollback.read()["progression"]["credits"] == 41, "failure after replacing primary rolls back the old valid run")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(rollback.path + ".bak"))
	check(rollback.write(valid) and rollback.read()["progression"]["credits"] == 52, "delayed authorized retry installs new-run primary and matching backup")
	for phase in 4:
		var interrupted := RunSaveStore.new(directory.path_join("interrupted_%d.json" % phase))
		interrupted.validator = RunSnapshot.prepare
		valid["progression"]["credits"] = 41
		check(interrupted.write(valid, true), "interrupted fixture has old run: %d" % phase)
		valid["progression"]["credits"] = 99
		file = FileAccess.open(interrupted.path + ".freshbak", FileAccess.WRITE)
		file.store_string(RunSaveCodec.encode(valid))
		file.close()
		check(interrupted.read()["progression"]["credits"] == 41, "unmarked freshbak never becomes active new game: %d" % phase)
		var absolute := ProjectSettings.globalize_path(interrupted.path)
		check(interrupted._begin_new_run(absolute), "verified new-round marker installed: %d" % phase)
		if phase >= 1:
			DirAccess.rename_absolute(absolute, absolute + ".previous")
			DirAccess.rename_absolute(absolute + ".bak", absolute + ".previous.bak")
		if phase >= 2:
			DirAccess.copy_absolute(absolute + ".freshbak", absolute)
		if phase >= 3:
			DirAccess.rename_absolute(absolute + ".freshbak", absolute + ".bak")
		check(interrupted.read()["progression"]["credits"] == 99, "marked rename window recovers new round rather than archived old round: %d" % phase)
		file = FileAccess.open(interrupted.path, FileAccess.WRITE)
		file.store_string("{}")
		file.close()
		check(interrupted.read()["progression"]["credits"] == 99 and not FileAccess.file_exists(interrupted.path + ".newrun"), "recovery resolves marker and retains matching new-round backup: %d" % phase)
	var future_pending := RunSaveStore.new(directory.path_join("unknown_transaction.json"))
	future_pending.validator = RunSnapshot.prepare
	check(future_pending.write(valid, true), "future transaction fixture begins with valid slot")
	file = FileAccess.open(future_pending.path + ".freshbak", FileAccess.WRITE)
	file.store_string(RunSaveCodec.encode(valid))
	file.close()
	check(future_pending._begin_new_run(ProjectSettings.globalize_path(future_pending.path)), "future transaction fixture has legitimate matching marker")
	file = FileAccess.open(future_pending.path, FileAccess.WRITE)
	file.store_string('{"version":999}')
	file.close()
	check(future_pending.read().is_empty() and future_pending.unknown_version and FileAccess.get_file_as_string(future_pending.path).contains("999") and FileAccess.file_exists(future_pending.path + ".newrun"), "matching current freshbak cannot overwrite unknown-version primary during recovery")
	check(future_pending.write(valid, true) and future_pending.read()["progression"]["credits"] == 99, "explicit new-game authorization may replace protected pending future format")
	AimInput.using_gamepad = previous_gamepad
	AimInput._last_stick_dir = previous_direction
	AimInput._last_stick_msec = previous_msec
	check(AimInput.using_gamepad == previous_gamepad and AimInput._last_stick_dir == previous_direction and AimInput._last_stick_msec == previous_msec, "suite restores aim source direction and timestamp without polluting later suites")
	preload("res://tests/helpers/story_install_checks.gd").run(self)
	preload("res://tests/helpers/story_durable_write_checks.gd").run(self)
	preload("res://tests/helpers/run_restore_checks.gd").run(self)
	preload("res://tests/helpers/campaign_edition_checks.gd").run(self)
	preload("res://tests/helpers/required_item_checks.gd").run(self)
	await preload("res://tests/helpers/resume_portal_checks.gd").run(self)
	GameState.start_new_run(GameState.difficulties[1])
