extends "res://tools/prologue_play_probe.gd"
## Retain the original actual-input training route. Intercept only after genuine
## actions, then refuse the original counter's real completion write.
var mode := ""
var checks := 0
var issues: Array[String] = []
var target: StringName
var faulted := false
var original := PackedByteArray()
var facts_before := PackedByteArray()

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = false
	target = &"ch1_p06_call" if mode == "call" else &"ch1_p05_service_clean" if mode == "clean" else &"ch1_p05_service_fall"
	Story.scene_started.connect(_inject)
	super._ready()

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		issues.append(what)
	super._check(ok,what)

func _stop_if(flag: StringName) -> bool:
	if mode == "clean" and flag == &"ch1_prologue_melee_done":
		_clean_tail.call_deferred()
		return true
	if mode != "clean" and flag == &"ch1_prologue_dash_done":
		_counter_tail.call_deferred()
		return true
	return false

func _clean_tail() -> void:
	await _finish_story()
	_aim(Vector2.RIGHT)
	Input.action_press(&"block")
	var trainer := _station(&"ch1_training_trainer")
	await _walk_to(trainer.global_position.x-34.0)
	_check(await _wait_flag(&"ch1_prologue_guard_done",600),"clean actual-input route blocks its first trainer strike")
	Input.action_release(&"block")
	_check(not GameState.has_flag(&"ch1_prologue_fall_shown"),"clean original route never invents a training fall")
	await _finish_story()
	var dash := _station(&"ch1_training_dash")
	await _walk_to(dash.global_position.x-40.0)
	Input.action_press(&"move_right")
	await _frames(2)
	await _press(&"dash",3)
	await _frames(20)
	Input.action_release(&"move_right")
	_check(await _wait_flag(&"ch1_prologue_dash_done",120),"clean actual-input route completes the original dash line")
	await _counter_tail()

func _counter_tail() -> void:
	await _finish_story()
	_check(GameState.deaths == 0 and not GameState.has_flag(&"ch1_first_death_done"),"actual training never consumes a genuine death or first-clinic registration")
	var actor := _npc(&"ch1_old_k_counter")
	_check(actor != null and actor.is_present(),"actual completed training makes original counter Old K available")
	if actor == null:
		await _finish_probe()
		return
	await _walk_to(actor.global_position.x+14.0)
	await _press(&"interact")
	await _finish_story()
	if mode == "call":
		_check(GameState.has_flag(&"ch1_prologue_service_heard") and actor.talk_count > 0,"genuine original service dialogue completes before the wrap-up call")
		await _frames(70)
		await _press(&"interact")
		await _finish_story()
	await _frames(5)
	_check(faulted,"same real counter dispatch reaches the exact intended original result")
	_check(_facts() == facts_before,"genuine prologue write refusal cannot publish flags, history, items, wallet or NPC completion")
	var store: RunSaveStore = _main.get("_run_store")
	_check(FileAccess.get_file_as_bytes(store.path) == original,"genuine refusal retains the exact previous Main primary")
	_check(_prompt() != null and Story._current_cinematic == target and get_tree().paused,"genuine refusal holds original counter waiter and its real retry prompt")
	if faulted:
		_check(DirAccess.remove_absolute(store.path+".tmp") == OK,"remove only the owned empty IO obstruction")
	await _finish_probe()

func _finish_story(shot := "") -> void:
	if not faulted:
		await super._finish_story(shot)
		return
	var deadline := Time.get_ticks_msec()+30000
	while Story.is_cinematic_active() and _prompt() == null and Time.get_ticks_msec() < deadline:
		Story.skip_cinematic()
		await _frames(1)

func _inject(id: StringName, _kind: StringName) -> void:
	if id != target or faulted:
		return
	faulted = true
	var store: RunSaveStore = _main.get("_run_store")
	original = FileAccess.get_file_as_bytes(store.path)
	facts_before = _facts()
	FileAccess.open(_save_dir.path_join("refused-primary.json"),FileAccess.WRITE).store_buffer(original)
	_check(not original.is_empty() and DirAccess.make_dir_absolute(store.path+".tmp") == OK,"create genuine temp-directory IO refusal only at the original counter result")

func _facts() -> PackedByteArray:
	var actor := _npc(&"ch1_old_k_counter")
	return var_to_bytes([GameState.world_flags,Story.progress_snapshot(),StoryItems.snapshot(),Progression.snapshot(),actor.talk_count if actor != null else -1])

func _prompt() -> Control:
	return (_main.get("_result_completion") as Node).get("_prompt") as Control

func _finish_probe() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	FileAccess.open(_out.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"mode":mode,"checks":checks,"failures":issues,"flags":GameState.world_flags,"history":Story.progress_snapshot(),"current":String(Story._current_cinematic),"deaths":GameState.deaths,"faulted":faulted},"  "))
	_main.call("_quit",0 if issues.is_empty() else 1)
