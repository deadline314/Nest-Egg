extends Node
## NE-230 第二階段的兩程序驗收：每組 *_write 由真的主流程寫入後關閉程序，*_read 是另一個引擎程序冷啟動續玩。
##   prologue_write/read  序章不重播、探索／存檔點啟用、已開箱子與撿到的錢一致
##   growth_write/read    招式購買、任務獎勵（一次交易）關閉重開後不重複、不遺失
##   growth_death_write/read  買招式、領獎後在電話亭區真的死亡並當影格關閉：扣款一次、招式保留、獎勵不重領
##   repair_write/read    區域資源遺失與導覽損毀：保留成長與故事，退回可玩區域並提示
##   edition_end          序章至第一章：章末停在完成卡，存檔寫在自己的版本目錄
##   edition_next         序章至第二章（下一章用明確標示的 fixture）：接續第一章版的存檔，原檔不改
##   edition_again        序章至第二章再開一次：直接用自己的槽，不再從舊版匯入
##   edition_newer        只收錄序章的版本：看到較新版本存檔只提示，不讀不寫
## 用法：godot --headless --path . res://tools/run_continuity_probe.tscn -- --save-dir=<絕對隔離目錄> --mode=<模式> [--edition=<版本 id>]
## 存檔一律在 --save-dir/runs/<版本 id>/ 底下，絕不使用正式 user:// 槽。

const MainScript := preload("res://game/main.gd")
const Capture := preload("res://tools/viewport_capture.gd")
const FIRST := "res://data/levels/ch1_pawnshop.tres"
const DAWN := "res://data/levels/ch1_pawnshop_dawn.tres"
const FIXTURE_NEXT := "res://data/levels/level_02.tres"
const TECHNIQUE := &"technique_blade"
const REWARD := "res://data/story_transactions/ch1_commission_settled.tres"
const PAWN_ITEM := &"shield_cell"

var _failures := PackedStringArray()
var _checks := 0
var _directory := ""
var _mode := ""
var _edition_id := ""
## 有真實視窗時（Forward+）把關鍵畫面存成 PNG；無頭執行時略過。
var _capture_dir := ""
var _main: Node
var _closing := false
var _started_scenes: Array[StringName] = []
## fixture 改的是快取中的資源；持有引用，避免被釋放後從磁碟重讀成原樣。
var _fixture_levels: Array[LevelData] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save-dir="):
			_directory = argument.trim_prefix("--save-dir=")
		elif argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--edition="):
			_edition_id = argument.trim_prefix("--edition=")
		elif argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
	if _directory.is_empty() or not _directory.is_absolute_path() or _mode.is_empty():
		push_error("[ContinuityProbe] --save-dir 絕對隔離目錄與 --mode 必填")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	Transition.instant = true
	Enemy.activation_culling_enabled = false
	if not _edition_id.is_empty():
		var edition := CampaignEdition.current().describe(_edition_id)
		if edition == null:
			_check(false, "known edition id: %s" % _edition_id)
			await _finish()
			return
		CampaignEdition.override_current(edition)
	if _mode in ["edition_next", "edition_again"]:
		_install_next_chapter_fixture()
	Story.scene_started.connect(func(id: StringName, _mode_name: StringName) -> void: _started_scenes.append(id))
	_main = MainScript.new()
	_main.set("_run_store", RunSaveStore.new(_slot(CampaignEdition.current().id)))
	add_child(_main)
	await _frames(3)
	print("[ContinuityProbe] edition=%s slot=%s" % [CampaignEdition.current().id, (_main.get("_run_store") as RunSaveStore).path])
	match _mode:
		"prologue_write": await _prologue_write()
		"prologue_read": await _prologue_read()
		"growth_write": await _growth_write()
		"growth_read": await _growth_read()
		"growth_death_write": await _growth_death_write()
		"growth_death_read": await _growth_death_read()
		"repair_write": await _repair_write()
		"repair_read": await _repair_read()
		"edition_end": await _edition_end()
		"edition_next": await _edition_next()
		"edition_again": await _edition_again()
		"edition_newer": await _edition_newer()
		_: _check(false, "unknown probe mode")
	if not _closing:
		await _finish()


# --- 序章、探索、世界 -------------------------------------------------------

func _prologue_write() -> void:
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _frames(30)
	var level := _main.get("_screen") as Level
	_check(level != null and level.data.resource_path == FIRST, "formal new game enters the first area")
	if level == null:
		return
	_check(_started_scenes.has(level.data.intro_scene) and Story.was_seen(level.data.intro_scene), "opening scene played once in the first process")
	var navigation := QuestMapState.for_run()
	var keys := QuestMapIndex.for_chapter(level.data.chapter).checkpoint_keys
	_check(not keys.is_empty(), "chapter has real checkpoint keys")
	if not keys.is_empty():
		navigation.activated[keys[0]] = true
		navigation._touch()
	var broken := 0
	for node in level.get("_entities").get_children():
		if node is Breakable and broken == 0:
			node.health.kill(DamageInfo.create(99, Combat.Team.PLAYER, &"probe"))
			broken += 1
	_check(broken == 1, "real persistent box broken in first area")
	var credits_before := Progression.credits
	for node in level.get("_entities").get_children():
		if node is CreditPickup and node.cell != Vector2i(-1, -1):
			node._apply(level.player)
			node._consume()
			break
	await _frames(4)
	_check(navigation.explored.has(FIRST) and not navigation.explored[FIRST].is_empty(), "walking in the area reveals map cells")
	_check(Progression.credits >= credits_before, "picked cash is credited")
	_close_and_record()


func _prologue_read() -> void:
	var expected := _expected()
	Story.auto_skip = false  # 如果開場被重播，會停在演出上而被抓到。
	_main.call("_on_continue_requested")
	await _wait_level()
	await _frames(20)
	var level := _main.get("_screen") as Level
	_check(level != null and level.data.resource_path == FIRST, "second process continues in the saved area")
	if level == null:
		return
	_check(not _started_scenes.has(level.data.intro_scene) and Story.was_seen(level.data.intro_scene), "opening scene is not replayed after a real restart")
	var navigation := QuestMapState.for_run()
	var saved_cells: Dictionary = expected["navigation"]["explored"].get(FIRST, {})
	var restored_cells: Dictionary = navigation.explored.get(FIRST, {})
	_check(not saved_cells.is_empty() and saved_cells.keys().all(func(key: String) -> bool: return restored_cells.has(key)), "every explored cell survives the restart")
	_check(navigation.activated.keys() == expected["navigation"]["activated"].keys(), "activated checkpoints survive the restart")
	_check(navigation.pinned_id == expected["navigation"]["pinned_id"], "pinned quest id survives the restart")
	var broken := 0
	for node in level.get("_entities").get_children():
		if node is Breakable and node.is_broken:
			broken += 1
	_check(broken == 1, "opened box stays open, others stay closed")
	_check(Progression.credits == expected["progression"]["credits"], "credits equal the saved wallet")
	_check(GameState.story_progress_snapshot()["flags"] == expected["story"]["flags"], "story flags equal the saved story")


# --- 成長、任務獎勵 ---------------------------------------------------------

func _growth_write() -> void:
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _frames(20)
	var blade := load("res://data/weapons/melee/melee_blade.tres") as WeaponData
	var technique := Progression.find_upgrade(TECHNIQUE)
	Progression.add_credits(1000)
	var before := Progression.credits
	_check(Progression.buy_upgrade(blade, technique), "melee technique purchase completes")
	_check(Progression.credits == before - technique.cost, "technique charged exactly once")
	var reward := load(REWARD) as StoryTransactionData
	var granted := Progression.apply_story_transaction(reward)
	_check(granted.get("applied", false) and Progression.credits == before - technique.cost + reward.credits_delta, "quest reward credited once")
	# 真的當舖頁面：從背包拿走一件換錢與當票。
	var player := (_main.get("_screen") as Level).player
	var item := ConsumableBag.find(PAWN_ITEM)
	player.consumables.add(item)
	var held := player.consumables.count(PAWN_ITEM)
	var page := _pawn_page(player)
	_check(page._do_pawn(item) and player.consumables.count(PAWN_ITEM) == held - 1 and Progression.pawned_count(PAWN_ITEM) == 1, "pawn page takes the item and issues one ticket")
	page.free()
	await _frames(3)
	_close_and_record()


func _growth_read() -> void:
	var expected := _expected()
	_main.call("_on_continue_requested")
	await _wait_level()
	var blade := load("res://data/weapons/melee/melee_blade.tres") as WeaponData
	var technique := Progression.find_upgrade(TECHNIQUE)
	_check(Progression.credits == expected["progression"]["credits"], "wallet after restart equals the saved wallet")
	_check(Progression.has_upgrade(blade, TECHNIQUE) and Progression.owned_upgrades(blade).size() == 1, "technique unlock survives without duplication")
	_check(not Progression.buy_upgrade(blade, technique) and Progression.credits == expected["progression"]["credits"], "technique cannot be bought or charged again")
	var again := Progression.apply_story_transaction(load(REWARD) as StoryTransactionData)
	_check(not again.get("applied", true) and Progression.credits == expected["progression"]["credits"], "quest reward is not granted again after restart")
	var store: RunSaveStore = _main.get("_run_store")
	_main.call("_save_run")
	RunSnapshot.apply(store.read())
	_check(Progression.credits == expected["progression"]["credits"] and Progression.owned_upgrades(blade).size() == 1, "repeated reload keeps the same wallet and unlock")
	# 當票跨程序：贖回一次拿回東西並扣款；再贖一次被拒絕，重讀也不會多出東西或錢。
	var player := (_main.get("_screen") as Level).player
	var item := ConsumableBag.find(PAWN_ITEM)
	var held := player.consumables.count(PAWN_ITEM)
	var wallet := Progression.credits
	var page := _pawn_page(player)
	_check(Progression.pawned_count(PAWN_ITEM) == 1, "pawn ticket survives restart exactly once")
	_check(page._do_redeem(item) and player.consumables.count(PAWN_ITEM) == held + 1 and Progression.credits == wallet - Progression.redeem_cost(item), "redeem returns the item and charges once")
	_check(not page._do_redeem(item) and player.consumables.count(PAWN_ITEM) == held + 1, "second redeem has no ticket and adds nothing")
	page.free()
	await _frames(3)
	_main.call("_save_run")
	var after := store.read()
	RunSnapshot.apply(after)
	_check(Progression.credits == wallet - Progression.redeem_cost(item) and Progression.pawned_count(PAWN_ITEM) == 0 and int(after["runtime"]["loadout"]["consumables"].get(String(PAWN_ITEM), 0)) == held + 1, "reload after redeem keeps one item, no ticket, single charge")


func _growth_death_write() -> void:
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _wait_level()
	_main.call("_on_area_requested", "res://data/levels/ch1_booth_alley.tres")
	await _wait_level()
	var level := _main.get("_screen") as Level
	_check(level != null and level.data.resource_path.ends_with("ch1_booth_alley.tres"), "real phone-booth area loaded")
	if level == null:
		return
	var blade := load("res://data/weapons/melee/melee_blade.tres") as WeaponData
	Progression.add_credits(1000)
	_check(Progression.buy_upgrade(blade, Progression.find_upgrade(TECHNIQUE)), "technique bought before dying")
	_check(Progression.apply_story_transaction(load(REWARD) as StoryTransactionData).get("applied", false), "reward granted before dying")
	var before_deaths := GameState.deaths
	level.player.health.kill(DamageInfo.create(99, Combat.Team.ENEMY, &"probe"))
	var saved := (_main.get("_run_store") as RunSaveStore).read()
	_check(saved["state"]["deaths"] == before_deaths + 1 and saved["runtime"]["dead"], "death settles on disk in the same frame")
	_close_and_record()


func _growth_death_read() -> void:
	var expected := _expected()
	_main.call("_on_continue_requested")
	await _wait_level()
	await _frames(30)
	var blade := load("res://data/weapons/melee/melee_blade.tres") as WeaponData
	_check(GameState.deaths == expected["state"]["deaths"], "death is not counted again after restart")
	_check(Progression.credits == expected["progression"]["credits"], "death charge is not applied twice and purchase not refunded")
	_check(Progression.has_upgrade(blade, TECHNIQUE) and Progression.owned_upgrades(blade).size() == 1, "permanent technique survives death and restart")
	var again := Progression.apply_story_transaction(load(REWARD) as StoryTransactionData)
	_check(not again.get("applied", true) and Progression.credits == expected["progression"]["credits"], "reward cannot be claimed again after death and restart")
	var level := _main.get("_screen") as Level
	_check(level != null and not level.died, "player is back at the checkpoint, alive")


func _pawn_page(player: Player) -> PawnPage:
	var page := PawnPage.new()
	page.bind(InventoryContext.new(player))
	return page


# --- 損毀與缺值 -------------------------------------------------------------

func _repair_write() -> void:
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _frames(20)
	Progression.add_credits(555)
	GameState.set_flag(&"ne230_repair_probe", true)
	_main.call("_on_area_requested", "res://data/levels/ch1_street.tres")
	await _frames(10)
	_main.call("_save_run")
	_close_program()
	# 關閉後模擬「下一版移除了這個區域」與導覽損毀：以合法封包寫回，讓讀取走到內容驗證而不是校驗失敗。
	var path := _slot(CampaignEdition.current().id)
	var data: Dictionary = RunSaveCodec.decode(FileAccess.get_file_as_string(path))["data"]
	data["level"] = "res://data/levels/removed_area_ne230.tres"
	data["navigation"] = {"version": 1, "pinned_id": 42, "explored": {"res://nowhere.tres": {"1,1": true}}, "activated": "broken"}
	_write_text(path, RunSaveCodec.encode(data))
	_write_text(_directory.path_join("expected.json"), JSON.stringify(data))


func _repair_read() -> void:
	var expected := _expected()
	var menu := _main.get("_screen") as MainMenu
	_check(menu != null and menu.continue_available, "damaged area still offers continue")
	_check(menu != null and menu.save_notice.contains("區域已不存在"), "menu explains what was repaired: %s" % (menu.save_notice if menu != null else "<none>"))
	await _menu_evidence(menu, "repair-menu")
	_main.call("_on_continue_requested")
	await _wait_level()
	var level := _main.get("_screen") as Level
	_check(level != null and level.data.resource_path == FIRST, "continue falls back to a playable area")
	_check(Progression.credits == expected["progression"]["credits"] and GameState.has_flag(&"ne230_repair_probe"), "credits and story survive the repair")
	_check(QuestMapState.for_run().pinned_id == "" and not QuestMapState.for_run().explored.has("res://nowhere.tres"), "broken navigation entries are dropped, not trusted")
	await _frames(5)
	_main.call("_save_run")
	var saved := (_main.get("_run_store") as RunSaveStore).read()
	_check(saved.get("level") == FIRST and not saved.has("notices"), "next save is the repaired state")


# --- 累積版本 ---------------------------------------------------------------

func _edition_end() -> void:
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _frames(10)
	Progression.add_credits(246)
	_main.call("_on_area_requested", DAWN)
	# 末區的收尾演出依實際時間推進；軟體渲染較慢，等到完成卡或逾時（真時間 90 秒）。
	var deadline := Time.get_ticks_msec() + 90000
	while not _main.get("_screen") is VictoryScreen and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.5, true, false, true).timeout
	_check(_main.get("_screen") is VictoryScreen, "final area of the edition ends on the completion card")
	var card := _main.get("_screen") as VictoryScreen
	if card != null:
		var texts := card.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
		_check(texts.any(func(text: String) -> bool: return text.contains(VictoryScreen.EDITION_END_TEXT)), "completion card says the edition ends here and progress is kept")
		# 等逐項顯示結束、按鈕可用再拍；同時核對整個面板都在畫面內。
		var reveal_deadline := Time.get_ticks_msec() + 30000
		var buttons: Array = card.get("_buttons")
		while (buttons[0] as Button).disabled and Time.get_ticks_msec() < reveal_deadline:
			await _frames(5)
		var visible := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		var panel := card.find_children("*", "UiPanel", true, false)
		_check(not panel.is_empty() and visible.encloses((panel[0] as Control).get_global_rect()), "completion panel stays fully on screen")
		await _capture("edition-end")
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(saved.get("chapter_complete", false) and saved.get("release") == "through-ch1_kasa", "completion saved with this edition's identity")
	_check(store.path == _slot("through-ch1_kasa"), "edition writes only to its own directory")
	_write_text(_directory.path_join("ch1.sha256"), FileAccess.get_sha256(store.path))
	_close_and_record()


func _edition_next() -> void:
	var menu := _main.get("_screen") as MainMenu
	_check(menu != null and menu.continue_available and menu.save_notice.contains("序章至第一章"), "newer edition offers to continue the older edition: %s" % (menu.save_notice if menu != null else "<none>"))
	_check(menu != null and not menu.overwrite_required, "new game here would not overwrite the older edition")
	await _menu_evidence(menu, "import-menu")
	var expected := _expected()
	_main.call("_on_continue_requested")
	await _wait_level()
	var level := _main.get("_screen") as Level
	_check(level != null and level.data.resource_path == FIXTURE_NEXT, "completed chapter continues into the next included chapter, not the completion card")
	_check(Progression.credits == expected["progression"]["credits"], "credits carry across editions")
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(saved.get("release") == "through-chapter_2" and saved.get("level") == FIXTURE_NEXT and not saved.get("chapter_complete", true), "continued progress is saved in the newer edition's own slot")
	_check(FileAccess.get_sha256(_slot("through-ch1_kasa")) == FileAccess.get_file_as_string(_directory.path_join("ch1.sha256")), "older edition save file is byte-identical")
	_close_program()


func _edition_again() -> void:
	var menu := _main.get("_screen") as MainMenu
	_check(menu != null and menu.continue_available and menu.save_notice.is_empty(), "own slot continues without import notice")
	_main.call("_on_continue_requested")
	await _wait_level()
	_check(String(_main.get("_import_path")).is_empty(), "no second import from the older edition")
	var level := _main.get("_screen") as Level
	_check(level != null and level.data.resource_path == FIXTURE_NEXT, "own slot resumes in the next chapter")


func _edition_newer() -> void:
	var before := {}
	for id in ["through-ch1_kasa", "through-chapter_2"]:
		before[id] = FileAccess.get_sha256(_slot(id))
	var menu := _main.get("_screen") as MainMenu
	_check(menu != null and not menu.continue_available and menu.save_notice.contains("序章至第二章"), "smaller edition only explains which edition to use: %s" % (menu.save_notice if menu != null else "<none>"))
	await _menu_evidence(menu, "newer-menu")
	_main.call("_on_continue_requested")
	await _frames(5)
	_check(_main.get("_screen") is MainMenu, "continue cannot load a newer edition save")
	for id in before:
		_check(FileAccess.get_sha256(_slot(id)) == before[id], "%s save untouched" % id)
	_check(not FileAccess.file_exists(_slot(CampaignEdition.current().id)), "nothing written for the smaller edition")


## 明確標示的 fixture：正式第二章尚未交付，只在記憶體中把第一章末區接到舊示範區並標為 chapter_2，驗證跨章接續的路由。
func _install_next_chapter_fixture() -> void:
	var dawn := load(DAWN) as LevelData
	var next := load(FIXTURE_NEXT) as LevelData
	dawn.next_level = FIXTURE_NEXT
	next.chapter = &"chapter_2"
	_fixture_levels = [dawn, next]
	print("[ContinuityProbe] FIXTURE: %s -> %s (chapter_2, in memory only)" % [DAWN, FIXTURE_NEXT])


# --- 共用 ------------------------------------------------------------------

## 主選單的說明文字要完整放進預留的框（不被裁切、不壓到下方說明）。
func _menu_evidence(menu: MainMenu, name: String) -> void:
	if menu == null:
		return
	await _frames(20)
	var notice: Label = null
	for node in menu.find_children("*", "Label", true, false):
		if (node as Label).text == menu.save_notice:
			notice = node
	_check(notice != null, "%s: notice label exists" % name)
	if notice != null and DisplayServer.get_name() != "headless":
		var used := notice.get_line_count() * notice.get_line_height()
		var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		_check(used <= notice.size.y + 0.5 and notice.size.x <= 300.5 and screen.encloses(notice.get_global_rect()), "%s: notice wraps inside its box and the screen (%d lines, %.0fx%.0f, used %.0f px)" % [name, notice.get_line_count(), notice.size.x, notice.size.y, used])
	await _capture(name)


func _capture(name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(10)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	Capture.image(get_viewport()).save_png(_capture_dir.path_join("%s.png" % name))
	print("[ContinuityProbe] captured %s" % name)


func _slot(edition_id: String) -> String:
	return _directory.path_join("runs").path_join(edition_id).path_join(CampaignEdition.SLOT_FILE)


func _close_and_record() -> void:
	_close_program()
	var store := RunSaveStore.new(_slot(CampaignEdition.current().id))
	store.validator = RunSnapshot.prepare
	_write_text(_directory.path_join("expected.json"), JSON.stringify(store.read()))


func _close_program() -> void:
	_closing = true
	print("[ContinuityProbe] %s checks=%d failures=%d" % [_mode, _checks, _failures.size()])
	# 與玩家關閉視窗相同：Main 同步保存後結束程序。
	_main.notification(NOTIFICATION_WM_CLOSE_REQUEST)


func _expected() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("expected.json")))
	return parsed if parsed is Dictionary else {}


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print("PASS " + message if condition else "FAIL " + message)
	if not condition:
		_failures.append(message)


## 等主流程把新區域真的放上畫面（轉場在軟體渲染下可能多花幾秒）。
func _wait_level(limit_msec := 60000) -> void:
	var deadline := Time.get_ticks_msec() + limit_msec
	await _frames(20)
	while not (_main.get("_screen") is Level and (_main.get("_screen") as Level).is_inside_tree()) and Time.get_ticks_msec() < deadline:
		await _frames(5)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _finish() -> void:
	print("[ContinuityProbe] %s checks=%d failures=%d" % [_mode, _checks, _failures.size()])
	if is_instance_valid(_main):
		_main.call("_quit", 0 if _failures.is_empty() else 1)
		return
	get_tree().quit(0 if _failures.is_empty() else 1)
