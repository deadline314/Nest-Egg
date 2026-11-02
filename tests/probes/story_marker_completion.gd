extends "res://tests/probes/ch2_reading_completion.gd"
## Real original NPC interactions with declared metadata damage, then original recovery.
const MARKER_SOURCES := {
	"label": {"scene":&"ch1_t_label_watch","actor":&"ch1_label_watch","level":"res://data/levels/ch1_pawnshop.tres","flag":&"ch1_label_watch_seen"},
	"gate": {"scene":&"ch2_t_s05_gate","actor":&"ch2_patroller","level":"res://data/levels/ch2_market_gate.tres","flag":&"ch2_gate_checked"},
	"item": {"scene":&"ch2_t_s08_contract","actor":&"ch2_rent_window","level":"res://data/levels/ch2_market.tres","flag":&"ch2_evidence_contract","item":&"ch2_evidence_contract"},
}
var _item_notices := 0
var _bad_choice_selected := false
func _ready() -> void:
	super._ready()
	_definition=MARKER_SOURCES.get(_producer,{})
func _has_item() -> bool:
	return not String(_definition.get("item","")).is_empty()
func _run() -> void:
	_check(not _definition.is_empty(),"declared original protected producer exists")
	if _definition.is_empty():get_tree().quit(2);return
	_main=load("res://game/main.gd").new()
	_store=RunSaveStore.new(_save_dir.path_join("slot.json"))
	_main.set("_run_store",_store)
	add_child(_main)
	await _frames(8)
	if _mode.ends_with("_read"):
		_main.call("_on_continue_requested")
		await _frames(12)
		var original:=_reading_actor()
		_check(original!=null and _level().data.resource_path==_definition.level,"cold accepted original restores its actual source area and actor")
		_check(GameState.has_flag(_definition.flag) and Story._completed.has(_definition.scene),"cold read restores only the genuinely accepted result and history")
		_check(original!=null and original.talk_count==1,"cold read restores one original actor settlement")
		if _has_item():_check(StoryItems.holds(_definition.item),"cold accepted item custody is preserved")
		_check(_prompt()==null and not get_tree().paused,"cold read has no damaged-presentation lock")
		await _shot(_producer+"-cold")
		await _done()
		return
	_check(_mode in ["missing","shifted","malformed","missing_choice","intact"],"supported marker corruption fixture")
	if not _mode in ["missing","shifted","malformed","missing_choice","intact"]:get_tree().quit(2);return
	_main.call("_on_start_requested",GameState.difficulties[1])
	await _frames(90)
	await _finish_story()
	await _wait_control()
	_main.call("_on_area_requested",_definition.level)
	await _frames(12)
	await _finish_story()
	await _wait_control()
	if _producer=="gate":
		GameState.set_flag(&"ch2_brief_done",true,false)
		StoryItems.acquire(&"ch2_check_card",false)
	var npc:=_reading_actor()
	_check(npc!=null,"real Main owns the actual original protected actor")
	if npc==null:await _done();return
	_player().global_position=npc.global_position+Vector2(-32,0)
	_player().velocity=Vector2.ZERO
	_player().set_physics_process(false)
	_level().camera.snap_to_target()
	await _frames(4)
	_check(Story.resolve_dispatch(npc.data.talks[0].scene)==_definition.scene,"original dispatcher offers its actual unread protected scene")
	_check(not GameState.has_flag(_definition.flag) and not Story._completed.has(_definition.scene),"protected result and history are genuinely absent")
	if _has_item():_check(not StoryItems.owns(_definition.item),"protected item has never been granted")
	_main.call("_save_run")
	_before=FileAccess.get_file_as_bytes(_store.path)
	_original_facts=_facts()
	_check(not _before.is_empty(),"ordinary writer establishes a complete original primary before any metadata damage")
	var original_scene: Dictionary=Story._scenes[String(_definition.scene)].duplicate(true)
	var scene: Dictionary=Story._scenes[String(_definition.scene)]
	match _mode:
		"missing":scene.erase("completion_policy")
		"shifted":scene["completion_policy"]="main_flags_v1"
		"malformed":scene["completion_policy"]={"unsupported":"policy"}
		"missing_choice":
			scene.erase("completion_policy")
			scene["mode"]="animated"
			scene["overlay"]=true
			scene["steps"]=[{"do":"choice","text":"Declared metadata-loss choice fixture","default":"inject","options":[{"id":"inject","text":"Attempt unregistered result","set_flags":{String(_definition.flag):true}},{"id":"leave","text":"Leave"}]}]
	var io_fault:=_mode in ["intact","missing_choice"]
	if io_fault:_check(DirAccess.make_dir_absolute(_store.path+".tmp")==OK,"owned IO obstruction controls ordinary saves while the fixture resets")
	GameState.flag_changed.connect(_observe_flag)
	StoryItems.acquired.connect(_observe_item)
	var done: Array[bool]=[false,false]
	var talk:=func()->void:
		done[1]=await npc._talk()
		done[0]=true
	talk.call()
	await _frames(2)
	# Main legitimately saves the unread cinematic entry before its result.
	_before=FileAccess.get_file_as_bytes(_store.path)
	await _drive_marker(done)
	await _frames(4)
	_check(_facts()==_original_facts and npc.talk_count==0,"bad metadata or refused IO cannot mutate any original result or actor counter")
	_check(_flag_notices==0 and _item_notices==0,"unaccepted protected source has no result notifications")
	_check(FileAccess.get_file_as_bytes(_store.path)==_before,"refusal preserves exact complete original primary bytes")
	if _mode=="missing_choice":
		_check(_bad_choice_selected and done[0] and not done[1],"real unregistered choice is selected but cannot complete its original actor")
		_check(_prompt()==null and not get_tree().paused,"refused unregistered choice returns without a stuck save UI")
	else:
		_check(not done[0] and _prompt()!=null and get_tree().paused,"actual protected source retains its original waiter and owned prompt")
		_check(_main.get("_story_completion").get("_prompt")==null,"damaged terminal never falls through to a different flag owner")
		_check(bool(_main.get("_result_completion").get("_reload_original"))==(_mode!="intact"),"semantic metadata damage requires original recovery while genuine IO remains retryable")
	await _shot(_producer+"-"+_mode+"-refused")
	Story._scenes[String(_definition.scene)]=original_scene
	if io_fault:_check(DirAccess.remove_absolute(_store.path+".tmp")==OK,"remove only the owned obstruction after refusal evidence")
	if _mode=="intact":
		if _prompt()!=null:_prompt().retry_button.pressed.emit()
		await _drive_marker(done)
	else:
		if _mode!="missing_choice":
			if _prompt()!=null:_prompt().retry_button.pressed.emit()
			await _frames(12)
			_check(done[0] and not done[1],"original recovery returns the rejected original actor waiter")
			npc=_reading_actor()
			_check(npc!=null and npc.talk_count==0 and _facts()==_original_facts,"whole-original recovery restores the real unaccepted actor and all progress")
			_check(_prompt()==null,"original recovery releases its damaged-result prompt")
			await _drive_marker([false,false])
			await _frames(8)
			done=[true,GameState.has_flag(_definition.flag)]
		if npc==null:await _done();return
		_player().set_physics_process(false)
		if _mode=="missing_choice":
			done=[false,false]
			var repaired:=func()->void:
				done[1]=await npc._talk()
				done[0]=true
			repaired.call()
			await _drive_marker(done)
	await _frames(8)
	_check(done[0] and done[1] and npc.talk_count==1,"corrected original source completes exactly once after recovery or retry")
	_check(_flag_notices==1 and _item_notices==int(_has_item()),"only the real accepted request publishes its expected results")
	_check(GameState.has_flag(_definition.flag) and Story._completed.has(_definition.scene),"accepted original flag and history are installed together")
	if _has_item():_check(StoryItems.holds(_definition.item),"accepted original item is installed with the flag and history")
	_check(_prompt()==null and not get_tree().paused,"accepted corrected source releases its original UI and lock")
	await _shot(_producer+"-"+_mode+"-accepted")
	await _done()
func _drive_marker(done: Array[bool]) -> void:
	for i in 1800:
		if done[0] or _prompt()!=null or Story._current_cinematic==&"":return
		if is_instance_valid(Story._player) and Story._player.choice_active():
			_bad_choice_selected=true
			Story._player.choose(0)
			await _frames(1)
			continue
		var event:=InputEventAction.new()
		event.action=&"ui_accept"
		event.pressed=true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		event=event.duplicate()
		event.pressed=false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(1)
	_check(false,"protected original reading settles or refuses within its frame guard")
func _observe_item(item: StoryItemData) -> void:
	if not _has_item() or item.id!=_definition.item:return
	_item_notices+=1
	_observe_coherent("item")
func _observe_coherent(event: String) -> void:
	super._observe_coherent(event)
	if not _has_item():return
	_check(StoryItems.holds(_definition.item),"first protected item observer sees actual installed live custody")
	var decoded:=RunSaveCodec.decode(FileAccess.get_file_as_string(_store.path))
	_check(decoded.has("data") and decoded.get("data",{}).get("story",{}).get("items",{}).get("held",[]).has(String(_definition.item)),"every protected observer sees the same original item in the complete disk primary")
