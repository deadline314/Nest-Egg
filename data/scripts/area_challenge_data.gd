class_name AreaChallengeData
extends Resource
## 區域裡的可選小挑戰（NE-410）：給同一段路第二種玩法，完成時給一次信用點。
## 掛在 LevelData.challenges；新增一個只要一份資料，不用改程式。進區域時提示一次，完成後不再出現。

enum Kind {
	## 用玩家觸發的環境機關（落下的貨箱、通電的積水……）擊倒 target 名敵人。
	ENVIRONMENT_KILLS,
	## 走到 finish_cell_x 那一格之前，finish 線附近的敵人沒有一個發現玩家（NE-411）。被發現就算失敗，回檢查點可以重來。
	UNSEEN_PASS,
	## 越過 start_cell_x 開始計時，time_limit 秒內走到 finish_cell_x（NE-418）。時間到就算失敗，回檢查點可以重來。
	TIMED_REACH,
}

@export var id: StringName = &""
@export var kind: Kind = Kind.ENVIRONMENT_KILLS
@export_range(1, 20) var target: int = 2
@export_range(1, 500) var reward_credits: int = 30
## UNSEEN_PASS、TIMED_REACH 的終點格（整個區域的 x）；UNSEEN_PASS 只看終點右邊 WATCH_MARGIN 以內的敵人。
@export var finish_cell_x: int = -1
## TIMED_REACH：越過這一格開始計時（-1＝提示出現時就開始），以及限時幾秒。
@export var start_cell_x: int = -1
@export_range(5.0, 600.0, 0.5) var time_limit: float = 30.0
## 一句講清楚要做什麼（中文）；其他語言寫在 localized_goals（"ja"、"en"）。
@export var goal: String = ""
@export var localized_goals: Dictionary[String, String] = {}
## 完成時播的一句反應（劇本場景 id：附近的人冒一句氣泡，或燈在通訊裡說一句）；空白＝不播。不寫旗標。
@export var done_scene: StringName = &""


func goal_for(language: String) -> String:
	return StoryLocale.optional_text(localized_goals, language, goal)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("區域挑戰缺少 id")
	if target < 1 or reward_credits < 1:
		problems.append("區域挑戰 %s 的目標數或獎勵無效" % id)
	if kind == Kind.UNSEEN_PASS and finish_cell_x <= 0:
		problems.append("區域挑戰 %s 是「不被發現」但沒有終點格" % id)
	if kind == Kind.TIMED_REACH and (finish_cell_x <= start_cell_x or finish_cell_x <= 0):
		problems.append("區域挑戰 %s 是「限時抵達」但終點格（%d）沒有在起點格（%d）右邊" % [id, finish_cell_x, start_cell_x])
	if kind == Kind.TIMED_REACH and time_limit < 5.0:
		problems.append("區域挑戰 %s 的限時太短（%.1f 秒）" % [id, time_limit])
	if goal.strip_edges().is_empty():
		problems.append("區域挑戰 %s 缺少說明" % id)
	for language in ["ja", "en"]:
		if str(localized_goals.get(language, "")).strip_edges().is_empty():
			problems.append("區域挑戰 %s 的說明缺少 %s 譯文" % [id, language])
	if done_scene != &"" and not Story.has_scene(done_scene):
		problems.append("區域挑戰 %s 的完成反應場景 %s 不存在" % [id, done_scene])
	return problems
