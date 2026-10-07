class_name UiKitSuite
extends TestSuite
## 介面共用元件（NE-35）：字體與備援、字級、切角外框、分段條、按鈕、橫幅、主題覆蓋。


func run() -> void:
	_test_font()
	_test_sizes()
	await _test_widgets()
	_test_theme()


func _test_font() -> void:
	var previous := Settings.get_ui_font()
	var font := UiKit.font()
	check(font is FontVariation, "公開的字型是一層 FontVariation（切換樣式時所有使用者一起換）")
	var base := (font as FontVariation).base_font
	check(base is FontFile, "專案字體載入成功（FontFile）")
	check(base.get_fallbacks().size() >= 1, "專案字體有系統備援")
	check(font.has_char("回".unicode_at(0)) and font.has_char("溯".unicode_at(0)), "字體含常用劇情字")
	check(FileAccess.file_exists("res://art/fonts/OFL-Cubic11.txt") and FileAccess.file_exists("res://art/fonts/OFL-NotoSansTC.txt"), "兩種字體的授權文件都存在")
	# 樣式：預設平滑，可切到像素；亂寫的樣式退回預設；已經拿著字型的標籤立刻跟著換
	Settings.set_ui_font("smooth")
	check(Settings.get_ui_font() == "smooth" and UiKit.font_style() == "smooth", "預設是平滑字型")
	var smooth_base := (UiKit.font() as FontVariation).base_font
	check((smooth_base as FontFile).resource_path.contains("NotoSansTC") or (smooth_base as FontFile).data.size() > 500000, "平滑樣式用思源黑體子集")
	var label := Label.new()
	label.add_theme_font_override(&"font", UiKit.font())
	var smooth_width := label.get_theme_font(&"font").get_string_size("水位又上來了", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY).x
	Settings.set_ui_font("pixel")
	check(UiKit.font_style() == "pixel" and (UiKit.font() as FontVariation).base_font != smooth_base, "切到像素字之後底層字型換掉")
	var pixel_width := label.get_theme_font(&"font").get_string_size("水位又上來了", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY).x
	check(smooth_width <= pixel_width + 0.01, "平滑字型的中文不比像素字寬（原本排得下的版面不會爆：%.0f vs %.0f）" % [smooth_width, pixel_width])
	Settings.set_value(Settings.DISPLAY_SECTION, "ui_font", "no_such_style")
	check(Settings.get_ui_font() == UiKit.DEFAULT_FONT_STYLE and UiKit.font_style() == UiKit.DEFAULT_FONT_STYLE, "設定裡寫了不存在的字型樣式時退回預設")
	label.free()
	Settings.set_ui_font(previous)
	Settings.reset_display()
	check(Settings.get_ui_font() == UiKit.DEFAULT_FONT_STYLE, "恢復顯示預設也會把字型改回預設")


func _test_sizes() -> void:
	check(UiKit.snap_size(9) == UiKit.FS_BODY and UiKit.snap_size(12) == UiKit.FS_BODY, "小字級吸附到內文")
	check(UiKit.snap_size(18) == UiKit.FS_TITLE, "中字級吸附到標題")
	check(UiKit.snap_size(34) == UiKit.FS_DISPLAY, "大字級吸附到大標")
	var label := UiKit.label("測試", 14)
	check(label.get_theme_font_size(&"font_size") == UiKit.FS_BODY, "label() 套用吸附後的字級")
	label.free()


func _test_widgets() -> void:
	var root := UiKit.full_rect_root(runner)
	# 切角外框的所有變化都能畫出來（不報錯、尺寸極小時安全略過）。
	for variant in 5:
		var box := ChamferBox.make(Palette.UI_PANEL, Palette.CYAN, 4)
		box.bracket = Palette.CYAN
		box.scanlines = 0.1
		box.glow = Color(Palette.CYAN, 0.1)
		box.dashed = variant == 1
		box.open_bottom = variant == 2
		box.corners = ChamferBox.Corner.TOP if variant == 3 else ChamferBox.Corner.ALL
		var panel := Panel.new()
		panel.add_theme_stylebox_override(&"panel", box)
		panel.size = Vector2(2, 2) if variant == 4 else Vector2(80, 30)
		root.add_child(panel)
	await frames(2)

	var bar := SegmentBar.new()
	bar.segments = 10
	bar.size = Vector2(100, 6)
	root.add_child(bar)
	bar.set_ratio(0.5)
	check(is_equal_approx(bar.ratio(), 0.5), "分段條記住數值")
	bar.set_ratio(2.0)
	check(is_equal_approx(bar.ratio(), 1.0), "分段條數值夾在 0 到 1")
	bar.set_ratio(0.2)
	await frames(3)
	check(bar.is_processing(), "數值下降時殘影動畫啟動")
	bar.trail_hold = 0.0
	bar.trail_fade = 0.05
	await runner.get_tree().create_timer(0.4).timeout
	check(not bar.is_processing(), "殘影結束後停止每影格更新")

	var button := UiKit.button("測試", Callable(), "一句重點")
	check(button is UiButton and button.tooltip_text == "一句重點", "按鈕為共用元件並帶提示")
	root.add_child(button)
	var pressed_count := [0]
	button.pressed.connect(func() -> void: pressed_count[0] += 1)
	button.pressed.emit()
	await frames(2)
	check(pressed_count[0] == 1, "按鈕確認訊號正常")
	button.disabled = true
	await frames(2)
	check(button.disabled, "按鈕可禁用")

	var banner := UiBanner.new()
	root.add_child(banner)
	banner.show_text("取得：醫療包", UiBanner.Kind.ITEM, 0.2)
	await frames(8)
	check(banner.is_showing(), "橫幅滑入後可見")
	await runner.get_tree().create_timer(0.8).timeout
	check(not banner.is_showing(), "橫幅停留後自動退場")

	var hint := UiHint.new()
	root.add_child(hint)
	hint.set_text("按 E 檢查")
	hint.pop()
	await frames(2)
	check(hint.size.x > 40.0, "提示框依文字決定寬度")
	root.queue_free()
	await frames(2)


func _test_theme() -> void:
	var t := UiKit.theme()
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		check(t.get_stylebox(state, &"Button") is ChamferBox, "按鈕狀態 %s 使用切角外框" % state)
	check(t.get_stylebox(&"panel", &"TooltipPanel") is ChamferBox, "提示框使用切角外框")
	check(t.get_stylebox(&"tab_selected", &"TabContainer") is ChamferBox, "頁籤使用切角外框")
	check(t.has_icon(&"checked", &"CheckButton"), "勾選框有圖示")
	check(t.default_font_size == UiKit.FS_BODY, "預設字級為內文字級")
