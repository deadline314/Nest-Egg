extends "res://tools/ch4_atropos_probe.gd"
## Continues an arena save, visits the ledger and takes a copy.
## --mode=continue --save-dir=<absolute path>; NESTEGG_LEDGER_READBACK=1 for cold readback.


const LEDGER := &"ch4_original_ledger_copy"
const LEDGER_HOST := &"ch4_original_ledger"
const READ_LEDGER := &"ch4_original_ledger_read"
const SAVED_LEDGER := &"ch4_original_ledger_saved"


func _continue() -> void:
	if OS.get_environment("NESTEGG_LEDGER_READBACK") == "1":
		var record := await _route_main.continue_game()
		_level = _route_main.level()
		_check(_level != null and record.get("level") == OFFICE, "cold reader resumes at the ledger desk")
		_check(GameState.has_flag(READ_LEDGER) and GameState.has_flag(SAVED_LEDGER) and StoryItems.holds(LEDGER),
				"cold reader sees the same source-owned ledger")
		_check_body()
		if is_instance_valid(_level) and DisplayServer.get_name() != "headless":
			await _capture_ledger()
		return
	await super._continue()
	if _failures > 0 or not is_instance_valid(_level):
		return
	if _level.data.resource_path != OFFICE and not await _portal(&"arena_office", OFFICE):
		return
	_check(StoryItems.holds(SLIP), "the real ward collection slip remains available for comparison")
	_check(await _talk(LEDGER_HOST, ["leave"]), "the first prompt can be closed")
	_check(not GameState.has_flag(READ_LEDGER) and not StoryItems.holds(LEDGER),
			"leaving the first prompt commits no result")
	_check(await _talk(LEDGER_HOST, ["compare"]), "the author-owned comparison plays")
	_check(GameState.has_flag(READ_LEDGER) and not StoryItems.holds(LEDGER),
			"reading records only the inspection")
	_check(await _talk(LEDGER_HOST, ["leave"]), "the copy choice can be cancelled")
	_check(not GameState.has_flag(SAVED_LEDGER) and not StoryItems.holds(LEDGER),
			"leaving the copy choice never gives an item")
	_check(await _talk(LEDGER_HOST, ["save"]), "the ledger source accepts the requested copy")
	_check(GameState.has_flag(SAVED_LEDGER) and StoryItems.holds(LEDGER) and StoryItems.holds(SLIP),
			"the item, its completion and the original ward slip are all available")
	_check(await _talk(LEDGER_HOST), "the conversation can be revisited")
	_check_body()
	var store := _main.get("_run_store") as RunSaveStore
	var flags: Dictionary = (store.read().get("story", {}) as Dictionary).get("flags", {})
	_check(flags.get(String(READ_LEDGER), false) and flags.get(String(SAVED_LEDGER), false),
			"reading and taking the copy are present in the primary save")
	if DisplayServer.get_name() != "headless":
		await _capture_ledger()


func _check_body() -> void:
	var copy := load("res://data/story_items/ch4_original_ledger_copy.tres") as StoryItemData
	var body := copy.body_text() if copy != null else ""
	_check("91%" in body and (" %d " % GameState.deaths) in body and "{run_restorations}" not in body,
			"the shared reader shows the live count and the recorded 91 percent")



func _capture_ledger() -> void:
	var document := StoryItems.find(LEDGER)
	if document == null:
		_check(false, "the registered ledger is available to draw")
		return
	var camera := Camera2D.new()
	camera.position = Vector2(345, 251)
	camera.zoom = Vector2(1.53, 1.53)
	_level.add_child(camera)
	camera.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture := preload("res://tools/viewport_capture.gd")
	_check(capture.image(get_viewport()).save_jpg(_out_dir.path_join("ledger-office.jpg"), 0.90) == OK,
			"captured the authored ledger desk at game scale")

	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var page := Control.new()
	layer.add_child(page)
	page.position = Vector2(48, 36)
	page.size = Vector2(544, 270)
	var reader := preload("res://ui/inventory/document_reader.gd").new()
	page.add_child(reader)
	reader.show_document(document.title_text(), document.body_text(), document.color)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(capture.image(get_viewport()).save_jpg(_out_dir.path_join("ledger-open.jpg"), 0.90) == OK,
			"captured the shared document reader with the live count")
	layer.queue_free()
