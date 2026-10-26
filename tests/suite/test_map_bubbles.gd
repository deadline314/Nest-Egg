class_name MapBubblesSuite
extends TestSuite
## 地圖對話氣泡（ST-12）：資料規則（字數、句數、bark）、顯示時間、同屏上限、不鎖操作不暫停、
## 講者不在地圖上改用通訊、場景結束訊號、關卡離開時不卡住等待的流程、auto_skip。

const BOOTH_AREA := "res://data/levels/ch1_booth_alley.tres"


func run() -> void:
	var previous_auto := Story.auto_skip
	_test_rules()
	await _test_in_level()
	await _test_released_host_does_not_hang()
	await preload("res://tests/helpers/bubble_source_checks.gd").run(self)
	await preload("res://tests/helpers/bubble_admission_checks.gd").run(self)
	await _test_wrapped_bubble_bounds()
	Story.auto_skip = previous_auto
	Story.reset_progress()
	GameState.start_new_run(GameState.difficulties[1])


func _test_wrapped_bubble_bounds() -> void:
	var original_obstacles := PromptLayout._obstacles.size()
	var stage := Node2D.new()
	runner.add_child(stage)
	var camera := Camera2D.new()
	camera.zoom = Vector2(2, 2)
	stage.add_child(camera)
	camera.make_current()
	await frames(2)
	var view := runner.get_viewport().get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, runner.get_viewport().get_visible_rect().size)
	var speaker := Node2D.new()
	speaker.position = view.get_center() + Vector2(0, 45)
	stage.add_child(speaker)
	var host := MapBubbles.new()
	host.anchor_resolver = func(_id: String) -> Node2D: return speaker
	stage.add_child(host)
	var text := "今天的飯煮好了喔。這頓我煮給你，不用交四十。"
	host.show_lines(&"test_complete_bubble", [{"speaker": "test", "text": text}])
	host._process(0.0)
	var prompt := WorldPrompt.new()
	prompt.text = "按下確認鍵繼續前往倉庫。"
	prompt.reach_check = func() -> bool: return true
	prompt.position = speaker.position
	stage.add_child(prompt)
	prompt._process(1.0)
	await frames(1)
	PromptLayout.update()
	prompt._process(1.0)
	var bubble: Dictionary = host._active[0]
	var rect: Rect2 = bubble.get("rect", Rect2())
	check(rect.has_area() and view.encloses(rect) and rect.size.x <= view.size.x * 0.6, "complete ambient sentence uses a bounded on-screen bubble")
	var paragraph: TextParagraph = bubble.get("paragraph")
	check(paragraph != null and paragraph.get_range().y == text.length() and paragraph.get_line_count() > 1, "wrapped ambient sentence preserves every character")
	check(rect.has_area() and not rect.intersects(Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size)), "nearby world invitation avoids the actual ambient bubble: %s" % [{"bubble": rect, "prompt": prompt.base_rect(), "nudge": prompt._nudge, "target": prompt._nudge_target, "obstacles": PromptLayout._obstacle_rects}])
	check(rect.has_area() and PromptLayout.covers(rect), "ambient reading participates in the existing HUD goal yielding rule")
	var other := Node2D.new()
	other.position = speaker.position + Vector2(20, 0)
	stage.add_child(other)
	host.anchor_resolver = func(id: String) -> Node2D: return other if id == "other" else speaker
	host._active[0]["age"] = host._active[0]["hold"]
	host.show_lines(&"test_other_bubble", [{"speaker": "other", "text": "先趁熱吃，吃完以後我們再慢慢談明天的事情。"}])
	host._process(0.0)
	await frames(1)
	PromptLayout.update()
	var first: Rect2 = host._active[0].get("rect", Rect2())
	var second: Rect2 = host._active[1].get("rect", Rect2())
	check(first.has_area() and second.has_area() and not first.intersects(second), "adjacent speakers keep both simultaneous bubbles separate")
	camera.zoom = Vector2(4, 4)
	await frames(2)
	prompt._process(1.0)
	check(prompt.enabled and not prompt.is_showing() and prompt._alpha == 0.0, "a view with no free space hides the invitation without disabling its interaction")
	host.queue_free()
	await frames(2)
	prompt._process(1.0)
	check(prompt.is_showing(), "the invitation returns after the temporary bubble leaves")
	stage.queue_free()
	await frames(2)
	check(PromptLayout._obstacles.size() == original_obstacles, "bubble teardown releases its registered reading bounds")


func _rules_scene(lines: Array, bark := false) -> Dictionary:
	var scene := {"mode": "bubbles", "lines": lines}
	if bark:
		scene["bark"] = true
	return scene


func _problems_for(scene: Dictionary) -> PackedStringArray:
	Story._scenes["test_bubble_rules"] = scene
	var all := Story.validate()
	Story._scenes.erase("test_bubble_rules")
	var mine := PackedStringArray()
	for problem in all:
		if problem.contains("test_bubble_rules"):
			mine.append(problem)
	return mine


func _test_rules() -> void:
	check(MapBubbles.hold_time("一二三") == 1.5, "hold time is 1.2s + 0.1s per character (%f)" % MapBubbles.hold_time("一二三"))
	check(MapBubbles.hold_time("一".repeat(60)) == MapBubbles.HOLD_MAX, "hold time is capped at 4.2 seconds")
	var ok := _rules_scene([{"speaker": "rin", "text": "字".repeat(30)}])
	check(_problems_for(ok).is_empty(), "a line of 30 characters is fine %s" % [_problems_for(ok)])
	var long_line := _rules_scene([{"speaker": "rin", "text": "字".repeat(31)}])
	check(not _problems_for(long_line).is_empty(), "31 characters is too long for a bubble")
	var too_many := _rules_scene([{"speaker": "rin", "text": "一"}, {"speaker": "rin", "text": "二"}, {"speaker": "rin", "text": "三"}, {"speaker": "rin", "text": "四"}, {"speaker": "rin", "text": "五"}])
	check(not _problems_for(too_many).is_empty(), "five lines in one bubble scene is too many")
	var bark := _rules_scene([{"speaker": "rin", "text": "字".repeat(17)}], true)
	check(not _problems_for(bark).is_empty(), "a combat bark is capped at 16 characters")
	var bark_ok := _rules_scene([{"speaker": "rin", "text": "字".repeat(16)}], true)
	check(_problems_for(bark_ok).is_empty(), "a 16-character bark is fine")
	var bark_many := _rules_scene([{"speaker": "rin", "text": "一"}, {"speaker": "rin", "text": "二"}, {"speaker": "rin", "text": "三"}], true)
	check(not _problems_for(bark_many).is_empty(), "a bark scene has at most two lines")
	var no_speaker := _rules_scene([{"speaker": "nobody_here", "text": "嗯"}])
	check(not _problems_for(no_speaker).is_empty(), "an undefined speaker is reported")


func _test_in_level() -> void:
	Story.auto_skip = false
	Story.reset_progress()
	GameState.start_new_run(GameState.difficulties[1])
	var level := await spawn_level(load(BOOTH_AREA) as LevelData)
	var host: MapBubbles = level._bubbles
	check(host != null and Story._bubble_host == host, "the level registers its bubble host with the story service")
	check(host.can_show_all([{"speaker": "rin"}]) and not host.can_show_all([{"speaker": "lamp"}]), "rin is on the map, the lamp voice is not")
	Story._scenes["test_bubble_a"] = _rules_scene([{"speaker": "rin", "text": "第一句"}, {"speaker": "rin", "text": "第二句"}, {"speaker": "rin", "text": "第三句"}])
	var finished: Array[StringName] = []
	var on_finished := func(id: StringName) -> void: finished.append(id)
	Story.scene_finished.connect(on_finished)
	var max_seen := 0
	var started := Story.play(&"test_bubble_a")
	check(started, "the scene starts")
	check(not runner.get_tree().paused, "a bubble scene never pauses the game")
	check(not Story.is_cinematic_active(), "a bubble scene is not a cinematic")
	host._process(0.0)
	var age := float(host._active[0]["age"])
	var queued := host._queue.size()
	var modal_lock := GameplayLock.acquire(level)
	host._process(5.0)
	check(not host.visible and float(host._active[0]["age"]) == age and host._queue.size() == queued and not finished.has(&"test_bubble_a"), "a modal hides bubbles and preserves unread lines without a false completion")
	GameplayLock.release(modal_lock)
	host._process(0.0)
	check(host.visible and float(host._active[0]["age"]) == age, "releasing modal resumes the same bubble with its original reading time")
	var guard := 0
	while not finished.has(&"test_bubble_a") and guard < 900:
		await frames(1)
		max_seen = maxi(max_seen, host.visible_count())
		guard += 1
	check(finished.has(&"test_bubble_a"), "the scene finishes after its last bubble fades")
	check(max_seen >= 1 and max_seen <= MapBubbles.MAX_VISIBLE, "never more than two bubbles at once (%d)" % max_seen)
	check(not host.is_busy(), "nothing is left on screen afterwards")
	check(not Story.play(&"test_bubble_a"), "a bubble scene plays once per run (not replayed after a death)")
	# 講者不在地圖上：改用通訊。
	Story._scenes["test_bubble_b"] = _rules_scene([{"speaker": "lamp", "text": "歡迎回來"}])
	var modes: Array[StringName] = []
	var on_started := func(id: StringName, mode: StringName) -> void:
		if id == &"test_bubble_b":
			modes.append(mode)
	Story.scene_started.connect(on_started)
	Story.play(&"test_bubble_b")
	check(modes == [Story.MODE_RADIO], "a voice that is not on the map falls back to the radio panel (%s)" % [modes])
	Story.scene_started.disconnect(on_started)
	Story.scene_finished.disconnect(on_finished)
	Story._scenes.erase("test_bubble_a")
	Story._scenes.erase("test_bubble_b")
	await end_level(level)
	check(Story._bubble_host == null, "leaving the level clears the bubble host")
	Story.reset_progress()


## 關卡結束時還沒播完的氣泡場景：等待它的流程不會永遠卡住。
func _test_released_host_does_not_hang() -> void:
	Story.auto_skip = false
	GameState.start_new_run(GameState.difficulties[1])
	var level := await spawn_level(load(BOOTH_AREA) as LevelData)
	Story._scenes["test_bubble_c"] = _rules_scene([{"speaker": "rin", "text": "一"}, {"speaker": "rin", "text": "二"}])
	var finished := [false]
	var on_finished := func(id: StringName) -> void:
		if id == &"test_bubble_c":
			finished[0] = true
	Story.scene_finished.connect(on_finished)
	Story.play(&"test_bubble_c")
	await frames(5)
	await end_level(level)
	await frames(3)
	check(finished[0], "a scene still playing when the level ends is finished, not left waiting")
	Story.scene_finished.disconnect(on_finished)
	Story._scenes.erase("test_bubble_c")
	# auto_skip：立即結束且仍寫旗標。
	Story.auto_skip = true
	Story._scenes["test_bubble_d"] = {"mode": "bubbles", "lines": [{"speaker": "rin", "text": "嗯"}], "set_flags": ["test_bubble_flag"]}
	await Story.play_and_wait(&"test_bubble_d")
	check(GameState.has_flag(&"test_bubble_flag"), "auto_skip finishes the scene and writes its flag")
	Story._scenes.erase("test_bubble_d")
	Story.reset_progress()
