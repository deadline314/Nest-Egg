extends "res://tests/probes/channel_completion.gd"
## Arranged prior briefing, card and position; real NPC/input, not a chapter playthrough.
const TARGET := &"ch2_t_s05_gate"
func _ready() -> void:
	super._ready()
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch2_heron"))
var _store: RunSaveStore
var _publications := 0
func _run() -> void:
	_main=load("res://game/main.gd").new()
	var store:=RunSaveStore.new(_save_dir.path_join("slot.json"))
	_main.set("_run_store",store)
	_store=store
	add_child(_main)
	await _frames(8)
	if _mode.ends_with("_read"):
		_main.call("_on_continue_requested")
		await _frames(12)
		var original:=_patroller()
		var accepted:=_mode=="accepted_read"
		_check(original!=null and _level().data.id==&"ch2_market_gate","cold primary restores the original chapter-two actor and area")
		_check(GameState.has_flag(&"ch2_gate_checked")==accepted and Story._completed.has(TARGET)==accepted,"cold result and history agree with the accepted original primary")
		_check(original!=null and original.talk_count==int(accepted),"cold original actor counter settles exactly once")
		_check(_prompt()==null and not get_tree().paused,"cold read has no stale result prompt")
		await _shot("patroller-cold")
		await _done()
		return
	_main.call("_on_start_requested",GameState.difficulties[1])
	await _frames(90)
	await _finish_story()
	await _wait_control()
	_main.call("_on_area_requested","res://data/levels/ch2_market_gate.tres")
	await _frames(12)
	await _finish_story()
	await _wait_control()
	# Explicit prior briefing/card and position fixture; not a chapter playthrough.
	GameState.set_flag(&"ch2_brief_done",true,false)
	StoryItems.acquire(&"ch2_check_card",false)
	var npc: NpcActor
	for node in _level()._entities.get_children():
		if node is NpcActor and node.data.id==&"ch2_patroller":npc=node
	_check(npc!=null,"real Main owns the original authored second-chapter patroller")
	if npc==null:await _done();return
	_player().global_position=npc.global_position+Vector2(-32,0)
	_player().velocity=Vector2.ZERO
	_player().set_physics_process(false)
	await _frames(4)
	_check(Story.resolve_dispatch(npc.data.talks[0].scene)==TARGET and not GameState.has_flag(&"ch2_gate_checked"),"declared prior briefing routes the original actor to its real uncompleted check")
	_main.call("_save_run")
	_before=FileAccess.get_file_as_bytes(store.path)
	_check(not _before.is_empty() and DirAccess.make_dir_absolute(store.path+".tmp")==OK,"owned refusal follows an ordinary complete original primary")
	var starts: Array[StringName]=[]
	Story.scene_started.connect(func(id: StringName, _mode: StringName)->void: starts.append(id))
	var original_scene: Dictionary=Story._scenes[String(TARGET)].duplicate(true)
	if _mode=="choice":
		var scene: Dictionary=Story._scenes[String(TARGET)]
		scene["mode"]="animated"
		scene["overlay"]=true
		scene["steps"]=[{"do":"choice","text":"Declared corrupt-choice fixture","default":"inject","options":[{"id":"inject","text":"Attempt unregistered result","set_flags":{"ch2_gate_checked":true}},{"id":"leave","text":"Leave"}]}]
	if _mode=="contract":
		Story._scenes[String(TARGET)]["results"][0]["value"]=false
	if _mode=="duplicate":
		var duplicate:=NpcActor.new()
		duplicate.configure(npc.data,npc.cell)
		duplicate.position=npc.position
		_level()._entities.add_child(duplicate)
		duplicate.remove_from_group(WorldState.GROUP)
		npc=duplicate
		_check(not _level().npc_sources.has(npc),"same-resource same-cell duplicate is not an original authored actor")
	var before_count:=npc.talk_count
	GameState.flag_changed.connect(_observe)
	var done: Array[bool]=[false,false]
	var talk:=func()->void:
		done[1]=await Story.play(TARGET) if _mode=="direct" else await npc._talk()
		done[0]=true
	talk.call()
	var choice_attempted:=false
	for i in 1800:
		if done[0] or _prompt()!=null:break
		if _mode=="choice" and is_instance_valid(Story._player) and Story._player.choice_active():
			choice_attempted=true
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
	await _frames(4)
	if _mode=="choice":_check(choice_attempted,"actual injected choice was offered and selected through its real player")
	_check(starts.has(TARGET),"actual original NPC interaction presents the authored gate check")
	_check(not GameState.has_flag(&"ch2_gate_checked"),"refused real patroller result cannot publish its gate flag")
	_check(not Story._completed.has(TARGET),"refused patroller reading cannot become completed history")
	_check(npc.talk_count==before_count and (_mode in ["direct","duplicate","contract","choice"] or not done[0]),"refused result preserves actor count and genuine pending waiter")
	_check(FileAccess.get_file_as_bytes(store.path)==_before,"refused patroller result preserves exact whole original primary bytes")
	if not _mode in ["direct","duplicate","contract","choice"]:
		_check(_prompt()!=null and get_tree().paused,"refused original check owns a retryable presentation")
	await _shot("patroller-refused")
	if _mode in ["direct","duplicate","contract","choice"]:
		Story._scenes[String(TARGET)]=original_scene
		Story.reset_active_presentation(&"probe_invalid_source")
		await _frames(4)
		_check(not GameState.has_flag(&"ch2_gate_checked") and not Story._completed.has(TARGET),"unowned or altered scene cannot publish gate progress")
		_check(FileAccess.get_file_as_bytes(store.path)==_before,"invalid producer leaves exact original primary intact")
		DirAccess.remove_absolute(store.path+".tmp")
		await _done()
		return
	if _mode=="cancel":
		Story.reset_active_presentation(&"probe_cancel")
		await _frames(4)
		_check(done[0] and not done[1] and npc.talk_count==before_count,"reset returns the original waiter without accepting a check")
		_check(_prompt()==null and not get_tree().paused,"reset releases the original retry presentation")
		_check(FileAccess.get_file_as_bytes(store.path)==_before,"reset preserves exact original primary")
		DirAccess.remove_absolute(store.path+".tmp")
		await _done()
		return
	var prompt:=_prompt()
	if prompt!=null:prompt.retry_button.pressed.emit()
	await _frames(4)
	_check(_prompt()!=null and not done[0] and not GameState.has_flag(&"ch2_gate_checked"),"a second genuine writer refusal remains pending without a result")
	_check(DirAccess.remove_absolute(store.path+".tmp")==OK,"remove only the owned write obstruction")
	if _prompt()!=null:_prompt().retry_button.pressed.emit()
	await _frames(8)
	_check(done[0] and done[1] and npc.talk_count==before_count+1,"same original request settles once after successful retry")
	_check(_publications==1 and GameState.has_flag(&"ch2_gate_checked") and Story._completed.has(TARGET),"successful retry publishes one coherent gate result")
	_check(_prompt()==null and not get_tree().paused,"accepted check releases its prompt and pause")
	await _shot("patroller-accepted")
	await _done()
func _patroller() -> NpcActor:
	if _level()==null:return null
	for actor: NpcActor in _level().npc_sources:
		if is_instance_valid(actor) and actor.data.id==&"ch2_patroller":return actor
	return null
func _observe(id: StringName, value: Variant) -> void:
	if id!=&"ch2_gate_checked" or value!=true:return
	_publications+=1
	var npc:=_patroller()
	_check(npc!=null and npc._talking and npc._durable_completed and npc.talk_count==1,"first result observer sees durable actor settlement before waiter returns")
	var decoded:=RunSaveCodec.decode(FileAccess.get_file_as_string(_store.path))
	_check(decoded.has("data"),"publication observes original valid checksum without read repair")
	if not decoded.has("data") or npc==null:return
	var disk: Dictionary=decoded.data
	_check(disk.story.flags.get("ch2_gate_checked",false) and disk.story.seen.has(String(TARGET)),"first result observer sees durable flag and history")
	for world: Dictionary in [disk.runtime.world,disk.runtime.area.world,disk.state.area_states[String(_level().data.id)].world]:
		_check(world.get(npc.state_key(),{}).get("talks",-1)==1,"first observer sees the same actor count in every raw primary world")
	_check(not Story.play(TARGET,false),"reentrant presentation cannot replace a publishing result")
func _prompt() -> Control:
	var owner: Node=_main.get("_result_completion")
	return owner.get("_prompt") as Control if is_instance_valid(owner) else null
