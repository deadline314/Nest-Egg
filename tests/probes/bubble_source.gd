extends "res://tests/probes/ali_completion.gd"
## Same original source/choices/real retry flow; observe the original entry greeting.
func _exit() -> void:
	var level := _main.get("_screen") as Level
	var host: MapBubbles = level._bubbles
	var active: Array = []
	var queued: Array = []
	for entry: Dictionary in host._active:
		if entry["id"] == &"ch1_b_lounge":
			active.append({"id":String(entry["id"]),"text":entry.get("text", ""),"age":entry["age"],"hold":entry["hold"],"rect":str(entry.get("rect", Rect2()))})
	for entry: Dictionary in host._queue:
		if entry["id"] == &"ch1_b_lounge":
			queued.append(entry["line"].duplicate(true))
	_check(GameState.has_flag(&"ch1_lounge_evening_done") and not _actor().is_present(), "real original closing has actually retired the authored lounge speaker")
	_check(active.is_empty() and queued.is_empty(), "departed lounge Ali cannot retain or queue the original invitation greeting")
	_check(not Story.scene_available(&"ch1_b_lounge"), "departed Ali greeting is no longer eligible on a later room entry")
	_check(not Story.play(&"ch1_b_lounge", false), "departed greeting cannot return through a radio fallback")
	var record := {"active":active,"queued":queued,"host_visible":host.visible,"present":_actor().is_present(),"talks":_actor().talk_count,"cinematic":String(Story._current_cinematic),"passive_requests":Story._passive_requests.get(&"ch1_b_lounge", []).duplicate(),"completed_greeting":Story.progress_snapshot().has(&"ch1_b_lounge")}
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("source-state.json"), FileAccess.WRITE).store_string(JSON.stringify(record,"  "))
	await _capture("source-state")
	await super._exit()
