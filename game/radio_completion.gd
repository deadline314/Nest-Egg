extends Node
## Main-owned completion gate for important, flag-only radio scenes.
## Durable write precedes the two silent owner assignments and every notification.

const Prompt := preload("res://ui/radio_save_prompt.gd")
const Bundle := preload("res://core/story_install_bundle.gd")
var main: Node
var _pending_id: StringName
var _pending_request := 0
var _lock := 0
var _prompt: Control
var _publishing := false
var _recovery := false
var _reload_original := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Story.passive_completion_gate = complete
	Story.presentation_reset.connect(_presentation_reset)


func _exit_tree() -> void:
	if Story.passive_completion_gate == complete:
		Story.passive_completion_gate = Callable()
	_clear()


func blocks_save() -> bool:
	return _pending_request != 0 or _publishing or _recovery


func complete(id: StringName, request: int) -> Dictionary:
	var scene: Dictionary = Story._scenes.get(String(id), {})
	if not main.get("_active_run") or str(scene.get("mode", "")) != "radio" or not bool(scene.get("freeze", false)):
		return {}  # Preserve non-Main and ambient presentation behavior.
	# This gate owns only flags/completion. Never silently swallow a future item or money result.
	var results: Variant = scene.get("results", [])
	if not results is Array or not results.is_empty() or not StoryRules.transfer_ids(scene).is_empty() or not (Story._pending_transfers.get(id, []) as Array).is_empty():
		return {}
	var level := main.get("_screen") as Level
	if level == null or not level.is_initialized() or main.call("_route_pending") or Story.is_cinematic_active():
		return {}  # Cinematic entry snapshots retain their existing atomic boundary.
	_pending_id = id
	_pending_request = request
	if _lock == 0:
		_lock = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
	var result := _commit(id, scene, level)
	if not result.get("committed", false):
		push_warning("[RadioCompletion] %s: %s" % [id, str(result.get("error", "completion preparation refused")).left(512)])
		_reload_original = result.get("reload_original", false)
		_show_prompt(false)
		return {"handled": true, "ready": false}
	if result.get("recovery", false):
		_recovery = true
		_show_prompt(true)
		return {"handled": true, "ready": false}
	_publishing = true
	# Both owners are already consistent before any observer can execute.
	for flag: String in result["changed"]:
		GameState.flag_changed.emit(StringName(flag), GameState.get_flag(StringName(flag)))
	_clear()
	_finish_publish.call_deferred()
	return {"handled": true, "ready": true}


func _commit(id: StringName, scene: Dictionary, level: Level) -> Dictionary:
	if scene != Story._scenes.get(String(id), {}):
		return {"error": "scene contract differs from the loaded registry"}
	var source := Bundle._capture_source()
	if source.has("error"):
		return source
	var candidate := RunSnapshot.capture(main.get("_level_path"), level.run_snapshot(), "", main.get("_chapter_complete"))
	var baseline := candidate.duplicate(true)
	var flags: Dictionary = candidate["story"]["flags"]
	for raw: Variant in scene.get("set_flags", []):
		var flag := str(raw)
		if not GameState.flag_defaults.has(flag) or not GameState.flag_defaults[flag] is bool:
			return {"error": "story/set_flags/%s requires a declared boolean" % flag}
		flags[flag] = true
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
	# This gate cannot silently install a repaired item or wallet. Full restore
	# owns those migrations; refuse a normalized proposal that changes either owner.
	for pair: Array in [[normalized["story"]["items"], baseline["story"]["items"]], [normalized["progression"], baseline["progression"]]]:
		if JSON.parse_string(JSON.stringify(pair[0])) != JSON.parse_string(JSON.stringify(pair[1])):
			return {"error": "run/story/items or run/progression needs a whole-run repair"}
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
		Story.reset_active_presentation(&"load")
		_clear()
		_recovery = false
		main.call("_on_continue_requested")
		return
	if _pending_request != 0:
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
	_publishing = false
	# Keep the original post-scene autosave contract: observers or the next
	# presentation may have queued additional state after the durable radio result.
	if is_instance_valid(main) and main.is_inside_tree():
		main.call("_queue_save")
