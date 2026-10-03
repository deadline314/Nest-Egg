class_name DeathReactionSuite
extends TestSuite
## 依死亡次數變化的劇情與回溯紀錄（NE-51）：死亡次數是本輪進度（不隨檢查點回溯、新一輪歸零）、
## 場景的「死亡次數達到 N 次時改用的台詞」、3／8／15／30／50 次的反應、世界時鐘、重生後的廣播、
## 死亡畫面的「NEST 回溯紀錄 #n」、壞資料的容錯；這些只影響措辭，不影響流程。

const LEVEL_1 := "res://data/levels/level_01.tres"
const LEVEL_2 := "res://data/levels/level_02.tres"


func run() -> void:
	_test_death_counter_is_run_progress()
	_test_world_clock()
	_test_variants_follow_thresholds()
	_test_the_reaction_table()
	_test_variants_change_wording_only()
	_test_placeholder_and_delay_lines()
	_test_death_note()
	_test_respawn_reactions()
	_test_bad_variant_data()
	await _test_radio_delay()
	await _test_play_uses_variants()
	await _test_level_respawn_reaction()
	await _test_death_screen()
	GameState.start_new_run(GameState.difficulties[1])


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _texts(lines: Array) -> String:
	var parts := PackedStringArray()
	for line: Variant in lines:
		parts.append(str((line as Dictionary).get("text", "")))
	return "\n".join(parts)


## 清掉通訊佇列（前面的測試播過的通訊還在排隊）。
func _clear_radio() -> void:
	var layer := Story._layer
	layer._radio_queue.clear()
	layer._radio_active = false
	layer._radio_wait = 0.0
	layer._radio_root.visible = false


func _find_labels(node: Node, needle: String, result: Array[Label]) -> void:
	for child in node.get_children():
		if child is Label and (child as Label).text.contains(needle):
			result.append(child)
		_find_labels(child, needle, result)


# ---------------------------------------------------------------------------
# 死亡次數是本輪進度
# ---------------------------------------------------------------------------

func _test_death_counter_is_run_progress() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	check(GameState.deaths == 0 and not GameState.respawn_pending and GameState.last_death_clock.is_empty(), "a new run starts with no deaths")
	for i in 3:
		GameState.register_death()
	check(GameState.deaths == 3, "every death is counted (%d)" % GameState.deaths)
	check(GameState.respawn_pending and not GameState.last_death_clock.is_empty(), "a death marks the next level build as a respawn and records the time")
	# 檢查點、換關都不會讓次數歸零，也不會被存進檢查點。
	GameState.set_checkpoint(Vector2(10, 10), {}, {"a": 1}, {})
	check(GameState.deaths == 3, "setting a checkpoint does not touch the death count")
	check(not GameState.checkpoint_world.has("deaths") and not GameState.checkpoint_progress.has("deaths") and not GameState.checkpoint_loadout.has("deaths"), "the death count is not part of the checkpoint snapshot")
	GameState.clear_checkpoint()
	GameState.enter_level()
	check(GameState.deaths == 3, "returning to the level start or entering the next level keeps the count")
	check(GameState.consume_respawn() and not GameState.consume_respawn(), "a respawn is consumed once")
	# 殘機用盡（重新開始關卡）也不歸零。
	GameState.start_new_run(GameState.difficulties[2])
	var lives := GameState.lives_left
	for i in lives:
		GameState.register_death()
	check(GameState.deaths == lives, "running out of lives restarts the level but keeps counting (%d)" % GameState.deaths)
	# 新的一輪才歸零。
	GameState.start_new_run(GameState.difficulties[1])
	check(GameState.deaths == 0 and not GameState.respawn_pending, "a new run resets the death count")


func _test_world_clock() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	check(GameState.world_clock_text(0.0) == "21 點 0 分", "the world clock starts at 21:00 (%s)" % GameState.world_clock_text(0.0))
	check(GameState.world_clock_text(1200.0) == "0 點 20 分", "ten world seconds pass per second and the clock wraps past midnight (%s)" % GameState.world_clock_text(1200.0))
	GameState.run_time = 2400.0
	check(GameState.world_clock_text() == "3 點 40 分", "the default is the run time so far (%s)" % GameState.world_clock_text())
	GameState.run_time = 0.0


# ---------------------------------------------------------------------------
# 場景的死亡次數變化
# ---------------------------------------------------------------------------

func _test_variants_follow_thresholds() -> void:
	var base := Story.lines_for(&"radio_shield", 0)
	check(_texts(base).contains("貴欸") and not _texts(base).contains("停過"), "no deaths: the normal line")
	check(_texts(Story.lines_for(&"radio_shield", 7)) == _texts(base), "below the threshold nothing changes")
	check(_texts(Story.lines_for(&"radio_shield", 8)).contains("你是不是在這裡停過"), "eight deaths: mei asks if you stopped here before")
	check(_texts(Story.lines_for(&"radio_shield", 40)).contains("停過"), "the variant keeps applying beyond the threshold")
	# 多個門檻：取達到的最高一個。
	Story._scenes["test_tiers"] = {"mode": "radio", "lines": [{"speaker": "rin", "text": "零。"}], "variants": [
		{"min_deaths": 20, "lines": [{"speaker": "rin", "text": "二十。"}]},
		{"min_deaths": 5, "lines": [{"speaker": "rin", "text": "五。"}]},
	]}
	check(_texts(Story.lines_for(&"test_tiers", 4)) == "零。" and _texts(Story.lines_for(&"test_tiers", 5)) == "五。", "a variant applies from its threshold")
	check(_texts(Story.lines_for(&"test_tiers", 19)) == "五。" and _texts(Story.lines_for(&"test_tiers", 20)) == "二十。", "the highest reached threshold wins, whatever the order in the file")
	Story._scenes.erase("test_tiers")
	# 預設用目前的累計死亡。
	GameState.start_new_run(GameState.difficulties[1])
	check(_texts(Story.lines_for(&"radio_shield")).contains("貴欸") and not _texts(Story.lines_for(&"radio_shield")).contains("停過"), "the default count is the run's deaths")
	for i in 8:
		GameState.register_death()
	check(_texts(Story.lines_for(&"radio_shield")).contains("停過"), "the default count follows the run's deaths")
	GameState.start_new_run(GameState.difficulties[1])
	check(Story.lines_for(&"no_such_scene", 99).is_empty(), "an unknown scene has no lines")


## 伏筆表（F19）的反應：3、8、15、30、50 次。
func _test_the_reaction_table() -> void:
	# 3：死亡畫面多一行小字（見 _test_death_note）。
	check(Story.death_note(2).is_empty() and not Story.death_note(3).is_empty(), "three deaths: the death screen gets an extra small line")
	# 8：芽的通訊多出一句「剛才……你是不是在這裡停過？」，凜回「沒有。」
	var mei_scenes := 0
	for id in [&"radio_market_mei", &"radio_shield", &"radio_facility", &"c2_radio_corridor", &"c2_radio_medic", &"c2_radio_last"]:
		if not Story.has_scene(id):
			continue
		var lines := Story.lines_for(id, 8)
		var text := _texts(lines)
		if text.contains("你是不是在這裡停過"):
			mei_scenes += 1
			check(str(lines[0]["speaker"]) == "mei" and text.contains("沒有"), "eight deaths: %s has mei asking and rin answering" % id)
	check(mei_scenes >= 4, "eight deaths changes several of mei's radios (%d)" % mei_scenes)
	# 15：老 K 少一句碎念，只剩「你臉色很差」。
	for id in [&"radio_mech", &"radio_last", &"c2_radio_k1", &"c2_radio_k2"]:
		if not Story.has_scene(id):
			continue
		var normal := _texts(Story.lines_for(id, 14))
		var worn := _texts(Story.lines_for(id, 15))
		check(worn.contains("你臉色很差") and not normal.contains("你臉色很差"), "fifteen deaths: old K says only that you look bad: %s" % id)
		check(worn.length() < normal.length() + 8, "old K's line gets shorter, not longer: %s" % id)
	# 30：天穹廣播在重生的位置念出剛剛死掉的時間。
	check(Story.respawn_scene_ids(&"chapter_01", 29).is_empty() and Story.respawn_scene_ids(&"chapter_01", 30).has(&"respawn_30"), "thirty deaths: the broadcast starts at respawn")
	GameState.last_death_clock = "11 點 40 分"
	check(_texts(Story.resolved_lines(&"respawn_30", 30)).contains("剛剛的雨，在 11 點 40 分。"), "the broadcast reads the time you just died")
	# 50：芽主動關掉通訊一次，沒說原因，十秒後接回來。
	var ids := Story.respawn_scene_ids(&"chapter_01", 50)
	check(ids.has(&"respawn_50"), "fifty deaths: mei closes the line")
	var closing := Story.lines_for(&"respawn_50", 50)
	check(closing.size() == 2 and float(closing[1].get("delay", 0.0)) == 10.0, "and reconnects ten seconds later")
	check(not _texts(closing).contains("因為") and not _texts(closing).contains("原因"), "she gives no reason")


func _test_variants_change_wording_only() -> void:
	for id: String in Story.scene_ids():
		var scene: Dictionary = Story._scenes[id]
		var mode := str(scene.get("mode", "radio"))
		var variants: Variant = scene.get("variants", [])
		if typeof(variants) != TYPE_ARRAY:
			continue
		for variant: Variant in variants:
			var lines: Array = (variant as Dictionary).get("lines", [])
			var limit := 2 if mode == "radio" else (6 if mode == "cinematic" else 8)
			check(lines.size() >= 1 and lines.size() <= limit, "%s: a variant keeps the scene's length limit (%d)" % [id, lines.size()])
			for line: Variant in lines:
				check(Story.speaker_ids().has(str((line as Dictionary).get("speaker", ""))), "%s: a variant uses defined speakers" % id)
	# 變化只影響措辭：場景類型、觸發方式、取得的道具都不變，同一場景在任何次數下都是同一個模式。
	for id in [&"radio_shield", &"radio_mech", &"radio_last"]:
		check(str(Story._scenes[String(id)]["mode"]) == "radio", "a scene with variants is still a radio: %s" % id)
	check(Story.validate().is_empty(), "variants pass validation and the quality check: %s" % [Story.validate()])
	var issues := Story.lint()
	check(issues.is_empty(), "variants are checked by the quality check too")
	# 檢查範圍包含變化台詞。
	var found := false
	for unit in Story.text_units(&"chapter_01"):
		if str(unit["id"]).contains("radio_shield") and str(unit["id"]).contains("死亡"):
			found = true
	check(found, "the quality check scans the death variants")


func _test_placeholder_and_delay_lines() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	GameState.last_death_clock = "3 點 5 分"
	var lines := Story.resolved_lines(&"respawn_30", 30)
	check(lines.size() == 1 and str(lines[0]["text"]).contains("3 點 5 分") and not str(lines[0]["text"]).contains("{death_time}"), "the death time placeholder is filled in")
	GameState.last_death_clock = ""
	GameState.run_time = 1200.0
	check(str(Story.resolved_lines(&"respawn_30", 30)[0]["text"]).contains("0 點 20 分"), "without a recorded death the current world time is used")
	GameState.run_time = 0.0
	var closing := Story.resolved_lines(&"respawn_50", 50)
	check(float(closing[0].get("delay", 0.0)) == 0.0 and float(closing[1].get("delay", 0.0)) == 10.0, "line delays come through to the dialogue box")
	# 壞的 delay 當作沒有。
	Story._scenes["test_bad_delay"] = {"mode": "radio", "lines": [{"speaker": "rin", "text": "好。", "delay": "很久"}, {"speaker": "rin", "text": "好。", "delay": -4}]}
	var bad := Story.resolved_lines(&"test_bad_delay", 0)
	check(float(bad[0].get("delay", 0.0)) == 0.0 and float(bad[1].get("delay", 0.0)) == 0.0, "a bad delay is ignored")
	Story._scenes.erase("test_bad_delay")


func _test_death_note() -> void:
	check(Story.death_note(0).is_empty() and Story.death_note(2).is_empty(), "no note before three deaths")
	check(Story.death_note(3) == "紀錄已寫入。" and Story.death_note(99) == "紀錄已寫入。", "a note from three deaths on, with no explanation")
	Story._death_notes.append({"min_deaths": 20, "text": "第二行"})
	check(Story.death_note(19) == "紀錄已寫入。" and Story.death_note(20) == "第二行", "the highest reached note wins")
	Story._death_notes.pop_back()
	Story._death_notes.append({"min_deaths": "壞", "text": 5})
	check(Story.death_note(3) == "紀錄已寫入。", "a malformed note is ignored")
	Story._death_notes.pop_back()


func _test_respawn_reactions() -> void:
	var started: Array[StringName] = []
	var on_started := func(id: StringName, _mode: StringName) -> void: started.append(id)
	Story.scene_started.connect(on_started)
	Story.reset_progress()
	check(Story.play_respawn_reactions(&"chapter_01", 29) == 0 and started.is_empty(), "nothing plays below thirty deaths")
	check(Story.play_respawn_reactions(&"chapter_01", 30) == 1 and started == [&"respawn_30"], "thirty deaths: the broadcast plays")
	check(Story.play_respawn_reactions(&"chapter_01", 31) == 1 and started.size() == 2, "and it plays again at every respawn")
	started.clear()
	Story.reset_progress()
	check(Story.play_respawn_reactions(&"chapter_01", 50) == 2 and started.has(&"respawn_30") and started.has(&"respawn_50"), "fifty deaths: both reactions play")
	started.clear()
	check(Story.play_respawn_reactions(&"chapter_01", 51) == 1 and started == [&"respawn_30"], "mei closes the line only once")
	check(Story.play_respawn_reactions(&"no_such_chapter", 99) == 0, "an unknown chapter has no reactions")
	Story.scene_started.disconnect(on_started)
	Story.reset_progress()
	_clear_radio()
	# 兩章各有自己的版本。
	check(Story.respawn_scene_ids(&"chapter_02", 30).has(&"c2_respawn_30") and Story.respawn_scene_ids(&"chapter_02", 50).has(&"c2_respawn_50"), "chapter two has its own reactions")


func _test_bad_variant_data() -> void:
	var before := Story.validate().size()
	var good := [{"speaker": "rin", "text": "好。"}]
	# 結構壞掉（門檻無效、沒有台詞、不是物件）：啟動時指出位置，執行時略過、退回正常台詞。
	Story._scenes["test_bad_variants"] = {"mode": "radio", "lines": good, "variants": [
		{"min_deaths": 0, "lines": [{"speaker": "rin", "text": "零。"}]},
		{"min_deaths": "壞", "lines": [{"speaker": "rin", "text": "壞。"}]},
		{"min_deaths": 5, "lines": []},
		{"min_deaths": 6, "lines": "不是陣列"},
		"garbage",
	]}
	Story._scene_chapter["test_bad_variants"] = &"chapter_01"
	var problems := Story.validate()
	var joined := "\n".join(problems)
	check(problems.size() - before >= 5, "broken variants are reported one by one (%d problems)" % (problems.size() - before))
	check(joined.contains("test_bad_variants") and joined.contains("死亡變化"), "the report names the scene and the variant: %s" % joined)
	check(_texts(Story.lines_for(&"test_bad_variants", 100)) == "好。", "broken variants fall back to the normal lines")
	# 內容不合規（講者未定義、句數超過上限）：同樣指出位置。
	Story._scenes["test_bad_variants"] = {"mode": "radio", "lines": good, "variants": [
		{"min_deaths": 6, "lines": [{"speaker": "nobody", "text": "誰。"}]},
		{"min_deaths": 7, "lines": [{"speaker": "rin", "text": "一。"}, {"speaker": "rin", "text": "二。"}, {"speaker": "rin", "text": "三。"}]},
	]}
	problems = Story.validate()
	check(problems.size() - before >= 2 and "\n".join(problems).contains("未定義") and "\n".join(problems).contains("上限"), "a variant with an unknown speaker or too many lines is reported")
	Story._scenes["test_bad_variants"] = {"mode": "radio", "lines": good, "variants": "不是陣列"}
	check("\n".join(Story.validate()).contains("variants 必須是陣列") and _texts(Story.lines_for(&"test_bad_variants", 100)) == "好。", "variants that are not a list are reported and ignored")
	Story._scenes.erase("test_bad_variants")
	Story._scene_chapter.erase("test_bad_variants")
	# 重生通訊與死亡畫面小字的壞資料。
	Story._respawn_scenes[&"test_chapter"] = [{"scene": "test_no_such_scene", "min_deaths": 0}, "garbage"]
	Story._death_notes.append({"min_deaths": "壞", "text": 5})
	problems = Story.validate()
	joined = "\n".join(problems)
	check(problems.size() - before >= 4 and joined.contains("test_chapter") and joined.contains("重生通訊") and joined.contains("死亡畫面小字"), "broken respawn scenes and notes are reported: %s" % joined)
	check(Story.respawn_scene_ids(&"test_chapter", 99).size() <= 1 and Story.death_note(99) == "紀錄已寫入。", "broken entries never reach the player")
	Story._respawn_scenes.erase(&"test_chapter")
	Story._death_notes.pop_back()
	check(Story.validate().size() == before, "validation is back to normal")


# ---------------------------------------------------------------------------
# 對話框與關卡
# ---------------------------------------------------------------------------

func _test_radio_delay() -> void:
	_clear_radio()
	Story.auto_skip = false
	Story._scenes["test_radio_delay"] = {"mode": "radio", "lines": [
		{"speaker": "mei", "text": "先關了。"}, {"speaker": "mei", "text": "回來了。", "delay": 0.6},
	]}
	var finished: Array[StringName] = []
	var on_finished := func(id: StringName) -> void: finished.append(id)
	Story.scene_finished.connect(on_finished)
	Story.reset_progress()
	Story.play(&"test_radio_delay")
	await frames(6)
	var layer := Story._layer
	check(layer._radio_root.visible and layer._radio_text.text == "先關了。", "the first line shows right away")
	# 等第一句念完並收起，進入沉默。
	var guard := 0
	while layer._radio_text.text != "回來了。" and guard < 400:
		await frames(1)
		guard += 1
	check(layer._radio_text.text == "回來了。" and not layer._radio_root.visible, "the line with a delay is silent first: the box is hidden")
	guard = 0
	while not layer._radio_root.visible and guard < 400:
		await frames(1)
		guard += 1
	check(layer._radio_root.visible, "the line appears after the delay")
	guard = 0
	while finished.is_empty() and guard < 600:
		await frames(1)
		guard += 1
	check(finished == [&"test_radio_delay"], "the scene still finishes once")
	Story.scene_finished.disconnect(on_finished)
	Story._scenes.erase("test_radio_delay")
	Story.auto_skip = true
	Story.reset_progress()


func _test_play_uses_variants() -> void:
	_clear_radio()
	Story.auto_skip = false
	GameState.start_new_run(GameState.difficulties[1])
	for i in 8:
		GameState.register_death()
	Story.reset_progress()
	Story.play(&"radio_shield")
	await frames(3)
	var queue_text := ""
	for entry: Dictionary in Story._layer._radio_queue:
		queue_text += str(entry["line"]["text"])
	check(queue_text.contains("停過") or Story._layer._radio_text.text.contains("停過"), "playing a scene with eight deaths shows the variant")
	# 流程不變：同一個場景一輪只播一次，與死亡次數無關。
	check(not Story.play(&"radio_shield"), "the scene still plays only once per run")
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	_clear_radio()
	await frames(2)


func _test_level_respawn_reaction() -> void:
	Story.auto_skip = true
	var data := load(LEVEL_1) as LevelData
	var started: Array[StringName] = []
	var on_started := func(id: StringName, _mode: StringName) -> void: started.append(id)
	Story.scene_started.connect(on_started)
	# 沒有剛死過：即使累計很多次，建立關卡時也不會播重生廣播。
	GameState.start_new_run(GameState.difficulties[1])
	GameState.deaths = 35
	var level := await spawn_level(data)
	await frames(100)
	check(not started.has(&"respawn_30"), "no respawn broadcast when the level was not rebuilt after a death")
	await end_level(level)
	# 剛死過、累計 30 次：重生後念出廣播，且廣播不暫停遊戲。
	started.clear()
	Story.reset_progress()
	GameState.deaths = 29
	GameState.register_death()
	check(GameState.deaths == 30 and GameState.respawn_pending, "the thirtieth death is pending a respawn")
	level = await spawn_level(data)
	var guard := 0
	while not started.has(&"respawn_30") and guard < 400:
		await frames(1)
		guard += 1
	check(started.has(&"respawn_30"), "thirty deaths: the respawned level plays the broadcast")
	check(not GameState.respawn_pending, "the respawn is consumed by the level")
	check(not runner.get_tree().paused, "the broadcast does not pause the game")
	await end_level(level)
	# 次數不夠：不播。
	started.clear()
	GameState.start_new_run(GameState.difficulties[1])
	for i in 5:
		GameState.register_death()
	level = await spawn_level(data)
	await frames(100)
	check(started.is_empty() or not started.has(&"respawn_30"), "five deaths: no broadcast")
	check(is_instance_valid(level.player) and not level.player.is_dead(), "reactions never change the level itself")
	await end_level(level)
	Story.scene_started.disconnect(on_started)
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	_clear_radio()


func _test_death_screen() -> void:
	Story.auto_skip = true
	var card := {"number": 1, "title": "測試", "text": "x", "hint": "", "is_new": false}
	for deaths in [1, 2, 3, 12]:
		GameState.start_new_run(GameState.difficulties[1])
		GameState.deaths = deaths
		var screen := DeathScreen.new()
		screen.setup(card, true)
		runner.get_tree().root.add_child(screen)
		await frames(3)
		var titles: Array[Label] = []
		_find_labels(screen, "NEST 回溯紀錄 #%d" % deaths, titles)
		check(titles.size() == 1, "death %d: the screen shows 「NEST 回溯紀錄 #%d」" % [deaths, deaths])
		var old_style: Array[Label] = []
		_find_labels(screen, "回溯 #", old_style)
		check(old_style.is_empty(), "the old 「回溯 #n」 title is replaced, not kept beside the new one")
		var notes: Array[Label] = []
		_find_labels(screen, Story.death_note(3), notes)
		check(notes.size() == (1 if deaths >= 3 else 0), "death %d: the small note appears from three deaths on" % deaths)
		runner.get_tree().root.remove_child(screen)
		screen.free()
	var caption := str((load("res://game/main.gd") as GDScript).get_script_constant_map().get("RETRY_CAPTION", ""))
	check(caption.contains("NEST 回溯紀錄"), "the retry transition caption uses the same name: %s" % caption)
	# 真的死一次：死亡畫面顯示本輪累計的次數。
	GameState.start_new_run(GameState.difficulties[1])
	var level := await start_level(load(LEVEL_1) as LevelData)
	var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"grunt_shot")
	lethal.ignore_invulnerability = true
	level.player.health.take_damage(lethal)
	await frames(130)
	var found: Array[Label] = []
	_find_labels(level, "NEST 回溯紀錄 #1", found)
	check(found.size() == 1 and GameState.deaths == 1, "a real death shows the first record")
	await end_level(level)
	GameState.start_new_run(GameState.difficulties[1])
