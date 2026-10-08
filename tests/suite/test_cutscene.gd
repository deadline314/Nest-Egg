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
	await _test_story_features()
	_test_checker()
	_test_stages()
	await _test_play_all_steps()
	await _test_skip()
	await _test_broken_data()
	await _test_pause_restored()
	await _test_story_integration()
	await _test_overlay_and_layers()
	await _test_stand_up_returns_to_the_floor()
	await _test_lock_lifecycle()
	await _test_gameplay_input_lock()
	await _test_skip_covered_transition()
	_test_real_data()


## 坐在桌上、箱子上的演員站起來時，腳要落回舞台的地面線，不能留在座位的高度浮空（NE-214）。
func _test_stand_up_returns_to_the_floor() -> void:
	var actor := CutsceneActor.new()
	runner.add_child(actor)
	check(actor.setup(&"t", "rin", "", 1.0, ""), "an actor with a skeleton is built")
	actor.ground_y = 280.0
	actor.position = Vector2(100, 232.0)  # 坐在離地 48 像素的檢查台上
	actor.set_pose(&"sit")
	await frames(3)
	check(is_equal_approx(actor.position.y, 232.0), "sitting keeps the seat height")
	actor.set_pose(&"idle")
	for i in 90:
		await runner.get_tree().process_frame
	check(is_equal_approx(actor.position.y, 280.0), "standing up puts the feet back on the floor line (%.1f)" % actor.position.y)
	var free_actor := CutsceneActor.new()
	runner.add_child(free_actor)
	free_actor.setup(&"u", "rin", "", 1.0, "")
	free_actor.position = Vector2(50, 200.0)
	free_actor.set_pose(&"sit")
	free_actor.set_pose(&"idle")
	await frames(3)
	check(is_equal_approx(free_actor.position.y, 200.0), "an actor without a registered floor stays where the scene put it")
	actor.queue_free()
	free_actor.queue_free()
	await frames(2)


func _test_lock_lifecycle() -> void:
	var tree := runner.get_tree()
	var mouse_mode := Input.mouse_mode
	tree.paused = false
	var first := Node.new()
	var second := Node.new()
	runner.add_child(first)
	runner.add_child(second)
	var token := GameplayLock.acquire(first, Input.MOUSE_MODE_HIDDEN)
	var other := GameplayLock.acquire(second, Input.MOUSE_MODE_VISIBLE)
	GameplayLock.release(token)
	GameplayLock.release(token)
	check(tree.paused and GameplayLock.is_locked() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "重複釋放不影響其他演出與游標")
	second.queue_free()
	await frames(2)
	check(not tree.paused and not GameplayLock.is_locked() and Input.mouse_mode == mouse_mode, "owner 中途刪除自動回收最後一把鎖並還原游標")
	GameplayLock.release(other)
	first.queue_free()
	# 目的畫面解除舊選單的暫停，不能同時解除正在播放的演出。
	tree.paused = true
	var owner := Node.new()
	runner.add_child(owner)
	token = GameplayLock.acquire(owner)
	GameplayLock.set_base_paused(false)
	UiKit.set_cursor_visible(false)
	check(tree.paused, "換畫面更新基礎暫停仍保留演出鎖")
	GameplayLock.release(token)
	check(not tree.paused, "最後演出結束使用目的畫面的暫停狀態")
	# headless DisplayServer 的 mouse_mode 永遠回傳 VISIBLE；仍驗證保存的目的畫面需求。
	check(GameplayLock._base_mouse_mode == Input.MOUSE_MODE_HIDDEN and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_HIDDEN), "轉場結束保留目的關卡的隱藏游標，不還原主選單游標")
	GameplayLock.set_base_mouse_mode(mouse_mode)
	owner.queue_free()
	# 真正的播放器中途刪除也能還原。
	var cinematic := _play(&"test_deleted", {"overlay": true, "steps": [{"do": "wait", "time": 30.0}]}, 1.0)
	await frames(2)
	cinematic.queue_free()
	await frames(2)
	check(not tree.paused and not GameplayLock.is_locked(), "播放器中途刪除不留下暫停或輸入鎖")
	# 阻擋式章節卡必須保留原本的手動暫停。
	tree.paused = true
	var card := ChapterCard.new()
	card.block = true
	runner.add_child(card)
	card._done()
	check(tree.paused and not GameplayLock.is_locked(), "章末卡結束保留原本手動暫停")
	tree.paused = false
	await frames(2)


## 用真正的玩家、音效訊號與輸入事件驗證，包含每影格輪詢及 ALWAYS 節點。
func _test_gameplay_input_lock() -> void:
	var level := await start_level(PropsSuite.level_data())
	var player := level.player
	await physics_frames(10)
	var sounds: Array[StringName] = []
	var on_sound := func(id: StringName) -> void: sounds.append(id)
	Sfx.sound_played.connect(on_sound)
	player._jump_buffer_left = 0.1
	player._dash_buffer_left = 0.1
	player._melee_buffer_left = 0.1
	var cinematic := _play(&"test_input_lock", {"overlay": true, "steps": [{"do": "wait", "time": 30.0}]}, 1.0)
	check(player._jump_buffer_left == 0.0 and player._dash_buffer_left == 0.0 and player._melee_buffer_left == 0.0, "過場開始清除玩家動作緩衝")
	var before := player.global_position
	var mag := player.loadout.mag_in(player.loadout.active_slot)
	var fire_sound := player.loadout.active_weapon().fire_sound
	var old_mode := player.process_mode
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	Input.action_press(&"move_right")
	await physics_frames(12)
	check(player.global_position == before and player.loadout.mag_in(player.loadout.active_slot) == mag, "過場中的左鍵與移動輸入不能移動或消耗彈藥")
	check(not sounds.has(fire_sound), "過場點擊不會播放玩家開槍聲")
	var reload_event := InputEventAction.new()
	reload_event.action = &"reload"
	reload_event.pressed = true
	player._unhandled_input(reload_event)
	check(not player.loadout.is_reloading(), "過場事件輸入不能換彈")
	level._pause_menu.open()
	level._inventory.open()
	DevMenu.open()
	check(not level._pause_menu._root.visible and not level._inventory.is_open() and not DevMenu.is_open, "過場阻擋暫停、背包與開發選單")
	var done := [false]
	cinematic.finished.connect(func(_id: StringName) -> void: done[0] = true)
	cinematic.skip()
	for i in 60:
		if done[0]:
			break
		await runner.get_tree().process_frame
	check(done[0] and not runner.get_tree().paused and not GameplayLock.is_locked(), "過場結束當下恢復遊戲")
	await physics_frames(3)
	check(player.loadout.mag_in(player.loadout.active_slot) == mag and not sounds.has(fire_sound), "過場最後的點擊不會在恢復後補開槍")
	player.process_mode = old_mode
	Input.action_press(&"move_right")
	await physics_frames(8)
	Input.action_release(&"move_right")
	check(player.global_position.x > before.x, "過場後不按 Esc 就能正常移動")
	Input.action_press(&"shoot")
	await physics_frames(2)
	Input.action_release(&"shoot")
	check(player.loadout.mag_in(player.loadout.active_slot) < mag and sounds.has(fire_sound), "恢復後重新按射擊仍能正常開槍")
	Sfx.sound_played.disconnect(on_sound)
	await end_level(level)


func _test_skip_covered_transition() -> void:
	var instant := Transition.instant
	Transition.instant = false
	var cinematic := _play(&"test_skip_covered", {"overlay": true, "steps": [
		{"do": "transition", "kind": "fade", "mode": "cover", "time": 0.03},
		{"do": "wait", "time": 30.0},
		{"do": "transition", "kind": "fade", "mode": "reveal", "time": 0.03},
	]}, 1.0)
	for i in 120:
		if Transition.is_active() and Transition._rect.visible:
			break
		await runner.get_tree().process_frame
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	check(await _wait_finished(&"test_skip_covered", 120), "Esc 能跳過包含轉場的演出")
	check(not Transition.is_active() and not runner.get_tree().paused and not GameplayLock.is_locked(), "跳過演出會清掉它的轉場，不留下黑畫面或暫停")
	Transition.instant = instant


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
	# 窗光閃爍（life）只能用在小面積的層：整張背景開了它會變成一格一格忽明忽暗的方塊。
	var scene_art := "res://art/environment/scenes/pawnshop_front.webp"
	check(StageLibrary.life_covers_stage({"path": scene_art, "scale": 0.5, "life": true}), "整張背景開 life 會被抓到")
	check(not StageLibrary.life_covers_stage({"path": scene_art, "scale": 0.5}), "沒開 life 的背景沒有問題")
	check(not StageLibrary.life_covers_stage({"path": scene_art, "scale": 0.1, "life": true}), "小面積的層可以開 life")
	for stage_id in ["ch1_pawnshop_front", "ch1_dawn_noodle_stall", "ch1_revival_room", "rainy_harbor", "elevator_rise"]:
		check(StageLibrary.validate(StringName(stage_id)).is_empty(), "舞台 %s 通過檢查：%s" % [stage_id, StageLibrary.validate(StringName(stage_id))])


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

	var motes := StageLayers.create({"kind": "motes", "count": 12, "area": [10, 20, 100, 50]}, "test motes")
	check(motes != null and motes.get("_points").size() == 12, "塵粒圖層建立固定數量的粒子")
	motes.call("_process", 30.0)
	var inside := true
	for point: Vector2 in motes.get("_points"):
		inside = inside and point.x >= 0.0 and point.x <= 100.0 and point.y >= 0.0 and point.y <= 50.0
	check(inside, "塵粒漂移後仍在指定範圍內（循環使用，不配置新物件）")
	motes.free()
	var pulsing := StageLayers.create({"kind": "glow", "pos": [0, 0], "radius": 20, "color": "#ff3322", "pulse": 1.0, "pulse_depth": 0.8}, "test pulse")
	var bright: float = pulsing.self_modulate.r
	pulsing.call("_process", 0.25)
	check(pulsing.self_modulate.r < bright * 0.5, "脈動的柔光在週期的一半暗下來")
	pulsing.free()

	var sprite := StageLayers.create({"kind": "sprite", "path": "res://art/environment/props/window_rain.png", "pos": [0, 0], "scale": 0.5}, "test sprite")
	check(sprite != null and sprite.get_child_count() == 1, "道具貼圖附帶自發光層")
	sprite.free()
	var plain := StageLayers.create({"kind": "sprite", "path": "res://art/environment/props/trash_can.png", "pos": [0, 0]}, "test sprite")
	check(plain != null and plain.get_child_count() == 0, "沒有自發光層的道具不加多餘節點")
	plain.free()


func _test_story_features() -> void:
	var previous_auto := Story.auto_skip
	var previous_flags := GameState.world_flags.duplicate(true)
	var previous_defaults := GameState.flag_defaults.duplicate(true)
	var previous_items := StoryItems.snapshot()
	var previous_seen := Story.progress_snapshot()
	var previous_sequences := Story._death_sequences.duplicate(true)
	check(Story.load_chapter("res://tests/fixtures/story_features.json"), "ST-3 fixture loads through the chapter API")
	for entry in [[false, false], [true, true], [0, false], [2, true], [0.0, false], [-0.5, true], ["", false], ["ask", true]]:
		GameState.set_flag(&"test_story_route", entry[0])
		check(GameState.has_flag(&"test_story_route") == entry[1], "native story truth handles scalar %s" % str(entry[0]))
		check(StoryRules.eligible({"requires_flag": "test_story_route"}, GameState.has_flag, StoryItems.owns) == entry[1], "branch prerequisites use the same scalar truth")
	GameState.set_flag(&"test_story_route", "")
	var scene: Dictionary = Story._scenes["test_story_choice"]
	check(CutsceneChecker.validate("test_story_choice", scene, Story._speakers).is_empty(), "choice and inline branches validate")
	Story.auto_skip = false
	var player := CutscenePlayer.new()
	runner.add_child(player)
	player.speed = 100.0
	player.play(&"test_story_choice", scene)
	for i in 90:
		if player.choice_active():
			break
		await frames(1)
	check(not Story.progress_snapshot().has(&"test_story_choice"), "unfinished scenes are excluded from serialized seen records")
	check(player.choice_active() and runner.get_tree().paused, "a choice waits for real input while gameplay is locked")
	check((player._choice.get_child(1) as Button).has_focus(), "the first choice starts with keyboard/controller focus")
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	Input.parse_input_event(accept)
	Input.flush_buffered_events()
	await runner.get_tree().process_frame
	accept = InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = false
	Input.parse_input_event(accept)
	Input.flush_buffered_events()
	await runner.get_tree().process_frame
	check(GameState.has_flag(&"test_story_decision"), "native confirm input selects the focused ask option")
	check(GameState.has_flag(&"test_story_decision"), "selection records its flag")
	for i in 90:
		if not is_instance_valid(player):
			break
		await frames(1)
	check(not runner.get_tree().paused, "a chosen branch finishes and releases gameplay")
	player = CutscenePlayer.new()
	runner.add_child(player)
	player.speed = 100.0
	player.play(&"test_story_choice", scene)
	for i in 90:
		if player.choice_active():
			break
		await frames(1)
	check(player.choose(1), "the leave option can be selected")
	check(not GameState.has_flag(&"test_story_decision"), "the alternative choice writes false rather than another true flag")
	player.skip()
	for i in 90:
		if not is_instance_valid(player):
			break
		await frames(1)
	Story.auto_skip = true
	Story.apply_default_choices(scene)
	check(not GameState.has_flag(&"test_story_decision"), "skipping resolves an unanswered choice using the declared default")
	StoryItems.acquire(&"doc_crayon_drawing", false)
	check(StoryRules.eligible({"requires_item": "doc_crayon_drawing"}, GameState.has_flag, StoryItems.owns), "later story conditions inspect the existing inventory")
	check(not StoryRules.eligible({"requires_item": "missing_item"}, GameState.has_flag, StoryItems.owns), "missing story items cannot satisfy a condition")
	Story._seen[&"test_story_object"] = true
	Story._completed[&"test_story_object"] = true
	GameState.set_flag(&"test_story_visits", 2)
	GameState.set_flag(&"test_story_route", "ask")
	check(GameState.save_story_progress("user://test_story_progress.json"), "story flags, items and completed interactions save to disk")
	GameState.world_flags.clear()
	StoryItems._owned.clear()
	Story._seen.clear()
	check(GameState.load_story_progress("user://test_story_progress.json"), "saved story progress can be reopened")
	check(GameState.get_flag(&"test_story_visits") == 2 and Story.was_seen(&"test_story_object") and StoryItems.owns(&"doc_crayon_drawing"), "disk roundtrip retains numbers, seen objects and story items")
	check(GameState.get_flag(&"test_story_route") == "ask" and GameState.has_flag(&"test_story_route"), "string route survives disk restore and remains usable as a condition")
	var broken_file := FileAccess.open("user://test_story_progress.json", FileAccess.WRITE)
	broken_file.store_string("{ broken JSON")
	broken_file.close()
	check(not GameState.load_story_progress("user://test_story_progress.json"), "invalid JSON reports its file and line and restores safe defaults")
	GameState.restore_story_progress({"flags": {"test_story_visits": []}}, "test_bad_cutscene/save")
	check(GameState.get_flag(&"test_story_visits") == 0 and GameState.get_flag(&"test_story_decision") == false, "missing or corrupted flags restore declared defaults")
	check(GameState.get_flag(&"test_story_route") == "" and not GameState.has_flag(&"test_story_route"), "missing string route restores an empty, false default")
	var npc := NpcData.new()
	npc.id = &"test_object"
	npc.display_name = "測試物件"
	npc.kind = NpcData.Kind.OBJECT
	var talk := NpcTalk.new()
	talk.scene = &"test_story_object"
	talk.once = true
	talk.story_item = StoryItems.find(&"old_k_order")
	npc.talks = [talk]
	check(npc.validate().is_empty(), "an investigation can award an ordinary story item using existing NpcTalk data")
	check(npc.pick_talk(0, func(_id: StringName) -> bool: return false) == 0 and npc.pick_talk(0, func(_id: StringName) -> bool: return true) == -1, "a once-only investigation cannot be counted twice")
	talk.requires_item = &"doc_crayon_drawing"
	check(npc.pick_talk(0, func(_id: StringName) -> bool: return false, 0, GameState.has_flag, func(_id: StringName) -> bool: return false) == -1, "investigation item requirements block unavailable lines")
	check(not Story.validate_death_sequences("test", [{"steps": [{"kind": "unknown", "time": []}]}]).is_empty(), "startup validation catches malformed death sequence positions")
	var first := Story.death_sequence(&"ch1_kasa", 1)
	var second := Story.death_sequence(&"ch1_kasa", 2)
	var third := Story.death_sequence(&"ch1_kasa", 3)
	check(first.steps.size() == 4 and second.steps.size() == 2 and third.skippable, "first death is complete, second is shorter, third is skippable")
	var screen := DeathScreen.new()
	screen.sequence = first
	screen.setup({"title": "記憶卡", "text": "測試記憶。"}, true)
	runner.add_child(screen)
	check(screen.sequence_index == 0, "death sequence starts with the first line")
	for i in 240:
		if screen.sequence_complete:
			break
		await frames(1)
	check(screen.sequence_complete and screen.sequence_index == 3, "death sequence reaches the memory card in order")
	screen.queue_free()
	await frames(2)
	var table := ContinuityAudit.flag_table({"test": scene}, {}, {})
	check(table.has("test_story_route") and table.test_story_route.writes.size() == 2 and table.test_story_route.reads.size() == 1, "continuity audit reads both string-route writes and the branch condition")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_story_progress.json"))
	Story._scenes.erase("test_story_choice")
	Story._scenes.erase("test_story_object")
	Story._scene_chapter.erase("test_story_choice")
	Story._scene_chapter.erase("test_story_object")
	Story._death_sequences = previous_sequences
	GameState.flag_defaults = previous_defaults
	GameState.world_flags = previous_flags
	StoryItems.restore(previous_items)
	Story.restore_progress(previous_seen)
	Story.auto_skip = previous_auto
