extends "res://tools/ch2_resume_probe.gd"
## Uses an isolated completed-Chapter-3 fixture and the real Main save route.
## --mode=write plays the ward investigation. --mode=continue cold-reads its save.
## Pass --save-dir=<absolute scratch directory> and --out=<absolute screenshot directory>.

const TERMINAL := "res://data/levels/ch3_pawnshop.tres"
const ENTRY := "res://data/levels/ch4_pawnshop.tres"
const RECEPTION := "res://data/levels/ch4_ward_reception.tres"
const WARD := "res://data/levels/ch4_nursing_ward.tres"
const SLIP := &"ch4_ward_collection_slip"
const CONSENT := &"ch4_linden_visit_confirmed"
const DESK := &"ch4_desk_demo_read"
const VOICE := &"ch4_voice_demo_read"
var _saved_capture := false


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	super._ready()
	level_pattern = "res://data/levels/ch4_%s.tres"


func _write() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	GameState.set_flag(&"ch3_shore_closed")
	GameState.set_flag(&"ch3_next_sunday_agreed")
	GameState.set_flag(&"ch3_told_egret_trade")
	GameState.set_flag(&"sq2_sunday_heard")
	GameState.set_flag(&"room_choice", "quiet")
	GameState.set_flag(&"sq7_ahan_recording_held")
	StoryItems.acquire(&"ch3_ahan_tape")
	StoryItems.acquire(&"ch3_petition_receipt")
	var store := _main.get("_run_store") as RunSaveStore
	var fixture := RunSnapshot.capture(TERMINAL, {"position": [800, 320], "health": 4, "world": {}, "loadout": {}}, "", true)
	_check(store.write(fixture, true), "prepared completed Chapter 3 snapshot with optional room and recording")
	var deadline := Time.get_ticks_msec() + ProbeMainRoute.LIMIT_MSEC
	while bool(_main.call("_route_pending")) and Time.get_ticks_msec() < deadline:
		await _settle(10)
	if bool(_main.call("_route_pending")):
		_check(false, "Main settles on the continue screen before loading the fixture")
		return
	_main.call("_on_continue_requested")
	if not await _route_main.wait_level(ENTRY):
		_check(false, "Main continues from Chapter 3 terminal to the following Sunday")
		return
	_level = _route_main.level()
	_check(_level.data.chapter == &"ch4_hollow", "the saved Chapter 3 completion resumes in the Chapter 4 pawnshop")
	await _settle(75)
	for frame in STEP_LIMIT:
		if not Story.is_cinematic_active():
			break
		Story.skip_cinematic()
		await _settle(6)
	if Story.is_cinematic_active():
		_check(false, "the chapter card completes before the opening interaction")
		return
	var front: Portal = _level._portals[&"pawn_ward"]
	_check(not front.try_use(), "the front door gives a lock reason before wrapping the receipt")
	await _talk(&"ch4_old_k")
	_check(GameState.has_flag(&"ch4_documents_wrapped"), "Old K publishes the receipt wrapping")
	if not await _portal(&"pawn_ward", RECEPTION):
		return
	_check(not (_level._portals[&"reception_ward"] as Portal).try_use(), "the ward is locked before sign-in")
	await _talk(&"ch4_egret", ["leave"])
	_check(not GameState.has_flag(&"ch4_visit_signed"), "leaving preserves the visitor lock")
	await _talk(&"ch4_egret", ["sign"])
	_check(_played.has("ch4_t_traded_before") and _played.has("ch4_t_sunday_before"), "the carried optional choices produce their exact visit lines")
	if not await _portal(&"reception_ward", WARD):
		return
	await _talk(&"ch4_cabinet")
	_check(not GameState.has_flag(CONSENT), "the cabinet never implies consent before asking Linden")
	await _talk(&"ch4_linden")
	await _settle(120)
	_capture("ward-visit-final")
	await _talk(&"ch4_voice_demo")
	_check(GameState.has_flag(VOICE) and not GameState.has_flag(DESK), "one may read the upstairs demonstration first")
	await _talk(&"ch4_cabinet")
	_check(not StoryItems.holds(SLIP), "one clue will not open the cabinet")
	await _talk(&"ch4_desk_demo")
	await _talk(&"ch4_cabinet", ["voice_first", "single_tap", "sequence"])
	_check(StoryItems.holds(SLIP) and GameState.has_flag(&"ch4_collection_slip_saved"), "wrong attempts retry immediately and only the right sequence grants the document")
	var published := store.read()
	_check((published.get("story", {}) as Dictionary).get("flags", {}).get("ch4_collection_slip_saved") == true, "the cabinet completion is in the primary save before exit")
	await _talk(&"ch4_staff_switch")
	_check(GameState.has_flag(&"ch4_inner_exit_open"), "the interior release opens a separate route")
	if not await _portal(&"ward_staff", RECEPTION):
		return
	await _portal(&"reception_staff", WARD)


func _continue() -> void:
	var data := await _route_main.continue_game()
	_level = _route_main.level()
	_check(data.get("level") == WARD and _level != null, "a cold process resumes in the ward")
	if _level == null:
		return
	_check(StoryItems.holds(SLIP) and StoryItems.holds(&"ch3_ahan_tape") and StoryItems.holds(&"ch3_petition_receipt"), "the ward form and earlier documents survive the cold load")
	_check(GameState.get_flag(&"room_choice") == "quiet", "the Far Shore room proposal is preserved")
	_check(GameState.has_flag(CONSENT) and GameState.has_flag(DESK) and GameState.has_flag(VOICE), "all investigation records survive the cold load")
	_check(Story.resolve_dispatch(&"ch4_dispatch_desk_demo") == &"ch4_t_desk_demo_replay", "rereading a demonstration uses the read-only replay")
	_check(Story.resolve_dispatch(&"ch4_dispatch_cabinet") == &"ch4_t_read_slip_again", "the completed cabinet offers read-only summary after reload")
	await _talk(&"ch4_cabinet")
	_check(StoryItems.holds(SLIP), "rereading leaves the same document in the notebook")


func _portal(id: StringName, destination: String) -> bool:
	var portal := _level._portals.get(id) as Portal
	var opened := portal != null and portal.try_use()
	_check(opened, "travel through %s" % id)
	if not opened:
		return false
	var arrived := await _route_main.wait_level(destination, _level)
	_check(arrived, "Main settles the authored destination %s" % destination.get_file())
	if arrived:
		_level = _route_main.level()
		await _settle(40)
	return arrived


func _capture(name: String) -> void:
	if _saved_capture or DisplayServer.get_name() == "headless":
		return
	_saved_capture = true
	var screenshot := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(screenshot.save_jpg(_out_dir.path_join(name + ".jpg"), 0.89) == OK, "captured the Forward+ ward scene")
