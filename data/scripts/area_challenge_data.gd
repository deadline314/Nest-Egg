class_name AreaChallengeData
extends Resource
## 區域裡的可選小挑戰（NE-410）：給同一段路第二種玩法，完成時給一次信用點。
## 掛在 LevelData.challenges；新增一個只要一份資料，不用改程式。進區域時提示一次，完成後不再出現。

enum Kind {
	## 用玩家觸發的環境機關（落下的貨箱、通電的積水……）擊倒 target 名敵人。
	ENVIRONMENT_KILLS,
}

@export var id: StringName = &""
@export var kind: Kind = Kind.ENVIRONMENT_KILLS
@export_range(1, 20) var target: int = 2
@export_range(1, 500) var reward_credits: int = 30
## 一句講清楚要做什麼（中文）；其他語言寫在 localized_goals（"ja"、"en"）。
@export var goal: String = ""
@export var localized_goals: Dictionary[String, String] = {}


func goal_for(language: String) -> String:
	return StoryLocale.optional_text(localized_goals, language, goal)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("區域挑戰缺少 id")
	if target < 1 or reward_credits < 1:
		problems.append("區域挑戰 %s 的目標數或獎勵無效" % id)
	if goal.strip_edges().is_empty():
		problems.append("區域挑戰 %s 缺少說明" % id)
	for language in ["ja", "en"]:
		if str(localized_goals.get(language, "")).strip_edges().is_empty():
			problems.append("區域挑戰 %s 的說明缺少 %s 譯文" % [id, language])
	return problems
