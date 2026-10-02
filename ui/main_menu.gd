class_name MainMenu
extends Control
## 主選單：選擇難度、開始遊戲、查看敗北圖鑑。每個選項都有一句重點 tooltip。

signal start_requested(difficulty: DifficultyData)
signal quit_requested

var _selected: DifficultyData
var _description: Label
var _difficulty_buttons: Array[Button] = []
var _start_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not get_parent() is Control:
		UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	_selected = GameState.difficulty
	add_child(LevelBackground.new())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	center.add_child(box)

	var title := UiKit.label("NEST EGG", 34, LightKit.glow(Palette.CYAN, 1.6), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(title)
	box.add_child(UiKit.label("巢中之卵　—　垂直切片", 12, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_spacer(10))

	box.add_child(UiKit.label("難度", 11, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 6)
	box.add_child(row)
	var group := ButtonGroup.new()
	for difficulty in GameState.difficulties:
		var b := UiKit.button(difficulty.display_name, _select_difficulty.bind(difficulty), difficulty.description)
		b.custom_minimum_size = Vector2(88, 0)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = difficulty == _selected
		row.add_child(b)
		_difficulty_buttons.append(b)
	_description = UiKit.label("", 10, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_description.custom_minimum_size = Vector2(300, 28)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_description)

	_start_button = UiKit.button("開始任務", _on_start, "以選擇的難度開始")
	box.add_child(_start_button)
	box.add_child(UiKit.button("敗北圖鑑", _open_codex, "查看已解鎖的失敗紀錄與攻略"))
	box.add_child(UiKit.button("離開", quit_requested.emit, "關閉遊戲"))
	_update_description()
	_start_button.grab_focus.call_deferred()


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _select_difficulty(difficulty: DifficultyData) -> void:
	_selected = difficulty
	_update_description()


func _update_description() -> void:
	if _selected == null:
		return
	var lives := "無限接關" if not _selected.has_limited_lives() else "殘機 %d" % _selected.lives
	_description.text = "%s（生命 %d・%s）" % [_selected.description, _selected.player_max_health, lives]


func _on_start() -> void:
	start_requested.emit(_selected)


func _open_codex() -> void:
	var codex := CodexScreen.new()
	codex.closed.connect(_start_button.grab_focus)
	add_child(codex)
