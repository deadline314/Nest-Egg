extends Node
## Explicit terminal segments, optional choices and flag-only continuations.
## The general atomic_v1 capability remains absent.
const Sources := preload("res://game/story_result_sources.gd")
const POLICY := Sources.TERMINAL
const CONTINUATION_POLICY := Sources.CONTINUATION
const Bundle := preload("res://core/story_install_bundle.gd")
const Prompt := preload("res://ui/radio_save_prompt.gd")
const SEGMENTS := {
	"ch1_b_dinner_food": "res://data/levels/ch1_pawnshop.tres",
}
const NPC_SOURCES := Sources.NPC_SOURCES
var main: Node
var _id: StringName
var _request := 0
var _lock := 0
var _prompt: Control
var _events: Array = []
var _changed: Array[String] = []
var _delta := 0
var _publishing := false
var _recovery := false
var _reload_original := false
var _choice_retry: Callable
var _choice_target: StringName
var _continuation_target: StringName
var _continuation_context: Dictionary = {}


func choice_pending() -> bool:
	return _choice_target != &"" and _request != 0


## Finite source binding; no new capability can be enabled by arbitrary story data.
## The default/return is result-free, so all existing skip paths stay result-free.
func choose(option: Dictionary, retry: Callable) -> Dictionary:
	if not Sources.CHOICES.has(String(Story._current_cinematic)):
		return {"handled": true, "accepted": false} if choice_pending() else {}
	if not main.get("_active_run") or _publishing:
		return {"handled": true, "accepted": false}
	var id := Story._current_cinematic
	var request := Story.current_presentation_request()
	if _request != 0 and (_request != request or _id != id):
		return {"handled": true, "accepted": false}
	var contract := Sources.choice(String(id), option, Story._scenes, Story._scene_sources)
	if contract.is_empty():
		push_warning("[StoryResultCompletion] %s choice differs from its finite authored contract" % id)
		# An unavailable authored option must not strand a skipped player waiting
		# for a save retry that was never created. Restore its actual entry safely.
		Story.reset_active_presentation(&"leave")
		EventBus.toast_requested.emit(Prompt.copy("這段對話暫時無法繼續，原進度保留。", "この会話は今は続けられません。元の進行状況は保持されています。", "This conversation is unavailable. Your previous progress is preserved."))
		return {"handled": true, "accepted": false}
	if not StoryRules.eligible(contract["option"], GameState.has_flag, StoryItems.owns):
		return {"handled": true, "accepted": false}
	if contract.get("return", false):
		return {"handled": true, "accepted": not choice_pending()}
	var player: CutscenePlayer = Story._player if is_instance_valid(Story._player) else null
	if not _choice_control_valid(player, retry):
		return {"handled": true, "accepted": false}
	_id = id
	_request = request
	_choice_target = StringName(contract["target"])
	_choice_retry = retry
	if _lock == 0:
		_lock = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
	var result := _prepare_and_commit(contract, _choice_target, true)
	if not result.get("committed", false) or result.get("recovery", false):
		_recovery = result.get("recovery", false)
		_reload_original = result.get("reload_original", false)
		push_warning("[StoryResultCompletion] %s choice: %s" % [id, str(result.get("error", "committed choice requires reload")).left(512)])
		_show_prompt()
		return {"handled": true, "accepted": false}
	var context := Story.current_presentation_context()
	Story._pending_next[id] = _choice_target
	_publishing = true
	main.call("_accept_story_choice", _choice_target, request, context)
	for flag: String in result["changed"]:
		GameState.flag_changed.emit(StringName(flag), GameState.get_flag(StringName(flag)))
	main.call("_accept_story_choice", _choice_target, request, context)
	finish()
	return {"handled": true, "accepted": true}


func _choice_control_valid(player: CutscenePlayer, retry: Callable) -> bool:
	if not retry.is_valid():
		return false
	if retry.get_object() == Story and retry.get_method() == &"_retry_auto_skip_choices":
		return Story.auto_skip
	if not is_instance_valid(player) or retry.get_object() != player or not player.is_running():
		return false
	if retry.get_method() == &"choose":
		return player.choice_active() and not player.skipping
	return retry.get_method() == &"_retry_skipped_choices" and player.skipped_defaults_pending()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Story.result_completion = self
	Story.presentation_reset.connect(_reset)


func _exit_tree() -> void:
	if Story.result_completion == self:
		Story.result_completion = null
	_clear()


func blocks_save() -> bool:
	return _request != 0 or _publishing


func publishing() -> bool:
	return _publishing


func complete(id: StringName, request: int) -> Dictionary:
	if choice_pending() and id == _id and request == _request:
		return {"handled": true, "ready": false}
	var scene: Dictionary = Story._scenes.get(String(id), {})
	if scene.get("completion_policy", "") not in [POLICY, CONTINUATION_POLICY]:
		return {}
	# Standalone tools retain legacy presentation; a real Main cannot fall through.
	if not main.get("_active_run"):
		return {"handled": true, "ready": false}
	if _publishing or (_request != 0 and (_request != request or _id != id)):
		return {"handled": true, "ready": false}
	_id = id
	_request = request
	if _lock == 0:
		_lock = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
	var continuation := Sources.continuation(String(id), Story._scenes, Story._scene_sources) if scene.get("completion_policy") == CONTINUATION_POLICY else &""
	var result: Dictionary
	if scene.get("completion_policy") == CONTINUATION_POLICY and continuation == &"":
		result = {"error": "flag continuation differs from its finite authored contract"}
	else:
		result = _prepare_and_commit(scene, continuation)
	if not result.get("committed", false) or result.get("recovery", false):
		_recovery = result.get("recovery", false)
		_reload_original = result.get("reload_original", false)
		push_warning("[StoryResultCompletion] %s: %s" % [id, str(result.get("error", "committed result requires reload")).left(512)])
		_show_prompt()
		return {"handled": true, "ready": false}
	_events = result["events"]
	_changed.assign(result["changed"])
	_delta = result["delta"]
	_continuation_target = continuation
	_continuation_context = Story.current_presentation_context() if continuation != &"" else {}
	_publishing = true
	if continuation != &"":
		main.call("_accept_story_choice", continuation, request, _continuation_context)
	elif Story._current_cinematic == id:
		main.call("_clear_cinematic")
	return {"handled": true, "ready": true, "terminal_batch": true}


func _prepare_and_commit(scene: Dictionary, continuation: StringName = &"", choice := false) -> Dictionary:
	var problem := Story.outcomes.result_contract_problem(_id, scene)
	if not problem.is_empty():
		return {"error": problem}
	var level := main.get("_screen") as Level
	if level == null or not level.is_initialized() or level.data.resource_path != main.get("_level_path") or not level.data.persistent_world or main.call("_route_pending"):
		return {"error": "terminal results require the current persistent Main Level"}
	if Story._scene_sources.get(String(_id)) != "res://data/story/ch1_kasa.json":
		return {"error": "terminal producer is not bound to this segment and current authored Level"}
	var npc := {}
	if NPC_SOURCES.has(String(_id)):
		npc = _npc_source(level)
		if npc.is_empty():
			return {"error": "terminal NPC result requires its actual current authored interaction"}
	elif SEGMENTS.get(String(_id), "") != level.data.resource_path:
		return {"error": "terminal producer is not bound to this authored Level"}
	if (not choice and str(scene.get("then", "")) != String(continuation)) or Story.offers_choice(scene) or Story._pending_next.has(_id) or scene.has("transfer_items") or not (Story._pending_transfers.get(_id, []) as Array).is_empty():
		return {"error": "result boundary cannot own this choice, continuation or pending transfer"}
	var passive: Array = Story._passive_requests.get(_id, [])
	if not (Story._current_cinematic == _id and Story.current_presentation_request() == _request) and (passive.is_empty() or int(passive[0]) != _request):
		return {"error": "stale terminal request"}
	for item: StoryItemData in StoryItems.catalog():
		if item.trigger == StoryItemData.Trigger.SCENE_FINISHED and item.trigger_scene == _id:
			return {"error": "terminal result has a duplicate automatic item producer"}
	var context := Story.current_presentation_context() if continuation != &"" else {}
	var candidate := RunSnapshot.capture(main.get("_level_path"), level.run_snapshot(), String(continuation), main.get("_chapter_complete"), context)
	var original := RunSnapshot.prepare(candidate)
	if original.has("error"):
		return original
	# Compare both sides through the writer's exact JSON + second validation
	# boundary. Vector2 normalization uses real_t precision; one pass compared to
	# two can otherwise reject an unchanged, non-cardinal aim by one float ULP.
	var encoded_original := RunSaveCodec.decode(RunSaveCodec.encode(original["data"]))
	if encoded_original.has("error"):
		return encoded_original
	original = RunSnapshot.prepare(encoded_original["data"])
	if original.has("error"):
		return original
	if not npc.is_empty():
		# Detach the raw capture from the live area, retaining actual owner facts.
		# Copying the normalized original could silently introduce read-time repairs.
		candidate = candidate.duplicate(true)
	var source := Bundle._capture_source()
	if source.has("error"):
		return source
	var planned := _plan(scene, candidate, continuation, choice)
	if not planned.get("valid", false):
		return {"error": planned.get("error", "invalid result plan")}
	var next: Dictionary = planned["next"]
	if choice:
		# The pure planner validates the explicit flag operation; selecting an option
		# is not segment completion. Only the real leaf may settle the NPC waiter.
		next["completed"] = candidate["story"]["seen"].duplicate()
		planned["events"] = []
	candidate["story"]["flags"] = next["flags"]
	candidate["story"]["items"] = next["items"]
	candidate["story"]["seen"] = next["completed"]
	candidate["progression"]["credits"] = next["credits"]
	candidate["progression"]["story_transactions"] = next["ledger"]
	var expected_state: Dictionary = original["data"]["state"].duplicate(true)
	var expected_runtime: Dictionary = original["data"]["runtime"].duplicate(true)
	if not npc.is_empty() and continuation == &"":
		var key: String = npc["key"]
		var area: String = String(level.data.id)
		var worlds: Array = [candidate["runtime"]["world"], candidate["runtime"]["area"]["world"], candidate["state"]["area_states"][area]["world"], expected_runtime["world"], expected_runtime["area"]["world"], expected_state["area_states"][area]["world"]]
		for world: Dictionary in worlds:
			if JSON.parse_string(JSON.stringify(world.get(key))) != JSON.parse_string(JSON.stringify(npc["prepared"]["before"])):
				return {"error": "terminal NPC requires matching original world state"}
		for world: Dictionary in worlds:
			world[key] = npc["prepared"]["after"].duplicate(true)
	var store: RunSaveStore = main.get("_run_store")
	if store.overwrite_authorized:
		# Establish OLD facts only, using the existing new-run authorization.
		var baseline := main.get("_cinematic_entry") as Dictionary
		if baseline.is_empty():
			baseline = RunSnapshot.capture(main.get("_level_path"), level.run_snapshot())
		if not store.write(baseline):
			return {"error": "initial save: " + "; ".join(store.issues)}
	var prepared := store.prepare_existing_write(candidate)
	if prepared.has("error"):
		return prepared
	var write: RunSaveStore.PreparedExistingWrite = prepared["data"]
	var normalized := write.snapshot()
	# A validator may repair legacy saves. Do not install or bill a repaired batch.
	for pair: Array in [[normalized["story"], candidate["story"]], [normalized["progression"], candidate["progression"]], [normalized["state"], expected_state], [normalized["runtime"], expected_runtime], [normalized["navigation"], original["data"]["navigation"]]]:
		if JSON.parse_string(JSON.stringify(pair[0])) != JSON.parse_string(JSON.stringify(pair[1])):
			return {"error": "terminal results need a whole-run repair before retry", "reload_original": true}
	var game := GameState.prepare_install(normalized["state"], next["flags"], "", false)
	var money := Progression.prepare_install(normalized["progression"])
	var items := StoryItems.prepare_install(next["items"])
	var story := Story.prepare_install(next["completed"], false)
	for owner: Dictionary in [game, money, items, story]:
		if owner.has("error"):
			return owner
	var changed: Array[String] = []
	for flag: String in game["data"].flags:
		if GameState.get_flag(StringName(flag)) != game["data"].flags[flag]:
			changed.append(flag)
	if Bundle._capture_source().get("data") != source["data"] or not _npc_unchanged(level, npc):
		return {"error": "live source changed before durable terminal write"}
	var delta: int = next["credits"] - Progression.credits
	var outcome := store.commit_existing_write(write)
	if not outcome.committed:
		return {"error": "; ".join(outcome.issues), "reload_original": outcome.requires_recovery}
	if outcome.requires_recovery or Bundle._capture_source().get("data") != source["data"] or not _npc_unchanged(level, npc):
		return {"committed": true, "recovery": true}
	# No callbacks, loading, validation, saves or world replacement in this section.
	Progression._install_prepared(money["data"])
	StoryItems._install_prepared(items["data"])
	GameState._install_prepared_flags(game["data"])
	Story._install_prepared(story["data"])
	if not npc.is_empty() and continuation == &"":
		(npc["actor"] as NpcActor).install_story_completion(npc["prepared"])
		level._area["world"][npc["key"]] = npc["prepared"]["after"].duplicate(true)
	return {"committed": true, "events": planned["events"], "changed": changed, "delta": delta}


func _npc_source(level: Level) -> Dictionary:
	var source: Dictionary = NPC_SOURCES.get(String(_id), {})
	var allowed: Array = source.get("levels", [])
	if level.died or not allowed.has(level.data.resource_path) or level.player == null or level.player.is_dead():
		return {}
	var context := Story.current_presentation_context()
	var index: int = context.get("talk_index", -1)
	for node: Node in level._entities.get_children():
		var actor := node as NpcActor
		if actor == null or actor.is_queued_for_deletion() or not actor.is_inside_tree() or actor.data == null or actor.data.resource_path != source.get("npc", "") or actor.state_key() != context.get("source_id") or not actor.is_present():
			continue
		var prepared := actor.prepare_story_completion(index)
		if prepared.is_empty() or not Story.is_chained_scene(Story.resolve_dispatch(actor.data.talks[index].scene), _id):
			continue
		for spawn: Dictionary in level._layout.spawns:
			if spawn["resource"] == actor.data and spawn["cell"] == actor.cell:
				return {"actor": actor, "key": actor.state_key(), "prepared": prepared}
	return {}


func _npc_unchanged(level: Level, expected: Dictionary) -> bool:
	if expected.is_empty():
		return true
	if not is_instance_valid(level) or level.is_queued_for_deletion() or not level.is_inside_tree() or main.get("_screen") != level or not is_instance_valid(expected["actor"]):
		return false
	var current := _npc_source(level)
	return not current.is_empty() and current["actor"] == expected["actor"] and current["key"] == expected["key"] and var_to_bytes(current["prepared"]) == var_to_bytes(expected["prepared"])


func _plan(scene: Dictionary, candidate: Dictionary, continuation: StringName = &"", choice := false) -> Dictionary:
	var scenes := {}
	for key: String in Story._scenes:
		scenes[key] = {"once": false, "condition": {}, "results": []}
	var operations: Array = scene.get("results", []).duplicate(true)
	var producers := {}
	var source: String = Story._scene_sources.get(String(_id), "")
	if source.is_empty() or not scene.get("set_flags", []).is_empty():
		return {"error": "terminal result needs its loaded source and explicit results"}
	for raw: Variant in operations:
		if not raw is Dictionary or not raw.get("kind") is String or not raw.get("id") is String:
			return {"error": "invalid unfiltered terminal operation"}
		var kind: String = raw["kind"]
		var entry := {"scene_id": String(_id), "source": source, "capability": "scene_completion"}
		if kind == "item_acquire":
			entry["capability"] = "scene_manual_item"
		elif kind == "item_transfer":
			if _id != &"ch1_t_handoff_accept" or raw["id"] != "ch1_data_disk" or raw.get("destination") != "ch1_handoff_cabinet":
				return {"error": "transfer destination does not match the real handoff cabinet"}
			entry["capability"] = "item_transfer"
			entry["destination"] = raw.get("destination", "")
		producers[kind + ":" + raw["id"]] = [entry]
	scenes[String(_id)] = {"once": true, "condition": scene.get("when", {}), "results": operations}
	var definitions := {}
	for item: StoryItemData in StoryItems.catalog():
		definitions[String(item.id)] = {"trigger": item.trigger}
	var transactions := {}
	for item: StoryTransactionData in ResourceCatalog.load_dir("res://data/story_transactions", StoryTransactionData, "TerminalStory"):
		if transactions.has(String(item.id)) or item.descriptor().has("error"):
			return {"error": "invalid or duplicate canonical transaction definition"}
		transactions[String(item.id)] = item.descriptor()
	var projection := {"flags": candidate["story"]["flags"], "items": candidate["story"]["items"], "credits": candidate["progression"]["credits"], "ledger": candidate["progression"]["story_transactions"], "area_states": candidate["state"]["area_states"], "completed": candidate["story"]["seen"]}
	var repeatable := choice or String(_id) == "ch1_t_lamp_voice_later"
	var previous_completion := false
	if repeatable:
		if choice:
			if not Sources.CHOICES.has(String(_id)):
				return {"valid": false, "error": "only registered finite question choices may repeat"}
		else:
			var boundary := Sources.boundary(String(_id), Story._scenes, Story._scene_sources)
			if boundary.is_empty() or not boundary.get("repeatable", false) or not operations.is_empty():
				return {"valid": false, "error": "only the authored result-free later reply may repeat"}
		# Keep the strict planner's once-only reward semantics. Registered choices
		# only repeat idempotent intent flags/positions; the later reply is empty.
		# Their original presentation history remains present and unchanged.
		previous_completion = (projection["completed"] as Array).any(func(value: Variant) -> bool: return String(value) == String(_id))
		projection["completed"] = (projection["completed"] as Array).filter(func(value: Variant) -> bool: return String(value) != String(_id))
	var result := StoryResultPlan.plan(operations, projection, {"scene_id": String(_id), "replay": false, "scenes": scenes, "flag_defaults": GameState.flag_defaults, "item_definitions": definitions, "transaction_definitions": transactions, "producers": producers, "ledger_locked": Progression._story_transactions._locked})
	if not result.get("valid", false):
		return result
	var next: Dictionary = result["next"]
	if repeatable and previous_completion:
		next["completed"] = candidate["story"]["seen"].duplicate()
	var facts := func(kind: StringName, key: StringName) -> Variant:
		match kind:
			&"flag": return next["flags"].get(String(key), GameState.flag_defaults.get(String(key), false))
			&"held": return next["items"]["held"].has(key)
			&"receipt": return next["ledger"]["receipts"].has(String(key))
		return Story.fact(kind, key)
	for flag: String in Story.outcomes.derived_flags:
		next["flags"][flag] = StoryRules.holds(Story.outcomes.derived_flags[flag], facts)
	if continuation != &"" and not StoryRules.holds((Story._scenes[String(continuation)] as Dictionary).get("when", {}), facts):
		return {"valid": false, "error": "choice continuation does not admit its proposed facts"}
	return result


## Called after the real presentation handle retires, before any completion observer.
func publish() -> void:
	if _delta != 0:
		Progression.credits_changed.emit(Progression.credits, _delta)
	for event: Dictionary in _events:
		var id := StringName(str(event.get("id", "")))
		match event["kind"]:
			"transaction_committed": Progression.story_transaction_committed.emit(id)
			"item_acquire":
				var item := StoryItems.find(id)
				StoryItems.acquired.emit(item)
				EventBus.toast_requested.emit(StoryItems.acquire_message(item))
			"item_transfer": StoryItems.transferred.emit(StoryItems.find(id))
	for flag: String in _changed:
		GameState.flag_changed.emit(StringName(flag), GameState.get_flag(StringName(flag)))


## All synchronous observers/waiters have returned. Never re-install the proposal.
func finish() -> void:
	if _continuation_target != &"":
		main.call("_accept_story_choice", _continuation_target, _request, _continuation_context)
	if is_instance_valid(_prompt):
		EventBus.toast_requested.emit(Prompt.copy("進度已保存，可以繼續。", "進行状況を保存しました。続けられます。", "Progress saved. You can continue."))
	_publishing = false
	_clear()
	main.call("_queue_save") # Fresh capture includes ordinary spending/NEW changes.


func _show_prompt() -> void:
	if is_instance_valid(_prompt):
		_prompt.set_recovery(_recovery)
		if _reload_original:
			_prompt.set_original_recovery()
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 110
	add_child(canvas)
	_prompt = Prompt.new()
	_prompt.presentation = "event"
	_prompt.allow_cancel = false
	_prompt.retry_requested.connect(_retry)
	canvas.add_child(_prompt)
	_prompt.set_recovery(_recovery)
	if _reload_original:
		_prompt.set_original_recovery()


func _retry() -> void:
	if _recovery or _reload_original:
		Story.reset_active_presentation(&"load")
		_clear()
		main.call("_on_continue_requested")
	elif choice_pending():
		if _choice_retry.is_valid() and Story._current_cinematic == _id and Story.current_presentation_request() == _request:
			_choice_retry.call()
		else:
			_reload_original = true
			_show_prompt()
	elif Story._current_cinematic == _id:
		Story._on_cinematic_finished(_id, _request)
	else:
		Story._on_passive_finished(_id, _request)


func _reset(_reason: StringName) -> void:
	_clear()


func _clear() -> void:
	_id = &""
	_request = 0
	_recovery = false
	_reload_original = false
	_choice_retry = Callable()
	_choice_target = &""
	_continuation_target = &""
	_continuation_context.clear()
	_events.clear()
	_changed.clear()
	if is_instance_valid(_prompt):
		_prompt.hide()
		_prompt.get_parent().queue_free()
	_prompt = null
	GameplayLock.release(_lock)
	_lock = 0
