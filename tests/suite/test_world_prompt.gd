class_name WorldPromptSuite
extends TestSuite
## 世界提示自動錯開（NE-120）：同時顯示的提示不重疊、不蓋住人物，被推開的提示滑過去，沒人靠近時不運算。


func run() -> void:
	_test_solver()
	_test_bounded_solver()
	_test_leader_geometry()
	await _test_leader_world_transform()
	await _test_toast_reading_space()
	await _test_motion_safety()
	await _test_nodes()
	await _test_npc_obstacle()
	await _test_modal_suppression()
	await _test_keycaps()
	await _test_screen_edge()
	await _test_dead_player_suppression()
	await _test_long_text()
	await _test_framing_bounds()


func _test_framing_bounds() -> void:
	var previous_motion := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(true)
	var stage := Node2D.new()
	runner.add_child(stage)
	var viewport := runner.get_viewport()
	var full := viewport.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	var token := Story.framing.acquire(stage)
	var prompt := _spawn_prompt(stage, full.get_center().x, "靠近電話亭後，按確認鍵保存目前的進度。")
	(prompt.get_parent() as Node2D).position.y = full.position.y + 6.0
	await frames(2)
	prompt._process(1.0)
	var safe := viewport.get_canvas_transform().affine_inverse() * Story.framing.safe_rect()
	var shown := Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size)
	check(prompt.is_showing() and safe.encloses(shown), "a top-edge world invitation stays below actual cinematic framing")
	Story.framing.release(token)
	Settings.set_reduce_ui_motion(previous_motion)
	stage.queue_free()
	await frames(2)


func _test_bounded_solver() -> void:
	var bounds := Rect2(0, 0, 200, 100)
	var rects: Array[Rect2] = [Rect2(4, 4, 120, 20), Rect2(20, 4, 120, 20)]
	var obstacles: Array[Rect2] = [Rect2(124, 0, 76, 35)]
	var nudges := PromptLayout.solve(rects, obstacles, PromptLayout.GAP, bounds).duplicate()
	var valid := _overlap_free(rects, nudges)
	for i in rects.size():
		var shown := Rect2(rects[i].position + nudges[i], rects[i].size)
		valid = valid and bounds.encloses(shown) and not shown.intersects(obstacles[0].grow(PromptLayout.OBSTACLE_MARGIN))
	check(valid, "crowded top-edge prompts find free positions inside both screen edges")


func _test_long_text() -> void:
	var scale := Settings.get_ui_text_scale()
	var stage := Node2D.new()
	runner.add_child(stage)
	var camera := Camera2D.new()
	camera.zoom = Vector2(4, 4)
	stage.add_child(camera)
	camera.make_current()
	await frames(2)
	var viewport := runner.get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	for source: String in ["在電話亭備份，死了會從最近的電話亭醒來，沿原路繼續前進。", "Back up at the telephone booth, then continue through the warehouse without losing your progress.", "電話ボックスでバックアップしてから、倉庫の奥へ進んでください。"]:
		var prompt := _spawn_prompt(stage, view.get_center().x, source)
		prompt._process(1.0)
		check(prompt._display_text == source and prompt.base_rect().size.x <= view.size.x * 0.6 and prompt.base_rect().size.y > 15.0, "long world text wraps without shortening its complete source: " + source)
		prompt.get_parent().queue_free()
		await frames(2)
	var taught := _spawn_prompt(stage, view.get_center().x, "先在電話亭按 {interact} 備份，補滿彈藥後按 {reload} 換彈再出發。")
	taught.keycaps = true
	Settings.set_ui_text_scale(1.2)
	taught._process(1.0)
	var caps := taught._segments.filter(func(segment: Dictionary) -> bool: return segment["cap"])
	var fits := caps.size() == 2 and taught.base_rect().size.x <= view.size.x * 0.6
	for segment in taught._segments:
		fits = fits and segment["x"] >= 0.0 and segment["x"] + segment["w"] <= taught._box.size.x - WorldPrompt.PADDING.x * 2.0 + 0.5
	check(fits, "large teaching text keeps both whole keycaps inside its wrapped box")
	Settings.set_ui_text_scale(scale)
	stage.queue_free()
	await frames(2)


func _test_modal_suppression() -> void:
	var stage := Node2D.new()
	runner.add_child(stage)
	var prompt := _spawn_prompt(stage, 0.0, "{interact} 交談")
	prompt._process(1.0)
	check(prompt.is_showing(), "reachable interaction is visible before a modal starts")
	var lock := GameplayLock.acquire(stage)
	prompt._process(1.0)
	check(not prompt.is_showing() and prompt._alpha == 0.0, "a modal hides the invitation instead of advertising a blocked interaction")
	GameplayLock.release(lock)
	prompt._process(1.0)
	check(prompt.is_showing(), "releasing modal control restores the actual reachable invitation")
	stage.queue_free()
	await frames(2)


## 倒下之後死亡畫面接手：教學與互動提示不再對倒地的主角顯示（NE-228）。
func _test_dead_player_suppression() -> void:
	var stage := Node2D.new()
	runner.add_child(stage)
	var player := FakePlayer.new()
	player.add_to_group(&"player")
	stage.add_child(player)
	var prompt := _spawn_prompt(stage, 0.0, "移動 {move_left}/{move_right}")
	prompt._process(1.0)
	check(prompt.is_showing(), "a living player still sees the nearby tutorial prompt")
	player.dead = true
	prompt._process(1.0)
	prompt._process(1.0)
	check(not prompt.is_showing(), "a dead player is not invited to move, jump or interact")
	player.dead = false
	prompt._process(1.0)
	check(prompt.is_showing(), "the prompt returns after the player is back on their feet")
	stage.queue_free()
	await frames(2)


class FakePlayer extends Node2D:
	var dead := false

	func is_dead() -> bool:
		return dead


func _rect(x: float, y := 0.0, w := 60.0, h := 15.0) -> Rect2:
	return Rect2(x, y, w, h)


func _overlap_free(rects: Array[Rect2], nudges: PackedVector2Array) -> bool:
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if Rect2(rects[i].position + nudges[i], rects[i].size).intersects(Rect2(rects[j].position + nudges[j], rects[j].size)):
				return false
	return true


func _test_solver() -> void:
	var one: Array[Rect2] = [_rect(0.0)]
	check(PromptLayout.solve(one, []).duplicate()[0] == Vector2.ZERO, "單獨一個提示不動")
	var apart: Array[Rect2] = [_rect(0.0), _rect(100.0)]
	var nudges := PromptLayout.solve(apart, []).duplicate()
	check(nudges[0] == Vector2.ZERO and nudges[1] == Vector2.ZERO, "不重疊的提示都不動")
	var stacked: Array[Rect2] = [_rect(0.0), _rect(10.0), _rect(20.0), _rect(30.0)]
	nudges = PromptLayout.solve(stacked, []).duplicate()
	check(_overlap_free(stacked, nudges), "四個重疊的提示排開後互不重疊")
	check(nudges[0] == Vector2.ZERO, "最左邊的提示留在原位")
	check(nudges[1].y < 0.0 and nudges[2].y < nudges[1].y, "重疊的提示先上下錯開（往上一格一格疊）")
	# 人物（障礙）在原位上方時改往旁邊讓開，不蓋住人物。
	var body := Rect2(20.0, -40.0, 24.0, 56.0)
	var blocked: Array[Rect2] = [_rect(10.0, -10.0)]
	var obstacles: Array[Rect2] = [body]
	nudges = PromptLayout.solve(blocked, obstacles).duplicate()
	check(not Rect2(blocked[0].position + nudges[0], blocked[0].size).intersects(body), "提示不蓋住人物")
	# 已經排好的結果，再算一次一樣（不會因重算而抖動）。
	var again := PromptLayout.solve(stacked, []).duplicate()
	var first := PromptLayout.solve(stacked, []).duplicate()
	check(again == first, "同樣的輸入每次排出同樣的結果")


## ST-16／BG-22：教學提示把 {動作} 畫成按鍵帽，鍵鼠與手把各自顯示目前的綁定；一般提示維持純文字。
func _test_keycaps() -> void:
	var stage := Node2D.new()
	runner.add_child(stage)
	var was_gamepad := InputBindings.using_gamepad
	var device := InputBindings.active_device
	InputBindings._set_device(false)
	var plain := _spawn_prompt(stage, 0.0, "{interact} 交談")
	var taught := _spawn_prompt(stage, 200.0, "換彈按 {reload}；落下要按住 {move_down} 再按 {jump}。")
	taught.keycaps = true
	await frames(1)
	check(plain._segments.is_empty(), "ordinary prompts stay plain text")
	var caps := taught._segments.filter(func(segment: Dictionary) -> bool: return segment["cap"])
	check(caps.size() == 3 and caps[0]["text"] == InputBindings.primary_label(&"reload"), "each action in a teaching prompt becomes its own keycap (%s)" % [caps])
	var texts := taught._segments.filter(func(segment: Dictionary) -> bool: return not segment["cap"]).map(func(segment: Dictionary) -> String: return segment["text"])
	check(texts == ["換彈按", "；落下要按住", "再按", "。"], "the words around the keycaps keep their order: %s" % [texts])
	var widths_fit := true
	for segment in taught._segments:
		widths_fit = widths_fit and segment["x"] + segment["w"] <= taught._box.size.x - WorldPrompt.PADDING.x * 2.0 + 0.5
	check(widths_fit, "the keycaps and words fit inside the prompt box")
	var keyboard_label: String = caps[0]["text"] if not caps.is_empty() else ""
	InputBindings._set_device(true, 0)
	await frames(1)
	var pad_caps := taught._segments.filter(func(segment: Dictionary) -> bool: return segment["cap"])
	check(not pad_caps.is_empty() and pad_caps[0]["text"] == InputBindings.joy_label(&"reload") and pad_caps[0]["text"] != keyboard_label,
			"picking up a gamepad switches the keycaps to gamepad buttons")
	InputBindings._set_device(was_gamepad, device)
	stage.queue_free()
	await frames(2)


## BG-22：鏡頭停在地圖邊上時，靠邊看板的文字往畫面內推，不被畫面切掉；指回看板的細線照常畫。
func _test_screen_edge() -> void:
	var stage := Node2D.new()
	runner.add_child(stage)
	var viewport := runner.get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	var edge := _spawn_prompt(stage, view.position.x + 2.0, "按 {interact} 在電話亭備份，死了會從最近的電話亭醒來。")
	# 推移是逐影格緩動：機器忙時影格時間長短不一，等到滑進畫面（最多約三秒）再判斷，而不是固定等幾格。
	var shown := Rect2()
	for i in 180:
		await frames(1)
		shown = Rect2(edge.base_rect().position + edge._nudge, edge.base_rect().size)
		if shown.position.x >= view.position.x + PromptLayout.SCREEN_MARGIN - 0.5:
			break
	check(edge.base_rect().position.x < view.position.x and shown.position.x >= view.position.x + PromptLayout.SCREEN_MARGIN - 0.5,
			"a prompt at the screen edge slides fully on screen (box %s, view %s)" % [shown, view])
	stage.queue_free()
	await frames(2)


func _spawn_prompt(parent: Node2D, x: float, text: String) -> WorldPrompt:
	var prompt := WorldPrompt.new()
	prompt.text = text
	prompt.offset = Vector2(0, -30)
	prompt.reach_check = func() -> bool: return true
	var holder := Node2D.new()
	holder.position = Vector2(x, 0)
	parent.add_child(holder)
	holder.add_child(prompt)
	return prompt


func _test_nodes() -> void:
	var stage := Node2D.new()
	runner.add_child(stage)
	var prompts: Array[WorldPrompt] = [
		_spawn_prompt(stage, 0.0, "{interact} 撥號備份"), _spawn_prompt(stage, 14.0, "{interact} 補給"),
		_spawn_prompt(stage, 28.0, "{interact} 拾取武器"),
	]
	await frames(30)
	var rects: Array[Rect2] = []
	for prompt in prompts:
		rects.append(Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size))
	var free := true
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			free = free and not rects[i].intersects(rects[j])
	check(free, "同一處三個提示實際顯示時自動排開、不重疊")
	var leader_shown := false
	for prompt in prompts:
		leader_shown = leader_shown or prompt._nudge.length() > 1.0
	check(leader_shown, "被推開的提示有移動（並畫出指回自己物件的細線）")
	# 條件不成立就不顯示，也不參與排版。
	for prompt in prompts:
		prompt.reach_check = func() -> bool: return false
	await frames(40)
	var hidden := true
	for prompt in prompts:
		hidden = hidden and prompt._alpha <= 0.0 and not prompt.is_showing()
	check(hidden, "離開互動範圍後提示淡出，不再參與排版")
	PromptLayout.update()
	check(PromptLayout._active.is_empty(), "沒有提示在顯示時不做排版運算")
	stage.queue_free()
	await frames(2)
	check(PromptLayout._prompts.is_empty(), "提示離開場景時取消登記")


## 人物登記為障礙：旁邊物件的提示不蓋住人物，自己的提示用「按互動鍵有效」的範圍顯示。
func _test_npc_obstacle() -> void:
	var stage := Node2D.new()
	runner.add_child(stage)
	var holder := Node2D.new()
	stage.add_child(holder)
	var npc_rect := Rect2(-12.0, -56.0, 24.0, 56.0)
	PromptLayout.add_obstacle(holder, func() -> Rect2: return Rect2(holder.global_position + npc_rect.position, npc_rect.size))
	var prompt := _spawn_prompt(stage, 6.0, "{interact} 撥號備份")
	prompt.offset = Vector2(0, -20)
	prompt.position = prompt.offset
	await frames(30)
	var shown := Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size)
	check(not shown.intersects(npc_rect), "提示不蓋住旁邊的人物")
	stage.queue_free()
	await frames(2)
	check(PromptLayout._obstacles.is_empty(), "人物離開場景時取消障礙登記")


func _test_leader_geometry() -> void:
	var spans: Array[Vector2] = []
	var obstacles: Array[Rect2] = [Rect2(-2, 4, 4, 2)]
	PromptLayout.clip_leader_segments(Vector2.ZERO, Vector2(0, 10), obstacles, spans, 0.5)
	check(spans == [Vector2.ZERO, Vector2(0, 3.5), Vector2(0, 6.5), Vector2(0, 10)], "leader keeps both original-end spans and removes the status plate plus actual half-stroke clearance")
	obstacles = [Rect2(6, -1, 2, 2), Rect2(2, -1, 3, 2), Rect2(4, -1, 3, 2)]
	PromptLayout.clip_leader_segments(Vector2.ZERO, Vector2(10, 0), obstacles, spans)
	check(spans == [Vector2.ZERO, Vector2(2, 0), Vector2(8, 0), Vector2(10, 0)], "unsorted overlapping body/status obstacles merge as a union without hiding unblocked endpoints")
	obstacles = [Rect2(-1, 2, 2, 3)]
	PromptLayout.clip_leader_segments(Vector2(0, 10), Vector2.ZERO, obstacles, spans)
	check(spans == [Vector2(0, 10), Vector2(0, 5), Vector2(0, 2), Vector2.ZERO], "reverse and parallel-axis leader retains direction and the real target")
	obstacles = [Rect2(0, 0, 0, 5), Rect2(NAN, 0, 2, 2), Rect2(20, 20, 2, 2)]
	var count := PromptLayout.clip_leader_segments(Vector2.ZERO, Vector2(0, 10), obstacles, spans)
	var misses := count == 2 and spans.slice(0, count) == [Vector2.ZERO, Vector2(0, 10)]
	obstacles = [Rect2(-1, -1, 2, 12)]
	count = PromptLayout.clip_leader_segments(Vector2.ZERO, Vector2(0, 10), obstacles, spans)
	var covered := count == 0
	count = PromptLayout.clip_leader_segments(Vector2.ZERO, Vector2.ZERO, [], spans)
	check(misses and covered and count == 0, "invalid/empty/missing obstacles do not cut valid line; full coverage and zero-length line produce no false span")


func _test_leader_world_transform() -> void:
	var stage := Node2D.new()
	stage.position = Vector2(20, -7)
	stage.rotation = 0.3
	stage.scale = Vector2(2, 1.5)
	runner.add_child(stage)
	var prompt := _spawn_prompt(stage, 0, "{interact} 補給")
	var owner := Node.new()
	stage.add_child(owner)
	var start := prompt._leader.to_global(Vector2(0, -30))
	var target := prompt._leader.to_global(Vector2.ZERO)
	var middle := start.lerp(target, 0.5)
	PromptLayout.add_obstacle(owner, func() -> Rect2: return Rect2(middle - Vector2(3, 3), Vector2(6, 6)))
	var spans: Array[Vector2] = []
	var count := PromptLayout.leader_segments(start, target, spans, 1.0)
	var clipped := count == 4 and spans[0].is_equal_approx(start) and spans[3].is_equal_approx(target)
	var roundtrip := clipped and prompt._leader.to_local(spans[0]).is_equal_approx(Vector2(0, -30)) \
			and prompt._leader.to_local(spans[3]).is_equal_approx(Vector2.ZERO)
	stage.queue_free()
	await frames(2)
	count = PromptLayout.leader_segments(start, target, spans)
	check(roundtrip and count == 2 and spans.slice(0, count) == [start, target] and PromptLayout._obstacles.is_empty(), "real transformed leader cuts registered world obstacle; owner removal restores original line and target without stale cuts")


func _test_motion_safety() -> void:
	var previous_motion := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(false)
	var stage := Node2D.new()
	runner.add_child(stage)
	var camera := Camera2D.new()
	camera.position = Vector2(400, 400)
	camera.zoom = Vector2(2, 2)
	stage.add_child(camera)
	camera.make_current()
	await frames(2)
	var view := runner.get_viewport().get_canvas_transform().affine_inverse() * runner.get_viewport().get_visible_rect()
	var center := view.get_center()
	var actor := Rect2(center - Vector2(12, 56), Vector2(24, 56))
	var obstacle := Node.new()
	stage.add_child(obstacle)
	PromptLayout.add_obstacle(obstacle, func() -> Rect2: return actor)
	var holder := Node2D.new()
	holder.position = center
	stage.add_child(holder)
	var prompt := WorldPrompt.new()
	prompt.text = "靠近查看"
	prompt.offset = Vector2(0, -20)
	prompt.reach_check = func() -> bool: return true
	holder.add_child(prompt)
	var initial_clear := true
	for i in 8:
		prompt._process(1.0 / 60.0)
		initial_clear = initial_clear and not Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size).intersects(actor)
	check(initial_clear, "a newly appearing invitation avoids the actor on every fade-in frame")
	# Same-frame layout delivery: both endpoints are valid, but the straight path crosses the actor.
	PromptLayout.update()
	prompt._nudge = Vector2(-60, 0)
	prompt.set_nudge_target(Vector2(60, 0))
	var crossing_clear := true
	for i in 32:
		prompt._process(1.0 / 60.0)
		crossing_clear = crossing_clear and not Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size).intersects(actor)
	check(crossing_clear and prompt._nudge == Vector2(60, 0), "safe endpoints never animate the text rectangle through the actor between them")
	prompt.set_nudge_target(Vector2(80, 0))
	prompt._process(1.0 / 60.0)
	check(prompt._nudge.x > 60.0 and prompt._nudge.x < 80.0, "an unobstructed already-visible invitation still slides at its normal speed")
	Settings.set_reduce_ui_motion(true)
	PromptLayout.update()
	prompt.set_nudge_target(Vector2(100, 0))
	prompt._process(1.0 / 60.0)
	check(prompt._nudge == Vector2(100, 0), "reduced interface motion places world text directly at its safe target")
	Settings.set_reduce_ui_motion(previous_motion)
	stage.queue_free()
	await frames(2)


func _test_toast_reading_space() -> void:
	var stage := Node2D.new()
	runner.add_child(stage)
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	var ui := UiKit.full_rect_root(layer)
	var banner := UiBanner.new()
	banner.position = Vector2(220, 112)
	banner.center_x = 320
	ui.add_child(banner)
	banner.show_text("有人看守保險箱，小心。", UiBanner.Kind.INFO, 0.4)
	await frames(2)
	var inverse := runner.get_viewport().get_canvas_transform().affine_inverse()
	var toast := inverse * (banner.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, banner.size))
	var holder := Node2D.new()
	stage.add_child(holder)
	var prompt := WorldPrompt.new()
	prompt.text = "保險箱裡的一片資料盤，拿到後從上層通道離開。"
	prompt.reach_check = func() -> bool: return false
	holder.add_child(prompt)
	holder.global_position += toast.get_center() - prompt.base_rect().get_center()
	prompt.reach_check = func() -> bool: return true
	PromptLayout.invalidate()
	var readable := true
	for i in 12:
		await frames(1)
		toast = inverse * (banner.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, banner.size))
		if banner.is_showing() and prompt._alpha > 0.01 and prompt._layout_allowed:
			readable = readable and not Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size).intersects(toast)
	check(readable, "a sliding HUD notification and actual world text never share visible pixels")
	for i in 90:
		if not banner.is_showing() and prompt._alpha > 0.5:
			break
		await frames(1)
	check(not banner.is_showing() and prompt._alpha > 0.5 and prompt.enabled, "world reading remains eligible and returns after a temporary HUD notification")
	stage.queue_free()
	await frames(2)
