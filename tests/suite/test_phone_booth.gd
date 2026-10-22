class_name PhoneBoothSuite
extends EnemySuiteBase
## 電話亭檢查點（NE-121）：路過不啟動、走近按互動鍵才撥號、撥號時收起武器拿話筒再放回、通話時間線（拿起、撥號音、標語、掛上）、
## 完成後記錄位置與武器配置並依難度回滿血與補滿彈藥、已啟動的亭子可以再撥、通話被打斷不備份、重生時直接是已啟動、
## 骨架動作逐格稽核（骨頭長度、手肘、驅幹、角度跳動）。

const BOOTH_TILE := 30.0
const HANDSET_FILE := "handset.png"


func run() -> void:
	_test_data()
	await _test_walking_past_does_nothing()
	await _test_dial_with_the_interact_key()
	await _test_call_timeline_and_weapon_swap()
	await _test_completion_and_second_call()
	await _test_call_can_be_interrupted()
	await _test_respawn_shows_activated()
	await _test_cannot_dial_in_the_air()
	await _test_nearest_interaction()
	await _test_action_audit()


func _booth(level_node: Level, x_tile := BOOTH_TILE) -> Checkpoint:
	var booth := Checkpoint.new()
	booth.position = Vector2(x_tile * 16.0, FLOOR_Y)
	level_node._entities.add_child(booth)
	return booth


func _clear_enemies() -> void:
	for enemy in level.get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()


func _test_data() -> void:
	var weapons: Dictionary = RigLibrary.weapons().get("weapons", {})
	check(weapons.has("handset") and FileAccess.file_exists("res://art/weapons/%s" % HANDSET_FILE), "the handset exists as a hand-held visual")
	var actions: Dictionary = RigLibrary.load_json(HumanoidAnimator.ACTIONS_PATH).get("actions", {})
	check(actions.has("rin.phone_call") and absf(float(actions["rin.phone_call"]["duration"]) - Player.PHONE_DURATION) < 0.01, "the phone call action matches the call duration")
	for id in [&"phone_pickup", &"phone_dial", &"phone_dial2", &"phone_dial3", &"phone_voice", &"phone_hangup", &"phone_ring"]:
		check(Sfx.SOUNDS.has(id), "sound exists: %s" % id)
	var last := 0.0
	for t in [Checkpoint.T_PICKUP] + Checkpoint.T_DIAL + [Checkpoint.T_VOICE, Checkpoint.T_HANGUP, Checkpoint.T_DONE]:
		check(float(t) > last and float(t) <= 1.0, "call timeline is in order (%.2f)" % float(t))
		last = float(t)
	check(Player.PHONE_DURATION <= 1.2, "a call is about a second so it does not slow the pace")


func _test_walking_past_does_nothing() -> void:
	await open_level(10.0)
	_clear_enemies()
	var booth := _booth(level)
	GameState.clear_checkpoint()
	place_player(BOOTH_TILE - 1.0)
	await physics_frames(40)
	check(not booth.activated and not GameState.has_checkpoint and not level.player.is_on_phone(), "walking up to a booth does not start a call")
	check(booth.can_dial(), "the booth can be dialed when the player is in reach")
	place_player(BOOTH_TILE + 10.0)
	await physics_frames(10)
	check(not booth.can_dial(), "out of reach nothing can be dialed")
	await end_level(level)


func _test_dial_with_the_interact_key() -> void:
	await open_level(10.0)
	_clear_enemies()
	var booth := _booth(level)
	GameState.clear_checkpoint()
	place_player(BOOTH_TILE - 1.0)
	await physics_frames(20)
	Input.action_press(&"interact")
	await physics_frames(2)
	Input.action_release(&"interact")
	check(level.player.is_on_phone() and booth.is_calling(), "pressing the interact key starts the call")
	check(level.player.facing == 1, "the player faces the booth")
	await physics_frames(100)
	check(not level.player.is_on_phone() and not booth.is_calling() and booth.activated, "the call finishes by itself")
	await end_level(level)


func _test_call_timeline_and_weapon_swap() -> void:
	await open_level(10.0)
	_clear_enemies()
	var booth := _booth(level)
	GameState.clear_checkpoint()
	place_player(BOOTH_TILE - 1.0)
	await physics_frames(10)
	var player := level.player
	var original := str(player.loadout.active_weapon().visual_id)
	check(not original.is_empty() and not player._visual.rig.weapon_def().is_empty(), "the player holds a weapon before the call")
	var toasts: Array[String] = []
	var listener := func(text: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(listener)
	check(booth.start_call(player), "the call starts")
	await physics_frames(3)
	check(player._visual.rig.weapon_def().is_empty(), "the weapon is put away first")
	var frames_seen := 0
	var handset_seen := false
	var progress_ok := true
	var last_progress := -1.0
	for i in 90:
		await physics_frames(1)
		var progress := player._visual.phone_progress()
		if progress >= 0.0:
			progress_ok = progress_ok and progress >= last_progress
			last_progress = progress
			frames_seen += 1
			if str(player._visual.rig.weapon_def().get("file", "")) == HANDSET_FILE:
				handset_seen = true
	check(handset_seen, "the handset is in hand during the call")
	check(progress_ok and frames_seen >= 55, "the call animation advances smoothly (%d frames)" % frames_seen)
	check(str(player._visual.rig.weapon_def().get("file", "")) == str(RigLibrary.weapon(original).get("file", "x")), "the original weapon is back afterwards")
	check(toasts.has(Checkpoint.SLOGAN), "the receiver plays the slogan")
	EventBus.toast_requested.disconnect(listener)
	await end_level(level)


func _test_completion_and_second_call() -> void:
	await open_level(10.0)
	_clear_enemies()
	var booth := _booth(level)
	GameState.start_new_run(GameState.difficulties[1])
	level.player.health.setup(999, 0.0)
	var player := level.player
	place_player(BOOTH_TILE - 1.0)
	await physics_frames(10)
	player.health.take_damage(hit(4))
	player.loadout.consume_ammo()
	var before_mag := player.loadout.mag_in(player.loadout.active_slot)
	booth.start_call(player)
	await physics_frames(90)
	check(GameState.has_checkpoint and GameState.checkpoint_position.distance_to(booth.global_position) < 2.0, "the first call records the checkpoint")
	check(booth.activated, "the booth is active afterwards")
	check(player.loadout.mag_in(player.loadout.active_slot) >= before_mag, "the ammo is refilled")
	if GameState.difficulty.checkpoint_heals:
		check(player.health.current == player.health.max_health, "health is restored on difficulties that heal at checkpoints")
	var credits := Progression.credits
	var mag := player.loadout.mag_in(player.loadout.active_slot)
	player.loadout.consume_ammo()
	check(booth.start_call(player), "an active booth can be dialed again")
	await physics_frames(90)
	check(player.loadout.mag_in(player.loadout.active_slot) == mag and Progression.credits == credits, "the second call refills ammo and costs nothing")
	await end_level(level)
	GameState.clear_checkpoint()


func _test_call_can_be_interrupted() -> void:
	await open_level(10.0)
	_clear_enemies()
	var booth := _booth(level)
	GameState.clear_checkpoint()
	place_player(BOOTH_TILE - 1.0)
	await physics_frames(10)
	var player := level.player
	booth.start_call(player)
	await physics_frames(20)
	player.health.take_damage(hit(9999, true))
	await physics_frames(10)
	check(player.is_dead() and not booth.is_calling() and not booth.activated and not GameState.has_checkpoint, "dying during the call cancels it without saving")
	await end_level(level)


func _test_respawn_shows_activated() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	await open_level(10.0)
	GameState.set_checkpoint(Vector2(BOOTH_TILE * 16.0, FLOOR_Y), {}, {}, {})
	_clear_enemies()
	var booth := _booth(level)
	await physics_frames(2)
	check(booth.activated and booth._rebirth > 0.0, "respawning at a booth shows it active with the rebirth moment")
	await end_level(level)
	GameState.clear_checkpoint()


func _test_cannot_dial_in_the_air() -> void:
	await open_level(10.0)
	_clear_enemies()
	var booth := _booth(level)
	GameState.clear_checkpoint()
	place_player(BOOTH_TILE - 1.0, FLOOR_Y - 60.0)
	await physics_frames(2)
	check(not level.player.begin_phone_call(1), "a call cannot start in mid-air")
	check(not booth.start_call(level.player), "the booth refuses while the player is falling")
	await end_level(level)


## The real booth/NPC overlap shares one interact key and cannot start both activities.
func _test_nearest_interaction() -> void:
	await open_level(10.0)
	_clear_enemies()
	GameState.clear_checkpoint()
	var auto_skip := Story.auto_skip
	Story.auto_skip = false
	var scene := &"test_phone_nearest_source"
	Story._scenes[String(scene)] = {"mode": "dialogue", "lines": [{"speaker": "rin", "text": "互動來源測試。"}]}
	var booth := _booth(level, 18.0)
	var talk := NpcTalk.new()
	talk.scene = scene
	var data := NpcData.new()
	data.id = &"phone_neighbour"
	data.kind = NpcData.Kind.OBJECT
	data.rig_id = ""
	data.talks = [talk]
	var npc := NpcActor.new()
	npc.configure(data, Vector2i(21, 19))
	level._entities.add_child(npc)
	npc.global_position = booth.global_position + Vector2(48, 0)
	level.player.global_position = booth.global_position + Vector2(20, 0)
	await physics_frames(15)
	check(booth._player_in_range and npc._player_in_range, "both real interaction sensors overlap")
	check(booth.can_dial() and not Story.framing.is_interaction_target(npc), "the nearer phone owns interact before any action starts")
	level.player.global_position.x = booth.global_position.x + 25.0
	await physics_frames(5)
	check(not booth.can_dial() and Story.framing.is_interaction_target(npc), "the nearer NPC owns interact inside the same overlap")
	level.player.global_position.x = booth.global_position.x + 20.0
	await physics_frames(5)
	Input.action_press(&"interact")
	await physics_frames(2)
	Input.action_release(&"interact")
	check(level.player.is_on_phone() and booth.is_calling(), "a single overlap press begins the nearer booth call")
	check(not npc._talking and not Story.is_cinematic_active(), "that same press does not also begin NPC dialogue")
	Story.reset_active_presentation(&"test")
	await physics_frames(2)
	if not level.player.is_on_phone():
		check(booth.start_call(level.player), "phone precondition for the direct-dialogue guard")
	var done := [false, false]
	var begin_talk := func() -> void:
		done[1] = await npc._talk()
		done[0] = true
	begin_talk.call()
	await physics_frames(2)
	check(done[0] and not done[1] and not Story.is_cinematic_active(), "direct dialogue entry also refuses during the actual phone state")
	check(not npc._prompt_available(), "NPC hover guidance stays hidden during the call")
	Story.reset_active_presentation(&"test")
	Story.auto_skip = true
	await physics_frames(100)
	var token := GameplayLock.acquire(booth)
	check(not booth.start_call(level.player), "direct phone entry refuses an existing gameplay lock")
	GameplayLock.release(token)
	await physics_frames(100)
	Story.reset_active_presentation(&"test")
	await end_level(level)
	Story._scenes.erase(String(scene))
	Story._seen.erase(scene)
	Story._completed.erase(scene)
	Story.auto_skip = auto_skip
	GameState.clear_checkpoint()


## 骨架動作逐格稽核：把撥號動作整段播放，骨頭長度、手肘、驅幹、頭、角度跳動都要在限制內。
func _test_action_audit() -> void:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup("rin"), "rin builds")
	rig.set_weapon("handset")
	var report := AnimAudit.audit_actions(rig, ["rin.phone_call"])
	for check_name: String in ["bone_stretch", "elbow_hyper", "trunk_lean", "head_turn", "angle_pop"]:
		var entry: Dictionary = report.get(check_name, {"value": 0.0, "limit": AnimAudit.LIMITS[check_name], "where": "-"})
		check(float(entry["value"]) <= float(entry["limit"]), "phone call: %s within limit (%.2f > %.2f at %s)" % [check_name, float(entry["value"]), float(entry["limit"]), entry["where"]])
	holder.queue_free()
	await frames(1)
