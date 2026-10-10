class_name NpcTalk
extends Resource
## 場景人物的一段對話：用哪個劇情場景、什麼條件下使用、說完給什麼。
## 條件由人物資料（NpcData.pick_talk）從清單中挑選：符合條件的最後一段勝出，所以越後面的越優先。

## 台詞所在的劇情場景（data/story/*.json，mode 為 dialogue）。
@export var scene: StringName = &""
## 至少已經談過幾次才會用這一段（0 = 任何時候；1 = 之後再來）。
@export var min_talks: int = 0
## 本輪累計死亡至少幾次才會用這一段（0 = 不限）：人物對死亡的反應。
@export var min_deaths: int = 0
## 這個劇情場景在本輪播過之後才會用這一段（空白 = 不限）。
@export var after_scene: StringName = &""
@export var requires_flag: StringName = &""
@export var unless_flag: StringName = &""
@export var requires_item: StringName = &""
## 目前手上有這件原件才用這一段（交出後不再符合）。
@export var requires_held_item: StringName = &""
## 手上沒有這件原件才用這一段（未取得或已交出）。
@export var unless_held_item: StringName = &""
## 這件原件本輪已交出才用這一段（交付後的回訪）。
@export var requires_transferred_item: StringName = &""
## Investigation scenes can be tracked once; old NPC reward/checkpoint rules stay unchanged.
@export var once: bool = false
@export_group("Reward")
## 說完給的信用點。
@export var credits: int = 0
## 說完給的補給。
@export var consumable: ConsumableData
## 說完給的收集品（文件或錄音，算進收集進度）。
@export var story_item: StoryItemData
## 領取時顯示的提示；空白時依內容自動產生。
@export var reward_text: String = ""


## 交給 StoryRules 判斷的原件條件；只有設定了才建立字典。
func custody_conditions() -> Dictionary:
	if requires_held_item == &"" and unless_held_item == &"" and requires_transferred_item == &"":
		return {}
	return {"requires_held_item": requires_held_item, "unless_held_item": unless_held_item, "requires_transferred_item": requires_transferred_item}


func has_reward() -> bool:
	return credits > 0 or consumable != null or story_item != null


func validate(owner_id: StringName) -> PackedStringArray:
	var problems := PackedStringArray()
	if scene == &"":
		problems.append("人物 %s 有一段對話沒有指定場景" % owner_id)
	if min_talks < 0:
		problems.append("人物 %s 的對話「%s」min_talks 不能為負" % [owner_id, scene])
	if min_deaths < 0:
		problems.append("人物 %s 的對話「%s」min_deaths 不能為負" % [owner_id, scene])
	if credits < 0:
		problems.append("人物 %s 的對話「%s」信用點不能為負" % [owner_id, scene])

	return problems
