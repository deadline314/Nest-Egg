extends "res://tools/ch2_flow_probe.gd"
## 第二章死亡與跨程序讀檔探針（ST-19）：每個模式都在獨立的程序裡從真正的 Main 進入，存檔放在 --save-dir。
## 用法：godot --path . res://tools/ch2_resume_probe.tscn -- --mode=write|continue --save-dir=<絕對路徑> --out=<截圖資料夾>
##   write：新遊戲後帶著第一章收尾的結果走進第二章早上：和老 K 結算、修收音機、上屋頂拿查核證、在代收處代墊四十；
##          接著在公眾攤道死一次，從檢查點重來後款項收據、文件與進度都不重算也不消失；最後像玩家一樣退出（會存檔）。
##   continue：另一個程序按「繼續遊戲」：回到公眾攤道，早上、簡報與代收處都不重播，七百二十與四十各只記一次，
##          文件還在手上、任務停在下一步；再把市集的線索收完，證明讀檔後還能往下推。

const MARKET := "res://data/levels/ch2_market.tres"
const LIMIT_MSEC := 120000
## 讀檔後不該再播的段落（已經看過或已經結算）。
const DONE_SCENES: Array[StringName] = [&"ch2_s01_morning", &"ch2_t_s01_settle", &"ch2_t_s02_power", &"ch2_t_s03_brief", &"ch2_t_s06_open"]
## 早上結算、代墊四十、修好收音機（支線獎勵）各一筆，依編號排序。
const RECEIPTS: Array[StringName] = [&"ch1.commission.settled", &"ch2.market_advance", &"ch2.sq4_radio"]
const DOCUMENTS: Array[StringName] = [&"ch2_check_card", &"ch2_evidence_receipt", &"ch2_radio_clip"]

var _mode := ""
var _save_dir := ""
var _main: Node
var _played: Array[StringName] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--save-dir="):
			_save_dir = arg.trim_prefix("--save-dir=")
	if _mode not in ["write", "continue"] or not _save_dir.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_save_dir) != OK:
		push_error("[Ch2ResumeProbe] 需要 --mode=write|continue 與可寫入的絕對路徑 --save-dir")
		get_tree().quit(2)
		return
	super._ready()


func _main_level() -> Level:
	var screen: Variant = _main.get("_screen") if is_instance_valid(_main) else null
	return screen as Level if screen is Level else null


func _wait_level(path: String, other_than: Level = null) -> bool:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < deadline:
		var level := _main_level()
		if level != null and level != other_than and level.data.resource_path == path and level.player != null and level.is_inside_tree():
			return true
		await _settle(1)
	return false


## 區域切換走 Main 的出入口路由（會存檔），而不是探針自己換關卡。
func _enter(area: String, near := Vector2.INF) -> void:
	var path := level_pattern % area
	var current := _main_level()
	if current == null or current.data.resource_path != path:
		GameState.pending_portal = &""
		_main.call("_on_area_requested", path)
		_check(await _wait_level(path, current), "Main routes into %s" % area)
	_level = _main_level()
	await _settle(30)
	for i in STEP_LIMIT:
		if not Story.is_cinematic_active():
			break
		Story.skip_cinematic()
		await _settle(4)
	if near != Vector2.INF:
		_level.player.global_position = near
		await _settle(20)


func _receipts() -> Array:
	var ledger: Dictionary = Progression.snapshot().get("story_transactions", {})
	var ids: Array = (ledger.get("receipts", {}) as Dictionary).keys()
	ids.sort()
	return ids


func _run() -> void:
	_shots = {}
	Story.scene_started.connect(func(id: StringName, _mode_name: StringName) -> void: _played.append(id))
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.set("_run_store", RunSaveStore.new(_save_dir.path_join("slot.json")))
	add_child(_main)
	await _settle(30)
	if _mode == "write":
		await _write()
	else:
		await _continue()
	print("CH2_RESUME_PROBE mode=%s failures=%d" % [_mode, _failures])
	_main.call("_quit", 1 if _failures > 0 else 0)


func _write() -> void:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	var started := false
	while Time.get_ticks_msec() < deadline and _main_level() == null:
		if not started and not bool(_main.call("_route_pending")):
			_main.call("_on_start_requested", GameState.difficulties[1])
			started = _main.get("_active_run")
		await _settle(30)
	_check(_main_level() != null, "a new game from Main enters the first area")
	# 第一章收尾的真實結果（宵夜留下、初次建檔已做過），再從當舖的早上開始。
	for done in [&"ch1_complete", &"ch1_handoff_done", &"ch1_supper_done", &"ledger_disk_obtained", &"knows_ali_address", &"ch1_first_death_done"]:
		GameState.set_flag(done)
	await _enter("pawnshop")
	await _talk(&"ch2_old_k", ["settle"])
	await _talk(&"ch2_radio", ["antenna", "power", "antenna", "speaker", "middle", "save"])
	await _enter("rooftop")
	await _talk(&"ch2_egret")
	await _enter("market_gate")
	await _talk(&"ch2_patroller")
	await _enter("market")
	await _talk(&"ch2_vig", ["pay", "confirm"])
	_check(_receipts() == RECEIPTS.map(func(id: StringName) -> String: return String(id)),
			"before dying the ledger holds the settlement, the advance and the radio reward (%s)" % [_receipts()])
	var before := {"receipts": _receipts(), "deaths": GameState.deaths, "brief": GameState.has_flag(&"ch2_brief_done"),
			"contact": GameState.has_flag(&"ch2_market_contact_done")}
	_check(DOCUMENTS.all(func(id: StringName) -> bool: return StoryItems.holds(id)), "the check card, receipt copy and radio clip are in hand")
	# 公眾攤道死一次：死亡畫面上按「立即再挑戰」，Main 從檢查點重新載入這一區。
	var dead_level := _level
	var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"probe")
	lethal.ignore_invulnerability = true
	_level.player.health.take_damage(lethal)
	var screen: DeathScreen = null
	for i in STEP_LIMIT:
		screen = _find_death_screen()
		if screen != null:
			break
		await get_tree().physics_frame
	_check(screen != null, "dying in the market shows the death screen")
	if screen != null:
		await _settle(30)
		screen.retry_requested.emit()
	# 從檢查點重來：檢查點在哪一區就回哪一區（這一章市集沒有自己的檢查點時回到最後一個）。
	var retry_path := GameState.checkpoint_level_path if GameState.has_checkpoint and not GameState.checkpoint_level_path.is_empty() else MARKET
	_check(await _wait_level(retry_path, dead_level), "retry reloads the checkpoint area %s" % retry_path.get_file())
	_level = _main_level()
	await _settle(60)
	_check(GameState.deaths == int(before["deaths"]) + 1, "the death is counted once")
	_check(_receipts() == before["receipts"], "dying neither repeats nor drops a story payment (%s)" % [_receipts()])
	_check(GameState.has_flag(&"ch2_brief_done") and GameState.has_flag(&"ch2_market_contact_done") and DOCUMENTS.all(func(id: StringName) -> bool: return StoryItems.holds(id)),
			"progress and documents survive the death")
	_check(_object(&"ch2_vig") != null and Story.resolve_dispatch(&"ch2_dispatch_vig") != &"ch2_t_s06_open", "the collection office does not restart the advance after the retry")
	await _settle(30)
	_capture("ST-19-resume-after-death")
	print("CH2_RESUME_WRITE level=%s deaths=%d receipts=%s" % [_level.data.resource_path, GameState.deaths, _receipts()])


func _continue() -> void:
	var store := _main.get("_run_store") as RunSaveStore
	var data: Dictionary = store.read()
	_check(not data.is_empty(), "the previous process left a readable save")
	var saved_credits := int((data.get("progression", {}) as Dictionary).get("credits", -1))
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < deadline and bool(_main.call("_route_pending")):
		await _settle(10)
	_main.call("_on_continue_requested")
	var saved_level := str(data.get("level", ""))
	_check(await _wait_level(saved_level), "continue lands back in the saved area %s" % saved_level.get_file())
	_level = _main_level()
	await _settle(120)
	_capture("ST-19-resume-continue")
	_check(Progression.credits == saved_credits, "credits come back exactly as saved (%d)" % Progression.credits)
	_check(_receipts() == RECEIPTS.map(func(id: StringName) -> String: return String(id)), "each story payment is recorded once (%s)" % [_receipts()])
	_check(DOCUMENTS.all(func(id: StringName) -> bool: return StoryItems.holds(id)), "the documents are still in hand")
	_check(GameState.deaths == 1, "the death from the previous process is remembered")
	_check(not _played.any(func(id: StringName) -> bool: return DONE_SCENES.has(id)), "no finished scene replays on continue (played %s)" % [_played])
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var open_main := catalog.list_for("ch2_heron", "main", false, GameState.world_flags)
	_check(catalog.issues.is_empty() and not open_main.is_empty(), "chapter 2 main quests are still open after continue")
	# 讀檔後繼續往下：回公眾攤道收完租攤合約與榕樹的故事。
	await _enter("market")
	await _talk(&"ch2_rent_window")
	await _talk(&"ch2_banyan")
	_check(GameState.has_flag(&"ch2_evidence_contract") and GameState.has_flag(&"ch2_banyan_heard"), "the market clues can still be collected after continue")
	await _enter("pawnshop")
	var credits := Progression.credits
	await _talk(&"ch2_old_k")
	_check(Progression.credits == credits and _receipts().size() == RECEIPTS.size(), "Old K does not pay the 720 again after continue")
