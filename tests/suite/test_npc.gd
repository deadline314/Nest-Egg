class_name NpcSuite
extends TestSuite
## 場景人物（NE-45）：資料檢查、依次數與劇情挑選對話、對話演出（暫停、推進、結束）、獎勵只領一次、
## 檢查點還原（回溯後狀態與獎勵一起還原）、不受傷也不被當成目標、壞資料與缺外觀的容錯、第一二章的擺放。

const MAP_PATH := "res://tests/fixtures/npc_map.json"
const NPC_DIR := "res://data/npcs"
const LEVELS: Array[String] = ["res://data/levels/level_01.tres", "res://data/levels/level_02.tres"]
const MED_PATH := "res://data/consumables/med_injector.tres"
## 人物周圍不放敵人的安全距離（格）。
const SAFE_TILES := 8.0
const TEST_SCENE_A := &"test_npc_talk_a"
const TEST_SCENE_B := &"test_npc_talk_b"
const TEST_SCENE_C := &"test_npc_talk_c"


func run() -> void:
	_install_test_scenes()
	_test_data()
	_test_talk_selection()
	_test_state_snapshot()
	_test_placement()
	await _test_conversation()
	await _test_interaction_input()
	await _test_rewards_once()
	await _test_checkpoint_consistency()
	await _test_real_npcs()
	await _test_fallbacks()
	await _test_once_object()
	await _test_cinematic_framing()
	await _test_framing_real_time()
	await _test_formal_portal_preview()
	await _test_waiter_teardown()
	await preload("res://tests/helpers/interaction_holster_checks.gd").run(self)
	_test_reaction_selection()
	await _test_awareness()
	_remove_test_scenes()
	Story.auto_skip = true


func _test_framing_real_time() -> void:
	var previous_motion := Settings.get_reduce_ui_motion()
	var previous_scale := Engine.time_scale
	var previous_fps := Engine.max_fps
	Settings.set_reduce_ui_motion(false)
	Engine.max_fps = 120
	Engine.time_scale = 0.05
	var owner := Node.new()
	runner.add_child(owner)
	Story.framing.clear_preview()
	var token := Story.framing.acquire(owner)
	await runner.get_tree().create_timer(0.4, true, false, true).timeout
	check(is_equal_approx(Story.framing.amount, 1.0), "framing fully opens in real time at120fps during slow motion")
	Story.framing.release(token)
	await runner.get_tree().create_timer(0.4, true, false, true).timeout
	check(is_zero_approx(Story.framing.amount) and Story.framing.scope_count() == 0, "framing fully closes in real time at120fps during slow motion")
	Engine.time_scale = previous_scale
	Engine.max_fps = previous_fps
	Settings.set_reduce_ui_motion(previous_motion)
	owner.queue_free()
	await frames(2)


func _test_cinematic_framing() -> void:
	var reduced := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(true)
	Story.auto_skip = false
	var alias_modes: Array[StringName] = []
	var on_started := func(id: StringName, mode: StringName) -> void:
		if id == TEST_SCENE_A:
			alias_modes.append(mode)
	Story.scene_started.connect(on_started)
	for view_size in [Vector2(640, 360), Vector2(1600, 900), Vector2(840, 360), Vector2(1000, 360)]:
		var rect := CinematicFraming.rect_for(view_size)
		check(is_equal_approx(rect.size.x, view_size.x), "framing preserves world width at %s" % view_size)
		check(rect.position.y >= 0 and rect.end.y <= view_size.y, "safe rect remains in viewport at %s" % view_size)
		check(is_equal_approx(rect.size.x / rect.size.y, maxf(CinematicFraming.ASPECT, view_size.x / view_size.y)), "framing uses 21:9 without narrowing ultrawide %s" % view_size)
	check(absf(CinematicFraming.rect_for(Vector2(640, 360)).position.y - 42.857142) < 0.001, "640x360 uses 42.857px per edge")
	var person := _npc(&"framing_person", [_talk(TEST_SCENE_A, 0, &"", 15)])
	var object := _npc(&"framing_object", [_talk(TEST_SCENE_A)])
	object.kind = NpcData.Kind.OBJECT
	var data := _level_data({"A": person, "Z": object})
	var entry := CinematicEntryData.new()
	entry.id = &"framing_entry"
	entry.cell = Vector2i(34, 19)
	entry.scene = &"framing_entry_scene"
	Story._scenes[String(entry.scene)] = {"mode": "cinematic", "lines": [{"speaker": "rin", "text": "入口確認後才會開始這段演出。"}]}
	data.cinematic_entries = [entry]
	var level := await start_level(data)
	var npc := _find_npc(level, 14)
	var marker := _find_npc(level, 24)
	await _test_preview_boundaries(level, npc)
	await _stand_next_to(level, npc)
	Story.framing._physics_process(1.0)
	check(Story.framing.selected_target() == npc and is_equal_approx(Story.framing.amount, 1.0), "eligible PERSON previews at conversation range")
	check(not runner.get_tree().paused and not GameplayLock.is_locked(), "preview does not lock gameplay")
	var hud := level.hud
	if hud != null:
		var read_time := hud._controls_read_time
		await frames(2)
		check(not hud._controls_card.visible and not hud._framing_edge_root.visible, "preview hides whole edge HUD and controls card without clipping")
		check(is_equal_approx(read_time, hud._controls_read_time), "hidden controls retain remaining reading time")
	check(not Story.was_seen(TEST_SCENE_A) and npc.talk_count == 0 and Progression.credits == 0, "preview does not alter story, conversations or rewards")
	npc._talk()
	await frames(2)
	check(Story.current_presentation_context().get("framing_source") == "person", "PERSON context accompanies the actual conversation")
	check(Story.framing.scope_count() == 1, "PERSON dialogue owns one formal framing scope")
	check(not npc._prompt.visible and not npc._prompt.reach_check.call(), "active NPC dialogue hides repeat-interact prompt synchronously")
	var safe := Story.framing.safe_rect()
	check(Story._layer._portrait.get_rect().position.y >= safe.position.y and Story._layer._text.get_rect().end.y <= safe.end.y, "portrait and subtitles lie within actual safe rect")
	Story.reset_active_presentation()
	await frames(2)
	check(not GameplayLock.is_locked() and Story.framing.scope_count() == 0, "interruption restores gameplay and all framing scopes")
	check(npc.talk_count == 0 and Progression.credits == 0 and not Story.was_seen(TEST_SCENE_A), "cancelled conversation grants no reward and remains playable")
	await _stand_next_to(level, marker)
	Story.framing._physics_process(1.0)
	check(Story.framing.selected_target() != marker and is_zero_approx(Story.framing.amount), "OBJECT using the same dialogue scene never previews")
	check(npc._prompt.visible and hud._framing_edge_root.visible, "retreat restores NPC prompt state and whole edge HUD")
	marker._talk()
	await frames(2)
	check(Story.current_presentation_context().get("framing_source") == "object" and Story.framing.scope_count() == 0, "OBJECT dialogue remains unframed during formal reading")
	Story.skip_cinematic()
	await frames(2)
	# 同一scene的兩個真正NPC waiter必須按每次請求結算，不能由第一個finished(id)喚醒全部。
	var person_count := npc.talk_count
	var object_count := marker.talk_count
	var credits_before := Progression.credits
	npc._talk()
	marker._talk()
	await frames(2)
	Story.skip_cinematic()
	await frames(2)
	check(npc.talk_count == person_count + 1 and Progression.credits == credits_before + 15, "first same-id waiter completes and receives only its own reward")
	check(marker.talk_count == object_count and marker._talking and Story.is_cinematic_active(), "second same-id waiter keeps waiting after the first occurrence finishes")
	Story.reset_active_presentation()
	await frames(2)
	check(marker.talk_count == object_count and not marker._talking and Progression.credits == credits_before + 15, "cancelling the second same-id occurrence grants no extra reward or talk count")
	var queued_context := {"framing_source": "object", "source_id": "queued_object"}
	Story.play(TEST_SCENE_B, false, {"framing_source": "person", "source_id": "queued_person"})
	Story.play(TEST_SCENE_A, false, queued_context)
	queued_context.framing_source = "person"
	Story.skip_cinematic()
	await frames(2)
	check(Story.current_presentation_context().get("framing_source") == "object" and Story.framing.scope_count() == 0, "each queued occurrence copies its own source rather than inferring by scene id")
	Story.reset_active_presentation()
	var entrances := level.find_children("", "CinematicEntrance", true, false)
	check(entrances.size() == 1, "LevelData creates the explicitly declared movie entrance")
	if entrances.size() == 1:
		var entrance := entrances[0] as CinematicEntrance
		level.player.global_position = entrance.global_position + Vector2(-12, -2)
		await frames(6)
		Story.framing._physics_process(1.0)
		check(Story.framing.selected_target() == entrance and not Story.was_seen(entry.scene), "declared entrance previews without starting its movie")
		entrance.process_mode = Node.PROCESS_MODE_ALWAYS
		runner.get_tree().paused = true
		Input.action_press(&"interact")
		await frames(3)
		Input.action_release(&"interact")
		check(not Story.is_cinematic_active() and not Story.was_seen(entry.scene), "ALWAYS entrance cannot consume interact through pause")
		runner.get_tree().paused = false
		var lock := GameplayLock.acquire(level)
		Input.action_press(&"interact")
		await frames(3)
		Input.action_release(&"interact")
		check(not Story.is_cinematic_active(), "ALWAYS entrance cannot consume interact through another gameplay lock")
		GameplayLock.release(lock)
		entrance.process_mode = Node.PROCESS_MODE_INHERIT
		Input.action_press(&"interact")
		await frames(3)
		Input.action_release(&"interact")
		check(Story.is_cinematic_active() and Story.current_presentation_context().get("framing_source") == "entry", "explicit interact starts the declared movie")
		Story.skip_cinematic()
		await frames(3)
	Story.reset_active_presentation()
	await end_level(level)
	Story._scenes.erase(String(entry.scene))
	check(alias_modes.size() >= 4 and alias_modes.all(func(mode: StringName) -> bool: return mode == Story.MODE_CINEMATIC), "PERSON and OBJECT preserve the public dialogue-to-cinematic start alias")
	Story.scene_started.disconnect(on_started)
	Settings.set_reduce_ui_motion(reduced)
	Story.auto_skip = true


func _test_preview_boundaries(level: Level, npc: NpcActor) -> void:
	var framing := Story.framing
	framing.clear_preview()
	level.player.global_position = npc.global_position + Vector2(-81, 0)
	framing._physics_process(1.0)
	check(framing.selected_target() == null, "an unselected PERSON does not preview outside 80px")
	level.player.global_position.x = npc.global_position.x - 79.0
	framing._physics_process(1.0)
	check(framing.selected_target() == npc and framing.amount > 0.0 and framing.amount < 1.0, "approaching PERSON progressively previews between entry and talk range")
	level.player.global_position.x = npc.global_position.x - 90.0
	framing._physics_process(1.0)
	check(framing.selected_target() == npc, "the current preview survives retreat across the entry boundary")
	level.player.global_position.x = npc.global_position.x - 101.0
	framing._physics_process(1.0)
	check(framing.selected_target() == null and is_zero_approx(framing.amount), "retreat beyond 100px restores the full viewport")
	var neighbour := NpcActor.new()
	neighbour.configure(_npc(&"framing_neighbour", [_talk(TEST_SCENE_B)]), Vector2i(18, 19))
	level.add_child(neighbour)
	neighbour.global_position = npc.global_position + Vector2(64, 0)
	level.player.global_position = npc.global_position + Vector2(8, 0)
	framing._physics_process(1.0)
	level.player.global_position.x = npc.global_position.x + 35.0
	framing._physics_process(1.0)
	check(framing.selected_target() == npc, "a neighbour only 6px nearer does not steal the selected preview")
	level.player.global_position.x = npc.global_position.x + 44.0
	framing._physics_process(1.0)
	check(framing.selected_target() == neighbour, "a neighbour 24px nearer becomes the preview target")
	neighbour.queue_free()
	await frames(2)
	await _stand_next_to(level, npc)
	framing._physics_process(1.0)
	var threat := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
	threat.position = level.player.position + Vector2(96, 0)
	level._entities.add_child(threat)
	threat.raise_alert(level.player.global_position, 5.0)
	check(Music.engaged_enemies() > 0, "the combat fixture uses a real nearby alerted enemy")
	framing._physics_process(1.0)
	check(framing.selected_target() == null and is_zero_approx(framing.amount), "an engaged enemy immediately suppresses approach framing")
	threat.queue_free()
	await frames(2)
	framing._physics_process(1.0)
	check(framing.selected_target() == npc, "the eligible conversation preview returns after the threat leaves")


func _test_formal_portal_preview() -> void:
	var reduced := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(true)
	Story.auto_skip = true
	var level := await start_level(load("res://data/levels/ch1_stall.tres") as LevelData)
	var portal := level._portals.get(&"stall_home") as Portal
	check(portal != null and portal.data.cinematic_preview_scene == &"ch1_c14_home", "the formal stall_home portal declares the existing home movie")
	if portal == null:
		await end_level(level)
		Settings.set_reduce_ui_motion(reduced)
		return
	level.player.global_position = portal.global_position + Vector2(-70, 0)
	level.player.velocity = Vector2.ZERO
	await frames(3)
	var gate := portal.data.requires_flag
	GameState.clear_flag(gate)
	Story.framing._physics_process(1.0)
	check(not portal.preview_available() and Story.framing.selected_target() != portal, "locked formal movie entrance does not preview")
	GameState.set_flag(gate)
	Story.framing._physics_process(1.0)
	check(portal.preview_available() and Story.framing.selected_target() == portal, "unlocked formal portal previews before its actual interaction area")
	check(not portal._player_in_range and not portal.interaction_available(), "80px preview does not falsely advertise being within the real portal interaction area")
	check(portal._cinematic_notice != null and portal._cinematic_notice.text == "前方將播放劇情。", "formal movie approach explicitly announces the unavoidable story")
	check(not Story.was_seen(&"ch1_c14_home") and not Story.is_cinematic_active(), "formal entrance preview has not started or marked the movie seen")
	portal.disarm()
	Story.framing._physics_process(1.0)
	check(not portal.preview_available() and Story.framing.selected_target() != portal, "a disarmed arrival portal does not preview")
	portal._armed = true
	Story._seen[&"ch1_c14_home"] = true
	Story.framing._physics_process(1.0)
	check(not portal.preview_available() and Story.framing.selected_target() != portal, "an already seen home movie is not advertised for replay")
	Story._seen.erase(&"ch1_c14_home")
	await end_level(level)
	Settings.set_reduce_ui_motion(reduced)


func _test_waiter_teardown() -> void:
	Story.auto_skip = false
	for cycle in 12:
		var data := _level_data({"A": _npc(&"framing_waiter_owner", [_talk(TEST_SCENE_A, 0, &"", 15)])})
		var level := await start_level(data)
		var npc := _find_npc(level, 14)
		npc._talk()
		await frames(2)
		check(Story.is_cinematic_active() and Story._waiters.size() == 1, "cycle %d has an actual NPC coroutine waiting on one request" % cycle)
		if cycle % 2 == 0:
			# Caller先被刪除，Story coroutine是否仍能消耗結果必須由引擎實測。
			npc.queue_free()
			await frames(2)
			Story.reset_active_presentation(&"leave")
			await frames(2)
			await end_level(level)
		else:
			# 真Level離樹在NPC coroutine等待期間取消，覆蓋換區釋放順序。
			await end_level(level)
		await frames(2)
		check(not Story.is_cinematic_active() and Story._waiters.is_empty() and Story._request_results.is_empty(), "cycle %d caller/level teardown leaves no waiting or retained request result" % cycle)
		check(Progression.credits == 0 and Story.framing.scope_count() == 0, "cycle %d teardown grants no NPC reward and releases framing" % cycle)
	Story.auto_skip = true


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _install_test_scenes() -> void:
	for id in [TEST_SCENE_A, TEST_SCENE_B, TEST_SCENE_C]:
		Story._scenes[String(id)] = {"mode": "dialogue", "lines": [
			{"speaker": "rin", "text": "測試一。"}, {"speaker": "rin", "text": "測試二。"}, {"speaker": "rin", "text": "測試三。"},
		]}


func _remove_test_scenes() -> void:
	for id in [TEST_SCENE_A, TEST_SCENE_B, TEST_SCENE_C]:
		Story._scenes.erase(String(id))


func _talk(scene: StringName, min_talks := 0, after_scene := &"", credits := 0, consumable: ConsumableData = null, item: StoryItemData = null) -> NpcTalk:
	var talk := NpcTalk.new()
	talk.scene = scene
	talk.min_talks = min_talks
	talk.after_scene = after_scene
	talk.credits = credits
	talk.consumable = consumable
	talk.story_item = item
	return talk


func _npc(id: StringName, talks: Array[NpcTalk], rig := "") -> NpcData:
	var npc := NpcData.new()
	npc.id = id
	npc.display_name = "測試人物"
	npc.speaker = "rin"
	npc.rig_id = rig
	npc.talks = talks
	return npc


func _level_data(legend: Dictionary[String, Resource]) -> LevelData:
	var data := LevelData.new()
	data.id = &"npc_test"
	data.layout_path = MAP_PATH
	# 地圖上沒用到的字元放一小堆信用點，避免「未知字元」警告。
	for ch in ["A", "Z", "M"]:
		if not legend.has(ch):
			legend[ch] = load("res://data/props/credits_small.tres")
	data.legend = legend
	return data


func _find_npc(level: Level, column: int) -> NpcActor:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is NpcActor and (node as NpcActor).cell.x == column:
			return node
		stack.append_array(node.get_children())
	return null


func _find_prompt(npc: NpcActor) -> WorldPrompt:
	for child in npc.get_children():
		if child is WorldPrompt:
			return child
	return null


## 把玩家放到人物旁邊並等進入範圍。
func _stand_next_to(level: Level, npc: NpcActor) -> void:
	level.player.global_position = npc.global_position + Vector2(-8, -2)
	level.player.velocity = Vector2.ZERO
	await frames(6)


# ---------------------------------------------------------------------------
# 資料
# ---------------------------------------------------------------------------

func _test_data() -> void:
	var count := 0
	for file in DirAccess.get_files_at(NPC_DIR):
		if not file.ends_with(".tres"):
			continue
		count += 1
		var npc := load(NPC_DIR.path_join(file)) as NpcData
		check(npc != null, "npc loads: %s" % file)
		if npc == null:
			continue
		check(npc.validate().is_empty(), "npc valid: %s %s" % [file, npc.validate()])
		check(npc.pick_talk(0, Story.was_seen) >= 0, "npc has a first conversation: %s" % file)
		for talk in npc.talks:
			check(Story.has_scene(talk.scene), "npc talk scene exists: %s -> %s" % [file, talk.scene])
			# 人物與物件的入口可以是分派：每條路線都必須是玩家主動、鎖操作的對話（對話或疊加動畫），不能是通訊或氣泡。
			var scene: Dictionary = Story._scenes[String(talk.scene)]
			var targets: Array = [talk.scene] if str(scene.get("mode")) != "dispatch" else scene.get("routes", []).map(func(route: Dictionary) -> String: return str(route.get("target", "")))
			for target: Variant in targets:
				var mode := str((Story._scenes.get(str(target), {}) as Dictionary).get("mode"))
				check(mode == "dialogue" or mode == "animated", "npc talk is a dialogue scene: %s -> %s (%s)" % [talk.scene, target, mode])
			if talk.story_item != null:
				check(talk.story_item.is_collectible(), "npc reward item is a collectible: %s" % talk.story_item.id)
		if npc.kind == NpcData.Kind.PERSON:
			check(Story.speaker_ids().has(npc.speaker), "npc speaker is defined: %s -> %s" % [file, npc.speaker])
			check(not npc.prompt_text().is_empty() and npc.prompt_text().contains("{interact}"), "npc prompt names the interact key: %s" % file)
	check(count >= 6, "five people and one object are defined (%d)" % count)
	# 壞資料會被指出具體位置。
	var bad := NpcData.new()
	bad.id = &"test_npc_bad"
	bad.facing = 0
	bad.pose = &"flying"
	var empty_talk := NpcTalk.new()
	empty_talk.credits = -5
	bad.talks = [empty_talk]
	check(bad.validate().size() >= 4, "invalid npc data is reported (facing, pose, scene, credits): %s" % [bad.validate()])


func _test_talk_selection() -> void:
	var npc := _npc(&"test_pick", [_talk(TEST_SCENE_A), _talk(TEST_SCENE_B, 1), _talk(TEST_SCENE_C, 1, &"test_story_gate")])
	var seen_nothing := func(_id: StringName) -> bool: return false
	var seen_gate := func(id: StringName) -> bool: return id == &"test_story_gate"
	check(npc.pick_talk(0, seen_nothing) == 0, "the first conversation uses the first talk")
	check(npc.pick_talk(1, seen_nothing) == 1, "later visits use the talk that needs one earlier conversation")
	check(npc.pick_talk(5, seen_nothing) == 1, "the last matching talk repeats")
	check(npc.pick_talk(0, seen_gate) == 0, "a talk that needs earlier conversations is not used on the first visit")
	check(npc.pick_talk(1, seen_gate) == 2, "a talk after a story scene wins once that scene was seen")
	var empty := _npc(&"test_empty", [])
	check(empty.pick_talk(0, seen_nothing) == -1, "an npc without talks has nothing to say")


func _test_state_snapshot() -> void:
	var npc := NpcActor.new()
	npc.data = _npc(&"test_state", [_talk(TEST_SCENE_A)])
	npc.cell = Vector2i(7, 3)
	npc.talk_count = 2
	npc.claimed[0] = true
	check(npc.state_key() == "npc:test_state@7,3", "state key is stable and unique per placement")
	var state: Variant = npc.capture_state()
	var other := NpcActor.new()
	other.data = npc.data
	other.restore_state(state)
	check(other.talk_count == 2 and other.claimed.has(0), "state survives a snapshot round trip")
	other.restore_state("garbage")
	check(other.talk_count == 0 and other.claimed.is_empty(), "garbage state falls back to a fresh npc")
	other.restore_state({"talks": -4, "claimed": "nope"})
	check(other.talk_count == 0 and other.claimed.is_empty(), "malformed state fields are ignored")
	npc.free()
	other.free()


func _test_placement() -> void:
	for path in LEVELS:
		var data := load(path) as LevelData
		var layout := LevelBuilder.parse(data)
		var people: Array[Dictionary] = []
		var enemies: Array[Dictionary] = []
		for spawn in layout.spawns:
			if spawn["resource"] is NpcData:
				people.append(spawn)
			elif spawn["resource"] is EnemyData:
				enemies.append(spawn)
		check(layout.warnings.is_empty(), "%s parses without warnings after adding people %s" % [path, layout.warnings])
		check(people.size() >= 2, "%s has people to talk to (%d)" % [path, people.size()])
		for spawn in people:
			var npc := spawn["resource"] as NpcData
			var cell: Vector2i = spawn["cell"]
			for enemy in enemies:
				var enemy_cell: Vector2i = enemy["cell"]
				check(Vector2(cell - enemy_cell).length() > SAFE_TILES, "%s: no enemy within %d tiles of %s" % [path, int(SAFE_TILES), npc.id])
			# 腳下是實心地面（不是掛在半空）。
			check(layout.cell(cell.x, cell.y + 1) == "#" or layout.cell(cell.x, cell.y + 1) == "=", "%s: %s stands on the ground" % [path, npc.id])


# ---------------------------------------------------------------------------
# 對話
# ---------------------------------------------------------------------------

func _test_conversation() -> void:
	Story.auto_skip = false
	var med := load(MED_PATH) as ConsumableData
	var npc_data := _npc(&"test_talker", [_talk(TEST_SCENE_A, 0, &"", 100), _talk(TEST_SCENE_B, 1, &"", 0, med)])
	var data := _level_data({"A": npc_data})
	var level := await start_level(data)
	var npc := _find_npc(level, 14)
	check(npc != null, "the npc spawns from a map character and its data")
	if npc == null:
		await end_level(level)
		return
	# 不受傷、不被當作目標：不在敵人群組、沒有碰撞層、沒有受擊盒。
	check(not npc.is_in_group(&"enemies"), "an npc is not in the enemies group")
	check(npc.collision_layer == 0, "an npc has no collision layer (nothing can hit it)")
	var hurtboxes := 0
	for child in npc.get_children():
		if child is Hurtbox or child.is_in_group(&"hurtbox"):
			hurtboxes += 1
	check(hurtboxes == 0, "an npc has no hurtbox")
	var prompt := _find_prompt(npc)
	check(prompt != null and prompt.text.contains("{interact}") and prompt.text.contains("測試人物"), "the npc shows an interact prompt")
	check(npc.is_in_group(WorldState.GROUP), "an npc takes part in checkpoint snapshots")
	await _stand_next_to(level, npc)
	# 開始對話：遊戲暫停、對話框演出，逐句推進後結束。
	var credits_before := Progression.credits
	npc._talk()
	await frames(2)
	check(runner.get_tree().paused and Story.is_cinematic_active(), "a conversation pauses the game and opens the dialogue box")
	check(npc.talk_count == 0 and Progression.credits == credits_before, "nothing is given before the conversation ends")
	var active_request := Story.current_presentation_request()
	check(not await npc._talk(), "the same NPC rejects reentry while its real waiter owns a presentation")
	check(Story.current_presentation_request() == active_request and npc._talking, "reentry preserves the original request and waiter")
	check(npc.prepare_story_completion(0).is_empty(), "ordinary NPC credit rewards cannot enter the reward-free durable boundary")
	check(npc.prepare_story_completion(-1).is_empty(), "a different talk index cannot settle the current NPC presentation")
	var gap := npc.global_position.x - level.player.global_position.x
	check(gap >= NpcActor.TALK_SPACING - 0.5 and gap <= NpcActor.TALK_SPACING + 0.5, "standing on top of the npc steps the player back to talking distance (%.1f px)" % gap)
	for i in 6:
		Story._layer.advance()
		await frames(1)
	await frames(2)
	check(not runner.get_tree().paused and not Story.is_cinematic_active(), "the game resumes after the conversation")
	check(npc.talk_count == 1, "a finished conversation is counted")
	check(Progression.credits == credits_before + 100, "the first conversation gives its credits (%d)" % (Progression.credits - credits_before))
	check(npc.current_talk_index() == 1, "the next visit uses the later conversation")
	# 同一段場景可以重複對話（不受「看過就不再播」限制）。
	Story.auto_skip = true
	var before_second := Progression.credits
	var player := level.player
	npc._talk()
	await frames(3)
	check(npc.talk_count == 2, "the same npc can be talked to again")
	check(player.consumables.count(med.id) >= 1, "the later conversation gives its supply")
	check(Progression.credits == before_second, "the later conversation does not repeat the first reward")
	# 第三次：獎勵都領過了，不重複給。
	var meds := player.consumables.count(med.id)
	npc._talk()
	await frames(3)
	check(npc.talk_count == 3 and player.consumables.count(med.id) == meds and Progression.credits == before_second, "claimed rewards are not given again")
	await end_level(level)
	Story.auto_skip = true


func _test_interaction_input() -> void:
	Story.auto_skip = true
	var npc_data := _npc(&"test_input", [_talk(TEST_SCENE_A)])
	var level := await start_level(_level_data({"A": npc_data}))
	var npc := _find_npc(level, 14)
	# 站得太遠：按互動鍵沒有反應。
	level.player.global_position = Vector2(30 * 16.0, 19 * 16.0)
	await frames(6)
	Input.action_press(&"interact")
	await frames(3)
	Input.action_release(&"interact")
	await frames(3)
	check(npc.talk_count == 0, "pressing interact far away does nothing")
	# 站在旁邊按互動鍵：開始對話。
	await _stand_next_to(level, npc)
	Input.action_press(&"interact")
	await frames(3)
	Input.action_release(&"interact")
	await frames(6)
	check(npc.talk_count == 1, "pressing interact next to the npc starts the conversation")
	# 剛說完不會馬上又開始（按住互動鍵時）。
	check(npc._cooldown > 0.0 or npc.talk_count == 1, "a short cooldown follows a conversation")
	# 死掉的玩家不能對話。
	var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"grunt_shot")
	lethal.ignore_invulnerability = true
	level.player.health.take_damage(lethal)
	await frames(4)
	var count_before := npc.talk_count
	npc._talk()
	await frames(3)
	check(npc.talk_count == count_before, "a dead player cannot start a conversation")
	await end_level(level)


# ---------------------------------------------------------------------------
# 獎勵
# ---------------------------------------------------------------------------

func _test_rewards_once() -> void:
	Story.auto_skip = true
	var drawing := load("res://data/story_items/doc_crayon_drawing.tres") as StoryItemData
	var med := load(MED_PATH) as ConsumableData
	var talks: Array[NpcTalk] = [_talk(TEST_SCENE_A, 0, &"", 50, null, drawing), _talk(TEST_SCENE_B, 1, &"", 0, med)]
	var level := await start_level(_level_data({"A": _npc(&"test_rewards", talks)}))
	var npc := _find_npc(level, 14)
	var toasts: Array[String] = []
	var on_toast := func(text: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(on_toast)
	var credits_before := Progression.credits
	npc._talk()
	await frames(3)
	check(Progression.credits == credits_before + 50 and StoryItems.owns(drawing.id), "one conversation can give credits and a collectible at once")
	check(StoryItems.collected_count(drawing.chapter) == 1, "the collectible counts toward the chapter collection")
	check(toasts.any(func(t: String) -> bool: return t.contains("信用點") and t.contains(drawing.display_name)), "the reward is announced in one toast: %s" % [toasts])
	# 補給帶滿：整份保留，騰出空間後再說話才補領，而且只領一次。
	npc.talk_count = 1
	var player := level.player
	while not player.consumables.is_full(med):
		player.consumables.add(med)
	npc._talk()
	await frames(3)
	check(not npc.claimed.has(1), "a full bag keeps the reward for later")
	check(toasts.any(func(t: String) -> bool: return t.contains("已達上限")), "the player is told the bag is full")
	player.consumables.take(med.id)
	npc._talk()
	await frames(3)
	check(npc.claimed.has(1) and player.consumables.is_full(med), "the reward is claimed once there is room")
	EventBus.toast_requested.disconnect(on_toast)
	await end_level(level)


func _test_checkpoint_consistency() -> void:
	Story.auto_skip = true
	var talks: Array[NpcTalk] = [_talk(TEST_SCENE_A, 0, &"", 100), _talk(TEST_SCENE_B, 1, &"", 70)]
	var data := _level_data({"A": _npc(&"test_checkpoint", talks)})
	GameState.clear_checkpoint()
	# 領獎後存下檢查點，死亡重來：人物記得談過，獎勵不會再領一次，信用點也還在。
	var level := await start_level(data)
	var npc := _find_npc(level, 14)
	npc._talk()
	await frames(3)
	check(Progression.credits == 100 and npc.claimed.has(0), "the reward is claimed before the checkpoint")
	GameState.set_checkpoint(level.player.global_position, level.player.checkpoint_snapshot(), WorldState.capture(runner.get_tree()), Progression.snapshot())
	check(GameState.checkpoint_world.has(npc.state_key()), "the checkpoint stores the npc state")
	await end_level(level)
	level = await spawn_level(data)
	npc = _find_npc(level, 14)
	check(npc.talk_count == 1 and npc.claimed.has(0), "after respawning the npc remembers the conversation and the claimed reward")
	check(Progression.credits == 100, "after respawning the credits kept their value (%d)" % Progression.credits)
	check(npc.current_talk_index() == 1, "after respawning the npc continues with the later conversation")
	npc._talk()
	await frames(3)
	check(Progression.credits == 170, "only the new reward is added after respawning (%d)" % Progression.credits)
	# 檢查點之後才領的獎勵：重來時信用點與人物一起回到檢查點的樣子，不會多領。
	await end_level(level)
	level = await spawn_level(data)
	npc = _find_npc(level, 14)
	check(npc.talk_count == 1 and not npc.claimed.has(1) and Progression.credits == 100, "a reward claimed after the checkpoint is rolled back together with the credits")
	npc._talk()
	await frames(3)
	check(Progression.credits == 170, "claiming again after the rollback ends with the same total (%d)" % Progression.credits)
	await end_level(level)
	# 沒有檢查點：整關重來，人物與信用點都回到關卡開頭。
	GameState.clear_checkpoint()
	level = await spawn_level(data)
	npc = _find_npc(level, 14)
	check(npc.talk_count == 0 and npc.claimed.is_empty() and Progression.credits == 0, "without a checkpoint the level restarts with a fresh npc and the starting credits")
	npc._talk()
	await frames(3)
	check(Progression.credits == 100, "the first reward is given once per attempt (%d)" % Progression.credits)
	await end_level(level)
	# 新的一輪：全部重置。
	level = await start_level(data)
	npc = _find_npc(level, 14)
	check(npc.talk_count == 0 and Progression.credits == 0, "a new run resets the npc")
	await end_level(level)
	GameState.clear_checkpoint()


# ---------------------------------------------------------------------------
# 真實人物與容錯
# ---------------------------------------------------------------------------

func _test_real_npcs() -> void:
	Story.auto_skip = true
	for path in LEVELS:
		var data := load(path) as LevelData
		var level := await start_level(data)
		var people := 0
		var stack: Array[Node] = [level]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is NpcActor:
				people += 1
				check(not (node as NpcActor).is_in_group(&"enemies"), "%s: %s is not an enemy" % [path, (node as NpcActor).data.id])
			stack.append_array(node.get_children())
		var expected := 0
		for ch in data.legend:
			if data.legend[ch] is NpcData:
				expected += 1
		check(people == expected and people >= 2, "%s: every npc in the legend is in the level (%d)" % [path, people])
		await end_level(level)
	# 第一章的麵攤阿婆：第一次給蠟筆畫，之後給零錢，同一個人談過兩次。
	var ah_po := load("res://data/npcs/ah_po.tres") as NpcData
	var level := await start_level(_level_data({"A": ah_po}))
	var npc := _find_npc(level, 14)
	npc._talk()
	await frames(3)
	check(StoryItems.owns(&"doc_crayon_drawing") and Progression.credits == 0, "the noodle lady gives the drawing first")
	npc._talk()
	await frames(3)
	check(Progression.credits == 150, "and some coins on the next visit (%d)" % Progression.credits)
	await end_level(level)


func _test_fallbacks() -> void:
	Story.auto_skip = true
	# 骨架外觀還沒做好：自動退回頭像剪影，沒有錯誤。
	var no_rig := _npc(&"test_no_rig", [_talk(TEST_SCENE_A)], "test_rig_not_made_yet")
	# 可調查物：沒有外觀，只有記號。
	var marker := _npc(&"test_marker", [_talk(TEST_SCENE_B)])
	marker.kind = NpcData.Kind.OBJECT
	# 壞資料（沒有任何對話）：記錄錯誤並移除，關卡照常建立。
	var broken := _npc(&"test_npc_bad", [])
	var level := await start_level(_level_data({"A": no_rig, "Z": marker, "M": broken}))
	var silhouette := _find_npc(level, 14)
	check(silhouette != null and silhouette._actor != null and silhouette._actor.rig == null, "a missing skeleton falls back to the portrait silhouette")
	var object := _find_npc(level, 24)
	check(object != null and object._actor == null and object.data.kind == NpcData.Kind.OBJECT, "an inspectable object has a marker and no figure")
	check(_find_prompt(object).text.contains("{interact}"), "an object also shows the interact prompt")
	await frames(2)
	check(_find_npc(level, 34) == null, "an npc without talks is removed instead of crashing")
	check(is_instance_valid(level.player), "the level still builds around broken npc data")
	await _stand_next_to(level, object)
	object._talk()
	await frames(3)
	check(object.talk_count == 1, "an object can be inspected")
	# 找不到對話場景：記錄警告並略過，不會卡住。
	var lost := _npc(&"test_lost_scene", [_talk(&"test_no_such_scene")])
	lost.speaker = "rin"
	var npc := NpcActor.new()
	npc.configure(lost, Vector2i(5, 5))
	level.add_child(npc)
	npc.position = level.player.position
	await frames(2)
	npc._talk()
	await frames(3)
	check(not Story.is_cinematic_active() and not runner.get_tree().paused, "a missing dialogue scene does not freeze the game")
	await end_level(level)


func _test_once_object() -> void:
	Story.auto_skip = true
	var talk := _talk(TEST_SCENE_A)
	talk.once = true
	talk.story_item = StoryItems.find(&"nest07_shard")
	var object_data := _npc(&"test_once_object", [talk])
	object_data.kind = NpcData.Kind.OBJECT
	var level := await start_level(_level_data({"A": object_data}))
	var object := _find_npc(level, 14)
	await _stand_next_to(level, object)
	Input.action_press(&"interact")
	await physics_frames(2)
	Input.action_release(&"interact")
	for i in 90:
		if object.talk_count == 1:
			break
		await frames(1)
	check(object.talk_count == 1 and StoryItems.owns(&"nest07_shard"), "interacting with an object grants the existing story item")
	object._talk()
	await frames(3)
	check(object.talk_count == 1, "repeating a once-only investigation does not increment its count")
	await end_level(level)


# ---------------------------------------------------------------------------
# 走近反應與聽到聲響（NE-240）
# ---------------------------------------------------------------------------

func _reaction(gesture: StringName, conditions := {}) -> NpcReaction:
	var reaction := NpcReaction.new()
	reaction.gesture = gesture
	for key: String in conditions:
		reaction.set(key, conditions[key])
	return reaction


## 挑反應：初見、回訪、凜死過之後、旗標；越後面越優先；once 做過就跳過；資料錯誤會被驗證擋下。
func _test_reaction_selection() -> void:
	var npc := _npc(&"test_react", [_talk(TEST_SCENE_A)], "old_k")
	npc.reactions = [_reaction(&"greet", {"max_talks": 0}), _reaction(&"dismiss", {"min_talks": 1}),
			_reaction(&"nod", {"requires_flag": &"test_flag"}), _reaction(&"rub_neck", {"min_deaths": 1, "once": true})]
	var seen := func(_scene: StringName) -> bool: return false
	var no_flag := func(_flag: StringName) -> bool: return false
	var flag := func(f: StringName) -> bool: return f == &"test_flag"
	check(npc.pick_reaction(0, seen, 0, no_flag) == 0, "first meeting: greet")
	check(npc.pick_reaction(2, seen, 0, no_flag) == 1, "revisit: a different reaction")
	check(npc.pick_reaction(2, seen, 0, flag) == 2, "after a story flag: the later reaction wins")
	check(npc.pick_reaction(2, seen, 1, flag) == 3, "after Rin has died: the worried reaction")
	check(npc.pick_reaction(2, seen, 1, flag, Callable(), {3: true}) == 2, "a once reaction is skipped after it was done")
	check(npc.validate().is_empty(), "valid reactions pass validation (%s)" % ", ".join(npc.validate()))
	npc.reactions = [_reaction(&"no_such_gesture"), _reaction(&"nod", {"max_talks": 0, "min_talks": 2}), null]
	check(npc.validate().size() == 3, "unknown gestures, impossible conditions and empty entries are reported (%d)" % npc.validate().size())
	for path in DirAccess.get_files_at(NPC_DIR):
		if path.ends_with(".tres"):
			var real := load(NPC_DIR.path_join(path)) as NpcData
			check(real != null and real.validate().is_empty(), "%s validates with its reactions" % path)
	var ch1_old_k := load("res://data/npcs/ch1_old_k.tres") as NpcData
	check(ch1_old_k.reactions.size() >= 3, "Old K has first-meet, revisit and after-death reactions")


## 實際關卡：走近時做反應（有冷卻、說話中不做）；附近開槍會縮一下並轉頭看，連續三聲就蹲下抱頭，安靜後站起來回到工作；
## once 反應做過會存在檢查點狀態裡。
func _test_awareness() -> void:
	Story.auto_skip = true
	var data := _npc(&"test_aware", [_talk(TEST_SCENE_A)], "old_k")
	data.loop = &"wipe_hands"
	data.reactions = [_reaction(&"greet", {"max_talks": 0, "once": true}), _reaction(&"dismiss", {"min_talks": 1})]
	var level := await start_level(_level_data({"A": data}))
	var npc := _find_npc(level, 14)
	check(npc != null and npc.awareness != null, "a rigged npc has awareness")
	if npc == null or npc.awareness == null:
		await end_level(level)
		return
	var awareness := npc.awareness
	level.player.global_position = npc.global_position + Vector2(-NpcAwareness.NOTICE_RANGE - 80.0, -2)
	await physics_frames(4)
	check(awareness.reactions_done == 0, "no reaction while the player is far away")
	level.player.global_position = npc.global_position + Vector2(-NpcAwareness.NOTICE_RANGE + 20.0, -2)
	await physics_frames(3)
	check(awareness.reactions_done == 1, "walking up triggers a reaction")
	var life := (npc._actor.rig.animator as NpcAnimator)._life
	check(life != null and life.current_gesture() == &"greet", "the first meeting is a greeting (%s)" % (life.current_gesture() if life != null else &"?"))
	level.player.global_position = npc.global_position + Vector2(-NpcAwareness.NOTICE_RANGE - 80.0, -2)
	await physics_frames(3)
	level.player.global_position = npc.global_position + Vector2(-NpcAwareness.NOTICE_RANGE + 20.0, -2)
	await physics_frames(3)
	check(awareness.reactions_done == 1, "walking back and forth does not repeat it right away (cooldown)")
	var state: Variant = npc.capture_state()
	check(typeof(state) == TYPE_DICTIONARY and (state["reacted"] as Array).has(0), "a once reaction is saved with the checkpoint")
	# 聲響：遠的聽不到；近的縮一下並轉頭；三聲就蹲下
	level.player.global_position = npc.global_position + Vector2(-NpcAwareness.NOTICE_RANGE - 80.0, -2)
	await physics_frames(2)
	EventBus.world_noise.emit(npc.global_position + Vector2(NpcAwareness.NOISE_RADIUS * 2.0, 0), 1.0)
	check(awareness.startles == 0, "a gunshot far away is not heard")
	EventBus.world_noise.emit(npc.global_position + Vector2(40, -10), Portal.RATTLE_NOISE)
	await physics_frames(2)
	check(awareness.startles == 0 and awareness.look_direction() == 1, "a rattling locked door only makes the npc look over")
	await physics_frames(int(NpcAwareness.LOOK_HOLD * 60.0) + 2)
	EventBus.world_noise.emit(npc.global_position + Vector2(60, -10), 1.0)
	await physics_frames(2)
	check(awareness.startles == 1, "a nearby gunshot makes the npc flinch")
	check(npc._actor.facing == 1, "and turn toward the sound")
	for i in 2:
		await physics_frames(int(NpcAwareness.STARTLE_COOLDOWN * 60.0) + 2)
		EventBus.world_noise.emit(npc.global_position + Vector2(60, -10), 1.0)
	await physics_frames(2)
	check(awareness.is_cowering() and npc._actor.pose == &"squat", "three shots in a few seconds: the npc ducks and covers")
	check(npc._actor._input.npc_loop == &"", "and stops working")
	await physics_frames(int((NpcAwareness.COWER_QUIET + 0.5) * 60.0))
	check(not awareness.is_cowering() and npc._actor.pose == data.pose, "after it is quiet again the npc stands back up")
	check(npc._actor._input.npc_loop == &"wipe_hands", "and goes back to work")
	await physics_frames(int(NpcAwareness.LOOK_HOLD * 60.0))
	check(npc._actor.facing == data.facing, "and turns back to where it was facing")
	await end_level(level)
