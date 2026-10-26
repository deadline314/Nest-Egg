extends "res://tools/run_save_probe.gd"
## Original Main first death; no injected clinic flags, items or history.
const AREA := "res://data/levels/ch1_booth_alley.tres"
const ROOT := &"ch1_c09_wake"
const TRAY := &"ch1_t_clinic_tray_prompt"
const TARGETS := {"wake":ROOT,"look":&"ch1_t_clinic_cloth_look","take":&"ch1_t_clinic_cloth_take"}
var store: RunSaveStore
var output := ""
var target: StringName
var faulted := false
var skip_sent := false
var original := PackedByteArray()
var facts_before := PackedByteArray()
var starts: Array[String] = []

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	super._ready()

func _run() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = _mode != "pending_read"
	_main = MainScript.new()
	store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(5)
	if _mode == "pending_read":
		await _cold()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	if not await _until(func() -> bool: return _main.get("_screen") is Level and not _main.call("_route_pending")):
		await _finish()
		return
	await _frames(8)
	if not await _until(_idle):
		await _finish()
		return
	_main.call("_on_area_requested", AREA)
	if not await _until(func() -> bool: return _level() != null and _level().data.resource_path == AREA and _level().is_initialized() and not _main.call("_route_pending")):
		await _finish()
		return
	await _frames(8)
	if not await _until(_idle):
		await _finish()
		return
	_check(_death_watchers() == 1 and _level().is_inside_tree(), "exactly one current in-tree original Level owns the real death event")
	Story.auto_skip = false
	target = StringName(TARGETS.get(_mode, TRAY))
	_check(GameState.deaths == 0 and not GameState.has_flag(&"ch1_first_death_done") and not StoryItems.owns(&"ch1_grey_cloth"), "fresh original Main has no arranged death completion or grey cloth")
	Story.scene_started.connect(_started)
	var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"grunt_shot")
	lethal.ignore_invulnerability = true
	_level().player.health.take_damage(lethal)
	await _drive()
	if _mode == "pending_write":
		_check(starts.has(String(ROOT)) and GameState.deaths == 1 and _level().died and Story._current_cinematic == TRAY and _movie() != null and _movie().choice_active(), "actual first lethal damage reaches the original unread clinic tray menu")
		_main.call("_save_run")
		var raw := _primary()
		_check(raw.get("cinematic") == String(TRAY) and raw.get("runtime",{}).get("dead",false) and raw.get("story",{}).get("flags",{}).get("ch1_first_death_done",false), "actual Main saves its unread real first-clinic menu and settled death result")
		FileAccess.open(_directory.path_join("pending-primary.json"), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(store.path))
	else:
		await _frames(5)
		_check(GameState.deaths == 1, "one real lethal event registers exactly one first death")
		_check(faulted and starts.has(String(ROOT)), "actual first-death chain reaches the selected material boundary")
		_check(_facts() == facts_before, "genuine IO refusal cannot publish flags, item custody or completed history")
		_check(FileAccess.get_file_as_bytes(store.path) == original, "genuine IO refusal preserves exact previous primary bytes")
		_check(_prompt() != null and Story._current_cinematic == target and get_tree().paused, "refused first-clinic result retains its original segment and real retry modal")
		_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only the owned empty IO obstruction after recording refusal")
	await _finish()

func _cold() -> void:
	var raw := _primary()
	var pending: String = raw.get("cinematic", "")
	var before: Dictionary = raw.get("story", {}).get("flags", {})
	_check(pending == String(TRAY) and before.get("ch1_first_death_done",false) and not before.get("has_grey_cloth",false), "cold input is an original unread first-clinic primary, not arranged flags")
	_main.call("_on_continue_requested")
	if not await _until(func() -> bool: return _level() != null and _level().is_initialized() and not _main.call("_route_pending")):
		await _finish()
		return
	await _frames(30)
	# A real cold presentation retains its unread spoken line before the menu.
	# Advance that original dialogue with the same input as a player; the old
	# root-denied softlock has no movie and cannot reach this menu.
	var deadline := Time.get_ticks_msec() + 15000
	while Story._current_cinematic == StringName(pending) and _movie() != null and not _movie().choice_active() and Time.get_ticks_msec() < deadline:
		if _movie()._dialogue.visible:
			_movie()._dialogue.complete()
			_movie()._advance_requested = true
		await _frames(1)
	_check(Story._current_cinematic == StringName(pending) and _movie() != null and _movie().choice_active(), "actual cold continue restores the exact unread first-clinic menu without a dead-level softlock")
	_check(GameState.deaths == 1 and not StoryItems.owns(&"ch1_grey_cloth"), "cold continue does not repeat death or invent a cloth pickup")
	await _finish()

func _started(id: StringName, _kind: StringName) -> void:
	starts.append(String(id))
	if _mode != "pending_write" and id == target and not faulted:
		faulted = true
		original = FileAccess.get_file_as_bytes(store.path)
		FileAccess.open(_directory.path_join("refused-primary.json"), FileAccess.WRITE).store_buffer(original)
		facts_before = _facts()
		FileAccess.open(_directory.path_join("facts-before.bin"), FileAccess.WRITE).store_buffer(facts_before)
		FileAccess.open(_directory.path_join("flags-before.json"), FileAccess.WRITE).store_string(JSON.stringify(GameState.world_flags, "  "))
		_check(not original.is_empty() and DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "create genuine owned temporary-directory IO refusal at actual material boundary")

func _drive() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		var movie := _movie()
		if _mode == "pending_write" and Story._current_cinematic == TRAY and movie != null and movie.choice_active():
			return
		if faulted and (_prompt() != null or (skip_sent and Story._current_cinematic != target)):
			return
		if movie != null and movie.choice_active():
			var wanted := "look" if Story._current_cinematic == TRAY else "take"
			var index := movie._choice_options.find_custom(func(option: Dictionary) -> bool: return option.get("id") == wanted)
			_check(index >= 0 and movie.choose(index), "original authored clinic menu accepts " + wanted)
		elif faulted and not skip_sent and movie != null and movie.is_running():
			skip_sent = true
			Story.skip_cinematic()
		elif movie != null and movie.is_running() and movie._dialogue.visible:
			movie._dialogue.complete()
			movie._advance_requested = true
		elif Story._layer.is_cinematic_active():
			Story._layer.advance()
		await _frames(1)
	_check(false, "original first-clinic driver reaches bounded target")

func _idle() -> bool:
	return _level() != null and _level().is_initialized() and not _main.call("_route_pending") and not Story.is_cinematic_active() and not GameplayLock.is_locked() and not get_tree().paused and _death_watchers() == 1

func _death_watchers() -> int:
	var count := 0
	for connection: Dictionary in EventBus.player_died.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_object() is Level:
			count += 1
	return count

func _level() -> Level:
	return _main.get("_screen") as Level if is_instance_valid(_main) else null

func _movie() -> CutscenePlayer:
	return Story._player as CutscenePlayer if is_instance_valid(Story._player) else null

func _prompt() -> Control:
	return (_main.get("_result_completion") as Node).get("_prompt") as Control

func _facts() -> PackedByteArray:
	return var_to_bytes([GameState.world_flags, Story.progress_snapshot(), StoryItems.snapshot(), Progression.snapshot()])

func _primary() -> Dictionary:
	var decoded := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
	_check(decoded.has("data"), "read actual checksum-valid Main primary without re-encoding")
	return decoded.get("data", {})

func _until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await _frames(1)
	_check(predicate.call(), "original Main route settles within bounded time")
	return predicate.call()

func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var result := {"mode":_mode,"checks":_checks,"failures":Array(_failures),"starts":starts,"current":String(Story._current_cinematic),"deaths":GameState.deaths,"flags":GameState.world_flags.duplicate(true),"items":StoryItems.snapshot(),"history":Story.progress_snapshot(),"context_facts":Story.outcomes.context_facts.duplicate(true),"level_dead":_level().died if _level() != null else false}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("[ClinicOriginal] ", _mode, " checks=", _checks, " failures=", _failures.size())
	_main.call("_quit",0 if _failures.is_empty() else 1)
