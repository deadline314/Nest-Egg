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

## 種類：關鍵道具（照片、晶片…，劇情自動取得）、文件與錄音（散落在關卡裡的背景故事，每章有固定數量，算進收集進度）。
enum Category { KEY_ITEM, DOCUMENT, RECORDING }

@export var id: StringName = &"item"
@export var display_name: String = "道具"
## 一兩句話的背景說明（背包顯示）。
@export_multiline var description: String = ""
@export var color: Color = Color.WHITE
@export var category: Category = Category.KEY_ITEM
## 背包的排列順序（小的在前）。
@export var order: int = 0
@export_group("Collectible")
## 文件與錄音屬於哪一章（章節 id，與 data/story/chapter_XX.json 的 chapter.id 相同）；用來計算每章的收集進度。
@export var chapter: StringName = &""
## 文件的全文或錄音的逐字稿（背包閱讀用）；空白時只顯示 description。
@export_multiline var body: String = ""
## 撿到時播放的通訊場景（例如航的語音留言），空白代表不播。
@export var play_scene: StringName = &""
@export_group("Acquire")
@export var trigger: Trigger = Trigger.MANUAL
## trigger 為 SCENE_FINISHED 時，要等哪個劇情場景（data/story/*.json 的場景 id）播完。
@export var trigger_scene: StringName = &""
## 第一次取得時寫入的劇情旗標（例如拿到資料盤）；交出後旗標仍在，代表「曾經取得」。
@export var acquire_flag: StringName = &""
@export_group("Art")
## 背包像素圖示的檔名（art/items/icons/<icon>.png）。
@export var icon: String = ""


## 是否算進「每章收集進度」。
## 內文長度上限：背包詳情面板不捲動，超過會被裁掉。
const MAX_BODY_LENGTH := 220


func is_collectible() -> bool:
	return category != Category.KEY_ITEM


## 依目前的劇本語言取名稱、說明與內文（日文與英文在 data/story_items/i18n.json，缺譯退回英文再退回中文）。
func title_text() -> String:
	return StoryItemText.lookup(id, "display_name", display_name, Story.language)


func description_text() -> String:
	return StoryItemText.lookup(id, "description", description, Story.language)


func body_text() -> String:
	return StoryItemText.lookup(id, "body", body, Story.language)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("劇情道具缺少 id")
	if display_name.is_empty():
		problems.append("%s 缺少名稱" % id)
	if description.is_empty():
		problems.append("%s 缺少說明" % id)
	if is_collectible():
		if chapter == &"":
			problems.append("%s 是文件或錄音，必須指定 chapter" % id)
		if body.is_empty():
			problems.append("%s 是文件或錄音，必須有內文 body" % id)
		if body.length() > MAX_BODY_LENGTH:
			problems.append("%s 的內文有 %d 字，超過上限 %d 字（背包放不下）" % [id, body.length(), MAX_BODY_LENGTH])
		if trigger != Trigger.MANUAL:
			problems.append("%s 是文件或錄音，取得時機必須是 MANUAL（在關卡裡撿）" % id)
	if trigger == Trigger.SCENE_FINISHED and trigger_scene == &"":
		problems.append("%s 的取得時機是劇情場景結束，但沒有指定 trigger_scene" % id)
	return problems
