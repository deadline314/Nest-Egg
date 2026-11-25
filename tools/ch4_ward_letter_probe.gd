extends "res://tools/ch4_ward_probe.gd"
## Real Main, ward interactions, and two processes sharing only the isolated slot.
## Run with --mode=write|continue --save-dir=<absolute directory> --out=<absolute directory>.

const WITNESS_NOTE := &"ch4_linden_witness_note"
const WITNESSES_NOTED := &"ch4_linden_witnesses_noted"
const SCARF := &"ch4_ward_scarf"
const LETTER := &"ch4_t_read_linden_letter"
const NOTE_SCENE := &"ch4_t_note_linden_witnesses"
const OFFICE_ACCESS := &"ch4_office_access"


func _write() -> void:
	await super._write()
	if _level == null or _level.data.resource_path != WARD:
		_check(false, "the chapter route reaches the ward")
		return
	var credits := Progression.credits
	var items_before := StoryItems.snapshot()
	var flags_before := GameState.world_flags.duplicate(true)
	await _talk(SCARF)
	_check(_played.has("ch4_b_ward_scarf"), "the scarf has its own investigation")
	_check(StoryItems.snapshot() == items_before and GameState.world_flags == flags_before,
		"inspecting the scarf identifies the bed without publishing a result")
	await _talk(&"ch4_cabinet", ["leave"])
	await _talk(&"ch4_cabinet", ["ask_letter", "leave"])
	_check(not _played.has(String(LETTER)), "declining after asking leaves the letter unread")
	await _talk(&"ch4_cabinet", ["ask_letter", "read_aloud", "leave"])
	_check(_played.has(String(LETTER)) and not StoryItems.holds(WITNESS_NOTE),
		"listening to the authorized names leaves the notebook unchanged")
	_check(GameState.world_flags == flags_before and StoryItems.snapshot() == items_before,
		"all leave options preserve visit progress and earlier papers")

	Story.scene_started.connect(_cancel_note_once)
	var cabinet := _object(&"ch4_cabinet")
	if not is_instance_valid(cabinet):
		_check(false, "the supported cabinet is present for the abort check")
		return
	var cancelled := [false]
	var talk := func() -> void:
		await cabinet._talk()
		cancelled[0] = true
	talk.call()
	await _drive(["ask_letter", "read_aloud", "note"], func() -> bool: return cancelled[0])
	if Story.scene_started.is_connected(_cancel_note_once):
		Story.scene_started.disconnect(_cancel_note_once)
	_check(not GameState.has_flag(WITNESSES_NOTED) and not StoryItems.holds(WITNESS_NOTE),
		"aborting the writing scene publishes neither the flag nor a partial document")

	_shots["ch4_t_ask_linden_letter:choice"] = "ST-34-ward-letter"
	await _talk(&"ch4_cabinet", ["ask_letter", "read_aloud", "note"])
	_check(StoryItems.holds(WITNESS_NOTE) and GameState.has_flag(WITNESSES_NOTED),
		"finishing with Linden’s permission records exactly the note and its flag")
	var held := StoryItems.snapshot()
	_check(StoryItems.holds(SLIP) and (held.get("owned", []) as Array).count(WITNESS_NOTE) == 1,
		"the public slip remains and the optional note exists once")
	_check(Progression.credits == credits and GameState.has_flag(OFFICE_ACCESS) == flags_before.get(String(OFFICE_ACCESS), false)
		and _level.data.chapter == &"ch4_hollow", "the optional visit neither pays credits nor advances the factory or chapter")
	var note := StoryItems.find(WITNESS_NOTE)
	_check(note != null and not note.is_collectible() and note.source_actor == &"ch4_cabinet",
		"the note is cabinet-owned and excluded from collectible totals")
	var store := _main.get("_run_store") as RunSaveStore
	var saved := store.read()
	_check((saved.get("story", {}) as Dictionary).get("flags", {}).get(String(WITNESSES_NOTED)) == true,
		"the note completion is durable before quitting")


func _continue() -> void:
	await super._continue()
	if _level == null:
		return
	_check(GameState.has_flag(WITNESSES_NOTED) and StoryItems.holds(WITNESS_NOTE) and StoryItems.holds(SLIP),
		"the cold process restores the note, flag and original public slip")
	var prior_count := _played.count(String(NOTE_SCENE))
	var items_before := StoryItems.snapshot()
	await _talk(&"ch4_cabinet", ["ask_letter", "read_aloud", "leave"])
	_check(_played.has(String(LETTER)), "the cold process still allows an authorized reread")
	_check(StoryItems.snapshot() == items_before and _played.count(String(NOTE_SCENE)) == prior_count,
		"rereading after a saved copy adds no duplicate")


func _cancel_note_once(id: StringName, _mode_name: StringName) -> void:
	if id != NOTE_SCENE:
		return
	Story.scene_started.disconnect(_cancel_note_once)
	Story.skip_cinematic.call_deferred()


func _capture(name: String) -> void:
	if name == "ST-34-ward-letter":
		super._capture(name)
