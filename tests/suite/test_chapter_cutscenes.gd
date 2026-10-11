class_name ChapterCutscenesSuite
extends TestSuite
## 兩章的動畫過場（NE-52、NE-53）：資料通過檢查、與靜態劇本文字一致、掛在關卡上、接續播放與略過。
## 靜態劇本（prologue 等）保留為文字稿；動畫版的台詞必須涵蓋文字稿的每一句（系統旁白除外）。

const CHAPTER_1_SCENES := [&"cut_c0_opening", &"cut_c1_shop", &"cut_c2_hangar", &"cut_c3_terminal", &"cut_c8_arm_noise"]
const CHAPTER_2_SCENES := [&"cut_c4_dawn", &"cut_c5_memory", &"cut_c6_corridor", &"cut_c7_elevator", &"cut_c9_alarm"]
## 動畫版 -> 對應的文字稿。
const SCRIPT_OF := {
	"cut_c1_shop": "prologue", "cut_c2_hangar": "boss_intro", "cut_c3_terminal": "epilogue", "cut_c8_arm_noise": "radio_arm",
	"cut_c4_dawn": "c2_prologue", "cut_c5_memory": "c2_memory", "cut_c6_corridor": "c2_boss_intro", "cut_c7_elevator": "c2_epilogue",
}
const MAX_SAYS := 16


func run() -> void:
	_test_scene_data()
	_test_ch1_pose_baseline()
	_test_script_consistency()
	_test_level_bindings()
	_test_chain_rules()
	await _test_chain_playback()
	await _test_user_skip_drops_chain()


func _scene(id: StringName) -> Dictionary:
	return Story._scenes.get(String(id), {})


func _says(scene: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for step: Variant in scene.get("steps", []):
		if typeof(step) == TYPE_DICTIONARY and str(step.get("do", "")) == "say":
			result.append(step)
	return result


func _test_scene_data() -> void:
	for id: StringName in CHAPTER_1_SCENES + CHAPTER_2_SCENES:
		var scene := _scene(id)
		check(not scene.is_empty() and str(scene.get("mode", "")) == "animated", "動畫過場存在：%s" % id)
		check(CutsceneChecker.validate(String(id), scene, Story._speakers).is_empty(), "動畫過場通過檢查：%s" % id)
		check(_says(scene).size() <= MAX_SAYS, "動畫過場台詞不超過 %d 句：%s" % [MAX_SAYS, id])
	check(bool(_scene(&"cut_c8_arm_noise").get("overlay", false)) and bool(_scene(&"cut_c9_alarm").get("overlay", false)), "右臂雜訊與燈幕警報是疊加演出")
	check(Story.chapter_ids().size() == 3, "只提供場景的檔案不會多出章節（舊的兩章加上新的傘；%s）" % [Story.chapter_ids()])
	check(not Story.chapter_info(&"chapter_01").is_empty() and not Story.chapter_info(&"chapter_02").is_empty(), "章節資訊沒有被場景檔覆蓋")


func _test_ch1_pose_baseline() -> void:
	for id in ["ch1_p01_door", "ch1_c09_wake", "ch1_c14_home"]:
		var scene := _scene(StringName(id))
		check(scene.get("pose_policy", "") == "supported", "%s enforces supported poses" % id)
		check(CutsceneChecker.validate(id, scene, Story._speakers).is_empty(), "%s has reasons and supports for restricted poses" % id)
		var staging := CutsceneChecker.staging_problems(id, scene)
		check(staging.is_empty(), "%s keeps actor feet above the dialogue panel: %s" % [id, "；".join(staging)])
	for step: Dictionary in _scene(&"ch1_p01_door")["steps"]:
		if step.get("do") == "actor" and step.get("id") == "rin":
			check(step.get("pose") == "idle", "Rin stands at the pawnshop counter in the opening")
	for action in [{"do": "pose", "id": "rin", "pose": "squat"}, {"do": "move", "id": "rin", "to": [385, 348], "then": "sit"}]:
		var scene := _scene(&"ch1_p01_door").duplicate(true)
		scene["steps"].append(action)
		check("\n".join(CutsceneChecker.validate("pose_negative", scene, Story._speakers)).contains("pose_reason"), "unsupported %s without a reason fails" % action)
		action["pose_reason"] = "在舞台上檢查地面物件。"
		check("\n".join(CutsceneChecker.validate("pose_negative", scene, Story._speakers)).contains("pose_support"), "a reason without a support fails")
		action["pose_support"] = "舞台地板接觸線 y=348。"
		check(CutsceneChecker.validate("pose_positive", scene, Story._speakers).is_empty(), "explicit pose context passes the data check; geometry still needs visual review")


func _test_script_consistency() -> void:
	for animated_id: String in SCRIPT_OF.keys():
		var said := PackedStringArray()
		for step in _says(_scene(StringName(animated_id))):
			said.append(str(step["text"]))
		for line: Variant in _scene(StringName(SCRIPT_OF[animated_id])).get("lines", []):
			var speaker := str(line["speaker"])
			if speaker == "system" and animated_id != "cut_c1_shop" and animated_id != "cut_c5_memory":
				continue
			check(said.has(str(line["text"])), "動畫版 %s 保留文字稿的台詞：「%s」" % [animated_id, line["text"]])


func _test_level_bindings() -> void:
	var level_1 := load("res://data/levels/level_01.tres") as LevelData
	var level_2 := load("res://data/levels/level_02.tres") as LevelData
	check(level_1.intro_scene == &"cut_c0_opening" and level_1.boss_scene == &"cut_c2_hangar" and level_1.outro_scene == &"cut_c3_terminal", "第一章的開場、頭目、結尾使用動畫過場")
	check(level_2.intro_scene == &"cut_c4_dawn" and level_2.boss_scene == &"cut_c6_corridor" and level_2.outro_scene == &"cut_c7_elevator", "第二章的開場、頭目、結尾使用動畫過場")
	check(level_1.story_triggers.has("cut_c8_arm_noise"), "第一章設施裡有右臂雜訊演出")
	check(level_2.story_triggers.has("cut_c5_memory"), "第二章升降井有記憶演出")
	check(_scene(&"cut_c0_opening").get("then", "") == "cut_c1_shop", "片頭接開場")


func _test_chain_rules() -> void:
	Story._scenes["test_chain_a"] = {"mode": "animated", "then": "test_chain_b", "steps": [{"do": "wait", "time": 0.1}]}
	Story._scenes["test_chain_b"] = {"mode": "animated", "then": "test_chain_a", "steps": [{"do": "wait", "time": 0.1}]}
	Story._scenes["test_chain_radio"] = {"mode": "radio", "then": "test_chain_a", "lines": [{"speaker": "rin", "text": "嗯。"}]}
	Story._scenes["test_chain_missing"] = {"mode": "animated", "then": "test_no_such_next", "steps": [{"do": "wait", "time": 0.1}]}
	Story._scenes["test_chain_to_radio"] = {"mode": "animated", "then": "radio_start", "steps": [{"do": "wait", "time": 0.1}]}
	var problems := "\n".join(Story.validate())
	check(problems.contains("test_chain_a 的接續形成迴圈"), "接續形成迴圈會被指出")
	check(problems.contains("test_chain_radio（radio）不能設定 then"), "通訊不能設定 then")
	check(problems.contains("test_no_such_next"), "接續場景不存在會被指出")
	check(problems.contains("test_chain_to_radio 的接續場景「radio_start」"), "接續到通訊會被指出")
	for id in ["test_chain_a", "test_chain_b", "test_chain_radio", "test_chain_missing", "test_chain_to_radio"]:
		Story._scenes.erase(id)


func _test_chain_playback() -> void:
	var previous_auto := Story.auto_skip
	Story.auto_skip = true
	Story._scenes["test_chain_one"] = {"mode": "animated", "then": "test_chain_two", "steps": [{"do": "wait", "time": 0.05}]}
	Story._scenes["test_chain_two"] = {"mode": "animated", "then": "test_chain_three", "steps": [{"do": "wait", "time": 0.05}]}
	Story._scenes["test_chain_three"] = {"mode": "animated", "steps": [{"do": "wait", "time": 0.05}]}
	var order: Array[StringName] = []
	var on_started := func(id: StringName, _mode: StringName) -> void: order.append(id)
	Story.scene_started.connect(on_started)
	var done := [false]
	var waiter := func() -> void:
		await Story.play_and_wait(&"test_chain_one", false)
		done[0] = true
	waiter.call()
	for i in 20:
		if done[0]:
			break
		await frames(1)
	check(done[0], "play_and_wait 等到接續場景全部播完")
	check(order == [&"test_chain_one", &"test_chain_two", &"test_chain_three"], "接續場景依序播放 %s" % [order])
	check(not Story.is_cinematic_active(), "整串播完後不再是過場狀態")
	# 已看過的接續場景不重播。
	order.clear()
	check(Story.play(&"test_chain_one", false), "再播一次起點")
	await frames(6)
	check(order == [&"test_chain_one"], "已看過的接續場景不會重播 %s" % [order])
	Story.scene_started.disconnect(on_started)
	for id in ["test_chain_one", "test_chain_two", "test_chain_three"]:
		Story._scenes.erase(id)
	Story.auto_skip = previous_auto


func _test_user_skip_drops_chain() -> void:
	var previous_auto := Story.auto_skip
	Story.auto_skip = false
	Story._scenes["test_skip_one"] = {"mode": "animated", "then": "test_skip_two", "steps": [{"do": "wait", "time": 30.0}]}
	Story._scenes["test_skip_two"] = {"mode": "animated", "steps": [{"do": "wait", "time": 30.0}]}
	var order: Array[StringName] = []
	var on_started := func(id: StringName, _mode: StringName) -> void: order.append(id)
	Story.scene_started.connect(on_started)
	Story.play(&"test_skip_one", false)
	await frames(5)
	Story.skip_cinematic()
	await frames(10)
	check(order == [&"test_skip_one"], "玩家按略過時，接續的場景一併略過 %s" % [order])
	check(not Story.is_cinematic_active(), "略過後回到遊戲")
	Story.scene_started.disconnect(on_started)
	for id in ["test_skip_one", "test_skip_two"]:
		Story._scenes.erase(id)
	Story.auto_skip = previous_auto
