class_name CutsceneSuite
extends TestSuite
## 過場動畫系統（NE-38）：資料檢查、所有步驟播放、跳過、損毀資料容錯、暫停還原、與 Story 整合。
## 故意損毀的演出 id 含 test_bad_cutscene，執行器會忽略它們的錯誤輸出。

const GOOD_SCENE := {
	"mode": "animated",
	"steps": [
		{"do": "scene", "id": "test_room", "fade": 0.1},
		{"do": "letterbox", "on": true, "time": 0.1, "wait": true},
		{"do": "camera", "pos": [300, 170], "zoom": 1.1, "time": 0.2, "wait": true},
		{"do": "actor", "id": "rin", "kind": "rin", "pos": [120, 290], "weapon": "rifle", "pose": "idle"},
		{"do": "actor", "id": "k", "portrait": "res://art/portraits/old_k.png", "pos": [260, 290], "facing": -1},
		{"do": "move", "id": "rin", "to": [200, 290], "time": 0.2, "pose": "walk", "wait": true},
		{"do": "face", "id": "rin", "dir": -1},
		{"do": "pose", "id": "rin", "pose": "crouch"},
		{"do": "say", "speaker": "rin", "text": "多少。", "auto": 0.05},
		{"do": "say", "speaker": "old_k", "text": "你鞋帶散了。", "style": "whisper", "auto": 0.05},
		{"do": "fx", "kind": "shake", "strength": 3, "time": 0.1},
		{"do": "fx", "kind": "flash", "time": 0.1},
		{"do": "fx", "kind": "noise", "time": 0.1},
		{"do": "fx", "kind": "tint", "color": "#ff0033", "alpha": 0.2, "time": 0.1},
		{"do": "sfx", "id": "ui_confirm"},
		{"do": "narrate", "lines": ["凌晨 3 點 12 分起暫停降雨"], "time": 0.1},
		{"do": "title", "text": "第一章　雨夜", "sub": "沉港市", "time": 0.1},
		{"do": "remove", "id": "k"},
		{"do": "wait", "time": 0.1},
		{"do": "fade", "to": 1.0, "time": 0.1},
	],
}

var _finished_ids: Array[StringName] = []
## 演出結束時已執行的步驟數（播放器結束後就釋放了，所以在結束訊號裡記下來）。
var _steps_done: Dictionary[StringName, int] = {}


func run() -> void:
	_test_checker()
	_test_stages()
	await _test_play_all_steps()
	await _test_skip()
	await _test_broken_data()
	await _test_pause_restored()
	await _test_story_integration()
	await _test_overlay_and_layers()
	_test_real_data()


func _speakers() -> Dictionary:
	return {"rin": {}, "old_k": {}}


func _test_checker() -> void:
	check(CutsceneChecker.validate("good", GOOD_SCENE, _speakers()).is_empty(), "正常的演出資料通過檢查")
	var bad := {"steps": [
		{"do": "actor", "id": "x", "kind": "rin", "pos": [0, 0]},
		{"do": "scene", "id": "no_such_stage"},
		{"do": "move", "id": "ghost", "to": [1, 1]},
		{"do": "say", "speaker": "nobody", "text": "a"},
		{"do": "say", "speaker": "rin", "text": "b", "style": "weird"},
		{"do": "say", "speaker": "rin", "text": "c"},
		{"do": "say", "speaker": "rin", "text": "d"},
		{"do": "fx", "kind": "nope"},
		{"do": "sfx", "id": "no_such_sfx"},
		{"do": "transition", "kind": "spin"},
		{"do": "dance"},
		{"do": "wait"},
	]}
	var joined := "\n".join(CutsceneChecker.validate("bad", bad, _speakers()))
	for needle in ["之前沒有指定場景", "no_such_stage", "ghost", "nobody", "weird", "連續超過", "nope", "no_such_sfx", "spin", "dance", "time"]:
		check(joined.contains(needle), "檢查工具能指出問題：%s" % needle)
	var long_text := {"steps": [{"do": "scene", "id": "test_room"}, {"do": "say", "speaker": "rin", "text": "字".repeat(60)}]}
	check(not CutsceneChecker.validate("long", long_text, _speakers()).is_empty(), "台詞太長會被指出")
	var too_many: Array = [{"do": "scene", "id": "test_room"}]
	for i in 18:
		too_many.append({"do": "say", "speaker": "rin", "text": "好"})
		too_many.append({"do": "wait", "time": 0.1})
	check("\n".join(CutsceneChecker.validate("many", {"steps": too_many}, _speakers())).contains("上限 16"), "台詞總數超過 16 句會被指出")
	check(not CutsceneChecker.validate("empty", {"steps": []}, _speakers()).is_empty(), "沒有步驟會被指出")


func _test_stages() -> void:
	var ids := StageLibrary.ids()
	check(ids.size() >= 2, "舞台庫有場景（%d）" % ids.size())
	for id in ids:
		check(StageLibrary.validate(id).is_empty(), "舞台 %s 通過檢查" % id)
	var stage := StageLibrary.build(&"test_room")
	check(stage.back.get_child_count() > 0 and stage.front.get_child_count() > 0, "舞台分成後層與前層")
	stage.free()
	var broken := StageLayers.create({"kind": "gradient"}, "test_bad_cutscene 圖層")
	check(broken == null, "缺欄位的圖層回傳 null 而不是崩潰")
	check(StageLayers.create({"kind": "nonsense"}, "test_bad_cutscene 圖層") == null, "未知圖層種類回傳 null")


func _play(id: StringName, scene: Dictionary, speed := 40.0) -> CutscenePlayer:
	var player := CutscenePlayer.new()
	player.speed = speed
	runner.add_child(player)
	player.finished.connect(func(done: StringName) -> void:
		_steps_done[done] = player.steps_run
		_finished_ids.append(done))
	player.play(id, scene)
	return player


func _wait_finished(id: StringName, max_frames := 900) -> bool:
	for i in max_frames:
		if _finished_ids.has(id):
			return true
		await runner.get_tree().process_frame
	return _finished_ids.has(id)


func _test_play_all_steps() -> void:
	_finished_ids.clear()
	var player := _play(&"test_all_steps", GOOD_SCENE)
	await frames(3)
	check(runner.get_tree().paused, "演出時遊戲暫停")
	check(await _wait_finished(&"test_all_steps"), "包含所有步驟的演出能播完")
	var done_count: int = _steps_done.get(&"test_all_steps", -1)
	check(done_count == GOOD_SCENE["steps"].size(), "每個步驟都執行了（%d / %d）" % [done_count, GOOD_SCENE["steps"].size()])
	await frames(2)
	check(not is_instance_valid(player), "演出結束後播放器釋放")
	check(not runner.get_tree().paused, "演出結束後還原成未暫停")


func _test_skip() -> void:
	_finished_ids.clear()
	var scene := {"steps": [{"do": "scene", "id": "test_room"}, {"do": "wait", "time": 30.0}, {"do": "wait", "time": 30.0}]}
	var player := _play(&"test_skip", scene, 1.0)
	await runner.get_tree().create_timer(0.3).timeout
	check(not _finished_ids.has(&"test_skip"), "長演出還在播放")
	player.skip()
	check(await _wait_finished(&"test_skip", 60), "跳過後立刻結束")
	check(not runner.get_tree().paused, "跳過後遊戲恢復")


func _test_broken_data() -> void:
	_finished_ids.clear()
	var scene := {"steps": [
		{"do": "move", "id": "ghost", "to": [1, 1]},
		{"do": "scene", "id": "no_such_stage"},
		{"do": "scene", "id": "test_room"},
		{"do": "actor", "id": "bad", "kind": "no_such_character", "pos": [10, 10]},
		{"do": "dance"},
		"not a dictionary",
		{"do": "fx", "kind": "tint"},
		{"do": "transition", "kind": "spin"},
		{"do": "wait", "time": 0.05},
	]}
	var player := _play(&"test_bad_cutscene", scene)
	check(await _wait_finished(&"test_bad_cutscene"), "資料損毀的演出略過壞步驟後仍然結束")
	check(int(_steps_done.get(&"test_bad_cutscene", 0)) >= 2, "好的步驟照常執行")


func _test_pause_restored() -> void:
	_finished_ids.clear()
	runner.get_tree().paused = true
	var player := _play(&"test_pause_kept", {"steps": [{"do": "scene", "id": "test_room"}, {"do": "wait", "time": 0.05}]})
	check(await _wait_finished(&"test_pause_kept"), "演出播完")
	check(runner.get_tree().paused, "演出前就暫停時，演出後仍然暫停")
	runner.get_tree().paused = false
	await frames(2)


func _test_story_integration() -> void:
	var previous_auto := Story.auto_skip
	Story.auto_skip = false
	Story._scenes["test_anim_scene"] = {"mode": "animated", "steps": [{"do": "scene", "id": "test_room", "fade": 0.05}, {"do": "wait", "time": 0.05}]}
	var modes: Array[StringName] = []
	var on_started := func(id: StringName, mode: StringName) -> void:
		if id == &"test_anim_scene":
			modes.append(mode)
	Story.scene_started.connect(on_started)
	var player_done := [false]
	Story.scene_finished.connect(func(id: StringName) -> void:
		if id == &"test_anim_scene":
			player_done[0] = true, CONNECT_ONE_SHOT)
	check(Story.play(&"test_anim_scene", false), "Story 可以播放動畫場景")
	check(Story.is_cinematic_active(), "動畫場景視為過場（暫停遊戲、排隊）")
	if Story._player != null:
		Story._player.speed = 40.0
	for i in 600:
		if player_done[0]:
			break
		await runner.get_tree().process_frame
	check(player_done[0], "動畫場景播完後發出結束訊號")
	check(modes.has(Story.MODE_ANIMATED), "開始訊號標示為動畫模式")
	check(not Story.is_cinematic_active(), "播完後不再是過場狀態")

	# 設定「略過過場動畫」時直接結束。
	Settings.set_skip_cutscenes(true)
	player_done[0] = false
	Story.scene_finished.connect(func(id: StringName) -> void:
		if id == &"test_anim_scene":
			player_done[0] = true, CONNECT_ONE_SHOT)
	Story.play(&"test_anim_scene", false)
	await frames(3)
	check(player_done[0], "開啟略過設定後動畫場景立刻結束")
	Settings.set_skip_cutscenes(false)
	Story.scene_started.disconnect(on_started)
	Story._scenes.erase("test_anim_scene")
	Story.auto_skip = previous_auto


func _test_real_data() -> void:
	check(Story.validate().is_empty(), "所有章節劇本（含動畫場景）通過檢查")


## 疊加演出（直接蓋在遊戲畫面上）、數字計數器、道具貼圖的自發光層。
func _test_overlay_and_layers() -> void:
	_finished_ids.clear()
	var overlay := {"overlay": true, "steps": [{"do": "fx", "kind": "noise", "time": 0.1}, {"do": "wait", "time": 0.1}]}
	check(CutsceneChecker.validate("overlay", overlay, _speakers()).is_empty(), "疊加演出不需要舞台也能通過檢查")
	var player := _play(&"test_overlay", overlay, 1.0)
	await frames(2)
	var backdrop := player._root.get_child(0) as ColorRect
	check(backdrop.color.a == 0.0 and player._fade.color.a == 0.0, "疊加演出不蓋黑底，遊戲畫面看得到")
	player.speed = 40.0
	check(await _wait_finished(&"test_overlay"), "疊加演出播完")

	var counter := StageLayers.create({"kind": "counter", "pos": [0, 0], "from": 10, "to": 20, "time": 1.0}, "test counter")
	check(counter != null and counter.call("current") == 10, "計數器從起始值開始")
	counter.call("_process", 0.5)
	check(counter.call("current") == 15, "計數器隨時間往上數")
	counter.call("_process", 5.0)
	check(counter.call("current") == 20, "計數器停在終點")
	counter.free()

	var sprite := StageLayers.create({"kind": "sprite", "path": "res://art/environment/props/window_rain.png", "pos": [0, 0], "scale": 0.5}, "test sprite")
	check(sprite != null and sprite.get_child_count() == 1, "道具貼圖附帶自發光層")
	sprite.free()
	var plain := StageLayers.create({"kind": "sprite", "path": "res://art/environment/props/trash_can.png", "pos": [0, 0]}, "test sprite")
	check(plain != null and plain.get_child_count() == 0, "沒有自發光層的道具不加多餘節點")
	plain.free()
