class_name SupplySuite
extends TestSuite
## 義體能力與補給點（NE-33）：能力資料、解鎖與裝備、電量與冷卻、超頻與電磁脈衝的效果、
## 補給點購買與攜帶上限、背包義體頁、檢查點還原。使用空曠測試場地（tests/fixtures/arena_map.json）。

const EMP_PATH := "res://data/abilities/emp_pulse.tres"
const OVERCLOCK_PATH := "res://data/abilities/overclock.tres"
const SHOP_PATH := "res://data/shops/supply.tres"
const MED_ID := &"med_injector"
const FLOOR_Y := 20 * 16.0


func run() -> void:
	_test_data()
	_test_progression()
	await _test_cyber_system()
	await _test_emp()
	await _test_overclock()
	await _test_shop()
	await _test_cyber_page_and_checkpoint()


func _ability(path: String) -> CyberAbilityData:
	return load(path) as CyberAbilityData


func _fresh() -> void:
	Progression.reset_run()


func _test_data() -> void:
	var catalog := Progression.ability_catalog()
	check(catalog.size() >= 2, "ability catalog loads (%d)" % catalog.size())
	for ability in catalog:
		check(ability.validate().is_empty(), "ability valid: %s %s" % [ability.id, ability.validate()])
		check(ResourceLoader.exists(ItemIcons.ICON_DIR.path_join(ability.icon + ".png")), "ability icon exists: %s" % ability.id)
		check(Sfx.SOUNDS.has(ability.sound), "ability sound exists: %s" % ability.id)
		# 平衡：能力不能一直開著（冷卻比持續時間長）。
		check(ability.cooldown > ability.duration, "ability cannot be kept up forever: %s" % ability.id)
	var shop := load(SHOP_PATH) as ShopData
	check(shop != null and shop.validate().is_empty(), "shop data valid %s" % [shop.validate() if shop != null else "missing"])
	for item in shop.stock:
		check(item.price >= 1, "shop item has a price: %s" % item.id)
	var bad_ability := CyberAbilityData.new()
	bad_ability.kind = CyberAbilityData.Kind.EMP
	bad_ability.radius = 0.0
	bad_ability.unlock_cost = 0
	check(bad_ability.validate().size() >= 3, "invalid ability data is reported")
	var bad_shop := ShopData.new()
	check(not bad_shop.validate().is_empty(), "empty shop is reported")
	check(InputBindings.ACTIONS.any(func(a: Dictionary) -> bool: return a["id"] == &"ability"), "ability action is bindable")


func _test_progression() -> void:
	_fresh()
	var emp := _ability(EMP_PATH)
	var overclock := _ability(OVERCLOCK_PATH)
	check(Progression.equipped_ability() == null, "no ability is equipped at the start")
	check(Progression.ability_unlock_block_reason(emp).contains("不足"), "cannot unlock without credits")
	check(not Progression.unlock_ability(emp), "failed unlock does not charge")
	Progression.add_credits(1000)
	check(Progression.unlock_ability(emp) and Progression.credits == 1000 - emp.unlock_cost, "unlock charges the price")
	check(Progression.equipped_ability() == emp, "the first unlocked ability is equipped automatically")
	check(not Progression.unlock_ability(emp), "an ability cannot be unlocked twice")
	check(Progression.unlock_ability(overclock) and Progression.equipped_ability() == emp, "the second unlock does not replace the equipped one")
	check(Progression.equip_ability(overclock.id) and Progression.equipped_ability() == overclock, "equipping switches the ability")
	check(not Progression.equip_ability(&"no_such_ability"), "equipping an unknown ability fails")
	# 快照：還原解鎖與裝備；損毀的快照退回安全狀態。
	var snapshot := Progression.snapshot()
	Progression.reset_run()
	check(Progression.equipped_ability() == null and not Progression.is_ability_unlocked(emp.id), "reset clears abilities")
	Progression.restore(snapshot)
	check(Progression.is_ability_unlocked(emp.id) and Progression.equipped_ability() == overclock, "snapshot restores unlocks and equipment")
	Progression.restore({"abilities": ["nope", "emp_pulse"], "equipped": "overclock"})
	check(Progression.is_ability_unlocked(emp.id) and Progression.equipped_ability() == emp, "an equipped ability that is not unlocked falls back to an unlocked one")
	Progression.restore({"abilities": "garbage", "equipped": 5})
	check(Progression.equipped_ability() == null, "garbage ability data restores a clean state")
	_fresh()


func _open_arena() -> Level:
	var level := await start_level(NewEnemiesSuite.arena_data())
	level.player.health.setup(999, 0.0)
	level.player.global_position = Vector2(10 * 16.0, FLOOR_Y)
	return level


func _spawn_enemy(level: Level, path: String, x_tile: float) -> Enemy:
	var enemy := level._create_enemy(load(path) as EnemyData)
	enemy.position = Vector2(x_tile * 16.0, FLOOR_Y)
	level._entities.add_child(enemy)
	return enemy


func _test_cyber_system() -> void:
	_fresh()
	var level := await _open_arena()
	var cyber := level.player.cyber
	check(cyber != null and cyber.ability() == null and not cyber.is_ready(), "no ability: the cyber system is idle")
	check(not cyber.try_activate() and cyber.block_reason().contains("義體"), "activating without an ability is refused with a hint")
	# 解鎖後自動接上。
	Progression.add_credits(500)
	Progression.unlock_ability(_ability(EMP_PATH))
	check(cyber.ability() == _ability(EMP_PATH), "the cyber system follows the equipped ability")
	var emp := _ability(EMP_PATH)
	cyber.charge = 10.0
	check(not cyber.is_ready() and cyber.block_reason().contains("不足"), "not enough charge is refused")
	# 電量隨時間回復，擊敗敵人額外回復。
	var before := cyber.charge
	await physics_frames(60)
	check(cyber.charge > before + 1.0, "charge regenerates over time (%.1f -> %.1f)" % [before, cyber.charge])
	before = cyber.charge
	EventBus.enemy_killed.emit(&"test", false)
	check(is_equal_approx(cyber.charge, minf(CyberSystem.MAX_CHARGE, before + CyberSystem.CHARGE_PER_KILL)), "kills recharge the cyber system")
	cyber.charge = CyberSystem.MAX_CHARGE
	var reported := [false]
	var on_report := func(charge: float, ready: bool, ability_name: String, _progress: float) -> void:
		reported[0] = ready and ability_name == emp.display_name and charge > 0.0
	EventBus.player_cyber_changed.connect(on_report)
	check(cyber.try_activate(), "full charge activates the ability")
	check(reported[0] == false and is_equal_approx(cyber.charge, CyberSystem.MAX_CHARGE - emp.charge_cost), "activation consumes the charge")
	check(not cyber.try_activate() and cyber.block_reason().contains("冷卻"), "cooldown blocks the next use")
	EventBus.player_cyber_changed.disconnect(on_report)
	check(level.hud.cyber_gauge.visible, "the HUD shows the cyber gauge while an ability is equipped")
	# 倒下的玩家不能使用。
	cyber._cooldown_left = 0.0
	cyber.charge = 100.0
	level.player.state = Player.State.DEAD
	check(not cyber.try_activate(), "a dead player cannot use abilities")
	level.player.state = Player.State.NORMAL
	await end_level(level)
	_fresh()


func _test_emp() -> void:
	var level := await _open_arena()
	Progression.add_credits(500)
	Progression.unlock_ability(_ability(EMP_PATH))
	var player := level.player
	var near := _spawn_enemy(level, "res://data/enemies/grunt.tres", 14.0)
	var far := _spawn_enemy(level, "res://data/enemies/grunt.tres", 50.0)
	await physics_frames(5)
	# 近處有一發敵方子彈。
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	ProjectilePool.spawn(spec, player.global_position + Vector2(60, -24), Vector2.RIGHT, Combat.Team.ENEMY)
	var friendly := ProjectilePool.spawn(load("res://data/projectiles/pistol_shot.tres") as ProjectileSpec, player.global_position + Vector2(40, -24), Vector2.UP, Combat.Team.PLAYER)
	var active_before := ProjectilePool.active_count()
	player.cyber.charge = 100.0
	check(player.cyber.try_activate(), "EMP activates")
	check(near.is_stunned(), "EMP stuns enemies in range")
	check(not far.is_stunned(), "EMP does not reach distant enemies")
	check(ProjectilePool.active_count() == active_before - 1 and friendly.active, "EMP clears enemy bullets but not the player's")
	# 頭目不會被暈眩（只消除彈幕）。
	var warden := _spawn_enemy(level, "res://data/enemies/warden.tres", 13.0)
	player.cyber._cooldown_left = 0.0
	player.cyber.charge = 100.0
	player.cyber.try_activate()
	check(not warden.is_stunned(), "bosses are not stunned by the EMP")
	await physics_frames(90)
	await end_level(level)
	_fresh()


func _test_overclock() -> void:
	var overclock := _ability(OVERCLOCK_PATH)
	var level := await _open_arena()
	Progression.add_credits(1000)
	Progression.unlock_ability(overclock)
	var cyber := level.player.cyber
	check(is_equal_approx(cyber.fire_rate_scale(), 1.0) and is_equal_approx(cyber.move_speed_scale(), 1.0), "no bonus before activating")
	cyber.charge = 100.0
	check(cyber.try_activate() and cyber.is_overclocked(), "overclock activates")
	check(is_equal_approx(cyber.fire_rate_scale(), 1.0 + overclock.magnitude), "overclock speeds up firing and reloading")
	check(cyber.move_speed_scale() > 1.0 and cyber.move_speed_scale() < cyber.fire_rate_scale(), "overclock speeds up movement a little less")
	# 實際射擊間隔縮短。
	var player := level.player
	player._fire_cooldown_left = 0.0
	player._try_fire()
	var weapon := player.loadout.active_weapon()
	check(is_equal_approx(player._fire_cooldown_left, weapon.fire_interval / cyber.fire_rate_scale()), "the fire interval shrinks while overclocked")
	# 持續時間過後恢復。
	await physics_frames(int((overclock.duration + 0.5) * 60.0))
	check(not cyber.is_overclocked() and is_equal_approx(cyber.fire_rate_scale(), 1.0), "overclock wears off")
	await end_level(level)
	_fresh()


func _test_shop() -> void:
	_fresh()
	var shop := load(SHOP_PATH) as ShopData
	var level := await _open_arena()
	var player := level.player
	var station := ShopStation.new()
	station.configure(shop, Vector2i(12, 19))
	station.position = Vector2(12 * 16.0 + 8.0, FLOOR_Y)
	level._entities.add_child(station)
	player.global_position = station.global_position
	await frames(6)
	check(station._player_in_range, "player in range of the supply point")
	await runner._press_action(&"interact")
	await frames(6)
	check(is_instance_valid(station._screen) and station._screen.is_open(), "interact opens the shop screen")
	check(runner.get_tree().paused, "the game pauses while shopping")
	var page: ShopPage = station._screen._pages[0]
	check(station._screen._pages.size() == 1 and not station._screen._tabs.visible, "the shop shows a single page without tabs")
	var messages: Array[String] = []
	var warnings := [0]
	station._screen._context.message.connect(func(text: String, is_warning: bool) -> void:
		messages.append(text)
		if is_warning:
			warnings[0] += 1)
	var med := ConsumableBag.find(MED_ID)
	var entries := page._build_entries()
	check(entries.size() == shop.stock.size() and not entries[0].action_enabled, "unaffordable items are disabled")
	check(not page._activate_entry(0) and warnings[0] == 1 and Progression.credits == 0, "buying without credits is refused with a warning")
	Progression.add_credits(1000)
	var bag := player.consumables
	var held := bag.count(MED_ID)
	check(page._activate_entry(0), "buying succeeds with credits")
	check(bag.count(MED_ID) == held + 1 and Progression.credits == 1000 - med.price, "the item is added and the price charged")
	# 買到上限後拒絕，而且不扣款。
	while bag.count(MED_ID) < med.max_carry:
		bag.add(med)
	var credits := Progression.credits
	check(not page._activate_entry(0) and Progression.credits == credits, "the carry limit blocks buying without charging")
	entries = page._build_entries()
	check(not entries[0].action_enabled and entries[0].action_hint.contains("上限"), "a full item shows the limit as the reason")
	check(not page._activate_entry(99) and not page._activate_entry(-1), "out-of-range purchases are ignored")
	# 離開：背包鍵關閉，遊戲繼續。
	await runner._press_action(&"inventory")
	await frames(4)
	check(not station._screen.is_open() and not runner.get_tree().paused, "closing the shop resumes the game")
	# 死亡或過關時，關卡會關掉補給畫面。
	station._screen.open()
	await frames(3)
	level._close_menus()
	check(not station._screen.is_open(), "the level closes open shops when it ends")
	var screen := station._screen
	await end_level(level)
	check(not is_instance_valid(screen) or screen.is_queued_for_deletion(), "the shop screen is cleaned up with the level")
	_fresh()


func _test_cyber_page_and_checkpoint() -> void:
	_fresh()
	var emp := _ability(EMP_PATH)
	var overclock := _ability(OVERCLOCK_PATH)
	var context := InventoryContext.new(null)
	var warnings := [0]
	context.message.connect(func(_text: String, is_warning: bool) -> void:
		if is_warning:
			warnings[0] += 1)
	var page := CyberPage.new()
	page.bind(context)
	var entries := page._build_entries()
	check(entries.size() == Progression.ability_catalog().size(), "the page lists every ability")
	check(not entries[0].action_enabled and entries[0].subtitle.contains("未解鎖"), "locked abilities show the price and a disabled action")
	check(entries[0].detail_stats.size() == 3 and entries[0].detail_stats[0].contains("耗電"), "details show cost and cooldown")
	check(not page._activate_entry(0) and warnings[0] == 1, "unlocking without credits is refused with a warning")
	Progression.add_credits(1000)
	check(page._activate_entry(0), "unlocking from the page succeeds")
	check(Progression.equipped_ability() == emp and page._build_entries()[0].badge == "裝備中", "the unlocked ability is equipped and marked")
	check(page._activate_entry(1) and Progression.is_ability_unlocked(overclock.id), "the second ability unlocks")
	check(page._activate_entry(1) == false or Progression.equipped_ability() == overclock, "an unlocked ability can be equipped")
	check(page.tab_tooltip().contains("¥"), "tab tooltip shows the credits")
	page.free()
	# 檢查點：解鎖與裝備跟著還原（重生後 HUD 與電量重新接上）。
	var data := NewEnemiesSuite.arena_data()
	var level := await start_level(data)
	Progression.add_credits(1000)
	Progression.unlock_ability(emp)
	var checkpoint_snapshot := Progression.snapshot()
	GameState.set_checkpoint(Vector2(80, 300), {}, {}, checkpoint_snapshot)
	Progression.add_credits(500)
	Progression.unlock_ability(overclock)
	await end_level(level)
	level = await spawn_level(data)
	check(Progression.is_ability_unlocked(emp.id) and not Progression.is_ability_unlocked(overclock.id), "respawning restores the unlocked abilities")
	check(level.player.cyber.ability() == emp and level.hud.cyber_gauge.visible, "the player and HUD pick up the restored ability")
	await end_level(level)
	GameState.clear_checkpoint()
	_fresh()
