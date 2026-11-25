extends "res://tools/route_frame_time_probe.gd"
## Live pawnshop overlap and durable notification boundary on an isolated Main.
const DOCUMENT := &"doc_pawn_stub"
const BONUS := 17
const MainScript := preload("res://game/main.gd")

class DeferredMain extends MainScript:
	var hold_pickup := false
	var pickup_attempts: Array[Callable] = []

	func _defer_world_operation(callback: Callable) -> bool:
		if hold_pickup and callback.get_object() == get("_world_item_completion"):
			pickup_attempts.append(callback)
			return true
		return super._defer_world_operation(callback)

class PickupStore extends RunSaveStore:
	var refuse_commit := false

	func _durable_rename(absolute: String, phase: DurablePhase) -> Error:
		if refuse_commit and phase == DurablePhase.PRIMARY_COMMITTED:
			return ERR_CANT_CREATE
		return super._durable_rename(absolute, phase)

var _mode := "ordinary"
var _check_count := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
	super._ready()
	set_process(false)


func _run() -> void:
	Story.auto_skip = true
	_main = load("res://scenes/main.tscn").instantiate()
	if _mode == "deferred":
		_main.set_script(DeferredMain)
	var store := PickupStore.new(_slot_path)
	_main.set("_run_store", store)
	add_child(_main)
	if not await _wait_menu():
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	if not await _level("ch1_prologue") or not await _portal("pawnshop", "ch1_pawnshop"):
		return
	var level := _main.get("_screen") as Level
	level._next_story_trigger = level._layout.story_triggers.size()
	var site: CollectiblePickup
	for value: Variant in level._tracked.values():
		if value is CollectiblePickup and (value as CollectiblePickup).item.id == DOCUMENT:
			site = value
			break
	if not _check(site != null and not StoryItems.owns(DOCUMENT), "the actual document starts uncollected"):
		return
	var player := level.player
	var owner: Node = _main.get("_world_item_completion")
	player.teleport_to(site.global_position + Vector2(-39.0,0.0))
	level.camera.snap_to_target()
	AimInput.set_virtual_gamepad(player, true)
	AimInput.restore_direction(Vector2.RIGHT)
	await get_tree().create_timer(0.2,true,false,true).timeout
	var before_credits := Progression.credits
	var seen := [0, false]
	StoryItems.acquired.connect(func(item: StoryItemData) -> void:
		if item.id != DOCUMENT:
			return
		seen[0] += 1
		var disk := store.read()
		seen[1] = String(DOCUMENT) in disk["story"]["items"]["owned"] and String(DOCUMENT) in disk["story"]["items"]["held"]
		owner.call("collect",site,player)
		if _mode == "listener":
			Progression.add_credits(BONUS))
	var blocked := store.path + ".tmp"
	var before_bytes := FileAccess.get_file_as_bytes(store.path)
	if _mode == "refusal" and not _check(DirAccess.make_dir_absolute(blocked) == OK,"isolated draft obstruction was established"):
		return
	store.refuse_commit = _mode == "rollback"
	if _mode == "deferred" and not await _deferred_reentry(_main as DeferredMain, site, player, store):
		return
	Input.action_press(&"move_right")
	if _mode in ["refusal", "rollback"]:
		if not await _until(func() -> bool: return is_instance_valid(owner.get("_prompt"))):
			return
		if not _check(GameplayLock.is_locked() and get_tree().paused and FileAccess.get_file_as_bytes(store.path) == before_bytes
				and not StoryItems.owns(DOCUMENT) and seen[0] == 0,"refusal keeps the actual modal lock without publishing the item or slot"):
			return
		if _mode == "refusal" and not _check(DirAccess.remove_absolute(blocked) == OK,"only the test draft obstruction is removed"):
			return
		store.refuse_commit = false
		owner.get("_prompt").retry_button.pressed.emit()
	if not await _until(func() -> bool: return StoryItems.owns(DOCUMENT) and not owner.call("blocks_save")):
		return
	if not _check(seen[0] == 1 and seen[1] and not GameplayLock.is_locked(),"observer sees durable custody and reentrancy settles just once"):
		return
	if _mode == "ordinary":
		var picked_x := player.position.x
		await get_tree().create_timer(0.22,true,false,true).timeout
		if not _check(Input.is_action_pressed(&"move_right") and player.position.x >= picked_x+10.0,
				"held movement continues after the automatic pickup without a new press"):
			return
	Input.action_release(&"move_right")
	var expected := before_credits + (BONUS if _mode == "listener" else 0)
	if not await _until(func() -> bool: return int(store.read().get("progression",{}).get("credits",-1)) == expected):
		return
	if not _check(Progression.credits == expected,"independent listener balance survives the post-commit save"):
		return
	if _active_capture:
		await RenderingServer.frame_post_draw
		if not _check(CAPTURE.image(get_viewport()).save_jpg(_out.path_join("NE-379-pickup.jpg"), 0.83) == OK,
				"the actual document notification was captured"):
			return
	print("PICKUP_OUTCOME ",_mode," ",_check_count," checks")
	_main.call("_quit",0)


func _deferred_reentry(context: DeferredMain, site: CollectiblePickup, player: Player, store: RunSaveStore) -> bool:
	context.hold_pickup = true
	Input.action_press(&"move_right")
	if not await _until(func() -> bool: return context.pickup_attempts.size() == 1):
		return false
	Input.action_release(&"move_right")
	Story.reset_active_presentation(&"leave")
	player.teleport_to(site.global_position + Vector2(-39.0, 0.0))
	await get_tree().create_timer(0.2, true, false, true).timeout
	Input.action_press(&"move_right")
	if not await _until(func() -> bool: return context.pickup_attempts.size() == 2):
		return false
	var before := FileAccess.get_file_as_bytes(store.path)
	context.hold_pickup = false
	context.pickup_attempts[0].call()
	if not _check(not StoryItems.owns(DOCUMENT) and FileAccess.get_file_as_bytes(store.path) == before,
			"an older deferred attempt cannot settle a later reservation on the same pickup"):
		return false
	context.pickup_attempts[1].call()
	return true


func _until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 4500
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	_fail("timed out waiting for active pickup state: " + _mode)
	return false


func _check(value: bool, detail: String) -> bool:
	if not value:
		_fail(detail)
		return false
	_check_count += 1
	print("PASS ",detail)
	return true
