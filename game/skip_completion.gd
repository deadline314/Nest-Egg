extends Node
## A confirmed skip is a real action; its flags must precede routing durably.
const FlagCommit := preload("res://core/run_flag_commit.gd")
const Prompt := preload("res://ui/radio_save_prompt.gd")
var main: Node
var _level: Level
var _contract := PackedByteArray()
var _lock := 0
var _prompt: Control
var _publishing := false
var _recovery := false
var _reload_original := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Level.skip_handler = request
	Story.presentation_reset.connect(_reset)

func _exit_tree() -> void:
	if Level.skip_handler == request: Level.skip_handler = Callable()
	_clear()

func blocks_save() -> bool:
	return is_instance_valid(_level) or _publishing

func publishing() -> bool:
	return _publishing

func request(level: Level) -> bool:
	if not main.get("_active_run") or main.get("_screen") != level: return false
	if blocks_save() or main.call("_route_pending") or main.call("_story_save_blocked"): return true
	# A confirmed route cancels the old presentation before proposing a result.
	Story.reset_active_presentation(&"route")
	if GameplayLock.is_locked() or get_tree().paused: return true
	_level = level
	_contract = _signature(level)
	if not _valid_source():
		push_warning("[SkipCompletion] invalid original skip route; result refused")
		_clear()
		return true
	level.tree_exiting.connect(_clear, CONNECT_ONE_SHOT)
	_lock = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
	_attempt()
	return true

func _signature(level: Level) -> PackedByteArray:
	var portal := _portal(level)
	return var_to_bytes([level.data.resource_path, level.data.skip_portal, level.data.skip_flags,
		portal.data.resource_path, portal.data.target_level, portal.data.target_portal]) if portal != null else PackedByteArray()

func _portal(level: Level) -> Portal:
	var candidate: Variant = level._portals.get(level.data.skip_portal)
	if not is_instance_valid(candidate) or not candidate is Portal or candidate.is_queued_for_deletion(): return null
	return candidate as Portal if candidate.data != null else null

func _valid_source() -> bool:
	if not is_instance_valid(_level) or _level.is_queued_for_deletion() or main.get("_screen") != _level or not main.get("_active_run") or main.call("_route_pending"):
		return false
	if not _level.is_initialized() or _level.died or _level._finished or not is_instance_valid(_level.player) or _level.player.is_dead() or _level.data.resource_path != main.get("_level_path") or _contract.is_empty() or _signature(_level) != _contract:
		return false
	var portal := _portal(_level)
	if portal == null or not _level.is_ancestor_of(portal): return false
	var destination := RunSaveCodec.resource(portal.data.target_level, "level", "res://data/levels/") as LevelData
	if destination == null or not CampaignEdition.current().includes_level(destination): return false
	return not _level.data.skip_flags.is_empty()

func _attempt() -> void:
	if not _valid_source():
		_clear()
		return
	var results: Dictionary = {}
	for flag: String in _level.data.skip_flags: results[flag] = true
	var outcome := FlagCommit.commit(main, _level, results, &"", _valid_source, _prepare_route)
	if not outcome.get("committed", false) or outcome.get("recovery", false):
		_recovery = outcome.get("recovery", false)
		_reload_original = outcome.get("reload_original", false)
		push_warning("[SkipCompletion] %s" % str(outcome.get("error", "saved skip requires reload")).left(512))
		_show_prompt.call_deferred()
		return
	var level := _level
	_publishing = true
	GameState._install_prepared(outcome["state"])
	main.set("_level_path", outcome["snapshot"]["level"])
	main.set("_destination_pending", true)
	for flag: String in outcome["changed"]:
		GameState.flag_changed.emit(StringName(flag), GameState.get_flag(StringName(flag)))
	GameplayLock.release(_lock)
	_lock = 0
	level._finished = true
	level._close_menus()
	_clear()
	main.call("_load_level", Transition.Kind.FADE)


func _prepare_route(candidate: Dictionary) -> Dictionary:
	var portal := _portal(_level)
	var changes := {"pending_portal": String(portal.data.target_portal), "carried_health": _level.player.health.current}
	if _level.data.persistent_world:
		changes["checkpoint_loadout"] = candidate["runtime"]["loadout"].duplicate(true)
	candidate["runtime"]["position"] = [-1, -1]
	return preload("res://core/run_destination.gd").prepare(candidate, portal.data.target_level, changes)

func _show_prompt() -> void:
	if not is_instance_valid(_level): return
	if not is_instance_valid(_prompt):
		var canvas := CanvasLayer.new()
		canvas.layer = 110
		add_child(canvas)
		_prompt = Prompt.new()
		_prompt.presentation = "skip"
		_prompt.retry_requested.connect(_retry)
		_prompt.cancel_requested.connect(_clear)
		canvas.add_child(_prompt)
	_prompt.set_recovery(_recovery)
	if _reload_original: _prompt.set_original_recovery()

func _retry() -> void:
	if _recovery or _reload_original:
		Story.reset_active_presentation(&"load")
		_clear()
		main.call("_on_continue_requested")
	else:
		_attempt()

func _reset(_reason: StringName) -> void:
	_clear()

func _clear() -> void:
	if is_instance_valid(_level) and _level.tree_exiting.is_connected(_clear):
		_level.tree_exiting.disconnect(_clear)
	_level = null
	_contract = PackedByteArray()
	_publishing = false
	_recovery = false
	_reload_original = false
	if is_instance_valid(_prompt):
		_prompt.hide()
		_prompt.get_parent().queue_free()
	_prompt = null
	GameplayLock.release(_lock)
	_lock = 0
