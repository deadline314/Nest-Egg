extends "res://tests/helpers/ali_completion_base.gd"
## Reuse the strict original NPC snapshot/waiter helpers; only source and flow differ.
const COUNTER := "res://data/npcs/ch1_old_k_counter.tres"
const PHASES := {"fall":&"ch1_p05_service_fall","clean":&"ch1_p05_service_clean","call":&"ch1_p06_call"}
var phase := ""
var action := ""
var expected_before := 0
var starts: Array[StringName] = []

func _run() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = false
	phase = _mode.get_slice("_",0)
	action = _mode.trim_prefix(phase+"_")
	target = PHASES[phase]
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/prologue_counter/provenance.json")):
		if row["mode"] == phase:
			expected_before = row["before_count"]
	_main = MainScript.new()
	store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store",store)
	add_child(_main)
	await _frames(5)
	_main.call("_on_continue_requested")
	await _until(func() -> bool: return _main.get("_screen") is Level and (_main.get("_screen") as Level).is_initialized() and not _main.call("_route_pending"))
	await _frames(8)
	await _until(func() -> bool: return _actor() != null and _actor().is_present())
	var actor := _actor()
	_check(GameState.deaths == 0 and not GameState.has_flag(&"ch1_first_death_done") and GameState.has_flag(&"ch1_prologue_dash_done"),"exact genuine training primary preserves actions and spends no death")
	_check(GameState.has_flag(&"ch1_prologue_fall_shown") == (phase != "clean"),"original fall and clean variants remain distinct")
	Story.scene_started.connect(_observe)
	if action == "read":
		await _frames(15)
		_check(not Story.is_cinematic_active() and starts.is_empty(),"cold completed primary does not replay the prologue")
		_check(_settled() and actor.talk_count == expected_before+1,"cold completed primary preserves the exact original counter completion once")
		await _finish()
		return
	_check(not _settled() and actor.talk_count == expected_before,"original unread target has no arranged completion")
	if action in ["pending_read","cancel_read"]:
		await _until(func() -> bool: return Story._current_cinematic == target and Story.is_cinematic_active())
		_check(actor._talking,"cold pending primary restores the same original counter waiter")
	else:
		await _until(func() -> bool: return not Story.is_cinematic_active() and not GameplayLock.is_locked())
		(_main.get("_screen") as Level).player.global_position = actor.global_position+Vector2(14,0)
		await _frames(4)
		actor._talk()
		await _until(func() -> bool: return Story._current_cinematic == target)
	if action in ["pending","cancel"]:
		_main.call("_save_run")
		var bytes := FileAccess.get_file_as_bytes(store.path)
		var raw := RunSaveCodec.decode(bytes.get_string_from_utf8())
		_check(raw.has("data") and raw["data"]["cinematic"] == String(target) and raw["data"]["cinematic_context"].get("framing_source") == "person","Main actually saves the exact unread target and original person source")
		FileAccess.open(_directory.path_join("pending-primary.json"),FileAccess.WRITE).store_buffer(bytes)
		await _capture("pending")
		if action == "cancel":
			_main.call("_show_main_menu")
			await _frames(5)
			_check(not Story.is_cinematic_active() and not _settled() and FileAccess.get_file_as_bytes(store.path) == bytes,"actual menu cancellation preserves unread primary without publishing completion")
		await _finish()
		return
	await _drive_dialogue()
	if action == "retry":
		_check(faulted and _prompt() != null and _facts() == facts_before and actor.talk_count == before_count,"actual writer refusal retains all services and original counter count")
		_check(FileAccess.get_file_as_bytes(store.path) == original and Story._current_cinematic == target and actor._talking,"actual refusal retains exact original primary and the same live request")
		if _prompt() == null:
			await _finish()
			return
		_prompt().get("retry_button").pressed.emit()
		await _frames(4)
		_check(_prompt() != null and _facts() == facts_before and actor.talk_count == before_count,"second refused retry cannot publish or duplicate completion")
		await _capture("refused")
		_check(DirAccess.remove_absolute(store.path+".tmp") == OK,"remove only the owned empty write obstruction")
		_prompt().get("retry_button").pressed.emit()
		await _drive_dialogue()
	await _until(func() -> bool: return not Story.is_cinematic_active() and not GameplayLock.is_locked() and not actor._talking)
	_check(_settled() and actor.talk_count == expected_before+1,"only successful original completion publishes its flags and one counter increment")
	_check(starts.count(target) == (0 if action.ends_with("read") else 1),"retry and cold resume do not replay the original counter presentation")
	var history: Array = Story.progress_snapshot().map(func(id: Variant) -> String: return String(id))
	_check(history.count(String(target)) == 1,"original completion history remains exactly once")
	_check(GameState.deaths == 0 and not GameState.has_flag(&"ch1_first_death_done"),"finishing the tutorial story never consumes the first genuine clinic")
	await _capture("complete")
	_main.call("_save_run")
	var saved := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
	_check(saved.has("data") and saved["data"]["cinematic"].is_empty(),"final original Main primary has no stale unread target")
	await _finish()

func _observe(id: StringName, kind: StringName) -> void:
	starts.append(id)
	if action == "retry":
		super._inject(id,kind)
		if faulted and id == target:
			FileAccess.open(_directory.path_join("refused-primary.json"),FileAccess.WRITE).store_buffer(original)

func _settled() -> bool:
	return GameState.has_flag(&"ch1_prologue_done") and GameState.has_flag(&"ch1_prologue_exit") if phase == "call" else GameState.has_flag(&"ch1_prologue_service_heard")

func _drive_dialogue() -> void:
	var deadline := Time.get_ticks_msec()+30000
	while Story.is_cinematic_active() and _prompt() == null and Time.get_ticks_msec() < deadline:
		if action == "skip":
			Story.skip_cinematic()
		elif Story._layer.is_cinematic_active():
			Story._layer.advance()
		await _frames(1)

func _actor() -> NpcActor:
	if not is_instance_valid(_main) or not _main.get("_screen") is Level:
		return null
	for node: Node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and node.data.resource_path == COUNTER and (_main.get("_screen") as Level).is_ancestor_of(node):
			return node
	return null

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if label == "pending" and Story._layer.is_cinematic_active():
		Story._layer.advance()
	await _frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out)
	preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(out.path_join(label+".png"))

func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var actor := _actor()
	FileAccess.open(out.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"mode":_mode,"checks":_checks,"failures":Array(_failures),"target":String(target),"talks":actor.talk_count if actor != null else -1,"flags":GameState.world_flags,"current":String(Story._current_cinematic),"deaths":GameState.deaths},"  "))
	_main.call("_quit",0 if _failures.is_empty() else 1)
