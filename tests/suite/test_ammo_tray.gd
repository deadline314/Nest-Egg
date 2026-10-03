class_name AmmoTraySuite
extends TestSuite
## 主角旁的動態彈匣（NE-42）：排列、位置與面向、開槍彈殼、換彈依序填回、低彈量常駐、
## 壓縮倍率、能量武器、閒置淡出，以及緩衝區大小固定。


func run() -> void:
	_test_compression()
	await _test_tray_follows_loadout()
	await _test_side_and_fade()
	await _test_firing_and_reload()
	await _test_energy_weapon()


func _test_compression() -> void:
	check(AmmoTray.per_icon_for(12) == 1 and AmmoTray.per_icon_for(30) == 1, "30 發以內一顆圖示一發")
	check(AmmoTray.per_icon_for(60) == 2, "60 發的彈匣一顆圖示代表 2 發")
	check(AmmoTray.per_icon_for(91) == 4, "超過 30 顆圖示時向上取整")


func _wait_frames(count: int) -> void:
	for i in count:
		await runner.get_tree().process_frame


func _test_tray_follows_loadout() -> void:
	var level := await start_level(PropsSuite.level_data())
	var tray := level.hud.ammo_tray
	var player := level.player
	check(tray != null, "HUD 有主角旁的彈匣")
	await frames(3)
	check(tray.icon_count() == 12 and tray.icons_per_row() == 10, "手槍 12 發排成兩排（每排最多 10 發）")
	player.loadout.equip(load("res://data/weapons/rifle.tres") as WeaponData)
	await frames(2)
	check(tray.icon_count() == 30 and tray.per_icon() == 1, "換成步槍後排成 30 顆")
	player.loadout.equip(load("res://data/weapons/spread.tres") as WeaponData)
	await frames(2)
	check(tray.icon_count() == 6, "霰彈槍 6 顆")
	check(tray._eject_pos.size() == AmmoTray.EJECT_SLOTS, "彈殼緩衝區大小固定（不每影格配置）")
	await end_level(level)


func _test_side_and_fade() -> void:
	var level := await start_level(PropsSuite.level_data())
	var tray := level.hud.ammo_tray
	await frames(30)
	Input.action_press(&"aim_right")
	await frames(10)
	var right_side := tray.side()
	Input.action_release(&"aim_right")
	Input.action_press(&"aim_left")
	await frames(10)
	var left_side := tray.side()
	Input.action_release(&"aim_left")
	check(right_side < 0.0 and left_side > 0.0, "彈匣放在與準星相反的一側")
	# 閒置淡出（開啟自動隱藏時）。
	var previous := Settings.get_hud_auto_hide()
	Settings.set_hud_auto_hide(true)
	for i in 400:
		await runner.get_tree().physics_frame
		tray._process(0.05)
	check(tray.presence.alpha < 0.05, "閒置一段時間後彈匣淡出")
	Settings.set_hud_auto_hide(previous)
	await end_level(level)


func _test_firing_and_reload() -> void:
	var level := await start_level(PropsSuite.level_data())
	var tray := level.hud.ammo_tray
	var player := level.player
	await frames(5)
	player.loadout.consume_ammo()
	await frames(2)
	var ejected := 0
	for i in AmmoTray.EJECT_SLOTS:
		if tray._eject_age[i] < AmmoTray.EJECT_TIME:
			ejected += 1
	check(ejected >= 1, "開槍時彈殼彈出")
	check(tray.presence.alpha > 0.5, "開槍時彈匣彈出")
	# 打到不到四分之一：常駐、圖示變紅。
	while player.loadout.mag_in(0) > 2:
		player.loadout.consume_ammo()
	await frames(3)
	check(tray.is_low(), "彈量不到四分之一標示為低量")
	var previous := Settings.get_hud_auto_hide()
	Settings.set_hud_auto_hide(true)
	for i in 200:
		tray._process(0.05)
	check(tray.presence.alpha > 0.9, "低彈量時彈匣常駐")
	Settings.set_hud_auto_hide(previous)
	# 換彈：依序填回。
	player.loadout.start_reload()
	var seen_partial := false
	for i in 120:
		await runner.get_tree().physics_frame
		if tray._reloading and tray._refill > float(tray._refill_from) + 1.0 and tray._refill < float(tray.icon_count()) - 1.0:
			seen_partial = true
		if not player.is_reloading():
			break
	check(seen_partial, "換彈時圖示依序填回（中途有部分填滿）")
	await frames(3)
	check(player.loadout.mag_in(0) == 12 and is_equal_approx(tray._refill, 12.0), "換彈完成後整排都是滿的")
	await end_level(level)


func _test_energy_weapon() -> void:
	var level := await start_level(PropsSuite.level_data())
	var tray := level.hud.ammo_tray
	level.player.loadout.equip(load("res://data/weapons/railgun.tres") as WeaponData)
	await frames(4)
	check(tray.is_energy and tray.max_ammo == 3, "能量武器改用電池格")
	level.player.loadout.consume_ammo()
	await frames(3)
	var ejected := 0
	for i in AmmoTray.EJECT_SLOTS:
		if tray._eject_age[i] < AmmoTray.EJECT_TIME:
			ejected += 1
	check(ejected == 0, "能量武器不彈出彈殼")
	await end_level(level)
