extends Node
var _mode := "main_0"
var _main: Node
var _out := ""
var _checks := 0
var _issues: Array[String] = []
var _trace: Dictionary = {}
func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		if arg.begins_with("--mode="): _mode = arg.trim_prefix("--mode=")
	Engine.max_fps = int(_mode.get_slice("_",1))
	DirAccess.make_dir_recursive_absolute(_out)
	Transition.instant = true
	_run.call_deferred()
func _check(ok: bool, text: String) -> void:
	_checks += 1
	print(("PASS " if ok else "FAIL ") + text)
	if not ok: _issues.append(text)
func _run() -> void:
	_main = load("res://game/main.gd").new()
	add_child(_main)
	for i in 8: await get_tree().process_frame
	Sfx.set_preview(&"ui_error", load("res://audio/sfx/beep_02.ogg"))
	_check(Sfx._play_voice(&"ui_error",-12.0,1.0,100),"ordinary runtime accepts the original Vorbis effect")
	Music.stop(0.0)
	var cue := Music.screen_cue(&"menu")
	_check(Music.play_cue(cue,true) and Music.is_playing(),"ordinary runtime accepts the original menu music")
	Ambience.set_zone(&"rooftop")
	_check(Ambience.playing_layers()>0,"ordinary runtime accepts its original ambience layers")
	await get_tree().create_timer(0.05,true,false,true).timeout
	if DisplayServer.get_name() != "headless":
		preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(_out.path_join("menu.png"))
	if _mode.begins_with("settle_"):
		_settle_and_quit()
	else:
		_main.call("_quit",0)
	# Registered after Main's own first process wait: its settle has stopped owners.
	await get_tree().process_frame
	_trace["quitting"]=_main.get("_quitting")
	_trace["stopped"]={"sfx":Sfx.voices_playing(),"music":Music.is_playing(),"ambience":Ambience.playing_layers()}
	_check((_mode.begins_with("settle_") or _trace["quitting"]) and Sfx.voices_playing()==0,"real Main quit has stopped effects before the delayed request")
	_check(not Music.is_playing(),"real Main quit has stopped music before the delayed request")
	_check(Ambience.playing_layers()==0,"real Main quit has stopped ambience before the delayed request")
	var late := Sfx._play_voice(&"ui_error",-12.0,1.0,100)
	_trace["late_effect_accepted"]=late
	_check(not late,"terminal quit refuses a deferred effect after stopping its voices")
	var late_music := Music.play_cue(cue,true)
	_trace["late_music_accepted"]=late_music
	_check(not late_music and not Music.is_playing(),"terminal quit refuses deferred music after stopping its owner")
	Ambience.set_zone(&"rooftop")
	_trace["late_ambience_layers"]=Ambience.playing_layers()
	_check(Ambience.playing_layers()==0,"terminal quit refuses deferred ambience after stopping its owner")
	DirAccess.make_dir_recursive_absolute(_out)
	FileAccess.open(_out.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":_checks,"failures":_issues,"trace":_trace},"  "))

func _settle_and_quit() -> void:
	await AudioRelease.settle(get_tree())
	get_tree().quit(0)
