class_name UiLayers
extends RefCounted
## 所有 CanvasLayer 的疊放順序集中在這裡（數字越大越上面）。新增畫面先在這裡加一行，不要在各檔案寫死數字。
## 暫停選單高於劇情通訊、章節標題卡與背包：暫停時它們不會蓋在選單上。暫停與背包、過場不會同時開啟。

const POST_PROCESS := 5
const HUD := 10
const DEATH := 25
const CHAPTER_CARD := 55
const CUTSCENE := 58
const FRAMING := 59
const DIALOGUE := 60
const INVENTORY := 61
const PAUSE := 70
const TRANSITION := 100
