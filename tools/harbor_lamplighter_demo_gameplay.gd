extends Node
## Real Level/NpcActor integration fixture. Its map and dialogue are isolated tool data.
const FIXTURE := "res://tools/fixtures/harbor_lamplighter_demo/"
const SCENE := "harbor_lamplighter_demo_preview_talk"
var _out := ""
var _failures: Array[String] = []
var _observations: Array[Dictionary] = []
var _talk_completed := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
	if _out.is_empty():
		push_error("[lamplighter fixture] --out is required")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(40.0, true, false, true).timeout.connect(func() -> void:
		_failures.append("fixture did not complete within 40 seconds")
		_finish())
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value: _failures.append(message)

func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _physics(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(screenshot.save_png(_out.path_join(name + ".png")) == OK, "save " + name)

func _record(npc: NpcActor, phase: String) -> void:
	var rig := npc._actor.rig
	var animator := rig.animator as NpcAnimator
	_observations.append({"phase": phase, "actor_class": npc.get_class(),
		"script": npc.get_script().resource_path, "rig": rig.skin_id,
		"requested_actor_pose": String(npc._actor.pose), "observed_npc_pose": animator._pose_now,
		"observed_loop": animator._loop_name, "talking": npc._talking,
		"talk_input": npc._actor._input.talking, "level_lighting": rig.use_level_lighting})

func _run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = false
	Story._speakers[SCENE.trim_suffix("_talk")] = {"name": "修燈工", "color": "#c8bc9e", "portrait": ""}
	Story._scenes[SCENE] = {"mode": "dialogue", "lines": [
		{"speaker": SCENE.trim_suffix("_talk"), "text": "正在驗證修燈工外觀。"},
		{"speaker": "rin", "text": "這段對話只存在於隔離示範。"}]}
	var data := LevelData.new()
	data.id = &"harbor_lamplighter_demo_fixture"
	data.display_name = "外觀隔離示範"
	data.layout_path = FIXTURE + "map.json"
	data.rain = false
	data.show_chapter_card = false
	data.announce_area = false
	data.legend = {"A": (load(FIXTURE + "preview_npc.tres") as NpcData).duplicate(true)}
	var zone := LightingZone.new()
	zone.profile = load("res://data/lighting/harbor_approach.tres")
	data.lighting_zones = [zone]
	var level := Level.new()
	level.configure(data)
	get_tree().root.add_child(level)
	await _physics(12)
	_check(level.is_initialized(), "real Level initialization")
	var npc: NpcActor
	for candidate in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if candidate.data.id == &"harbor_lamplighter_demo_preview": npc = candidate
	if npc == null or npc._actor == null or npc._actor.rig == null:
		_failures.append("real map did not create NpcActor/CutsceneActor/CharacterRig")
		_finish()
		return
	_check(npc._actor.rig.skin_id == "harbor_lamplighter_demo", "new appearance selected without fallback")
	_check(npc._actor.rig.use_level_lighting, "NpcActor selects normal level lighting")
	_check(npc.collision_layer == 0 and not npc.is_in_group(&"enemies"), "civilian has no combat collision or enemy group")
	var bench := level._world.get_node_or_null("bench") as PropNode
	_check(bench != null and bench.data.id == &"bench", "real Level loads the seat from its map prop definition")
	level.player.global_position = npc.global_position + Vector2(-36, -1)
	level.player.velocity = Vector2.ZERO
	level.camera.target = npc
	level.camera.tuning = CameraTuning.from_dictionary({"zoom": 2.4, "look_ahead": 0.0, "aim_look": 0.0}, "lamplighter fixture camera")
	level.camera.snap_to_target()
	var title_layer := CanvasLayer.new()
	title_layer.layer = 100
	var title := Label.new()
	title.text = "隔離外觀示範｜非正式劇情"
	title.position = Vector2(12, 12)
	title_layer.add_child(title)
	add_child(title_layer)
	await _physics(120)
	_record(npc, "map_stand")
	await _capture("01-map-stand")
	var order := {}
	for part in npc._actor.rig._parts: order[str(part.name)] = part.z_index
	_check(int(order["leg_back_upper"]) < int(order["torso"]) and int(order["arm_front_upper"]) > int(order["torso"]), "runtime near/far body layer order")
	_observations.append({"phase": "layer_order", "part_z_indices": order})
	_check(npc.present_pose(&"sit"), "NpcActor accepts real sit presentation")
	await _physics(24)
	_record(npc, "sit_enter")
	await _capture("02-sit-enter")
	await _physics(96)
	_record(npc, "sit_settled")
	_check((npc._actor.rig.animator as NpcAnimator)._pose_now == "sit", "actual NPC animator entered sit")
	await _capture("03-sit-settled")
	npc.refresh_pose()
	await _physics(24)
	_record(npc, "sit_exit")
	await _capture("04-sit-exit")
	await _physics(96)
	_check((npc._actor.rig.animator as NpcAnimator)._pose_now == "stand", "actual NPC animator returned to stand")
	_check(npc._player_in_range, "real player area enter enables conversation")
	_finish_talk(npc)
	await _frames(6)
	_check(npc._talking and Story.is_cinematic_active() and get_tree().paused, "real NpcActor conversation owns paused Story presentation")
	_check(npc._actor._input.talking, "conversation enters actual talking overlay")
	await _frames(30)
	if Story._layer._text.visible_ratio < 1.0: Story._layer.advance()
	await _frames(2)
	_check(Story._layer._cinematic_index == 0 and Story._layer._name.text.contains("修燈工") and Story._layer._text.visible_ratio == 1.0, "capture shows the actual complete NPC line")
	_record(npc, "conversation")
	await _capture("05-real-conversation")
	for i in 8:
		if Story.is_cinematic_active(): Story._layer.advance()
		await _frames(3)
	_check(_talk_completed and npc.talk_count == 1 and not get_tree().paused, "conversation ends once and resumes gameplay")
	await _physics(30)
	_check(not npc._actor._input.talking, "talk overlay clears after real conversation")
	_record(npc, "conversation_return")
	await _capture("06-conversation-return")
	var references := [weakref(level), weakref(level.player), weakref(npc), weakref(npc._actor), weakref(npc._actor.rig)]
	if bench != null: references.append(weakref(bench))
	Story.reset_active_presentation(&"fixture_end")
	level.queue_free()
	await _frames(4)
	var released := true
	for reference in references: released = released and reference.get_ref() == null
	_check(released, "Level/Player/NpcActor/CutsceneActor/CharacterRig/bench nodes released")
	_check(get_tree().get_nodes_in_group(NpcActor.GROUP).is_empty(), "no NPC actor remains registered")
	_check(Story._bubble_host == null and Story.framing.scope_count() == 0, "level dialogue host and framing ownership released")
	Story._scenes.erase(SCENE)
	Story._speakers.erase(SCENE.trim_suffix("_talk"))
	_observations.append({"phase": "released", "all_owned_nodes_released": released, "tracked_nodes": references.size(),
		"texture_cache_policy": "Existing autoload texture cache retention is unchanged; node release does not claim zero cached GPU resources."})
	_finish()

func _finish_talk(npc: NpcActor) -> void:
	_talk_completed = await npc._talk()

func _finish() -> void:
	var file := FileAccess.open(_out.path_join("receipt.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"fixture": "real Level + map-loaded NpcActor", "failures": _failures,
		"observations": _observations, "performance_claim": false}, "\t"))
	print("LAMPLIGHTER_GAMEPLAY %d failures: %s" % [_failures.size(), _failures])
	get_tree().quit(0 if _failures.is_empty() else 1)
