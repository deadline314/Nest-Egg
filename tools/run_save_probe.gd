extends Node
## --mode=unit/write/read/transition_write/transition_read/death_write/death_read
## --save-dir=<absolute isolated directory> 必填；絕不使用正式 user:// 槽。

const MainScript := preload("res://game/main.gd")
var _failures := PackedStringArray()
var _checks := 0
var _directory := ""
var _mode := ""
var _main: Node
var _closing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save-dir="):
			_directory = argument.trim_prefix("--save-dir=")
		elif argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
	if _directory.is_empty() or not _directory.is_absolute_path() or _mode.is_empty():
		push_error("[RunSaveProbe] --save-dir 絕對隔離目錄與 --mode 必填")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	Transition.instant = true  # 本工具只在 transition_write 明確啟用慢轉場。
	Enemy.activation_culling_enabled = false
	if _mode == "unit":
		var suite := RunSaveSuite.new(self)
		suite.directory = _directory
		await suite.run()
	else:
		if _mode.begins_with("choice_"):
			Story.load_chapter("res://tests/fixtures/run_save_choice.json")
		_main = MainScript.new()
		_main.set("_run_store", RunSaveStore.new(_directory.path_join("slot.json")))
		add_child(_main)
		await _frames(3)
		if _mode == "route":
			await _route()
			await _finish()
			return
		if _mode.ends_with("_read") or _mode == "read" or _mode == "second_write":
			if _mode == "choice_read":
				Story.auto_skip = false
			if _mode == "aim_read":
				AimInput.using_gamepad = true
				AimInput._last_stick_dir = Vector2.RIGHT
			_main.call("_on_continue_requested")
			if _mode == "read":
				# 先核對讀檔瞬間姿勢，避免無按鍵的下一物理影格正常站起。
				var restored := _main.get("_screen") as Level
				if restored != null:
					restored.player.set_physics_process(false)
		else:
			_main.call("_on_start_requested", GameState.difficulties[1])
		await _frames(5)
		if _mode.begins_with("end_"):
			if _mode == "end_write":
				await _end_write()
			else:
				_check(_main.get("_screen") is VictoryScreen, "second process resumes chapter completion card rather than old demo next level")
			await _finish()
			return
		if _mode == "death_write":
			_main.call("_on_area_requested", "res://data/levels/ch1_booth_alley.tres")
			await _frames(5)
		var level := _main.get("_screen") as Level
		_check(level != null, "Main actually creates playable Level from isolated slot")
		if level == null:
			await _finish()
			return
		match _mode:
			"write": await _write(level)
			"read": await _read(level)
			"transition_write": await _transition_write(level)
			"transition_read": await _transition_read(level)
			"death_write": await _death_write(level)
			"death_read": await _death_read()
			"choice_write": await _choice_write()
			"choice_read": await _choice_read()
			"world_write": await _world_write(level)
			"world_read": await _world_read(level)
			"retry_write": await _retry_write()
			"retry_read": await _retry_read(level)
			"aim_read": await _aim_read(level)
			"second_write": await _second_write(level)
			"second_read": await _second_read(level)
			"restore_order": await _restore_order(level)
			_: _check(false, "unknown probe mode")
	if not _closing:
		await _finish()


func _route() -> void:
	Transition.instant = false
	var original_menu: Node = _main.get("_screen")
	_main.call("_on_level_completed", load("res://data/levels/level_01.tres"))
	_check(_main.get("_screen") == original_menu and _main.get("_pending_screen") == null, "completion from a menu is safely rejected without creating a route")
	_main.call("_on_start_requested", GameState.difficulties[1])
	var pending: Node = _main.get("_pending_screen")
	var store: RunSaveStore = _main.get("_run_store")
	var first_bytes := FileAccess.get_file_as_string(store.path)
	_check(pending is Level and not pending.is_inside_tree(), "noninstant start owns unparented destination")
	_main.call("_on_start_requested", GameState.difficulties[2])
	_main.call("_on_continue_requested")
	_check(_main.get("_pending_screen") == pending and GameState.difficulty == GameState.difficulties[1], "duplicate same-frame start and continue preserve original route")
	_check(FileAccess.get_file_as_string(store.path) == first_bytes and not FileAccess.file_exists(store.path + ".previous"), "duplicate route does not start a second new-round transaction")
	await get_tree().create_timer(1.5).timeout
	var count := 0
	for child in _main.get_children():
		if child is Level:
			count += 1
	_check(count == 1 and _main.get("_screen") == pending, "covered callback installs exactly one original live Level")
	_main.call("_on_level_completed", load("res://data/levels/level_02.tres"))
	_check(_main.get("_screen") == pending and _main.get("_pending_screen") == null and not _main.get("_chapter_complete"), "stale completion data cannot replace the current source Level")
	var old_data := (pending as Level).data
	var old_completion: Callable = (pending as Level).get_signal_connection_list(&"completed")[0]["callable"]
	(pending as Level).retry_requested.emit()
	await get_tree().create_timer(1.5).timeout
	var retried := _main.get("_screen") as Level
	_check(retried != null and retried.data == old_data, "retry installs a new source Level sharing cached LevelData")
	old_completion.call_deferred()
	await _frames(2)
	_check(_main.get("_screen") == retried and _main.get("_pending_screen") == null and not _main.get("_chapter_complete"), "old deferred completion cannot complete the retried Level with identical data")
	pending = retried
	(pending as Level).menu_requested.emit()
	(pending as Level).menu_requested.emit()
	await _frames(1)
	var menu: Node = _main.get("_pending_screen")
	_check(menu is MainMenu and not menu.is_inside_tree(), "same-frame menu signals own one unparented destination")
	await get_tree().create_timer(1.5).timeout
	count = 0
	var levels := 0
	for child in _main.get_children():
		if child is MainMenu:
			count += 1
		elif child is Level:
			levels += 1
	_check(count == 1 and levels == 0 and _main.get("_screen") == menu, "duplicate deferred menu requests install exactly one original menu")
	_main.call("_on_continue_requested")
	await get_tree().create_timer(1.5).timeout
	_main.call("_on_area_requested", "res://data/levels/ne230_missing.tres")
	await get_tree().create_timer(1.5).timeout
	_check(_main.get("_screen") is MainMenu and not _main.get("_destination_pending"), "invalid destination still falls back to safe menu without pending save lock")


func _restore_order(level: Level) -> void:
	var actor: NpcActor
	for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and level.is_ancestor_of(node):
			actor = node
			break
	_check(actor != null, "restore ordering uses a real stateful chapter-one NPC")
	if actor == null:
		return
	actor.talk_count = 5
	var actor_key := actor.state_key()
	Progression.add_credits(73)
	GameState.world_flags["restore_probe_marker"] = "saved"
	_main.call("_save_run")
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(not saved.is_empty(), "real Main writes the complete ordering fixture")
	if saved.is_empty():
		return
	_main.call("_show_main_menu")
	await _frames(3)
	var observations: Array[Dictionary] = []
	var observer := func(value: int, _delta: int) -> void:
		var restored := _main.get("_screen") as Level
		var restored_actor: NpcActor
		if restored != null:
			for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
				if node is NpcActor and restored.is_ancestor_of(node) and node.state_key() == actor_key:
					restored_actor = node
		observations.append({"wallet": value, "level": restored != null and restored.is_inside_tree(),
			"player": restored != null and is_instance_valid(restored.player),
			"talks": restored_actor.talk_count if restored_actor != null else -1,
			"marker": GameState.world_flags.get("restore_probe_marker"),
			"guarded": _main.get("_publishing_restore")})
		# 同步監聽者不能在半個載入流程裡再開始另一局或另一份續玩。
		_main.call("_on_start_requested", GameState.difficulties[2])
		_main.call("_on_continue_requested")
	Progression.credits_changed.connect(observer)
	_main.call("_on_continue_requested")
	await _frames(6)
	Progression.credits_changed.disconnect(observer)
	_check(observations.size() == 1, "Continue publishes one complete wallet notification")
	if observations.size() == 1:
		var first: Dictionary = observations[0]
		_check(first["level"] and first["player"] and first["talks"] == 5, "first Continue observer sees resumed Level player and restored actual NPC state")
		_check(first["wallet"] == saved["progression"]["credits"] and first["marker"] == "saved" and first["guarded"], "first Continue observer sees matching wallet/story with route guard held")
	_check(GameState.difficulty.resource_path == saved["difficulty"] and not _main.get("_restore_publish_pending"), "reentrant observer cannot replace the resumed difficulty or leave restore pending")
	if DisplayServer.get_name() != "headless":
		await _frames(20)
		await RenderingServer.frame_post_draw
		preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(_directory.path_join("restore-order.png"))


func _write(level: Level) -> void:
	Progression.add_credits(700)
	var shop := load("res://data/shops/ch1_pawn.tres") as ShopData
	var page := ShopPage.new()
	page.shop = shop
	page.bind(InventoryContext.new(level.player))
	var before := Progression.credits
	_check(page._activate_entry(0), "actual ShopPage purchase succeeds")
	_check(Progression.credits == before - shop.stock[0].price, "actual shop charges exactly one price")
	page.free()
	var weapon := load("res://data/weapons/smg.tres") as WeaponData
	level.player.loadout.equip(weapon)
	Progression.add_credits(1000)
	var upgrade := Progression.upgrades_for(weapon)[0]
	_check(Progression.buy_upgrade(weapon, upgrade), "actual weapon upgrade transaction completes")
	_check(Progression.unlock_ability(Progression.ability_catalog()[0]), "actual ability purchase completes")
	level.player.loadout.set_ammo(1, 3, 7)
	level.player.facing = -1
	level.player.aim_dir = Vector2.LEFT
	level.player.is_crouching = true
	level.player.health.take_damage(DamageInfo.create(2, Combat.Team.ENEMY, &"probe"))
	GameState.set_flag(&"ne230_probe_reward", true)
	Progression.add_credits(25)
	var pawn := ConsumableBag.find(&"shield_cell")
	Progression.pawn(pawn)
	var map := QuestMapState.for_run()
	map.reveal(level.data.resource_path, [Vector2i(2, 2)])
	# 真電話亭的復原點另由 death_phone / retry 兩程序驗；本區沒有電話亭。
	for node in level.get("_entities").get_children():
		if node is CreditPickup and node.cell != Vector2i(-1, -1):
			node._apply(level.player)
			node._consume()
			break
	_main.call("_save_run")
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(saved["runtime"]["health"] == level.player.health.current, "disk contains injured actual health")
	_write_expected(saved)
	# 完整退出由本工具 finish 關閉程序；下一個 read 是另一個引擎程序。


func _read(level: Level) -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("expected.json")))
	_check(Progression.credits == expected["progression"]["credits"], "second process retains purchase, reward, pawn and collected cash")
	print("[RunSaveProbe] pawn actual=%s expected=%s pose=%s/%s" % [Progression.snapshot()["pawned"], expected["progression"]["pawned"], level.player.facing, level.player.is_crouching])
	_check(Progression.pawned_count(&"shield_cell") == int(expected["progression"]["pawned"].get("shield_cell", 0)), "pawn ticket survives process restart")
	_check(level.player.health.current == expected["runtime"]["health"], "second process restores injured health")
	_check(level.player.facing == -1 and level.player.is_crouching, "second process restores facing and crouch pose")
	_check(level.player.loadout.active_weapon().id == &"smg", "active equipment survives process restart")
	_check(level.player.loadout.mag_in(1) == 3 and level.player.loadout.reserve_in(1) == 7, "magazine and reserve remain separate")
	_check(Progression.snapshot()["equipped"] == expected["progression"]["equipped"] and Progression.equipped_ability() != null, "unlocked and equipped ability survives process restart")
	_check(Progression.owned_upgrades(load("res://data/weapons/smg.tres") as WeaponData).size() == 1, "paid weapon upgrade survives without recharging")
	_check(GameState.has_flag(&"ne230_probe_reward"), "completed reward flag survives")
	_check(QuestMapState.for_run().knows(level.data.resource_path, Vector2i(2, 2)), "navigation survives with same story and world")
	var before := Progression.credits
	_main.call("_save_run")
	var store: RunSaveStore = _main.get("_run_store")
	RunSnapshot.apply(store.read())
	_check(Progression.credits == before and GameState.has_flag(&"ne230_probe_reward"), "repeated disk apply does not re-grant reward")


func _transition_write(level: Level) -> void:
	var loose := CreditPickup.new()
	loose.value = 777
	loose.position = level.player.position + Vector2(120, -50)
	level.get("_entities").add_child(loose)
	GameState.pending_portal = &"roof_stairs"
	GameState.carried_health = level.player.health.current
	Transition.instant = false
	_main.call("_queue_save")
	_main.call("_on_area_requested", "res://data/levels/ch1_rooftop.tres")
	_check((_main.get("_screen") as Level).data.resource_path == level.data.resource_path, "probe is inside transition before screen swap")
	_main.call("_save_run")  # WM_CLOSE_REQUEST 的同步保存使用同入口。
	await _frames(1)  # 明確執行切換前已排隊的 deferred save。
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(saved["level"] == "res://data/levels/ch1_rooftop.tres", "queued save cannot replace target identity with source region")
	_check(RunSaveCodec.vector(saved["runtime"]["position"]) == Vector2(-1, -1), "close-before-covered retains pending entry sentinel")
	_check(saved["runtime"]["loose"].is_empty() and saved["runtime"]["enemies"].is_empty() and saved["runtime"]["encounters"].is_empty(), "source dynamic world is not copied into target")
	_write_expected(saved)
	# 檢查完即真正 WM_CLOSE_REQUEST；不能等正常轉場後冒稱邊界已驗。
	print("[RunSaveProbe] transition before close checks=%d failures=%d" % [_checks, _failures.size()])
	_close_program()


func _transition_read(level: Level) -> void:
	_check(level.data.resource_path == "res://data/levels/ch1_rooftop.tres", "second process loads destination region")
	var expected := Vector2.ZERO
	for spawn in level.get("_layout").spawns:
		if spawn["resource"] is PortalData and spawn["resource"].id == &"roof_stairs":
			expected = spawn["position"]
	_check(level.player.position.distance_to(expected) < 4, "pending sentinel uses actual destination portal, not player_start")
	var has_old_drop := false
	for node in level.get("_entities").get_children():
		if node is CreditPickup and node.value == 777:
			has_old_drop = true
	_check(not has_old_drop, "no source loose pickup appears in destination")


func _death_write(level: Level) -> void:
	Progression.add_credits(400)
	var before := GameState.deaths
	level.player.health.kill(DamageInfo.create(99, Combat.Team.ENEMY, &"probe"))
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(saved["state"]["deaths"] == before + 1 and saved["runtime"]["dead"], "death settles and writes before delay or blackout")
	_write_expected(saved)
	_close_program()


func _death_read() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("expected.json")))
	await _frames(24)
	var level := _main.get("_screen") as Level
	_check(GameState.deaths == expected["state"]["deaths"], "restarted settled death does not increment a second time")
	_check(Progression.credits == expected["progression"]["credits"], "restarted death does not charge twice")
	_check(GameState.has_checkpoint and level != null and not level.died, "first death still plays registration and returns to live checkpoint")


func _second_write(level: Level) -> void:
	_check(GameState.has_checkpoint and GameState.deaths == 1, "second-death fixture continues real first-death registration")
	Progression.add_credits(400)
	var before := Progression.credits
	var count := GameState.deaths
	level.player.health.kill(DamageInfo.create(99, Combat.Team.ENEMY, &"probe"))
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(saved["state"]["deaths"] == count + 1 and saved["runtime"]["death_entry"].is_empty(), "second death settles without repeating first registration cinematic")
	_check(saved["progression"]["credits"] < before, "second death charges actual persistent-area fee before close")
	_write_expected(saved)
	_close_program()


func _second_read(level: Level) -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("expected.json")))
	_check(GameState.deaths == expected["state"]["deaths"] and Progression.credits == expected["progression"]["credits"], "second process does not duplicate settled death or fee")
	_check(level.died and level.player.is_dead() and level.player.health.current == 0, "saved dead player is a corpse rather than live HP while death screen waits")
	level.call("_request_retry")
	await _frames(7)
	level = _main.get("_screen") as Level
	_check(level != null and not level.died and GameState.deaths == expected["state"]["deaths"], "actual retry returns alive without another death charge")


func _end_write() -> void:
	# 直接定位正式第一章末區，僅驗路由，不宣稱通過整章敘事或未交付章節。
	_main.call("_on_area_requested", "res://data/levels/ch1_pawnshop_dawn.tres")
	await get_tree().create_timer(6.0, true, false, true).timeout
	_check(_main.get("_screen") is VictoryScreen, "actual final-area completion routes to victory")
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(saved["chapter_complete"] and saved["level"] == "res://data/levels/ch1_pawnshop_dawn.tres", "chapter completion is saved with final area identity")
	_check(not saved["level"].contains("level_02"), "missing new chapter does not route to legacy demonstration")


func _choice_write() -> void:
	Progression.add_credits(300)
	await _frames(2)
	Story.auto_skip = false
	Story.play(&"ne230_choice_atomic")
	await _frames(2)
	var player := Story.get("_player") as CutscenePlayer
	_check(player != null, "non-auto-skip real choice player is active")
	player.choose(0)
	await _frames(2)
	_check(GameState.has_flag(&"ne230_choice_a") and not GameState.has_flag(&"ne230_choice_b"), "real A selection applied provisionally before interruption")
	Progression.add_credits(9)  # 本段的暫定交易，不屬入口之前的已完成交易。
	_main.call("_save_run")
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(not saved["story"]["flags"].get("ne230_choice_a", false) and not saved["story"]["flags"].get("ne230_choice_b", false), "incomplete cinematic persists entry flags, neither unanswered option")
	_check(saved["progression"]["credits"] == 300, "entry keeps previous transaction and rolls back provisional cinematic credit")
	_write_expected(saved)
	_close_program()


func _close_program() -> void:
	_closing = true
	print("[RunSaveProbe] %s checks=%d failures=%d" % [_mode, _checks, _failures.size()])
	_main.notification(NOTIFICATION_WM_CLOSE_REQUEST)


func _choice_read() -> void:
	_check(not GameState.has_flag(&"ne230_choice_a") and not GameState.has_flag(&"ne230_choice_b"), "second process re-enters unanswered choice without previous A")
	_check(Progression.credits == 300, "pre-cinematic completed transaction survives restart")
	var player := Story.get("_player") as CutscenePlayer
	_check(player != null, "choice is waiting for player rather than default selecting")
	player.choose(1)
	await get_tree().create_timer(3.1, true, false, true).timeout
	_main.call("_save_run")
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(not GameState.has_flag(&"ne230_choice_a") and GameState.has_flag(&"ne230_choice_b"), "real B result remains mutually exclusive with interrupted A")
	_check(saved["story"]["flags"]["ne230_choice_b"] and not saved["story"]["flags"]["ne230_choice_a"], "completed B commits whole result to disk")


func _world_write(level: Level) -> void:
	var boxes := 0
	for node in level.get("_entities").get_children():
		if node is Breakable:
			node.health.kill(DamageInfo.create(99, Combat.Team.PLAYER, &"probe"))
			boxes += 1
	_check(boxes > 0, "actual persistent pawnshop contains breakable fixture")
	await _frames(4)
	_main.call("_save_run")
	_main.call("_on_area_requested", "res://data/levels/ch1_warehouse.tres")
	await _frames(5)
	level = _main.get("_screen") as Level
	var switches := 0
	for node in level.get("_entities").get_children():
		if node is MechanismSwitch:
			node.toggle()
			switches += 1
	_check(switches > 0, "actual warehouse contains persistent switches")
	await _frames(5)
	_main.call("_save_run")
	_main.call("_on_area_requested", MainScript.FIRST_LEVEL)
	await _frames(5)
	level = _main.get("_screen") as Level
	var loose := CreditPickup.new()
	loose.value = 777
	loose.position = level.player.position + Vector2(120, -50)
	level.get("_entities").add_child(loose)
	Transition.instant = false
	_main.call("_queue_save")
	_main.call("_on_area_requested", "res://data/levels/ch1_warehouse.tres")
	_main.call("_save_run")
	await _frames(1)
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(saved["runtime"]["world"] == saved["state"]["area_states"]["ch1_warehouse"]["world"], "destination snapshot keeps its own persistent switches and gates")
	_check(saved["runtime"]["loose"].is_empty(), "destination snapshot excludes source loose cash")
	_write_expected(saved)
	_close_program()


func _world_read(level: Level) -> void:
	var switches := 0
	for node in level.get("_entities").get_children():
		if node is MechanismSwitch:
			_check(node.active, "second process restores actual destination switch")
			switches += 1
	_check(switches > 0, "restored destination has real switch nodes")
	_main.call("_on_area_requested", MainScript.FIRST_LEVEL)
	await _frames(5)
	level = _main.get("_screen") as Level
	var boxes := 0
	for node in level.get("_entities").get_children():
		if node is Breakable:
			_check(node.is_broken, "second process revisits actual broken persistent box")
			boxes += 1
	_check(boxes > 0, "revisited region contains real boxes")
	_check(not level.run_snapshot()["loose"].any(func(entry: Dictionary) -> bool: return entry.get("value", 0) == 777), "source cash is not injected in returned region")


func _retry_write() -> void:
	# 舊示範關卡僅作非持久框架 fixture，不代表新版第二章驗收。
	_main.call("_on_area_requested", "res://data/levels/level_02.tres")
	await _frames(6)
	var level := _main.get("_screen") as Level
	var switch_key := ""
	for node in level.get("_entities").get_children():
		if node is MechanismSwitch:
			node.toggle()
			switch_key = node.state_key()
			break
	_check(switch_key != "", "legacy nonpersistent fixture has real switch")
	Progression.add_credits(100)
	var layout: LevelLayout = level.get("_layout")
	GameState.set_checkpoint(layout.checkpoints[0], level.player.checkpoint_snapshot(), WorldState.capture(get_tree()), Progression.snapshot())
	for node in level.get("_entities").get_children():
		if node is MechanismSwitch and node.state_key() == switch_key:
			node.toggle()
	Progression.add_credits(900)
	var weapon := load("res://data/weapons/smg.tres") as WeaponData
	level.player.loadout.equip(weapon)
	_check(Progression.buy_upgrade(weapon, Progression.upgrades_for(weapon)[0]), "checkpoint-later real upgrade purchase completes")
	_check(Progression.unlock_ability(Progression.ability_catalog()[0]), "checkpoint-later real ability purchase completes")
	Transition.instant = false
	_main.call("_queue_save")
	_main.call("_on_retry_requested", level)
	_main.call("_save_run")
	await _frames(1)
	var store: RunSaveStore = _main.get("_run_store")
	var saved := store.read()
	_check(saved["runtime"]["world"].get(switch_key, false), "same-region queued retry retains checkpoint world rather than current off switch")
	_check(saved["progression"]["credits"] == 100, "nonpersistent retry restores checkpoint progression before writing")
	_check(saved["progression"]["upgrades"].is_empty() and saved["progression"]["abilities"].is_empty(), "nonpersistent retry rewinds paid growth to checkpoint")
	_check(not saved["runtime"]["loadout"]["weapons"].has(weapon.resource_path), "nonpersistent retry uses checkpoint equipment rather than current SMG")
	saved["probe_switch"] = switch_key
	_write_expected(saved)
	_close_program()


func _retry_read(level: Level) -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("expected.json")))
	var found := false
	for node in level.get("_entities").get_children():
		if node is MechanismSwitch and node.state_key() == expected["probe_switch"]:
			found = true
			_check(node.active, "second process restores real nonpersistent checkpoint switch")
	_check(found and Progression.credits == 100, "same-region retry checkpoint world and transaction match")
	_check(Progression.equipped_ability() == null and Progression.owned_upgrades(load("res://data/weapons/smg.tres") as WeaponData).is_empty(), "continued retry does not retain later paid upgrade or ability")
	_check(level.player.loadout.find_slot(&"smg") < 0, "continued retry restores checkpoint weapons")
	var before := {"progression": Progression.snapshot(), "loadout": level.player.checkpoint_snapshot(), "world": WorldState.capture(get_tree())}
	_main.call("_on_retry_requested", level)
	await _frames(6)
	level = _main.get("_screen") as Level
	_check(before["progression"] == Progression.snapshot() and before["loadout"] == level.player.checkpoint_snapshot() and before["world"] == WorldState.capture(get_tree()), "ordinary no-close retry matches interrupted-retry continuation")


func _aim_read(level: Level) -> void:
	for i in 3:
		await get_tree().physics_frame
	_check(level.player.facing == -1, "saved LEFT survives three physics frames with idle gamepad and old global RIGHT")
	var mouse := InputEventMouseMotion.new()
	mouse.position = Vector2(1000, 200)
	mouse.relative = Vector2(10, 0)
	Input.parse_input_event(mouse)
	await get_tree().physics_frame
	_check(not AimInput.using_gamepad, "new mouse motion takes aim control normally")
	var axis := InputEventJoypadMotion.new()
	axis.device = 999  # 合成裝置，不宣稱實體手把驗收。
	axis.axis = JOY_AXIS_RIGHT_X
	axis.axis_value = 0.9
	Input.parse_input_event(axis)
	Input.action_press(&"aim_right", 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(level.player.facing == 1 and AimInput.using_gamepad, "new axis input takes aim control normally")
	Input.action_release(&"aim_right")


func _write_expected(saved: Dictionary) -> void:
	var file := FileAccess.open(_directory.path_join("expected.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print("PASS " + message if condition else "FAIL " + message)
	if not condition:
		_failures.append(message)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _end_level(level: Level) -> void:
	level.queue_free()
	await _frames(3)


func _finish() -> void:
	print("[RunSaveProbe] %s checks=%d failures=%d" % [_mode, _checks, _failures.size()])
	if is_instance_valid(_main):
		_main.call("_quit", 0 if _failures.is_empty() else 1)
		return
	await _frames(3)
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await get_tree().create_timer(1.1, true, false, true).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
