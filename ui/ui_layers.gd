class_name UiLayers
extends RefCounted
## 所有 CanvasLayer 的疊放順序集中在這裡（數字越大越上面）。新增畫面先在這裡加一行，不要在各檔案寫死數字。
## 暫停選單高於劇情通訊、章節標題卡與背包：暫停時它們不會蓋在選單上。暫停與背包、過場不會同時開啟。

const POST_PROCESS := 5
const HUD := 10
## 地點標示：在 HUD 之上、死亡畫面與所有選單之下（NE-490），蓋住遊戲的畫面出現時被它們蓋住並藏起來。
const LOCATION_MARKER := 12
const DEATH := 25
const CHAPTER_CARD := 55
## 演出層（地點標示、章末畫面）都在這個群組：截圖與量測工具要乾淨的畫面時，清掉這個群組即可。
const PRESENTATION_GROUP := &"presentation_overlays"
const CUTSCENE := 58
const FRAMING := 59
const DIALOGUE := 60
const INVENTORY := 61
const LOCAL_REPLAY := 62
const PAUSE := 70
const CONTROLLER_NOTICE := 75
const TRANSITION := 100
## 蓋住遊戲的畫面（死亡畫面、結算、存檔與手把斷線的提示…）在顯示時都在這個群組。
## 疊在遊戲上的演出（地點標示）用 gameplay_covered() 判斷要不要藏起來，不逐個畫面檢查。
const COVER_GROUP := &"covers_gameplay"


## 遊戲畫面現在是不是被蓋住：暫停（暫停選單、背包、地圖、圖鑑都會暫停）、通訊顯示中、或任何一個蓋住遊戲的畫面正在顯示。
static func gameplay_covered(tree: SceneTree) -> bool:
	if tree == null:
		return false
	if tree.paused or DialogueLayer.radio_visible():
		return true
	for node in tree.get_nodes_in_group(COVER_GROUP):
		if node is CanvasLayer and (node as CanvasLayer).visible:
			return true
		if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
			return true
	return false


## 截圖與量測工具用：轉場正在進行、或章末畫面的黑幕還在時回傳 true（這時取樣會拿到黑畫面）。
## 用法：while UiLayers.presentation_busy(get_tree()): await get_tree().process_frame
static func presentation_busy(tree: SceneTree) -> bool:
	if tree == null:
		return false
	if Transition.is_active():
		return true
	for node in tree.get_nodes_in_group(PRESENTATION_GROUP):
		if node is ChapterCard:
			return true
	return false
