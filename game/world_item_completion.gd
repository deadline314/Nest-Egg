extends Node
## The actual world source, item custody and objective become durable together.
const Bundle = preload("res://core/story_install_bundle.gd")
const Prompt = preload("res://ui/radio_save_prompt.gd")
var main: Node
var _pickup: CollectiblePickup
var _player: Player
var _generation := 0
var _lock := 0
var _prompt: Control
var _publishing := false
var _recovery := false
var _reload_original := false
var _suppressed: CollectiblePickup
var _suppressed_player: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	StoryItems.world_pickup_handler = collect
	Story.presentation_reset.connect(_reset)

func _exit_tree() -> void:
	if StoryItems.world_pickup_handler == collect:
		StoryItems.world_pickup_handler = Callable()
	_clear()

func publishing() -> bool:
	return _publishing

func blocks_save() -> bool:
	return is_instance_valid(_pickup) or _publishing

func _overlaps(pickup: CollectiblePickup, player: Player) -> bool:
	if not is_instance_valid(pickup) or not is_instance_valid(player):
		return false
	return pickup.get_overlapping_bodies().any(func(body: Node2D) -> bool: return Pickup.resolve_player(body) == player)

func _process(_delta: float) -> void:
	if not _overlaps(_suppressed, _suppressed_player):
		_suppressed = null
		_suppressed_player = null
		set_process(false)

func collect(pickup: CollectiblePickup, player: Player) -> void:
	if _publishing or is_instance_valid(_pickup) or pickup == _suppressed or GameplayLock.is_locked() or get_tree().paused:
		return
	if _source(pickup, player).is_empty():
		return
	_pickup = pickup
	_player = player
	_generation += 1
	var generation := _generation
	pickup.tree_exiting.connect(func() -> void:
		if is_instance_valid(_pickup) and generation == _generation:
			_clear(), CONNECT_ONE_SHOT)
	# Collection completes in this turn. Reserving the pickup prevents another
	# operation from taking it without consuming gameplay input.
	_attempt(generation)

func _source(pickup: CollectiblePickup, player: Player) -> Dictionary:
	var level := main.get("_screen") as Level
	if not main.get("_active_run") or bool(main.call("_route_pending")) or level == null or not level.is_initialized() or level.died or level.data.resource_path != main.get("_level_path"):
		return {}
	if not is_instance_valid(pickup) or pickup.is_queued_for_deletion() or not level.is_ancestor_of(pickup) or player != level.player or player.is_dead() or not _overlaps(pickup, player):
		return {}
	if pickup.item == null or StoryItems.find(pickup.item.id) != pickup.item:
		return {}
	for key: String in level._tracked:
		if is_same(level._tracked[key], pickup):
			for spawn: Dictionary in level._layout.spawns:
				if level._spawn_key(spawn) == key and spawn["resource"] == pickup.item:
					return {"level": level, "key": key}
	return {}

func _attempt(generation: int) -> void:
	if _publishing or not is_instance_valid(_pickup) or generation != _generation:
		return
	if main.has_method("_defer_world_operation") and main.call("_defer_world_operation", _attempt.bind(generation)):
		return
	var source := _source(_pickup, _player)
	if source.is_empty():
		_clear()
		return
	var result := _commit(source)
	if not is_instance_valid(_pickup) or generation != _generation:
		return
	if not result.get("committed", false) or result.get("recovery", false):
		_recovery = result.get("recovery", false)
		_reload_original = result.get("reload_original", false)
		if _lock == 0:
			_lock = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
		push_warning("[WorldItemCompletion] %s: %s" % [_pickup.item.id, result.get("error", "committed pickup requires reload")])
		_show_prompt.call_deferred()
		return
	var item := _pickup.item
	_publishing = true
	_pickup.complete_collection()
	# Every listener observes matching durable custody, objective and world source.
	if result["first_acquisition"]:
		StoryItems.acquired.emit(item)
		EventBus.toast_requested.emit(StoryItems.acquire_message(item))
	for flag: String in result["changed"]:
		GameState.flag_changed.emit(StringName(flag), GameState.get_flag(StringName(flag)))
	_clear()
	# The committed slot already includes the pickup. Save again only for changes
	# made to the live state during its notifications.
	if _listener_save_needed(source["level"], result):
		main.call("_queue_save")
	if result["first_acquisition"] and item.play_scene != &"":
		Story.play(item.play_scene)

func _commit(source: Dictionary) -> Dictionary:
	var level: Level = source["level"]
	var candidate := RunSnapshot.capture(main.get("_level_path"), level.run_snapshot(), "", main.get("_chapter_complete"))
	var decoded := RunSaveCodec.round_trip(candidate)
	if decoded.has("error"):
		return decoded
	var original := RunSnapshot.prepare(decoded["data"], level.data, level._layout)
	if original.has("error"):
		return original
	for pair: Array in [[original["data"]["story"]["items"], StoryItems.snapshot()], [original["data"]["story"]["flags"], GameState.world_flags], [original["data"]["progression"], Progression.snapshot()]]:
		if JSON.parse_string(JSON.stringify(pair[0])) != JSON.parse_string(JSON.stringify(pair[1])):
			return {"error": "world pickup requires restoring the complete original run first", "reload_original": true}
	candidate = original["data"].duplicate(true)
	var proof := Bundle.capture_world_pickup_source()
	if proof.has("error"):
		return proof
	var seal: Bundle.SourceSeal = proof["data"]
	var item := _pickup.item
	var first_acquisition := not StoryItems.owns(item.id)
	if first_acquisition:
		for key: String in ["owned", "held", "unseen"]:
			candidate["story"]["items"][key].append(String(item.id))
	if item.acquire_flag != &"":
		if not GameState.flag_defaults.has(item.acquire_flag):
			return {"error": "unknown acquisition flag"}
		candidate["story"]["flags"][String(item.acquire_flag)] = true
	var key: String = source["key"]
	candidate["runtime"]["area"]["consumed"][key] = true
	if level._persistent:
		candidate["state"]["area_states"][String(level.data.id)]["consumed"][key] = true
	var store: RunSaveStore = main.get("_run_store")
	if store.overwrite_authorized and not store.write(original["data"]):
		return {"error": "initial save: " + "; ".join(store.issues)}
	var prepared := store.prepare_existing_write(candidate, level)
	if prepared.has("error"):
		return prepared
	var write: RunSaveStore.PreparedExistingWrite = prepared["data"]
	var normalized := write.snapshot()
	var committed_values: Variant = JSON.parse_string(JSON.stringify(normalized))
	if committed_values != JSON.parse_string(JSON.stringify(candidate)):
		return {"error": "world pickup needs a whole-run repair before retry", "reload_original": true}
	var game := GameState.prepare_install(normalized["state"], normalized["story"]["flags"], "", false)
	var items := StoryItems.prepare_install(normalized["story"]["items"])
	for owner: Dictionary in [game, items]:
		if owner.has("error"):
			return owner
	var changed: Array[String] = []
	for flag: String in game["data"].flags:
		if GameState.get_flag(StringName(flag)) != game["data"].flags[flag]:
			changed.append(flag)
	if not seal.matches() or _source(_pickup, _player).is_empty():
		return {"error": "live pickup source changed before durable write"}
	var outcome := store.commit_existing_write(write)
	if not outcome.committed:
		return {"error": "; ".join(outcome.issues), "reload_original": outcome.requires_recovery}
	if outcome.requires_recovery or not seal.matches() or _source(_pickup, _player).is_empty():
		return {"committed": true, "recovery": true}
	# No callbacks, fallible operations or owner replacement between assignments.
	StoryItems._install_prepared(items["data"])
	GameState._install_prepared_flags(game["data"])
	level._area["consumed"][key] = true
	return {"committed": true, "changed": changed, "first_acquisition": first_acquisition,
		"checksum": outcome.checksum, "saved_at": normalized["saved_at"],
		"comparison_payload": JSON.stringify(committed_values)}


func _listener_save_needed(level: Level, committed: Dictionary) -> bool:
	var current: Dictionary = main.call("_snapshot_for_save")
	if current.is_empty():
		return false
	var store: RunSaveStore = main.get("_run_store")
	var checksum: String = committed["checksum"]
	if not is_instance_valid(level) or level.data == null or current.get("level") != level.data.resource_path \
			or FileAccess.get_sha256(store.path) != checksum:
		return true
	current["saved_at"] = committed["saved_at"]
	var encoded := RunSaveCodec.encode(current)
	if encoded.is_empty():
		return true
	if encoded.sha256_text() == checksum:
		return false
	# Compare JSON-decoded values so capture-time integers and saved numeric
	# values use the same representation. A mismatch still needs full preparation.
	var comparable := RunSaveCodec.round_trip(RunSnapshot.capture_with_save_defaults(current))
	if comparable.has("data") and JSON.stringify(comparable["data"]) == committed["comparison_payload"]:
		return false
	var decoded := RunSaveCodec.decode(encoded)
	if not decoded.has("data"):
		return true
	var normalized := RunSnapshot.prepare(decoded["data"], level.data, level._layout)
	return not normalized.has("data") or RunSaveCodec.encode(normalized["data"]).sha256_text() != checksum


func _show_prompt() -> void:
	if not is_instance_valid(_pickup):
		return
	if is_instance_valid(_prompt):
		_prompt.set_recovery(_recovery)
		if _reload_original:
			_prompt.set_original_recovery()
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 110
	add_child(canvas)
	_prompt = Prompt.new()
	_prompt.presentation = "pickup"
	_prompt.retry_requested.connect(_retry)
	_prompt.cancel_requested.connect(_cancel)
	canvas.add_child(_prompt)
	_prompt.set_recovery(_recovery)
	if _reload_original:
		_prompt.set_original_recovery()

func _retry() -> void:
	if _recovery or _reload_original:
		Story.reset_active_presentation(&"load")
		_clear()
		main.call("_on_continue_requested")
	elif is_instance_valid(_pickup):
		_attempt(_generation)

func _cancel() -> void:
	if _recovery:
		return
	_suppressed = _pickup
	_suppressed_player = _player
	set_process(true)
	_clear()

func _reset(_reason: StringName) -> void:
	_suppressed = null
	_suppressed_player = null
	set_process(false)
	_clear()

func _clear() -> void:
	_pickup = null
	_player = null
	_publishing = false
	_recovery = false
	_reload_original = false
	if is_instance_valid(_prompt):
		_prompt.hide()
		_prompt.get_parent().queue_free()
	_prompt = null
	GameplayLock.release(_lock)
	_lock = 0
