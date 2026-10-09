class_name UiPanel
extends PanelContainer
## 帶標題帶的面板：頂端一條標題（小菱形 + 標題字 + 分隔線），下方是內容區。
## 內容請加進 body。

var body: VBoxContainer
var _title_label: Label


func _init(title: String = "", accent: Color = Palette.CYAN) -> void:
	var box := ChamferBox.make(UiTheme.PANEL_BODY, UiTheme.PANEL_EDGE, 6)
	box.bracket = accent
	box.margins(14, 10, 14, 10)
	add_theme_stylebox_override(&"panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	add_child(column)
	if title != "":
		_title_label = UiKit.label(title, UiKit.FS_BODY, accent)
		column.add_child(_title_label)
		var divider := UiDivider.new()
		divider.color = Color(accent, 0.5)
		column.add_child(divider)
	body = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 6)
	column.add_child(body)


func set_title(title: String) -> void:
	if _title_label != null:
		_title_label.text = title
