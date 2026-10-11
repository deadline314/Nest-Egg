class_name DialogueMaterial
extends RefCounted
## 純外觀：不接收 Story 結果、旗標、動作或 callback。實心像素材質共用既有 ChamferBox。

static func panel(kind: String) -> ChamferBox:
	var body := UiTheme.PANEL_BODY
	var edge := UiTheme.PANEL_EDGE
	if kind == "object":
		body = Color("292c30")
		edge = Color("807967")
	elif kind == "radio":
		body = Color("12212b")
		edge = Color("466474")
	var box := ChamferBox.make(body, edge, 4, 2)
	box.margins(10, 6, 10, 6)
	return box


static func nameplate(kind: String) -> ChamferBox:
	var edge := Color("807967") if kind == "object" else Color("4a8193")
	var box := ChamferBox.make(Color("192e39") if kind != "object" else Color("373831"), edge, 3)
	box.corners = ChamferBox.Corner.TOP
	box.margins(6, 2, 6, 2)
	return box


## 名牌只寫講者（閱讀時是物件名稱）；不加「交談／通訊／閱讀」字樣，種類由面板材質與顏色區分。
static func header(_kind: String, speaker: String) -> String:
	return speaker
