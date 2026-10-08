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
	Story.auto_skip = previous_auto
	Story.reset_progress()
	GameState.start_new_run(GameState.difficulties[1])


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
