extends "res://tests/probes/clinic_original.gd"
## Real first death and original menus; no arranged clinic flags or item custody.
const Clinic := preload("res://game/story_result_clinic.gd")
const PHASES := {"wake":Clinic.ROOT,"tray":Clinic.TRAY,"look":Clinic.LOOK,"decide":Clinic.DECIDE,"take":Clinic.TAKE,"leave":Clinic.LEAVE,"missing":Clinic.MISSING}
var action := ""
var phase := ""
var wallet_before := 0
var item_events := 0

func _run() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	action = _mode.get_slice("_",0)
	phase = _mode.get_slice("_",1)
	target = StringName(PHASES.get(phase,Clinic.TAKE))
	Story.auto_skip = action != "read"
	_main = MainScript.new()
	store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store",store)
	add_child(_main)
	await _frames(5)
	StoryItems.acquired.connect(func(item: StoryItemData) -> void:
		if item.id == &"ch1_grey_cloth":
			item_events += 1)
	if action == "read":
		var raw := _primary()
		wallet_before = int(raw.get("progression",{}).get("credits",-1))
		_check(raw.get("cinematic") == String(target) and raw.get("runtime",{}).get("dead",false),"reader uses exact original pending death envelope")
		_main.call("_on_continue_requested")
		await _until(func() -> bool: return _level() != null and _level().is_initialized() and not _main.call("_route_pending"))
		await _until(func() -> bool: return Story._current_cinematic == target and _movie() != null)
		_check(GameState.deaths == 1 and Story.outcomes.context_facts.get("first_clinic",false),"cold reader restores owned transient context without registering another death")
	else:
		_main.call("_on_start_requested",GameState.difficulties[1])
		await _until(func() -> bool: return _level() != null and not _main.call("_route_pending"))
		await _frames(8)
		await _until(_idle)
		_main.call("_on_area_requested",AREA)
		await _until(func() -> bool: return _level() != null and _level().data.resource_path == AREA and _level().is_initialized() and not _main.call("_route_pending"))
		await _frames(8)
		await _until(_idle)
		_check(_death_watchers() == 1 and GameState.deaths == 0 and not GameState.has_flag(&"ch1_first_death_done"),"fresh genuine Level exclusively owns its first death")
		Story.auto_skip = false
		wallet_before = Progression.credits
		Story.scene_started.connect(_started)
		var lethal := DamageInfo.create(9999,Combat.Team.ENEMY,&"grunt_shot")
		lethal.ignore_invulnerability = true
		_level().player.health.take_damage(lethal)
	if action in ["write","cancel"]:
		await _advance_to_target()
		_check(Story._current_cinematic == target and _movie() != null and _movie()._dialogue.visible,"actual authored path reaches its original unread target")
		_main.call("_save_run")
		var bytes := FileAccess.get_file_as_bytes(store.path)
		var raw := _primary()
		_check(raw.get("cinematic") == String(target) and raw.get("runtime",{}).get("dead",false),"actual Main saves the exact unread first-clinic target")
		_check(not raw.get("story",{}).get("flags",{}).has("ch1_first_clinic_active"),"request context is never serialized as a world flag")
		FileAccess.open(_directory.path_join("pending-primary.json"),FileAccess.WRITE).store_buffer(bytes)
		await _capture("pending")
		if action == "cancel":
			_main.call("_show_main_menu")
			await _frames(8)
			_check(not Story.is_cinematic_active() and Story.outcomes.context_facts.is_empty() and Story._context_request == 0,"actual menu exit cancels its request and releases all clinic context")
			_check(FileAccess.get_file_as_bytes(store.path) == bytes and not StoryItems.owns(&"ch1_grey_cloth"),"cancel preserves original unread primary and grants no cloth")
		await _finish()
		return
	if action == "retry":
		await _advance_to_refusal()
		_check(faulted and _prompt() != null and _facts() == facts_before and FileAccess.get_file_as_bytes(store.path) == original,"real IO refusal holds all services and exact previous primary")
		if _prompt() == null:
			await _finish()
			return
		_prompt().get("retry_button").pressed.emit()
		await _frames(4)
		_check(_prompt() != null and _facts() == facts_before and FileAccess.get_file_as_bytes(store.path) == original,"second real refused retry cannot leak or duplicate results")
		await _capture("refused")
		_check(DirAccess.remove_absolute(store.path+".tmp") == OK,"remove only this process's actual empty IO obstruction")
		_prompt().get("retry_button").pressed.emit()
	await _advance_to_end()
	_check(_recovered() and GameState.deaths == 1,"original free first-death recovery returns to a live playable Level exactly once")
	_check(Progression.credits == wallet_before,"first clinic and cold retry never charge another restoration fee")
	var takes := phase == "take" and action != "skip"
	_check(StoryItems.owns(&"ch1_grey_cloth") == takes and GameState.has_flag(&"has_grey_cloth") == takes,"only the real selected completed cloth segment grants its original item")
	_check(item_events == (1 if takes else 0),"item acquisition publishes exactly once across retry and cold continuation")
	_check(Story.outcomes.context_facts.is_empty() and Story._context_request == 0,"completed death chain releases transient request context")
	_check(GameState.has_flag(&"ch1_first_death_done"),"completed first death retains its durably registered result")
	if action == "retry":
		_check(starts.count(String(target)) == 1,"retry saves the same completed segment without replaying its presentation")
	if action == "skip":
		_check(not starts.has(Clinic.TRAY if phase == "wake" else Clinic.DECIDE),"manual skip retains original close-here behavior without forcing optional choices")
	await _capture("complete")
	_main.call("_save_run")
	var final := _primary()
	_check(not final.get("runtime",{}).get("dead",true) and final.get("cinematic","invalid").is_empty(),"final Main primary is playable with no stale first-clinic continuation")
	await _finish()

func _started(id: StringName, _kind: StringName) -> void:
	starts.append(String(id))
	if action != "retry" or id != target or faulted:
		return
	faulted = true
	original = FileAccess.get_file_as_bytes(store.path)
	facts_before = _facts()
	FileAccess.open(_directory.path_join("refused-primary.json"),FileAccess.WRITE).store_buffer(original)
	_check(not original.is_empty() and DirAccess.make_dir_absolute(store.path+".tmp") == OK,"create genuine owned write obstruction at the exact original producer")

func _advance_to_target() -> void:
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec() < deadline:
		if Story._current_cinematic == target and _movie() != null and _movie()._dialogue.visible:
			return
		_step()
		await _frames(1)
	_check(false,"original authored route reaches its pending target within bounded time")

func _advance_to_refusal() -> void:
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec() < deadline and _prompt() == null:
		_step()
		await _frames(1)
	_check(_prompt() != null,"original real result reaches its actual IO retry modal")

func _advance_to_end() -> void:
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec() < deadline and not _recovered():
		if _prompt() != null:
			_check(false,"unobstructed original result must not enter a retry modal")
			return
		_step()
		await _frames(1)

func _step() -> void:
	var movie := _movie()
	if movie == null or not movie.is_running():
		return
	if action == "skip" and Story._current_cinematic == target and not skip_sent:
		skip_sent = true
		Story.skip_cinematic()
	elif movie.choice_active():
		var tray := Story._current_cinematic == StringName(Clinic.TRAY)
		var wanted := "look" if tray else "take" if phase == "take" else "leave"
		if tray and (phase == "leave" or (action == "read" and phase != "take")):
			wanted = "leave"
		if phase == "missing" and tray and action != "read":
			wanted = "backup"
		var index := movie._choice_options.find_custom(func(option: Dictionary) -> bool: return option.get("id") == wanted)
		_check(index >= 0 and movie.choose(index),"original clinic menu accepts "+wanted)
	elif movie._dialogue.visible:
		movie._dialogue.complete()
		movie._advance_requested = true

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(output.path_join(label+".png"))

func _recovered() -> bool:
	return _idle() and not _level().died and not _level().player.is_dead()
