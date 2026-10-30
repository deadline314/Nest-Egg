## Owned-profile regression: a pre-existing ordinary save must remain untouched.
extends Node
var _checks := 0
var _failures: Array[String] = []
var _out := ""
var _mode := "existing"
func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--mode="): _mode = arg.trim_prefix("--mode=")
	# This fixture seeds the ordinary slot only inside the runner's owned profile.
	var expected := _out.get_base_dir().path_join(_mode + "-profile").simplify_path() + "/"
	if not _out.is_absolute_path() or _mode != "existing" or not OS.get_user_data_dir().simplify_path().begins_with(expected):
		printerr("Controller storage fixture requires its isolated runner profile")
		get_tree().quit(2)
		return
	_run.call_deferred()
func _check(ok: bool, what: String) -> void:
	_checks += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok: _failures.append(what)
func _run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	GameState.story_autosave = false
	var slot := RunSaveStore.new()
	slot.validator = RunSnapshot.prepare
	var data := RunSnapshot.capture(CampaignEdition.current().first_level, {"position":[-1,-1],"health":6,"loadout":{},"world":{}})
	_check(slot.write(data, true), "owned profile has a real existing normal save")
	var before := FileAccess.get_file_as_bytes(slot.path)
	print("USER_DIR ", OS.get_user_data_dir(), " SLOT ", slot.path)
	Transition.instant = true
	var probe := ControllerFlowProbe.new()
	await probe.run(self, _check)
	_check(FileAccess.get_file_as_bytes(slot.path) == before, "controller probe preserves the exact pre-existing ordinary save")
	DirAccess.make_dir_recursive_absolute(_out)
	FileAccess.open(_out.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":_checks,"failures":_failures},"  "))
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if _failures.is_empty() else 1)
