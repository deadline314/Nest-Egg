class_name PresentationSuite
extends TestSuite
## 章節與地點的呈現：進場不疊章節卡、地點標示（右下角、回訪短版、暫停凍結、減少動態）、
## 章末畫面拆章名與印、暫停與主選單的章節名與地名、標題字體涵蓋所有地名與章名、共用字體階層（NE-422）。

const PAWNSHOP := "res://data/levels/ch1_pawnshop.tres"
const STREET := "res://data/levels/ch1_street.tres"
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
	await _test_level_entry()


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