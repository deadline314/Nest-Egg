extends Node
## A live training action becomes visible only after its complete run is durable.
## Standalone level tools retain their local behavior; Main owns real runs.
const FlagCommit := preload("res://core/run_flag_commit.gd")
const Prompt := preload("res://ui/radio_save_prompt.gd")
var main: Node
var _station: TrainingStation
var _success := false
var _contract := PackedByteArray()
var _lock := 0
var _prompt: Control
var _publishing := false
var _recovery := false
var _reload_original := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TrainingStation.result_handler = complete
	Story.presentation_reset.connect(_reset)

func _exit_tree() -> void:
	if TrainingStation.result_handler == complete:
		TrainingStation.result_handler = Callable()
	_clear()

func publishing() -> bool:
	return _publishing

func blocks_save() -> bool:
	return is_instance_valid(_station) or _publishing

func complete(station: TrainingStation, success: bool) -> bool:
	if not is_instance_valid(station) or station.is_queued_for_deletion():
		return true
	var level := main.get("_screen") as Level
	if not main.get("_active_run") or level == null or not level.is_ancestor_of(station):
		return false # Standalone previews and isolated Level tests own no Main run.
	if blocks_save() or main.call("_route_pending") or GameplayLock.is_locked() or get_tree().paused:
		return true
	_station = station
	_success = success
	_contract = _signature(station.data)
	if _source() == null:
		_clear()
		push_warning("[TrainingCompletion] training result has no valid live source")
		return true
	var identity := station.get_instance_id()
	station.tree_exiting.connect(func() -> void:
		if is_instance_valid(_station) and _station.get_instance_id() == identity: _clear(), CONNECT_ONE_SHOT)
	_lock = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
	_attempt()
	return true

func _signature(data: TrainingData) -> PackedByteArray:
	return var_to_bytes([data.resource_path, data.id, data.kind, data.requires_flag,
		data.done_flag, data.done_scene, data.fail_flag, data.fail_scene]) if data != null else PackedByteArray()

func _source() -> Level:
	var level := main.get("_screen") as Level
	if not main.get("_active_run") or main.call("_route_pending") or level == null or not level.is_initialized() or level.died or level.data.resource_path != main.get("_level_path"):
		return null
	if not is_instance_valid(_station) or _station.is_queued_for_deletion() or not level._training_stations.has(_station) or not level.is_ancestor_of(_station):
		return null
	var data := _station.data
	if data == null or _signature(data) != _contract or not _station.is_active() or _station.is_done() or not is_instance_valid(level.player) or level.player.is_dead():
		return null
	if data.requires_flag != &"" and not GameState.has_flag(data.requires_flag):
		return null
	var flag := data.done_flag if _success else data.fail_flag
	if flag == &"" or GameState.has_flag(flag) or not GameState.flag_defaults.get(String(flag)) is bool:
		return null
	if not _success and data.kind != TrainingData.Kind.TRAINER:
		return null
	for spawn: Dictionary in level._layout.spawns:
		if is_same(spawn["resource"], data) and _station.position.is_equal_approx(spawn["position"]):
			return level
	return null

func _attempt() -> void:
	if main.has_method("_defer_world_operation") and main.call("_defer_world_operation", _attempt): return
	var level := _source()
	if level == null:
		_clear()
		return
	var result := _commit(level)
	if not result.get("committed", false) or result.get("recovery", false):
		_recovery = result.get("recovery", false)
		_reload_original = result.get("reload_original", false)
		push_warning("[TrainingCompletion] %s: %s" % [_station.data.id, str(result.get("error", "saved result requires reload")).left(512)])
		_show_prompt.call_deferred()
		return
	var station := _station
	var success := _success
	_publishing = true
	station._refresh()
	# The silent flag installation already matches the actual saved primary.
	# All callbacks see the complete result, never a partially accepted action.
	for flag: String in result["changed"]:
		GameState.flag_changed.emit(StringName(flag), GameState.get_flag(StringName(flag)))
	# Release the action lock before starting its original explanation, which owns
	# its own presentation lock. Route changes remain guarded through publication.
	GameplayLock.release(_lock)
	_lock = 0
	if is_instance_valid(station) and level.is_ancestor_of(station):
		if success: station.publish_completion()
		else: station.publish_failure()
	_clear()
	main.call("_queue_save")

func _commit(level: Level) -> Dictionary:
	var data := _station.data
	var flag := String(data.done_flag if _success else data.fail_flag)
	var scene := data.done_scene if _success else data.fail_scene
	return FlagCommit.commit(main, level, {flag: true}, scene, func() -> bool: return _source() == level)

func _show_prompt() -> void:
	if not is_instance_valid(_station): return
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
	else:
		_attempt()

func _reset(_reason: StringName) -> void:
	_clear()

func _clear() -> void:
	_station = null
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
