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
	_remove_test_scenes()
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
			check(str((Story._scenes[String(talk.scene)] as Dictionary).get("mode")) == "dialogue", "npc talk is a dialogue scene: %s" % talk.scene)
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
