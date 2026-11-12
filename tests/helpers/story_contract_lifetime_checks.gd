extends RefCounted
const Owner := preload("res://game/story_result_completion.gd")
const Sources := preload("res://game/story_result_sources.gd")
class Host extends Node:
	var _screen: Node
	var _active_run := true
	var _level_path := "res://data/levels/ch2_market_gate.tres"
class QuietLevel extends Level:
	func _ready() -> void: pass
class QuietPlayer extends Player:
	func _ready() -> void: pass

static func run(s: TestSuite) -> void:
	var host := Host.new()
	var owner := Owner.new()
	owner.main = host
	var facts := var_to_bytes([GameState.world_flags,Progression.snapshot(),StoryItems.snapshot(),Story.progress_snapshot()])
	var original_cinematic := Story._current_cinematic
	var original_request := Story._current_request
	Story._current_cinematic = &"test_bad_cutscene_retired_host"
	var level := QuietLevel.new()
	level.set_process(false);level.set_physics_process(false)
	s.runner.add_child(level);host._screen = level
	level.queue_free()
	var queued := owner.complete(&"test_bad_cutscene_retired_host",7)
	s.check(queued.get("handled",false) and not queued.get("ready",true),"queued host cannot enter a story result writer")
	while is_instance_valid(level): await s.runner.get_tree().process_frame
	for active: bool in [false,true]:
		host._active_run = active
		var completed := owner.complete(&"test_bad_cutscene_retired_host",7)
		var chosen := owner.choose({},Callable())
		s.check(completed.get("handled",false) and not completed.get("ready",true),"actual freed host completion refuses before fallback")
		s.check(chosen.get("handled",false) and not chosen.get("accepted",true),"actual freed host choice refuses before fallback")
	var id := "ch2_t_s05_gate"
	s.check(Sources.inspect(id,Story._scenes,Story._scene_sources)["state"] == Sources.Catalog.MATCH,"lifetime regression starts with actual original MATCH content")
	owner._id = StringName(id);owner._request = 7;owner._contract_revision = Sources.revision()
	s.check(owner._prepare_and_commit(Story._scenes[id]).has("error"),"even a MATCH request rechecks host lifetime before preparation")
	var alive := QuietLevel.new()
	alive.set_process(false);alive.set_physics_process(false)
	alive.data = load(host._level_path)
	alive.set("_initialization_complete",true)
	s.runner.add_child(alive);host._screen = alive
	var entities := Node2D.new();alive.add_child(entities);alive.set("_entities",entities)
	var player := QuietPlayer.new();player.melee.free();player.melee = null
	player.set_process(false);player.set_physics_process(false)
	s.runner.add_child(player);alive.player = player
	Story._current_cinematic = StringName(id);Story._current_request = 7
	var context := Story._presentation_context.duplicate(true)
	Story._presentation_context = {"framing_source":"person","source_id":"test_bad_cutscene_retired_host","talk_index":0}
	player.queue_free()
	while is_instance_valid(player): await s.runner.get_tree().process_frame
	s.check(owner._npc_origin(alive,StringName(id),7).get("kind") == "invalid","released Player is rejected before its state is read")
	var replacement := QuietPlayer.new();replacement.melee.free();replacement.melee = null
	alive.player = replacement
	entities.queue_free()
	while is_instance_valid(entities): await s.runner.get_tree().process_frame
	s.check(owner._npc_origin(alive,StringName(id),7).get("kind") == "invalid","released entities are rejected before child lookup")
	Story._presentation_context = context
	Story._current_cinematic = original_cinematic
	Story._current_request = original_request
	replacement.free();alive.queue_free()
	while is_instance_valid(alive): await s.runner.get_tree().process_frame
	owner.free();host.free()
	s.check(var_to_bytes([GameState.world_flags,Progression.snapshot(),StoryItems.snapshot(),Story.progress_snapshot()]) == facts,"all lifetime rejection paths preserve game facts")
