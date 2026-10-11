class_name BossHoldPoint
extends Node2D
## 頭目戰裡要「站在旁邊按住互動鍵一段時間」的點（第二章：主隔離箱、拔出儲能匣）。
## 規則：玩家在範圍內按住互動鍵 hold 秒就完成；途中放開、離開或受擊都會中斷並歸零（受擊中斷才算「操作被打斷」）。
## 未完成不寫任何東西；完成只發一次 completed。enabled 為 false 時只畫外觀、不出提示。
## 跟著目標節點走時（follow），位置每影格對齊目標（拔頭目背上的儲能匣）。

signal completed
signal interrupted

const RING_RADIUS := 7.0

var hold := 1.5
var reach := Vector2(26, 40)
var prompt_text := ""
## 外觀：box＝畫一個牆上的箱子（隔離箱）；none＝只有進度環（掛在頭目身上時）。
var look := "box"
var enabled := false:
	set(value):
		enabled = value
		_progress = 0.0
		if _prompt != null:
			_prompt.enabled = value
		queue_redraw()
var done := false
var follow: Node2D
var follow_offset := Vector2.ZERO

var _progress := 0.0
var _player: Player
var _prompt: WorldPrompt


func setup(p_hold: float, p_prompt: String, p_look := "box") -> void:
	hold = maxf(0.2, p_hold)
	prompt_text = p_prompt
	look = p_look


func _ready() -> void:
	LightKit.mark_emissive(self)
	if not prompt_text.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = prompt_text
		_prompt.radius = 64.0
		_prompt.reach_check = _in_reach
		_prompt.offset = Vector2(0, -reach.y - 10.0)
		_prompt.enabled = enabled
		add_child(_prompt)
	_bind_player()


func progress() -> float:
	return clampf(_progress / hold, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if is_instance_valid(follow):
		global_position = follow.global_position + follow_offset
	if not enabled or done:
		return
	if not is_instance_valid(_player):
		_bind_player()
	if _in_reach() and Input.is_action_pressed(&"interact") and not GameplayLock.is_locked():
		_progress += delta
		if _progress >= hold:
			done = true
			enabled = false
			Fx.burst(global_position + Vector2(0, -reach.y * 0.5), Palette.WHITE, 12, 120.0, 0.3)
			Sfx.play(&"switch", -2.0)
			completed.emit()
	elif _progress > 0.0:
		_progress = 0.0
	queue_redraw()


func _in_reach() -> bool:
	if not is_instance_valid(_player):
		return false
	# 跟著頭目的點（背上的儲能匣）以頭目的腳底高度判斷，玩家站在旁邊的地上就算到了。
	var ground_y := follow.global_position.y if is_instance_valid(follow) else global_position.y
	var dx := _player.global_position.x - global_position.x
	var dy := _player.global_position.y - ground_y
	return absf(dx) <= reach.x and dy <= 8.0 and dy >= -reach.y


func _bind_player() -> void:
	var target := get_tree().get_first_node_in_group(&"player") as Player if is_inside_tree() else null
	if target == _player:
		return
	if is_instance_valid(_player) and _player.health.damaged.is_connected(_on_player_damaged):
		_player.health.damaged.disconnect(_on_player_damaged)
	_player = target
	if _player != null:
		_player.health.damaged.connect(_on_player_damaged)


## 受擊中斷：進度歸零，提示一次「被打斷了」。
func _on_player_damaged(_info: DamageInfo) -> void:
	if enabled and _progress > 0.0:
		_progress = 0.0
		interrupted.emit()
		EventBus.toast_requested.emit("操作被打斷了")
		queue_redraw()


func _draw() -> void:
	if look == "box":
		# 牆上的隔離箱：深色箱體、上方指示燈（可以操作時亮白、完成後變灰）。
		var body := Rect2(Vector2(-9, -30), Vector2(18, 22))
		draw_rect(body, Color(0.16, 0.17, 0.2))
		draw_rect(body, Color(0.55, 0.58, 0.62), false, 1.0)
		draw_line(Vector2(-5, -20), Vector2(5, -20), Color(0.4, 0.42, 0.46), 2.0)
		var lamp := Color(0.35, 0.35, 0.38) if done else (LightKit.glow(Palette.WHITE, 1.8) if enabled else LightKit.glow(Palette.CYAN, 1.2))
		draw_circle(Vector2(0, -26), 2.0, lamp)
	if enabled and _progress > 0.0:
		var center := Vector2(0, -reach.y - 2.0) if look == "box" else Vector2.ZERO
		draw_arc(center, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * progress(), 24, LightKit.glow(Palette.WHITE, 2.0), 2.0)
	elif enabled and look != "box":
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		draw_arc(Vector2.ZERO, RING_RADIUS + pulse * 2.0, 0.0, TAU, 20, LightKit.glow(Palette.WARNING, 2.6), 1.5)
