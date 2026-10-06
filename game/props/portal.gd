class_name Portal
extends Area2D
## 出入口節點（PortalData 的實體）：互動或走進去就請求切換區域。原點在底邊中點。
## 玩家從這裡出現時（entry）暫時不觸發，等他離開一次再啟用，避免來回彈跳。
## 缺旗標或沒有目標的門只顯示提示文字，不會切換。

signal used(portal: Portal)

const PROMPT_LOCKED_RADIUS := 56.0
const LOCKED_TOAST_COOLDOWN := 1.2

var data: PortalData
var cell := Vector2i.ZERO

var _player_in_range := false
## false＝剛從這裡出現，玩家離開前不觸發。
var _armed := true
var _time := 0.0
var _toast_left := 0.0
var _prompt: WorldPrompt


func configure(p_data: PortalData, p_cell: Vector2i) -> void:
	data = p_data
	cell = p_cell


func _ready() -> void:
	if data == null:
		push_error("[Portal] 未指定 PortalData，已移除。")
		queue_free()
		return
	for problem in data.validate():
		push_error("[Portal] %s" % problem)
	LightKit.mark_emissive(self)
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = Vector2(data.width, data.height)
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -data.height * 0.5)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = WorldPrompt.new()
	_prompt.text = data.default_prompt()
	_prompt.radius = maxf(PROMPT_LOCKED_RADIUS, data.width * 0.5 + 24.0)
	_prompt.reach_check = func() -> bool: return _player_in_range and _armed and data.mode == PortalData.Mode.INTERACT
	_prompt.offset = Vector2(0, -data.height - 10.0)
	add_child(_prompt)
	if data.style != "road" and data.style != "hidden":
		var light := LightKit.create_point_light(_accent(), 70.0, 0.5, false)
		light.position = Vector2(0, -data.height * 0.5)
		add_child(light)


## 玩家從這個出入口出現：離開一次之前不觸發。
func disarm() -> void:
	_armed = false


func is_armed() -> bool:
	return _armed


## 現在能不能通行（旗標滿足、有目標）。
func is_open() -> bool:
	if data == null or data.is_locked_door():
		return false
	return data.requires_flag == &"" or GameState.has_flag(data.requires_flag)


## 嘗試使用：可通行就發出 used，否則顯示鎖住的提示。回傳是否通行。
func try_use() -> bool:
	if not is_open():
		if _toast_left <= 0.0 and not data.locked_text.is_empty():
			_toast_left = LOCKED_TOAST_COOLDOWN
			EventBus.toast_requested.emit(data.locked_text)
		return false
	used.emit(self)
	return true


func _physics_process(delta: float) -> void:
	_time += delta
	_toast_left = maxf(0.0, _toast_left - delta)
	if _player_in_range and _armed and data.mode == PortalData.Mode.INTERACT \
			and Input.is_action_just_pressed(&"interact") and not get_tree().paused:
		var player := get_tree().get_first_node_in_group(&"player") as Player
		if player != null and not player.is_dead():
			try_use()
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if Pickup.resolve_player(body) == null:
		return
	_player_in_range = true
	if _armed and data.mode == PortalData.Mode.WALK:
		try_use()


func _on_body_exited(body: Node2D) -> void:
	if Pickup.resolve_player(body) == null:
		return
	_player_in_range = false
	_armed = true


func _accent() -> Color:
	if data.is_locked_door() or (data.requires_flag != &"" and not GameState.has_flag(data.requires_flag)):
		return Palette.DANGER.darkened(0.2)
	return Palette.NEON_YELLOW if data.style == "door" else Palette.CYAN


func _draw() -> void:
	if data == null:
		return
	var half := data.width * 0.5
	var top := -float(data.height)
	var accent := _accent()
	match data.style:
		"ladder":
			var rail := Color(accent, 0.9)
			draw_line(Vector2(-half + 3.0, 0.0), Vector2(-half + 3.0, top), rail, 1.5)
			draw_line(Vector2(half - 3.0, 0.0), Vector2(half - 3.0, top), rail, 1.5)
			var y := -4.0
			while y > top:
				draw_line(Vector2(-half + 3.0, y), Vector2(half - 3.0, y), Color(accent, 0.7), 1.0)
				y -= 8.0
		"hidden":
			pass  # 門就是擺設本身，只留互動範圍與提示
		"road":
			# 街口：地面上兩個淡淡的箭頭，沒有門框。
			var pulse := 0.5 + 0.5 * sin(_time * 3.0)
			var color := Color(accent, 0.25 + 0.2 * pulse)
			for i in 2:
				var x := -4.0 + float(i) * 8.0
				draw_polyline(PackedVector2Array([Vector2(x, -10.0), Vector2(x + 4.0, -6.0), Vector2(x, -2.0)]), color, 1.2)
		_:
			var frame := Rect2(-half, top, data.width, data.height)
			draw_rect(frame, Color(0.03, 0.04, 0.06, 0.55))
			draw_rect(frame, LightKit.glow(accent, 1.2), false, 1.5)
			draw_line(Vector2(0.0, top + 3.0), Vector2(0.0, -3.0), Color(accent, 0.25), 1.0)
