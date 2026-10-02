class_name StoryItemData
extends Resource
## 劇情道具定義（照片、晶片、資料碎片…）。新增道具只需在 data/story_items/ 建立新的 .tres 並設定取得時機。

## 取得時機。
enum Trigger {
	## 新的一輪開始就持有。
	RUN_START,
	## 指定的劇情場景播完時取得。
	SCENE_FINISHED,
	## 擊敗頭目時取得。
	BOSS_DEFEATED,
	## 不自動取得，由程式呼叫 StoryItems.acquire()（例如關卡拾取）。
	MANUAL,
}

@export var id: StringName = &"item"
@export var display_name: String = "道具"
## 一兩句話的背景說明（背包顯示）。
@export_multiline var description: String = ""
@export var color: Color = Color.WHITE
## 背包的排列順序（小的在前）。
@export var order: int = 0
@export_group("Acquire")
@export var trigger: Trigger = Trigger.MANUAL
## trigger 為 SCENE_FINISHED 時，要等哪個劇情場景（data/story/*.json 的場景 id）播完。
@export var trigger_scene: StringName = &""
@export_group("Art")
## 背包像素圖示的檔名（art/items/icons/<icon>.png）。
@export var icon: String = ""


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("劇情道具缺少 id")
	if display_name.is_empty():
		problems.append("%s 缺少名稱" % id)
	if description.is_empty():
		problems.append("%s 缺少說明" % id)
	if trigger == Trigger.SCENE_FINISHED and trigger_scene == &"":
		problems.append("%s 的取得時機是劇情場景結束，但沒有指定 trigger_scene" % id)
	return problems
