class_name CombatHudSuite
extends TestSuite
## 戰鬥介面（NE-43）：頭目血條（登場展開、階段刻度閃光）、信用點讀數、義體電量、橫幅分類、
## 通訊對話框滑入，以及每個元素都有一句說明。


func run() -> void:
	await _test_boss_bar()
	await _test_boss_bar_accessibility()
	await _test_player_vitals_accessibility()
	await _test_credits_tag()
	await _test_credit_counter_accessibility()
	await _test_banner_kinds()
	await _test_tooltips()
	await _test_cyber_motion()
	await _test_reload_prompt_clearance()
	await _test_aim_feedback_accessibility()
	await _test_localized_hud_help()
	await preload("res://tests/helpers/hud_background_hover_checks.gd").run(self)
	await _test_radio_panel()
	await _test_radio_card()
	await _test_radio_clearance()
	await _test_radio_tall_clearance(false)
	await _test_radio_tall_clearance(true)
	await _test_radio_crowded_gutter()


func _test_reload_prompt_clearance() -> void:
	var level := await start_level(PropsSuite.level_data())
	var ring := level.hud.ammo_ring
	var loadout := level.player.loadout
	var slot := loadout.active_slot
	loadout.set_ammo(slot, 2, -1)
	await frames(15)
	var bounds_for_ring: Callable = PromptLayout._obstacles.get(ring, Callable())
	var reserved: Rect2 = bounds_for_ring.call() if bounds_for_ring.is_valid() else Rect2()
	var to_world := level.get_viewport().get_canvas_transform().affine_inverse()
	check(reserved.has_point(to_world * ring._point) and reserved.has_point(to_world * (ring._point + Vector2(-15, 24))),
			"world prompts leave the low-ammo hint and reticle readable together")
	if bounds_for_ring.is_valid():
		check(loadout.start_reload(), "the equipped magazine starts a reload")
		await frames(2)
		reserved = bounds_for_ring.call()
		check(reserved.has_point(to_world * (ring._point + Vector2(-15, 24))),
				"active reload feedback reserves the same label position")
		loadout.set_ammo(slot, loadout.active_weapon().magazine_size, -1)
		await frames(2)
		reserved = bounds_for_ring.call()
		check(not reserved.has_area(), "a full magazine does not reserve space around the crosshair")
	await end_level(level)


func _test_aim_feedback_accessibility() -> void:
	var motion_before := Settings.get_reduce_ui_motion()
	var flashes_before := Settings.get_reduce_flashes()
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	var level := await start_level(PropsSuite.level_data())
	var reticle := level.hud.crosshair
	var ring := level.hud.ammo_ring
	reticle._bloom = 0.35
	var aim_gap := reticle._tick_gap()
	EventBus.dry_fired.emit()
	reticle._dry_left *= 0.8
	EventBus.hit_confirmed.emit(Vector2.ZERO, true)
	EventBus.hit_marker.emit(&"weak")
	check(reticle._tick_gap() > aim_gap and reticle._draw_center() != reticle._screen_point,
			"ordinary reticle widens on a kill and recoils from a dry shot")
	Settings.set_reduce_flashes(true)
	check(is_equal_approx(reticle._flash_scale, Settings.REDUCED_FLASH_SCALE) and ring._reduce_pulses
			and not ring._reduce_motion and reticle._tick_gap() > aim_gap,
			"reduced flashes dims burst feedback without removing reticle motion")
	Settings.set_reduce_ui_motion(true)
	check(reticle._draw_center() == reticle._screen_point and is_equal_approx(reticle._tick_gap(), aim_gap)
			and reticle._kill_left > 0.0 and reticle._weak_left > 0.0,
			"reduced motion stops active decorative displacement and keeps real aim and hit markers")
	EventBus.reload_completed.emit()
	check(ring._done_left == AmmoRing.DONE_TIME and ring._reduce_pulses and ring._reduce_motion,
			"reduced settings keep reload completion available at a fixed radius")
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	check(reticle._draw_center() == reticle._screen_point and is_equal_approx(reticle._tick_gap(), aim_gap)
			and not ring._reduce_pulses, "restoring ordinary settings does not replay completed aim motion")
	EventBus.hit_confirmed.emit(Vector2.ZERO, true)
	check(reticle._tick_gap() > aim_gap, "the next actual kill starts ordinary reticle motion again")
	Settings.set_reduce_ui_motion(motion_before)
	Settings.set_reduce_flashes(flashes_before)
	await end_level(level)


func _test_boss_bar() -> void:
	var level := await start_level(PropsSuite.level_data())
	var bar := level.hud.boss_bar
	check(not bar.is_open(), "沒有頭目時血條不顯示")
	EventBus.boss_started.emit("測試頭目", 100)
	await frames(2)
	check(bar.is_open() and bar.scale.x < 1.0, "頭目登場時血條從中間開始展開")
	for i in 90:
		await runner.get_tree().physics_frame
		if bar.scale.x >= 0.99:
			break
	check(bar.scale.x >= 0.99, "展開完成後是完整寬度")
	EventBus.boss_health_changed.emit(70, 100)
	check(is_equal_approx(bar.ratio(), 0.7) and bar._flash == 0.0, "還沒跨過刻度時不閃")
	EventBus.boss_health_changed.emit(49, 100)
	check(bar._flash > 0.5, "跨過階段刻度時閃一下")
	EventBus.boss_health_changed.emit(30, 100)
	check(is_equal_approx(bar.ratio(), 0.3), "血條跟著血量")
	EventBus.boss_defeated.emit()
	for i in 60:
		await runner.get_tree().physics_frame
		if not bar.is_open():
			break
	check(not bar.is_open(), "頭目擊敗後血條收起")
	await end_level(level)


func _test_boss_bar_accessibility() -> void:
	var previous_motion := Settings.get_reduce_ui_motion()
	var previous_flashes := Settings.get_reduce_flashes()
	var level := await start_level(PropsSuite.level_data())
	var bar := level.hud.boss_bar
	for mode: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		Settings.set_reduce_ui_motion(bool(mode.x))
		Settings.set_reduce_flashes(bool(mode.y))
		EventBus.boss_started.emit("測試頭目", 100)
		check(bar.visible and bar.scale == Vector2.ONE, "accessible boss bar starts at full width")
		if mode.x:
			check(bar.modulate.a == 1.0, "reduced motion displays the complete boss bar immediately")
		EventBus.boss_health_changed.emit(45, 100)
		check(bar._crossed.has(0) and bar._flash == 0.0 and is_equal_approx(bar._bar._trail, 0.45),
				"the phase tick stays crossed without a phase flash or white trail")
		EventBus.boss_health_changed.emit(15, 100)
		check(is_equal_approx(bar.ratio(), 0.15) and not bar._bar._pulse and not bar._bar.is_processing(),
				"accessible boss bar shows real low health without a pulse or per-frame update")
		EventBus.boss_defeated.emit()
		if mode.x:
			check(not bar.visible, "reduced motion hides the defeated boss bar immediately")
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	EventBus.boss_started.emit("測試頭目", 100)
	check(bar.scale.x < 1.0, "normal mode still starts the boss bar animation")
	Settings.set_reduce_ui_motion(true)
	check(bar.visible and bar.scale == Vector2.ONE and bar.modulate.a == 1.0,
			"switching reduced motion on finishes an active opening animation")
	Settings.set_reduce_ui_motion(false)
	EventBus.boss_health_changed.emit(15, 100)
	check(bar._flash > 0.0 and bar._bar._pulse, "ordinary phase and low-health feedback still run")
	Settings.set_reduce_flashes(true)
	check(bar._flash == 0.0 and not bar._bar.is_processing() and is_equal_approx(bar._bar._trail, 0.15),
			"turning on reduced flashes clears the active pulse, flash, and white trail")
	Settings.set_reduce_flashes(false)
	check(bar._bar._pulse and bar._flash == 0.0, "restoring normal mode resumes low health without replaying the phase flash")
	EventBus.boss_defeated.emit()
	check(bar.visible, "normal mode still fades out a defeated boss bar")
	Settings.set_reduce_ui_motion(true)
	check(not bar.visible, "switching reduced motion on finishes an active close animation")
	Settings.set_reduce_ui_motion(previous_motion)
	Settings.set_reduce_flashes(previous_flashes)
	await end_level(level)


func _test_player_vitals_accessibility() -> void:
	var previous_motion := Settings.get_reduce_ui_motion()
	var previous_flashes := Settings.get_reduce_flashes()
	var level := await start_level(PropsSuite.level_data())
	var tag := level.hud.vitals_tag
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	EventBus.player_health_changed.emit(6, 6)
	tag.presence.alpha = 0.12
	EventBus.player_health_changed.emit(2, 6)
	EventBus.player_guard_changed.emit(25.0, 100.0, false)
	tag._tick_effects(0.05)
	EventBus.player_parried.emit(Vector2.ZERO)
	check(tag.is_low_health() and tag._lost_time[2] >= 0.0 and tag._shake_left > 0.0 and tag.presence.pop > 0.0,
			"ordinary player vitals retain health loss, shake, pop and low-health state")
	check(tag._parry_left > 0.0 and tag._guard_ghost > tag._guard_shown and tag._guard_shown > tag.guard_ratio,
			"ordinary player vitals retain parry feedback and the guard trail")
	Settings.set_reduce_flashes(true)
	var low_color := tag._health_color(1.0)
	tag._time += 0.24
	check(tag._lost_time[2] < 0.0 and tag._parry_left == 0.0 and tag._guard_ghost == tag._guard_shown
			and tag._shake_left > 0.0 and tag._health_color(1.0).is_equal_approx(low_color),
			"reduced flashes clears active light effects while retaining the ordinary motion")
	Settings.set_reduce_ui_motion(true)
	check(tag._shake_left == 0.0 and tag.presence.pop == 0.0 and is_equal_approx(tag._guard_shown, tag.guard_ratio),
			"switching reduced motion on finishes existing shake, pop and guard easing")
	EventBus.player_health_changed.emit(4, 6)
	EventBus.player_guard_changed.emit(0.0, 100.0, true)
	EventBus.player_parried.emit(Vector2.ZERO)
	check(tag.health == 4 and tag._gain_time[2] < 0.0 and tag.guard_broken and tag._guard_shown == 0.0
			and tag._parry_left == 0.0 and tag.presence.pop == 0.0, "reduced player vitals keep the actual new values and break state")
	EventBus.player_guard_changed.emit(65.0, 100.0, false)
	tag._tick_effects(0.05)
	check(is_equal_approx(tag._guard_shown, 0.65) and not tag._guard_rising and not tag.guard_broken,
			"recovery remains visible immediately without a scan or break indicator")
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	check(tag._gain_time[2] < 0.0 and tag._parry_left == 0.0 and tag._shake_left == 0.0,
			"returning to ordinary settings does not replay retired player effects")
	Settings.set_reduce_ui_motion(previous_motion)
	Settings.set_reduce_flashes(previous_flashes)
	await end_level(level)


func _test_credits_tag() -> void:
	var level := await start_level(PropsSuite.level_data())
	var tag := level.hud.credits_tag
	Progression.add_credits(50)
	await frames(2)
	check(tag.value() == 50 and tag._flash > 0.0 and tag._shown < 50.0, "增加信用點時數字往上跳動並閃白")
	for i in 90:
		await runner.get_tree().physics_frame
	check(is_equal_approx(tag._shown, 50.0), "跳動結束後顯示正確數字")
	Progression.credits = 50
	Progression.credits_changed.emit(20, -30)
	await frames(1)
	check(tag.value() == 20 and tag._flash_color == Palette.DANGER, "花費時閃紅")
	await end_level(level)


func _test_credit_counter_accessibility() -> void:
	var previous_motion := Settings.get_reduce_ui_motion()
	var previous_flashes := Settings.get_reduce_flashes()
	var level := await start_level(PropsSuite.level_data())
	var tag := level.hud.credits_tag
	Settings.set_reduce_ui_motion(true)
	Settings.set_reduce_flashes(false)
	check(Progression.add_credits(30) == 30, "the original wallet gains credits")
	check(tag.value() == 30 and tag._shown == 30.0 and tag._flash == 0.0 and not tag.is_processing(),
			"reduced motion immediately shows the actual gain without a flash")
	check(Progression.spend(8) and tag._shown == 22.0 and tag._flash == 0.0 and not tag.is_processing(),
			"reduced motion immediately shows the actual spend without a flash")
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(true)
	check(Progression.add_credits(11) == 11 and tag.value() == 33 and tag._shown < 33.0 and tag._flash == 0.0 and tag.is_processing(),
			"reduced flashes keeps the ordinary count-up without a gain flash")
	check(Progression.spend(4) and tag._shown == 29.0 and tag._flash == 0.0 and not tag.is_processing(),
			"reduced flashes also suppresses the expense flash")
	Settings.set_reduce_ui_motion(true)
	check(Progression.add_credits(7) == 7 and tag._shown == 36.0 and tag._flash == 0.0,
			"both settings keep the credit counter still and correct")
	check(not Progression.spend(37) and tag.value() == 36 and tag._shown == 36.0,
			"an unaffordable expense leaves the displayed balance unchanged")
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	check(Progression.add_credits(8) == 8 and tag._shown < 44.0 and tag._flash > 0.0,
			"ordinary counting and flashing resume for a new gain")
	Settings.set_reduce_ui_motion(true)
	check(tag._shown == 44.0 and tag._flash == 0.0 and not tag.is_processing(),
			"enabling reduced motion immediately finishes the active count-up")
	Settings.set_reduce_ui_motion(false)
	check(Progression.spend(6) and tag._flash > 0.0 and tag._flash_color == Palette.DANGER,
			"ordinary expenses still use the red feedback")
	Settings.set_reduce_flashes(true)
	check(tag.value() == 38 and tag._shown == 38.0 and tag._flash == 0.0 and not tag.is_processing(),
			"enabling reduced flashes clears the active expense flash")
	Settings.set_reduce_ui_motion(previous_motion)
	Settings.set_reduce_flashes(previous_flashes)
	await end_level(level)


func _test_banner_kinds() -> void:
	check(Hud._toast_kind("取得 醫療針") == UiBanner.Kind.ITEM, "取得類提示是物品橫幅")
	check(Hud._toast_kind("警告：回收部接近") == UiBanner.Kind.WARNING, "警告類提示是警告橫幅")
	check(Hud._toast_kind("檢查點") == UiBanner.Kind.INFO, "其他是一般橫幅")
	var level := await start_level(PropsSuite.level_data())
	level.hud.show_toast("檢查點已啟用")
	await frames(10)
	check(level.hud.toast_banner.is_showing(), "提示用橫幅顯示")
	check(absf(level.hud.toast_banner.position.x + level.hud.toast_banner.size.x * 0.5 - 320.0) < 3.0, "橫幅水平置中")
	await _check_pickup_feed(level.hud)
	await end_level(level)


## 取得類提示進左下的拾取紀錄，不佔畫面中央；同一句計次，列數有上限，時間到淡出。
func _check_pickup_feed(hud: Hud) -> void:
	var feed := hud.pickup_feed
	hud.show_toast("取得 測試護符")
	await frames(2)
	check(feed.lines() == PackedStringArray(["取得 測試護符"]) and hud.toast_banner._label.text != "取得 測試護符", "取得類提示進入拾取紀錄，不顯示中央橫幅")
	hud.show_toast("取得 測試護符")
	check(feed.lines() == PackedStringArray(["取得 測試護符 ×2"]), "同一句再出現時計次，不洗版")
	for i in 5:
		hud.show_toast("取得 測試零件 %d" % i)
	check(feed.lines().size() == PickupFeed.MAX_ROWS and feed.lines()[-1] == "取得 測試零件 4", "超過上限時換掉最舊的一行，最新的在最下面")
	await frames(1)
	var credits := hud.credits_tag.get_global_rect()
	var newest := (feed.get_child(feed.get_child_count() - 1) as Control).get_global_rect()
	check(newest.position.y >= credits.end.y and absf(newest.end.x - credits.end.x) < 16.0 and newest.size.x < 200.0, "拾取紀錄在右上角信用點下方靠右，每行只和文字一樣寬")
	Story._scenes["ne228_feed_radio"] = {"mode": "radio", "lines": [{"speaker": "mei", "text": "測試通訊。"}]}
	Story.play(&"ne228_feed_radio", false)
	await frames(2)
	var kept: float = (feed.get_child(feed.get_child_count() - 1) as PickupFeed._Row).left
	await frames(5)
	check(not feed.visible and is_equal_approx((feed.get_child(feed.get_child_count() - 1) as PickupFeed._Row).left, kept), "通訊出現時拾取紀錄讓位，剩餘時間保留")
	Story._scenes.erase("ne228_feed_radio")
	Story._layer.cancel_radio()
	# Feed visibility is published by _process; physics ticks can finish before any UI update.
	await runner.get_tree().create_timer(0.0, true, false, true).timeout
	check(feed.visible and feed.lines().size() == PickupFeed.MAX_ROWS, "通訊結束後拾取紀錄回來")
	var deadline := Time.get_ticks_msec() + int((PickupFeed.HOLD + 1.5) * 1000.0)
	while Time.get_ticks_msec() < deadline and not feed.lines().is_empty():
		await runner.get_tree().process_frame
	await frames(1)
	check(feed.lines().is_empty() and not feed.is_processing(), "時間到後全部淡出，閒置時不再每影格更新")


func _test_tooltips() -> void:
	var level := await start_level(PropsSuite.level_data())
	var hud := level.hud
	await frames(3)
	check(hud.credits_tag.tooltip_text != "", "信用點有說明")
	check(hud.boss_bar.tooltip_text != "", "頭目血條有說明")
	check(hud.cyber_gauge.mouse_filter == Control.MOUSE_FILTER_PASS, "義體電量可以顯示說明")
	for slot in hud.weapon_bar.row_count():
		check(hud.weapon_bar.get_child(slot).get_tooltip() != "", "武器欄第 %d 列有說明" % (slot + 1))
	var empty := hud.weapon_bar.get_child(Loadout.MAX_SLOTS - 1) as Control
	var using_gamepad := InputBindings.using_gamepad
	var previous_device := InputBindings.active_device
	var press := InputEventKey.new()
	press.physical_keycode = KEY_N
	press.pressed = true
	InputBindings.observe_device(press)
	var old_key := InputBindings.get_code(&"weapon_next", 0)
	InputBindings.set_code(&"weapon_next", 0, KEY_N)
	check(empty.get_tooltip().contains(InputBindings.primary_label(&"weapon_next")), "empty weapon slot help uses the new cycling binding before another loadout change")
	InputBindings.set_code(&"weapon_next", 0, old_key)
	InputBindings._set_device(using_gamepad, previous_device)
	await end_level(level)


func _test_cyber_motion() -> void:
	var original := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(true)
	var level := await start_level(PropsSuite.level_data())
	var cyber := level.player.cyber
	var gauge := level.hud.cyber_gauge
	cyber.charge = CyberSystem.MAX_CHARGE
	cyber.debug_set_ability(Progression.find_ability(&"emp_pulse"))
	check(gauge.visible and gauge._ready_to_use and is_equal_approx(gauge._bar.ratio(), 1.0), "reduced motion keeps the ready indicator and full charge")
	check(not gauge.is_processing(), "an ability becoming ready with reduced motion does not start the pulse")
	Settings.set_reduce_ui_motion(false)
	check(gauge.is_processing(), "returning to normal motion starts the current ready pulse")
	Settings.set_reduce_ui_motion(true)
	check(not gauge.is_processing() and gauge._ready_to_use, "enabling reduced motion stops the current pulse immediately")
	check(cyber.try_activate() and not gauge._ready_to_use and gauge._bar.ratio() < 1.0, "reduced motion still displays spent charge")
	Settings.set_reduce_ui_motion(original)
	await end_level(level)


func _test_localized_hud_help() -> void:
	var original := Story.language
	var locales := {
		"zh": ["開啟操作說明", "殘機 ×3", "快速道具", "消耗品", "擊敗敵人"],
		"ja": ["操作ガイド", "残機 ×3", "クイックアイテム", "消耗品", "敵撃破"],
		"en": ["Controls", "Lives ×3", "quick item", "consumables", "defeating enemies"],
	}
	for language: String in locales:
		Story.set_language(language)
		var level := await start_level(PropsSuite.level_data(), 2)
		var hud := level.hud
		check(hud._controls.text == locales[language][0] and hud._lives_label.text == locales[language][1],
				"%s HUD presents the opening help and remaining lives in the selected language" % language)
		var cap := hud._hint_caps[0].get_child(0) as Label
		check(cap.text == InputBindings.primary_label(&"pause"), "%s HUD still shows the active pause binding" % language)
		var bag := level.player.consumables
		var items := hud._items_label
		bag.restore({})
		check(not items.visible, "%s HUD removes the hover target when the bag is empty" % language)
		bag.add(ConsumableBag.find(&"shield_cell"))
		check(items.visible and items.tooltip_text.contains(locales[language][3]) and items.tooltip_text.contains(InputBindings.primary_label(&"inventory")),
				"%s HUD points to the inventory when no quick item is carried" % language)
		bag.add(ConsumableBag.find(&"med_injector"))
		check(items.tooltip_text.contains(locales[language][2]) and items.tooltip_text.contains(InputBindings.primary_label(&"use_item")),
				"%s HUD says how to use the current quick item" % language)
		check(hud.cyber_gauge.tooltip_text.contains(locales[language][4]) and hud.cyber_gauge.tooltip_text.contains(InputBindings.primary_label(&"ability")),
				"%s HUD explains cyber charge and the current activation binding" % language)
		await end_level(level)
	Story.set_language(original)


func _test_radio_panel() -> void:
	Story._scenes["test_radio_panel"] = {"mode": "radio", "lines": [{"speaker": "mei", "text": "測試通訊。"}]}
	var layer: DialogueLayer = Story._layer
	# 清掉前面測試留下的通訊佇列與面板，才看得到滑入。
	layer._radio_queue.clear()
	layer._radio_active = false
	layer._radio_root.visible = false
	layer._radio_root.modulate.a = 0.0
	check(Story.play(&"test_radio_panel", false), "可以播放通訊")
	# 播放會同步設定滑入起點；等三個影格可能已超過 0.15 秒，不能代表「剛出現」。
	check(layer._radio_root.visible and layer._radio_root.modulate.a < 1.0, "通訊面板從側邊滑入（剛出現時還沒完全不透明）")
	for i in 40:
		await runner.get_tree().physics_frame
	check(layer._radio_root.modulate.a > 0.95 and layer._radio_root.position.is_equal_approx(DialogueLayer.RADIO_HOME), "滑入後停在定位")
	check(layer._radio_bar.color != Color.BLACK, "講者名字旁有顏色條")
	Story._scenes.erase("test_radio_panel")
	for i in 400:
		await runner.get_tree().physics_frame
		if not layer._radio_active:
			break


## 通訊對話框的外觀（NE-274）：名牌只有名字；講者的顏色用在頭像框與名牌；頭像格是固定的方格、沒有頭像也不留空框；
## 長句之後接短句會縮回去；看得出這一句還會停多久；字不超出面板。
func _test_radio_card() -> void:
	var level := await start_level(PropsSuite.level_data())
	var layer: DialogueLayer = Story._layer
	var old_skip := Story.auto_skip
	Story.auto_skip = false
	layer.cancel_radio()
	await frames(2)
	var card := layer._radio_root as RadioCard
	check(card != null, "通訊對話框是通訊卡片")
	if card == null:
		Story.auto_skip = old_skip
		await end_level(level)
		return
	var long_line: Array[Dictionary] = [{"name": "老K", "color": Color("ffd23f"), "portrait": "res://art/portraits/old_k.png",
		"text": "倉庫的電是從隔壁偷接的，燈會閃。看到快壞的燈就繞過去，別站在下面。"}]
	layer.enqueue_radio(&"test_card_long", long_line)
	# 卡片在自己的畫面更新裡跟上講者的顏色：等到它更新過（機器忙的時候幾個物理影格可能擠在同一個畫面影格）。
	for i in 60:
		await frames(1)
		if card._cell_box.border.is_equal_approx(Color("ffd23f")):
			break
	check(layer._radio_name.text == "老K", "名牌只寫講者的名字（%s）" % layer._radio_name.text)
	check(card._cell_box.border.is_equal_approx(Color("ffd23f")) and card._box.bracket.a > 0.0 and card._plate_box.border != RadioCard.EDGE,
			"頭像框、角標與名牌的邊用講者的顏色")
	check(card.radio_speaking(), "字還在出現時訊號格是「講話中」")
	var early := card.size.y
	check(layer.radio_hold_ratio() < 0.0, "字還在出現時不顯示停留線")
	for i in 600:
		if layer._radio_text.visible_ratio >= 1.0:
			break
		await frames(1)
	await frames(3)
	var tall := card.size.y
	var cell := card._cell.size
	check(layer._radio_text.get_line_count() >= 2, "長句排成兩行")
	check(is_equal_approx(early, tall), "面板一出現就是兩行的高度，逐字顯示時不會中途長高（%.0f → %.0f）" % [early, tall])
	check(is_equal_approx(cell.x, RadioCard.PORTRAIT_SIZE) and is_equal_approx(cell.y, RadioCard.PORTRAIT_SIZE), "頭像格是固定的方格，不跟著句子拉長（%s）" % cell)
	check(card.get_global_rect().grow(1.0).encloses(layer._radio_text.get_global_rect()), "字在面板裡面")
	var first := layer.radio_hold_ratio()
	await frames(30)
	var later := layer.radio_hold_ratio()
	check(first > 0.0 and first <= 1.0 and later < first and not card.radio_speaking(), "整句出現後停留線開始倒數（%.2f → %.2f）" % [first, later])
	# 接一句沒有頭像的短句：縮回一行、頭像格還在。
	layer.cancel_radio()
	var short_line: Array[Dictionary] = [{"name": "不明訊號", "color": Color("9aa7b4"), "portrait": "", "text": "有人嗎。"}]
	layer.enqueue_radio(&"test_card_short", short_line)
	for i in 60:
		await frames(1)
		if card._cell_box.border.is_equal_approx(Color("9aa7b4")) and card.size.y < tall - 4.0:
			break
	check(card.size.y < tall - 4.0, "長句之後接短句，面板縮回去（%.0f → %.0f）" % [tall, card.size.y])
	check(not card.portrait.visible and card._cell.visible and is_equal_approx(card._cell.size.x, RadioCard.PORTRAIT_SIZE),
			"沒有頭像的講者：頭像格還在（畫只有聲音的波形），不留空框")
	check(card._cell_box.border.is_equal_approx(Color("9aa7b4")), "換講者時顏色跟著換")
	layer.cancel_radio()
	Story.auto_skip = old_skip
	await end_level(level)


## A declared screen-space obstacle exercises placement, not character art.
func _test_radio_clearance() -> void:
	var layer: DialogueLayer = Story._layer
	var previous_skip := Story.auto_skip
	Story.auto_skip = false
	Story.reset_active_presentation(&"test_setup")
	var obstacle := Node.new()
	runner.get_tree().root.add_child(obstacle)
	var screen_rect := Rect2(DialogueLayer.RADIO_HOME + Vector2(90, 25), Vector2(36, 36))
	var world_rect := layer.get_viewport().get_canvas_transform().affine_inverse() * screen_rect
	PromptLayout.add_obstacle(obstacle, func() -> Rect2: return world_rect)
	Story._scenes["test_radio_clearance"] = {"mode": "radio", "freeze": true, "lines": [{"speaker": "mei", "text": "通訊閱讀期間保留完整的角色空間。"}]}
	check(Story.play(&"test_radio_clearance", false), "radio clearance retains the real presentation input")
	var clear := true
	for i in 16:
		await frames(1)
		clear = clear and not layer._radio_root.get_global_rect().intersects(screen_rect)
	check(clear, "radio remains clear of registered actors throughout its entrance")
	check(layer._safe_rect.encloses(layer._radio_root.get_global_rect()), "radio clearance stays inside the cinematic safe rectangle")
	check(layer._radio_active and not Story.progress_snapshot().has(&"test_radio_clearance"), "radio positioning does not finish or advance the unread presentation")
	Story.reset_active_presentation(&"test_teardown")
	Story._scenes.erase("test_radio_clearance")
	obstacle.queue_free()
	await frames(1)
	Story.auto_skip = previous_skip


func _test_radio_tall_clearance(reduced: bool) -> void:
	var layer: DialogueLayer = Story._layer
	var previous_skip := Story.auto_skip
	var previous_scale := Settings.get_ui_text_scale()
	var previous_motion := Settings.get_reduce_ui_motion()
	Story.auto_skip = false
	Story.reset_active_presentation(&"test_setup")
	Settings.set_ui_text_scale(1.2)
	Settings.set_reduce_ui_motion(reduced)
	var obstacle := Node.new()
	runner.get_tree().root.add_child(obstacle)
	var screen_rect := Rect2(Vector2(282, 117), Vector2(65, 138))
	var world_rect := layer.get_viewport().get_canvas_transform().affine_inverse() * screen_rect
	PromptLayout.add_obstacle(obstacle, func() -> Rect2: return world_rect)
	var hud_obstacle := Node.new()
	runner.get_tree().root.add_child(hud_obstacle)
	var hud_rect := layer.get_viewport().get_canvas_transform().affine_inverse() * Rect2(328, 0, 312, 110)
	PromptLayout.add_obstacle(hud_obstacle, func() -> Rect2: return hud_rect)
	Story._scenes["test_radio_tall_clearance"] = {"mode": "radio", "freeze": true, "lines": [{"speaker": "mei", "text": "Welcome to Skydome Backup Service. Your backup is complete."}]}
	check(Story.play(&"test_radio_tall_clearance", false), "tall radio uses the real reader at enlarged text size")
	check(not layer._radio_root.get_global_rect().intersects(screen_rect) and (layer._radio_root.modulate.a >= 0.99 if reduced else layer._radio_root.modulate.a < 1.0), "blocked entrance respects motion preference and starts in clear space")
	await frames(3)
	check(not layer._radio_root.get_global_rect().intersects(screen_rect), "tall radio finds the available edge slot between actor and screen boundary")
	check(layer._safe_rect.encloses(layer._radio_root.get_global_rect()), "enlarged radio remains fully inside the safe rectangle")
	check(layer._radio_active and not Story.progress_snapshot().has(&"test_radio_tall_clearance"), "edge placement preserves unread radio state")
	Story.reset_active_presentation(&"test_teardown")
	Story._scenes.erase("test_radio_tall_clearance")
	obstacle.queue_free()
	hud_obstacle.queue_free()
	await frames(1)
	Settings.set_ui_text_scale(previous_scale)
	Settings.set_reduce_ui_motion(previous_motion)
	Story.auto_skip = previous_skip


func _test_radio_crowded_gutter() -> void:
	var layer: DialogueLayer = Story._layer
	var old_skip := Story.auto_skip
	var old_scale := Settings.get_ui_text_scale()
	var old_motion := Settings.get_reduce_ui_motion()
	Story.auto_skip = false
	Story.reset_active_presentation(&"test_setup")
	Settings.set_ui_text_scale(1.2)
	Settings.set_reduce_ui_motion(true)
	var reservations: Array[Rect2] = [Rect2(156.75, 109.82, 71, 39), Rect2(142, 156, 72, 23),
		Rect2(518, 8, 110, 30), Rect2(12, 270, 132, 78), Rect2(16, 111, 61, 143),
		Rect2(183, 116, 65, 139), Rect2(261, 115, 63, 139), Rect2(625, 114, 63, 139)]
	var owners: Array[Node] = []
	for rect in reservations:
		var owner := Node.new()
		runner.get_tree().root.add_child(owner)
		owners.append(owner)
		var world_rect := layer.get_viewport().get_canvas_transform().affine_inverse() * rect
		PromptLayout.add_obstacle(owner, func() -> Rect2: return world_rect)
	Story._scenes["test_radio_crowded_gutter"] = {"mode": "radio", "freeze": true, "lines": [{"speaker": "voice", "text": "歡迎使用天穹備份服務，備份已經完成。"}]}
	check(Story.play(&"test_radio_crowded_gutter", false), "crowded radio uses the real enlarged reader")
	var clear := true
	for i in 16:
		await frames(1)
		for rect in reservations:
			clear = clear and not layer._radio_root.get_global_rect().intersects(rect)
	check(clear, "crowded radio preserves every actor and HUD reservation")
	check(layer._safe_rect.encloses(layer._radio_root.get_global_rect()), "compact gutter retains the original safe rectangle")
	check(layer._radio_active and not Story.progress_snapshot().has(&"test_radio_crowded_gutter"), "compact gutter preserves unread state and confirmation")
	Story.reset_active_presentation(&"test_teardown")
	Story._scenes.erase("test_radio_crowded_gutter")
	for owner in owners:
		owner.queue_free()
	await frames(1)
	Settings.set_ui_text_scale(old_scale)
	Settings.set_reduce_ui_motion(old_motion)
	Story.auto_skip = old_skip
