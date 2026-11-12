class_name AmmoTraySuite
extends TestSuite
## 主角旁的彈帶（NE-42、NE-212）：常駐一排十顆、位置與面向、開槍最近的一顆彈出且其餘往主角方向補位、
## 換彈依序填回、低彈量變紅、壓縮倍率、能量武器，以及緩衝區大小固定。


func run() -> void:
	_test_compression()
	_test_head_route()
	_test_guide_clearance()
	_test_full_layout_bounds()
	_test_aim_corridor()
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
	_test_head_bounds(player)
	_test_route_reset(level)
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
	# 主角從左緣一步步往內走：每個站位彈帶與標籤都同在背後或同在頭上，不會一個上一個下而疊在一起。
	var agree := true
	for x in range(20, 200, 3):
		player.global_position.x = float(x)
		await frames(15)
		if (tray._above > 0.5) != (tag._above > 0.5):
			agree = false
	check(agree, "彈帶與生命護盾標籤在每個站位都一起決定放背後或頭上")
	player.global_position.x = 20.0
	await frames(40)
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
	# NE-256 拉近後，面向右時主角固定站在畫面左側（前方留 300 像素）；轉身面向左，主角才移到畫面右側、真的離開左下角。
	player.global_position.x = 300.0
	Input.action_release(&"aim_right")
	Input.action_press(&"aim_left")
	await frames(120)
	check(not bar.is_making_way(), "主角離開左下角後武器欄恢復完整亮度")
	Input.action_release(&"aim_left")
	Input.action_press(&"aim_right")
	player.global_position.x = 20.0
	await frames(120)
	# 轉身：彈帶從頭頂回到背後（右邊有空間），每一格的移動都很小。
	Input.action_release(&"aim_right")
	Input.action_press(&"aim_left")
	# 量離主角最遠的那一顆：舊做法轉身時它會一格內跳到另一邊。
	# Sample one controlled 60Hz UI step per physics sample; rendered frames
	# may otherwise batch several physics ticks under load.
	const FOLLOW_TEST_DELTA := 1.0 / 60.0
	var far := tray.icon_count() - 1
	var largest := 0.0
	var last := tray._slot_position(far)
	tray.set_process(false)
	for i in 40:
		await frames(1)
		tray._process(FOLLOW_TEST_DELTA)
		var now := tray._slot_position(far)
		largest = maxf(largest, now.distance_to(last))
		last = now
	tray.set_process(true)
	Input.action_release(&"aim_left")
	check(largest < 24.0, "轉身時彈帶平滑移動（每格最多 %.1f 畫面像素）" % largest)
	check(tray.side() > 0.0 and tray._above < 0.01, "面向左、背後（右側）有空間時回到背後")
	# 跳躍與落地：彈帶跟著主角平滑移動，不會一格內跳位置。
	player.velocity.y = -380.0
	largest = 0.0
	last = tray._slot_position(far)
	tray.set_process(false)
	for i in 50:
		await frames(1)
		tray._process(FOLLOW_TEST_DELTA)
		var now := tray._slot_position(far)
		largest = maxf(largest, now.distance_to(last))
		last = now
	tray.set_process(true)
	check(largest < 24.0, "跳躍時彈帶平滑移動（每格最多 %.1f 畫面像素）" % largest)
	# 跑步穿過切換點：從左緣面向右往畫面中間跑，彈帶從頭頂回到背後，過程平滑。
	player.global_position.x = 20.0
	Input.action_press(&"aim_right")
	await frames(40)
	# Keep the original right-facing setup and waits. Public upward aim
	# removes horizontal aim lookahead so the camera can actually expose
	# 108px behind the actor; the props crate at x160 remains unchanged.
	Input.action_release(&"aim_right")
	Input.action_press(&"aim_up")
	Input.action_press(&"move_right")
	largest = 0.0
	last = tray._slot_position(far)
	var was_above := tray._above
	tray.set_process(false)
	for i in 240:
		await frames(1)
		tray._process(FOLLOW_TEST_DELTA)
		var now := tray._slot_position(far)
		largest = maxf(largest, now.distance_to(last))
		last = now
		if tray._above < 0.01:
			break
	tray.set_process(true)
	Input.action_release(&"move_right")
	Input.action_release(&"aim_right")
	Input.action_release(&"aim_up")
	var end_anchor: Vector2 = tray.get_viewport().get_canvas_transform() * player.global_position
	check(HudPlacement.above_target(end_anchor.x, -float(player.facing), view) == 0.0, "公開上瞄run真的到達背後空間足夠的站位")
	check(was_above > 0.99 and tray._above < 0.01, "跑離畫面邊緣後彈帶從頭頂回到背後")
	check(largest < 24.0, "跑步經過切換點時彈帶平滑移動（每格最多 %.1f 畫面像素）" % largest)
	await end_level(level)



## A known head occupies the diagonal between safe endpoints. Both directions
## must use the upper corridor; the old direct endpoint lerp fails this check.
func _test_head_route() -> void:
	var head := Rect2(40, 0, 20, 20)
	var clear := true
	for step in 61:
		var p := float(step) / 60.0
		var point := HudPlacement.routed_target(Vector2(20, 20), Vector2(60, -10), p)
		if head.has_point(point):
			clear = false
	check(clear, "頭頂與背側往返走頭外的上方通道，不斜穿頭部")
	var beside := HudPlacement.follow_route(Vector2(20, 0), Vector2(20, 20), 0.0, 1.0 / 30.0, 18.0)
	check(beside.y > 0.0 and beside.y < 20.0, "背側仍保留自然垂直跟隨，不因路徑修正取消跳躍緩動")
	var upper := HudPlacement.follow_route(Vector2(20, 20), Vector2(60, -10), 0.75, 1.0 / 30.0, 18.0)
	check(upper.y <= -10.0, "頭頂橫移不被第二次位置插值拉回頭部")
	var bounds := HudPlacement.FollowState.new()
	check(not bounds.screen_rect(null, Transform2D.IDENTITY).has_area(), "玩家已釋放或不存在時頭部查詢安全回空，不保留舊drawable")


func _test_head_bounds(player: Player) -> void:
	var cache := HudPlacement.FollowState.new()
	var canvas := player.get_viewport().get_canvas_transform()
	var expected := canvas * Rect2(player.global_position + HudPlacement.HEAD_OFFSET - Vector2(10, 10), Vector2(20, 20))
	var visual := player._visual
	var rig := visual.rig
	var actual := cache.screen_rect(player, canvas)
	check(actual.has_area(), "頭部界取真正可見Sprite而非同名骨頭")
	player._visual = null
	var missing_visual := cache.screen_rect(player, canvas)
	player._visual = visual
	check(missing_visual.is_equal_approx(expected), "視覺暫不可用時安全回到保守頭部界")
	var empty := CharacterRig.new()
	visual.add_child(empty)
	visual.rig = empty
	var missing_head := cache.screen_rect(player, canvas)
	visual.rig = rig
	empty.free()
	check(missing_head.is_equal_approx(expected), "換成沒有頭部的rig時不沿用舊Sprite")
	check(cache.screen_rect(player, canvas).is_equal_approx(actual), "恢復原rig時重新解析頭部而非沿用缺件fallback")
	var head := rig.contact_part(&"head")
	var texture := head.texture
	head.texture = null
	var missing_texture := cache.screen_rect(player, canvas)
	head.texture = texture
	check(missing_texture.is_equal_approx(expected), "頭部貼圖缺失時有安全fallback")
	var parent := head.get_parent()
	var index := head.get_index()
	parent.remove_child(head)
	var outside := cache.screen_rect(player, canvas)
	parent.add_child(head)
	parent.move_child(head, index)
	check(outside.is_equal_approx(expected), "頭部離tree時不使用已失效的drawable位置")
	check(cache.screen_rect(player, canvas).is_equal_approx(actual), "頭部回到原rig後恢復真正drawable界")


## Unit fixture only: no physics step occurs while the actor is relocated.
## The native public-input trace remains separate and never calls _follow.
func _test_route_reset(level: Level) -> void:
	var player := level.player
	var tray := level.hud.ammo_tray
	var tag := level.hud.vitals_tag
	var world := player.global_position
	var tray_saved := {}
	var tag_saved := {}
	for key in ["_pos", "_side", "_draw_side", "_above", "_has_pos", "_placement"]:
		tray_saved[key] = tray.get(key)
	for key in ["_pos", "_side", "_above", "_has_pos", "_placement"]:
		tag_saved[key] = tag.get(key)
	tray._placement = HudPlacement.FollowState.new()
	tag._placement = HudPlacement.FollowState.new()
	tray._follow(player, 1.0 / 60.0)
	tag._follow(player, 1.0 / 60.0)
	tray._above = 0.5
	tray._draw_side = 0.0
	tag._above = 0.5
	tag._side = 0.0
	player.global_position += Vector2(200, 200)
	tray._follow(player, 1.0 / 60.0)
	tag._follow(player, 1.0 / 60.0)
	var canvas := player.get_viewport().get_canvas_transform()
	var anchor := canvas * (player.global_position + Vector2(0, -34))
	var head := canvas * (player.global_position + HudPlacement.HEAD_OFFSET)
	var wanted := HudPlacement.above_target(anchor.x, -float(player.facing), tray.get_viewport_rect().size.x)
	check(is_equal_approx(tray._above, wanted) and is_equal_approx(tray._draw_side, tray.side()), "大位移立即復位整個彈帶route，不沿用半途翻側")
	check(is_equal_approx(tag._above, wanted) and is_equal_approx(tag._side, -float(player.facing)), "大位移立即復位生命護盾route")
	if wanted == 0.0:
		check(is_equal_approx(tray._pos.y, anchor.y - AmmoTray.LIFT), "跨區後背側彈帶首步已在新位置，不從舊場景慢追")
		check(is_equal_approx(tag._pos.y, head.y - 10.0), "跨區後背側生命護盾首步已在新位置")
	else:
		check(tray._pos.y < head.y - HudPlacement.ABOVE_GAP and tag._pos.y < tray._pos.y, "跨區後頭頂HUD首步已到新頭部上方")
	var state := HudPlacement.FollowState.new()
	check(state.should_reset(player, canvas, anchor, AmmoTray.SNAP_DISTANCE), "首次Player配置復位")
	check(not state.should_reset(player, canvas, anchor, AmmoTray.SNAP_DISTANCE), "同Player與anchor不把正常route角點當傳送")
	var replacement := Player.new()
	# This unit-only actor never runs _ready, which normally parents melee.
	# Own the already-constructed Node before freeing this fixture.
	replacement.add_child(replacement.melee)
	check(state.should_reset(replacement, canvas, anchor, AmmoTray.SNAP_DISTANCE), "即使anchor相同，Player替換也復位route")
	replacement.free()
	player.global_position = world
	for key in tray_saved:
		tray.set(key, tray_saved[key])
	for key in tag_saved:
		tag.set(key, tag_saved[key])



func _test_guide_clearance() -> void:
	var guide := HudPlacement.FollowState.new()
	guide.update_guide(Rect2(40, 148, 13, 16), Vector2(43, 258), 1.0 / 30.0, 3.0, 16.0, 34.4, 18.0)
	var previous := guide.guide_y
	guide.update_guide(Rect2(40, 115, 13, 16), Vector2(43, 233), 1.0 / 30.0, 3.0, 16.0, 34.4, 18.0)
	check(absf(guide.guide_y - previous) < 24.0, "起跳頭界移33時保留整行緩衝，不硬跳到名義頭頂")
	check(guide.guide_y + 13.0 <= 115.0, "緩衝仍讓完整備彈字下緣離開真head安全界")
	check(not guide.guide_ready, "頭界仍快速變動時延後橫移，不能提早切過頭部")
	for i in 60:
		guide.update_guide(Rect2(40, 52, 13, 16), Vector2(43, 190), 1.0 / 30.0, 3.0, 16.0, 34.4, 18.0)
	check(guide.guide_y >= 34.4 and guide.guide_y + 13.0 <= 52.0 and guide.guide_ready, "整個頭頂stack留在viewport內且仍保持head clearance")


func _test_full_layout_bounds() -> void:
	var head := Rect2(133.3497, 180.7509, 21.0197, 21.7462)
	var origin := Vector2(86.9313, 168.0405)
	var plate := Rect2(origin, Vector2(51, 19))
	var fitted := HudPlacement.beside_position(origin, plate, head, -1, 640)
	check(fitted.x + plate.size.x <= head.position.x - HudPlacement.ROW_GAP, "真上瞄偏頭時生命標籤按實際head外緣讓位，不只按腳底偏移")
	check(fitted.x >= HudPlacement.EDGE_MARGIN, "head讓位與view clamp同時成立，不再被clamp推回頭部")
	var cramped := HudPlacement.beside_position(Vector2.ZERO, Rect2(0, 0, 80, 19), Rect2(30, 40, 20, 20), -1, 640)
	check(not is_finite(cramped.x), "橫向容不下完整文字時拒絕背側位置，交回既有頭頂route")
	var tray := AmmoTray.new()
	tray.max_ammo = 12
	tray.ammo = 12
	tray._per_icon = 1.2
	tray._draw_side = 1.0
	tray.reserve = -1
	tray._refresh_obstacle_text_metrics()
	var start := Vector2(8.819, 121.921)
	var bounds := tray._layout_bounds_at(start, 1.0)
	start.x += HudPlacement.clamp_shift(bounds.position.x, bounds.size.x, 640)
	var corrected := tray._layout_bounds_at(start, 1.0)
	check(corrected.position.x >= HudPlacement.EDGE_MARGIN and corrected.end.x <= 640.0 - HudPlacement.EDGE_MARGIN, "翻側頭頂reserve完整字形含shadow邊界留在view，不只clamp icons")
	tray.free()


func _test_aim_corridor() -> void:
	var placement := HudPlacement.FollowState.new()
	placement.update_guide(Rect2(32, 146, 19, 20), Vector2(43, 256), 1.0 / 30.0, 3, 16, 39, 18, 640, Vector2(35, 134))
	check(placement.guide_x - HudPlacement.ROOM_NEEDED * 0.5 >= 54.0, "邊緣頭頂整組按真head外緣預留內側通道，不等UP首格才大步投影")
	check(placement.lower_y - 35.0 > 166.0 and placement.lower_y - 35.0 > 134.0, "下方通道整組上緣在真head與槍口下方")
	placement.choose_corridor(0.0, 1.0, -1.0, Vector2.RIGHT, 220, 194)
	check(placement.lower_mode, "從射線前側翻回背側沿下方L，不抬升穿過水平射線")
	placement.choose_corridor(0.0, -1.0, -1.0, Vector2.RIGHT, 170, 194)
	check(not placement.lower_mode, "回到最終背側後重置下方通道，不永久留在繞路狀態")

	placement.choose_corridor(0.0, 1.0, -1.0, Vector2.RIGHT, 177, 194)
	check(not placement.lower_mode, "本來在槍口上的shield留在上方L，不跟下方Ammo越過射線")
