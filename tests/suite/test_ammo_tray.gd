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
	await _test_screen_edge()


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
	AimInput.using_gamepad = true  # Synthetic action presses choose their source explicitly.
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


## NE-264：主角靠近畫面邊緣、背後放不下時，彈帶與生命護盾標籤一起移到頭頂，完整留在畫面裡；
## 轉身時整排平滑收攏再展開，不在一格內跳到另一邊。
func _test_screen_edge() -> void:
	var level := await start_level(PropsSuite.level_data())
	var tray := level.hud.ammo_tray
	var tag := level.hud.vitals_tag
	var player := level.player
	player.global_position.x = 20.0
	player.velocity = Vector2.ZERO
	AimInput.using_gamepad = true
	Input.action_press(&"aim_right")
	await frames(60)
	var view := tray.get_viewport_rect().size.x
	var to_screen := tray.get_viewport().get_canvas_transform()
	var head: Vector2 = to_screen * (player.global_position + HudPlacement.HEAD_OFFSET)
	check(head.x < HudPlacement.ROOM_NEEDED, "測試站位：主角在畫面左緣附近（頭 x=%.0f）" % head.x)
	var inside := true
	for i in tray.icon_count():
		var rect := tray._icon_draw_rect(i, tray.icon_count(), 1.0)
		if rect.position.x < 0.0 or rect.end.x > view:
			inside = false
	check(inside, "面向右站在左緣：彈帶每一顆都在畫面內")
	check(tray._above > 0.99 and tray._pos.y < head.y, "背後放不下時彈帶移到頭頂上方")
	check(tag._above > 0.99 and tag._pos.y + 20.0 < tray._pos.y and tag._pos.x >= 0.0, "生命護盾標籤也移到頭頂，在彈帶上面一列")
	# 武器欄：和主角重疊時讓位變淡，沒有重疊時維持完整亮度（街道的實際空隙另由截圖確認）。
	var bar := level.hud.weapon_bar
	var feet: Vector2 = to_screen * (player.global_position + WeaponBar.PLAYER_BOX.position)
	var overlap := Rect2(feet, WeaponBar.PLAYER_BOX.size * to_screen.get_scale()).intersects(bar.get_global_rect())
	check(bar.is_making_way() == overlap, "武器欄只在和主角重疊時讓位（重疊=%s）" % overlap)
	player.global_position.x = 300.0
	await frames(40)
	check(not bar.is_making_way(), "主角離開左下角後武器欄恢復完整亮度")
	player.global_position.x = 20.0
	await frames(40)
	# 轉身：彈帶從頭頂回到背後（右邊有空間），每一格的移動都很小。
	Input.action_release(&"aim_right")
	Input.action_press(&"aim_left")
	# 量離主角最遠的那一顆：舊做法轉身時它會一格內跳到另一邊。
	var far := tray.icon_count() - 1
	var largest := 0.0
	var last := tray._slot_position(far)
	for i in 40:
		await frames(1)
		var now := tray._slot_position(far)
		largest = maxf(largest, now.distance_to(last))
		last = now
	Input.action_release(&"aim_left")
	check(largest < 24.0, "轉身時彈帶平滑移動（每格最多 %.1f 畫面像素）" % largest)
	check(tray.side() > 0.0 and tray._above < 0.01, "面向左、背後（右側）有空間時回到背後")
	# 跳躍與落地：彈帶跟著主角平滑移動，不會一格內跳位置。
	player.velocity.y = -380.0
	largest = 0.0
	last = tray._slot_position(far)
	for i in 50:
		await frames(1)
		var now := tray._slot_position(far)
		largest = maxf(largest, now.distance_to(last))
		last = now
	check(largest < 24.0, "跳躍時彈帶平滑移動（每格最多 %.1f 畫面像素）" % largest)
	# 跑步穿過切換點：從左緣面向右往畫面中間跑，彈帶從頭頂回到背後，過程平滑。
	player.global_position.x = 20.0
	Input.action_press(&"aim_right")
	await frames(40)
	Input.action_press(&"move_right")
	largest = 0.0
	last = tray._slot_position(far)
	var was_above := tray._above
	for i in 240:
		await frames(1)
		var now := tray._slot_position(far)
		largest = maxf(largest, now.distance_to(last))
		last = now
		if tray._above < 0.01:
			break
	Input.action_release(&"move_right")
	Input.action_release(&"aim_right")
	check(was_above > 0.99 and tray._above < 0.01, "跑離畫面邊緣後彈帶從頭頂回到背後")
	check(largest < 24.0, "跑步經過切換點時彈帶平滑移動（每格最多 %.1f 畫面像素）" % largest)
	await end_level(level)
