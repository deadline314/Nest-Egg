class_name QuestMapSuite
extends TestSuite
## 資料接點與導覽實測；樣本任務不代表第一章主流程已驗收。

const FIXTURE := "res://tests/fixtures/navigation/catalog.json"
const PAWN := "res://data/levels/ch1_pawnshop.tres"
const ROOF := "res://data/levels/ch1_rooftop.tres"


func run() -> void:
	var catalog := fixture_catalog()
	_test_catalog(catalog)
	_test_required_route_steps()
	var maps := QuestMapIndex.new()
	maps.load_chapter(&"ch1_kasa")
	_test_real_maps(maps)
	_test_state(catalog, maps)
	await _test_ui(catalog, maps)
	await _test_runtime()
	_test_display_defaults()
	await _test_story_language()


func _visible_quest_text(root: Node) -> PackedStringArray:
	var result := PackedStringArray()
	if root is Label or root is Button:
		result.append(root.text)
	for child in root.get_children():
		result.append_array(_visible_quest_text(child))
	return result


## Real source, row/detail factories and live HUD: language never rewrites quest facts.
func _test_story_language() -> void:
	var previous_language := Story.language
	var level := await start_level(load(PAWN) as LevelData)
	var old_flags := GameState.world_flags.duplicate(true)
	GameState.set_flag(&"ch3_clinic_access", true, false)
	var guidance: QuestGuidance = level.hud.quest_guidance
	guidance.level.data = guidance.level.data.duplicate()
	guidance.level.data.chapter = &"ch3_clearwater"
	guidance.state.pin("sq7_ahan_tape", guidance.catalog)
	var catalog := guidance.catalog
	var raw_before := JSON.stringify(catalog.quests)
	var flags_before := JSON.stringify(GameState.world_flags)
	var quest := catalog.find("sq7_ahan_tape")
	var maps := QuestMapIndex.for_chapter(&"ch3_clearwater")
	var blocked: Dictionary = {}
	for candidate in catalog.quests:
		if candidate.has("blocked_reason") and candidate.has("suggestion") and QuestCatalog.status(candidate, GameState.world_flags) == "blocked":
			blocked = candidate
			break
	check(not blocked.is_empty(), "real catalog supplies a blocked quest with translated guidance")
	for language in ["en", "ja", "zh"]:
		check(Story.set_language(language), "quest language %s is supported" % language)
		var screen := QuestMapScreen.new()
		screen.catalog = catalog
		screen.maps = maps
		screen.state = guidance.state
		screen.chapter = "ch3_clearwater"
		screen.player_path = "res://data/levels/ch3_clinic.tres"
		runner.get_tree().root.add_child(screen)
		screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		screen.size = Vector2(640,360)
		await frames(3)
		screen._select("sq7_ahan_tape")
		for button: Button in screen._list.find_children("*", "Button", true, false):
			for child in button.get_children():
				if child is Label and child.text == "追蹤中":
					check(button.get_global_rect().encloses(child.get_global_rect()), "the full pinned badge fits the %s quest row" % language)
					check(is_equal_approx(child.get_global_rect().end.y, button.get_global_rect().end.y - 2) and child.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM, "the %s pinned badge uses the caption line below the title" % language)
		var texts := _visible_quest_text(screen)
		for field in ["title", "background", "reward"]:
			var expected := str(quest[field] if language == "zh" else quest[field + "_" + language])
			check(texts.has(expected), "quest %s uses real %s source in detail view" % [field, language])
		var expected_title := str(quest["title"] if language == "zh" else quest["title_" + language])
		var row := screen._quest_row(quest)
		check(row.text.contains(expected_title) and row.tooltip_text.contains(expected_title), "quest list and tooltip use %s title" % language)
		row.free()
		var step: Dictionary = quest["steps"][0]
		var expected_step := str(step["title"] if language == "zh" else step["title_" + language])
		check(texts.has("▶ " + expected_step), "current and checklist steps use %s text" % language)
		guidance._refresh_target()
		check(guidance._label.text == "◎ " + expected_step, "live objective HUD uses %s text from the same quest" % language)
		check(guidance._row.tooltip_text.begins_with(expected_step), "the full %s objective remains available when the HUD line is ellipsized" % language)
		if not blocked.is_empty():
			screen._select(str(blocked["id"]))
			var blocked_text := _visible_quest_text(screen)
			for field in ["blocked_reason", "suggestion"]:
				var expected := str(blocked[field] if language == "zh" else blocked[field + "_" + language])
				check(blocked_text.has(expected), "blocked quest %s uses %s text" % [field, language])
		screen._select("sq7_ahan_tape")
		for button: Button in screen._list.find_children("*", "Button", true, false):
			if button.get_meta(&"quest_id", "") == "sq7_ahan_tape":
				button.grab_focus()
		var focus_key := screen._focus_text()
		var history_size := screen._history.size()
		var next_language := "ja" if language == "en" else "en"
		Story.set_language(next_language)
		var refresh_deadline := Time.get_ticks_msec() + 1000
		while Time.get_ticks_msec() < refresh_deadline:
			if _visible_quest_text(screen).has(str(quest["title_" + next_language])) and screen._focus_text() == focus_key:
				break
			await runner.get_tree().process_frame
		check(_visible_quest_text(screen).has(str(quest["title_" + next_language])), "an already open journal refreshes from %s to %s" % [language, next_language])
		check(screen._selected == "sq7_ahan_tape" and screen._focus_text() == focus_key and screen._history.size() == history_size and guidance.state.pinned_id == "sq7_ahan_tape",
				"live language refresh preserves selection, stable focus, history and pin")
		await runner.get_tree().create_timer(0.22).timeout
		check(guidance._label.text == "◎ " + str(step["title_" + next_language]), "normal HUD polling follows a live language switch")
		check(JSON.stringify(catalog.quests) == raw_before and JSON.stringify(GameState.world_flags) == flags_before,
				"language %s preserves all original quest fields and progress bytes" % language)
		var outside := Button.new()
		outside.text = "external modal focus fixture"
		runner.add_child(outside)
		outside.grab_focus()
		Story.set_language(language)
		refresh_deadline = Time.get_ticks_msec() + 1000
		while Time.get_ticks_msec() < refresh_deadline:
			if _visible_quest_text(screen).has(expected_title):
				break
			await runner.get_tree().process_frame
		await runner.get_tree().process_frame
		await runner.get_tree().process_frame
		check(_visible_quest_text(screen).has(expected_title), "journal refreshes %s content behind another focused control" % language)
		check(outside.has_focus(), "language refresh cannot steal %s focus from another screen" % language)
		outside.queue_free()
		screen.queue_free()
		await frames(2)
	# Existing UI factories exercise missing-field fallback without calling a new API.
	Story.set_language("ja")
	var missing := quest.duplicate(true)
	missing.erase("title_ja")
	var preview := QuestMapScreen.new()
	preview.state = QuestMapState.new()
	var row := preview._quest_row(missing)
	check(row.text.contains(quest["title_en"]), "missing Japanese title falls back to existing English")
	row.free()
	missing.erase("title_en")
	row = preview._quest_row(missing)
	check(row.text.contains(quest["title"]), "missing Japanese and English title retain Chinese")
	row.free()
	missing["title_ja"] = []
	missing["title_en"] = quest["title_en"]
	row = preview._quest_row(missing)
	check(row.text.contains(quest["title_en"]), "a malformed Japanese translation uses valid English")
	row.free()
	missing["title_en"] = {}
	row = preview._quest_row(missing)
	check(row.text.contains(quest["title"]), "malformed translated fields cannot leak array or dictionary text into the title")
	row.free()
	preview.free()
	Story.set_language(previous_language)
	GameState.world_flags = old_flags
	await end_level(level)


static func fixture_catalog() -> QuestCatalog:
	var result := QuestCatalog.new()
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(FIXTURE))
	result.read_source(json.data, FIXTURE)
	return result


func _test_catalog(catalog: QuestCatalog) -> void:
	check(catalog.quests.size() == 3 and catalog.issues.is_empty(), "navigation fixture has three valid tasks %s" % catalog.issues)
	check(catalog.list_for("ch1_kasa", "main", false, {}).size() == 2, "main active tab shows main tasks")
	check(catalog.list_for("ch1_kasa", "side", false, {}).size() == 1, "side tab shows side task")
	check(QuestCatalog.status(catalog.find("nav_test_side"), {}) == "blocked", "missing prerequisite blocks task")
	check(QuestCatalog.status(catalog.find("nav_test_side"), {"nav_test_ready": true}) == "active", "prerequisite activates task")
	check(catalog.list_for("ch1_kasa", "all", true, {"nav_test_done": true}).size() == 1, "completed tab uses canonical completion flag")
	check(catalog.list_for("other_chapter", "all", false, {}).is_empty(), "chapter does not leak another chapter tasks")
	for entry in [[0, false], [1, true], ["", false], ["done", true]]:
		check(QuestCatalog.all_flags(["nav_test_ready"], {"nav_test_ready": entry[0]}) == entry[1], "prerequisite uses story scalar truth: %s" % str(entry[0]))
		check((QuestCatalog.status(catalog.find("nav_test_completed"), {"nav_test_done": entry[0]}) == "completed") == entry[1], "completion uses story scalar truth: %s" % str(entry[0]))
	var flags: Array = ["nav_test_finished", "nav_test_ready", "nav_test_side_finished", "nav_test_done"]
	check(catalog.validate_flags(flags, flags).is_empty(), "fixture producer contract validates")
	check(not catalog.validate_flags([], []).is_empty(), "unknown completion flags are reported")
	for value: Variant in [null, [], {}, {"level": PAWN, "cell": [-1, 19]}, {"level": PAWN, "cell": [9999, 19]}, {"level": PAWN, "cell": [3.5, 19]}, {"level": PAWN, "cell": [10, 20]}, {"level": "missing", "cell": [1, 1]}]:
		check(not QuestCatalog.valid_location(value), "bad task location rejected: %s" % str(value))
	for bad: Variant in [false, "bad", null, [], {"id": "bad"}]:
		var broken := QuestCatalog.new()
		broken.read_source({"quests": [bad]}, "fixture")
		check(broken.quests.is_empty() and not broken.issues.is_empty(), "bad quest metadata fails safely %s" % str(bad))
	var source := QuestCatalog.new()
	source.load_story_sources()
	check(source.issues.is_empty(), "current story files remain readable")
	# 這是觀察缺口，不是「任務主流程通過」；穩定資料合入後更新此測試。
	print("[QuestMap] Current story quest count: %d; chapter walkthrough requires Session 3 sources." % source.quests.size())


func _test_real_maps(maps: QuestMapIndex) -> void:
	check(maps.areas.size() == 11, "eleven real chapter areas indexed (with the prologue and the handoff cabinet)")
	check(maps.parse_count == 11, "each area parses once")
	var count := maps.parse_count
	for path: String in maps.areas:
		var area: Dictionary = maps.areas[path]
		maps.add_area(area["data"])
		for marker: Dictionary in area["markers"]:
			var cell: Vector2i = marker["cell"]
			check(cell.x >= 0 and cell.x < area["layout"].width and cell.y >= 0 and cell.y < area["layout"].height, "real marker is inside map: %s %s" % [path, cell])
		for edge in maps.edges(path):
			check(maps.areas.has(edge["resource"].target_level), "world edge points to real area")
	check(maps.parse_count == count, "cached index is not rebuilt when reused")
	var exit := maps.next_exit(PAWN, ROOF, {})
	check(not exit.is_empty() and exit["resource"].target_level == ROOF, "cross-area route points to actual stairs")
	check(maps.marker_text(exit, {}) == exit["resource"].locked_text, "map lock explanation matches game portal source")
	check(maps.marker_text(exit, {String(exit["resource"].requires_flag): true}).contains("屋頂"), "unlocked stairs show destination")
	var street := "res://data/levels/ch1_street.tres"
	var wall: Dictionary = {}
	for marker: Dictionary in maps.areas[street]["markers"]:
		if marker["kind"] == "secret_wall":
			wall = marker
	check(not wall.is_empty(), "real street contains a secret wall")
	if not wall.is_empty():
		var cell: Vector2i = wall["cell"]
		var position: Vector2 = Vector2(cell + Vector2i(-3, 0)) * 16 + Vector2(8, 8)
		var before := maps.visible_cells(street, position, {})
		var after := maps.visible_cells(street, position, {"breakable@%d,%d" % [cell.x, cell.y]: true})
		check(not before.has(cell + Vector2i(1, 0)), "unbroken secret wall hides cells behind it")
		check(after.has(cell + Vector2i(1, 0)), "broken secret wall reveals cells behind it")


func _test_state(catalog: QuestCatalog, maps: QuestMapIndex) -> void:
	var state := QuestMapState.new()
	check(state.target(catalog, "ch1_kasa", {})["id"] == "nav_test_main", "unpinned tracker follows main task")
	state.pin("nav_test_side", catalog)
	check(state.target(catalog, "ch1_kasa", {})["id"] == "nav_test_side", "pinned blocker still displays its reason")
	check(state.target(catalog, "ch1_kasa", {"nav_test_side_finished": true})["id"] == "nav_test_main", "completed pin falls back to main")
	check(state.target(catalog, "other", {}).is_empty(), "chapter change does not track old pin")
	state.reveal(PAWN, [Vector2i(50, 19), Vector2i(51, 19)])
	var revision := state.revision
	state.reveal(PAWN, [Vector2i(50, 19)])
	check(state.revision == revision, "same exploration cell does not invalidate map")
	var data: Dictionary = state.snapshot()
	var restored := QuestMapState.new()
	restored.restore(data, catalog, maps)
	check(restored.pinned_id == state.pinned_id and restored.knows(PAWN, Vector2i(50, 19)), "snapshot roundtrip retains pin and explored cells")
	data["explored"][PAWN].clear()
	check(state.knows(PAWN, Vector2i(50, 19)), "snapshot does not alias runtime state")
	for corrupt: Variant in [null, [], {"version": 2}, {"version": 1, "pinned_id": [], "explored": [], "activated": []}, {"version": 1, "pinned_id": "unknown", "explored": {PAWN: {"bad": true, "9999,1": true}}, "activated": {"fake": true}}]:
		restored.restore(corrupt, catalog, maps)
		check(not restored.issues.is_empty() and restored.pinned_id.is_empty() and restored.explored.is_empty(), "corrupt navigation safely defaults and identifies fields")


func _test_ui(catalog: QuestCatalog, maps: QuestMapIndex) -> void:
	var old_flags := GameState.world_flags.duplicate(true)
	GameState.world_flags = {"nav_test_done": true}
	var screen := QuestMapScreen.new()
	screen.catalog = catalog
	screen.maps = maps
	screen.state = QuestMapState.new()
	screen.state.reveal(PAWN, [Vector2i(50, 19)])
	screen.chapter = "ch1_kasa"
	screen.player_path = PAWN
	screen.player_position = Vector2(800, 320)
	runner.get_tree().root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(640, 360)
	await frames(3)
	check(screen._page == "quests" and screen._selected == "nav_test_main", "journal opens active main details")
	await _key(KEY_DOWN)
	await frames(2)
	check(screen.get_viewport().gui_get_focus_owner() != null, "keyboard navigation retains focus")
	screen._filter("side")
	await frames(2)
	check(screen._selected == "nav_test_side", "side filter shows blocker details")
	screen._pin("nav_test_side")
	check(screen.state.pinned_id == "nav_test_side", "journal pin action updates tracker")
	screen._jump_to_map(PAWN)
	await frames(3)
	check(screen._page == "region" and screen._canvas != null, "selected task jumps to real map")
	for marker in screen._canvas._markers:
		check(marker.size.x <= 20 and marker.size.y <= 20, "region marker does not retain wide button bounds: %s" % marker.text)
	var builds := screen._canvas.builds
	screen._canvas.refresh()
	screen._canvas.refresh()
	check(screen._canvas.builds == builds, "map redraw uses cached terrain texture")
	await _key(KEY_ESCAPE)
	await frames(2)
	check(screen._page == "quests" and screen._selected == "nav_test_side", "keyboard return goes back to selected task")
	screen.show_page("world")
	await frames(3)
	check(screen._canvas._markers.size() == maps.areas.size(), "world shows every real area")
	await frames(2)
	var overlap := false
	var clipped := false
	var nodes := screen._canvas._markers
	for i in nodes.size():
		var font := nodes[i].get_theme_font(&"font")
		var font_size := nodes[i].get_theme_font_size(&"font_size")
		if nodes[i].autowrap_mode == TextServer.AUTOWRAP_OFF:
			clipped = clipped or font.get_string_size(nodes[i].text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > nodes[i].size.x
		else:
			# 折成兩行的名稱：行數疊起來的高度不能超過按鈕。
			clipped = clipped or font.get_multiline_string_size(nodes[i].text, HORIZONTAL_ALIGNMENT_CENTER, nodes[i].size.x - 4, font_size, -1, TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_MANDATORY).y > nodes[i].size.y
		for j in range(i + 1, nodes.size()):
			if nodes[i].get_global_rect().grow(-1).intersects(nodes[j].get_global_rect()):
				overlap = true
	check(not overlap and not clipped, "world map nodes neither overlap nor cut area names")
	check(_world_lines_cross_nodes(screen._canvas) == 0, "world map connections never run through another area's box")
	await _joy(JOY_BUTTON_B)
	await frames(2)
	check(screen._page == "quests", "controller return goes back one level")
	var nav_buttons := screen.find_children("*", "Button", true, false)
	var world_button: Button
	for button: Button in nav_buttons:
		if button.text == "世界地圖":
			world_button = button
	world_button.grab_focus()
	await _joy(JOY_BUTTON_A)
	await frames(3)
	check(screen._page == "world", "controller confirm opens focused page")
	for page in ["quests", "region", "world"]:
		screen.show_page(page, false)
		await frames(3)
		check(screen._body.get_global_rect().end.y <= 348, "navigation content fits 640x360 design: %s" % page)
		for button: Button in screen.find_children("*", "Button", true, false):
			check(not button.tooltip_text.is_empty(), "navigation button has readable tooltip: %s" % button.text)
	await _test_journal_input(screen, false)
	await _test_journal_input(screen, true)
	await _test_completed_pin_label(screen)
	screen.queue_free()
	await frames(2)
	await _test_long_details(maps)
	GameState.world_flags = old_flags


func _test_completed_pin_label(screen: QuestMapScreen) -> void:
	screen.state.pin("nav_test_side", screen.catalog)
	GameState.world_flags["nav_test_side_finished"] = true
	screen._filter("completed")
	screen._select("nav_test_side")
	await frames(3)
	check(not "追蹤中" in " ".join(_visible_quest_text(screen._detail_head)), "completed detail does not claim an old pin is still tracked")
	for row: Button in screen._list.find_children("*", "Button", true, false):
		if row.get_meta(&"quest_id", "") == "nav_test_side":
			check(not "追蹤中" in " ".join(_visible_quest_text(row)), "completed row does not retain a misleading tracking badge")
	check(screen.state.pinned_id == "nav_test_side" and screen.state.target(screen.catalog, "ch1_kasa", GameState.world_flags).get("id") == "nav_test_main", "removing completed tracking labels preserves saved pin and actual main fallback")


## 背景很長時：獎勵固定在操作上方、捲動區有「下方還有內容」提示，右搖桿捲動內文且焦點不動。
func _test_long_details(maps: QuestMapIndex) -> void:
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(FIXTURE))
	var source: Dictionary = json.data
	var main: Dictionary = source["quests"][0]
	main["background"] = "這段背景故意寫得很長，用來確認細節區塊會捲動。".repeat(12)
	var catalog := QuestCatalog.new()
	catalog.read_source(source, FIXTURE)
	var screen := QuestMapScreen.new()
	screen.catalog = catalog
	screen.maps = maps
	screen.state = QuestMapState.new()
	screen.chapter = "ch1_kasa"
	screen.player_path = PAWN
	runner.get_tree().root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(640, 360)
	await frames(4)
	check(screen._selected == str(main["id"]), "long-detail screen selects the long task")
	check(screen._reward != null and screen._details.is_ancestor_of(screen._reward), "reward follows the objectives inside the details")
	check(screen._actions.get_global_rect().end.y <= 348, "fixed actions fit inside the 640x360 design")
	await _check_filter_groups(screen)
	var cue := ScrollCue.of(screen._detail_scroll)
	var cue_ok := cue != null and cue.more_below
	check(cue_ok, "long details show a 'more below' cue")
	check(screen._scroll_note.is_visible_in_tree(), "long details explain how to scroll beside the actions")
	screen._focus_details()
	await frames(2)
	var focus_before := screen.get_viewport().gui_get_focus_owner()
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_RIGHT_Y
	motion.axis_value = 1.0
	runner.get_viewport().push_input(motion)
	await frames(2)
	motion = motion.duplicate()
	motion.axis_value = 0.0
	runner.get_viewport().push_input(motion)
	await frames(2)
	check(screen._detail_scroll.scroll_vertical > 0, "right stick scrolls long details")
	check(screen.get_viewport().gui_get_focus_owner() == focus_before, "scrolling details keeps focus on the action")
	check(cue_ok and cue.more_above, "scrolled details show the 'more above' cue")
	var page := InputEventKey.new()
	page.keycode = KEY_PAGEUP
	page.physical_keycode = KEY_PAGEUP
	page.pressed = true
	runner.get_viewport().push_input(page)
	await frames(2)
	check(screen._detail_scroll.scroll_vertical == 0, "PageUp scrolls details back to the top")
	screen.queue_free()
	await frames(2)


## 文字放大時，篩選的兩組按鈕（狀態、種類）各自整組換行，不把最後一顆單獨擠到下一行。
func _check_filter_groups(screen: QuestMapScreen) -> void:
	var previous := Settings.get_ui_text_scale()
	Settings.set_ui_text_scale(1.2)
	screen._build()
	await frames(3)
	var rows: Dictionary = {}
	for button in screen._buttons:
		var key := str(button.get_meta(&"nav_key", ""))
		if key.begins_with("filter:"):
			rows[key] = button.get_global_rect().position.y
	var same_row: bool = rows.size() == 5 and rows["filter:active"] == rows["filter:completed"] and rows["filter:all"] == rows["filter:main"] and rows["filter:main"] == rows["filter:side"]
	check(same_row, "at 120%% text each filter group stays on one row (%s)" % rows)
	Settings.set_ui_text_scale(previous)
	screen._build()
	await frames(3)


func _test_runtime() -> void:
	var level := await start_level(load(PAWN) as LevelData)
	await _check_fixed_hud_reading_space(level)
	await _check_caption_avoids_actor(level)
	await _check_destination_reading_priority(level)
	await _check_reading_yield_timing(level)
	await _check_prompt_avoids_objective(level)
	var state := QuestMapState.for_run()
	state.reveal(PAWN, [Vector2i(50, 19)])
	GameState.register_death()
	check(is_same(state, QuestMapState.for_run()), "death preserves navigation state instance")
	GameState.enter_level()
	check(is_same(state, QuestMapState.for_run()), "chapter transition preserves exploration state")
	await end_level(level)
	GameState.start_new_run(GameState.difficulties[1])
	check(not is_same(state, QuestMapState.for_run()) and QuestMapState.for_run().explored.is_empty(), "new run clears previous exploration")


## 世界提示（訓練站、告示）壓到 HUD 目標列時，目標列淡出讓位、提示框留在原處；提示收起後目標列回來（序章實際畫面曾疊字）。
func _check_prompt_avoids_objective(level: Level) -> void:
	var guidance: QuestGuidance = level.hud.quest_guidance
	var row := Rect2()
	for i in 60:
		await frames(1)
		row = guidance.row_world_rect()
		if row.has_area():
			break
	check(row.has_area(), "the objective row is on screen in a new game")
	if not row.has_area():
		return
	var prompt := WorldPrompt.new()
	prompt.text = "{jump} 跳上搬貨台，工具就放在上面。"
	prompt.reach_check = func() -> bool: return true
	var holder := Node2D.new()
	level.add_child(holder)
	holder.add_child(prompt)
	await frames(2)
	# 提示框原本的位置正好壓在目標列中央。
	holder.global_position += row.get_center() - prompt.base_rect().get_center()
	var faded := false
	for i in 120:
		await frames(1)
		if prompt.is_showing() and guidance._row.modulate.a < 0.05:
			faded = true
			break
	var placed := Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size)
	check(faded and guidance.yielding, "a world prompt over the objective row makes the row fade out")
	check(guidance._row.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the faded objective row no longer catches the mouse tooltip")
	check(placed.intersects(row), "the prompt itself stays in place instead of being pushed off screen")
	holder.queue_free()
	var back := false
	for i in 120:
		await frames(1)
		if not guidance.yielding and guidance._row.modulate.a > 0.35:
			back = true
			break
	check(back, "the objective row comes back once the prompt is gone")


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	runner.get_viewport().push_input(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	runner.get_viewport().push_input(event)


func _joy(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	runner.get_viewport().push_input(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	runner.get_viewport().push_input(event)


func _test_display_defaults() -> void:
	var old_objective: Variant = Settings.get_value(Settings.DISPLAY_SECTION, "quest_objective", true)
	var old_arrows: Variant = Settings.get_value(Settings.DISPLAY_SECTION, "quest_arrows", true)
	Settings.set_value(Settings.DISPLAY_SECTION, "quest_objective", false)
	Settings.set_value(Settings.DISPLAY_SECTION, "quest_arrows", true)
	check(Settings.get_value(Settings.DISPLAY_SECTION, "quest_objective") == false and Settings.get_value(Settings.DISPLAY_SECTION, "quest_arrows") == true, "objective row and direction arrow can be disabled independently")
	Settings.reset_display()
	check(Settings.get_value(Settings.DISPLAY_SECTION, "quest_objective") == true and Settings.get_value(Settings.DISPLAY_SECTION, "quest_arrows") == true, "reset display restores both navigation switches")
	Settings.set_value(Settings.DISPLAY_SECTION, "quest_objective", old_objective)
	Settings.set_value(Settings.DISPLAY_SECTION, "quest_arrows", old_arrows)


func _test_journal_input(screen: QuestMapScreen, controller: bool) -> void:
	screen._history.clear()
	screen.state.pinned_id = ""
	screen._completed = false
	screen._kind = "all"
	screen._page = "quests"
	screen._build()
	await frames(3)
	var method := "controller" if controller else "keyboard"
	screen._buttons[4].grab_focus()
	if controller:
		await _joy(JOY_BUTTON_A)
	else:
		await _key(KEY_ENTER)
	await frames(2)
	check(screen._kind == "side" and screen._selected == "nav_test_side", "%s opens side tab through focused button" % method)
	check(screen.get_viewport().gui_get_focus_owner().text == "支線", "%s keeps focus on the selected filter" % method)
	(screen._list.get_child(0) as Button).grab_focus()
	if controller:
		await _joy(JOY_BUTTON_A)
	else:
		await _key(KEY_ENTER)
	await frames(2)
	var focused := screen.get_viewport().gui_get_focus_owner() as Button
	check(focused != null and focused.text == "釘選這項任務", "%s opens details and focuses pin" % method)
	if controller:
		await _joy(JOY_BUTTON_A)
	else:
		await _key(KEY_ENTER)
	await frames(2)
	check(screen.state.pinned_id == "nav_test_side", "%s pins task through confirm input" % method)
	if controller:
		await _joy(JOY_BUTTON_DPAD_DOWN)
	else:
		await _key(KEY_DOWN)
	await frames(2)
	focused = screen.get_viewport().gui_get_focus_owner() as Button
	check(focused != null and focused.text.contains("的地圖"), "%s navigates to map action inside scrollable details" % method)
	if controller:
		await _joy(JOY_BUTTON_A)
	else:
		await _key(KEY_ENTER)
	await frames(3)
	check(screen._page == "region", "%s confirms jump to destination map" % method)
	if controller:
		await _joy(JOY_BUTTON_B)
	else:
		await _key(KEY_ESCAPE)
	await frames(3)
	focused = screen.get_viewport().gui_get_focus_owner() as Button
	check(screen._page == "quests" and focused != null and focused.text.contains("的地圖"), "%s returns one layer and restores action focus" % method)


## 世界地圖的每一段連線取樣，碰到的區域框只能是這條線的兩端。
static func _world_lines_cross_nodes(canvas: QuestMapCanvas) -> int:
	var crossings := 0
	for line: PackedVector2Array in canvas._lines:
		for marker: Control in canvas._markers:
			var rect := Rect2(marker.position, marker.size).grow(-2)
			if rect.has_point(line[0]) or rect.has_point(line[line.size() - 1]):
				continue
			var hit := false
			for i in line.size() - 1:
				for t in 21:
					if rect.has_point(line[i].lerp(line[i + 1], t / 20.0)):
						hit = true
			if hit:
				crossings += 1
	return crossings


func _test_required_route_steps() -> void:
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var quest := catalog.find("ch1_take_disk")
	check(quest.get("completion_requires_steps", false) == true, "formal disk quest explicitly requires its route steps")
	var route := ["ch1_street_route_open", "watchdog_defeated", "ch1_flood_gate_open"]
	for mask in 8:
		var flags := {"ch1_prologue_exit": true, "ch1_dinner_done": true, "ch1_heard_brief": true, "ledger_disk_obtained": true}
		for i in route.size():
			flags[route[i]] = bool(mask & (1 << i))
		var expected := "completed" if mask == 7 else "active"
		check(QuestCatalog.status(quest, flags) == expected, "disk possession cannot hide unfinished route mask=%d" % mask)
		var restored: Dictionary = JSON.parse_string(JSON.stringify(flags))
		check(QuestCatalog.status(quest, restored) == expected, "serialized flags retain exact route status mask=%d" % mask)
		if mask != 7:
			var step := QuestCatalog.current_step(quest, flags)
			check(not step.is_empty() and not QuestCatalog.flag_set(flags, step.get("complete_flag", "")), "current step remains an actual unfinished route objective mask=%d" % mask)
			check(QuestMapState.new().target(catalog, "ch1_kasa", flags).get("id") == "ch1_take_disk", "default tracking retains the unfinished route before handoff mask=%d" % mask)
	var prologue := catalog.find("ch1_prologue")
	check(not prologue.is_empty() and QuestCatalog.status(prologue, {"ch1_prologue_exit": true}) == "completed", "skipping the prologue still completes its quest without faking practice")
	var legacy := quest.duplicate(true)
	legacy.erase("completion_requires_steps")
	check(QuestCatalog.status(legacy, {"ledger_disk_obtained": true}) == "completed", "quests without the new opt-in retain their original terminal flag rule")
	var malformed := quest.duplicate(true)
	malformed["completion_requires_steps"] = "true"
	var invalid := QuestCatalog.new()
	invalid.read_source({"chapter": {"id": "ch1_kasa"}, "quests": [malformed]}, "test_optional_completion")
	check(invalid.quests.is_empty() and Array(invalid.issues).any(func(issue: String) -> bool: return issue.contains("completion_requires_steps")), "invalid completion policy reports its exact source field")


func _check_reading_yield_timing(level: Level) -> void:
	var guidance: QuestGuidance = level.hud.quest_guidance
	await frames(2)
	var row := guidance.row_world_rect()
	check(row.has_area(), "reading handoff fixture has a real objective row")
	if not row.has_area():
		return
	guidance.yielding = false
	guidance._row.modulate.a = 1.0
	guidance._pulse_row()
	var surface := Node.new()
	level.add_child(surface)
	PromptLayout.add_obstacle(surface, func() -> Rect2: return row, true)
	guidance._process(1.0 / 60.0)
	check(guidance.yielding and guidance._row.modulate.a == 0.0, "a newly overlapping reading surface takes the objective pixels immediately")
	check(guidance._row.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the first yielding frame also stops objective hover input")
	await frames(3)
	check(guidance._row.modulate.a == 0.0, "an already-running objective pulse never restores alpha through a reading surface")
	surface.queue_free()
	await frames(2)


func _check_destination_reading_priority(level: Level) -> void:
	var guidance: QuestGuidance = level.hud.quest_guidance
	var original := guidance._target
	var selected := false
	for quest: Dictionary in guidance.catalog.quests:
		var step := QuestCatalog.current_step(quest, GameState.world_flags)
		var location: Dictionary = step.get("location", {})
		var path := str(location.get("level", ""))
		if path.is_empty() or path == level.data.resource_path or guidance.maps.next_exit(level.data.resource_path, path, GameState.world_flags).is_empty():
			continue
		guidance._target = quest
		guidance._update_arrow()
		if guidance._arrow.visible:
			selected = true
			break
	check(selected, "a real other-area quest supplies the destination caption for handoff testing")
	if selected:
		var screen := guidance._arrow.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, guidance._arrow.size)
		var rect := guidance.get_viewport().get_canvas_transform().affine_inverse() * screen
		var surface := Node.new()
		level.add_child(surface)
		PromptLayout.add_obstacle(surface, func() -> Rect2: return rect, true)
		guidance._update_arrow()
		check(not guidance._arrow.visible, "the destination caption yields when its own pixels are needed for world reading")
		surface.free()
		guidance._update_arrow()
		check(guidance._arrow.visible, "the real destination caption returns after world reading releases its space")
	guidance._target = original
	guidance._update_arrow()


func _check_fixed_hud_reading_space(level: Level) -> void:
	var hud := level.hud
	var inverse := runner.get_viewport().get_canvas_transform().affine_inverse()
	var obstacles: Array[Rect2] = []
	PromptLayout.collect_obstacles_except(level._bubbles, obstacles)
	for control: Control in [hud._timer_label, hud.credits_tag]:
		var rect := (inverse * control.get_global_transform_with_canvas()) * Rect2(Vector2.ZERO, control.size.max(control.get_minimum_size()))
		check(obstacles.any(func(candidate: Rect2) -> bool: return candidate.encloses(rect)), "actual fixed HUD reserves its full visible reading rectangle: " + str(control.name))
	var feed := hud.pickup_feed
	for row in feed._rows:
		row.hide()
	feed.push("取得資料盤")
	PromptLayout.collect_obstacles_except(level._bubbles, obstacles)
	var occupied := (inverse * feed.get_global_transform_with_canvas()) * Rect2(Vector2.ZERO, feed.size.max(feed.get_minimum_size()))
	check(obstacles.any(func(candidate: Rect2) -> bool: return candidate.encloses(occupied)), "an actual acquired-feed row reserves its allotted space on the first fade-in frame")
	feed._process(PickupFeed.HOLD + PickupFeed.FADE)
	PromptLayout.collect_obstacles_except(level._bubbles, obstacles)
	check(not obstacles.any(func(candidate: Rect2) -> bool: return candidate.encloses(occupied)), "expired acquired-feed rows release their reading reservation")


func _check_caption_avoids_actor(level: Level) -> void:
	var guidance: QuestGuidance = level.hud.quest_guidance
	var original_target := guidance._target
	var original_player := level.player.global_position
	var selected := false
	for quest: Dictionary in guidance.catalog.quests:
		var step := QuestCatalog.current_step(quest, GameState.world_flags)
		var path := str((step.get("location", {}) as Dictionary).get("level", ""))
		if path.is_empty() or path == level.data.resource_path or guidance.maps.next_exit(level.data.resource_path, path, GameState.world_flags).is_empty():
			continue
		guidance._target = quest
		guidance._update_arrow()
		if guidance._arrow.visible:
			selected = true
			break
	check(selected, "the actual catalog provides a cross-area caption for actor clearance")
	if selected:
		var inverse := runner.get_viewport().get_canvas_transform().affine_inverse()
		var original_position := guidance._arrow.position
		var text := guidance._arrow.text
		var rect := (inverse * guidance._arrow.get_global_transform_with_canvas()) * Rect2(Vector2.ZERO, guidance._arrow.size.max(guidance._arrow.get_minimum_size()))
		var body := level.player.prompt_obstacle_rect()
		level.player.global_position += rect.get_center() - body.get_center()
		guidance._update_arrow()
		rect = (inverse * guidance._arrow.get_global_transform_with_canvas()) * Rect2(Vector2.ZERO, guidance._arrow.size.max(guidance._arrow.get_minimum_size()))
		check(guidance._arrow.visible and not rect.intersects(level.player.prompt_obstacle_rect()), "the real destination caption finds a visible position clear of the actual player")
		check(guidance._arrow.text == text, "clearance preserves the real destination wording and direction")
		level.player.global_position = original_player
		guidance._update_arrow()
		check(guidance._arrow.visible and guidance._arrow.position.is_equal_approx(original_position), "the caption returns to its original edge position after the player clears it")
	level.player.global_position = original_player
	guidance._target = original_target
	guidance._update_arrow()
