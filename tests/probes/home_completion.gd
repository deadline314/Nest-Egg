extends "res://tests/probes/channel_completion.gd"
## Actual terminal dawn intro; prerequisites are fixtures, ending results are not.
const HOME := &"ch1_c14_home"
const AREA := "res://data/levels/ch1_pawnshop_dawn.tres"
const Sources := preload("res://game/story_flag_sources.gd")
var _store: RunSaveStore
var _original_scene: Dictionary
var _original_source: String
var _notices := 0
var _publications: Array[Dictionary] = []
var _started := false
var _selected := false
var _replaying := false

func _run() -> void:
	_main = load("res://game/main.gd").new()
	_store = RunSaveStore.new(_save_dir.path_join("slot.json"))
	_main.set("_run_store", _store)
	add_child(_main)
	await _frames(8)
	if _mode.ends_with("_read"):
		_main.call("_on_continue_requested")
		await _frames(12)
		_check(_main.get("_screen") is VictoryScreen, "cold accepted original home restores its real chapter completion screen")
		_check(GameState.has_flag(&"ch1_home_done") and GameState.has_flag(&"ch1_complete") and Story._completed.has(HOME), "cold accepted original restores both real ending results and history")
		_check(_prompt() == null and not get_tree().paused, "cold accepted ending has no stale recovery scope")
		await _shot("home-cold")
		await _done()
		return
	_check(_mode in ["intact", "missing", "shifted", "malformed", "foreign", "choice", "source", "condition"], "supported finite original ending fixture")
	if not _mode in ["intact", "missing", "shifted", "malformed", "foreign", "choice", "source", "condition"]:
		await _done()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _frames(90)
	await _finish_story()
	await _wait_control()
	GameState.set_flag(&"ch1_supper_done", true, false)
	GameState.set_flag(&"ch1_handoff_done", true, false)
	_check(not GameState.has_flag(&"ch1_home_done") and not GameState.has_flag(&"ch1_complete") and not Story._completed.has(HOME), "original ending results are genuinely absent before its actual original intro")
	_original_scene = Story._scenes[String(HOME)].duplicate(true)
	_original_source = Story._scene_sources[String(HOME)]
	_check(Sources.valid(String(HOME), Story._scenes, Story._scene_sources), "original authored home matches its independent finite contract")
	var scene: Dictionary = Story._scenes[String(HOME)]
	match _mode:
		"missing": scene.erase("completion_policy")
		"shifted": scene["completion_policy"] = "main_terminal_results_v1"
		"malformed": scene["completion_policy"] = {"unsupported": "policy"}
		"foreign": scene.results[0].id = "ch1_label_guitar_seen"
		"source": Story._scene_sources[String(HOME)] = "res://data/story/chapter_01.json"
		"condition": scene["when"] = {"not": {"flag": "ch1_home_done", "equals": true}}
		"choice":
			scene.erase("completion_policy")
			scene.steps = [{"do": "choice", "text": "Declared unregistered ending choice fixture", "default": "inject", "options": [{"id": "inject", "text": "Attempt an unregistered result", "set_flags": {"ch1_home_done": true}}, {"id": "leave", "text": "Leave"}]}]
	Story.scene_started.connect(_on_home_started)
	GameState.flag_changed.connect(_on_home_flag)
	_main.call("_on_area_requested", AREA)
	await _frames(12)
	_check(_started and _level() != null and _level().data.resource_path == AREA, "real Main enters the original dawn area and requests its actual ending intro")
	_before = FileAccess.get_file_as_bytes(_store.path)
	FileAccess.open(_out.path_join("entry-primary.json"), FileAccess.WRITE).store_buffer(_before)
	_check(not _before.is_empty(), "actual original entry primary exists before completion refusal")
	await _drive_home()
	await _frames(4)
	_check(not GameState.has_flag(&"ch1_home_done") and not GameState.has_flag(&"ch1_complete") and not GameState.has_flag(&"ch1_label_guitar_seen"), "refused original ending cannot publish its own or another declared result")
	_check(not Story._completed.has(HOME) and _notices == 0, "unaccepted ending has no completed history or premature flag notifications")
	_check(FileAccess.get_file_as_bytes(_store.path) == _before, "refusal preserves exact complete original entry primary bytes")
	_check(_prompt() != null and get_tree().paused and not _main.get("_chapter_complete"), "original flag owner keeps its real pending ending and recovery UI")
	_check(_main.get("_result_completion").get("_prompt") == null, "ending cannot move to another result owner when its policy changes")
	_check(bool(_main.get("_story_completion").get("_reload_original")) == (_mode != "intact"), "semantic corruption requires original recovery while ordinary IO remains retryable")
	if _mode == "choice": _check(_selected, "fixture actually selects its unregistered choice through the real player")
	FileAccess.open(_out.path_join("refused-primary.json"), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(_store.path))
	await _shot("home-" + _mode + "-refused")
	_replaying = true
	Story._scenes[String(HOME)] = _original_scene
	Story._scene_sources[String(HOME)] = _original_source
	if _mode == "intact":
		_check(DirAccess.remove_absolute(_store.path + ".tmp") == OK, "remove only the owned IO obstruction for the same original retry")
	if _prompt() != null: _prompt().retry_button.pressed.emit()
	await _frames(12)
	if _mode != "intact":
		_check(_prompt() == null and not GameState.has_flag(&"ch1_home_done") and not Story._completed.has(HOME), "whole-original recovery first reconstructs the actual unread ending")
	await _drive_home()
	for frame in 900:
		if _main.get("_screen") is VictoryScreen: break
		await _frames(1)
	_check(_main.get("_screen") is VictoryScreen and _main.get("_chapter_complete"), "genuinely accepted original intro reaches its actual chapter completion screen")
	_check(GameState.has_flag(&"ch1_home_done") and GameState.has_flag(&"ch1_complete") and Story._completed.has(HOME), "accepted original ending installs exactly its two original results and completed history")
	_check(not GameState.has_flag(&"ch1_label_guitar_seen") and _notices == 2, "only the accepted original ending publishes exactly two original result notifications")
	_check(_prompt() == null and not get_tree().paused, "accepted original ending releases its own recovery scope")
	var decoded := RunSaveCodec.decode(FileAccess.get_file_as_string(_store.path))
	_check(decoded.has("data") and decoded.data.chapter_complete and decoded.data.cinematic == "", "real settled primary records actual chapter completion without an unread cinematic")
	await _shot("home-" + _mode + "-accepted")
	await _done()

func _on_home_started(id: StringName, _kind: StringName) -> void:
	if id != HOME: return
	_started = true
	if _mode == "intact" and not _replaying:
		_check(DirAccess.make_dir_absolute(_store.path + ".tmp") == OK, "owned ordinary IO obstruction starts only at the actual original ending")

func _on_home_flag(flag: StringName, _value: Variant) -> void:
	if flag not in [&"ch1_home_done", &"ch1_complete", &"ch1_label_guitar_seen"]: return
	_notices += 1
	_check(flag in [&"ch1_home_done", &"ch1_complete"], "original ending cannot publish an unrelated declared flag")
	_check(GameState.has_flag(&"ch1_home_done") and GameState.has_flag(&"ch1_complete") and Story._completed.has(HOME), "every original ending observer sees all installed original results and history")
	var raw := FileAccess.get_file_as_string(_store.path)
	var decoded := RunSaveCodec.decode(raw)
	_check(decoded.has("data") and decoded.get("issues", []).is_empty(), "original ending publication primary retains its complete valid checksum")
	if not decoded.has("data"): return
	var disk: Dictionary = decoded.data
	_check(disk.story.flags.get("ch1_home_done", false) and disk.story.flags.get("ch1_complete", false) and disk.story.seen.has(String(HOME)) and disk.cinematic == "", "first ending observers see both real results and history durably installed before the chapter card settles")
	var filename := "publication-" + str(_publications.size()) + ".json"
	FileAccess.open(_out.path_join(filename), FileAccess.WRITE).store_string(raw)
	_publications.append({"flag": String(flag), "primary": filename, "chapter_complete": disk.chapter_complete})

func _drive_home() -> void:
	for frame in 1800:
		if _prompt() != null or _main.get("_screen") is VictoryScreen: return
		if is_instance_valid(Story._player) and Story._player.choice_active():
			_selected = true
			Story._player.choose(0)
		elif Story._current_cinematic == HOME:
			Story.skip_cinematic()
		elif _started and not Story.is_cinematic_active(): return
		await _frames(1)
	_check(false, "actual original ending settles or refuses within its bounded frame guard")

func _prompt() -> Control:
	var owner: Node = _main.get("_story_completion")
	return owner.get("_prompt") as Control if is_instance_valid(owner) else null

func _done() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var file := FileAccess.open(_out.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"mode": _mode, "checks": _checks, "failures": _issues, "publications": _publications}, "  "))
		file.close()
	else:
		_check(false, "original ending result receipt is writable")
	Story.reset_active_presentation(&"menu")
	_main.call("_quit", 0 if _issues.is_empty() else 1)
