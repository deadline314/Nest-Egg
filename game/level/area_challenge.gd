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
const FAIL_TEXT := {"zh": "挑戰失敗：被發現了。回到檢查點可以再試一次。", "ja": "チャレンジ失敗：見つかった。チェックポイントから再挑戦できます。", "en": "Challenge failed: you were spotted. Retry from the checkpoint."}
## 「不被發現」只看終點右邊這麼遠以內的敵人（像素）；多久檢查一次（秒）。
const WATCH_MARGIN := 160.0
const WATCH_EVERY := 0.2

var data: AreaChallengeData
var progress := 0
var done := false
## 「不被發現」被發現了；回到比這更早的檢查點會重置。
var failed := false
var _intro_in := INTRO_DELAY
var _tile := 16.0
var _watch_in := 0.0
var _player_ref := PlayerRef.new()


func configure(p_data: AreaChallengeData, tile_size := 16) -> void:
	data = p_data
	_tile = float(tile_size)


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
		AreaChallengeData.Kind.UNSEEN_PASS:
			set_physics_process(true)
	if data.kind != AreaChallengeData.Kind.UNSEEN_PASS:
		set_physics_process(false)


func _process(delta: float) -> void:
	_intro_in -= delta
	if _intro_in <= 0.0:
		set_process(false)
		if not done and not failed:
			EventBus.toast_requested.emit(_text(INTRO_TEXT) % data.goal_for(Story.language))


func _physics_process(delta: float) -> void:
	if done or failed:
		set_physics_process(false)
		return
	_watch_in -= delta
	if _watch_in > 0.0:
		return
	_watch_in = WATCH_EVERY
	var finish_x := (float(data.finish_cell_x) + 0.5) * _tile
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.global_position.x <= finish_x + WATCH_MARGIN and enemy.is_engaged():
			fail()
			return
	var player := _player_ref.get_player(get_tree())
	if player != null and player.global_position.x >= finish_x:
		add_progress(data.target)


## 被發現：這一輪的挑戰失敗（回到更早的檢查點會重置）。
func fail() -> void:
	if done or failed:
		return
	failed = true
	EventBus.toast_requested.emit(_text(FAIL_TEXT))


func _on_environment_kill(_enemy_id: StringName, _source_id: StringName) -> void:
	add_progress(1)


## 加進度；達成時給獎勵。已完成就不做事；回傳這一次有沒有完成。
func add_progress(amount: int) -> bool:
	if done or failed or amount <= 0:
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
	return {"progress": progress, "done": done, "failed": failed}


func restore_state(saved: Variant) -> void:
	if saved is Dictionary:
		progress = clampi(int(saved.get("progress", 0)), 0, data.target)
		done = bool(saved.get("done", false))
		failed = bool(saved.get("failed", false))
		set_physics_process(data.kind == AreaChallengeData.Kind.UNSEEN_PASS and not done and not failed)
