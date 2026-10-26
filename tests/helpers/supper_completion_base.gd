extends "res://tools/run_save_probe.gd"
const ROOM := "res://data/levels/ch1_stall.tres"
const TARGETS := {
	"pay":"ch1_t_supper_pay", "tab":"ch1_t_supper_tab", "host":"ch1_t_supper_stay_host",
	"host_none":"ch1_t_supper_stay_host_none", "meal":"ch1_t_supper_stay_meal",
	"address":"ch1_t_supper_stay_address", "leave_none":"ch1_t_supper_leave_none",
	"return":"ch1_t_supper_return", "choice_leave":"ch1_t_supper_choice_ordered",
	"choice_stay":"ch1_t_supper_choice_none", "choice_host":"ch1_t_supper_host_prompt",
	"choice_tab":"ch1_t_supper_tab_confirm",
}
var store: RunSaveStore
var target: StringName
var out := ""
var original := PackedByteArray()
var facts_before := PackedByteArray()
var faulted := false
var skip_sent := false
var choosing := false
var before_count := -1

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	super._ready()

func _open_source() -> NpcActor:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = false
	target = StringName(TARGETS.get(_mode, ""))
	choosing = _mode.begins_with("choice")
	_check(target != &"", "bounded probe selects an actual authored supper boundary")
	_main = MainScript.new()
	store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(5)
	var kind := "none" if _mode in ["host_none", "leave_none", "choice_stay"] else "ordered"
	var seed := FileAccess.get_file_as_bytes("res://tests/fixtures/supper_evening_" + kind + ".json")
	_check(not seed.is_empty() and RunSaveCodec.decode(seed.get_string_from_utf8()).has("data"), "exact original completed-evening primary has its original checksum")
	FileAccess.open(store.path, FileAccess.WRITE).store_buffer(seed)
	_main.call("_on_continue_requested")
	await _until(func() -> bool: return _main.get("_screen") is Level and not _main.call("_route_pending"))
	_check(GameState.has_flag(&"ch1_lounge_evening_done") and not GameState.has_flag(&"ch1_supper_done") and not GameState.has_flag(&"knows_ali_address") and Progression.credits == 233, "actual evening producer has no arranged supper result or target wallet")
	_main.call("_on_area_requested", ROOM)
	await _until(func() -> bool: return _main.get("_level_path") == ROOM and _main.get("_screen") is Level and (_main.get("_screen") as Level).is_initialized() and not _main.call("_route_pending"))
	await _frames(8)
	var actor := _actor()
	_check(actor != null and actor.is_present() and actor.talk_count == 0, "actual authored stall Ali starts with no completed supper encounter")
	if actor == null:
		return null
	(_main.get("_screen") as Level).player.global_position = actor.global_position + Vector2(-40, 0)
	await _frames(6)
	Story.scene_started.connect(_inject)
	return actor

func _run() -> void:
	var actor := await _open_source()
	if actor == null:
		await _finish()
		return
	actor._talk()
	await _drive()
	_check(faulted, "real authored menu reaches the exact selected supper boundary")
	if faulted:
		await _frames(5)
		_check(_facts() == facts_before and FileAccess.get_file_as_bytes(store.path) == original, "actual refusal preserves every fact and exact original primary")
		_check(_actor().talk_count == before_count and _actor()._talking, "actual refusal preserves its real unsettled original NPC")
		_check(Story._current_cinematic == target and _prompt() != null and get_tree().paused, "actual refusal owns the same segment and real persistent retry modal")
		if choosing:
			var player: CutscenePlayer = Story._player if is_instance_valid(Story._player) else null
			_check(player != null and player.choice_active() and player._chosen == -1, "refused material choice stays unanswered at original actual menu")
		_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only the owned filesystem obstruction")
	await _finish()

func _inject(id: StringName, _kind: StringName) -> void:
	if not choosing and id == target and not faulted:
		_fault()

func _fault() -> void:
	faulted = true
	original = FileAccess.get_file_as_bytes(store.path)
	facts_before = _facts()
	before_count = _actor().talk_count
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "create genuine temporary-directory IO refusal at the original boundary")

func _wanted() -> String:
	var id := String(Story._current_cinematic)
	if id in ["ch1_t_supper_choice_ordered", "ch1_t_supper_choice_none"]:
		return "stay" if _mode in ["host", "host_none", "meal", "address", "return", "choice_stay", "choice_host"] else "leave"
	if id == "ch1_t_supper_leave_options":
		return "pay" if _mode == "pay" else "defer"
	if id == "ch1_t_supper_tab_confirm":
		return "confirm"
	if id in ["ch1_t_supper_host_prompt", "ch1_t_supper_host_none_prompt"]:
		return "return" if _mode == "return" else "accept"
	return "return"

func _drive() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if faulted and (_prompt() != null or (skip_sent and Story._current_cinematic != target)):
			return
		var player: CutscenePlayer = Story._player if is_instance_valid(Story._player) else null
		if is_instance_valid(player) and player.choice_active():
			var wanted := _wanted()
			var index := player._choice_options.find_custom(func(option: Dictionary) -> bool: return option.get("id") == wanted)
			_check(index >= 0, "original menu exposes the authored " + wanted + " option")
			if choosing and Story._current_cinematic == target and not faulted:
				_fault()
				_check(not player.choose(index), "real IO refusal cannot consume material choice")
				return
			_check(index >= 0 and player.choose(index), "actual original menu accepts " + wanted)
		elif faulted and not skip_sent and is_instance_valid(player) and player.is_running():
			skip_sent = true
			Story.skip_cinematic()
		elif is_instance_valid(player) and player.is_running() and player._dialogue.visible:
			player._dialogue.complete()
			player._advance_requested = true
		elif Story._layer.is_cinematic_active():
			Story._layer.advance()
		await _frames(1)
	_check(false, "actual authored supper reaches its exact IO boundary within bounded time")

func _actor() -> NpcActor:
	for node: Node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and node.data.id == &"ch1_ali_stall" and (_main.get("_screen") as Level).is_ancestor_of(node):
			return node
	return null

func _prompt() -> Control:
	return (_main.get("_result_completion") as Node).get("_prompt") as Control

func _facts() -> PackedByteArray:
	return var_to_bytes([GameState.world_flags, Story.progress_snapshot(), StoryItems.snapshot(), Progression.snapshot()])

func _until(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await _frames(1)
	_check(predicate.call(), "actual Main original area settles within bounded time")

func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"mode":_mode,"target":String(target),"checks":_checks,"failures":Array(_failures),"before_count":before_count},"  "))
	print("[SupperBoundary] %s checks=%d failures=%d" % [_mode,_checks,_failures.size()])
	_main.call("_quit", 0 if _failures.is_empty() else 1)
