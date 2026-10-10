extends Node
## ST-22：真Main／正式NPC節點＋工具專用劇本；分離程序續玩、then與死亡取消。
const MainScript := preload("res://game/main.gd")
const LEVEL := "res://data/levels/ch1_stall.tres"
const A := &"st22_resume_a"
const B := &"st22_resume_b"
var mode := ""
var directory := ""
var source := "person"
var main: Node
var _fixture_npc: NpcData
var checks := 0
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--save-dir="):
			directory = arg.trim_prefix("--save-dir=")
	var profile := OS.get_environment("ST22_PROFILE").replace("\\", "/").to_lower().trim_suffix("/")
	if profile.is_empty() or not OS.get_user_data_dir().replace("\\", "/").to_lower().begins_with(profile + "/") or not directory.is_absolute_path():
		push_error("[ST22Resume] isolated APPDATA and absolute --save-dir required")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		get_tree().quit(2)
		return
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1


func frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame


func _fixture() -> void:
	source = "object" if mode.begins_with("object") else "person"
	_fixture_npc = load("res://data/npcs/ch1_ali_stall.tres") as NpcData
	var npc := _fixture_npc
	var talk := NpcTalk.new()
	talk.scene = A
	talk.credits = 15
	talk.once = false
	npc.talks = [talk]
	npc.kind = NpcData.Kind.OBJECT if source == "object" else NpcData.Kind.PERSON
	Story._scenes[String(A)] = {"mode": "dialogue", "lines": [{"speaker": "ali", "text": "合成續玩來源測試。"}]}
	if mode.begins_with("chain") or mode.begins_with("bad") or mode in ["death", "route", "leave"]:
		Story._scenes[String(A)]["then"] = String(B)
		Story._scenes[String(A)]["set_flags"] = ["st22_a_completed"]
		Story._scenes[String(B)] = {"mode": "animated", "steps": [
			{"do": "scene", "id": "old_k_shop", "fade": 0.0},
			{"do": "choice", "text": "合成續段選擇。", "default": "b", "options": [
				{"id": "a", "text": "路線A", "set_flags": {"st22_choice_a": true}},
				{"id": "b", "text": "路線B", "set_flags": {"st22_choice_b": true}}]},
			{"do": "wait", "time": 600.0}]}
	Story.scene_finished.connect(func(id: StringName) -> void:
		if id == A and GameState.has_flag(&"st22_a_completed"):
			Progression.add_credits(40))


func npc_for(level: Level) -> NpcActor:
	for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if level.is_ancestor_of(node) and node.data.id == &"ch1_ali_stall":
			return node as NpcActor
	return null


func _wait_choice() -> void:
	for i in 120:
		if is_instance_valid(Story._player) and Story._player.choice_active():
			return
		await frames(1)
	check(false, "actual choice becomes active")


func _run() -> void:
	_fixture()
	Transition.instant = true
	Story.auto_skip = true
	main = MainScript.new()
	main.set("_run_store", RunSaveStore.new(directory.path_join("slot.json")))
	add_child(main)
	await frames()
	if mode.ends_with("_read"):
		if mode.begins_with("bad"):
			var store: RunSaveStore = main.get("_run_store")
			var corrupted := store.read()
			if mode == "badindex_read":
				corrupted["cinematic_context"]["talk_index"] = 255
			else:
				corrupted["cinematic"] = "ch1_t_ali_3"
			check(store.write(corrupted), "tool-only invalid source linkage is written into isolated actual slot")
		Story.auto_skip = false
		main.call("_on_continue_requested")
	else:
		main.call("_on_start_requested", GameState.difficulties[1])
		await frames(5)
		main.call("_on_area_requested", LEVEL)
	await frames(6)
	var level := main.get("_screen") as Level
	check(level != null and level.data.resource_path == LEVEL, "actual Main loads the formal stall map")
	if level == null:
		_finish()
		return
	var npc := npc_for(level)
	check(npc != null, "actual formal NPC owner exists")
	if npc == null:
		_finish()
		return
	if mode.ends_with("_read"):
		await _read(level, npc)
	else:
		await _write(level, npc)
	_finish()


func _write(level: Level, npc: NpcActor) -> void:
	Progression.add_credits(100)
	await frames()
	Story.auto_skip = false
	if mode == "death":
		GameState.set_flag(&"ch1_first_death_done")
	npc._talk()
	await frames()
	check(Story.current_presentation_context().get("framing_source") == source, "actual NPC request carries its own source")
	if mode.begins_with("chain") or mode in ["death", "route", "leave"]:
		for i in 10:
			if Story._current_cinematic != A:
				break
			Story._layer.advance()
			await frames(1)
		await _wait_choice()
		check(Story._current_cinematic == B and Progression.credits == 140 and GameState.has_flag(&"st22_a_completed"), "completed A transaction survives into B's new atomic entry")
		Story._player.choose(0)
		await frames()
		Progression.add_credits(900) # 明標工具暫定交易，須取消／退出撤回。
		check(GameState.has_flag(&"st22_choice_a"), "actual choice applies A provisionally")
	if mode == "sameid":
		var first_request := Story.current_presentation_request()
		var object_data := npc.data.duplicate() as NpcData
		object_data.id = &"st22_queued_object"
		object_data.kind = NpcData.Kind.OBJECT
		var object := NpcActor.new()
		object.configure(object_data, Vector2i(-1, -1))
		level.add_child(object)
		object._talk()
		await frames()
		Story.skip_cinematic()
		await frames()
		var second_request := Story.current_presentation_request()
		check(second_request != first_request and Story.current_presentation_context().get("framing_source") == "object" and npc.talk_count == 1 and object.talk_count == 0, "same-ID first request completes only first NPC while second stays active")
		Story.presentation_cancelled.emit(A, {"framing_source": "person"}, &"leave", first_request) # 合成舊callback，不是第二段真正取消。
		check(main.get("_cinematic_request") == second_request, "stale same-ID cancellation cannot clear the new atomic entry")
		Story.reset_active_presentation(&"leave")
		await frames()
		check(object.talk_count == 0 and Progression.credits == 115 and Story._waiters.is_empty() and Story._request_results.is_empty(), "actual second-request cancellation grants nothing and retains first reward")
	elif mode == "leave":
		level.queue_free() # 真tree_exiting，而非直接呼叫cancel假冒離場。
		await frames(6)
		check(not is_instance_valid(level) and main.get("_cinematic") == "", "true Level owner teardown cancels and clears atomic marker")
		check(Progression.credits == 140 and not GameState.has_flag(&"st22_choice_a") and GameState.has_flag(&"st22_a_completed"), "owner teardown withdraws B while preserving completed A")
		check(Story._waiters.is_empty() and Story._request_results.is_empty() and Story.framing.scope_count() == 0, "true owner teardown leaves no request result or framing scope")
	elif mode == "death":
		var deaths := GameState.deaths
		level.player.health.kill(DamageInfo.create(999, Combat.Team.ENEMY, &"probe"))
		check(level.player.is_dead() and level.player.health.current == 0 and level.died, "cancel rollback preserves actual corpse, health and Level death")
		check(GameState.deaths == deaths + 1 and main.get("_cinematic") == "", "death registers once after presentation marker clears")
		check(Progression.credits < 140 and not GameState.has_flag(&"st22_choice_a") and GameState.has_flag(&"st22_a_completed"), "death withdraws B only, retains A, then applies original cost")
	elif mode == "route":
		GameState.pending_portal = &"pawn_front"
		Story.auto_skip = true
		main.call("_on_area_requested", "res://data/levels/ch1_pawnshop.tres")
		await frames(6)
		check(main.get("_screen") is Level and (main.get("_screen") as Level).data.resource_path == "res://data/levels/ch1_pawnshop.tres" and main.get("_screen") != level and Progression.credits == 140 and not GameState.has_flag(&"st22_choice_a"), "actual area route withdraws provisional B without A rollback")
	else:
		main.call("_save_run")
		var saved: Dictionary = (main.get("_run_store") as RunSaveStore).read()
		check(saved.get("cinematic_context", {}).get("framing_source") == source and saved["cinematic_context"].get("talk_index") == 0, "disk snapshot preserves pure source and NPC index")
		check(not saved["cinematic_context"].has("request") and not saved["cinematic_context"].has("bar_pose"), "runtime handle and framing pose never enter save")
		if mode.begins_with("chain"):
			check(saved["cinematic"] == String(B) and saved["progression"]["credits"] == 140 and not saved["story"]["flags"].get("st22_choice_a", false), "quit snapshot retains completed A while rewinding B's provisional transaction")
		else:
			check(saved["cinematic"] == String(A) and npc.talk_count == 0 and npc.claimed.is_empty(), "interrupted NPC dialogue has no reward yet")


func _read(_level: Level, npc: NpcActor) -> void:
	if mode.begins_with("bad"):
		check(not npc.get("_talking") and npc.talk_count == 0 and npc.claimed.is_empty(), "invalid saved index or chain never enters NPC reward owner")
		var saved: Dictionary = (main.get("_run_store") as RunSaveStore).read()
		check(saved["cinematic"] != "" and Progression.credits == 140 and GameState.has_flag(&"st22_a_completed"), "invalid owner linkage preserves unfinished story entry and completed A")
		Story.skip_cinematic()
		await frames(6)
		check(npc.talk_count == 0 and npc.claimed.is_empty() and Progression.credits == 140, "fallback scene completion cannot claim unrelated NPC reward")
		check(npc.current_talk_index() == 0 and npc.preview_available(), "formal NPC remains available for a legitimate new conversation")
		return
	check(Story.current_presentation_context().get("framing_source") == source and npc.get("_talking"), "second process resumes through actual NPC owner")
	if mode.begins_with("chain"):
		await _wait_choice()
		check(Story._current_cinematic == B and Progression.credits == 140 and not GameState.has_flag(&"st22_choice_a"), "second process resumes unanswered B without reversing completed A")
		Story._player.choose(1)
		await frames()
		Story.skip_cinematic()
	else:
		check(Story.framing.scope_count() == (1 if source == "person" else 0), "same dialogue resumes with PERSON framing and OBJECT excluded")
		Story.skip_cinematic()
	await frames(6)
	var expected := 155 if mode.begins_with("chain") else 115
	check(npc.talk_count == 1 and npc.claimed.has(0) and Progression.credits == expected, "actual resumed NPC grants exactly one final reward")
	check(not npc.can_resume_presentation(A, 999) and not npc.can_resume_presentation(&"ch1_c14_home", 0), "illegal index and unrelated scene cannot claim NPC rewards")
	check(Story._waiters.is_empty() and Story._request_results.is_empty() and Story.framing.scope_count() == 0, "resume completion releases waiters, result and framing scope")
	main.call("_save_run")


func _finish() -> void:
	print("ST22_RESUME_RESULT mode=%s checks=%d failures=%d" % [mode, checks, failures])
	# 真實關閉：Main必須先保存原子入口，然後cancel/free。
	main.call("_quit", 0 if failures == 0 else 1)
