extends "res://tools/ch4_archive_probe.gd"
## Uses a prior factory office save, actual roof route and the pawnshop actor.


const PAWNSHOP := "res://data/levels/ch4_pawnshop.tres"
const OLD_K := &"ch4_old_k"
const LEDGER_COPY := &"ch4_original_ledger_copy"
const ROOF_HEARD := &"ch4_roof_radio_heard"
const HOME_SEEN := &"ch4_pawnshop_homecoming_seen"
const HOMECOMING := &"ch4_t_homecoming"

var _skip_final_scene := false


func _ready() -> void:
	_skip_final_scene = OS.get_cmdline_user_args().has("--skip-return")
	super._ready()


func _write() -> void:
	if not await _resume_to(ARCHIVE_OFFICE):
		return
	_check(StoryItems.holds(LEDGER_COPY) and not GameState.has_flag(HOME_SEEN),
			"the office save has the ledger and has not completed the return")
	var before := StoryItems.snapshot()
	if not await _portal(&"office_roof", level_pattern % "factory_roof"):
		return
	await _talk(&"ch4_roof_lantern")
	_check(GameState.has_flag(ROOF_HEARD), "the roof transmission completes on the ordinary route")
	var route: Array = [
		[&"roof_safety", "factory_safety"],
		[&"safety_relay", "factory_relay"],
		[&"relay_loading", "factory_loading"],
		[&"loading_approach", "factory_approach"],
		[&"approach_lounge", "revival_lounge"],
		[&"lounge_reception", "ward_reception"],
		[&"reception_pawn", "pawnshop"],
	]
	for step: Array in route:
		if not await _portal(step[0], level_pattern % step[1]):
			return
	await _talk(OLD_K, ["later"])
	_check(not GameState.has_flag(HOME_SEEN), "deferring the decision leaves the scene available")
	if _skip_final_scene:
		await _skip_after_confirming()
	else:
		await _talk(OLD_K, ["sit"])
	_check(_played.has(String(HOMECOMING)), "the ledger return started at the authorized shop actor")
	_check(GameState.has_flag(HOME_SEEN), "this visit records its durable homecoming")
	_check(StoryItems.snapshot() == before and StoryItems.holds(LEDGER_COPY),
			"the borrowed tape, optional branches and ledger stay separate")
	var slot := (_main.get("_run_store") as RunSaveStore).read()
	_check(slot.get("level") == PAWNSHOP and slot.get("story", {}).get("flags", {}).get(String(HOME_SEEN)) == true,
			"the office ledger remains part of a saved pawnshop run")
	await _talk(OLD_K)
	_check(_played.count(String(HOMECOMING)) == 1, "a revisited old K does not restart the sequence")


func _continue() -> void:
	if not await _resume_to(PAWNSHOP):
		return
	_check(GameState.has_flag(HOME_SEEN) and StoryItems.holds(LEDGER_COPY),
			"cold restore keeps the chapter result and the ledger")
	_check(not GameState.has_flag(&"ch4_lamp_mic_requested"),
			"an optional microphone request is unnecessary for the closing scene")
	await _talk(OLD_K)
	_check(_played.has("ch4_t_homecoming_reminder") and not _played.has(String(HOMECOMING)),
			"the reminder replaces the one-time presentation")


func _skip_after_confirming() -> void:
	var old_k := _object(OLD_K)
	_check(old_k != null and old_k.is_present(), "old K is present at his authored counter")
	if old_k == null:
		return
	_level.player.global_position = old_k.global_position + Vector2(-22, 0)
	await _settle(12)
	var done := [false]
	var talk := func() -> void:
		await old_k._talk()
		done[0] = true
	talk.call()
	await _drive(["sit"], func() -> bool: return done[0] or Story._current_cinematic == HOMECOMING)
	_check(Story._current_cinematic == HOMECOMING, "skip is issued only after confirmation started the return")
	Story.skip_cinematic()
	await _drive([], func() -> bool: return done[0])
	_check(done[0], "skip returns to an interactive shop")
