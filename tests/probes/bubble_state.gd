extends "res://tests/probes/supper_completion.gd"
const GREETING := &"ch1_b_stall"

func _capture(name: String) -> void:
	if name != "accepted":
		return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var host: MapBubbles = Story._bubble_host
	var active: Array = []
	var queued: Array = []
	for entry: Dictionary in host._active:
		active.append({"id":String(entry["id"]),"request":entry["request"],"text":entry["text"],"age":entry["age"],"hold":entry["hold"]})
	for entry: Dictionary in host._queue:
		queued.append({"id":String(entry["id"]),"request":entry["request"]})
	var raw := _primary()
	var state := {"scene_eligible":Story.scene_available(GREETING),"npc_present":_actor().is_present(),"talks":_actor().talk_count,"host_visible":host.visible,"active":active,"queued":queued,"passive":Story._passive_requests.get(GREETING,[]).duplicate(),"completed":Story.progress_snapshot().has(GREETING),"flags":GameState.world_flags.duplicate(true),"wallet":Progression.credits,"primary_flags":raw.get("story",{}).get("flags",{}),"frame":Engine.get_process_frames()}
	DirAccess.make_dir_recursive_absolute(out)
	# No await or game-state mutation between same-frame state and original PNG.
	if DisplayServer.get_name() != "headless":
		preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(out.path_join("state.png"))
	FileAccess.open(out.path_join("state.json"),FileAccess.WRITE).store_string(JSON.stringify(state,"  "))
	_check(not state["scene_eligible"] and state["npc_present"] and state["talks"] == 1, "actual completed payment invalidates only the original invitation while same authored NPC remains present")
	_check(not state["completed"], "withdrawing an obsolete invitation cannot fabricate a completed reading")
	_check(not (host._active + host._queue).any(func(entry: Dictionary) -> bool: return entry["id"] == GREETING), "ineligible original invitation has no active or queued original line")
