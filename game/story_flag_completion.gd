extends Node
## Main-owned durable flags for important radio and explicitly marked terminal scenes.
## Durable write precedes the two silent owner assignments and every notification.

const POLICY := StoryOutcomes.MAIN_FLAG_COMPLETION_POLICY
const Prompt := preload("res://ui/radio_save_prompt.gd")
const Bundle := preload("res://core/story_install_bundle.gd")
var main: Node
var _pending_id: StringName
var _pending_request := 0
var _pending_cinematic := false
var _notify_flags: Array[String] = []
var _lock := 0
var _prompt: Control
var _publishing := false
var _recovery := false
var _reload_original := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Story.passive_completion_gate = complete
	Story.cinematic_completion_gate = complete
	Story.presentation_reset.connect(_presentation_reset)


func _exit_tree() -> void:
	if Story.passive_completion_gate == complete:
		Story.passive_completion_gate = Callable()
	if Story.cinematic_completion_gate == complete:
		Story.cinematic_completion_gate = Callable()
	_clear()


func blocks_save() -> bool:
	return _pending_request != 0 or _publishing or _recovery


func complete(id: StringName, request: int) -> Dictionary:
	var scene: Dictionary = Story._scenes.get(String(id), {})
	var cinematic := scene.has("completion_policy")
	var radio := str(scene.get("mode", "")) == "radio" and bool(scene.get("freeze", false))
	if not main.get("_active_run") or not (radio or cinematic):
		return {} # Standalone presentation tools retain their existing behavior.
	var results: Variant = scene.get("results", [])
	if not cinematic and (not results is Array or not results.is_empty() or not StoryRules.transfer_ids(scene).is_empty() or not (Story._pending_transfers.get(id, []) as Array).is_empty()):
		return {} # Existing radio admission; marked scenes must never fall through.
	var level := main.get("_screen") as Level
	if level == null or not level.is_initialized() or main.call("_route_pending") or (not cinematic and Story.is_cinematic_active()):
		if cinematic:
			push_warning("[StoryFlagCompletion] marked scene has no current Main Level: " + String(id))
			return {"handled": true, "ready": false}
		return {}
	_pending_id = id
	_pending_request = request
	_pending_cinematic = cinematic
	if _lock == 0:
		_lock = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
	var result := _commit(id, scene, level)
	if not result.get("committed", false):
		push_warning("[StoryFlagCompletion] %s: %s" % [id, str(result.get("error", "completion preparation refused")).left(512)])
		_reload_original = result.get("reload_original", false)
		_show_prompt(false)
		return {"handled": true, "ready": false}
	if result.get("recovery", false):
		_recovery = true
		_show_prompt(true)
		return {"handled": true, "ready": false}
	_publishing = true
	if cinematic:
		# Retire the old entry before completion/flag listeners can route or save.
		main.call("_clear_cinematic")
		# Story first retires this real handle and settles its waiter. The deferred
		# notification is queued before Level's deferred completion/navigation.
		_notify_flags.assign(result["changed"])
	else:
		for flag: String in result["changed"]:
			GameState.flag_changed.emit(StringName(flag), GameState.get_flag(StringName(flag)))
	_clear()
	_finish_publish.call_deferred()
	return {"handled": true, "ready": true}


func _commit(id: StringName, scene: Dictionary, level: Level) -> Dictionary:
	if scene != Story._scenes.get(String(id), {}):
		return {"error": "scene contract differs from the loaded registry"}
	var problem := Story.outcomes.result_contract_problem(id, scene)
	if not problem.is_empty():
		return {"error": problem}
	var cinematic: bool = scene.get("completion_policy", "") == POLICY
	if cinematic:
		if scene.get("mode", "") not in ["animated", "dialogue"] or not str(scene.get("then", "")).is_empty() or Story.offers_choice(scene) or not StoryRules.transfer_ids(scene).is_empty() or not (Story._pending_transfers.get(id, []) as Array).is_empty():
			return {"error": "main_flags_v1 requires a terminal, choice-free, flag-only scene"}
		if level.data.intro_scene != id or not level.data.complete_after_intro or level.data.resource_path != main.get("_level_path") or Story._current_cinematic != id or Story.current_presentation_request() != _pending_request:
			return {"error": "main_flags_v1 requires its real terminal intro request and current Level"}
		for item: StoryItemData in StoryItems.catalog():
			if item.trigger == StoryItemData.Trigger.SCENE_FINISHED and item.trigger_scene == id:
				return {"error": "flag completion cannot own an automatic item reward"}
	for op: Dictionary in StoryOutcomes.operations(scene):
		if op["kind"] != "flag" or not GameState.flag_defaults.has(String(op["id"])):
			return {"error": "flag completion cannot own non-flag or undeclared results"}
	# run_snapshot may merge Level's area; freeze the source after that capture.
	var candidate := RunSnapshot.capture(main.get("_level_path"), level.run_snapshot(), "", main.get("_chapter_complete"))
	var source := Bundle._capture_source()
	if source.has("error"):
		return source
	var unchanged := candidate.duplicate(true)
	var baseline := candidate.duplicate(true)
	if cinematic:
		var entry: Variant = main.get("_cinematic_entry")
		if not entry is Dictionary or entry.is_empty():
			return {"error": "terminal flag completion has no original presentation entry"}
		baseline = entry.duplicate(true)
		baseline["cinematic"] = String(id)
		baseline["cinematic_context"] = main.get("_cinematic_context").duplicate(true)
	var flags: Dictionary = candidate["story"]["flags"]
	for raw: Variant in scene.get("set_flags", []):
		var flag := str(raw)
		if not GameState.flag_defaults.has(flag) or not GameState.flag_defaults[flag] is bool:
			return {"error": "story/set_flags/%s requires a declared boolean" % flag}
		flags[flag] = true
	for op: Dictionary in StoryOutcomes.operations(scene):
		flags[String(op["id"])] = op.get("value", true)
	var facts := func(kind: StringName, key: StringName) -> Variant:
		return flags.get(String(key), GameState.flag_defaults.get(String(key), false)) if kind == &"flag" else Story.fact(kind, key)
	for flag: String in Story.outcomes.derived_flags:
		flags[flag] = StoryRules.holds(Story.outcomes.derived_flags[flag], facts)
	if not candidate["story"]["seen"].has(id):
		candidate["story"]["seen"].append(id)
	var store: RunSaveStore = main.get("_run_store")
	# A confirmed new run retains its original overwrite authorization until its
	# first successful save. Establish only OLD facts before using the existing-slot
	# writer; no radio result becomes live or completed if this bootstrap fails.
	if store.overwrite_authorized and not store.write(baseline):
		return {"error": "initial save: " + "; ".join(store.issues)}
	var prepared := store.prepare_existing_write(candidate)
	if prepared.has("error"):
		return prepared
	var write: RunSaveStore.PreparedExistingWrite = prepared["data"]
	var normalized := write.snapshot()
	# Empty checkpoint/loadout dictionaries are valid live defaults that every
	# save encodes in full. Compare run state under that same canonical encoding;
	# never mistake filling those defaults for a new result changing the owner.
	var prior := RunSnapshot.prepare(unchanged)
	if prior.has("error"):
		return prior
	# Item and wallet migrations still require the original whole-run restore.
	for pair: Array in [[normalized["story"]["items"], unchanged["story"]["items"]], [normalized["progression"], unchanged["progression"]], [normalized["state"], prior["data"]["state"]]]:
		if JSON.parse_string(JSON.stringify(pair[0])) != JSON.parse_string(JSON.stringify(pair[1])):
			return {"error": "non-flag run owners need a whole-run repair", "reload_original": true}
	# All fallible owner preparation completes BEFORE the durable boundary.
	var game := GameState.prepare_install(normalized["state"], normalized["story"]["flags"], "", false)
	var story := Story.prepare_install(normalized["story"]["seen"], false)
	if game.has("error"):
		return game
	if story.has("error"):
		return story
	if Bundle._capture_source().get("data") != source["data"]:
		return {"error": "live source changed before durable write"}
	var changed: Array[String] = []
	for flag: String in (game["data"].flags as Dictionary):
		if GameState.get_flag(StringName(flag)) != game["data"].flags[flag]:
			changed.append(flag)
	var outcome := store.commit_existing_write(write)
	if not outcome.committed:
		return {"reload_original": outcome.requires_recovery, "error": "; ".join(outcome.issues)}
	# A committed outcome is irrevocable, even if a future platform callback changed live state.
	if outcome.requires_recovery or Bundle._capture_source().get("data") != source["data"]:
		return {"committed": true, "recovery": true}
	GameState._install_prepared_flags(game["data"])
	Story._install_prepared(story["data"])
	return {"committed": true, "changed": changed}


func _show_prompt(recovery: bool) -> void:
	if is_instance_valid(_prompt):
		_prompt.set_recovery(recovery)
		if _reload_original:
			_prompt.set_original_recovery()
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 110
	add_child(canvas)
	_prompt = Prompt.new()
	_prompt.presentation = "event" if _pending_cinematic else "radio"
	_prompt.allow_cancel = not _pending_cinematic
	_prompt.retry_requested.connect(_retry)
	_prompt.cancel_requested.connect(_cancel)
	canvas.add_child(_prompt)
	_prompt.set_recovery(recovery)
	if _reload_original:
		_prompt.set_original_recovery()


func _retry() -> void:
	if _recovery or _reload_original:
		# Restore only through Main: committed recovery reads the new slot; a failed
		# rollback reads the original backup without inventing a commit.
		if _recovery and _pending_cinematic:
			main.call("_clear_cinematic")
		Story.reset_active_presentation(&"load")
		_clear()
		_recovery = false
		main.call("_on_continue_requested")
		return
	if _pending_request != 0:
		if _pending_cinematic:
			Story._on_cinematic_finished(_pending_id, _pending_request)
		else:
			Story._on_passive_finished(_pending_id, _pending_request)


func _cancel() -> void:
	if _recovery:
		return
	Story.reset_active_presentation(&"radio_save_cancel")
	_clear()


func _presentation_reset(_reason: StringName) -> void:
	if not _recovery:
		_clear()


func _clear() -> void:
	_pending_cinematic = false
	_pending_id = &""
	_pending_request = 0
	_reload_original = false
	if is_instance_valid(_prompt):
		_prompt.get_parent().queue_free()
		_prompt.hide()
	_prompt = null
	GameplayLock.release(_lock)
	_lock = 0


func _finish_publish() -> void:
	var flags := _notify_flags.duplicate()
	_notify_flags.clear()
	for flag: String in flags:
		GameState.flag_changed.emit(StringName(flag), GameState.get_flag(StringName(flag)))
	_publishing = false
	# Keep the original post-scene autosave contract: observers or the next
	# presentation may have queued additional state after the durable radio result.
	if is_instance_valid(main) and main.is_inside_tree():
		main.call("_queue_save")
