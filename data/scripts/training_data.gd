class_name TrainingData
extends Resource
## 序章的訓練站（ST-16）：玩家真的做到一個動作才算完成，完成時寫旗標並播放一段劇情。
## 新增一個練習只需要一份 .tres 與一個地圖字元；判定種類由 kind 決定，沒有額外程式。
## 訓練站不會讓玩家死亡、不扣錢、不計死亡次數；訓練器打中玩家只會停機並把生命補回。

enum Kind {
	## 走到這裡（腳底在 reach 範圍內）就完成。
	REACH,
	## 被玩家的子彈打中才完成（近戰打中不算）。
	TARGET,
	## 被玩家的近戰打中才完成（子彈不算）。
	DUMMY,
	## 訓練器：亮燈預告後朝前方出手一次；玩家用格擋擋下才完成，被打中就停機重來。
	TRAINER,
	## 玩家用衝刺穿過這條線才完成（走過去不算）。
	DASH_LINE,
}

@export var id: StringName = &"training"
@export var kind: Kind = Kind.REACH
## 出現在站上方的提示（一句講重點，可用 {shoot}、{melee}、{block}、{dash}、{jump}、{interact}）。
@export var prompt: String = ""
## 這個旗標成立才開始判定（空白＝一開始就可以）；未開始時只畫暗色的器材。
@export var requires_flag: StringName = &""
## 完成時寫入的旗標（必填）。
@export var done_flag: StringName = &""
## 完成時播放的劇情場景（可空白）。
@export var done_scene: StringName = &""
## 訓練器第一次打中玩家時播放的場景（說明停機、怎麼重來），並寫入 fail_flag。
@export var fail_scene: StringName = &""
@export var fail_flag: StringName = &""
## 之後再失誤時的一句提示。
@export var fail_repeat_text: String = ""
## 判定範圍（像素，以站的腳底為中心）：REACH／TRAINER 的有效距離、TARGET／DUMMY 的受擊框大小、DASH_LINE 的高度。
@export var reach: Vector2 = Vector2(40, 64)
## 畫在地圖上的高度（像素）。
@export var height: float = 48.0


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if done_flag == &"":
		problems.append("訓練站 %s 沒有 done_flag，完成後無法記錄" % id)
	if prompt.strip_edges().is_empty():
		problems.append("訓練站 %s 沒有提示文字" % id)
	if reach.x <= 0.0 or reach.y <= 0.0:
		problems.append("訓練站 %s 的 reach 必須大於 0" % id)
	if kind == Kind.TRAINER and (fail_flag == &"" or fail_repeat_text.is_empty()):
		problems.append("訓練器 %s 需要 fail_flag 與 fail_repeat_text" % id)
	return problems
