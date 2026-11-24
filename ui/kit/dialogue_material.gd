class_name DialogueMaterial
extends RefCounted
## 純外觀：不接收 Story 結果、旗標、動作或 callback。實心像素材質共用既有 ChamferBox。

static func panel(kind: String) -> ChamferBox:
	var reading := kind == "object"
	var body := Color("242429fa") if reading else UiTheme.PANEL_BODY
	var signal_color := Color("d4ba93") if reading else Palette.CYAN
	var box := UiTheme.surface(signal_color, body, 6)
	box.margins(10, 6, 10, 6)
	return box


static func portrait_backing() -> ChamferBox:
	return UiTheme.surface(Color.TRANSPARENT, Color("1a2730"), 3).margins(2, 2, 2, 2)


## 名牌只寫講者（閱讀時是物件名稱）；不加「交談／通訊／閱讀」字樣，種類由面板材質與顏色區分。
static func header(_kind: String, speaker: String) -> String:
	return speaker
