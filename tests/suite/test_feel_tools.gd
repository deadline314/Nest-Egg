class_name FeelToolsSuite
extends TestSuite
## 實驗室工具（NE-150、NE-151）：A／B 兩槽儲存與一鍵切換、依序重播、盲測十次統計並寫檔、對照截圖；
## 事件錄放（固定種子、不同參數重播、匯出）與預算煙霧測試（能偵測超標）。

const TEMP_DIR := "user://feel_tools_test"
const SAMPLE := "res://tests/fixtures/feel_record_sample.json"


func run() -> void:
	await _test_ab_slots_and_replay()
	await _test_blind_test()
	await _test_record_and_replay()
	await _test_budget_smoke()
	_cleanup()


func _cleanup() -> void:
	for file in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR + "/" + file)
	DirAccess.remove_absolute(TEMP_DIR)


func _px(id: StringName) -> float:
	return float(Feel.event_def(id)["shake"]["px"])


func _test_ab_slots_and_replay() -> void:
	var ab := FeelAB.new()
	var original := _px(&"boss_land")
	check(not ab.activate("A") and not ab.save_slot("C"), "an empty slot cannot be activated and unknown slots are refused")
	check(ab.save_slot("A"), "slot A stores the current parameters")
	FeelParams.set_value(Feel.event_def(&"boss_land"), ["shake", "px"], 9.0)
	Feel.set_preset(&"heavy")
	check(ab.save_slot("B"), "slot B stores a different set")
	check(ab.toggle() == "A" and is_equal_approx(_px(&"boss_land"), original) and Feel.preset == &"standard", "one key switches back to A and applies it immediately")
	check(ab.toggle() == "B" and is_equal_approx(_px(&"boss_land"), 9.0) and Feel.preset == &"heavy", "and over to B")
	# 依序重播同一事件：A 再 B。
	var order: Array[float] = []
	await ab.replay_sequence(runner, &"boss_land", func(id: StringName) -> void: order.append(float(Feel.event_def(id)["shake"]["px"])), 0.05)
	check(order.size() == 2 and is_equal_approx(order[0], original) and is_equal_approx(order[1], 9.0) and ab.active == "B", "the same event replays under A then B and returns to the active slot")
	# 對照截圖（沒有畫面時回傳空字串，不崩潰）。
	var shot := FeelAB.save_screenshot(runner.get_viewport(), "test", TEMP_DIR)
	check(shot == "" or FileAccess.file_exists(shot), "a comparison screenshot is saved when there is a picture")
	# 還原。
	ab.activate("A")
	FeelParams.set_value(Feel.event_def(&"boss_land"), ["shake", "px"], original)
	Feel.set_preset(&"standard")


func _test_blind_test() -> void:
	var ab := FeelAB.new()
	check(not ab.start_blind(&"boss_land"), "a blind test needs both slots")
	ab.save_slot("A")
	var original := _px(&"boss_land")
	FeelParams.set_value(Feel.event_def(&"boss_land"), ["shake", "px"], 8.0)
	ab.save_slot("B")
	check(ab.start_blind(&"boss_land", 99) and ab.round_count() == FeelAB.BLIND_ROUNDS, "a blind test has ten rounds")
	check(ab.save_results(TEMP_DIR) == "", "unfinished tests are not written")
	var plays: Array[float] = []
	await ab.play_round(0, runner, func(id: StringName) -> void: plays.append(float(Feel.event_def(id)["shake"]["px"])), 0.02)
	check(plays.size() == 2 and not is_equal_approx(plays[0], plays[1]), "a round plays both options, one after the other")
	# 同一個種子的順序一致；總是選第一個時，統計等於各輪先播的是誰。
	var again := FeelAB.new()
	again.slots = ab.slots
	again.start_blind(&"boss_land", 99)
	check(again.blind_rounds == ab.blind_rounds, "the same seed gives the same blind order")
	var expected_a := 0
	var expected_b := 0
	for i in ab.round_count():
		check(ab.answer(i, 1), "round %d can be answered" % (i + 1))
		if (ab.blind_rounds[i] as Array)[0] == "A":
			expected_a += 1
		else:
			expected_b += 1
	check(not ab.answer(0, 3) and not ab.answer(99, 1), "invalid answers are refused")
	var tally := ab.tally()
	check(int(tally["answered"]) == 10 and int(tally["A"]) == expected_a and int(tally["B"]) == expected_b and int(tally["A"]) + int(tally["B"]) == 10, "the tally counts every answer for the right slot")
	var path := ab.save_results(TEMP_DIR)
	check(path != "" and FileAccess.file_exists(path), "finished results are written to the user folder")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(typeof(saved) == TYPE_DICTIONARY and int((saved["tally"] as Dictionary)["answered"]) == 10, "the written file contains the tally")
	ab.activate("A")
	FeelParams.set_value(Feel.event_def(&"boss_land"), ["shake", "px"], original)


func _test_record_and_replay() -> void:
	var record := FeelRecord.new()
	record.seed_value = 777
	record.start()
	Feel.play(&"boss_land", {"dir": Vector2.LEFT, "origin": Vector2(100, 50)})
	Sfx.play_event(&"hit_enemy")
	HitFeedback.play(&"metal", Vector2(10, 20), Vector2.UP, Color.WHITE, {"weak": true})
	record.capture_inputs()
	record.stop()
	check(record.events.size() >= 3 and FeelRecord.active == null, "events are recorded while recording")
	var kinds := {}
	for entry in record.events:
		kinds[entry["kind"]] = true
	check(kinds.has("feel") and kinds.has("sound") and kinds.has("material"), "feel, sound and material events are all recorded")
	# 錄檔可匯出再讀回，內容一致。
	var path := record.save(TEMP_DIR, "roundtrip")
	check(path != "" and FileAccess.file_exists(path), "a record is exported to a folder")
	var loaded := FeelRecord.load_file(path)
	check(loaded != null and loaded.events.size() == record.events.size() and loaded.seed_value == 777 and loaded.inputs.size() == 1, "an exported record loads back the same")
	# 同一份錄檔套用不同參數：重播出來的震動不同。
	var shakes: Array[float] = []
	var on_shake := func(px: float, _t: float, _d: Vector2, _o: Vector2) -> void: shakes.append(px)
	EventBus.screen_shake.connect(on_shake)
	var original := _px(&"boss_land")
	await loaded.replay_events(runner, 50.0)
	FeelParams.set_value(Feel.event_def(&"boss_land"), ["shake", "px"], original * 0.5)
	await loaded.replay_events(runner, 50.0)
	FeelParams.set_value(Feel.event_def(&"boss_land"), ["shake", "px"], original)
	EventBus.screen_shake.disconnect(on_shake)
	check(shakes.size() >= 2 and shakes[1] < shakes[0] - 0.1, "the same record plays differently under different parameters (%s)" % str(shakes))
	check(FeelRecord.active == null, "replaying does not record")
	# 固定種子：兩次重播後的亂數序列一致。
	var first_stats := await loaded.replay_events(runner, 50.0)
	var second_stats := await loaded.replay_events(runner, 50.0)
	var fresh := RandomNumberGenerator.new()
	fresh.seed = 777
	check(first_stats["rng_probe"] == second_stats["rng_probe"], "every replay starts from the same random state")
	seed(777)
	check(first_stats["rng_probe"] == randi(), "and it is the state the record's seed produces")
	# 輸入回放：依錄下的步驟按住與放開。
	var inputs := FeelRecord.new()
	inputs.inputs = [{"f": 0, "a": ["shoot"]}, {"f": 1, "a": []}]
	inputs.apply_inputs(0)
	check(Input.is_action_pressed(&"shoot"), "input replay presses the recorded actions")
	inputs.apply_inputs(1)
	check(not Input.is_action_pressed(&"shoot"), "and releases them on the next step")
	inputs.apply_inputs(5)


func _test_budget_smoke() -> void:
	# 煙霧測試：載入範例錄檔重播，檢查預算。
	var sample := FeelRecord.load_file(SAMPLE)
	check(sample != null and sample.events.size() > 20, "the sample record loads")
	if sample == null:
		return
	FlashGuard.reset()
	var stats := await sample.replay_events(runner, 40.0)
	var problems := sample.check_budgets(stats)
	check(problems.is_empty(), "the sample battle stays inside every budget: %s" % "; ".join(problems))
	# 能偵測超標：一秒內塞很多頓幀與全螢幕閃光。
	var heavy := FeelRecord.new()
	for i in 40:
		heavy.events.append({"t": 1.0 + float(i) * 0.01, "kind": "feel", "id": "player_hurt"})
	var overload := heavy.check_budgets({"particles": 5000, "voices": 40, "flash_per_second": 9, "frozen": 90})
	check(overload.size() >= 5, "overloads are detected (%d problems)" % overload.size())
	check(" ".join(overload).contains("particles") and " ".join(overload).contains("hitstop"), "the problems name the budget that was exceeded")
	FlashGuard.reset()
	Fx._hitstop_log.clear()
