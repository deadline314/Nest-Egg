class_name AreaChallenge
extends Node
## 區域可選小挑戰的進度（NE-410）：進區域時提示一次要做什麼，達成時給信用點並提示，之後不再出現。
## 進度跟著檢查點保存（WorldState）：死了回到檢查點時，進度與信用點一起回到存檔那一刻，不會重複領。
## 「限時抵達」（NE-418）的計時不存：回到檢查點就回到還沒開始，越過起點重新計時。

signal completed(challenge: AreaChallenge)

const GROUP := &"area_challenges"
## 進區域後等章節標題卡淡出再提示（秒）。
const INTRO_DELAY := 4.2
const INTRO_TEXT := {"zh": "區域挑戰：%s", "ja": "エリアチャレンジ：%s", "en": "Area challenge: %s"}
const DONE_TEXT := {"zh": "挑戰完成：%s（+%d 信用點）", "ja": "チャレンジ達成：%s（+%d クレジット）", "en": "Challenge complete: %s (+%d credits)"}
const FAIL_TEXT := {"zh": "挑戰失敗：被發現了。回到檢查點可以再試一次。", "ja": "チャレンジ失敗：見つかった。チェックポイントから再挑戦できます。", "en": "Challenge failed: you were spotted. Retry from the checkpoint."}
const DONE_TIMED_TEXT := {"zh": "挑戰完成：用了 %.1f 秒（+%d 信用點）", "ja": "チャレンジ達成：%.1f 秒（+%d クレジット）", "en": "Challenge complete in %.1f s (+%d credits)"}
const TIMEOUT_TEXT := {"zh": "挑戰失敗：時間到。回到檢查點可以再試一次。", "ja": "チャレンジ失敗：時間切れ。チェックポイントから再挑戦できます。", "en": "Challenge failed: out of time. Retry from the checkpoint."}
const START_TEXT := {"zh": "計時開始：%d 秒", "ja": "計測開始：%d 秒", "en": "Timer started: %d s"}
## 限時中跟著主角的倒數（世界裡的全像字幕，不是 HUD 方框）：位置在頭頂上方。
const CLOCK_TEXT := {"zh": "剩 %d 秒", "ja": "残り %d 秒", "en": "%d s left"}
const CLOCK_OFFSET := Vector2(0, -100)  # 在主角頭頂的生命與彈藥列上面，不互相推擠
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
## 「限時抵達」剩下的秒數；負數＝還沒開始。
var time_left := -1.0
var _clock_anchor: Node2D
var _clock: WorldPrompt
var _clock_shown := -1


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
	set_physics_process(_watches())


func _process(delta: float) -> void:
	_intro_in -= delta
	if _intro_in <= 0.0:
		set_process(false)
		if not done and not failed:
			EventBus.toast_requested.emit(_text(INTRO_TEXT) % data.goal_for(Story.language))


## 這一種挑戰要不要每一格看玩家或敵人。
func _watches() -> bool:
	return data.kind in [AreaChallengeData.Kind.UNSEEN_PASS, AreaChallengeData.Kind.TIMED_REACH] and not done and not failed


func _physics_process(delta: float) -> void:
	if done or failed:
		_hide_clock()
		set_physics_process(false)
		return
	if data.kind == AreaChallengeData.Kind.TIMED_REACH:
		_tick_timer(delta)
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


## 限時抵達：越過起點開始倒數，倒數中走到終點就完成，時間到就失敗。
func _tick_timer(delta: float) -> void:
	var player := _player_ref.get_player(get_tree())
	if player == null:
		return
	var x := player.global_position.x
	if time_left < 0.0:
		var waiting := _intro_in > 0.0 if data.start_cell_x < 0 else x < (float(data.start_cell_x) + 0.5) * _tile
		if waiting:
			return
		time_left = data.time_limit
		EventBus.toast_requested.emit(_text(START_TEXT) % roundi(data.time_limit))
		_show_clock()
	if x >= (float(data.finish_cell_x) + 0.5) * _tile:
		add_progress(data.target)
		return
	time_left = maxf(0.0, time_left - delta)
	_clock_anchor.global_position = player.global_position
	var shown := ceili(time_left)
	if shown != _clock_shown:
		_clock_shown = shown
		_clock.text = _text(CLOCK_TEXT) % shown
	if time_left <= 0.0:
		fail(TIMEOUT_TEXT)


func _show_clock() -> void:
	if _clock_anchor != null:
		return
	_clock_anchor = Node2D.new()
	_clock_anchor.name = "ChallengeClock"
	add_child(_clock_anchor)
	_clock = WorldPrompt.new()
	_clock.offset = CLOCK_OFFSET
	_clock.reach_check = func() -> bool: return time_left >= 0.0 and not done and not failed
	_clock_anchor.add_child(_clock)
	_clock_shown = -1


func _hide_clock() -> void:
	if _clock_anchor != null:
		_clock_anchor.queue_free()
		_clock_anchor = null
		_clock = null


## 這一輪的挑戰失敗（被發現、時間到；回到更早的檢查點會重置）。
func fail(text: Dictionary = FAIL_TEXT) -> void:
	if done or failed:
		return
	failed = true
	_hide_clock()
	EventBus.toast_requested.emit(_text(text))


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
	if data.kind == AreaChallengeData.Kind.TIMED_REACH and time_left >= 0.0:
		EventBus.toast_requested.emit(_text(DONE_TIMED_TEXT) % [data.time_limit - time_left, gained])
	else:
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
		time_left = -1.0
		_hide_clock()
		set_physics_process(_watches())
