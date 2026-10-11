class_name ContextualPriorityChecks
extends RefCounted
## Presentation fixtures plus a real Level/Player obstacle; no producer authority.


static func run(suite: TestSuite) -> void:
	await _reading_priority(suite)
	await _actual_player_obstacle(suite)
	await _actual_hud_obstacles(suite)


static func _reading_priority(suite: TestSuite) -> void:
	var owners := DialogueLayer._radio_layers.size()
	var layer := DialogueLayer.new()
	suite.runner.add_child(layer)
	layer.set_process(false)
	var original_flags := GameState.world_flags.duplicate(true)
	var original_progress := Story.progress_snapshot()
	var radio_done: Array[StringName] = []
	layer.radio_finished.connect(func(id: StringName) -> void: radio_done.append(id))
	var line := {"name": "通訊員", "color": Palette.CYAN, "portrait": "", "speaker": "rin",
		"text": "前方道路已確認，請留意屋頂的出口。", "delay": 0.5}
	var lines: Array[Dictionary] = [line]
	layer.enqueue_radio(&"priority_fixture", lines)
	suite.check(not DialogueLayer.radio_visible() and not layer._radio_root.visible,
		"authored silence does not suppress lower-priority information")
	var card := ChapterCard.new()
	card.title = "第一章"
	card.subtitle = "開場標題必須保留完整閱讀時間。"
	card.hold = 0.1
	suite.runner.add_child(card)
	card.set_process(false)
	var card_done := [0]
	card.finished.connect(func() -> void: card_done[0] += 1)
	suite.check(card._root.visible and card._tween.is_running(), "nonblocking card may read during radio silence")
	var anchor := Node2D.new()
	suite.runner.add_child(anchor)
	var bubbles := MapBubbles.new()
	bubbles.anchor_resolver = func(_speaker: String) -> Node2D: return anchor
	suite.runner.add_child(bubbles)
	var bubble_done: Array[StringName] = []
	bubbles.scene_finished.connect(func(id: StringName) -> void: bubble_done.append(id))
	var bubble_lines: Array[Dictionary] = [line, line]
	bubbles.show_lines(&"priority_bubbles", bubble_lines)
	bubbles._process(0.0)
	bubbles.set_process(false)
	var age := float(bubbles._active[0]["age"])
	var queued := bubbles._queue.size()
	var holder := Node2D.new()
	suite.runner.add_child(holder)
	var prompt := WorldPrompt.new()
	var reachable := [true]
	prompt.text = "{interact} 閱讀入口說明。"
	prompt.reach_check = func() -> bool: return reachable[0]
	holder.add_child(prompt)
	prompt.set_process(false)
	prompt._process(1.0)
	suite.check(prompt.is_showing(), "reachable prompt displays before radio reveal")
	var hold := layer._radio_hold
	layer._process(0.6)
	suite.check(DialogueLayer.radio_visible() and layer._radio_text.visible_ratio == 0.0
		and layer._radio_hold == hold and radio_done.is_empty(), "radio reveal consumes only silence, not unread hold or completion")
	card._process(0.0)
	prompt._process(0.0)
	bubbles._process(20.0)
	var elapsed := card._tween.get_total_elapsed_time()
	suite.check(not card._root.visible and not card._tween.is_running(), "visible radio suspends actual card tween and its entire visual")
	suite.check(not bubbles.visible and float(bubbles._active[0]["age"]) == age
		and bubbles._queue.size() == queued and bubble_done.is_empty(), "radio hides bubbles without aging unread lines, dequeuing, or false completion")
	suite.check(not prompt.visible and not prompt.is_showing() and prompt._alpha == 0.0,
		"radio suppresses prompt and excludes it from layout without retaining a stale invitation")
	await suite.runner.get_tree().create_timer(1.5).timeout
	suite.check(is_instance_valid(card) and card_done[0] == 0 and card._tween.get_total_elapsed_time() == elapsed,
		"card survives hidden longer than its complete authored lifetime; no invisible consumption")
	# A blocking card owns the screen directly; it must not wait on radio.
	var block := ChapterCard.new()
	block.title = "章節結束"
	block.block = true
	suite.runner.add_child(block)
	var ratio := layer._radio_text.visible_ratio
	var wait := layer._radio_wait
	layer._process(10.0)
	suite.check(block._root.visible and not block._presentation_suspended and block._tween.is_running(),
		"blocking chapter card plays immediately instead of waiting on a paused radio")
	suite.check(not DialogueLayer.radio_visible() and layer._radio_hold == hold and layer._radio_wait == wait
		and layer._radio_text.visible_ratio == ratio and radio_done.is_empty(), "real modal pause hides radio but freezes every unread clock")
	# Always observer, not a manually invoked modal method: test a second prompt.
	var modal_prompt := WorldPrompt.new()
	modal_prompt.text = "{interact} 拾取物品。"
	modal_prompt.reach_check = func() -> bool: return true
	holder.add_child(modal_prompt)
	await suite.frames(3)
	suite.check(not modal_prompt.visible and not modal_prompt.is_showing(), "all prompt nodes observe modal pause despite their world parent being pausable")
	block._done()
	layer._process(0.0)
	suite.check(DialogueLayer.radio_visible() and layer._radio_hold == hold, "unpause restores the same radio without resetting its hold")
	layer._radio_text.visible_ratio = 1.0
	layer._process(hold + 0.1)
	suite.check(radio_done == [&"priority_fixture"] and DialogueLayer.radio_visible(), "normal radio completes once; fading panel still owns the reading space")
	card._process(0.0)
	suite.check(not card._root.visible, "card never flashes through radio's fade-out tail")
	await suite.runner.get_tree().create_timer(0.3).timeout
	suite.check(not DialogueLayer.radio_visible(), "finished panel releases priority after actual fade callback")
	card._process(0.0)
	reachable[0] = false
	prompt._process(1.0)
	suite.check(card._root.visible and card._tween.is_running() and not prompt.is_showing(), "card resumes while an out-of-range invitation stays hidden")
	reachable[0] = true
	prompt._process(1.0)
	suite.check(prompt.is_showing(), "actual reach returning restores the same prompt")
	bubbles._process(0.0)
	suite.check(bubbles.visible and float(bubbles._active[0]["age"]) == age, "same bubble returns with its original remaining reading time")
	bubbles._process(MapBubbles.HOLD_MAX + 0.5)
	bubbles._process(MapBubbles.HOLD_MAX + 0.5)
	suite.check(bubble_done == [&"priority_bubbles"], "bubble completion occurs once after actual resumed display")
	await suite.runner.get_tree().create_timer(1.5).timeout
	suite.check(card_done[0] == 1, "restored chapter card completes once after its remaining tween")
	var cancel_lines: Array[Dictionary] = [line.duplicate(true)]
	cancel_lines[0]["delay"] = 0.0
	layer.enqueue_radio(&"priority_cancel", cancel_lines)
	layer.cancel_radio()
	suite.check(not DialogueLayer.radio_visible() and not radio_done.has(&"priority_cancel"), "explicit cancel releases visibility without fabricating radio completion")
	layer.enqueue_radio(&"priority_owner_removed", cancel_lines)
	suite.check(DialogueLayer.radio_visible(), "actual new layer owns visible radio before removal")
	layer.queue_free()
	suite.check(not DialogueLayer.radio_visible(), "queued-for-deletion layer cannot retain presentation ownership")
	bubbles.queue_free()
	anchor.queue_free()
	holder.queue_free()
	await suite.frames(2)
	suite.check(DialogueLayer._radio_layers.size() == owners, "tree exit removes weak owner registration")
	suite.check(GameState.world_flags == original_flags and Story.progress_snapshot() == original_progress,
		"presentation arbitration never writes story flags or completion progress")


static func _actual_player_obstacle(suite: TestSuite) -> void:
	var level: Level = await suite.start_level(PropsSuite.level_data())
	var player: Player = level.player
	player.set_physics_process(false)
	var player_id := player.get_instance_id()
	var vitals := level.hud.vitals_tag
	var vitals_id := vitals.get_instance_id()
	suite.check(PromptLayout._obstacles.has(player), "production Player registers itself, not a capture-created obstacle")
	suite.check(PromptLayout._obstacles.has(level.hud.vitals_tag), "actual head-side vitals register separately from crouching character art")
	vitals.presence.poke()
	vitals._process(0.1)
	suite.check(vitals.prompt_obstacle_rect().has_area(), "actual visible vitals expose their current screen-to-world footprint")
	vitals.hide()
	suite.check(not vitals.prompt_obstacle_rect().has_area(), "invisible vitals reserve no prompt space")
	vitals.show()
	var body := player.prompt_obstacle_rect()
	suite.check(body.size.x > Player.BODY_SIZE.x and body.size.x < level.get_viewport_rect().size.x * 0.5,
		"true character/equipment presentation protects more than the narrow collider without blocking the whole screen")
	var torso := Rect2(player.global_position + Vector2(-Player.BODY_SIZE.x * 0.5, -Player.BODY_SIZE.y), Player.BODY_SIZE)
	suite.check(body.encloses(torso), "measured player obstacle always retains actual physical torso fallback")
	var head := player._visual.rig.bone(&"head")
	var standing_top := body.position.y
	var head_position := head.position
	# Known exact head motion isolates the O(1) stance follow; no repeated bounds scan.
	head.position.y += 6.0
	player.is_crouching = true
	var crouch := player.prompt_obstacle_rect()
	suite.check(crouch.position.y > standing_top and crouch.encloses(Rect2(player.global_position
		+ Vector2(-Player.BODY_SIZE.x * 0.5, -Player.CROUCH_HEIGHT), Vector2(Player.BODY_SIZE.x, Player.CROUCH_HEIGHT))),
		"actual head motion changes standing/crouch protection while retaining crouched torso")
	head.position = head_position
	player.is_crouching = false
	var holder := Node2D.new()
	holder.position = player.global_position
	level.add_child(holder)
	var prompt := WorldPrompt.new()
	prompt.text = "{move_left}/{move_right} 沿平台前進，留意前方矮牆。"
	prompt.offset = Vector2(0, -20)
	prompt.reach_check = func() -> bool: return true
	holder.add_child(prompt)
	var prompt_id := prompt.get_instance_id()
	suite.check(prompt.base_rect().intersects(player.prompt_obstacle_rect()), "long tutorial prompt starts over actual player torso, making avoidance test nonvacuous")
	await suite.frames(45)
	var shown := Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size)
	suite.check(not shown.intersects(player.prompt_obstacle_rect()), "actual solver shifts long tutorial text away from actual registered player presentation")
	suite.check(not shown.intersects(vitals.prompt_obstacle_rect()), "actual solver also clears head-side vitals rather than moving text into its health pips")
	var ascent := prompt._font.get_ascent(WorldPrompt.FONT_SIZE)
	var descent := prompt._font.get_descent(WorldPrompt.FONT_SIZE)
	suite.check(is_equal_approx(prompt._text_baseline.y - ascent, prompt._box.position.y + WorldPrompt.PADDING.y)
		and prompt._text_baseline.y + descent <= prompt._box.end.y - WorldPrompt.PADDING.y + 0.001,
		"cached baseline and ascent/descent fit the exact rectangle used by collision layout")
	await suite.end_level(level)
	var retained := false
	for owner: Node in PromptLayout._obstacles:
		retained = retained or (is_instance_valid(owner) and owner.get_instance_id() in [player_id, vitals_id])
	for value: WorldPrompt in PromptLayout._prompts:
		retained = retained or (is_instance_valid(value) and value.get_instance_id() == prompt_id)
	for value: WorldPrompt in PromptLayout._active:
		retained = retained or (is_instance_valid(value) and value.get_instance_id() == prompt_id)
	suite.check(not retained,
		"real Level removal cleans Player obstacle, prompt registration and reusable active scratch")


static func _actual_hud_obstacles(suite: TestSuite) -> void:
	var level: Level = await suite.start_level(PropsSuite.level_data())
	var tray: AmmoTray = level.hud.ammo_tray
	await suite.frames(4)
	var tray_id := tray.get_instance_id()
	suite.check(PromptLayout._obstacles.has(tray), "real AmmoTray registers its actual owner and drawing getter")
	suite.check(tray.prompt_obstacle_rect().has_area(), "visible loaded AmmoTray protects its actual world-space drawing")
	var alpha := tray.presence.alpha
	tray.presence.alpha = 0.0
	suite.check(not tray.prompt_obstacle_rect().has_area(), "transparent AmmoTray exposes no obstruction")
	tray.presence.alpha = alpha
	var saved := {"pos": tray._pos, "has_pos": tray._has_pos, "side": tray._side, "draw_side": tray._draw_side, "ammo": tray.ammo,
		"reloading": tray._reloading, "hint_width": tray._obstacle_hint_width}
	tray._has_pos = true
	tray._reloading = false
	tray.ammo = 0
	tray._pos = Vector2(320.0, 180.0)
	var canvas := tray.get_viewport().get_canvas_transform()
	for side: float in [-1.0, 1.0]:
		tray._side = side
		# NE-264：畫面上的方向是平滑過渡的連續值；這裡直接檢查兩側都到位後的幾何。
		tray._draw_side = side
		var hint_rect := canvas * tray.prompt_obstacle_rect()
		var anchor_x := tray._pos.x - 16.0 if side < 0.0 else tray._pos.x
		suite.check(hint_rect.has_area() and hint_rect.end.x >= anchor_x + tray._obstacle_hint_width,
			"left-aligned empty-ammo hint full text width is included on both HUD sides")
	tray._pos = saved["pos"]
	tray._has_pos = saved["has_pos"]
	tray._side = saved["side"]
	tray._draw_side = saved["draw_side"]
	tray.ammo = saved["ammo"]
	tray._reloading = saved["reloading"]
	tray._obstacle_hint_width = saved["hint_width"]
	# A shell already in the actual fixed pool remains drawable after an energy switch.
	var saved_energy := tray.is_energy
	var saved_age := tray._eject_age[0]
	var saved_position := tray._eject_pos[0]
	var saved_spin := tray._eject_spin[0]
	var saved_icon := tray._icon_id
	tray._icon_id = &"pistol"
	tray._eject_age[0] = 0.15
	tray._eject_pos[0] = Vector2(300.0, 170.0)
	tray._eject_spin[0] = 7.0
	tray.is_energy = true
	var shell_center := tray._eject_pos[0] + AmmoTray.ICON * 0.5
	# Check the actual rotated draw rectangle, independently of the getter's
	# circumscribed-radius calculation, so a skipped shell cannot pass this check.
	var shell_transform := Transform2D(tray._eject_spin[0] * tray._eject_age[0], shell_center)
	var shell_local := shell_transform * Rect2(-AmmoTray.ICON * 0.5, AmmoTray.ICON)
	var shell_world := canvas.affine_inverse() * (tray.get_global_transform() * shell_local)
	suite.check(tray.prompt_obstacle_rect().encloses(shell_world), "actual retained shell draw condition stays protected after energy weapon switch")
	tray._icon_id = saved_icon
	tray._eject_age[0] = saved_age
	tray._eject_pos[0] = saved_position
	tray._eject_spin[0] = saved_spin
	tray.is_energy = saved_energy
	var card := ChapterCard.new()
	card.title = "第一章"
	card.subtitle = "請帶著資料盤離開倉庫。"
	card.hold = 10.0
	suite.runner.add_child(card)
	await suite.frames(3)
	var card_id := card.get_instance_id()
	var card_rect := card.prompt_obstacle_rect()
	var card_screen := card.get_viewport().get_canvas_transform() * card_rect
	suite.check(PromptLayout._obstacles.has(card) and card_rect.has_area(), "visible ChapterCard registers the real owner and text bounds")
	suite.check(card_screen.size.x < 440.0, "ChapterCard protects measured labels rather than full VBox width")
	var old_extent := card._title_extent
	var old_font_size := card._title_label.get_theme_font_size(&"font_size")
	card._title_label.add_theme_font_size_override(&"font_size", old_font_size + 6)
	await suite.frames(2)
	suite.check(card._title_extent.x > old_extent.x, "actual Label theme reflow refreshes cached title extent")
	card._root.visible = false
	suite.check(not card.prompt_obstacle_rect().has_area(), "hidden ChapterCard reserves no prompt space")
	card._root.visible = true
	card._root.modulate.a = 0.0
	suite.check(not card.prompt_obstacle_rect().has_area(), "faded ChapterCard reserves no prompt space")
	card.queue_free()
	await suite.frames(2)
	var retained := false
	for owner: Node in PromptLayout._obstacles:
		retained = retained or (is_instance_valid(owner) and owner.get_instance_id() == card_id)
	suite.check(not retained, "ChapterCard tree exit automatically removes its obstacle owner")
	await suite.end_level(level)
	retained = false
	for owner: Node in PromptLayout._obstacles:
		retained = retained or (is_instance_valid(owner) and owner.get_instance_id() == tray_id)
	suite.check(not retained, "Level removal automatically cleans real AmmoTray obstacle owner")
