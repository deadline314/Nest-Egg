extends Node
## Original world actors supply receipts; all results in one physics turn share
## one whole-run write. Standalone Level tools keep their original local path.
const FlagCommit := preload("res://core/run_flag_commit.gd")
const Prompt := preload("res://ui/radio_save_prompt.gd")
const MAX_PENDING := 64
var main: Node
var _level: Level
var _events: Array[Dictionary] = []
var _contract := PackedByteArray()
var _lock := 0
var _prompt: Control
var _publishing := false
var _recovery := false
var _reload_original := false
var _overflow := false
var _area := ""
var _portal := &""
var _deferred: Array[Callable] = []
var _deferred_scenes: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Level.channel_handler = request
	Story.presentation_reset.connect(_reset)

func _exit_tree() -> void:
	if Level.channel_handler == request: Level.channel_handler = Callable()
	_clear()

func publishing() -> bool:
	return _publishing

func blocks_save() -> bool:
	return not _events.is_empty() or _publishing or _overflow

func _mapping(level: Level, active: bool) -> Dictionary:
	return level.data.channel_done_flags if active else level.data.channel_cleared_flags

func request(level: Level, channel: StringName, active: bool) -> bool:
	if not main.get("_active_run") or not level.data.durable_channel_results: return false
	if main.get("_screen") != level or level.data.resource_path != main.get("_level_path"): return true
	var mapping := _mapping(level, active)
	if not mapping.has(channel) or GameState.has_flag(mapping[channel]): return false
	var flag := String(mapping[channel])
	for pending: Dictionary in _events:
		if pending["flag"] == flag: return true
	var proof := _find_source(level, channel, active)
	if proof.is_empty():
		push_warning("[ChannelCompletion] refused channel without an original live actor: %s" % channel)
		return true
	if _events.size() >= MAX_PENDING:
		_overflow = true
		return true
	if _events.is_empty():
		_level = level
		_contract = _signature(level)
		level.channel_result_pending = true
		level.tree_exiting.connect(_clear, CONNECT_ONE_SHOT)
		_lock = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
	proof.merge({"flag": flag, "channel": channel, "active": active})
	_events.append(proof)
	return true

func _signature(level: Level) -> PackedByteArray:
	return var_to_bytes([level.data.resource_path, level.data.id, level.data.layout_path,
		level.data.channel_done_flags, level.data.channel_cleared_flags, level.data.channel_scenes, level.data.durable_channel_results])

func _channel(node: Node) -> StringName:
	if node is MechanismSwitch or node is FloodPit or node is EncounterZone: return node.data.channel
	if node is PatternBoss: return node.pattern.gate_channel
	if node is Enemy and node.has_method("_gate_channel"): return StringName(node.call("_gate_channel"))
	return &""

func _matches(node: Node, channel: StringName, active: bool) -> bool:
	if _channel(node) != channel: return false
	if node is ChannelSwitch: return node.active == active
	if node is FloodPit: return active and node.triggered
	if node is EncounterZone: return node.state == (&"active" if active else &"cleared")
	return active and node is Enemy and node.is_dying()

func _actor_signature(resource: Resource, script_path: String, channel: StringName) -> PackedByteArray:
	return var_to_bytes([resource.resource_path, resource.get("id"), script_path, channel,
		resource.kind if resource is MechanismData else -1])

func _find_source(level: Level, channel: StringName, active: bool) -> Dictionary:
	for index in level.channel_sources.size():
		var node := level.channel_sources[index]
		if not is_instance_valid(node) or not level.is_ancestor_of(node) or not _matches(node, channel, active): continue
		var resource := node.get("data") as Resource
		if resource == null: continue
		var key := ""
		if node is Enemy:
			for tracked: String in level._tracked:
				if is_same(level._tracked[tracked], node): key = tracked; break
		var original := false
		for spawn: Dictionary in level._layout.spawns:
			if is_same(spawn["resource"], resource) and (level._spawn_key(spawn) == key if node is Enemy else node.position.is_equal_approx(spawn["position"])):
				original = true
				break
		if not original: continue
		var script_path: String = node.get_script().resource_path
		return {"node": weakref(node), "index": index, "id": node.get_instance_id(), "resource": resource,
			"script": script_path, "signature": _actor_signature(resource, script_path, channel), "key": key, "enemy": node is Enemy}
	return {}

func _proof_valid(proof: Dictionary) -> bool:
	var resource: Resource = proof["resource"]
	if _actor_signature(resource, proof["script"], proof["channel"]) != proof["signature"]: return false
	var node: Node = proof["node"].get_ref()
	if not is_instance_valid(node):
		# A real dying boss may finish its original queue_free after requesting a
		# result. Its retained receipt cannot authorize a replacement actor.
		return proof["enemy"] and _level._tracked.has(proof["key"]) and not is_instance_valid(_level._tracked[proof["key"]]) \
			and proof["index"] < _level.channel_sources.size() and not is_instance_valid(_level.channel_sources[proof["index"]])
	if node.get_instance_id() != proof["id"] or proof["index"] >= _level.channel_sources.size() or not is_same(_level.channel_sources[proof["index"]], node): return false
	if not _level.is_ancestor_of(node) or not is_same(node.get("data"), resource) or node.get_script().resource_path != proof["script"]: return false
	if node.is_queued_for_deletion() and not proof["enemy"]: return false
	if not _matches(node, proof["channel"], proof["active"]): return false
	for spawn: Dictionary in _level._layout.spawns:
		if is_same(spawn["resource"], resource) and (_level._spawn_key(spawn) == proof["key"] if proof["enemy"] else node.position.is_equal_approx(spawn["position"])): return true
	return false

func _valid_source() -> bool:
	if not is_instance_valid(_level) or _level.is_queued_for_deletion() or main.get("_screen") != _level or not main.get("_active_run"): return false
	if not _level.is_initialized() or _level.died or not is_instance_valid(_level.player) or _level.player.is_dead() or _level.data.resource_path != main.get("_level_path") or _signature(_level) != _contract: return false
	for proof: Dictionary in _events:
		if not _proof_valid(proof): return false
	return not _events.is_empty()

func _process(_delta: float) -> void:
	if _events.is_empty() or _publishing or is_instance_valid(_prompt): return
	if not _valid_source():
		_require_original("live world result source changed")
		return
	# Capture after every listener of the original channel emission has settled.
	# Other result owners/presentations must finish before this complete snapshot.
	if main.call("_world_recovery_pending", self):
		_require_original("another complete run already requires recovery")
		return
	_attempt()

func defer_operation(callback: Callable) -> bool:
	if not blocks_save() or not main.get("_active_run"): return false
	if not callback.is_valid():
		_require_original("dependent result lost its live retry")
		return true
	if not _deferred.has(callback):
		if _deferred.size() >= MAX_PENDING: _overflow = true
		else: _deferred.append(callback)
	return true

func defer_story(id: StringName, request: int) -> bool:
	if not blocks_save() or not main.get("_active_run"): return false
	if not _deferred_scenes.has(id) and _deferred_scenes.size() >= MAX_PENDING:
		_overflow = true
		return true
	_deferred_scenes[id] = request
	var callback := Story._on_passive_finished.bind(id, request) if Story.scene_mode(id) in [Story.MODE_RADIO, Story.MODE_BUBBLES] else Story._on_cinematic_finished.bind(id, request)
	return defer_operation(callback)

func _request_live(id: StringName, request: int) -> bool:
	if Story.scene_mode(id) in [Story.MODE_RADIO, Story.MODE_BUBBLES]:
		return (Story._passive_requests.get(id, []) as Array).has(request)
	return Story._current_cinematic == id and Story.current_presentation_request() == request

func _prepare_source(candidate: Dictionary) -> Dictionary:
	# A queued portal owns a future destination, never this source-room slot.
	candidate["state"]["pending_portal"] = ""
	candidate["runtime"]["ending"] = false
	var existing: String = main.get("_cinematic")
	var pending: Array[StringName] = []
	for id: StringName in _deferred_scenes:
		if _request_live(id, _deferred_scenes[id]): pending.append(id)
	if pending.size() > 1:
		return {"error": "dependent explanations require an ordered save contract", "reload_original": true}
	if existing.is_empty() and not pending.is_empty(): existing = String(pending[0])
	if existing.is_empty() and Story._layer.is_radio_frozen() and not Story._layer._radio_queue.is_empty():
		existing = String(Story._layer._radio_queue.front()["id"])
	if not existing.is_empty():
		if candidate["cinematic"] != "" and candidate["cinematic"] != existing:
			return {"error": "concurrent explanations require an ordered save contract", "reload_original": true}
		candidate["cinematic"] = existing
		candidate["cinematic_context"] = main.get("_cinematic_context").duplicate(true)
	return {"data": candidate}

func _attempt() -> void:
	if main.call("_world_recovery_pending", self):
		_require_original("another complete run already requires recovery")
		return
	if not _valid_source():
		_require_original("live world result source changed before retry")
		return
	if _overflow:
		_require_original("world result batch exceeds supported bound")
		return
	var flags: Dictionary = {}
	var scenes: Array[StringName] = []
	for proof: Dictionary in _events:
		flags[proof["flag"]] = true
		if proof["active"] and _level.data.channel_scenes.has(proof["channel"]):
			var scene: StringName = _level.data.channel_scenes[proof["channel"]]
			if not scenes.has(scene): scenes.append(scene)
	if scenes.size() > 1:
		_require_original("simultaneous world explanations require an ordered save contract")
		return
	var scene := scenes[0] if not scenes.is_empty() else &""
	var outcome := FlagCommit.commit(main, _level, flags, scene, _valid_source, _prepare_source)
	if not outcome.get("committed", false) or outcome.get("recovery", false):
		_recovery = outcome.get("recovery", false)
		_reload_original = outcome.get("reload_original", false)
		push_warning("[ChannelCompletion] %s" % str(outcome.get("error", "saved world result requires reload")).left(512))
		_show_prompt()
		return
	var route := _area
	var portal := _portal
	var deferred := _deferred.duplicate()
	var remembered := StringName(outcome["snapshot"].get("cinematic", ""))
	if remembered != &"":
		if Story.scene_mode(remembered) == Story.MODE_RADIO:
			var requests: Array = Story._passive_requests.get(remembered, [])
			var request: int = _deferred_scenes.get(remembered, int(requests.front()) if not requests.is_empty() else 0)
			main.call("_remember_world_radio", remembered, request)
		elif main.get("_cinematic") == String(remembered):
			# Its untouched entry must now include this accepted world action.
			main.set("_cinematic_entry", outcome["snapshot"].duplicate(true))
	_publishing = true
	for flag: String in outcome["changed"]:
		GameState.flag_changed.emit(StringName(flag), GameState.get_flag(StringName(flag)))
	if _overflow:
		_recovery = true
		_publishing = false
		_show_prompt()
		return
	var live := is_instance_valid(_level) and not _level.died and is_instance_valid(_level.player) and not _level.player.is_dead()
	GameplayLock.release(_lock)
	_lock = 0
	if live and scene != &"":
		Story.play(scene)
	deferred.assign(_deferred) # Includes requests made by publication callbacks.
	_clear()
	for callback: Callable in deferred:
		if callback.is_valid(): callback.call_deferred()
	if live and not route.is_empty():
		GameState.pending_portal = portal
		main.call("_on_area_requested", route)
	else:
		main.call("_queue_save")

func defer_area(path: String) -> bool:
	if not blocks_save() or _publishing: return false
	if is_instance_valid(_level) and _level._finished:
		for node: Portal in _level._portals.values():
			if is_instance_valid(node) and node.data != null and node.data.target_level == path and node.data.target_portal == GameState.pending_portal:
				_area = path
				_portal = GameState.pending_portal
				return true
	return true # No unrelated caller can route a partly saved automatic result.

func _require_original(reason: String) -> void:
	_reload_original = true
	push_warning("[ChannelCompletion] %s; original whole run required" % reason)
	_show_prompt()

func _show_prompt() -> void:
	if not is_instance_valid(_level): return
	if not is_instance_valid(_prompt):
		var canvas := CanvasLayer.new()
		canvas.layer = 110
		add_child(canvas)
		_prompt = Prompt.new()
		_prompt.presentation = "event"
		_prompt.allow_cancel = false
		_prompt.retry_requested.connect(_retry)
		canvas.add_child(_prompt)
	_prompt.set_recovery(_recovery)
	if _reload_original: _prompt.set_original_recovery()

func _retry() -> void:
	if _recovery or _reload_original:
		Story.reset_active_presentation(&"load")
		_clear()
		main.call("_on_continue_requested")
	else: _attempt()

func _reset(reason: StringName) -> void:
	# Death/cancellation must not unblock an autosave of the already changed
	# mechanism with an unaccepted flag. Only a whole-run load or a Main exit
	# can discard this receipt. A published result already owns its durable file.
	if _publishing: return
	if blocks_save() and main.get("_active_run") and reason != &"load":
		_require_original("world result interrupted by " + String(reason))
	else:
		_clear()

func _clear() -> void:
	if is_instance_valid(_level):
		_level.channel_result_pending = false
		if _level.tree_exiting.is_connected(_clear): _level.tree_exiting.disconnect(_clear)
	_level = null
	_events.clear()
	_contract = PackedByteArray()
	_publishing = false
	_recovery = false
	_reload_original = false
	_overflow = false
	_area = ""
	_portal = &""
	_deferred.clear()
	_deferred_scenes.clear()
	if is_instance_valid(_prompt):
		_prompt.hide()
		_prompt.get_parent().queue_free()
	_prompt = null
	GameplayLock.release(_lock)
	_lock = 0
