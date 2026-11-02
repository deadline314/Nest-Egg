extends "res://tests/probes/channel_completion.gd"
## Original authored object interactions; arranged position, not a chapter playthrough.
const PRODUCERS := {
	"banyan": {"scene":&"ch2_t_s08_banyan","actor":&"ch2_banyan","level":"res://data/levels/ch2_market.tres","flag":&"ch2_banyan_heard"},
	"rumor": {"scene":&"ch2_t_s08_rumor","actor":&"ch2_hawker","level":"res://data/levels/ch2_market.tres","flag":&"ch2_rumor_heard"},
	"guard": {"scene":&"ch2_t_s09_guard","actor":&"ch2_guard","level":"res://data/levels/ch2_loading.tres","flag":&"ch2_guard_seen"},
	"bridge": {"scene":&"ch2_t_s09_lever","actor":&"ch2_sc1_lever","level":"res://data/levels/ch2_loading.tres","flag":&"ch2_sc1_open"},
}
var _producer := "banyan"
var _definition: Dictionary
var _store: RunSaveStore
var _original_facts := PackedByteArray()
var _flag_notices := 0
var _events: Array[Dictionary] = []
func _ready() -> void:
	super._ready()
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch2_heron"))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--producer="): _producer=arg.trim_prefix("--producer=")
	if _mode.contains("--"):
		_producer=_mode.get_slice("--",0)
		_mode=_mode.get_slice("--",1)
	_definition=PRODUCERS.get(_producer,{})
func _run() -> void:
	_check(not _definition.is_empty(),"declared original reading producer exists")
	_check(_mode in ["accepted","accepted_read","cancel","cancel_read","stale","contract","duplicate"],"declared reading probe mode is supported")
	if _definition.is_empty() or not _mode in ["accepted","accepted_read","cancel","cancel_read","stale","contract","duplicate"]:get_tree().quit(2);return
	_main=load("res://game/main.gd").new()
	_store=RunSaveStore.new(_save_dir.path_join("slot.json"))
	_main.set("_run_store",_store)
	add_child(_main)
	await _frames(8)
	if _mode.ends_with("_read"):
		_main.call("_on_continue_requested")
		await _frames(12)
		var original:=_reading_actor()
		var accepted:=_mode=="accepted_read"
		_check(original!=null and _level().data.resource_path==_definition.level,"cold original primary restores its original area and reading object")
		_check(GameState.has_flag(_definition.flag)==accepted and Story._completed.has(_definition.scene)==accepted,"cold flag, custody and completion match the accepted original result")
		_check(original!=null and original.talk_count==int(accepted),"cold original actor counter settles exactly once")
		_check(_prompt()==null and not get_tree().paused,"cold read leaves no stale presentation prompt")
		_check_bridge(accepted)
		await _shot(_producer+"-cold")
		await _done()
		return
	_main.call("_on_start_requested",GameState.difficulties[1])
	await _frames(90)
	await _finish_story()
	await _wait_control()
	_main.call("_on_area_requested",_definition.level)
	await _frames(12)
	await _finish_story()
	await _wait_control()
	var npc:=_reading_actor()
	_check(npc!=null,"real Main owns the original authored reading object")
	if npc==null:await _done();return
	_player().global_position=npc.global_position+Vector2(-32,0)
	_player().velocity=Vector2.ZERO
	_player().set_physics_process(false)
	_level().camera.snap_to_target() # The arranged teleport uses the original respawn camera path.
	await _frames(4)
	_check(Story.resolve_dispatch(npc.data.talks[0].scene)==_definition.scene,"actual dispatcher offers the original unread reading")
	_check(not GameState.has_flag(_definition.flag),"reading result is genuinely absent before its original reading")
	_check_bridge(false)
	_main.call("_save_run")
	_before=FileAccess.get_file_as_bytes(_store.path)
	_original_facts=_facts()
	_check(not _before.is_empty() and DirAccess.make_dir_absolute(_store.path+".tmp")==OK,"real IO refusal follows a complete original primary")
	var starts: Array[StringName]=[]
	Story.scene_started.connect(func(id: StringName,_kind: StringName)->void:starts.append(id))
	GameState.flag_changed.connect(_observe_flag)
	var original_scene: Dictionary=Story._scenes[String(_definition.scene)].duplicate(true)
	if _mode=="contract":
		Story._scenes[String(_definition.scene)]["results"][0]["id"]="ch1_flood_gate_open"
	if _mode=="duplicate":
		var duplicate:=NpcActor.new()
		duplicate.configure(npc.data,npc.cell)
		duplicate.position=npc.position
		_level()._entities.add_child(duplicate)
		duplicate.remove_from_group(WorldState.GROUP)
		npc=duplicate
		_check(not _level().npc_sources.has(npc),"same-resource same-cell reading duplicate is not an authored source")
	var count:=npc.talk_count
	var done: Array[bool]=[false,false]
	var talk:=func()->void:
		done[1]=await npc._talk()
		done[0]=true
	talk.call()
	await _drive_reading(done)
	await _frames(4)
	_check(starts.has(_definition.scene),"real object interaction presents the authored reading scene")
	_check(not GameState.has_flag(_definition.flag) and not Story._completed.has(_definition.scene),"refused reading cannot publish its flag or history")
	_check(_facts()==_original_facts,"refused reading preserves all original flags, custody and completion facts")
	_check(npc.talk_count==count and (_mode in ["contract","duplicate"] or not done[0]),"refused reading preserves its counter and genuine pending waiter")
	_check(_flag_notices==0,"refused reading has no premature result notifications")
	_check(FileAccess.get_file_as_bytes(_store.path)==_before,"refused reading preserves exact complete original primary bytes")
	if not _mode in ["contract","duplicate"]:
		_check(_prompt()!=null and get_tree().paused,"real failed reading retains its retryable presentation")
	_check_bridge(false)
	await _shot(_producer+"-refused")
	if _mode in ["contract","duplicate"]:
		Story._scenes[String(_definition.scene)]=original_scene
		Story.reset_active_presentation(&"probe_invalid_source")
		await _frames(4)
		_check(not GameState.has_flag(&"ch1_flood_gate_open") and _facts()==_original_facts,"altered or duplicate producer cannot grant a different declared flag or any partial result")
		_check(FileAccess.get_file_as_bytes(_store.path)==_before,"invalid reading producer retains exact original primary")
		DirAccess.remove_absolute(_store.path+".tmp")
		await _done()
		return
	if _mode=="cancel":
		Story.reset_active_presentation(&"probe_cancel")
		await _frames(4)
		_check(done[0] and not done[1] and npc.talk_count==count,"cancel returns the original waiter without settling the reading")
		_check(_facts()==_original_facts and FileAccess.get_file_as_bytes(_store.path)==_before,"cancel preserves all original facts and exact primary")
		_check(_prompt()==null and not get_tree().paused,"cancel releases the reading prompt and pause")
		DirAccess.remove_absolute(_store.path+".tmp")
		await _done()
		return
	if _mode=="stale":
		_level().npc_sources.erase(npc)
		_check(DirAccess.remove_absolute(_store.path+".tmp")==OK,"remove only owned IO obstruction before stale-source retry")
		if _prompt()!=null:_prompt().retry_button.pressed.emit()
		await _frames(4)
		_check(_prompt()!=null and _main.get("_result_completion").get("_reload_original"),"stale original source offers whole-original recovery")
		_check(_facts()==_original_facts and FileAccess.get_file_as_bytes(_store.path)==_before,"stale-source retry cannot accept partial reading")
		if _prompt()!=null:_prompt().retry_button.pressed.emit()
		await _frames(12)
		var restored:=_reading_actor()
		_check(restored!=null and restored.talk_count==count and not GameState.has_flag(_definition.flag),"whole-original recovery reconstructs the unaccepted original reading")
		_check(_prompt()==null and not get_tree().paused,"original recovery clears its pending presentation")
		await _done()
		return
	if _prompt()!=null:_prompt().retry_button.pressed.emit()
	await _frames(4)
	_check(_facts()==_original_facts and not done[0] and _prompt()!=null,"second genuine writer refusal keeps the same original interaction pending")
	_check(DirAccess.remove_absolute(_store.path+".tmp")==OK,"remove only the owned obstruction for successful retry")
	if _prompt()!=null:_prompt().retry_button.pressed.emit()
	await _frames(8)
	_check(done[0] and done[1] and npc.talk_count==count+1,"successful retry settles the same original reading interaction exactly once")
	_check(_flag_notices==1 and GameState.has_flag(_definition.flag) and Story._completed.has(_definition.scene),"one accepted result publishes exactly one flag notification")
	_check(_prompt()==null and not get_tree().paused,"accepted reading releases its prompt and pause")
	_check_bridge(true)
	await _shot(_producer+"-accepted")
	await _done()
func _reading_actor() -> NpcActor:
	if _level()==null:return null
	for actor: NpcActor in _level().npc_sources:
		if is_instance_valid(actor) and actor.data.id==_definition.actor:return actor
	return null
func _facts() -> PackedByteArray:
	return var_to_bytes([GameState.world_flags,StoryItems.snapshot(),Story.progress_snapshot()])
func _drive_reading(done: Array[bool]) -> void:
	for i in 1800:
		if done[0] or _prompt()!=null:return
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
	_check(false,"original reading reaches completion or explicit refusal within its frame guard")
func _observe_flag(id: StringName,value: Variant) -> void:
	if id!=_definition.flag or value!=true:return
	_flag_notices+=1
	_observe_coherent("flag")
	_check_bridge(true,false)
func _observe_coherent(event: String) -> void:
	var npc:=_reading_actor()
	_check(npc!=null and npc._talking and npc._durable_completed and npc.talk_count==1,"first result observers see durable original actor settlement before the waiter returns")
	_check(GameState.has_flag(_definition.flag) and Story._completed.has(_definition.scene),"every result observer sees all installed live reading facts")
	var raw:=FileAccess.get_file_as_string(_store.path)
	var decoded:=RunSaveCodec.decode(raw)
	_check(decoded.has("data"),"publication primary has its original valid checksum without reader repair")
	if not decoded.has("data") or npc==null:return
	var disk: Dictionary=decoded.data
	_check(disk.story.flags.get(String(_definition.flag),false) and disk.story.seen.has(String(_definition.scene)),"every observer sees flag and history in the complete original disk primary")
	var counts: Array=[]
	for world: Dictionary in [disk.runtime.world,disk.runtime.area.world,disk.state.area_states[String(_level().data.id)].world]:
		var count: Variant=world.get(npc.state_key(),{}).get("talks",-1)
		counts.append(count)
		_check(count==1,"every observer sees the same actor counter in all three raw primary worlds")
	var filename:=_producer+"-"+event+"-"+str(_events.size())+"-primary.json"
	var file:=FileAccess.open(_out.path_join(filename),FileAccess.WRITE)
	_check(file!=null,"raw publication primary can be preserved in the isolated reading directory")
	if file!=null:
		file.store_string(raw)
		file.close()
	_events.append({"event":event,"talks":npc.talk_count,"world_counts":counts,"primary":filename})
func _prompt() -> Control:
	var owner: Node=_main.get("_result_completion")
	return owner.get("_prompt") as Control if is_instance_valid(owner) else null

func _done() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var file:=FileAccess.open(_out.path_join("result.json"),FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"mode":_mode,"producer":_producer,"checks":_checks,"failures":_issues,"publications":_events},"  "))
		file.close()
	else:
		_check(false,"isolated result receipt is writable")
	Story.reset_active_presentation(&"menu")
	_main.call("_quit",0 if _issues.is_empty() else 1)

func _check_bridge(accepted: bool, visual := true) -> void:
	if _producer!="bridge":return
	var level:=_level()
	_check(level!=null,"bridge outcome has the original live Main Level")
	if level==null:return
	var found:=0
	for portal: Portal in level._portals.values():
		if portal.data.requires_flag==&"ch2_sc1_open":
			found+=1
			_check(portal.is_open()==accepted,"original bridge shortcut eligibility agrees with the accepted result")
	_check(found>0,"actual authored bridge shortcut exists in the original area")
	if not visual:return
	var reaction: PropReaction
	for node: Node in level.find_children("Reaction_bridge_ladder","Node",true,false):
		if node is PropReaction:reaction=node
	_check(reaction!=null,"original folded/down bridge prop reaction exists")
	if reaction!=null:
		_check(reaction._swapped==accepted and reaction._swap_node!=null and reaction._swap_node.visible==accepted,"original bridge prop shows folded versus down according to the accepted result")
