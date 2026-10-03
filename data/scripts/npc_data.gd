class_name NpcData
extends Resource
## 場景人物定義：站在關卡裡，玩家靠近按互動鍵就會說話。新增人物只需要一份 .tres 與一個地圖字元（LevelData.legend）。
## 台詞放在章節劇本（data/story/*.json，mode 為 dialogue），這裡只決定「什麼時候說哪一段、說完給什麼」。

## 人物（站著的人）或可調查物（牆上的刻痕、告示…，只畫一個記號，沒有外觀）。
enum Kind { PERSON, OBJECT }

@export var id: StringName = &"npc"
@export var kind: Kind = Kind.PERSON
@export var display_name: String = "路人"
## 講者 id（章節劇本 speakers）：沒有骨架外觀時，用這位講者的頭像做剪影。
@export var speaker: String = ""
## 骨架外觀 id（art/characters/<id>/）。找不到時自動退回頭像剪影。
@export var rig_id: String = ""
## 站姿（CutsceneActor.POSES 之一），例如受傷的人用 crouch。
@export var pose: StringName = &"idle"
## 專屬工作循環（art/rigs/npc_animations.json 的 loops，例如 stir、hammer、tablet；空白＝只有待機呼吸）與幅度倍率。
@export var loop: StringName = &""
@export var loop_scale: float = 1.0
## 原本面向（-1 左、1 右）；玩家靠近時會轉向玩家。
@export var facing: int = -1
## 互動提示（一句重點，可用 {interact}）；空白時用「{interact} 和<名字>說話」。
@export var prompt: String = ""
## 對話清單（見 NpcTalk）。
@export var talks: Array[NpcTalk] = []


func prompt_text() -> String:
	if not prompt.is_empty():
		return prompt
	return "{interact} 看一下%s" % display_name if kind == Kind.OBJECT else "{interact} 和%s說話" % display_name


## 依已談過的次數與劇情進度挑出這次要說的一段（符合條件的最後一段）。回傳在 talks 中的位置，沒有可用的回傳 -1。
## seen_scene：回傳某個劇情場景本輪是否播過。
func pick_talk(talk_count: int, seen_scene: Callable) -> int:
	var picked := -1
	for index in talks.size():
		var talk := talks[index]
		if talk == null or talk.min_talks > talk_count:
			continue
		if talk.after_scene != &"" and not bool(seen_scene.call(talk.after_scene)):
			continue
		picked = index
	return picked


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("場景人物缺少 id")
	if display_name.is_empty():
		problems.append("人物 %s 缺少名稱" % id)
	if talks.is_empty():
		problems.append("人物 %s 沒有任何對話" % id)
	if facing != -1 and facing != 1:
		problems.append("人物 %s 的面向必須是 -1 或 1" % id)
	if not CutsceneActor.POSES.has(String(pose)):
		problems.append("人物 %s 的站姿「%s」不存在" % [id, pose])
	if loop != &"" and not NpcAnimator.loop_names().has(String(loop)):
		problems.append("人物 %s 的工作循環「%s」不存在（art/rigs/npc_animations.json 的 loops）" % [id, loop])
	if loop_scale <= 0.0 or loop_scale > 3.0:
		problems.append("人物 %s 的 loop_scale 必須在 0~3 之間" % id)
	for talk in talks:
		if talk == null:
			problems.append("人物 %s 的對話清單有空項目" % id)
		else:
			problems.append_array(talk.validate(id))
	return problems
