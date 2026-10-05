class_name ProgressionSuite
extends TestSuite
## 成長系統（NE-32）：信用點、武器改裝、背包改裝頁、檢查點還原。

const MAP_PATH := "res://tests/fixtures/credits_map.json"
const RIFLE_PATH := "res://data/weapons/rifle.tres"
const PISTOL_PATH := "res://data/weapons/pistol.tres"
const SPREAD_PATH := "res://data/weapons/spread.tres"
const CANNON_PATH := "res://data/weapons/mech_cannon.tres"
const MAG_ID := &"mag_boost"
const BARREL_ID := &"steady_barrel"
const RELOAD_ID := &"quick_reload"


func run() -> void:
	_test_data()
	_test_credits()
	_test_upgrades()
	_test_loadout_tuning()
	_test_snapshot()
	await _test_pickups_and_checkpoint()
	await _test_upgrades_page()


func _upgrade(id: StringName) -> WeaponUpgradeData:
	return Progression.find_upgrade(id)


func _fresh() -> void:
	Progression.reset_run()


func _test_data() -> void:
	var catalog := Progression.upgrade_catalog()
	check(catalog.size() >= 3, "upgrade catalog loads (%d)" % catalog.size())
	var last_order := -INF
	for upgrade in catalog:
		check(upgrade.validate().is_empty(), "upgrade valid: %s %s" % [upgrade.id, upgrade.validate()])
		check(upgrade.order >= last_order, "upgrades sorted: %s" % upgrade.id)
		last_order = upgrade.order
		# 平衡：改裝只改手感，幅度有上限，價格不是零頭。
		check(upgrade.amount <= 0.6 and upgrade.cost >= 50, "upgrade stays modest: %s" % upgrade.id)
	for path in ["res://data/props/credits_small.tres", "res://data/props/credits_large.tres"]:
		var pile := load(path) as CreditPileData
		check(pile != null and pile.validate().is_empty(), "credit pile valid: %s" % path)
	var bad := WeaponUpgradeData.new()
	bad.cost = 0
	bad.amount = 0.0
	check(bad.validate().size() >= 3, "invalid upgrade data is reported")
	for file in DirAccess.get_files_at("res://data/enemies"):
		var enemy := load("res://data/enemies/%s" % file) as EnemyData
		check(enemy != null and enemy.credit_value > 0, "enemy drops credits: %s" % file)


func _test_credits() -> void:
	_fresh()
	var changes: Array[int] = []
	var on_change := func(_credits: int, delta: int) -> void: changes.append(delta)
	Progression.credits_changed.connect(on_change)
	check(Progression.credits == 0, "run starts with no credits")
	check(Progression.add_credits(50) == 50 and Progression.credits == 50, "credits are added")
	check(Progression.add_credits(0) == 0 and Progression.add_credits(-5) == 0 and Progression.credits == 50, "zero and negative gains are ignored")
	check(not Progression.spend(80) and Progression.credits == 50, "cannot overspend")
	check(Progression.spend(20) and Progression.credits == 30, "spending deducts")
	check(not Progression.spend(-5), "negative cost is refused")
	check(Progression.can_afford(30) and not Progression.can_afford(31), "can_afford matches the balance")
	Progression.add_credits(Progression.MAX_CREDITS * 2)
	check(Progression.credits == Progression.MAX_CREDITS, "credits are capped")
	check(changes == [50, -20, Progression.MAX_CREDITS - 30], "credits_changed reports each real change %s" % [changes])
	Progression.credits_changed.disconnect(on_change)
	_fresh()


func _test_upgrades() -> void:
	_fresh()
	var rifle := load(RIFLE_PATH) as WeaponData
	var cannon := load(CANNON_PATH) as WeaponData
	var mag := _upgrade(MAG_ID)
	check(Progression.upgrade_block_reason(rifle, mag).contains("不足"), "cannot buy without credits")
	check(not Progression.buy_upgrade(rifle, mag) and Progression.credits == 0, "failed purchase does not charge")
	check(Progression.upgrade_block_reason(cannon, mag).contains("用不到"), "mag upgrade does not apply to magazine-less weapons")
	Progression.add_credits(1000)
	check(Progression.upgrade_block_reason(rifle, mag).is_empty(), "purchase allowed with enough credits")
	var before := Progression.credits
	check(Progression.buy_upgrade(rifle, mag) and Progression.credits == before - mag.cost, "purchase deducts the price")
	check(Progression.has_upgrade(rifle, MAG_ID) and Progression.upgrade_block_reason(rifle, mag).contains("已經"), "an upgrade can only be bought once")
	check(not Progression.buy_upgrade(rifle, mag) and Progression.credits == before - mag.cost, "second purchase is refused without charge")
	var tuned := Progression.tuned(rifle)
	check(tuned != rifle and tuned.magazine_size > rifle.magazine_size, "tuned rifle has a bigger magazine (%d)" % tuned.magazine_size)
	check(WeaponTuning.base_of(tuned) == rifle and WeaponTuning.base_of(rifle) == rifle, "base_of finds the original data")
	# 其他武器不受影響；改裝不改傷害與射速。
	var pistol := load(PISTOL_PATH) as WeaponData
	check(Progression.tuned(pistol) == pistol, "untouched weapons are returned as-is")
	check(tuned.fire_interval == rifle.fire_interval and tuned.projectile == rifle.projectile and tuned.pellets == rifle.pellets, "upgrades never change damage or fire rate")
	Progression.buy_upgrade(rifle, _upgrade(RELOAD_ID))
	Progression.buy_upgrade(rifle, _upgrade(BARREL_ID))
	tuned = Progression.tuned(rifle)
	check(tuned.reload_time < rifle.reload_time and tuned.reload_time >= rifle.reload_time * 0.4, "reload is faster but bounded")
	check(tuned.random_spread_degrees < rifle.random_spread_degrees, "spread is reduced")
	check(rifle.magazine_size == 30, "original weapon data is never modified")
	# 散霧槍的固定散佈角也會減少。
	var spread := load(SPREAD_PATH) as WeaponData
	Progression.add_credits(1000)
	Progression.buy_upgrade(spread, _upgrade(BARREL_ID))
	check(Progression.tuned(spread).spread_degrees < spread.spread_degrees, "pellet spread is reduced")
	check(Progression.upgrades_for(cannon).is_empty() or not Progression.upgrades_for(cannon).any(func(u: WeaponUpgradeData) -> bool: return u.effect == WeaponUpgradeData.Effect.MAGAZINE), "magazine-less weapons are not offered a magazine upgrade")
	_fresh()


func _test_loadout_tuning() -> void:
	_fresh()
	var rifle := load(RIFLE_PATH) as WeaponData
	var loadout := Loadout.new()
	loadout.reset(load(PISTOL_PATH) as WeaponData)
	loadout.equip(rifle)
	var slot := loadout.find_slot(rifle.id)
	check(loadout.mag_in(slot) == 30 and loadout.weapon_in(slot) == rifle, "unmodified weapon behaves exactly as before")
	Progression.add_credits(500)
	var changed := [0]
	loadout.changed.connect(func() -> void: changed[0] += 1)
	Progression.upgrades_changed.connect(loadout.retune)
	Progression.buy_upgrade(rifle, _upgrade(MAG_ID))
	var tuned_size := loadout.weapon_in(slot).magazine_size
	check(tuned_size > 30 and loadout.mag_in(slot) == tuned_size, "a bigger magazine is filled immediately (%d/%d)" % [loadout.mag_in(slot), tuned_size])
	check(changed[0] >= 1, "loadout announces the retune")
	# 快照只存原始資料路徑；還原後重新套用改裝。
	var snapshot := loadout.snapshot()
	check((snapshot["weapons"] as Array).has(RIFLE_PATH), "snapshot stores the base weapon path")
	var restored := Loadout.new()
	restored.restore(snapshot, load(PISTOL_PATH) as WeaponData)
	check(restored.weapon_in(restored.find_slot(rifle.id)).magazine_size == tuned_size, "restored loadout re-applies upgrades")
	check(WeaponTuning.base_of(restored.weapon_in(restored.find_slot(rifle.id))) == rifle, "restored loadout still knows the base weapon")
	# 撿到同款武器（補彈）不會丟掉改裝。
	loadout.equip(rifle)
	check(loadout.weapon_in(loadout.find_slot(rifle.id)).magazine_size == tuned_size, "picking up the same weapon keeps the upgrade")
	Progression.upgrades_changed.disconnect(loadout.retune)
	_fresh()


func _test_snapshot() -> void:
	_fresh()
	var rifle := load(RIFLE_PATH) as WeaponData
	Progression.add_credits(400)
	Progression.buy_upgrade(rifle, _upgrade(MAG_ID))
	var snapshot := Progression.snapshot()
	Progression.reset_run()
	check(Progression.credits == 0 and not Progression.has_upgrade(rifle, MAG_ID), "reset_run clears credits and upgrades")
	Progression.restore(snapshot)
	check(Progression.credits == snapshot["credits"] and Progression.has_upgrade(rifle, MAG_ID), "snapshot restores credits and upgrades")
	# 損毀的快照不會崩潰，無效部分退回預設。
	Progression.restore({"credits": "lots", "upgrades": {"rifle": ["no_such_upgrade", MAG_ID, MAG_ID], "x": 5}})
	check(Progression.credits == 0, "garbage credits fall back to zero")
	check(Progression.has_upgrade(rifle, MAG_ID) and Progression.owned_upgrades(rifle).size() == 1, "unknown and duplicate upgrades are dropped")
	Progression.restore({"credits": -50})
	check(Progression.credits == 0, "negative credits are clamped")
	Progression.restore({})
	check(Progression.credits == 0 and Progression.owned_upgrades(rifle).is_empty(), "empty snapshot restores a clean state")
	_fresh()


func _level_data() -> LevelData:
	var data := LevelData.new()
	data.id = &"credits_test"
	data.layout_path = MAP_PATH
	data.legend = {
		"c": load("res://data/props/credits_small.tres"),
		"a": load("res://data/props/crate.tres"),
	}
	return data


func _pile_at(level: Level, column: int) -> CreditPickup:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CreditPickup and (node as CreditPickup).cell.x == column and (node as CreditPickup).visible:
			return node
		stack.append_array(node.get_children())
	return null


func _touch(level: Level, pickup: Pickup) -> void:
	level.player.global_position = pickup.global_position
	level.player.velocity = Vector2.ZERO
	await frames(8)


func _test_pickups_and_checkpoint() -> void:
	var data := _level_data()
	var level := await start_level(data)
	var first := _pile_at(level, 12)
	check(first != null and first.value == 10, "credit pile spawned from the legend")
	check(level.hud.credits_tag.value() == 0, "HUD shows the credits")
	await _touch(level, first)
	check(Progression.credits == 10, "touching a pile adds its value (%d)" % Progression.credits)
	check(level.hud.credits_tag.value() == 10, "HUD follows the credits")
	check(_pile_at(level, 12) == null, "a collected pile disappears")
	# 到檢查點存檔。
	var checkpoint: Checkpoint = null
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Checkpoint:
			checkpoint = node
		stack.append_array(node.get_children())
	level.player.global_position = checkpoint.global_position
	await frames(6)
	check(not GameState.has_checkpoint, "just walking past the phone booth does not record")
	check(checkpoint.start_call(level.player), "dialing at the booth starts the call")
	await frames(90)  # 撥號要一秒多
	check(GameState.has_checkpoint and GameState.checkpoint_progress.get("credits") == 10, "checkpoint stores the credits")
	# 檢查點之後再賺一些：重生後還原成檢查點當下，而且不能重新撿檢查點前的錢。
	await _touch(level, _pile_at(level, 18))
	check(Progression.credits == 20, "second pile collected after the checkpoint")
	await end_level(level)
	level = await spawn_level(data)
	check(Progression.credits == 10, "respawning restores the checkpoint credits (%d)" % Progression.credits)
	check(_pile_at(level, 12) == null, "a pile collected before the checkpoint stays collected")
	check(_pile_at(level, 18) != null, "a pile collected after the checkpoint comes back")
	# 沒有檢查點（殘機用盡）時還原成進入關卡時。
	await end_level(level)
	GameState.clear_checkpoint()
	level = await spawn_level(data)
	check(Progression.credits == 0, "no checkpoint restores the level-start credits")
	check(_pile_at(level, 12) != null, "all piles are back without a checkpoint")
	# 敵人與箱子掉信用點。
	var crate := _crate(level)
	var info := DamageInfo.create(99, Combat.Team.PLAYER, &"test")
	info.ignore_invulnerability = true
	crate.hit_by_projectile(info)
	await frames(6)
	var dropped: CreditPickup = null
	for node in level._entities.get_children():
		if node is CreditPickup and (node as CreditPickup).cell == Vector2i(-1, -1):
			dropped = node
	check(dropped != null and dropped.value == crate.data.credit_drop, "a broken crate drops credits")
	if dropped != null:
		await _touch(level, dropped)
		check(Progression.credits == crate.data.credit_drop, "drops add credits")
	var grunt := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
	grunt.position = Vector2(30 * 16.0, 20 * 16.0)
	level._entities.add_child(grunt)
	await frames(3)
	var lethal := DamageInfo.create(99, Combat.Team.PLAYER, &"test")
	lethal.ignore_invulnerability = true
	lethal.bypass_guard = true
	grunt.hurtbox.receive(lethal)
	await frames(6)
	var enemy_drop := 0
	for node in level._entities.get_children():
		if node is CreditPickup and (node as CreditPickup).cell == Vector2i(-1, -1) and (node as CreditPickup).value == 8:
			enemy_drop += 1
	check(enemy_drop == 1, "a defeated enemy drops credits")
	await frames(60)
	await end_level(level)
	GameState.clear_checkpoint()


func _crate(level: Level) -> Breakable:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Breakable:
			return node
		stack.append_array(node.get_children())
	return null


func _test_upgrades_page() -> void:
	var level := await start_level(_level_data())
	var player := level.player
	var rifle := load(RIFLE_PATH) as WeaponData
	player.loadout.equip(rifle)
	var context := InventoryContext.new(player)
	var messages: Array[String] = []
	var warnings := [0]
	context.message.connect(func(text: String, is_warning: bool) -> void:
		messages.append(text)
		if is_warning:
			warnings[0] += 1)
	var page := UpgradesPage.new()
	page.bind(context)
	var entries := page._build_entries()
	check(entries.size() >= 3, "upgrades page lists the rifle's upgrades (%d)" % entries.size())
	var mag_index := -1
	for i in page._targets.size():
		if page._targets[i]["upgrade"].id == MAG_ID and WeaponTuning.base_of(page._targets[i]["weapon"]) == rifle:
			mag_index = i
	check(mag_index >= 0, "rifle magazine upgrade is listed")
	var entry := entries[mag_index]
	check(entry.subtitle.begins_with("¥") and not entry.action_enabled, "unaffordable upgrade shows its price and a disabled action")
	check(entry.detail_stats.size() >= 2 and entry.detail_stats[1].contains("→"), "upgrade preview shows before and after: %s" % [entry.detail_stats])
	check(not entry.action_hint.is_empty() and not entry.hint.is_empty(), "upgrade has hints")
	# 錢不夠：被拒絕並提示。
	check(not page._activate_entry(mag_index) and warnings[0] == 1 and Progression.credits == 0, "insufficient funds are refused with a warning")
	Progression.add_credits(500)
	entries = page._build_entries()
	check(entries[mag_index].action_enabled, "upgrade becomes available with credits")
	check(page._activate_entry(mag_index), "buying from the page succeeds")
	check(Progression.has_upgrade(rifle, MAG_ID) and Progression.credits == 500 - _upgrade(MAG_ID).cost, "the page charged the price")
	check(player.loadout.weapon_in(player.loadout.find_slot(rifle.id)).magazine_size > 30, "the player's weapon is upgraded immediately")
	entries = page._build_entries()
	check(entries[mag_index].subtitle == "已改裝" and not entries[mag_index].action_enabled and entries[mag_index].badge == "已改裝", "an owned upgrade is marked and locked")
	check(page.tab_tooltip().contains("¥"), "tab tooltip shows the credits")
	page.free()
	await end_level(level)
