class_name ContextualPriorityChecks
extends RefCounted
## Presentation fixtures plus a real Level/Player obstacle; no producer authority.


static func run(suite: TestSuite) -> void:
	await _reading_priority(suite)
	await _actual_player_obstacle(suite)


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
