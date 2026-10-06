class_name AmmoTraySuite
extends TestSuite
## 主角旁的彈帶（NE-42、NE-212）：常駐一排十顆、位置與面向、開槍最近的一顆彈出且其餘往主角方向補位、
## 換彈依序填回、低彈量變紅、壓縮倍率、能量武器，以及緩衝區大小固定。


func run() -> void:
	_test_compression()
	await _test_tray_follows_loadout()
	await _test_side_and_fade()
	await _test_firing_and_reload()
	await _test_energy_weapon()


func _test_compression() -> void:
	check(is_equal_approx(AmmoTray.per_icon_for(9), 1.0) and is_equal_approx(AmmoTray.per_icon_for(10), 1.0), "10 發以內一顆圖示一發")
	check(is_equal_approx(AmmoTray.per_icon_for(30), 3.0) and is_equal_approx(AmmoTray.per_icon_for(12), 1.2), "更大的彈匣一顆圖示代表 容量 / 10 發（長度不變）")
	check(is_equal_approx(AmmoTray.per_icon_for(60), 6.0), "60 發的彈匣一顆圖示代表 6 發")


func _wait_frames(count: int) -> void:
	for i in count:
		await runner.get_tree().process_frame


func _test_tray_follows_loadout() -> void:
	var level := await start_level(PropsSuite.level_data())
	var tray := level.hud.ammo_tray
	var player := level.player
	check(tray != null, "HUD 有主角旁的彈匣")
	await frames(3)
	check(tray.icon_count() == 10, "手槍 12 發也是一排十顆")
	player.loadout.equip(load("res://data/weapons/rifle.tres") as WeaponData)
	await frames(2)
	check(tray.icon_count() == 10 and tray.per_icon() > 2.9, "30 發的步槍一樣十顆，一顆代表三發")
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
	# 常駐：即使開啟 HUD 自動淡出、閒置很久也一直完整顯示。
	var previous := Settings.get_hud_auto_hide()
	Settings.set_hud_auto_hide(true)
	for i in 400:
		await runner.get_tree().physics_frame
		tray._process(0.05)
	check(tray.presence.alpha > 0.95 and tray.is_showing(), "閒置很久彈帶也常駐顯示")
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
	check(tray.presence.alpha > 0.5, "開槍時彈帶顯示")
	var newest := tray._eject_pos[posmod(tray._eject_next - 1, AmmoTray.EJECT_SLOTS)]
	check(newest.distance_to(tray._slot_position(0)) < AmmoTray.STEP.x * 3.0, "彈出的是離主角最近的那一顆（離第 0 格 %.1f px）" % newest.distance_to(tray._slot_position(0)))
	# 補位：打掉一整顆圖示之後，剩下的子彈從遠一格的位置往主角的方向滑回來，然後停在原位（12 發的彈匣一顆圖示約 1.2 發，所以不是每槍都打掉一顆）。
	var slid := 0.0
	for i in 3:
		player.loadout.consume_ammo()
		slid = maxf(slid, tray.slide())
	check(slid > 0.0 and slid <= AmmoTray.SLIDE_MAX_STEPS * AmmoTray.STEP.x + 0.01, "打掉整顆圖示後剩下的子彈有補位滑動（%.2f px，有上限）" % slid)
	for i in 40:
		tray._process(0.05)
	check(tray.slide() == 0.0, "補位滑動最後停在原位")
	# 打到不到四分之一：圖示變紅。
	while player.loadout.mag_in(0) > 2:
		player.loadout.consume_ammo()
	await frames(3)
	check(tray.is_low(), "彈量不到四分之一標示為低量")
	for i in 200:
		tray._process(0.05)
	check(tray.presence.alpha > 0.9, "低彈量時彈帶顯示")
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
	check(player.loadout.mag_in(0) == 12 and is_equal_approx(tray._refill, 10.0), "換彈完成後整排都是滿的")
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
