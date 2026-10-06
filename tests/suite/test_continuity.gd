class_name ContinuitySuite
extends TestSuite
## 劇情與流程的連續性檢查（NE-217）：旗標只讀不寫／拼字相近／只寫不讀的偵測、孤兒場景偵測（用假資料驗證偵測本身會抓到），
## 然後對真實資料（全部章節的劇本、關卡、出入口、死亡場景表）執行：不能有錯誤；警告印出來讓人看。
## 死亡矩陣：第一次死亡有沒有電話亭／已經有復原點／旗標遺失／診間場景檔遺失，各走一遍並斷言結果。

const BOOTH_AREA := "res://data/levels/ch1_booth_alley.tres"
const STALL_AREA := "res://data/levels/ch1_stall.tres"
const SEEN_FLAG := &"ch1_first_death_done"


func run() -> void:
	var previous_auto := Story.auto_skip
	_test_detects_flag_problems()
	_test_detects_orphans()
	_test_real_data()
	await _test_death_matrix()
	Story.auto_skip = previous_auto
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()


# ---------------------------------------------------------------------------
# 偵測本身（假資料）
# ---------------------------------------------------------------------------

func _test_detects_flag_problems() -> void:
	var scenes := {
		"a": {"set_flags": ["door_open", "intro_seen_flag"]},
		"b": {"set_flags": ["door_opne"]},
	}
	var deaths := {"c1": [{"scene": "a", "unless_flag": "never_written_flag"}]}
	var files := {"res://x.tres": 'requires_flag = &"door_open"', "res://y.gd": 'GameState.has_flag(&"ghost_flag_x")'}
	var table := ContinuityAudit.flag_table(scenes, deaths, files)
	var result := ContinuityAudit.flag_problems(table)
	var errors: PackedStringArray = result["errors"]
	var warnings: PackedStringArray = result["warnings"]
	check(_any(errors, "never_written_flag"), "a flag that is only read is an error (death scene table)")
	check(_any(errors, "ghost_flag_x"), "a flag that is only read is an error (code)")
	check(_any(errors, "door_open") and _any(errors, "door_opne"), "near-identical flag names are reported as a likely typo")
	check(_any(warnings, "intro_seen_flag"), "a flag that is only written is a warning")
	check(not _any(warnings, "door_open「") , "a flag that is written and read is clean")
	var clean := ContinuityAudit.flag_problems(ContinuityAudit.flag_table({"a": {"set_flags": ["k_one_flag"]}}, {}, {"res://p.tres": 'requires_flag = &"k_one_flag"'}))
	check((clean["errors"] as PackedStringArray).is_empty() and (clean["warnings"] as PackedStringArray).is_empty(), "a consistent write/read pair is clean")
	check(ContinuityAudit.distance("kitten", "sitting") == 3 and ContinuityAudit.distance("same", "same") == 0, "edit distance is correct")
	check(ContinuityAudit.flag_problems({"a1": {"writes": ["x"], "reads": ["y"]}, "a2": {"writes": ["x"], "reads": ["y"]}})["errors"].is_empty(),
			"short names such as a1/a2 are not compared by spelling")


func _test_detects_orphans() -> void:
	var scenes := {"used_by_level": {}, "used_by_then": {}, "chain_head": {"then": "used_by_then"}, "lonely": {}, "in_table": {}}
	var refs := ContinuityAudit.scene_references(scenes, {"c": [{"scene": "in_table"}]}, {}, {"res://l.tres": 'intro_scene = &"used_by_level"'})
	var orphans := ContinuityAudit.orphan_scenes(refs)
	check(orphans == PackedStringArray(["chain_head", "lonely"]), "orphans are found, referenced scenes are not (%s)" % [orphans])


func _any(list: PackedStringArray, needle: String) -> bool:
	for item in list:
		if item.contains(needle):
			return true
	return false


# ---------------------------------------------------------------------------
# 真實資料
# ---------------------------------------------------------------------------

func _test_real_data() -> void:
	var view := Story.audit_data()
	var table := ContinuityAudit.flag_table(view["scenes"], view["death"], ContinuityAudit.read_text_files())
	var result := ContinuityAudit.flag_problems(table)
	var errors: PackedStringArray = result["errors"]
	for message in errors:
		check(false, "flag audit: %s" % message)
	check(errors.is_empty(), "the real flag table has no read-without-write flags and no near-duplicate names")
	for message in result["warnings"] as PackedStringArray:
		print("WARN ", message)
	check(table.size() > 0, "the audit finds flags in the real data (%d)" % table.size())
	# 孤兒場景：劇本檔本身不算引用。
	var files := ContinuityAudit.read_text_files(ContinuityAudit.SCAN_ROOTS, ["res://data/story/"])
	var orphans := ContinuityAudit.orphan_scenes(ContinuityAudit.scene_references(view["scenes"], view["respawn"], view["death"], files))
	for id in orphans:
		print("WARN 場景「%s」沒有任何地方引用" % id)
	check(orphans.size() < Story.scene_ids().size(), "not every scene is an orphan (%d of %d)" % [orphans.size(), Story.scene_ids().size()])
	# 每個會寫旗標的場景，旗標在場景開始時還沒寫、結束後才有。
	GameState.start_new_run(GameState.difficulties[1])
	for scene_id: String in view["scenes"]:
		for flag: String in Story._scene_set_flags(StringName(scene_id)):
			check(not GameState.has_flag(StringName(flag)), "%s: flag %s is not set before the scene finishes" % [scene_id, flag])
	Story._apply_scene_flags(&"ch1_c09_wake")
	check(GameState.has_flag(SEEN_FLAG), "finishing the scene writes its flag")
	GameState.start_new_run(GameState.difficulties[1])


# ---------------------------------------------------------------------------
# 死亡矩陣
# ---------------------------------------------------------------------------

## 情境：[說明, 先設旗標?, 先有復原點?, 區域, 死亡次數, 預期播診間?, 預期登記復原點?]
func _test_death_matrix() -> void:
	Story.auto_skip = true
	var cases: Array[Dictionary] = [
		{"name": "first death, no booth used", "flag": false, "checkpoint": false, "area": BOOTH_AREA, "deaths": 1, "clinic": true, "registers": true},
		{"name": "first death, booth already used", "flag": false, "checkpoint": true, "area": BOOTH_AREA, "deaths": 1, "clinic": true, "registers": false},
		{"name": "later death", "flag": true, "checkpoint": true, "area": BOOTH_AREA, "deaths": 2, "clinic": false, "registers": false},
		{"name": "flag lost after several deaths", "flag": false, "checkpoint": true, "area": BOOTH_AREA, "deaths": 4, "clinic": true, "registers": false},
		{"name": "first death in an area without booths", "flag": false, "checkpoint": false, "area": STALL_AREA, "deaths": 1, "clinic": true, "registers": false},
	]
	for case in cases:
		Story.reset_progress()
		GameState.start_new_run(GameState.difficulties[1])
		var started: Array[StringName] = []
		var on_started := func(id: StringName, _mode: StringName) -> void: started.append(id)
		Story.scene_started.connect(on_started)
		var level := await spawn_level(load(str(case["area"])) as LevelData)
		if bool(case["flag"]):
			GameState.set_flag(SEEN_FLAG)
		if bool(case["checkpoint"]):
			GameState.set_checkpoint(level._layout.player_start, {}, {}, Progression.snapshot())
		GameState.deaths = int(case["deaths"]) - 1
		var retried := [false]
		level.retry_requested.connect(func() -> void: retried[0] = true)
		var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"grunt_shot")
		lethal.ignore_invulnerability = true
		level.player.health.take_damage(lethal)
		var guard := 0
		var screens: Array = []
		while not retried[0] and screens.is_empty() and guard < 400:
			await frames(1)
			screens = level.get_children().filter(func(n: Node) -> bool: return n is DeathScreen)
			guard += 1
		var name_text := str(case["name"])
		check(started.has(&"ch1_c09_wake") == bool(case["clinic"]), "%s: clinic scene played = %s" % [name_text, case["clinic"]])
		if bool(case["clinic"]):
			check(retried[0] and screens.is_empty(), "%s: respawns right after the scene, no death screen" % name_text)
			check(GameState.has_flag(SEEN_FLAG), "%s: the flag is written after the scene" % name_text)
		else:
			check(not screens.is_empty() and not retried[0], "%s: normal death screen, no auto respawn" % name_text)
		var registered := GameState.has_checkpoint and GameState.checkpoint_notice_pending
		check(registered == bool(case["registers"]), "%s: booth newly registered = %s" % [name_text, case["registers"]])
		Story.scene_started.disconnect(on_started)
		await end_level(level)
	# 診間場景檔遺失：不卡住、照樣重生並記錄。
	GameState.start_new_run(GameState.difficulties[1])
	var level := await spawn_level(load(BOOTH_AREA) as LevelData)
	var retried := [false]
	level.retry_requested.connect(func() -> void: retried[0] = true)
	await level._run_death_scene({"scene": "test_no_such_scene", "register_checkpoint": true})
	check(retried[0], "a missing death scene does not block the respawn")
	await end_level(level)
	GameState.start_new_run(GameState.difficulties[1])
