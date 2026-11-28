class_name PresentationSuite
extends TestSuite
## 章節與地點的呈現：進場不疊章節卡、地點標示（右下角、回訪短版、暫停凍結、減少動態）、
## 章末畫面拆章名與印、暫停與主選單的章節名與地名、標題字體涵蓋所有地名與章名、共用字體階層（NE-422）。

const PAWNSHOP := "res://data/levels/ch1_pawnshop.tres"
const STREET := "res://data/levels/ch1_street.tres"
const WAREHOUSE := "res://data/levels/ch1_warehouse.tres"
const TITLE_FONT := "res://art/fonts/NestEggTitleTC-Bold.ttf"
const TITLE_FONT_JA := "res://art/fonts/NestEggTitleJP-Bold.ttf"


func run() -> void:
	_test_names()
	_test_typography()
	_test_title_font_coverage()
	_test_contrast()
	await _test_marker()
	await _test_marker_still_and_suspended()
	await _test_end_card()
	await _test_covered_screens()
	await _test_end_card_handoff()
	_test_place_names_are_places()
	_test_text_traffic_order()
	_test_text_box_placement()
	_test_cutscene_text_boxes()
	await _test_text_traffic_scene()
	await _test_level_entry()
	await _test_world_text_screen_size()
	_test_world_text_fits()
	await _test_world_text_real_areas()
	await _test_pickup_yields_to_bubble()


func _test_names() -> void:
	check(LocationMarker.split_note("當舖（天亮）") == PackedStringArray(["當舖", "天亮"]), "括號註記拆成地名與小字")
	check(LocationMarker.split_note("港區街道") == PackedStringArray(["港區街道", ""]), "沒有註記時地名不變")
	var pawnshop := load(PAWNSHOP) as LevelData
	var zh := LocationMarker.for_level(pawnshop, "zh", false)
	check(zh != null and zh.place_name == "當舖" and zh.secondary == "PAWNSHOP", "中文的第二行是大寫英文地名")
	var en := LocationMarker.for_level(pawnshop, "en", true)
	check(en != null and en.place_name == "Pawnshop" and en.secondary == "當舖" and en.revisit, "英文的第二行是中文地名")
	var blank := pawnshop.duplicate() as LevelData
	blank.display_name = ""
	blank.localized_names = {}
	check(LocationMarker.for_level(blank, "zh", false) == null and LocationMarker.for_level(null, "zh", false) == null, "沒有地名就不顯示")
	zh.free()
	en.free()
	check(ChapterCard.split_end_title("第一章　傘", "第一章　傘　完") == PackedStringArray(["第一章", "傘", "完"]), "章末標題拆成序號、章名、印")
	check(ChapterCard.split_end_title("Chapter 1: Kasa", "Chapter 1: Kasa, Complete") == PackedStringArray(["CHAPTER 1", "Kasa", "完"]),
		"英文章名也拆成序號與章名，同樣蓋印")
	check(ChapterCard.split_end_title("Prologue", "Prologue Complete") == PackedStringArray(["", "Prologue Complete", "完"]),
		"拆不出來時整段當章名，仍然蓋印")
	var street := PlaceNames.level_data(STREET)
	check(PlaceNames.progress_line(street, "zh") == "第一章　傘・港區街道", "暫停畫面寫出章節與目前地點：%s" % PlaceNames.progress_line(street, "zh"))
	check(PlaceNames.progress_line(null, "zh", "第一章　傘") == "第一章　傘", "找不到區域時只寫章節")
	check(PlaceNames.resume_line(STREET, "zh") == "從「第一章　傘」的港區街道繼續。", "繼續遊戲的說明講出章節與地點：%s" % PlaceNames.resume_line(STREET, "zh"))
	check(PlaceNames.resume_line("", "zh") == PlaceNames.RESUME_FALLBACK["zh"] and PlaceNames.resume_line("res://missing.tres", "en") == PlaceNames.RESUME_FALLBACK["en"],
		"沒有或讀不到存檔區域時退回原本的說明")


## 標題字體只收錄用得到的字：每個地名與章名都要涵蓋（中文用繁中字型、日文用日文字型），
## 缺字時指出是哪一份資料的哪一段文字（重跑 tools/ui/build_title_font.py）。
func _test_title_font_coverage() -> void:
	var faces := {"zh": load(TITLE_FONT) as FontFile, "ja": load(TITLE_FONT_JA) as FontFile}
	check(faces["zh"] != null and faces["ja"] != null, "兩份標題字體都載入")
	if faces["zh"] == null or faces["ja"] == null:
		return
	var missing: Array[String] = []
	for path in DirAccess.get_files_at("res://data/levels"):
		if not path.ends_with(".tres"):
			continue
		var data := load("res://data/levels/" + path) as LevelData
		if data == null:
			continue
		if not _covered(faces["zh"], data.display_name):
			missing.append("%s：%s" % [path, data.display_name])
		var ja := str(data.localized_names.get("ja", ""))
		if not _covered(faces["ja"], ja):
			missing.append("%s（ja）：%s" % [path, ja])
	for path in DirAccess.get_files_at("res://data/story"):
		var chapter: Variant = (JSON.parse_string(FileAccess.get_file_as_string("res://data/story/" + path)) as Dictionary).get("chapter") if path.ends_with(".json") else null
		if not chapter is Dictionary:
			continue
		for key in ["title", "end_title", "title_ja", "end_title_ja"]:
			var text := str(chapter.get(key, ""))
			if not _covered(faces["ja" if key.ends_with("_ja") else "zh"], text):
				missing.append("%s.%s：%s" % [path, key, text])
	check(missing.is_empty(), "標題字體涵蓋所有地名與章名（缺：%s）" % ", ".join(missing))
	var previous := UiKit._font_language
	UiKit.set_font_language("ja")
	var japanese := ((UiKit.special_font(&"title") as FontVariation).base_font as FontVariation).base_font
	UiKit.set_font_language("zh")
	var chinese := ((UiKit.special_font(&"title") as FontVariation).base_font as FontVariation).base_font
	UiKit.set_font_language(previous)
	check(japanese.resource_path == TITLE_FONT_JA and chinese.resource_path == TITLE_FONT, "日文用日文標題字型、中文用繁中標題字型")


func _covered(font: FontFile, text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if code > 0x20 and not font.has_char(code):
			return false
	return true


## 共用字體階層：讀檔、錯誤時退回預設並指出欄位、角色套到控制項、像素字體的字級取整數倍。
func _test_typography() -> void:
	check(Typography.load_table() and Typography.issues.is_empty(), "字體階層設定檔沒有錯誤：%s" % [Typography.issues])
	for role: StringName in [&"hero", &"display", &"title", &"kicker", &"heading", &"body", &"caption", &"label", &"numeral"]:
		check(Typography.has_role(role), "字體階層有「%s」" % role)
	check(Typography.base_size(&"hero") > Typography.base_size(&"display") and Typography.base_size(&"display") > Typography.base_size(&"title")
		and Typography.base_size(&"title") > Typography.base_size(&"heading") and Typography.base_size(&"heading") > Typography.base_size(&"body")
		and Typography.base_size(&"body") > Typography.base_size(&"caption"), "字級由大到小：時刻大標、時刻標題、畫面標題、段落標題、內文、說明小字")
	var broken := Typography.parse("{oops", "res://test.json")
	check(not (broken["issues"] as PackedStringArray).is_empty() and str(broken["issues"][0]).contains("res://test.json")
		and (broken["roles"] as Dictionary)[&"title"]["size"] == Typography.DEFAULTS[&"title"]["size"], "設定檔損毀時指出檔案並全部用預設")
	var bad := Typography.parse('{"roles": {"title": {"face": "comic", "size": 999}, "body": "x"}}', "res://test.json")
	var bad_issues := ", ".join(bad["issues"])
	check(bad_issues.contains("roles.title.face") and bad_issues.contains("roles.title.size") and bad_issues.contains("roles.body")
		and (bad["roles"] as Dictionary)[&"title"]["face"] == &"title" and (bad["roles"] as Dictionary)[&"title"]["size"] == 22,
		"錯的欄位指出角色與欄位，該欄退回預設：%s" % bad_issues)
	var title := UiKit.styled("測試", &"title")
	check(title.get_theme_font(&"font") == UiKit.special_font(&"title") and title.get_theme_font_size(&"font_size") == UiKit.role_size(&"title"),
		"畫面標題角色套用標題字體與字級")
	var label := UiKit.styled("TAG", &"label")
	check((label.get_theme_font(&"font") as FontVariation).spacing_glyph == Typography.spacing(&"label"), "外文標籤角色帶字距")
	var body := UiKit.styled("內文", &"body")
	check(not body.has_theme_font_override(&"font"), "內文角色跟著主題換語言，不另外覆寫字體")
	title.free()
	label.free()
	body.free()
	var previous := UiKit.style_override
	UiKit.style_override = "pixel"
	check(UiKit.role_size(&"title") == UiKit.scaled_size(22) and UiKit.role_size(&"caption") == UiKit.scaled_size(11)
		and UiKit.role_size(&"hero") % 11 == 0, "像素字體的角色字級取 11 的整數倍")
	UiKit.style_override = previous


## 地點標示的文字對比（標準見 TYPOGRAPHY.md）：襯底壓在中灰背景上時，外文行至少 4.5:1，地名更高一階。
func _test_contrast() -> void:
	var under := Typography.blend(LocationMarker.WASH_COLOR, LocationMarker.WASH_ALPHA * 0.8, Color(0.5, 0.5, 0.5))
	var sub := Typography.contrast_ratio(LocationMarker.SUB_COLOR, under)
	var name_ratio := Typography.contrast_ratio(LocationMarker.NAME_COLOR, under)
	check(sub >= Typography.MIN_CONTRAST, "外文行對比 %.1f:1 至少 %.1f:1" % [sub, Typography.MIN_CONTRAST])
	check(name_ratio >= sub * 1.3, "地名對比 %.1f:1 比外文行高一階" % name_ratio)
	check(is_equal_approx(Typography.contrast_ratio(Color.WHITE, Color.BLACK), 21.0), "對比公式：白對黑是 21:1")


func _test_marker() -> void:
	var previous := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(false)
	var marker := LocationMarker.for_level(load(PAWNSHOP), "zh", false)
	runner.add_child(marker)
	await frames(2)
	var view := runner.get_viewport().get_visible_rect().size
	var rect := marker.screen_rect()
	check(rect.has_area() and rect.position.x > view.x * 0.5 and rect.position.y > view.y * 0.6, "地點標示在右下角：%s" % rect)
	check(is_equal_approx(rect.end.x, view.x - LocationMarker.MARGIN_RIGHT) and rect.end.y <= view.y - LocationMarker.CONTROLS_TOP - 6.0,
		"右緣和操作說明對齊、下緣在操作說明上方留出間距：%s" % rect)
	check(marker._sub_label.visible and marker._name_label.get_theme_font(&"font") == Typography.font(&"title")
		and marker._sub_label.get_theme_font(&"font") == Typography.font(&"label"), "第一次到訪有第二行；地名用畫面標題、第二行用外文標籤的字體")
	check(marker._slider.position.x > 0.0, "地名從右邊滑入")
	await runner.get_tree().create_timer(LocationMarker.NAME_DELAY + LocationMarker.NAME_TIME + 0.2).timeout
	check(marker.presentation_alpha() > 0.99 and is_zero_approx(marker._slider.position.x), "淡入後停在原位")
	check(PromptLayout._obstacles.has(marker) and marker.prompt_obstacle_rect().has_area(), "顯示中的標示讓世界提示避開")
	# 判讀優先：玩家站進標示的範圍時，標示淡到很低；離開後恢復。
	var stand_in := Node2D.new()
	stand_in.add_to_group(&"player")
	runner.add_child(stand_in)
	var canvas := runner.get_viewport().get_canvas_transform()
	stand_in.global_position = canvas.affine_inverse() * (rect.get_center() + Vector2(0, 20))
	for i in 20:
		marker._process(0.05)
	check(marker.crowded() and marker._root.modulate.a <= LocationMarker.AVOID_ALPHA + 0.01, "玩家進到標示範圍時標示淡到很低（%.2f）" % marker._root.modulate.a)
	stand_in.global_position = canvas.affine_inverse() * Vector2(view.x * 0.2, view.y * 0.5)
	for i in 20:
		marker._process(0.05)
	check(not marker.crowded() and marker._root.modulate.a > 0.95, "玩家離開後標示恢復")
	stand_in.queue_free()
	marker.queue_free()
	await frames(1)
	var short := LocationMarker.for_level(load(PAWNSHOP), "zh", true)
	var ended := [false]
	short.finished.connect(func() -> void: ended[0] = true)
	runner.add_child(short)
	await frames(2)
	check(not short._sub_label.visible and short._name_label.get_theme_font_size(&"font_size") < UiKit.scaled_size(UiKit.FS_TITLE), "回訪只顯示較小的地名")
	var lifetime := short.lifetime()
	await runner.get_tree().create_timer(lifetime + 0.5).timeout
	check(ended[0] and not is_instance_valid(short), "回訪版播完自行釋放（%.1f 秒內）" % (lifetime + 0.5))
	Settings.set_reduce_ui_motion(previous)


func _test_marker_still_and_suspended() -> void:
	var previous := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(true)
	var marker := LocationMarker.for_level(load(STREET), "zh", false)
	runner.add_child(marker)
	await frames(2)
	check(is_equal_approx(marker._rail, 1.0) and is_zero_approx(marker._slider.position.x), "減少動態：細軌直接到位、不滑動，只淡入")
	runner.get_tree().paused = true
	marker._process(0.0)
	check(not marker._root.visible and not marker._tween.is_running(), "暫停時藏起來並凍結")
	var alpha := marker._text_alpha
	await runner.get_tree().create_timer(0.3, true).timeout
	check(marker._text_alpha == alpha, "暫停期間不消耗停留時間")
	runner.get_tree().paused = false
	marker._process(0.0)
	check(marker._root.visible and marker._tween.is_running(), "解除暫停後接著播放")
	marker.queue_free()
	Settings.set_reduce_ui_motion(previous)
	await frames(1)


func _test_end_card() -> void:
	var card := ChapterCard.new()
	card.title = "第一章　傘　完"
	card.chapter_number = "第一章"
	card.chapter_name = "傘"
	card.seal_text = "完"
	card.subtitle = "下一步：明早核對交盤回執。"
	card.hold = 0.1
	var ended := [false]
	card.finished.connect(func() -> void: ended[0] = true)
	runner.add_child(card)
	await frames(2)
	check(GameplayLock.is_locked(), "章末畫面鎖住操作")
	var labels := card._content.find_children("*", "Label", true, false)
	var texts := labels.map(func(l: Label) -> String: return l.text)
	check(texts.has("第一章") and texts.has("傘") and texts.has("下一步：明早核對交盤回執。"), "章末畫面分開排序號、章名、提示：%s" % [texts])
	var name_label: Label = labels[texts.find("傘")]
	check(name_label.get_theme_font(&"font") == Typography.font(&"hero") and card.name_font_size() == UiKit.role_size(&"hero")
		and card.name_font_size() >= 100, "章名用時刻大標（約為 NE-421 的兩倍）：%d" % card.name_font_size())
	var number_label: Label = labels[texts.find("第一章")]
	var teaser_label: Label = labels[texts.find("下一步：明早核對交盤回執。")]
	check(number_label.get_theme_font_size(&"font_size") < card.name_font_size() / 4 and teaser_label.get_theme_font_size(&"font_size") < card.name_font_size() / 4,
		"序號與提示比章名小很多，層級拉開")
	# 提早收尾：開始不久的按鍵不算（避免帶著上一個畫面的按鍵直接跳過）。
	var press := InputEventAction.new()
	press.action = &"ui_accept"
	press.pressed = true
	card._input(press)
	check(not card._closing, "剛開始的確認鍵不會跳過章末畫面")
	card._elapsed = ChapterCard.SKIP_AFTER
	card._input(press)
	await runner.get_tree().create_timer(ChapterCard.SKIP_OUT + 0.3).timeout
	check(ended[0] and not GameplayLock.is_locked(), "確認鍵提早收尾並解除鎖定")
	check(is_instance_valid(card) and card._root.visible, "收尾後黑底留著給結算畫面接手")
	card.queue_free()
	await frames(1)
	# 英文：序號與章名一樣分開、一樣蓋印；太長的章名縮小到放得下。
	var english := ChapterCard.new()
	var parts := ChapterCard.split_end_title("Chapter Five: The Paymaster", "Chapter Five: The Payer — End")
	english.chapter_number = parts[0]
	english.chapter_name = parts[1]
	english.seal_text = parts[2]
	english.subtitle = "Next Chapter: Unmooring"
	runner.add_child(english)
	await frames(2)
	var view_width := runner.get_viewport().get_visible_rect().size.x
	var name_width := english._name_label.get_theme_font(&"font").get_string_size(english._name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, english.name_font_size()).x
	check(english.chapter_number == "CHAPTER FIVE" and english._name_label.text == "The Paymaster", "英文章末分成序號與章名")
	check(name_width <= view_width * ChapterCard.NAME_MAX_WIDTH + 1.0 and english.name_font_size() >= UiKit.role_size(&"display"),
		"長的英文章名縮小到畫面寬度內（%d 號字、寬 %.0f）" % [english.name_font_size(), name_width])
	var seals := english._name_label.get_children().filter(func(n: Node) -> bool: return n.get_script() != null and n.visible)
	check(not seals.is_empty(), "英文章末也蓋印")
	english._done()
	english.queue_free()
	await frames(1)


## 進入章節第一個區域：不再把章節卡疊在畫面上，改顯示地點標示。
func _test_level_entry() -> void:
	var previous_skip := Story.auto_skip
	Story.auto_skip = true
	var data := (load(PAWNSHOP) as LevelData).duplicate() as LevelData
	data.intro_scene = &""
	data.show_chapter_card = true
	var level := await start_level(data)
	var marker: LocationMarker = null
	var cards := 0
	for i in 120:
		for node in level.find_children("*", "", true, false):
			if node is LocationMarker:
				marker = node
			elif node is ChapterCard:
				cards += 1
		if marker != null:
			break
		await frames(1)
	check(marker != null and marker.place_name == "當舖", "章節第一個區域顯示地點標示")
	check(cards == 0, "進入章節不再疊章節卡")
	var runtime := level.run_snapshot()
	await end_level(level)
	# 從主選單接續存檔：告訴玩家人在哪裡。
	var resumed := Level.new()
	resumed.configure(data)
	resumed.configure_resume(runtime)
	runner.get_tree().root.add_child(resumed)
	var resumed_marker := false
	for i in 120:
		await frames(1)
		for node in resumed.find_children("*", "", true, false):
			if node is LocationMarker:
				resumed_marker = true
		if resumed_marker:
			break
	check(resumed_marker, "接續存檔時顯示目前地點")
	await end_level(resumed)
	Story.auto_skip = previous_skip

## 蓋住遊戲的畫面出現時地點標示藏起來（NE-490）：共用判斷 UiLayers.gameplay_covered，圖層在這些畫面之下。
func _test_covered_screens() -> void:
	check(UiLayers.LOCATION_MARKER > UiLayers.HUD and UiLayers.LOCATION_MARKER < UiLayers.DEATH and UiLayers.LOCATION_MARKER < UiLayers.INVENTORY
		and UiLayers.LOCATION_MARKER < UiLayers.PAUSE and UiLayers.LOCATION_MARKER < UiLayers.CONTROLLER_NOTICE, "地點標示畫在 HUD 之上、所有蓋住遊戲的畫面之下")
	for path in ["res://ui/death_screen.gd", "res://ui/controller_recovery_prompt.gd", "res://ui/victory_screen.gd", "res://ui/run_overwrite_prompt.gd",
			"res://ui/destination_save_prompt.gd", "res://ui/radio_save_prompt.gd"]:
		check(FileAccess.get_file_as_string(path).contains("add_to_group(UiLayers.COVER_GROUP)"), "蓋住遊戲的畫面登記到共用群組：%s" % path)
	var marker := LocationMarker.new()
	marker.place_name = "測試地點"
	runner.add_child(marker)
	await frames(2)
	marker._process(0.0)
	check(marker._root.visible, "沒有東西蓋住時地點標示顯示")
	var death := DeathScreen.new()
	death.setup(DefeatCodex.unlock(&"grunt_shot", Story.language), true)
	runner.add_child(death)
	await frames(2)
	marker._process(0.0)
	check(UiLayers.gameplay_covered(runner.get_tree()) and not marker._root.visible and not marker._tween.is_running(), "死亡畫面開著時地點標示藏起來並凍結")
	death.queue_free()
	await frames(2)
	marker._process(0.0)
	check(marker._root.visible, "死亡畫面關掉後地點標示恢復")
	var prompt := (load("res://ui/controller_recovery_prompt.gd") as GDScript).new() as Control
	runner.add_child(prompt)
	await frames(2)
	marker._process(0.0)
	check(not marker._root.visible, "手把斷線提示開著時地點標示藏起來")
	prompt.queue_free()
	await frames(2)
	marker.queue_free()
	await frames(1)


## 章末畫面收尾後沒有人接手（例如工具單獨載入這一區）：黑底淡掉並釋放，不會停在黑畫面。
func _test_end_card_handoff() -> void:
	var card := ChapterCard.new()
	card.chapter_name = "傘"
	card.hold = 0.05
	runner.add_child(card)
	await frames(2)
	check(UiLayers.presentation_busy(runner.get_tree()), "章末畫面在的時候工具查得到「有全螢幕的演出在進行」")
	card._done()
	await runner.get_tree().create_timer(ChapterCard.HANDOFF_WAIT + ChapterCard.HANDOFF_FADE + 0.4).timeout
	check(not is_instance_valid(card), "沒有人接手時章末畫面的黑底淡掉並釋放")
	check(not UiLayers.presentation_busy(runner.get_tree()), "釋放後工具可以取樣")


## 地點標示顯示的是地點名稱：區域的名稱欄位不能寫成章節標題（NE-490）。
func _test_place_names_are_places() -> void:
	var titles: Array[String] = []
	for chapter in Story.chapter_ids():
		titles.append(str(Story.chapter_info(chapter).get("title", "")))
	var pattern := RegEx.create_from_string("第.{1,3}章|序章|Chapter\\s")
	var wrong: Array[String] = []
	for path in DirAccess.get_files_at("res://data/levels"):
		if not path.ends_with(".tres"):
			continue
		var data := load("res://data/levels/" + path) as LevelData
		if data == null:
			continue
		for name: String in [data.display_name, str(data.localized_names.get("en", "")), str(data.localized_names.get("ja", ""))]:
			if titles.has(name) or pattern.search(name) != null:
				wrong.append("%s：%s" % [path, name])
	check(wrong.is_empty(), "區域名稱都是地點，不是章節標題（%s）" % ", ".join(wrong))

## 文字的交通管制（NE-491）：優先順序高的先講，同樣高時先來的保留；不講了就交出去。
func _test_text_traffic_order() -> void:
	TextTraffic.reset()
	var board := RefCounted.new()
	var ambient := RefCounted.new()
	var addressed := RefCounted.new()
	check(TextTraffic.claim(board, TextTraffic.Voice.BOARD), "只有看板要講時看板拿到發言")
	check(TextTraffic.claim(ambient, TextTraffic.Voice.AMBIENT) and TextTraffic.speaker() == ambient.get_instance_id(), "閒聊優先於看板")
	TextTraffic.claim(addressed, TextTraffic.Voice.ADDRESSED)
	check(TextTraffic.speaker() == addressed.get_instance_id(), "對主角說的話優先於閒聊")
	TextTraffic.release(addressed)
	TextTraffic.release(ambient)
	check(TextTraffic.speaker() == board.get_instance_id(), "其他人講完後看板拿回發言")
	var other_board := RefCounted.new()
	TextTraffic.claim(other_board, TextTraffic.Voice.BOARD)
	check(TextTraffic.speaker() == board.get_instance_id(), "同樣優先時先來的保留發言，不會互搶")
	TextTraffic.reset()
	check(TextTraffic.claim(null, TextTraffic.Voice.NONE), "不是講話的文字（互動提示）永遠可以顯示")


## 看板、互動提示、路人氣泡同時在場：氣泡在講的時候看板只亮螢幕不展開；展開的文字塊最多兩塊（互動提示＋一個講話的）且互不重疊。
func _test_text_traffic_scene() -> void:
	TextTraffic.reset()
	var holder := Node2D.new()
	runner.add_child(holder)
	var speaker := Node2D.new()
	speaker.position = Vector2(220, 260)
	holder.add_child(speaker)
	var interaction := WorldPrompt.new()
	interaction.text = "{interact} 和發傳單的人說話"
	interaction.reach_check = func() -> bool: return true
	interaction.position = Vector2(200, 230)
	holder.add_child(interaction)
	var board := WorldPrompt.new()
	board.text = "街角的巷子裡有電話亭，先去備份。"
	board.voice = TextTraffic.Voice.BOARD
	board.reach_check = func() -> bool: return true
	board.position = Vector2(150, 250)
	holder.add_child(board)
	var bubbles := MapBubbles.new()
	bubbles.anchor_resolver = func(_speaker: String) -> Node2D: return speaker
	holder.add_child(bubbles)
	var lines: Array[Dictionary] = [{"speaker": "street_vendor", "text": "市集那頭被收帳的封了，菜車只好繞去碼頭。", "color": Palette.UI_TEXT}]
	bubbles.show_lines(&"traffic_fixture", lines)
	for i in 20:
		await frames(1)
	var shown: Array[Rect2] = []
	for prompt: WorldPrompt in [interaction, board]:
		if prompt.is_showing() and prompt._alpha > 0.0:
			shown.append(Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size))
	for bubble: Dictionary in bubbles._active:
		var rect: Rect2 = bubble.get("rect", Rect2())
		if rect.has_area():
			shown.append(rect)
	check(not board.is_showing() or board._alpha <= 0.0, "氣泡在講的時候看板不展開文字")
	check(shown.size() <= 2, "同一格展開的文字塊最多兩塊（%d）" % shown.size())
	var overlap := false
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			overlap = overlap or shown[i].intersects(shown[j])
	check(not overlap, "展開的文字塊互不重疊：%s" % [shown])
	# 氣泡講完後看板拿回發言並展開。
	var deadline := MapBubbles.HOLD_MAX + MapBubbles.FADE_OUT + 1.0
	await runner.get_tree().create_timer(deadline).timeout
	for i in 20:
		await frames(1)
	check(board.is_showing() and board._alpha > 0.0, "氣泡講完後看板展開")
	holder.queue_free()
	await frames(2)
	TextTraffic.reset()

## 過場的文字框不蓋住講者（NE-492）：挑不蓋住人的位置；目前位置可用就不換；都蓋到時鏡頭讓位但不拍到背景圖以外。
func _test_text_box_placement() -> void:
	var screen := Vector2(640, 360)
	var safe := Rect2(0, 42.857, 640, 274.29)
	var actors: Array[Dictionary] = [{"id": "left", "feet": Vector2(270, 300), "tall": 120.0}, {"id": "right", "feet": Vector2(520, 300), "tall": 120.0}]
	var protected := TextBoxPlacement.protected_rects(actors, Vector2(320, 180), 1.0, screen)
	var choices := TextBoxPlacement.choice_candidate_set(safe, Vector2(300, 140), 14.0, 84.0, 20.0)
	var pick := TextBoxPlacement.first_free(choices, protected, safe)
	check(pick >= 0 and not choices[pick].intersects(protected[1]), "右邊有人時選擇框換到不蓋住人的位置（%d）" % pick)
	check(TextBoxPlacement.first_free(choices, [], safe, 2) == 2, "目前的位置還可以用就不換")
	var crowd: Array[Dictionary] = [{"id": "a", "feet": Vector2(250, 300), "tall": 150.0}, {"id": "b", "feet": Vector2(400, 300), "tall": 150.0}]
	var crowded := TextBoxPlacement.protected_rects(crowd, Vector2(320, 180), 1.3, screen)
	var room := TextBoxPlacement.make_room(crowd, Vector2(320, 180), 1.3, screen, safe, choices)
	if TextBoxPlacement.first_free(choices, crowded, safe) < 0:
		check(room["ok"], "每個位置都蓋到人時鏡頭讓位")
	if room["ok"]:
		check(TextBoxPlacement.DEFAULT_ART.grow(0.5).encloses(TextBoxPlacement.view_rect(room["cam"], room["zoom"], screen)), "讓位後不拍到背景圖以外")
	var clamped := TextBoxPlacement.clamp_cam(Vector2(900, 180), 1.0, screen, TextBoxPlacement.DEFAULT_ART)
	check(TextBoxPlacement.DEFAULT_ART.encloses(TextBoxPlacement.view_rect(clamped, 1.0, screen)), "鏡頭推回背景圖裡")


## 所有章節的過場：每一句台詞與每個選擇框都有不蓋住演員臉與上半身的位置（或鏡頭讓位後有）。
func _test_cutscene_text_boxes() -> void:
	var problems := PackedStringArray()
	var staged := 0
	for id: String in Story._scenes:
		var scene: Variant = Story._scenes[id]
		if not scene is Dictionary or not (scene as Dictionary).get("steps") is Array:
			continue
		if not (scene["steps"] as Array).any(func(step: Variant) -> bool: return step is Dictionary and str(step.get("do", "")) == "scene"):
			continue
		staged += 1
		problems.append_array(CutsceneChecker.text_box_problems(id, scene))
	check(staged > 50 and problems.is_empty(), "%d 段過場的文字框都不蓋住講者（%s）" % [staged, ", ".join(problems)])


## NE-493：世界裡的文字（互動提示、拾取說明、氣泡）在螢幕上的字高不隨鏡頭倍率變（回憶舞台 1.4、關卡 1.92、測試場景 2.4、拉近的脈衝），
## 720p、1080p、21:9 與文字 1.2 倍下，同一類文字在不同倍率的字高相差不超過 1 像素；寬度不超過該類的上限。
func _test_world_text_screen_size() -> void:
	var original_scale := Settings.get_ui_text_scale()
	var windows := {"720p": Vector2(1280, 720), "1080p": Vector2(1920, 1080), "21:9": Vector2(2560, 1080)}
	for text_scale: float in [1.0, 1.2]:
		Settings.set_ui_text_scale(text_scale)
		var heights := {}
		for zoom: float in [1.4, 1.92, 1.92 * 1.06, 2.4]:
			var measured := await _measure_world_text(zoom)
			for kind: StringName in measured:
				var list: Array = heights.get(kind, [])
				list.append(measured[kind])
				heights[kind] = list
		for kind: StringName in heights:
			var design: Array = heights[kind]
			check(design.size() == 4, "%s 在四種鏡頭倍率都量得到（%d）" % [kind, design.size()])
			for window: String in windows:
				var size: Vector2 = windows[window]
				var stretch := minf(size.x / 640.0, size.y / 360.0)
				var low := INF
				var high := -INF
				for value: float in design:
					low = minf(low, value * stretch)
					high = maxf(high, value * stretch)
				check(high - low <= 1.0, "%s 在 %s、文字 %.1f 倍時各倍率字高 %.1f～%.1f 像素，相差不超過 1" % [kind, window, text_scale, low, high])
				var expected := WorldText.font_size(kind) * stretch
				check(absf(high - expected) <= 1.0, "%s 在 %s 的字高 %.1f 像素等於字體角色 %s（%.1f）" % [kind, window, high, WorldText.role(kind), expected])
	Settings.set_ui_text_scale(original_scale)


## 在倍率 zoom 的鏡頭下放一個互動提示、一個拾取說明與兩種氣泡，回傳每一類文字在 640×360 畫布上的字高。
func _measure_world_text(zoom: float) -> Dictionary:
	TextTraffic.reset()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	runner.add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	var camera := Camera2D.new()
	camera.position = Vector2(320, 180)
	camera.zoom = Vector2.ONE * zoom
	world.add_child(camera)
	camera.make_current()
	var prompt := WorldPrompt.new()
	prompt.text = "{interact} 打開閘門"
	prompt.reach_check = func() -> bool: return true
	prompt.position = Vector2(270, 200)
	world.add_child(prompt)
	var pickup := WorldPrompt.new()
	pickup.text = "止痛貼片：撐過下一場就好。"
	pickup.text_kind = &"pickup"
	pickup.reach_check = func() -> bool: return true
	pickup.position = Vector2(370, 150)
	world.add_child(pickup)
	var speaker := Node2D.new()
	speaker.position = Vector2(320, 230)
	world.add_child(speaker)
	var bubbles := MapBubbles.new()
	bubbles.anchor_resolver = func(_id: String) -> Node2D: return speaker
	world.add_child(bubbles)
	await frames(3)
	var result := {}
	for item: WorldPrompt in [prompt, pickup]:
		result[item.text_kind] = item._font_size * item.get_global_transform_with_canvas().get_scale().y
		check(item._box.size.x <= WorldText.max_width(item.text_kind) + (WorldPrompt.PADDING.x + 1.0) * 2.0,
			"%s 的寬度 %.0f 不超過上限（倍率 %.2f）" % [item.text_kind, item._box.size.x, zoom])
	for voice: int in [TextTraffic.Voice.AMBIENT, TextTraffic.Voice.ADDRESSED]:
		var bubble := {"voice": voice, "text": "市集那頭被收帳的封了，菜車只好繞去碼頭。"}
		var kind := MapBubbles.kind_of(bubble)
		var unit := WorldText.unit(bubbles)
		result[kind] = WorldText.font_size(kind) * bubbles.get_global_transform_with_canvas().get_scale().y * unit
		check(WorldText.paragraph(bubble["text"], kind).get_size().x <= WorldText.max_width(kind) + 0.5, "%s 氣泡的寬度不超過上限" % kind)
	viewport.queue_free()
	await frames(1)
	return result


## NE-493：所有地圖氣泡的台詞與拾取物的說明，在文字 1.2 倍時也不超過該類的行數上限。
func _test_world_text_fits() -> void:
	var original_scale := Settings.get_ui_text_scale()
	Settings.set_ui_text_scale(1.2)
	var over := PackedStringArray()
	var bubble_lines := 0
	for id: Variant in Story.scene_ids():
		var scene: Dictionary = Story.audit_data()["scenes"].get(id, {})
		if StringName(str(scene.get("mode", ""))) != Story.MODE_BUBBLES:
			continue
		var lines := Story.resolved_lines(StringName(str(id)))
		var kind := &"addressed" if lines.any(func(l: Dictionary) -> bool: return str(l.get("speaker", "")) == "rin") else &"ambient"
		for line: Dictionary in lines:
			bubble_lines += 1
			var count := WorldText.paragraph(str(line.get("text", "")), kind).get_line_count()
			if count > WorldText.max_lines(kind):
				over.append("%s（%s %d 行）" % [id, kind, count])
	check(bubble_lines > 40, "檢查到地圖氣泡的台詞（%d 句）" % bubble_lines)
	var pickups := 0
	for folder: String in ["res://data/consumables", "res://data/weapons", "res://data/weapons/melee", "res://data/story_items"]:
		for file: String in ResourceLoader.list_directory(folder):
			if not file.ends_with(".tres"):
				continue
			var resource := load(folder.path_join(file))
			var text := ""
			if resource is StoryItemData:
				text = "%s：%s" % [resource.title_text(), resource.description_text()]
			elif resource != null and resource.has_method(&"display_name_for") and resource.has_method(&"description_for"):
				text = Pickup._describe(resource.display_name_for(Story.language), resource.description_for(Story.language))
			if text.strip_edges().is_empty():
				continue
			pickups += 1
			var count := WorldText.paragraph(text, &"pickup").get_line_count()
			if count > WorldText.max_lines(&"pickup"):
				over.append("%s（%d 行）" % [file, count])
	check(pickups > 20, "檢查到拾取物的說明（%d 個）" % pickups)
	check(over.is_empty(), "地圖氣泡與拾取說明在文字 1.2 倍時不超過行數上限：%s" % ", ".join(over))
	Settings.set_ui_text_scale(original_scale)


## NE-493：在真實區域量。取景最緊的是第一章街道靠近人物時（21:9 遮幅，看得到約 143 個世界單位高），最鬆的是沒有遮幅的倉庫（約 188）；
## 同一類文字的字高在 720p、1080p、21:9 與文字 1.0、1.2 倍時相差不超過 1 像素，等於字體角色的字級。
func _test_world_text_real_areas() -> void:
	var previous_skip := Story.auto_skip
	Story.auto_skip = true
	var factors := {}
	var view_heights := {}
	for area: Array in [["街道", STREET, 1.0], ["倉庫", WAREHOUSE, 0.0]]:
		var data := (load(area[1]) as LevelData).duplicate() as LevelData
		data.intro_scene = &""
		var level := await start_level(data)
		Story.framing.amount = area[2]
		var prompt := WorldPrompt.new()
		prompt.text = "{interact} 打開閘門"
		prompt.reach_check = func() -> bool: return true
		level.add_child(prompt)
		prompt.global_position = level.player.global_position + Vector2(0.0, -48.0)
		var pickup := WorldPrompt.new()
		pickup.text = "止痛貼片：撐過下一場就好。"
		pickup.text_kind = &"pickup"
		pickup.reach_check = func() -> bool: return true
		level.add_child(pickup)
		pickup.global_position = level.player.global_position + Vector2(60.0, -20.0)
		await frames(3)
		var host: MapBubbles = null
		for node in level.find_children("*", "", true, false):
			if node is MapBubbles:
				host = node
		view_heights[area[0]] = Story.framing.safe_rect().size.y / level.camera.zoom.y
		# 畫面像素對字級的倍率：字高＝字級 × 這個倍率 × 視窗縮放。
		factors[area[0]] = {
			&"prompt": prompt.get_global_transform_with_canvas().get_scale().y,
			&"pickup": pickup.get_global_transform_with_canvas().get_scale().y,
			&"addressed": host.get_global_transform_with_canvas().get_scale().y * WorldText.unit(host) if host != null else 0.0,
			&"ambient": host.get_global_transform_with_canvas().get_scale().y * WorldText.unit(host) if host != null else 0.0,
		}
		Story.framing.amount = 0.0
		await end_level(level)
	Story.auto_skip = previous_skip
	check(absf(float(view_heights["街道"]) - 143.0) < 4.0 and float(view_heights["倉庫"]) > 180.0,
		"最緊的街道約 143 個世界單位高、最鬆的倉庫超過 180（%.0f／%.0f）" % [view_heights["街道"], view_heights["倉庫"]])
	var original_scale := Settings.get_ui_text_scale()
	for text_scale: float in [1.0, 1.2]:
		Settings.set_ui_text_scale(text_scale)
		for kind: StringName in [&"prompt", &"pickup", &"addressed", &"ambient"]:
			for window: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1080)]:
				var stretch := minf(window.x / 640.0, window.y / 360.0)
				var tight := WorldText.font_size(kind) * float(factors["街道"][kind]) * stretch
				var loose := WorldText.font_size(kind) * float(factors["倉庫"][kind]) * stretch
				check(absf(tight - loose) <= 1.0 and absf(tight - WorldText.font_size(kind) * stretch) <= 1.0,
					"%s 在 %dx%d、文字 %.1f 倍：街道 %.1f、倉庫 %.1f 像素，等於字級" % [kind, window.x, window.y, text_scale, tight, loose])
	Settings.set_ui_text_scale(original_scale)


## NE-493：拾取說明不排隊（一直可以顯示），但不能蓋住正在講話的氣泡，也不能把氣泡擠走。
func _test_pickup_yields_to_bubble() -> void:
	TextTraffic.reset()
	var holder := Node2D.new()
	runner.add_child(holder)
	var speaker := Node2D.new()
	speaker.position = Vector2(220, 260)
	holder.add_child(speaker)
	var bubbles := MapBubbles.new()
	bubbles.anchor_resolver = func(_speaker: String) -> Node2D: return speaker
	holder.add_child(bubbles)
	var lines: Array[Dictionary] = [{"speaker": "street_vendor", "text": "市集那頭被收帳的封了，菜車只好繞去碼頭。", "color": Palette.UI_TEXT}]
	bubbles.show_lines(&"pickup_fixture", lines)
	# 等氣泡排好位置（機器忙時可能晚幾格）。
	for i in 90:
		await frames(1)
		if not bubbles._active.is_empty() and (bubbles._active[0].get("rect", Rect2()) as Rect2).has_area():
			break
	var natural: Rect2 = bubbles._active[0].get("rect", Rect2()) if not bubbles._active.is_empty() else Rect2()
	# 拾取說明放在氣泡原本的位置上。
	var pickup := WorldPrompt.new()
	pickup.text = "止痛貼片：撐過下一場就好，別當成治療。"
	pickup.text_kind = &"pickup"
	pickup.reach_check = func() -> bool: return true
	pickup.position = natural.get_center() + Vector2(0.0, natural.size.y * 0.5)
	holder.add_child(pickup)
	for i in 20:
		await frames(1)
	var bubble_rect: Rect2 = bubbles._active[0].get("rect", Rect2()) if not bubbles._active.is_empty() else Rect2()
	var shown := pickup.is_showing() and pickup._alpha > 0.0
	var pickup_rect := Rect2(pickup.base_rect().position + pickup._nudge, pickup.base_rect().size)
	check(natural.has_area() and bubble_rect.is_equal_approx(natural), "拾取說明出現後氣泡留在原位（%s → %s）" % [natural, bubble_rect])
	check(shown, "拾取說明不排隊：有人講話時仍然顯示")
	check(not shown or not pickup_rect.intersects(bubble_rect), "拾取說明不蓋住正在講話的氣泡")
	holder.queue_free()
	await frames(1)
