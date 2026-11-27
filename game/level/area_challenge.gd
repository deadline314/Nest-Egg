class_name AreaChallenge
extends Node
## 區域可選小挑戰的進度（NE-410）：進區域時提示一次要做什麼，達成時給信用點並提示，之後不再出現。
## 進度跟著檢查點保存（WorldState）：死了回到檢查點時，進度與信用點一起回到存檔那一刻，不會重複領。

signal completed(challenge: AreaChallenge)

const GROUP := &"area_challenges"
## 進區域後等章節標題卡淡出再提示（秒）。
const INTRO_DELAY := 4.2
const INTRO_TEXT := {"zh": "區域挑戰：%s", "ja": "エリアチャレンジ：%s", "en": "Area challenge: %s"}
const DONE_TEXT := {"zh": "挑戰完成：%s（+%d 信用點）", "ja": "チャレンジ達成：%s（+%d クレジット）", "en": "Challenge complete: %s (+%d credits)"}

var data: AreaChallengeData
var progress := 0
var done := false
var _intro_in := INTRO_DELAY


func configure(p_data: AreaChallengeData) -> void:
	data = p_data


func _ready() -> void:
	if data == null:
		push_error("[AreaChallenge] 未指定 AreaChallengeData，已移除。")
		queue_free()
		return
	add_to_group(GROUP)
	add_to_group(WorldState.GROUP)
	match data.kind:
		AreaChallengeData.Kind.ENVIRONMENT_KILLS:
			EventBus.enemy_killed_by_environment.connect(_on_environment_kill)


func _process(delta: float) -> void:
	_intro_in -= delta
	if _intro_in <= 0.0:
		set_process(false)
		if not done:
			EventBus.toast_requested.emit(_text(INTRO_TEXT) % data.goal_for(Story.language))


func _on_environment_kill(_enemy_id: StringName, _source_id: StringName) -> void:
	add_progress(1)


## 加進度；達成時給獎勵。已完成就不做事；回傳這一次有沒有完成。
func add_progress(amount: int) -> bool:
	if done or amount <= 0:
		return false
	progress = mini(progress + amount, data.target)
	if progress < data.target:
		return false
	done = true
	var gained := Progression.add_credits(data.reward_credits)
	EventBus.toast_requested.emit(_text(DONE_TEXT) % [data.goal_for(Story.language), gained])
	Sfx.play(&"pickup", -4.0)
	completed.emit(self)
	return true


func _text(table: Dictionary) -> String:
	return table.get(Story.language, table["zh"])


# 檢查點狀態（WorldState）。
func state_key() -> String:
	return "challenge@%s" % data.id


func capture_state() -> Variant:
	return {"progress": progress, "done": done}


func restore_state(saved: Variant) -> void:
	if saved is Dictionary:
		progress = clampi(int(saved.get("progress", 0)), 0, data.target)
		done = bool(saved.get("done", false))
